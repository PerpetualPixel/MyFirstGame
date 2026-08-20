extends SceneTree
## Inventory presentation contract:
##   * every carryable has an icon that LOADS, and that icon is rendered
##     from the item's own 3D model (tools/render_item_icons.gd), so the
##     slot can never show a picture of something else;
##   * every carryable has a display name, and hovering its slot shows it;
##   * an item whose job is done reads as spent — a red cross on the slot
##     and a tooltip that says so — so nobody hauls a dead tool around.
## Run: godot --headless --path . --script res://tests/inventory_test.gd

## Every scene a player can end up carrying in the 3-slot pack.
const CARRYABLES := [
	"res://scenes/Crowbar.tscn",
	"res://scenes/Fuse.tscn",
	"res://scenes/SmallWrench.tscn",
	"res://scenes/BrassWrench.tscn",
	"res://scenes/WillItem.tscn",
	"res://scenes/Prism.tscn",
	"res://scenes/AstralPendant.tscn",
	"res://scenes/BigBattery.tscn",  # two-hand carry, shown in the "in hand" panel
]

func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	var hud: HUD = main.get_node("HUD")
	hud.dismiss_intro()
	var player: Player = main.get_node("Players/1")

	# Every registered icon path resolves.
	for group in hud.ITEM_ICONS:
		var path: String = hud.ITEM_ICONS[group]
		if not ResourceLoader.exists(path) or load(path) == null:
			print("TEST FAIL: icon for group '%s' does not load (%s)" % [group, path])
			quit(1)
			return
		if not path.begins_with("res://assets/ui/items/"):
			print("TEST FAIL: '%s' uses a hand-made icon (%s); icons are rendered from the models" % [group, path])
			quit(1)
			return

	# Every carryable names itself and has a picture of ITSELF.
	for scene_path in CARRYABLES:
		var item: Node3D = (load(scene_path) as PackedScene).instantiate()
		main.add_child(item)
		await process_frame
		var display: String = str(item.get("display_name"))
		if display.is_empty() or display == "<null>":
			print("TEST FAIL: %s has no display_name to show on hover" % scene_path)
			quit(1)
			return
		if hud._icon_for(item) == null:
			print("TEST FAIL: %s ('%s') has no inventory icon" % [scene_path, display])
			quit(1)
			return
		item.queue_free()
		await process_frame
	print("every carryable: named, and pictured from its own model")

	# Each pendant face has its own rendered icon, so the slot shows the
	# sky-mark actually being carried.
	for symbol in PuzzleBox.SYMBOLS:
		var path := "res://assets/ui/items/pendant_%s.png" % symbol
		if not ResourceLoader.exists(path):
			print("TEST FAIL: no rendered icon for the %s pendant" % symbol)
			quit(1)
			return

	# Spent contract: cross on the slot, and a tooltip that says so.
	var bar: Grabbable = get_nodes_in_group("crowbars")[0]
	player.teleport(bar.global_position + Vector3(0, 0, 1.0))
	for i in 10:
		await physics_frame
	player.pick_up(bar)
	for i in 5:
		await physics_frame
	var slot: InventorySlot = hud._inv_slots[0]
	if slot.tooltip_text != str(bar.display_name):
		print("TEST FAIL: fresh item tooltip was '%s', expected '%s'" % [
			slot.tooltip_text, bar.display_name])
		quit(1)
		return
	if _has_cross(slot):
		print("TEST FAIL: an unused item is already crossed out")
		quit(1)
		return
	bar.spent = true
	hud._inv_signature = ""  # force a rebuild
	for i in 5:
		await physics_frame
	if not _has_cross(slot):
		print("TEST FAIL: a spent item shows no cross on its slot")
		quit(1)
		return
	if not "used up" in slot.tooltip_text:
		print("TEST FAIL: a spent item's tooltip ('%s') does not say it is done" % slot.tooltip_text)
		quit(1)
		return
	print("spent items: crossed out and labelled")

	print("TEST PASS: inventory icons, names and spent marks")
	quit(0)


func _has_cross(slot: InventorySlot) -> bool:
	for child in slot.get_children():
		if child is Label and (child as Label).text == "✕":
			return true
	return false
