class_name AstralPendant
extends Grabbable

## One of the inventor's three astral pendants. Each is stamped with a
## single sky symbol and belongs in a socket on the astronomical puzzle
## box; carrying all three back arms the box's dial. Which three exist in
## a given run IS the first half of the answer — the order they go in is
## the other half, and that is written in his observatory log.

## "sun", "moon", "star" or "comet" — matches PuzzleBox.SYMBOLS.
@export var pendant_symbol := "moon"


## Each symbol gets its own colour, and the disc glows with a small lamp
## of its own. Without that a 0.11 m dark medallion on a dark floor is
## effectively invisible, and hunting three of them stops being a hunt.
const SYMBOL_COLORS := {
	"sun": Color(1.0, 0.78, 0.3),
	"moon": Color(0.72, 0.85, 1.0),
	"star": Color(1.0, 0.95, 0.72),
	"comet": Color(0.6, 1.0, 0.95),
}


func _ready() -> void:
	super._ready()
	display_name = "%s Pendant" % PuzzleBox.SYMBOL_LABELS.get(pendant_symbol, "Astral")
	var tint: Color = SYMBOL_COLORS.get(pendant_symbol, Color(1.0, 0.9, 0.6))
	var glyph := get_node_or_null("Glyph") as Label3D
	if glyph:
		glyph.text = PuzzleBox.SYMBOL_GLYPHS.get(pendant_symbol, "?")
	var disc := get_node_or_null("Disc") as MeshInstance3D
	if disc:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.metallic = 0.8
		mat.roughness = 0.25
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.9
		disc.material_override = mat
	var lamp := OmniLight3D.new()
	lamp.light_color = tint
	lamp.light_energy = 1.1
	lamp.omni_range = 2.6
	lamp.position = Vector3(0, 0.22, 0)
	add_child(lamp)


func get_prompt(_by: Node3D = null) -> String:
	return "[E] Take the %s Pendant" % PuzzleBox.SYMBOL_LABELS.get(pendant_symbol, "Astral")
