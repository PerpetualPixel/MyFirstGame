class_name PlayerNotes
extends RefCounted

## Static store for notes the player has collected this run (ledger pages,
## codes, hints). The HUD renders them in the [Tab] notes panel; the
## generator clears them when a new mansion is built. Never instantiated.

static var entries: Array[String] = []


static func add(entry: String) -> void:
	if not entries.has(entry):
		entries.append(entry)


static func clear() -> void:
	entries.clear()
