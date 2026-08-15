class_name AudioSynthesizer
extends Node

## Procedurally synthesizes every sound effect at startup (16-bit PCM into
## AudioStreamWAV — no external audio assets) and offers static playback
## helpers. Must be the FIRST child of Main so `instance` exists before the
## mansion generates and valves/clocks ask for loops.

static var instance: AudioSynthesizer

const SAMPLE_RATE := 44100

var _streams := {}


func _ready() -> void:
	instance = self
	_setup_reverb_bus()
	_streams["plug"] = _gen_plug()
	_streams["heartbeat"] = _gen_heartbeat()
	_streams["ratchet"] = _gen_ratchet()
	_streams["tick"] = _gen_tick()
	_streams["chime"] = _gen_chime()
	_streams["steam"] = _gen_steam()
	# Footsteps: four surfaces x three takes each, so consecutive steps
	# never repeat a sample.
	for v in 3:
		_streams["step_wood_%d" % v] = _gen_step_wood()
		_streams["step_stone_%d" % v] = _gen_step_stone()
		_streams["step_gravel_%d" % v] = _gen_step_gravel()
		_streams["step_grass_%d" % v] = _gen_step_grass()
	_streams["wind"] = _gen_wind()
	_streams["jazz_ambient"] = _gen_jazz_ambient()
	_streams["fire_crackle"] = _gen_fire_crackle()
	_streams["zap"] = _gen_zap()
	_streams["power_up"] = _gen_power_up()


func _exit_tree() -> void:
	if instance == self:
		instance = null


## One shared "MansionReverb" bus: subtle room reverb so hisses, ticks,
## and footsteps resonate down the hallways. Created once per process.
static func _setup_reverb_bus() -> void:
	if AudioServer.get_bus_index("MansionReverb") != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "MansionReverb")
	AudioServer.set_bus_send(idx, "Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.7
	reverb.damping = 0.6
	reverb.wet = 0.14
	reverb.dry = 0.9
	AudioServer.add_bus_effect(idx, reverb)


## Positional one-shot; the temporary player frees itself when done.
## `dry` skips the mansion reverb bus (outdoor sounds).
static func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, dry := false) -> void:
	if instance == null or not instance._streams.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = instance._streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.bus = "Master" if dry else "MansionReverb"
	instance.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Non-positional UI one-shot; keeps playing while the tree is paused
## (menus and the wiring minigame pause the game).
static func play_ui(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if instance == null or not instance._streams.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.stream = instance._streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	instance.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Looping non-positional ambience (e.g. the menu's wind bed).
static func create_ui_loop(sound: String, volume_db := 0.0) -> AudioStreamPlayer:
	if instance == null or not instance._streams.has(sound):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = instance._streams[sound]
	p.volume_db = volume_db
	p.autoplay = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	instance.add_child(p)
	return p


## Looping positional emitter parented to `parent` (e.g. valve steam hiss).
static func create_loop(sound: String, parent: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	if instance == null or not instance._streams.has(sound):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = instance._streams[sound]
	p.volume_db = volume_db
	p.autoplay = true
	p.bus = "MansionReverb"
	parent.add_child(p)
	return p


# --- Synthesis -----------------------------------------------------------


static func _make_wav(samples: PackedFloat32Array, looped := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## Wire plug: low thud + electric arc buzz + crackle.
static func _gen_plug() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var thud := sin(TAU * 85.0 * t) * exp(-t * 40.0) * 0.9
		var arc := 0.0
		if t > 0.02:
			arc = signf(sin(TAU * 2900.0 * t + 3.0 * sin(TAU * 47.0 * t))) * exp(-t * 16.0) * 0.1
		var crackle := (randf() * 2.0 - 1.0) * exp(-t * 28.0) * 0.12
		s[i] = thud + arc + crackle
	return _make_wav(s)


## Electric short: harsh buzz sweeping down, with arc crackle — wrong wire.
static func _gen_zap() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var freq := 640.0 - t * 700.0  # falling pitch = power draining away
		var buzz := signf(sin(TAU * freq * t)) * 0.35
		var gate := 0.5 + 0.5 * signf(sin(TAU * 55.0 * t))  # mains-hum stutter
		var crackle := (randf() * 2.0 - 1.0) * exp(-t * 9.0) * 0.3
		s[i] = (buzz * gate + crackle) * exp(-t * 6.5) * 0.85
	return _make_wav(s)


## Power-up: low hum swelling and rising as the mansion's grid wakes.
static func _gen_power_up() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 1.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var freq := 70.0 + 90.0 * minf(t / 1.1, 1.0)  # 70 Hz -> 160 Hz sweep
		phase += TAU * freq / SAMPLE_RATE
		var v := sin(phase) * 0.5 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.1
		var swell := minf(t / 0.5, 1.0) * exp(-maxf(t - 1.1, 0.0) * 7.0)
		var sparkle := (randf() * 2.0 - 1.0) * 0.04 * swell
		s[i] = (v * swell + sparkle) * 0.8
	return _make_wav(s)


## Brass ratchet: one sharp mechanical click.
static func _gen_ratchet() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.035)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var noise := randf() * 2.0 - 1.0
		var hp := noise - prev  # crude high-pass for metallic snap
		prev = noise
		s[i] = hp * exp(-t * 220.0) * 0.8 + sin(TAU * 1400.0 * t) * exp(-t * 300.0) * 0.3
	return _make_wav(s)


## Clock tick / door latch: woody knock with a bright top.
static func _gen_tick() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.09)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		s[i] = sin(TAU * 1100.0 * t) * exp(-t * 90.0) * 0.4 + sin(TAU * 190.0 * t) * exp(-t * 55.0) * 0.5
	return _make_wav(s)


## Grandfather clock chime: inharmonic bell partials, long decay.
static func _gen_chime() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 2.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var f := 262.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := sin(TAU * f * t) * 0.38
		v += sin(TAU * f * 2.76 * t) * 0.22 * exp(-t * 1.4)
		v += sin(TAU * f * 5.4 * t) * 0.1 * exp(-t * 2.6)
		v += sin(TAU * (f + 1.7) * t) * 0.12
		s[i] = v * exp(-t * 1.6)
	return _make_wav(s)


## Steam hiss: looping low-passed noise with a slow pressure wobble.
static func _gen_steam() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 1.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += 0.22 * ((randf() * 2.0 - 1.0) - lp)
		var wobble := 0.75 + 0.25 * sin(TAU * t / 1.4 * 2.0)  # loop-aligned
		s[i] = lp * wobble * 0.75
	return _make_wav(s, true)


## Sub-bass heartbeat thump for the countdown tension layer.
static func _gen_heartbeat() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var thump := sin(TAU * 52.0 * t) * exp(-t * 22.0)
		var second := 0.0
		if t > 0.12:
			second = sin(TAU * 48.0 * (t - 0.12)) * exp(-(t - 0.12) * 26.0) * 0.6
		s[i] = (thump + second) * 0.9
	return _make_wav(s)


## Distant wind with faint rain patter: looping, heavily low-passed noise
## with a slow swell plus sparse high-frequency droplets.
static func _gen_wind() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 4.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var drop := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += 0.03 * ((randf() * 2.0 - 1.0) - lp)
		var swell := 0.6 + 0.4 * sin(TAU * t / 4.0)  # loop-aligned
		if randf() < 0.00012:
			drop = 0.5
		drop *= 0.9985
		var patter := (randf() * 2.0 - 1.0) * drop * 0.25
		s[i] = lp * swell * 0.9 + patter
	return _make_wav(s, true)


# --- Footsteps -----------------------------------------------------------
# Each surface is a physically-flavored layering: a body "thud" (the heel
# landing), a surface "voice" (a resonant filter ringing at the material's
# character frequency), and surface texture (creak, crunch, swish).


## Two-pole resonator: rings input noise at `freq_hz` with sharpness `r`
## (0.9 loose .. 0.99 bell-like). Returns the filtered array.
static func _resonate(input: PackedFloat32Array, freq_hz: float, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(input.size())
	var w := TAU * freq_hz / SAMPLE_RATE
	var a1 := 2.0 * r * cos(w)
	var a2 := -r * r
	var y1 := 0.0
	var y2 := 0.0
	for i in input.size():
		var y := input[i] + a1 * y1 + a2 * y2
		out[i] = y
		y2 = y1
		y1 = y
	return out


static func _noise_burst(n: int, decay: float, gain: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * decay) * gain
	return s


## Hardwood floor: a hollow low knock with a soft board creak on top.
static func _gen_step_wood() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var knock := _resonate(_noise_burst(n, 70.0, 0.05), randf_range(520.0, 680.0), 0.975)
	var body := _resonate(_noise_burst(n, 40.0, 0.06), randf_range(140.0, 180.0), 0.985)
	var creak_hz := randf_range(1500.0, 2200.0)
	var creak_gain := 0.05 if randf() < 0.6 else 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var thud := sin(TAU * 105.0 * t) * exp(-t * 34.0) * 0.55
		var creak := sin(TAU * creak_hz * t + 4.0 * sin(TAU * 60.0 * t)) * exp(-t * 55.0) * creak_gain
		s[i] = thud + knock[i] * 3.0 + body[i] * 1.6 + creak
	return _make_wav(_normalize(s, 0.8))


## Stone / cobble / concrete: a hard, short click with a bright ring.
static func _gen_step_stone() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.11)
	var s := PackedFloat32Array()
	s.resize(n)
	var ring := _resonate(_noise_burst(n, 110.0, 0.04), randf_range(1900.0, 2600.0), 0.965)
	var scrape := _noise_burst(n, 60.0, 0.12)
	var prev := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var hp := scrape[i] - prev  # high-pass: gritty scrape, no low mud
		prev = scrape[i]
		var thud := sin(TAU * 170.0 * t) * exp(-t * 60.0) * 0.35
		s[i] = thud + ring[i] * 2.5 + hp * 1.4
	return _make_wav(_normalize(s, 0.75))


## Gravel: a cluster of tiny stone-on-stone ticks under a crunch.
static func _gen_step_gravel() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.2)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var spike := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		# Dense micro-impacts early, thinning out as the foot settles.
		if randf() < 0.05 * exp(-t * 9.0):
			spike = randf_range(0.5, 1.0)
		spike *= 0.93
		raw[i] = (randf() * 2.0 - 1.0) * (0.03 + spike) * exp(-t * 14.0)
	var mid := _resonate(raw, randf_range(1200.0, 1700.0), 0.9)
	var hi := _resonate(raw, randf_range(3200.0, 4200.0), 0.85)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		s[i] = mid[i] * 1.2 + hi[i] * 0.6 + raw[i] * 0.4 + sin(TAU * 130.0 * t) * exp(-t * 45.0) * 0.2
	return _make_wav(_normalize(s, 0.75))


## Grass / lawn: a soft brushed swish, no hard transient.
static func _gen_step_grass() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var cutoff := randf_range(0.18, 0.28)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += cutoff * ((randf() * 2.0 - 1.0) - lp)
		lp2 += 0.5 * (lp - lp2)
		var env := minf(t / 0.025, 1.0) * exp(-t * 16.0)  # brushed attack, soft tail
		var rustle := (randf() * 2.0 - 1.0) * 0.08 * exp(-t * 30.0) if randf() < 0.3 else 0.0
		s[i] = (lp2 * 1.6 + rustle) * env + sin(TAU * 90.0 * t) * exp(-t * 40.0) * 0.12
	return _make_wav(_normalize(s, 0.55))


## Scale a buffer so its loudest sample sits at `peak` (keeps takes at a
## consistent level regardless of the random filter frequencies).
static func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0001
	for v in s:
		loudest = maxf(loudest, absf(v))
	var k := peak / loudest
	for i in s.size():
		s[i] *= k
	return s


## Warm, mellow ambient jazz-like tone: low-pass filtered sine with slow
## amplitude breath and subtle harmonic layers. Looping, relaxing.
static func _gen_jazz_ambient() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 8.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		# Low fundamental with slow breath (8 s cycle)
		var fundamental := sin(TAU * 72.0 * t) * (0.5 + 0.5 * sin(TAU * t / 8.0))
		# Warm harmonic layer (softer, slightly higher)
		var harmonic := sin(TAU * 108.0 * t) * (0.3 + 0.2 * sin(TAU * t / 6.5))
		# Sub-bass warmth
		var sub := sin(TAU * 36.0 * t) * 0.2
		var raw := fundamental + harmonic + sub
		# Low-pass for smooth, mellow character
		lp += 0.08 * (raw - lp)
		s[i] = lp * 0.7
	return _make_wav(s, true)


## Fire crackle: sparse random pops and hisses at various pitches with
## quick decay. Looping, creates ambient warmth.
static func _gen_fire_crackle() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 3.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		# Sparse crackle: pop when random event fires
		var pop := 0.0
		if randf() < 0.006:  # ~18 pops per 3 seconds
			var pop_pitch := 200.0 + randf() * 600.0  # 200–800 Hz
			var pop_life := 0.02 + randf() * 0.08  # Quick decay
			pop = sin(TAU * pop_pitch * fmod(t, 3.0)) * exp(-fmod(t, 3.0) / pop_life) * 0.5
		# Low-pass hiss underbelly (very quiet)
		var hiss := (randf() * 2.0 - 1.0) * 0.12
		var lp_hiss := 0.0
		lp_hiss += 0.04 * (hiss - lp_hiss)
		s[i] = pop + lp_hiss * 0.3
	return _make_wav(s, true)
