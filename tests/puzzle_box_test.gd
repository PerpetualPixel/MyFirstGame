extends SceneTree
## Puzzle-box solvability regression, written after a playtest where the
## box "had no clues and every combo failed". Two separate faults caused
## that, and this guards both:
##   1. The lever's settle used to REJECT (and fail) any input inside its
##      window, so entering the CORRECT order at a normal clicking pace
##      was reported as wrong every single time.
##   2. The order was only ever shown as bare glyphs on the case, with no
##      way to tell which hand-drawn tile was which — effectively no clue.
## Now: three pendants arm the box (telling you WHICH symbols), and the
## observatory log names the ORDER in plain words, in another room.
## Run: godot --headless --path . --script res://tests/puzzle_box_test.gd

const SEEDS := [7, 11, 22, 33, 44, 55]

func _initialize() -> void:
	_run()


func _run() -> void:
	for seed_value in SEEDS:
		var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
		main.get_node("MansionGenerator").rng_seed = seed_value
		root.add_child(main)
		for i in 30:
			await physics_frame
		var gen: MansionGenerator = main.get_node("MansionGenerator")
		var box: PuzzleBox = main.find_child("PuzzleBox", true, false)
		var order: Array = box.required_symbols()

		# --- the hunt: one pendant per symbol, never in the box's room ---
		var pendants := get_nodes_in_group("pendants")
		if pendants.size() != box.sequence_length:
			print("TEST FAIL [seed %d]: %d pendants for a %d-symbol lock" % [
				seed_value, pendants.size(), box.sequence_length])
			quit(1)
			return
		var symbols_found: Array[String] = []
		for pd in pendants:
			symbols_found.append(pd.pendant_symbol)
			if gen._cell_of(pd.global_position) == gen._puzzle_box_cell:
				print("TEST FAIL [seed %d]: pendant %s sits in the box's own room" % [
					seed_value, pd.name])
				quit(1)
				return
		for sym in order:
			if not sym in symbols_found:
				print("TEST FAIL [seed %d]: no pendant for %s" % [seed_value, sym])
				quit(1)
				return

		# --- the clues: both in other rooms, and the log names the order ---
		for clue_name in ["ObservatoryLog", "WorkshopScrap"]:
			var clue: NotebookPickup = main.find_child(clue_name, true, false)
			if clue == null:
				print("TEST FAIL [seed %d]: %s never spawned" % [seed_value, clue_name])
				quit(1)
				return
			if gen._cell_of(clue.global_position) == gen._puzzle_box_cell:
				print("TEST FAIL [seed %d]: %s sits in the box's own room" % [seed_value, clue_name])
				quit(1)
				return
		var log_text: String = (main.find_child("ObservatoryLog", true, false) as NotebookPickup).note_text
		var last := -1
		for sym in order:
			var at: int = log_text.find(PuzzleBox.SYMBOL_LABELS[sym])
			if at < 0:
				print("TEST FAIL [seed %d]: log never names %s" % [seed_value, sym])
				quit(1)
				return
			if at < last:
				print("TEST FAIL [seed %d]: log names the symbols out of dial order" % seed_value)
				quit(1)
				return
			last = at

		# --- stage one gates stage two ---
		box.register_dial_input(order[0])
		if not box.current_input_buffer.is_empty():
			print("TEST FAIL [seed %d]: the dial turned before the box was armed" % seed_value)
			quit(1)
			return
		for sym in order:
			box.seat_pendant(sym)
		if not box.is_armed():
			print("TEST FAIL [seed %d]: seating every pendant did not arm the box" % seed_value)
			quit(1)
			return

		# --- the log's order, entered back-to-back, must open it ---
		for sym in order:
			box.register_dial_input(sym)
			box.register_advance_input()
		if box.is_locked:
			print("TEST FAIL [seed %d]: the log's own order did not open the box" % seed_value)
			quit(1)
			return

		main.queue_free()
		for i in 5:
			await physics_frame
		print("seed %d: %s — armed by pendants, opened by the log" % [seed_value, order])

	print("TEST PASS: the puzzle box is armed by its pendants and solved from its clue")
	quit(0)
