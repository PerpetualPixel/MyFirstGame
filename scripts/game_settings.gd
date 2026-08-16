class_name GameSettings
extends RefCounted

## Global game settings as a static class (same pattern as NetworkSession),
## so references compile in every mode — including headless --script test
## runs, where autoload singletons never register. Never instantiated.
## Accessed as GameSettings.hints_enabled, GameSettings.music_volume_db.

static var hints_enabled := true
static var music_volume_db := -10.4  # 30% volume in dB

## On-screen size of the objectives list (0.6 = compact, 1.6 = large).
## The HUD polls this each frame; writers should keep it in that range.
static var objectives_scale := 1.0


# --- Key bindings ---------------------------------------------------------
# Every gameplay action the player may rebind, in menu order, with its
# display name. Bindings live in the InputMap at run time and persist to
# user://controls.cfg. Keyboard keys and mouse buttons both work.

const BINDABLE_ACTIONS := [
	["move_up", "Move Forward"],
	["move_down", "Move Back"],
	["move_left", "Move Left"],
	["move_right", "Move Right"],
	["interact", "Interact / Use"],
	["drop", "Drop / Set Down"],
	["rotate_camera", "Rotate Camera"],
	["emote", "Emote Wheel"],
	["notes", "Notes"],
	["ping", "Ping (co-op)"],
	["restart", "Quick Restart"],
]
const BINDINGS_PATH := "user://controls.cfg"
## Prompt tokens as written in the game's strings -> the action they mean.
const PROMPT_TOKENS := {
	"[E]": "interact", "[G]": "drop", "[Q]": "rotate_camera", "[Tab]": "notes",
	"[F]": "ping", "[R]": "restart", "[B]": "emote",
}

static var _bindings_loaded := false


## Human label for an action's first bound key/button ("E", "Mouse 4").
static func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		return event_label(ev)
	return "—"


static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		var text := OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if k.physical_keycode != 0 else code)
		if text.is_empty():
			text = OS.get_keycode_string(code)
		return text
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Mouse L"
			MOUSE_BUTTON_RIGHT: return "Mouse R"
			MOUSE_BUTTON_MIDDLE: return "Mouse M"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			_: return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return ev.as_text()


## Rewrite a prompt's "[E]"-style tokens to the player's current keys.
static func fmt(text: String) -> String:
	for token in PROMPT_TOKENS:
		if text.find(token) != -1:
			text = text.replace(token, "[%s]" % key_label(PROMPT_TOKENS[token]))
	if text.find("[W] [A] [S] [D]") != -1:
		text = text.replace("[W] [A] [S] [D]", "[%s] [%s] [%s] [%s]" % [
			key_label("move_up"), key_label("move_left"), key_label("move_down"), key_label("move_right")])
	if text.find("[WASD]") != -1:
		text = text.replace("[WASD]", "[%s%s%s%s]" % [
			key_label("move_up"), key_label("move_left"), key_label("move_down"), key_label("move_right")])
	return text


## Replace an action's binding with `ev` (a key or mouse button) and save.
## Another action already using that input loses it (no double binding).
static func rebind(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for entry in BINDABLE_ACTIONS:
		var other: String = entry[0]
		if other == action:
			continue
		for existing in InputMap.action_get_events(other):
			if _same_input(existing, ev):
				InputMap.action_erase_event(other, existing)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)
	save_bindings()


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var ca := ka.physical_keycode if ka.physical_keycode != 0 else ka.keycode
		var cb := kb.physical_keycode if kb.physical_keycode != 0 else kb.keycode
		return ca == cb
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for entry in BINDABLE_ACTIONS:
		var action: String = entry[0]
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			cfg.set_value("bindings", action, "")
			continue
		var ev: InputEvent = events[0]
		if ev is InputEventKey:
			var k := ev as InputEventKey
			cfg.set_value("bindings", action, "key:%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode))
		elif ev is InputEventMouseButton:
			cfg.set_value("bindings", action, "mouse:%d" % (ev as InputEventMouseButton).button_index)
	cfg.save(BINDINGS_PATH)


## Apply saved bindings over the project defaults (once per process).
static func load_bindings() -> void:
	if _bindings_loaded:
		return
	_bindings_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(BINDINGS_PATH) != OK:
		return
	for entry in BINDABLE_ACTIONS:
		var action: String = entry[0]
		if not cfg.has_section_key("bindings", action) or not InputMap.has_action(action):
			continue
		var spec: String = str(cfg.get_value("bindings", action))
		var ev: InputEvent = null
		if spec.begins_with("key:"):
			var k := InputEventKey.new()
			k.physical_keycode = int(spec.substr(4)) as Key
			ev = k
		elif spec.begins_with("mouse:"):
			var m := InputEventMouseButton.new()
			m.button_index = int(spec.substr(6)) as MouseButton
			ev = m
		if ev != null:
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, ev)


## Back to the project's default keys.
static func reset_bindings() -> void:
	InputMap.load_from_project_settings()
	save_bindings()
