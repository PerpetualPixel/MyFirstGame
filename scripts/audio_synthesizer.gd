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
	_streams["door_creak"] = _gen_door_creak()
	_streams["drag_wood"] = _gen_drag_wood()
	_streams["laser_hum"] = _gen_laser_hum()
	_streams["rumble"] = _gen_rumble()
	_streams["whoosh"] = _gen_whoosh()
	_streams["radio"] = _gen_radio_blip()
	_streams["fanfare"] = _gen_fanfare()
	# Item handling foley: what each material does in the hand and on the
	# floor (hard) or the lawn (soft, muffled).
	_streams["pickup_metal"] = _gen_pickup_metal()
	_streams["pickup_heavy"] = _gen_pickup_heavy()
	_streams["pickup_ceramic"] = _gen_pickup_ceramic()
	_streams["pickup_paper"] = _gen_paper(0.16, 0.5)
	_streams["drop_metal"] = _gen_drop_metal(false)
	_streams["drop_metal_soft"] = _gen_drop_metal(true)
	_streams["drop_heavy"] = _gen_drop_heavy(false)
	_streams["drop_heavy_soft"] = _gen_drop_heavy(true)
	_streams["drop_ceramic"] = _gen_drop_ceramic(false)
	_streams["drop_ceramic_soft"] = _gen_drop_ceramic(true)
	_streams["drop_paper"] = _gen_paper(0.22, 0.35)


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
	_free_when_done(p, p.stream)


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
	_free_when_done(p, p.stream)


## One-shots free themselves when the sample ends. A LOOPING sample
## (steam, hums) never fires `finished`, so it would hiss forever — those
## get one pass and are cut after the sample's length.
static func _free_when_done(p: Node, stream: AudioStream) -> void:
	var looping := stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if looping:
		instance.get_tree().create_timer(stream.get_length(), true).timeout.connect(p.queue_free)
	else:
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


## Shortwave chirp: two quick filtered blips with a breath of static,
## announcing a radio transmission (the subtitle bar's attention cue).
static func _gen_radio_blip() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.32)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var lt := t if t < 0.14 else t - 0.14
		var f := 1150.0 if t < 0.14 else 1520.0
		var blip := sin(TAU * f * lt) * exp(-lt * 34.0) * 0.34
		lp += 0.3 * ((randf() * 2.0 - 1.0) - lp)
		s[i] = blip + lp * 0.05 * exp(-t * 6.0)
	return _make_wav(s)


## Victory fanfare: four ascending bell-brass notes (C-E-G-C), the last
## one ringing out under the rank screen.
static func _gen_fanfare() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 2.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [262.0, 330.0, 392.0, 523.0]
	for k in notes.size():
		var start := int(SAMPLE_RATE * 0.22 * k)
		var f: float = notes[k]
		var last := k == notes.size() - 1
		for i in n - start:
			var t := float(i) / SAMPLE_RATE
			var v := sin(TAU * f * t) * 0.3
			v += sin(TAU * f * 2.0 * t) * 0.12 * exp(-t * 2.2)
			v += sin(TAU * f * 3.01 * t) * 0.05 * exp(-t * 3.2)
			var env := minf(t / 0.02, 1.0) * exp(-t * (1.1 if last else 2.8))
			s[start + i] += v * env * 0.8
	for i in n:
		s[i] = clampf(s[i], -0.95, 0.95)
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


# --- Doors, hauling, machines, camera -----------------------------------


## Old hinge: a slow rising groan with a wobble, then a settle.
static func _gen_door_creak() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.75)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var freq := 190.0 + 170.0 * minf(t / 0.5, 1.0) + 18.0 * sin(TAU * 11.0 * t)
		phase += TAU * freq / SAMPLE_RATE
		# Stick-slip: the tone stutters like a dry hinge.
		var stick := 0.55 + 0.45 * signf(sin(TAU * 34.0 * t + 2.0 * sin(TAU * 3.0 * t)))
		var env := minf(t / 0.06, 1.0) * exp(-maxf(t - 0.5, 0.0) * 9.0)
		var body := (sin(phase) * 0.5 + sin(phase * 2.0) * 0.18 + sin(phase * 3.0) * 0.08) * stick
		s[i] = (body * env + (randf() * 2.0 - 1.0) * 0.03 * env) * 0.7
	return _make_wav(s)


## Heavy furniture dragged over floorboards: looping, gritty rumble with
## slow surges (loop-aligned).
static func _gen_drag_wood() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 1.2)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += 0.12 * ((randf() * 2.0 - 1.0) - lp)
		var surge := 0.6 + 0.4 * sin(TAU * t / 1.2 * 2.0)
		var grit := (randf() * 2.0 - 1.0) * 0.06 if randf() < 0.2 else 0.0
		raw[i] = (lp * 0.9 + grit) * surge
	var body := _resonate(raw, 160.0, 0.96)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i] * 0.6 + body[i] * 0.5
	return _make_wav(_normalize(s, 0.6), true)


## Powered laser: a steady electric hum with a faint high whine.
static func _gen_laser_hum() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := sin(TAU * 120.0 * t) * 0.35 + sin(TAU * 240.0 * t) * 0.15 + sin(TAU * 60.0 * t) * 0.2
		v += signf(sin(TAU * 120.0 * t)) * 0.04  # a little buzz
		v += sin(TAU * 2400.0 * t) * 0.03 * (0.5 + 0.5 * sin(TAU * 4.0 * t))
		s[i] = v * 0.6
	return _make_wav(s, true)


## Deep stone rumble for gates and heavy mechanisms settling.
static func _gen_rumble() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 1.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += 0.02 * ((randf() * 2.0 - 1.0) - lp)
		lp2 += 0.05 * (lp - lp2)
		var env := minf(t / 0.08, 1.0) * exp(-t * 2.6)
		var thump := sin(TAU * 42.0 * t) * exp(-t * 3.0) * 0.4
		s[i] = (lp2 * 6.0 + thump) * env
	return _make_wav(_normalize(s, 0.85))


## Camera swing: a short airy whoosh (band-swept noise).
static func _gen_whoosh() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.35)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := sin(PI * minf(t / 0.35, 1.0))  # swell and fade
		raw[i] = (randf() * 2.0 - 1.0) * env * 0.05
	var lo := _resonate(raw, 700.0, 0.93)
	var hi := _resonate(raw, 1600.0, 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var mix := t / 0.35  # sweeps upward through the swing
		s[i] = lo[i] * (1.0 - mix) + hi[i] * mix
	return _make_wav(_normalize(s, 0.45))


# --- Item handling -------------------------------------------------------
# Pick-ups are the object shifting in the hand; drops are the object
# meeting the floor. Metal rings, ceramic clinks, paper flops, and the
# heavy battery lands like the lead brick it is. "Soft" variants are the
# lawn: the transient is smothered, only the thud gets through.


## Tools lifted: two quick metallic taps as the piece settles in the grip.
static func _gen_pickup_metal() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.16)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var tap := exp(-t * 90.0) + (exp(-(t - 0.07) * 90.0) if t > 0.07 else 0.0) * 0.7
		raw[i] = (randf() * 2.0 - 1.0) * tap * 0.06
	var a := _resonate(raw, randf_range(2300.0, 2700.0), 0.975)
	var b := _resonate(raw, randf_range(3500.0, 4100.0), 0.965)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = a[i] * 1.6 + b[i] * 1.0
	return _make_wav(_normalize(s, 0.55))


## The battery hefted: a low grunt of effort in the case, a strap creak,
## and the terminals rattling.
static func _gen_pickup_heavy() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.32)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		raw[i] = (randf() * 2.0 - 1.0) * exp(-t * 26.0) * 0.05
	var rattle := _resonate(raw, 1800.0, 0.94)
	var body := _resonate(raw, 220.0, 0.985)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var thump := sin(TAU * 70.0 * t) * exp(-t * 20.0) * 0.6
		var creak := sin(TAU * (900.0 + 200.0 * t) * t) * exp(-t * 18.0) * 0.06 * (0.5 + 0.5 * signf(sin(TAU * 40.0 * t)))
		s[i] = thump + body[i] * 1.5 + rattle[i] * 0.9 + creak
	return _make_wav(_normalize(s, 0.75))


## A ceramic cartridge lifted: one glassy tick.
static func _gen_pickup_ceramic() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.12)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		raw[i] = (randf() * 2.0 - 1.0) * exp(-t * 140.0) * 0.06
	var s := _resonate(raw, randf_range(4200.0, 5200.0), 0.98)
	return _make_wav(_normalize(s, 0.5))


## Paper handled: a dry rustle (`dur` seconds, `crackle` density).
static func _gen_paper(dur: float, crackle: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	var flutter := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var noise := randf() * 2.0 - 1.0
		var hp := noise - prev
		prev = noise
		if randf() < 0.004 * crackle:
			flutter = 1.0
		flutter *= 0.985
		var env := minf(t / 0.02, 1.0) * exp(-t * (14.0 / dur))
		s[i] = hp * (0.25 + flutter * 0.6) * env
	return _make_wav(_normalize(s, 0.45))


## A tool dropped: hard = clang with a bright ring and a bounce; soft =
## a smothered thud with the ring choked off.
static func _gen_drop_metal(soft: bool) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * (0.28 if soft else 0.55))
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var hit := exp(-t * 60.0)
		var bounce := (exp(-(t - 0.16) * 70.0) if t > 0.16 else 0.0) * 0.5
		raw[i] = (randf() * 2.0 - 1.0) * (hit + bounce) * 0.06
	var s := PackedFloat32Array()
	s.resize(n)
	if soft:
		var lp := 0.0
		for i in n:
			var t := float(i) / SAMPLE_RATE
			lp += 0.18 * (raw[i] * 8.0 - lp)
			s[i] = lp + sin(TAU * 110.0 * t) * exp(-t * 30.0) * 0.5
	else:
		var r1 := _resonate(raw, randf_range(1050.0, 1250.0), 0.992)
		var r2 := _resonate(raw, randf_range(2600.0, 2900.0), 0.988)
		var r3 := _resonate(raw, randf_range(4000.0, 4400.0), 0.98)
		for i in n:
			var t := float(i) / SAMPLE_RATE
			s[i] = r1[i] * 1.2 + r2[i] * 0.9 + r3[i] * 0.5 + sin(TAU * 140.0 * t) * exp(-t * 45.0) * 0.4
	return _make_wav(_normalize(s, 0.8))


## The battery set down: a floor-shaking thud, terminal rattle, and on a
## hard floor a short case clang. On the lawn: just the thud.
static func _gen_drop_heavy(soft: bool) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.5)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		raw[i] = (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.06
	var rattle := _resonate(raw, 1700.0, 0.95)
	var clang := _resonate(raw, 900.0, 0.985)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += 0.03 * ((randf() * 2.0 - 1.0) - lp)
		var thud := sin(TAU * 55.0 * t) * exp(-t * 14.0) * 0.9 + lp * 4.0 * exp(-t * 10.0)
		if soft:
			s[i] = thud + rattle[i] * 0.2
		else:
			s[i] = thud + rattle[i] * 0.8 + clang[i] * 0.9
	return _make_wav(_normalize(s, 0.9))


## A ceramic fuse dropped: hard = bright clink and a skitter; soft = a
## dull tick in the grass.
static func _gen_drop_ceramic(soft: bool) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * (0.12 if soft else 0.3))
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var hit := exp(-t * 120.0)
		var skitter := 0.0
		if not soft:
			for k in [0.09, 0.15, 0.19]:
				if t > k:
					skitter += exp(-(t - k) * 150.0) * 0.4
		raw[i] = (randf() * 2.0 - 1.0) * (hit + skitter) * 0.06
	var s: PackedFloat32Array
	if soft:
		s = _resonate(raw, 2200.0, 0.93)
	else:
		var a := _resonate(raw, randf_range(4600.0, 5400.0), 0.985)
		var b := _resonate(raw, randf_range(7000.0, 8000.0), 0.97)
		s = PackedFloat32Array()
		s.resize(n)
		for i in n:
			s[i] = a[i] * 1.2 + b[i] * 0.6
	return _make_wav(_normalize(s, 0.6))


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
