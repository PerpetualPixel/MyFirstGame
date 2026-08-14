class_name FlickerLight
extends OmniLight3D

## Candle/lantern flame flicker: layered sines give an organic waver.

@export var base_energy: float = 0.9

var _t := randf() * 100.0


func _ready() -> void:
	# Fade out beyond typical camera framing so distant lanterns are culled.
	distance_fade_enabled = true
	distance_fade_begin = 24.0
	distance_fade_length = 8.0


func _process(delta: float) -> void:
	_t += delta
	light_energy = base_energy * (
		0.82
		+ 0.14 * sin(_t * 9.0) * sin(_t * 5.3 + 1.7)
		+ 0.06 * sin(_t * 23.0))
