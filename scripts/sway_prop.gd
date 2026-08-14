class_name SwayProp
extends Node3D

## Gentle wind sway for trees and branches; pivots at the node origin.

@export var amplitude: float = 0.03
@export var speed: float = 0.8

var _phase := randf() * TAU


func _process(delta: float) -> void:
	_phase += delta * speed
	rotation.z = sin(_phase) * amplitude
	rotation.x = cos(_phase * 0.8) * amplitude * 0.6
