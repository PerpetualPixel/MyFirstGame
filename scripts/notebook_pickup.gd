class_name NotebookPickup
extends Interactable

## A weathered notebook. [E] tucks its contents into the player's notes
## ([Tab] to read) and removes the book from the world. Interactions run
## on every co-op peer, so both explorers learn what it says.

@export var note_text := "An empty page."

var taken := false


func can_interact(_by: Node3D) -> bool:
	return not taken


func get_prompt(_by: Node3D = null) -> String:
	return "[E] Take Notebook"


func interact(by: Node3D) -> void:
	if taken:
		return
	taken = true
	PlayerNotes.add(note_text)
	AudioSynthesizer.play_at("tick", global_position, -10.0, 0.8)
	super.interact(by)
	queue_free()
