extends Node3D

## Entry scene: the MansionGenerator builds the house in its own _ready()
## (children ready before the parent), so by the time this runs the layout
## exists and the player just needs to be placed in the Foyer.

@onready var mansion: MansionGenerator = $MansionGenerator
@onready var player: Player = $Player


func _ready() -> void:
	player.teleport(mansion.get_spawn_position())
	mansion.puzzle_solved.connect(_on_puzzle_solved)


func _on_puzzle_solved() -> void:
	print("Puzzle solved: the Vault Study hums with light!")
