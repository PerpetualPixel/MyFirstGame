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
	_streams["plug"] = _gen_plug()
	_streams["ratchet"] = _gen_ratchet()
	_streams["tick"] = _gen_tick()
	_streams["chime"] = _gen_chime()
	_streams["steam"] = _gen_steam()
	_streams["footstep_wood"] = _gen_footstep(260.0, 0.10)
	_streams["footstep_stone"] = _gen_footstep(900.0, 0.07)
	_streams["wind"] = _gen_wind()


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Positional one-shot; the temporary player frees itself when done.
static func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if instance == null or not instance._streams.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = instance._streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
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


## Footstep: filtered noise thump; tone selects wood vs stone character.
static func _gen_footstep(tone_hz: float, dur: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var cutoff := clampf(tone_hz / 4000.0, 0.05, 0.6)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += cutoff * ((randf() * 2.0 - 1.0) - lp)
		s[i] = lp * exp(-t * 42.0) * 0.9 + sin(TAU * tone_hz * 0.35 * t) * exp(-t * 60.0) * 0.25
	return _make_wav(s)
