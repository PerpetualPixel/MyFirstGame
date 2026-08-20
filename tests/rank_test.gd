extends SceneTree
## End-screen regression: Story.rank_for's grade boundaries (the game
## loop test only ever sees a sub-2:00 S run), and the defeat path —
## which no other test reaches, yet owns the rank/flavor labels' hidden
## state and the heavier dim.
## Run: godot --headless --path . --script res://tests/rank_test.gd

const BOUNDARIES := [
	[0.0, "S"], [119.9, "S"], [120.0, "S"], [120.1, "A"],
	[150.0, "A"], [150.1, "B"], [180.0, "B"], [180.1, "C"],
	[210.0, "C"], [210.1, "D"], [400.0, "D"],
]

func _initialize() -> void:
	_run()


func _run() -> void:
	# Every threshold lands on the grade the design calls for, inclusive
	# at the boundary itself.
	for entry in BOUNDARIES:
		var elapsed: float = entry[0]
		var want: String = entry[1]
		var got: String = str(Story.rank_for(elapsed)["letter"])
		if got != want:
			print("TEST FAIL: %.1fs graded %s, expected %s" % [elapsed, got, want])
			quit(1)
			return
		var rank: Dictionary = Story.rank_for(elapsed)
		if str(rank["flavor"]).is_empty() or not rank.has("color"):
			print("TEST FAIL: rank %s is missing flavor/color" % got)
			quit(1)
			return
	print("rank boundaries OK")

	# Defeat: the clock runs out and the end screen must show the loss
	# text with NO rank letter left over from the victory layout.
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	var gm: GameManager = main.get_node("GameManager")
	var hud: HUD = main.get_node("HUD")
	hud.dismiss_intro()
	# The scene may ship with the playtest switch off; this test is
	# about the real timed loop.
	gm.timer_enabled = true
	gm.state = GameManager.State.PLAYING
	gm.time_left = 0.05
	for i in 30:
		await physics_frame
	if gm.state != GameManager.State.LOST:
		print("TEST FAIL: clock ran out but state is %d" % gm.state)
		quit(1)
		return
	var end_screen: Control = main.get_node("HUD/EndScreen")
	var rank_label: Label = main.get_node("HUD/EndScreen/Center/VBox/Rank")
	var flavor_label: Label = main.get_node("HUD/EndScreen/Center/VBox/Flavor")
	var title: Label = main.get_node("HUD/EndScreen/Center/VBox/Title")
	if not end_screen.visible or rank_label.visible or flavor_label.visible:
		print("TEST FAIL: defeat screen shows victory rank chrome")
		quit(1)
		return
	if not "Sealed" in title.text:
		print("TEST FAIL: defeat title wrong (%s)" % title.text)
		quit(1)
		return
	# The run is over: the HUD's own shortcuts must be retired so nothing
	# can be summoned over the end screen (co-op never pauses the tree).
	if not hud._run_over:
		print("TEST FAIL: defeat did not retire the HUD shortcuts")
		quit(1)
		return
	hud.say("this must not appear")
	if not hud._dialogue_queue.is_empty():
		print("TEST FAIL: radio chatter queued after the run ended")
		quit(1)
		return
	paused = false
	print("TEST PASS: rank boundaries and the defeat screen")
	quit(0)
