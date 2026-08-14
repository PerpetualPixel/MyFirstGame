class_name NetworkSession
extends RefCounted

## Process-wide co-op session state. Statics survive scene changes, so the
## lobby can hand the shared generation seed to Main on every peer.

static var multiplayer_active := false
## Shared layout seed for this run (0 = roll a fresh solo seed).
static var run_seed := 0
## Hint for the Lobby scene: "host" or "join".
static var lobby_mode := "host"


static func reset() -> void:
	multiplayer_active = false
	run_seed = 0
