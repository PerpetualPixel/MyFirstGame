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
