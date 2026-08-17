class_name MansionGenerator
extends Node3D

## Procedurally builds the estate: a 3x3 grid of interconnected rooms, the
## Front Porch, and a moonlit 60x60 walled yard with gate, trees, and
## driveway. A randomized spanning tree carved from the Foyer (excluding
## the Vault Study) guarantees reachability; the vault's only entrance is
## the gate-guarded doorway. Spawns all puzzles (laser mirror maze, the
## hydraulic press, breaker box, astronomical puzzle box), hinged doors,
## fog-of-war shrouds, furniture, and ambient atmosphere.
## Grid convention: x grows east, y (grid) grows south (+Z in world).

signal generated
signal puzzle_solved

const GRID_SIZE := Vector2i(3, 3)
const FOYER_CELL := Vector2i(1, 2)
const VAULT_STUDY_CELL := Vector2i(1, 0)
const PARLOR_CELL := Vector2i(2, 0)         ## Fireplace parlor.

const LIGHT_EMITTER_SCENE := preload("res://scenes/Puzzles/LightEmitter.tscn")
const ROTATING_MIRROR_SCENE := preload("res://scenes/Puzzles/PrismTable.tscn")
const LASER_SAFE_SCRIPT := preload("res://scripts/puzzles/laser_safe.gd")
const SMALL_WRENCH_SCENE := preload("res://scenes/SmallWrench.tscn")
const PRESSURE_MACHINE_SCRIPT := preload("res://scripts/puzzles/pressure_puzzle_manager.gd")
const BREAKER_BOX_SCENE := preload("res://scenes/Puzzles/BreakerBox.tscn")
const VAULT_DOOR_SCENE := preload("res://scenes/VaultDoor.tscn")
const WILL_ITEM_SCENE := preload("res://scenes/WillItem.tscn")
const BRASS_WRENCH_SCENE := preload("res://scenes/BrassWrench.tscn")
const DOOR_SCENE := preload("res://scenes/Door.tscn")
const ROOM_SHROUD_SCENE := preload("res://scenes/RoomShroud.tscn")
const BIG_BATTERY_SCENE := preload("res://scenes/BigBattery.tscn")
const CROWBAR_SCENE := preload("res://scenes/Crowbar.tscn")
const FUSE_SCENE := preload("res://scenes/Fuse.tscn")
const TOY_BOX_SCENE := preload("res://scenes/ToyBox.tscn")
const KEYPAD_SCENE := preload("res://scenes/Puzzles/Keypad.tscn")
const NOTEBOOK_SCENE := preload("res://scenes/NotebookPickup.tscn")
const GARAGE_BUTTON_SCRIPT := preload("res://scripts/puzzles/garage_door_button.gd")
const PUZZLE_BOX_SCRIPT := preload("res://scripts/puzzles/puzzle_box.gd")
const PRISM_SCENE := preload("res://scenes/Prism.tscn")

## Three hand-authored, guaranteed-solvable laser routes; one is drawn per
## run. EVERY mirror stands in a room corner (CORNER_INSET from both
## walls) so the rooms' walkways and doorways stay clear. The geometry
## is built on a 30-degree grid: legs run along OUTER walls (0/90 deg,
## never a door swing in the way) or cross a doorway diagonally from a
## corner on that wall through the door's center to the mirrored corner
## of the next room (exactly 60 deg off the wall) — so every mirror's
## solved yaw lands on a 15-degree detent (computed at run time by
## _route_solutions, never hand-typed). Doorways on the beam route are
## open archways: a hinged panel swung the wrong way would clip the
## diagonal. All routes end on the WALL SAFE hanging beside the vault
## doorway on the parlor's north wall (x = +-2.2, beam height): the last
## prism sits in the parlor corner on the far side of the door and fires
## back across at 60 degrees off the wall onto the safe's face. Every
## turn is at least 60 degrees: a shallow (30-degree) turn means a
## 15-degree grazing hit whose usable face is a hand-span, and bounce-to-
## bounce hit-point drift can walk the beam right off it.
const CORNER_INSET := 1.83
const ROUTE_VARIANTS := [
	{
		# Emitter in the SW room's NW corner fires through the archway into
		# the west wing room; the beam climbs that room's east wall, hops
		# into the parlor, climbs its west wall, runs the vault wall, and
		# comes back down onto the safe right of the door.
		"name": "west_wing",
		"emitter": Vector3(-13.17, 0, 6.83),
		"emitter_yaw": -60.0,
		"maze_cell": Vector2i(0, 1),
		"mirrors": [Vector3(-6.83, 0, 3.17), Vector3(-6.83, 0, -3.17), Vector3(-3.17, 0, 3.17), Vector3(-3.17, 0, -3.17), Vector3(3.17, 0, -3.17)],
		"safe": Vector3(2.2, 0, -4.85),
		"doors": [[Vector2i(0, 2), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(1, 1)]],
	},
	{
		# Mirror image up the east wing, ending on the safe left of the door.
		"name": "east_wing",
		"emitter": Vector3(13.17, 0, 6.83),
		"emitter_yaw": 60.0,
		"maze_cell": Vector2i(2, 1),
		"mirrors": [Vector3(6.83, 0, 3.17), Vector3(6.83, 0, -3.17), Vector3(3.17, 0, 3.17), Vector3(3.17, 0, -3.17), Vector3(-3.17, 0, -3.17)],
		"safe": Vector3(-2.2, 0, -4.85),
		"doors": [[Vector2i(2, 2), Vector2i(2, 1)], [Vector2i(2, 1), Vector2i(1, 1)]],
	},
	{
		# Detours through a THIRD room before ever reaching the parlor:
		# the opening three legs are west_wing's own proven corner chain
		# (NW room -> west wing -> parlor), reused verbatim since that
		# exact diagonal math is what actually threads each doorway: the
		# beam starts in the mansion's NW room, crosses into the west
		# wing, crosses again into the central parlor, then rings three
		# more parlor corners before dropping onto the safe left of the
		# door. The parlor's east doorway is an archway too so no swung
		# panel can cut a leg along that wall.
		"name": "parlor_ring",
		"emitter": Vector3(-13.17, 0, 6.83),
		"emitter_yaw": -60.0,
		"maze_cell": Vector2i(1, 1),
		"mirrors": [
			Vector3(-6.83, 0, 3.17), Vector3(-6.83, 0, -3.17), Vector3(-3.17, 0, 3.17),
			Vector3(3.17, 0, 3.17), Vector3(3.17, 0, -3.17), Vector3(-3.17, 0, -3.17),
		],
		"safe": Vector3(-2.2, 0, -4.85),
		"doors": [
			[Vector2i(0, 2), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(1, 1)],
			[Vector2i(1, 2), Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(2, 1)],
		],
	},
]
## Adjacent room pairs: the pair's FIRST room becomes the hydraulic
## press's dedicated machinery room (console + battery cage); the forced
## pair door keeps the approach corridor honest across layouts.
const VALVE_PAIR_OPTIONS := [
	[Vector2i(2, 1), Vector2i(2, 2)], [Vector2i(0, 1), Vector2i(0, 2)],
	[Vector2i(2, 0), Vector2i(2, 1)], [Vector2i(0, 0), Vector2i(0, 1)],
]
## Never the central parlor: the beam routes park mirrors in its
## corners, and the puzzle box stands on a room's south wall beside one.
const CLOCK_CELL_OPTIONS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 0)]
const DECOY_CELL_OPTIONS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
	Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
]

## Test hook: force a specific ROUTE_VARIANTS index (-1 = seeded random).
@export var route_override: int = -1

## The layout drawn for this run (read by tests and debug tools).
var active_route: Dictionary
## Seeded 4-digit front-door code (keypad + ledger notebook share it).
var front_door_pin := 0
var _valve_cells: Array = []
## Wall spots where hauled mirrors (and the decoy) were parked this run;
## furniture keeps clear of them.
var _mirror_parking: Array[Vector3] = []
## Floor spots where a misplaced prism is lying this run.
var _loose_prisms: Array[Vector3] = []
## Room the puzzle box was placed in this run (read by tests and props).
var _puzzle_box_cell := Vector2i(1, 1)
var _decoy_cell := Vector2i(2, 1)
var _keypad: Keypad
var _garage_button: GarageDoorButton
var _garage_lock_lamp: OmniLight3D
var _garage_lock_lens: StandardMaterial3D

@export_group("Dimensions")
@export var room_size: float = 10.0
@export var wall_height: float = 3.0
@export var wall_thickness: float = 0.3
@export var floor_thickness: float = 0.4
@export var door_width: float = 2.0
@export var door_height: float = 2.4

@export_group("Randomness")
@export_range(0.0, 1.0) var extra_door_chance: float = 0.35
## 0 = new random layout every run; any other value reproduces a fixed layout.
@export var rng_seed: int = 0
## Explicit seed with top priority (co-op: the host rolls one and RPCs it
## to every peer via the lobby, so all machines generate identical layouts
## — rooms, doors, props, and puzzle placement included).
@export var generation_seed: int = 0

var _rng := RandomNumberGenerator.new()
var _doors: Dictionary = {}
var _generated_root: Node3D
## Shared mesh/shape resources for repeated prop and decor sizes, so 300+
## boxes don't each allocate their own BoxMesh/BoxShape3D.
var _box_mesh_cache := {}
var _box_shape_cache := {}

const WALL_COLOR := Color(0.72, 0.68, 0.6)
var _wall_material := _make_material(WALL_COLOR)
var _floor_material := _make_material(Color(0.45, 0.38, 0.32))
var _foyer_material := _make_material(Color(0.55, 0.42, 0.28))
var _vault_material := _make_material(Color(0.4, 0.32, 0.5))
var _pedestal_material := _make_material(Color(0.42, 0.38, 0.34))
var _crate_material := _make_material(Color(0.55, 0.4, 0.24))
var _shelf_material := _make_material(Color(0.3, 0.2, 0.13))
var _table_material := _make_material(Color(0.45, 0.3, 0.18))
var _grass_material := _make_material(Color(0.1, 0.16, 0.09))
var _cobble_material := _make_material(Color(0.35, 0.36, 0.4))
var _gravel_material := _make_material(Color(0.3, 0.28, 0.26))
var _iron_material := _make_material(Color(0.13, 0.13, 0.16))
var _stone_material := _make_material(Color(0.45, 0.45, 0.48))
var _hedge_material := _make_material(Color(0.16, 0.32, 0.16))
var _pine_material := _make_material(Color(0.1, 0.25, 0.14))
var _autumn_material := _make_material(Color(0.55, 0.3, 0.12))
var _trunk_material := _make_material(Color(0.3, 0.2, 0.12))
var _rug_material := _make_material(Color(0.42, 0.14, 0.16))
var _lantern_glass_material := _make_glow_material(Color(1.0, 0.75, 0.4), 1.8)
var _window_material := _make_glow_material(Color(1.0, 0.7, 0.3), 1.2)
var _ember_glow_material := _make_glow_material(Color(1.0, 0.45, 0.15), 2.2)


func _ready() -> void:
	generate()


func generate() -> void:
	if _generated_root:
		_generated_root.queue_free()
	_generated_root = Node3D.new()
	_generated_root.name = "Generated"
	add_child(_generated_root)
	_door_counter = 0
	# Per-run placement state must not leak into a second generate() —
	# stale spots would keep blocking furniture in rooms that no longer
	# hold anything.
	_mirror_parking.clear()
	_loose_prisms.clear()
	PlayerNotes.clear()  # fresh run, fresh notebook

	var chosen_seed := generation_seed
	if chosen_seed == 0:
		chosen_seed = NetworkSession.run_seed
	if chosen_seed == 0:
		chosen_seed = rng_seed
	if chosen_seed != 0:
		_rng.seed = chosen_seed
	else:
		_rng.randomize()

	_pick_run_layout()
	_carve_doors()
	_build_geometry()
	_spawn_puzzle()
	_spawn_doors()
	_spawn_entrance()
	_spawn_props()
	_spawn_shrouds()
	_spawn_interior_atmosphere()
	_spawn_estate()
	generated.emit()


func get_room_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - 1) * room_size, 0.0, (cell.y - 1) * room_size)


## The run opens on the cobble walkway just inside the estate gate, the
## mansion up the path ahead (co-op partners spawn a step apart).
func get_spawn_position() -> Vector3:
	return Vector3(0.0, 0.1, 31.0)


## Draw this run's structural layout from the seeded rng: laser route,
## valve rooms, puzzle box location, and the decoy's spot.
## Combined with door carving, wiring, and spawn rotations, no two seeds
## play the same.
func _pick_run_layout() -> void:
	var picked: Dictionary
	if route_override >= 0 and route_override < ROUTE_VARIANTS.size():
		picked = ROUTE_VARIANTS[route_override]
	else:
		picked = ROUTE_VARIANTS[_rng.randi_range(0, ROUTE_VARIANTS.size() - 1)]
	active_route = picked.duplicate()
	active_route["solutions"] = _route_solutions(picked)
	var maze: Vector2i = active_route["maze_cell"]
	# Every room this run's beam actually passes through — not just
	# maze_cell, which only ever named the route's "main" room. A route
	# can detour through 2-3 rooms (see ROUTE_VARIANTS), and the press
	# console, battery cage, and puzzle box must never land in any of
	# them: heavy furniture in a beam room risks blocking or visually
	# burying the laser line.
	var route_cells := _route_room_cells(active_route)

	var pair_options: Array = VALVE_PAIR_OPTIONS.filter(
		func(pair: Array) -> bool: return not (pair[0] in route_cells or pair[1] in route_cells))
	_valve_cells = pair_options[_rng.randi_range(0, pair_options.size() - 1)]

	front_door_pin = _rng.randi_range(1000, 9999)

	var decoy_options: Array = DECOY_CELL_OPTIONS.filter(
		func(cell: Vector2i) -> bool:
			# Never park the decoy mirror on the live beam corridor — at a
			# room center it can swallow the beam before the real mirrors.
			return not cell in route_cells and not _near_beam_path(get_room_center(cell)))
	_decoy_cell = decoy_options[_rng.randi_range(0, decoy_options.size() - 1)]


## Distinct grid cells an active route's beam actually travels through:
## the emitter, every mirror, and the safe, each mapped to its room cell
## via _cell_of() (defined below, shared with mirror-parking spacing).
func _route_room_cells(route: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var pts: Array = [route["emitter"]] + (route["mirrors"] as Array) + [route["safe"]]
	for p in pts:
		var cell := _cell_of(p)
		if not cell in cells:
			cells.append(cell)
	return cells


## Solved root yaw (degrees) for each of a route's mirrors, derived from
## the beam geometry: the panel is mounted at +45 deg on the root and its
## normal must bisect the incoming and outgoing legs. With every leg on
## the 30-degree grid the results land on 15-degree detents (asserted).
static func _route_solutions(route: Dictionary) -> Array:
	var pts: Array = [route["emitter"]] + (route["mirrors"] as Array) + [route["safe"]]
	var solutions: Array = []
	for i in (route["mirrors"] as Array).size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var c: Vector3 = pts[i + 2]
		var d_in := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var d_out := Vector3(c.x - b.x, 0, c.z - b.z).normalized()
		var n := (d_out - d_in).normalized()
		# Panel normal in world = (sin(45+yaw), 0, cos(45+yaw)).
		var yaw := rad_to_deg(atan2(n.x, n.z)) - 45.0
		yaw = fposmod(yaw, 180.0)
		var detent := roundf(yaw / 15.0) * 15.0
		assert(absf(yaw - detent) < 0.05, "route %s mirror %d solution %.2f is off the 15-degree grid" % [route["name"], i, yaw])
		solutions.append(detent)
	return solutions


## True when `point` lies within 1.5 m of any segment of the active
## route's solved beam path (emitter -> mirrors -> receiver, ground plane).
func _near_beam_path(point: Vector3) -> bool:
	var flat := Vector3(point.x, 0, point.z)
	var pts: Array = [active_route["emitter"]] + (active_route["mirrors"] as Array) + [active_route["safe"]]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var closest := Geometry3D.get_closest_point_to_segment(
			flat, Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
		if closest.distance_to(flat) < 1.5:
			return true
	return false


# --- Door layout ---------------------------------------------------------


func _carve_doors() -> void:
	_doors.clear()
	var visited := {FOYER_CELL: true}
	var stack: Array[Vector2i] = [FOYER_CELL]
	while not stack.is_empty():
		var cell: Vector2i = stack.back()
		var unvisited: Array[Vector2i] = []
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + offset
			if _in_grid(next) and next != VAULT_STUDY_CELL and not visited.has(next):
				unvisited.append(next)
		if unvisited.is_empty():
			stack.pop_back()
		else:
			var next: Vector2i = unvisited[_rng.randi_range(0, unvisited.size() - 1)]
			visited[next] = true
			_doors[_edge_key(cell, next)] = true
			stack.push_back(next)

	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var next := cell + offset
				if not _in_grid(next):
					continue
				if cell == VAULT_STUDY_CELL or next == VAULT_STUDY_CELL:
					continue
				var key := _edge_key(cell, next)
				if not _doors.has(key) and _rng.randf() < extra_door_chance:
					_doors[key] = true

	# Force this run's route doors, the vault doorway, and the hydraulic
	# pair's connecting door open, whatever the random rolls decided.
	var forced: Array = []
	forced.append_array(active_route["doors"])
	forced.append([Vector2i(1, 1), VAULT_STUDY_CELL])
	forced.append(_valve_cells)
	for edge in forced:
		_doors[_edge_key(edge[0], edge[1])] = true


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE.x and cell.y >= 0 and cell.y < GRID_SIZE.y


func _has_door(a: Vector2i, b: Vector2i) -> bool:
	return _in_grid(a) and _in_grid(b) and _doors.has(_edge_key(a, b))


func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var tmp := a
		a = b
		b = tmp
	return "%s-%s" % [a, b]


# --- Geometry ------------------------------------------------------------


func _build_geometry() -> void:
	var csg := CSGCombiner3D.new()
	csg.name = "Structure"
	csg.use_collision = true
	_generated_root.add_child(csg)

	# 60x60 estate lawn, slightly below the interior floors.
	var lawn := CSGBox3D.new()
	# 100x100 grounds: the fenced yard plus the wooded belt around it.
	lawn.size = Vector3(100, 0.4, 100)
	lawn.position = Vector3(0, -0.22, 5)
	lawn.material = _grass_material
	csg.add_child(lawn)

	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			var center := get_room_center(cell)
			_add_floor(csg, cell, center)
			if x == 0:
				_add_wall(center + Vector3(-room_size / 2.0, 0, 0), false, false)
			if z == 0:
				_add_wall(center + Vector3(0, 0, -room_size / 2.0), true, false)
			var east := cell + Vector2i(1, 0)
			_add_wall(center + Vector3(room_size / 2.0, 0, 0), false, _has_door(cell, east))
			var south := cell + Vector2i(0, 1)
			var south_door := _has_door(cell, south) or cell == FOYER_CELL
			_add_wall(center + Vector3(0, 0, room_size / 2.0), true, south_door)

	_add_corner_posts(csg)

	# Stone porch slab and cobblestone walkway to the estate gate.
	var porch := CSGBox3D.new()
	porch.size = Vector3(room_size + 2.0, floor_thickness, room_size + 0.6)
	porch.position = get_room_center(FOYER_CELL) + Vector3(0, -floor_thickness / 2.0, room_size + 0.1)
	porch.material = _cobble_material
	csg.add_child(porch)

	var walkway := CSGBox3D.new()
	walkway.size = Vector3(2.6, 0.4, 7.8)
	walkway.position = Vector3(0, -0.18, 29.3)
	walkway.material = _cobble_material
	csg.add_child(walkway)

	var gravel := CSGBox3D.new()
	gravel.size = Vector3(5.5, 0.36, 8.5)
	gravel.position = Vector3(9.5, -0.21, 28.5)
	gravel.material = _gravel_material
	csg.add_child(gravel)

	# Gravel driveway running from the estate gate out to the lane at the
	# edge of the woods, with two darker wheel ruts.
	var drive := CSGBox3D.new()
	drive.size = Vector3(4.6, 0.36, 18.0)
	drive.position = Vector3(0, -0.2, 42.2)
	drive.material = _gravel_material
	csg.add_child(drive)
	var rut_material := _make_material(Color(0.24, 0.22, 0.2))
	for rx in [-1.1, 1.1]:
		var rut := CSGBox3D.new()
		rut.size = Vector3(0.5, 0.37, 17.6)
		rut.position = Vector3(rx, -0.2, 42.2)
		rut.material = rut_material
		csg.add_child(rut)
	# The lane the driveway meets: a packed-dirt road across the south edge.
	var lane := CSGBox3D.new()
	lane.size = Vector3(90, 0.35, 5.0)
	lane.position = Vector3(0, -0.21, 52.5)
	lane.material = rut_material
	csg.add_child(lane)


func _add_floor(parent: Node3D, cell: Vector2i, center: Vector3) -> void:
	var floor_box := CSGBox3D.new()
	var span := room_size + wall_thickness
	floor_box.size = Vector3(span, floor_thickness, span)
	floor_box.position = center + Vector3(0, -floor_thickness / 2.0, 0)
	match cell:
		FOYER_CELL:
			floor_box.material = _foyer_material
		VAULT_STUDY_CELL:
			floor_box.material = _vault_material
		_:
			floor_box.material = _floor_material
	parent.add_child(floor_box)


func _add_wall(edge_center: Vector3, along_x: bool, with_door: bool) -> void:
	var wall := CSGBox3D.new()
	var length := room_size - wall_thickness
	if along_x:
		wall.size = Vector3(length, wall_height, wall_thickness)
	else:
		wall.size = Vector3(wall_thickness, wall_height, length)
	wall.position = edge_center + Vector3(0, wall_height / 2.0, 0)
	wall.use_collision = true
	# Walls start fully opaque (opaque render pass); the player's fade
	# logic switches a material to TRANSPARENCY_ALPHA only while fading.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WALL_COLOR
	wall.material = mat
	wall.add_to_group("fade_walls")
	_generated_root.add_child(wall)
	if with_door:
		var hole := CSGBox3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		var cut_depth := wall_thickness + 0.1
		if along_x:
			hole.size = Vector3(door_width, door_height, cut_depth)
		else:
			hole.size = Vector3(cut_depth, door_height, door_width)
		hole.position = Vector3(0, (door_height - wall_height) / 2.0, 0)
		hole.material = mat
		wall.add_child(hole)


## Standalone camera-fading wall (outbuildings): same contract as the
## mansion's room walls — CSG with its own material, in "fade_walls".
func _add_fade_wall(at: Vector3, size: Vector3) -> void:
	var wall := CSGBox3D.new()
	wall.size = size
	wall.position = at
	wall.use_collision = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WALL_COLOR
	wall.material = mat
	wall.add_to_group("fade_walls")
	_generated_root.add_child(wall)


func _add_corner_posts(parent: Node3D) -> void:
	for gz in GRID_SIZE.y + 1:
		for gx in GRID_SIZE.x + 1:
			var post := CSGBox3D.new()
			post.size = Vector3(wall_thickness, wall_height, wall_thickness)
			post.position = Vector3(
				(gx - 1.5) * room_size, wall_height / 2.0, (gz - 1.5) * room_size)
			post.material = _wall_material
			parent.add_child(post)


# --- Puzzles -------------------------------------------------------------


func _spawn_puzzle() -> void:
	# NOTE: interactive nodes get deterministic names so RPC node paths
	# resolve identically on every co-op peer.
	var emitter := LIGHT_EMITTER_SCENE.instantiate() as Node3D
	emitter.name = "Emitter"
	emitter.position = active_route["emitter"]
	# Routes may aim the emitter off the default -Z (north) heading.
	emitter.rotation.y = deg_to_rad(active_route.get("emitter_yaw", 0.0))
	_generated_root.add_child(emitter)

	# The emitter starts dead: its Heavy Battery waits inside the hydraulic
	# press's pressure-locked cage (spawned with the press further down)
	# and must be carried to the cradle before the laser fires.
	var battery := BIG_BATTERY_SCENE.instantiate() as Grabbable
	battery.name = "HeavyBattery"
	_generated_root.add_child(battery)

	# World spots the mirrors' wall placement must keep clear of (the
	# puzzle box, press, and cage are appended as they spawn below).
	var reserved: Array[Vector3] = [active_route["emitter"], active_route["safe"]]

	# The wall safe beside the vault doorway is the beam's target: the
	# laser cracks it, the lever inside opens the gate. Untyped so the
	# script-added properties resolve post-set_script.
	var safe = StaticBody3D.new()
	safe.name = "WallSafe"
	safe.set_script(LASER_SAFE_SCRIPT)
	safe.position = active_route["safe"]
	_generated_root.add_child(safe)
	safe.puzzle_completed.connect(func() -> void: puzzle_solved.emit())

	var door := VAULT_DOOR_SCENE.instantiate() as VaultDoor
	door.name = "VaultGate"
	door.position = (get_room_center(Vector2i(1, 1)) + get_room_center(VAULT_STUDY_CELL)) / 2.0
	_generated_root.add_child(door)
	safe.puzzle_completed.connect(door.on_light_puzzle_completed)

	# Hydraulic press console in its own dedicated machinery room; [E]
	# opens the fullscreen control-panel minigame. Counts, PSI values, and
	# the target are seeded so every co-op peer builds an identical machine
	# with identical node paths. Untyped so script-added properties resolve
	# dynamically post-set_script (garage-button pattern).
	var machine = StaticBody3D.new()
	machine.name = "PressureMachine"
	machine.set_script(PRESSURE_MACHINE_SCRIPT)
	machine.small_point_count = _rng.randi_range(1, 3)
	machine.big_point_count = _rng.randi_range(1, 2)
	var pressures := _roll_valve_pressures()
	machine.valve_pressures = pressures
	machine.target_psi = _roll_target_psi(pressures)
	var press_room := get_room_center(_valve_cells[0])
	# Against the north wall, hard up beside the battery cage's west wall
	# (cage x 2.36..4.74), so the console stands right next to the
	# hydraulic gate it controls. Faces into the room.
	machine.position = press_room + Vector3(1.3, 0, -4.35)
	_generated_root.add_child(machine)
	reserved.append(machine.position)
	# The vault gate's right-hand lamp now tracks the hydraulics.
	machine.puzzle_solved.connect(door.on_hydraulics_ready)

	# Battery cage flush in the SAME room's NE corner: three camera-fading
	# walls, sealed by the hydraulic gate until the press balances. The
	# Heavy Battery sits inside, visible as the reward from the console.
	var cage := press_room + Vector3(3.55, 0, -3.55)
	reserved.append(cage)
	reserved.append(cage + Vector3(0, 0, 1.1))  # the gate and its approach
	_add_fade_wall(cage + Vector3(0, 1.15, -1.19), Vector3(2.56, 2.3, 0.18))
	_add_fade_wall(cage + Vector3(-1.19, 1.15, 0), Vector3(0.18, 2.3, 2.2))
	_add_fade_wall(cage + Vector3(1.19, 1.15, 0), Vector3(0.18, 2.3, 2.2))
	var hydraulic_gate := HydraulicDoor.new()
	hydraulic_gate.name = "HydraulicGate"
	hydraulic_gate.position = cage + Vector3(0, 0, 1.1)
	_generated_root.add_child(hydraulic_gate)
	machine.puzzle_solved.connect(hydraulic_gate.activate)
	battery.position = cage + Vector3(0, 0.4, -0.25)

	# Puzzle box flush against its room's south wall (back at the wall's
	# inner face, clear of the x -1..1 door gap), facing north into the
	# room; the Brass Wrench is stashed inside until the dial-and-lever
	# sequence unlocks it. Untyped so the script-added properties resolve
	# dynamically post-set_script (garage-button pattern).
	var box_route_cells := _route_room_cells(active_route)
	var puzzle_box_cell_options: Array = CLOCK_CELL_OPTIONS.filter(
		func(cell: Vector2i) -> bool: return not cell in box_route_cells and cell != _valve_cells[0])
	_puzzle_box_cell = puzzle_box_cell_options[_rng.randi_range(0, puzzle_box_cell_options.size() - 1)]
	var puzzle_box = StaticBody3D.new()
	puzzle_box.name = "PuzzleBox"
	puzzle_box.set_script(PUZZLE_BOX_SCRIPT)
	puzzle_box.position = get_room_center(_puzzle_box_cell) + Vector3(-3.0, 0, room_size / 2.0 - wall_thickness / 2.0 - 0.4)
	puzzle_box.rotation.y = PI
	_generated_root.add_child(puzzle_box)
	reserved.append(puzzle_box.position)
	var wrench := BRASS_WRENCH_SCENE.instantiate() as Grabbable
	wrench.name = "Wrench"
	puzzle_box.stash_item(wrench)

	_spawn_mirrors(reserved)

	_build_pedestal(get_room_center(VAULT_STUDY_CELL))
	var will := WILL_ITEM_SCENE.instantiate() as Node3D
	will.name = "Will"
	will.position = get_room_center(VAULT_STUDY_CELL) + Vector3(0, 1.05, 0)
	_generated_root.add_child(will)

	_build_exit_zone()


## Room-local wall spots a standing mirror can be parked at: hugging each
## wall, clear of every door gap (x/z -1..1), the north-wall shelves
## (x ±2.6..4.4), the NW lamp table, and the crate spots.
const PERIMETER_SPOTS: Array[Vector3] = [
	Vector3(-2.0, 0, -4.0), Vector3(2.0, 0, -4.0),   # north wall
	Vector3(-2.2, 0, 4.0), Vector3(2.2, 0, 4.0),     # south wall
	Vector3(-4.0, 0, -2.0), Vector3(-4.0, 0, 2.0),   # west wall
	Vector3(4.0, 0, -2.0), Vector3(4.0, 0, 2.0),     # east wall
]
## Minimum clearance between a parked mirror and anything reserved, and
## the tighter one against other mirrors' beam spots (two slim mirrors
## only need a metre between centers).
const MIRROR_CLEARANCE := 1.7
const MIRROR_TO_MIRROR := 1.15


func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / room_size) + 1, roundi(pos.z / room_size) + 1)


## Route mirrors at free random 15-degree detents (closed doors block the
## beam anyway, so no spawn can pre-solve the circuit). A seeded subset
## are HAULED mirrors: they start parked against a wall of their room
## with a floor ring marking their beam spot, and the player must push
## them home before they can be swiveled. Always at least one of each
## kind. The decoy stands parked against a wall of its own room, off the
## beam path, useless as ever.
func _spawn_mirrors(reserved: Array[Vector3]) -> void:
	var mirror_spots: Array = active_route["mirrors"]
	var targets: Array[Vector3] = []
	for spot in mirror_spots:
		targets.append(spot)

	var hauled: Array[bool] = []
	for i in mirror_spots.size():
		hauled.append(_rng.randf() < 0.5)
	if mirror_spots.size() > 1:
		if not hauled.has(true):
			hauled[_rng.randi_range(0, hauled.size() - 1)] = true
		if not hauled.has(false):
			hauled[_rng.randi_range(0, hauled.size() - 1)] = false

	# At least one route table's prism is MISPLACED: it spawns loose
	# somewhere else in the house and must be found and set on the table.
	var missing_count := 1 + (1 if mirror_spots.size() >= 5 and _rng.randf() < 0.4 else 0)
	var missing: Array[int] = []
	while missing.size() < missing_count:
		var idx := _rng.randi_range(0, mirror_spots.size() - 1)
		if not idx in missing:
			missing.append(idx)

	var tables: Array = []
	var any_hauled := false
	for i in mirror_spots.size():
		var target: Vector3 = mirror_spots[i]
		var mirror := ROTATING_MIRROR_SCENE.instantiate() as PrismTable
		mirror.name = "Mirror_%d" % i
		mirror.rotation.y = deg_to_rad(15.0 * float(_rng.randi_range(0, 23)))
		var parked: Array = _pick_perimeter_spot(_cell_of(target), reserved, targets) if hauled[i] else []
		if parked.is_empty():
			# Fixed on its beam spot (or no free wall spot: never break the route).
			mirror.position = target
		else:
			mirror.make_pushable(target)
			mirror.position = parked[0]
			reserved.append(parked[0])
			_mirror_parking.append(parked[0])
			any_hauled = true
		_generated_root.add_child(mirror)
		tables.append(mirror)
		if i in missing:
			_scatter_prism("Prism_%d" % i, reserved)
		else:
			_seat_new_prism(mirror, "Prism_%d" % i)
	# The seeded pick may have landed only on tables whose room has no
	# free wall spot (a beam that rings every wall leaves none). Keep the
	# "at least one hauled table" promise with the first that CAN park.
	if not any_hauled and mirror_spots.size() > 1:
		for i in mirror_spots.size():
			var target: Vector3 = mirror_spots[i]
			var parked: Array = _pick_perimeter_spot(_cell_of(target), reserved, targets)
			if parked.is_empty():
				continue
			var table: PrismTable = tables[i]
			table.convert_to_pushable(target, parked[0])
			reserved.append(parked[0])
			_mirror_parking.append(parked[0])
			break

	# Free-roaming: haulable anywhere with no ring, so it looks exactly
	# like a route table someone forgot to place. Comes with its prism.
	var decoy := ROTATING_MIRROR_SCENE.instantiate() as PrismTable
	decoy.name = "Mirror_Decoy"
	decoy.make_free()
	var decoy_spot: Array = _pick_perimeter_spot(_decoy_cell, reserved, targets)
	decoy.position = decoy_spot[0] if not decoy_spot.is_empty() else get_room_center(_decoy_cell)
	_mirror_parking.append(decoy.position)
	decoy.rotation.y = deg_to_rad(15.0 * float(_rng.randi_range(0, 23)))
	_generated_root.add_child(decoy)
	_seat_new_prism(decoy, "Prism_Decoy")


## Spawn a prism already seated on `table` (deterministic name for RPCs).
func _seat_new_prism(table: PrismTable, node_name: String) -> void:
	var prism := PRISM_SCENE.instantiate() as Grabbable
	prism.name = node_name
	_generated_root.add_child(prism)
	table.seat_prism(prism)


## Loose prism spot: a seeded room (never the vault), on the floor beside
## the south door's far jamb — clear of the swing, the corner tables, the
## wall pieces, and anything reserved.
func _scatter_prism(node_name: String, reserved: Array[Vector3]) -> void:
	var options: Array[Vector2i] = []
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			if cell != VAULT_STUDY_CELL and not cell in _valve_cells:
				options.append(cell)
	var at := Vector3.ZERO
	for attempt in 12:
		var cell: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
		var candidate := get_room_center(cell) + Vector3(1.5, 0.15, 3.55)
		var clear := true
		for r in reserved:
			if Vector2(candidate.x - r.x, candidate.z - r.z).length() < 1.4:
				clear = false
				break
		if clear:
			at = candidate
			break
	if at == Vector3.ZERO:
		at = get_room_center(FOYER_CELL) + Vector3(1.5, 0.15, 3.55)
	var prism := PRISM_SCENE.instantiate() as Grabbable
	prism.name = node_name
	prism.position = at
	prism.rotation.y = _rng.randf_range(0.0, TAU)
	_generated_root.add_child(prism)
	reserved.append(at)
	# Furniture must not be dropped on top of it (props spawn later).
	_loose_prisms.append(at)


## A seeded free wall spot in `cell`: off the beam path and at least
## MIRROR_CLEARANCE from everything reserved. Returns [pos] or [] if the
## room's walls are full.
func _pick_perimeter_spot(cell: Vector2i, reserved: Array[Vector3], targets: Array[Vector3]) -> Array:
	var center := get_room_center(cell)
	var options: Array[Vector3] = []
	for offset in PERIMETER_SPOTS:
		var p := center + offset
		if _near_beam_path(p):
			continue
		var clear := true
		for r in reserved:
			if Vector2(p.x - r.x, p.z - r.z).length() < MIRROR_CLEARANCE:
				clear = false
				break
		if clear:
			for t in targets:
				if Vector2(p.x - t.x, p.z - t.z).length() < MIRROR_TO_MIRROR:
					clear = false
					break
		if clear:
			options.append(p)
	if options.is_empty():
		return []
	return [options[_rng.randi_range(0, options.size() - 1)]]


## Five signed PSI contributions for the press's valves: seeded shuffled
## magnitudes, exactly two flipped negative — so every run needs genuine
## subset arithmetic, not just "open everything".
func _roll_valve_pressures() -> Array[int]:
	var pool: Array[int] = [5, 10, 15, 20, 25, 30, 40]
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var pressures: Array[int] = []
	for i in 5:
		pressures.append(pool[i])
	var flip_a := _rng.randi_range(0, 4)
	var flip_b := (flip_a + 1 + _rng.randi_range(0, 3)) % 5
	pressures[flip_a] = -pressures[flip_a]
	pressures[flip_b] = -pressures[flip_b]
	return pressures


## Target PSI = the sum of a seeded non-empty valve subset, so at least
## one solution always exists. Rerolled while it equals the base PSI —
## the gauge must never start on the answer.
func _roll_target_psi(pressures: Array[int]) -> int:
	while true:
		var mask := _rng.randi_range(1, 31)
		var total := 0
		for i in 5:
			if mask & (1 << i):
				total += pressures[i]
		if total != 0:
			return total
	return 0  # unreachable; single-valve masks are never zero


# --- Doors, entrance, props, shrouds -------------------------------------


## Every carved edge gets a frame; every edge but the vault's and the
## beam route's gets a hinged panel. Route doorways stay open archways so
## a swung door can never clip the diagonal beam.
func _spawn_doors() -> void:
	var vault_edge := _edge_key(Vector2i(1, 1), VAULT_STUDY_CELL)
	var archways := {}
	for edge in active_route["doors"]:
		archways[_edge_key(edge[0], edge[1])] = true
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			var center := get_room_center(cell)
			var east := cell + Vector2i(1, 0)
			var east_key := _edge_key(cell, east)
			if _has_door(cell, east) and east_key != vault_edge:
				if not archways.has(east_key):
					_spawn_hinged_door(center + Vector3(room_size / 2.0, 0, 1.0), PI / 2.0)
				_add_door_frame(center + Vector3(room_size / 2.0, 0, 0), PI / 2.0)
			var south := cell + Vector2i(0, 1)
			var south_key := _edge_key(cell, south)
			if _has_door(cell, south) and south_key != vault_edge:
				if not archways.has(south_key):
					_spawn_hinged_door(center + Vector3(-1.0, 0, room_size / 2.0), 0.0)
				_add_door_frame(center + Vector3(0, 0, room_size / 2.0), 0.0)


var _door_counter := 0


func _spawn_hinged_door(at: Vector3, yaw: float, locked := false, width := 2.0) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.name = "Door_%d" % _door_counter
	_door_counter += 1
	door.position = at
	door.rotation.y = yaw
	door.locked = locked
	door.panel_width = width
	_generated_root.add_child(door)
	return door


func _add_door_frame(at: Vector3, yaw: float) -> void:
	var frame_basis := Basis(Vector3.UP, yaw)
	var along := frame_basis.x
	for side in [-1.06, 1.06]:
		_add_decor_box(at + along * side + Vector3(0, 1.25, 0), Vector3(0.12, 2.5, 0.46), _shelf_material, yaw)
	_add_decor_box(at + Vector3(0, 2.52, 0), Vector3(2.24, 0.16, 0.46), _shelf_material, yaw)


func _spawn_entrance() -> void:
	var front_z := get_room_center(FOYER_CELL).z + room_size / 2.0
	var left := _spawn_hinged_door(Vector3(-1.0, 0, front_z), 0.0, true, 1.0)
	left.open_angle_degrees = 90.0
	var right := _spawn_hinged_door(Vector3(1.0, 0, front_z), PI, true, 1.0)
	right.open_angle_degrees = -90.0
	_add_door_frame(Vector3(0, 0, front_z), 0.0)

	var breaker := BREAKER_BOX_SCENE.instantiate() as BreakerBox
	breaker.name = "Breaker"
	breaker.wiring_seed = _rng.randi()
	# Mounted inside the detached garage (north wall, facing the room).
	breaker.position = Vector3(24.5, 0, 17.85)
	_generated_root.add_child(breaker)
	# Power no longer opens the front doors directly — it wakes the keypad
	# (and the garage door button); the doors want the 4-digit code.
	breaker.powered.connect(_on_power_restored)

	var keypad := KEYPAD_SCENE.instantiate() as Keypad
	keypad.name = "FrontKeypad"
	keypad.position = Vector3(2.4, 1.25, front_z + 0.12)
	keypad.pin_code = front_door_pin
	_generated_root.add_child(keypad)
	keypad.access_granted.connect(left.unlock_and_open)
	keypad.access_granted.connect(right.unlock_and_open)
	_keypad = keypad

	# Brass house number beside the breaker box.
	var number := Label3D.new()
	number.text = "No. 1887"
	number.font_size = 64
	number.pixel_size = 0.004
	number.modulate = Color(0.85, 0.68, 0.3)
	number.position = Vector3(4.6, 2.0, front_z + 0.2)
	_generated_root.add_child(number)


## Room dressing that reads "lived in" without ever costing a walkway.
## Every piece stands in a wall FLANK SLOT: 2.2 m either side of each
## wall's door axis, hard against the wall. Those slots are, by
## construction, clear of every door gap (|axis| < 1.2), every door's
## open-panel sweep (the hinge line at +1 on the wall), the corner mirror
## spots (|axis| > 2.67), and the straight lines from the room's center
## to each of its doors — so the middle of every room and every
## door-to-door path stays open. Slots that would collide with a puzzle
## fixture (puzzle box, press console, cage gate, keypad, parked mirrors) are
## skipped. Each room also gets one lamp table (its light source), a
## candle sconce, and paintings above the low pieces.
const FLANK_OFFSET := 2.2
## Wall slots as [wall point (local, on the wall's inner face), yaw whose
## local +Z faces into the room].
var _flank_slots: Array = []


func _build_flank_slots() -> void:
	var w := room_size / 2.0 - wall_thickness / 2.0  # inner face: 4.85
	_flank_slots = [
		[Vector3(-FLANK_OFFSET, 0, -w), 0.0], [Vector3(FLANK_OFFSET, 0, -w), 0.0],           # north wall
		[Vector3(-FLANK_OFFSET, 0, w), PI], [Vector3(FLANK_OFFSET, 0, w), PI],               # south wall
		[Vector3(-w, 0, -FLANK_OFFSET), PI / 2.0], [Vector3(-w, 0, FLANK_OFFSET), PI / 2.0], # west wall
		[Vector3(w, 0, -FLANK_OFFSET), -PI / 2.0], [Vector3(w, 0, FLANK_OFFSET), -PI / 2.0], # east wall
	]


func _spawn_props() -> void:
	_build_flank_slots()
	# World points no furniture may crowd (radius 1.2): puzzle fixtures
	# and the mirrors' wall parking spots.
	var blocked: Array[Vector3] = []
	blocked.append_array(_mirror_parking)
	blocked.append_array(_loose_prisms)
	blocked.append(get_room_center(_puzzle_box_cell) + Vector3(-3.0, 0, 4.45))
	if not _valve_cells.is_empty():
		var press_room := get_room_center(_valve_cells[0])
		blocked.append(press_room + Vector3(1.3, 0, -4.35))       # console
		blocked.append(press_room + Vector3(3.55, 0, -3.55))      # cage
		blocked.append(press_room + Vector3(3.55, 0, -2.45))      # gate
		blocked.append(press_room + Vector3(4.6, 0, -2.2))        # gate approach
	blocked.append(get_room_center(FOYER_CELL) + Vector3(2.4, 0, 4.6))  # keypad approach
	blocked.append(get_room_center(VAULT_STUDY_CELL))                   # will pedestal
	# The wall safe hangs on one of the parlor's north flank slots; keep
	# both clear so it and its beam approach stay unobstructed.
	blocked.append(Vector3(-2.2, 0, -4.85))
	blocked.append(Vector3(2.2, 0, -4.85))

	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			var center := get_room_center(cell)
			# Which slots are usable here.
			var free: Array = []
			for slot in _flank_slots:
				var world: Vector3 = center + slot[0]
				var ok := true
				for b in blocked:
					if Vector2(world.x - b.x, world.z - b.z).length() < 1.2:
						ok = false
						break
				if ok:
					free.append(slot)
			if free.is_empty():
				continue
			# Lamp table first — every room needs its light. Prefer a west
			# wall slot so the glow reads consistently room to room.
			var lamp_slot: Array = free[0]
			for slot in free:
				if slot[1] == PI / 2.0:
					lamp_slot = slot
					break
			free.erase(lamp_slot)
			_place_lamp_table(center, lamp_slot)
			# Two to four more pieces, seeded from the palette.
			var want := _rng.randi_range(2, 4)
			for i in range(free.size() - 1, 0, -1):
				var j := _rng.randi_range(0, i)
				var tmp = free[i]
				free[i] = free[j]
				free[j] = tmp
			var placed := 0
			var kinds := ["bookcase", "sideboard", "armchair", "plant", "desk", "bookcase"]
			for slot in free:
				if placed >= want:
					break
				var kind: String = kinds[_rng.randi_range(0, kinds.size() - 1)]
				if cell == FOYER_CELL and placed == 0:
					kind = "coat_rack"
				_place_wall_piece(kind, center, slot)
				placed += 1
			# A candle sconce 1.45 m off one wall's door axis (between the
			# doorway and the flank piece), on the wall face.
			var sconce_slot: Array = _flank_slots[_rng.randi_range(0, _flank_slots.size() - 1)]
			var wall_point: Vector3 = sconce_slot[0]
			if absf(wall_point.x) > 4.0:
				wall_point.z = signf(wall_point.z) * 1.45
			else:
				wall_point.x = signf(wall_point.x) * 1.45
			_add_sconce(center + wall_point, sconce_slot[1])


## Oriented placement helper: `origin` is the wall point (world), `yaw`
## turns local +Z toward the room; returns the group node to build under.
func _wall_group(origin: Vector3, yaw: float) -> Node3D:
	var group := Node3D.new()
	group.position = origin
	group.rotation.y = yaw
	_generated_root.add_child(group)
	return group


func _group_box(group: Node3D, local: Vector3, size: Vector3, mat: StandardMaterial3D, solid: bool) -> void:
	if solid:
		var body := StaticBody3D.new()
		body.position = local
		var mesh := MeshInstance3D.new()
		mesh.mesh = _get_box_mesh(size, mat)
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		col.shape = _get_box_shape(size)
		body.add_child(col)
		group.add_child(body)
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _get_box_mesh(size, mat)
		mesh.position = local
		group.add_child(mesh)


func _group_cylinder(group: Node3D, local: Vector3, radius: float, height: float, mat: StandardMaterial3D, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = mat
	mesh.mesh = cyl
	if solid:
		var body := StaticBody3D.new()
		body.position = local
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		col.shape = shape
		body.add_child(col)
		group.add_child(body)
	else:
		mesh.position = local
		group.add_child(mesh)


func _group_sphere(group: Node3D, local: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = mat
	mesh.mesh = sphere
	mesh.position = local
	group.add_child(mesh)


## Side table with a flickering oil lamp — each room's light source.
func _place_lamp_table(center: Vector3, slot: Array) -> void:
	var group := _wall_group(center + slot[0], slot[1])
	_group_box(group, Vector3(0, 0.375, 0.5), Vector3(0.9, 0.75, 0.9), _table_material, true)
	_group_cylinder(group, Vector3(0, 0.79, 0.5), 0.09, 0.08, _iron_material, false)
	_group_cylinder(group, Vector3(0, 0.95, 0.5), 0.12, 0.26, _lantern_glass_material, false)
	var light := FlickerLight.new()
	light.base_energy = 1.1
	light.light_color = Color(1.0, 0.78, 0.45)
	light.omni_range = 8.0
	light.position = Vector3(0, 1.1, 0.5)
	group.add_child(light)


## Candle sconce on the wall face: bracket, candle, small warm flicker.
func _add_sconce(at: Vector3, yaw: float) -> void:
	var group := _wall_group(at, yaw)
	_group_box(group, Vector3(0, 1.85, 0.05), Vector3(0.12, 0.3, 0.1), _iron_material, false)
	_group_cylinder(group, Vector3(0, 2.05, 0.12), 0.02, 0.16, _make_material(Color(0.95, 0.92, 0.8)), false)
	_group_sphere(group, Vector3(0, 2.15, 0.12), 0.035, _ember_glow_material)
	var light := FlickerLight.new()
	light.base_energy = 0.45
	light.light_color = Color(1.0, 0.7, 0.35)
	light.omni_range = 3.5
	light.position = Vector3(0, 2.2, 0.25)
	group.add_child(light)


## One furniture piece against a wall. Local frame: X along the wall,
## +Z into the room, wall face at z=0.
func _place_wall_piece(kind: String, center: Vector3, slot: Array) -> void:
	var group := _wall_group(center + slot[0], slot[1])
	match kind:
		"bookcase":
			_group_box(group, Vector3(0, 1.0, 0.21), Vector3(1.1, 2.0, 0.42), _shelf_material, true)
			# Rows of spines in muted leather colors.
			var spine_colors := [Color(0.45, 0.16, 0.12), Color(0.2, 0.3, 0.2), Color(0.55, 0.45, 0.25), Color(0.25, 0.2, 0.4)]
			for row in 4:
				var y := 0.35 + 0.42 * row
				var bx := -0.45
				while bx < 0.42:
					var bw := _rng.randf_range(0.05, 0.11)
					var bh := _rng.randf_range(0.22, 0.32)
					var col: Color = spine_colors[_rng.randi_range(0, spine_colors.size() - 1)]
					_group_box(group, Vector3(bx + bw / 2.0, y + bh / 2.0, 0.28), Vector3(bw, bh, 0.22), _make_material(col), false)
					bx += bw + 0.01
				_group_box(group, Vector3(0, y - 0.02, 0.21), Vector3(1.06, 0.03, 0.4), _shelf_material, false)
		"sideboard":
			_group_box(group, Vector3(0, 0.425, 0.24), Vector3(1.2, 0.85, 0.48), _table_material, true)
			_group_box(group, Vector3(0, 0.45, 0.49), Vector3(1.1, 0.5, 0.02), _shelf_material, false)
			# A vase or a pair of candlesticks on top.
			if _rng.randf() < 0.5:
				_group_cylinder(group, Vector3(0.25, 0.98, 0.24), 0.08, 0.26, _make_material(Color(0.25, 0.4, 0.55)), false)
				_group_sphere(group, Vector3(0.25, 1.15, 0.24), 0.11, _hedge_material)
			else:
				for cx in [-0.3, 0.3]:
					_group_cylinder(group, Vector3(cx, 0.95, 0.24), 0.03, 0.2, _make_material(Color(0.8, 0.65, 0.3), 0.7, 0.35), false)
					_group_cylinder(group, Vector3(cx, 1.13, 0.24), 0.02, 0.16, _make_material(Color(0.95, 0.92, 0.8)), false)
			_place_painting(group, 1.75)
		"armchair":
			# Seat, back against the wall, two arms; upholstered in the rug red.
			_group_box(group, Vector3(0, 0.22, 0.45), Vector3(0.8, 0.44, 0.8), _rug_material, true)
			_group_box(group, Vector3(0, 0.72, 0.1), Vector3(0.8, 0.56, 0.2), _rug_material, true)
			for ax in [-0.35, 0.35]:
				_group_box(group, Vector3(ax, 0.55, 0.45), Vector3(0.1, 0.22, 0.8), _table_material, false)
			_place_painting(group, 1.7)
		"plant":
			_group_cylinder(group, Vector3(0, 0.25, 0.4), 0.24, 0.5, _pedestal_material, true)
			_group_sphere(group, Vector3(0, 0.85, 0.4), 0.42, _hedge_material)
			_group_sphere(group, Vector3(0.22, 1.05, 0.5), 0.26, _pine_material)
		"desk":
			_group_box(group, Vector3(0, 0.39, 0.29), Vector3(1.1, 0.78, 0.58), _table_material, true)
			_group_box(group, Vector3(-0.2, 0.795, 0.3), Vector3(0.28, 0.03, 0.2), _make_material(Color(0.9, 0.86, 0.75)), false)
			_group_cylinder(group, Vector3(0.3, 0.9, 0.25), 0.03, 0.2, _iron_material, false)
			# Stool tucked under the front edge (decor only).
			_group_box(group, Vector3(0.1, 0.22, 0.6), Vector3(0.4, 0.44, 0.4), _shelf_material, false)
			_place_painting(group, 1.7)
		"coat_rack":
			_group_cylinder(group, Vector3(0, 0.9, 0.35), 0.035, 1.8, _shelf_material, true)
			_group_cylinder(group, Vector3(0, 0.03, 0.35), 0.28, 0.06, _shelf_material, false)
			for hook_yaw in [0.0, 1.5, 3.1, 4.6]:
				var offset := Basis(Vector3.UP, hook_yaw) * Vector3(0.12, 0, 0)
				_group_box(group, Vector3(offset.x, 1.72, 0.35 + offset.z), Vector3(0.05, 0.05, 0.05), _iron_material, false)
			# A hung coat and a hat.
			_group_box(group, Vector3(0.14, 1.25, 0.35), Vector3(0.28, 0.85, 0.16), _make_material(Color(0.2, 0.18, 0.2)), false)
			_group_cylinder(group, Vector3(-0.1, 1.86, 0.35), 0.11, 0.1, _make_material(Color(0.15, 0.13, 0.12)), false)


## Framed painting on the wall face above a piece: gold frame, dark
## canvas with a muted landscape band. Decor only.
func _place_painting(group: Node3D, y: float) -> void:
	if _rng.randf() < 0.35:
		return
	_group_box(group, Vector3(0, y, 0.03), Vector3(0.96, 0.72, 0.05), _make_material(Color(0.8, 0.62, 0.28), 0.6, 0.4), false)
	var canvases := [Color(0.22, 0.28, 0.36), Color(0.35, 0.28, 0.2), Color(0.18, 0.3, 0.24)]
	var canvas: Color = canvases[_rng.randi_range(0, canvases.size() - 1)]
	_group_box(group, Vector3(0, y, 0.06), Vector3(0.84, 0.6, 0.02), _make_material(canvas), false)
	_group_box(group, Vector3(0, y - 0.1, 0.07), Vector3(0.84, 0.16, 0.015), _make_material(canvas.lightened(0.25)), false)


func _add_prop(at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var mesh := MeshInstance3D.new()
	mesh.mesh = _get_box_mesh(size, material)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	col.shape = _get_box_shape(size)
	body.add_child(col)
	_generated_root.add_child(body)


func _add_decor_box(at: Vector3, size: Vector3, material: StandardMaterial3D, yaw := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _get_box_mesh(size, material)
	mesh.position = at
	mesh.rotation.y = yaw
	_generated_root.add_child(mesh)


func _get_box_mesh(size: Vector3, material: StandardMaterial3D) -> BoxMesh:
	if not _box_mesh_cache.has(material):
		_box_mesh_cache[material] = {}
	var by_size: Dictionary = _box_mesh_cache[material]
	if not by_size.has(size):
		var box := BoxMesh.new()
		box.size = size
		box.material = material
		by_size[size] = box
	return by_size[size]


func _get_box_shape(size: Vector3) -> BoxShape3D:
	if not _box_shape_cache.has(size):
		var shape := BoxShape3D.new()
		shape.size = size
		_box_shape_cache[size] = shape
	return _box_shape_cache[size]


func _spawn_shrouds() -> void:
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var shroud := ROOM_SHROUD_SCENE.instantiate() as RoomShroud
			shroud.room_extent = room_size
			shroud.lit_energy = 0.35
			shroud.position = get_room_center(Vector2i(x, z))
			_generated_root.add_child(shroud)


func _build_pedestal(at: Vector3) -> void:
	var pedestal := StaticBody3D.new()
	pedestal.name = "WillPedestal"
	pedestal.position = at
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.42
	cyl.height = 0.9
	cyl.material = _pedestal_material
	mesh.mesh = cyl
	mesh.position = Vector3(0, 0.45, 0)
	pedestal.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = 0.9
	shape.radius = 0.42
	col.shape = shape
	col.position = Vector3(0, 0.45, 0)
	pedestal.add_child(col)
	_generated_root.add_child(pedestal)


func _build_exit_zone() -> void:
	var zone := Area3D.new()
	zone.name = "ExitZone"
	zone.add_to_group("exit_zones")
	zone.position = get_room_center(FOYER_CELL) + Vector3(0, 1.25, room_size / 2.0 + 1.5)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.5, 2.4)
	col.shape = box
	zone.add_child(col)
	_generated_root.add_child(zone)


# --- Interior atmosphere -------------------------------------------------


func _spawn_interior_atmosphere() -> void:
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			var center := get_room_center(cell)

			# Drifting dust motes (the lamp tables live in _spawn_props).
			_add_particles(center + Vector3(0, 1.6, 0), 20, Vector3(8, 2.4, 8),
				0.02, 0.1, Vector3.ZERO, 0.012, Color(1, 0.95, 0.8), 0.22, 6.0)

			# Baseboard trim along each wall.
			var inset := room_size / 2.0 - 0.22
			_add_decor_box(center + Vector3(0, 0.075, -inset), Vector3(room_size - 0.5, 0.15, 0.06), _shelf_material)
			_add_decor_box(center + Vector3(0, 0.075, inset), Vector3(room_size - 0.5, 0.15, 0.06), _shelf_material)
			_add_decor_box(center + Vector3(-inset, 0.075, 0), Vector3(0.06, 0.15, room_size - 0.5), _shelf_material)
			_add_decor_box(center + Vector3(inset, 0.075, 0), Vector3(0.06, 0.15, room_size - 0.5), _shelf_material)

	# Area rugs in the foyer, both parlors, and a seeded scatter of others.
	var rug_cells: Array[Vector2i] = [FOYER_CELL]
	for cell: Vector2i in [_puzzle_box_cell, PARLOR_CELL]:
		if not cell in rug_cells:
			rug_cells.append(cell)
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			if not cell in rug_cells and cell != VAULT_STUDY_CELL and _rng.randf() < 0.4:
				rug_cells.append(cell)
	for cell in rug_cells:
		_add_decor_box(get_room_center(cell) + Vector3(0, 0.012, 0), Vector3(3.2, 0.02, 2.2), _rug_material)

	# Fireplace in the north-east parlor: stone surround, glowing hearth,
	# rising embers, flickering light.
	var hearth := get_room_center(PARLOR_CELL) + Vector3(0, 0, -4.35)
	_add_prop(hearth + Vector3(0, 0.7, 0), Vector3(1.6, 1.4, 0.5), _stone_material)
	_add_decor_box(hearth + Vector3(0, 0.5, 0.28), Vector3(0.8, 0.7, 0.08), _ember_glow_material)
	_add_particles(hearth + Vector3(0, 0.6, 0.4), 16, Vector3(0.7, 0.2, 0.2),
		0.2, 0.5, Vector3(0, 0.9, 0), 0.02, Color(1.0, 0.55, 0.2), 0.7, 1.6)
	var fire_light := FlickerLight.new()
	fire_light.base_energy = 0.8
	fire_light.light_color = Color(1.0, 0.55, 0.25)
	fire_light.omni_range = 5.0
	fire_light.position = hearth + Vector3(0, 0.9, 0.5)
	_generated_root.add_child(fire_light)


# --- Estate exterior -----------------------------------------------------


func _spawn_estate() -> void:
	var front_z := get_room_center(FOYER_CELL).z + room_size / 2.0  # 15

	# Open-beam portico: four stone pillars and edge beams (no solid roof,
	# so the isometric camera keeps sight of the porch).
	for px in [-5.2, 5.2]:
		_add_prop(Vector3(px, 1.55, front_z + 1.3), Vector3(0.32, 3.1, 0.32), _stone_material)
		_add_prop(Vector3(px, 1.55, front_z + 9.2), Vector3(0.32, 3.1, 0.32), _stone_material)
		_add_decor_box(Vector3(px, 3.25, front_z + 5.25), Vector3(0.4, 0.25, 8.4), _iron_material)
	_add_decor_box(Vector3(0, 3.25, front_z + 9.2), Vector3(10.8, 0.25, 0.4), _iron_material)
	for hx in [-3.0, 3.0]:
		_add_decor_box(Vector3(hx, 2.98, front_z + 9.2), Vector3(0.04, 0.5, 0.04), _iron_material)
		_add_decor_box(Vector3(hx, 2.6, front_z + 9.2), Vector3(0.24, 0.32, 0.24), _lantern_glass_material)
		var hang := FlickerLight.new()
		hang.base_energy = 0.8
		hang.light_color = Color(1.0, 0.78, 0.45)
		hang.omni_range = 5.5
		hang.position = Vector3(hx, 2.55, front_z + 9.2)
		_generated_root.add_child(hang)

	# Porch dressing: rocking chair, firewood stack, potted ferns.
	_add_decor_box(Vector3(-3.6, 0.45, 22.8), Vector3(0.55, 0.1, 0.5), _table_material, 0.5)
	_add_decor_box(Vector3(-3.78, 0.85, 22.66), Vector3(0.55, 0.75, 0.08), _table_material, 0.5)
	_add_decor_box(Vector3(-3.6, 0.22, 22.8), Vector3(0.5, 0.44, 0.44), _shelf_material, 0.5)
	for i in 5:
		var fx := 5.2 + (i % 3) * 0.2 - 0.2
		var fy := 0.1 + float(i / 3) * 0.17
		_add_decor_cylinder(Vector3(fx, fy, 23.5), 0.09, 0.6, _trunk_material, true)
	for fern_x in [-5.1, 5.1]:
		_add_decor_cylinder(Vector3(fern_x, 0.15, front_z + 1.6), 0.22, 0.3, _pedestal_material, false)
		_add_decor_sphere(Vector3(fern_x, 0.55, front_z + 1.6), 0.42, _hedge_material)

	# Glowing stained-glass windows with shutters on the mansion facade.
	# (No window at +2.4 — the front-door keypad hangs there.)
	for wx in [-2.4, -10.0, 10.0]:
		_add_decor_box(Vector3(wx, 1.6, front_z + 0.2), Vector3(0.9, 1.2, 0.08), _window_material)
		_add_decor_box(Vector3(wx - 0.62, 1.6, front_z + 0.19), Vector3(0.25, 1.2, 0.06), _shelf_material)
		_add_decor_box(Vector3(wx + 0.62, 1.6, front_z + 0.19), Vector3(0.25, 1.2, 0.06), _shelf_material)

	# Cobble steps off the walkway (visual only — no collision snags).
	_add_decor_box(Vector3(0, -0.02, 25.55), Vector3(3.0, 0.1, 0.5), _cobble_material)
	_add_decor_box(Vector3(0, -0.06, 26.05), Vector3(3.0, 0.1, 0.5), _cobble_material)

	# Wrought-iron estate fence with a locked Victorian gate (gargoyles on
	# the stone pillars), hedges inside, pines behind.
	_add_prop(Vector3(-15.85, 0.6, 33), Vector3(28.3, 1.2, 0.1), _iron_material)
	_add_prop(Vector3(15.85, 0.6, 33), Vector3(28.3, 1.2, 0.1), _iron_material)
	_add_prop(Vector3(30, 0.6, 24), Vector3(0.1, 1.2, 18), _iron_material)
	_add_prop(Vector3(-30, 0.6, 24), Vector3(0.1, 1.2, 18), _iron_material)
	for gx in [-0.85, 0.85]:
		_add_prop(Vector3(gx, 1.1, 33), Vector3(1.7, 2.2, 0.12), _iron_material)
	for px in [-2.15, 2.15]:
		_add_prop(Vector3(px, 1.1, 33), Vector3(0.9, 2.2, 0.9), _stone_material)
		_add_gargoyle(Vector3(px, 2.2, 33))

	_add_prop(Vector3(-15.85, 0.55, 32.2), Vector3(27.5, 1.1, 0.9), _hedge_material)
	_add_prop(Vector3(15.85, 0.55, 32.2), Vector3(27.5, 1.1, 0.9), _hedge_material)
	_add_prop(Vector3(29.2, 0.55, 23.5), Vector3(0.9, 1.1, 16.5), _hedge_material)
	_add_prop(Vector3(-29.2, 0.55, 23.5), Vector3(0.9, 1.1, 16.5), _hedge_material)
	# Natural blockers so the yard funnels between gate, walkway, and porch.
	_add_prop(Vector3(22.5, 0.8, 15.3), Vector3(15, 1.6, 1.1), _hedge_material)
	_add_prop(Vector3(-22.5, 0.8, 15.3), Vector3(15, 1.6, 1.1), _hedge_material)

	# Woods all round the estate (see _spawn_woods), lanterns flanking the
	# gate on the driveway side.
	_spawn_woods()
	for lx in [-3.4, 3.4]:
		_add_lantern(Vector3(lx, 0, 36.5), 2.0)

	# Antique steam roadster on the gravel driveway, a mechanic's toolbox
	# crate parked beside its running board — a second, non-junk-lot home
	# for the crowbar, on the theory someone left it there fixing the car.
	_spawn_roadster(Vector3(9.5, 0, 28.5), -0.35)
	_add_prop(Vector3(7.85, 0.24, 29.75), Vector3(0.5, 0.42, 0.42), _crate_material)

	# Detached garage at the driveway's end, against the east hedge line.
	_spawn_garage()

	# Toy rocket display on the far west lawn; a labeled parts crate there
	# opens to reveal the first of the two spare fuses.
	_spawn_toy_rocket_corner()

	# Garden lamp posts along the walkway.
	for lz in [27.5, 31.0]:
		_add_lantern(Vector3(-1.9, 0, lz))
		_add_lantern(Vector3(1.9, 0, lz))

	# Drifting leaves and low ground fog across the lawn and porch.
	_add_particles(Vector3(0, 1.2, 26), 28, Vector3(26, 1.6, 14),
		0.15, 0.45, Vector3(0.25, -0.35, 0.1), 0.03, Color(0.6, 0.35, 0.12), 0.85, 7.0)
	_add_particles(Vector3(0, 0.35, 20), 12, Vector3(11, 0.5, 9),
		0.02, 0.08, Vector3.ZERO, 0.5, Color(0.65, 0.7, 0.85), 0.05, 9.0)
	_add_particles(Vector3(0, 0.4, 29), 14, Vector3(24, 0.6, 10),
		0.02, 0.09, Vector3.ZERO, 0.55, Color(0.65, 0.7, 0.85), 0.045, 10.0)


## Detached garage off the driveway's east side. Houses the estate's
## breaker box (the wiring puzzle), so restoring power means a trip
## across the front yard. Person door on the west face toward the
## walkway; the south rolling door is decorative and permanently down.
func _spawn_garage() -> void:
	var c := Vector3(22.5, 0, 20.5)
	# Concrete slab, walls, flat roof with a small overhang.
	_add_decor_box(c + Vector3(0, 0.03, 0), Vector3(7.4, 0.1, 6.4), _stone_material)
	# Walls join the mansion's camera-fade system (CSG + "fade_walls"),
	# so standing behind the garage still shows the character inside.
	_add_fade_wall(c + Vector3(0, 1.4, -3.0), Vector3(7.0, 2.8, 0.3))        # north
	# South wall has a real vehicle opening; the rolling door fills it.
	for wall_x in [-2.675, 2.675]:
		_add_fade_wall(c + Vector3(wall_x, 1.4, 3.0), Vector3(1.65, 2.8, 0.3))
	_add_fade_wall(c + Vector3(0, 2.65, 3.0), Vector3(3.7, 0.3, 0.3))        # lintel
	_add_fade_wall(c + Vector3(3.35, 1.4, 0), Vector3(0.3, 2.8, 6.3))        # east
	_add_fade_wall(c + Vector3(-3.35, 1.4, -1.85), Vector3(0.3, 2.8, 2.6))   # west, N of door
	_add_fade_wall(c + Vector3(-3.35, 1.4, 1.85), Vector3(0.3, 2.8, 2.6))    # west, S of door
	_add_fade_wall(c + Vector3(-3.35, 2.5, 0), Vector3(0.3, 0.6, 1.3))       # door lintel
	# No solid roof — the isometric camera must see inside (the mansion is
	# roofless for the same reason). A single exposed rafter carries the bulb.
	_add_decor_box(c + Vector3(0, 2.86, 0), Vector3(7.2, 0.14, 0.18), _shelf_material)

	# Side entry: plain white external door (no window), jammed shut until
	# pried with the crowbar from the junk lot out back. White trim frame.
	var side_door := DOOR_SCENE.instantiate() as Door
	side_door.name = "GarageSideDoor"
	side_door.position = c + Vector3(-3.35, 0, 0.55)
	side_door.rotation.y = PI / 2.0
	side_door.panel_width = 1.0
	side_door.panel_height = 2.15
	side_door.panel_color = Color(0.93, 0.93, 0.91)
	side_door.display_name = "Garage Side Door"
	side_door.locked = true
	side_door.pry_group = "crowbars"
	_generated_root.add_child(side_door)
	var trim_mat := _make_material(Color(0.9, 0.9, 0.88))
	for trim_z in [-0.66, 0.66]:
		_add_decor_box(c + Vector3(-3.36, 1.15, trim_z), Vector3(0.34, 2.3, 0.14), trim_mat)
	_add_decor_box(c + Vector3(-3.36, 2.36, 0), Vector3(0.34, 0.14, 1.46), trim_mat)

	# Cement patio pad outside the side door, sheltered by an overhang.
	_add_decor_box(c + Vector3(-4.3, 0.02, 0), Vector3(1.6, 0.08, 2.2), _stone_material)
	_add_decor_box(c + Vector3(-4.05, 2.6, 0), Vector3(1.5, 0.1, 2.0), _shelf_material)
	for post_z in [-0.85, 0.85]:
		_add_decor_box(c + Vector3(-4.72, 1.29, post_z), Vector3(0.1, 2.52, 0.1), _iron_material)

	# Rolling garage door filling the south opening: lift-able assembly
	# (meshes + its own collision) raised by the powered wall button.
	var roll_door := Node3D.new()
	roll_door.name = "GarageRollDoor"
	roll_door.position = c + Vector3(0, 0, 3.0)
	_generated_root.add_child(roll_door)
	# The panel itself is a fade wall too (CSG carries its own collision
	# and rides the lift tween). Groove lines are CSG cuts, so the slat
	# look survives fading.
	var roll_panel := CSGBox3D.new()
	roll_panel.size = Vector3(3.7, 2.5, 0.12)
	roll_panel.position = Vector3(0, 1.25, 0)
	roll_panel.use_collision = true
	var roll_mat := StandardMaterial3D.new()
	roll_mat.albedo_color = Color(0.45, 0.36, 0.25)
	roll_panel.material = roll_mat
	roll_panel.add_to_group("fade_walls")
	roll_door.add_child(roll_panel)
	for slat_y in [-0.9, -0.4, 0.1, 0.6, 1.05]:
		var groove := CSGBox3D.new()
		groove.operation = CSGShape3D.OPERATION_SUBTRACTION
		groove.size = Vector3(3.72, 0.03, 0.03)
		groove.position = Vector3(0, slat_y, -0.055)
		roll_panel.add_child(groove)
	for rail_x in [-1.95, 1.95]:
		_add_decor_box(c + Vector3(rail_x, 1.35, 3.12), Vector3(0.14, 2.7, 0.14), _iron_material)

	# Status lamp beside the door: red while locked, green once powered.
	var lamp_mat := _make_material(Color(0.9, 0.1, 0.08))
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.05, 0.05)
	lamp_mat.emission_energy_multiplier = 2.5
	_add_decor_box(c + Vector3(2.55, 2.05, 2.88), Vector3(0.18, 0.18, 0.12), _iron_material)
	_add_decor_sphere(c + Vector3(2.55, 2.05, 2.97), 0.06, lamp_mat)
	var locked_lamp := OmniLight3D.new()
	locked_lamp.light_color = Color(1.0, 0.12, 0.08)
	locked_lamp.light_energy = 0.9
	locked_lamp.omni_range = 3.2
	locked_lamp.position = c + Vector3(2.55, 2.05, 3.4)
	_generated_root.add_child(locked_lamp)
	_garage_lock_lens = lamp_mat
	_garage_lock_lamp = locked_lamp

	# Interior wall button that rolls the door up once power is restored.
	# Untyped so script-added properties resolve dynamically post-set_script.
	var button = StaticBody3D.new()
	button.name = "GarageDoorButton"
	button.set_script(GARAGE_BUTTON_SCRIPT)
	button.position = c + Vector3(1.55, 1.15, 2.72)
	var btn_col := CollisionShape3D.new()
	btn_col.shape = _get_box_shape(Vector3(0.3, 0.4, 0.25))
	button.add_child(btn_col)
	var btn_mesh := MeshInstance3D.new()
	btn_mesh.mesh = _get_box_mesh(Vector3(0.18, 0.24, 0.1), _iron_material)
	button.add_child(btn_mesh)
	var btn_cap := MeshInstance3D.new()
	btn_cap.mesh = _get_box_mesh(Vector3(0.09, 0.09, 0.06), lamp_mat)
	btn_cap.position = Vector3(0, 0, -0.07)
	button.add_child(btn_cap)
	_generated_root.add_child(button)
	button.display_name = "Garage Door Button"
	button.roll_door = roll_door
	_garage_button = button as GarageDoorButton

	# Gravel spur linking the walkway to the garage's person door.
	_add_decor_box(Vector3(17.3, -0.02, 20.5), Vector3(4.4, 0.08, 2.4), _cobble_material)

	# Workshop dressing: bench, crate, hanging bulb with warm light.
	_add_prop(c + Vector3(-1.6, 0.45, -2.4), Vector3(2.4, 0.9, 0.9), _table_material)
	_add_prop(c + Vector3(2.5, 0.4, 1.7), Vector3(0.8, 0.8, 0.8), _crate_material)
	_add_decor_cylinder(c + Vector3(0, 2.72, 0), 0.05, 0.35, _iron_material)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.85, 0.55)
	bulb.light_energy = 1.1
	bulb.omni_range = 6.5
	bulb.shadow_enabled = true
	bulb.position = c + Vector3(0, 2.45, 0)
	_generated_root.add_child(bulb)

	# Junk lot behind (east of) the garage: a U of trash bins, boxes, and
	# a broke-down car. The U seals against the north hedge, the car arms
	# the east side, and the south stays OPEN — players walk in from the
	# yard and up the corridor between the garage wall and the car.
	var rust := _make_material(Color(0.42, 0.2, 0.12))
	_add_prop(Vector3(26.7, 0.45, 16.8), Vector3(0.6, 0.9, 0.6), _iron_material)   # bins, north end
	_add_prop(Vector3(27.6, 0.45, 16.9), Vector3(0.6, 0.9, 0.6), _iron_material)
	_add_prop(Vector3(28.3, 0.4, 17.4), Vector3(0.8, 0.8, 0.8), _crate_material)
	_spawn_junk_car(Vector3(27.85, 0, 20.6), rust)                                 # east arm
	_add_prop(Vector3(27.9, 0.4, 25.9), Vector3(0.8, 0.8, 0.8), _crate_material)   # south arm
	_add_prop(Vector3(26.8, 0.45, 26.2), Vector3(0.6, 0.9, 0.6), _iron_material)
	_add_prop(Vector3(25.6, 0.35, 26.0), Vector3(0.7, 0.7, 0.7), _crate_material)

	# Crowbar hidden at one of several seeded spots — it pries the
	# garage's side door open. Every spot sits directly against (or on
	# top of) a specific nearby prop, never bare ground: the junk-lot
	# bins/crate/car, or the mechanic's toolbox by the roadster out on
	# the driveway.
	var crowbar := CROWBAR_SCENE.instantiate() as Grabbable
	crowbar.name = "Crowbar"
	var crowbar_spots: Array[Vector3] = [
		Vector3(26.6, 0.25, 17.1),   # against the north-end bins
		Vector3(27.5, 0.25, 21.1),   # leaning on the junk car's flank
		Vector3(27.6, 0.83, 25.9),   # atop the south-arm crate
		Vector3(7.85, 0.52, 29.75),  # atop the roadster's toolbox crate
	]
	crowbar.position = crowbar_spots[_rng.randi_range(0, crowbar_spots.size() - 1)]
	crowbar.rotation.y = _rng.randf_range(0.0, TAU)
	_generated_root.add_child(crowbar)

	# The garage's spare fuse, at one of several seeded hiding spots.
	var garage_fuse := FUSE_SCENE.instantiate() as Grabbable
	garage_fuse.name = "Fuse_B"
	var fuse_spots: Array[Vector3] = [
		c + Vector3(-1.6, 0.95, -2.4),   # on the workbench
		c + Vector3(2.5, 0.85, 1.7),     # on the crate
		c + Vector3(2.4, 0.1, -1.6),     # floor by the cradle
		c + Vector3(-0.7, 0.1, 2.3),     # floor by the rolling door
	]
	garage_fuse.position = fuse_spots[_rng.randi_range(0, fuse_spots.size() - 1)]
	_generated_root.add_child(garage_fuse)

	# The Small Wrench — first phase of the hydraulic press — lives in the
	# workshop, at one of several seeded spots around the bench.
	var small_wrench := SMALL_WRENCH_SCENE.instantiate() as Grabbable
	small_wrench.name = "SmallWrench"
	var small_wrench_spots: Array[Vector3] = [
		c + Vector3(-2.4, 0.95, -2.4),   # west end of the workbench
		c + Vector3(-0.8, 0.95, -2.5),   # east end of the workbench
		c + Vector3(1.2, 0.1, -2.2),     # floor between bench and crate
	]
	small_wrench.position = small_wrench_spots[_rng.randi_range(0, small_wrench_spots.size() - 1)]
	small_wrench.rotation.y = _rng.randf_range(0.0, TAU)
	_generated_root.add_child(small_wrench)

	# Ledger notebook — it records the door code. Every spot rests on (or
	# tucked directly beside) a specific prop: junk-lot bins/crate, or
	# the porch firewood stack out front.
	var notebook := NOTEBOOK_SCENE.instantiate() as NotebookPickup
	notebook.name = "Notebook"
	var notebook_spots: Array[Vector3] = [
		Vector3(26.7, 0.92, 16.8),   # on a bin lid at the U's north end
		Vector3(27.9, 0.82, 25.9),   # atop the south-arm crate
		Vector3(5.2, 0.42, 23.3),    # resting on the porch firewood stack
	]
	notebook.position = notebook_spots[_rng.randi_range(0, notebook_spots.size() - 1)]
	notebook.rotation.y = _rng.randf_range(0.0, TAU)
	notebook.note_text = "Estate ledger — front door code: %04d" % front_door_pin
	_generated_root.add_child(notebook)


## The fuse panel came back online: wake the keypad and garage button,
## and flip the rolling door's status lamp from red to green.
func _on_power_restored() -> void:
	if _keypad:
		_keypad.power_on()
	if _garage_button:
		_garage_button.power_on()
	if _garage_lock_lens:
		_garage_lock_lens.albedo_color = Color(0.15, 0.75, 0.25)
		_garage_lock_lens.emission = Color(0.1, 0.9, 0.3)
	if _garage_lock_lamp:
		_garage_lock_lamp.light_color = Color(0.25, 1.0, 0.35)


## Toy rocket on a launch stand, west lawn, with stenciled parts crates.
## The openable ToyBox crate stashes Fuse_A (frozen until revealed).
func _spawn_toy_rocket_corner() -> void:
	var at := Vector3(-24.5, 0, 24.0)
	var body_mat := _make_material(Color(0.85, 0.2, 0.15))
	var nose_mat := _make_material(Color(0.9, 0.88, 0.85))
	_add_decor_cylinder(at + Vector3(0, 0.08, 0), 0.4, 0.16, _iron_material)  # launch stand
	_add_decor_cylinder(at + Vector3(0, 0.8, 0), 0.2, 1.3, body_mat)          # fuselage
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.2
	cone.height = 0.5
	cone.material = nose_mat
	nose.mesh = cone
	nose.position = at + Vector3(0, 1.7, 0)
	_generated_root.add_child(nose)
	for fin_yaw in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
		var offset := Basis(Vector3.UP, fin_yaw) * Vector3(0.26, 0, 0)
		_add_decor_box(at + offset + Vector3(0, 0.35, 0), Vector3(0.22, 0.55, 0.04), nose_mat, fin_yaw)
	# Solid: an invisible collision cylinder so nobody clips through it.
	var rocket_body := StaticBody3D.new()
	var rocket_col := CollisionShape3D.new()
	var rocket_shape := CylinderShape3D.new()
	rocket_shape.radius = 0.45
	rocket_shape.height = 1.95
	rocket_col.shape = rocket_shape
	rocket_col.position = Vector3(0, 0.98, 0)
	rocket_body.add_child(rocket_col)
	rocket_body.position = at
	_generated_root.add_child(rocket_body)
	# Wordless brand: a painted roundel on the fuselage's south face.
	var ring_mat := _make_material(Color(0.95, 0.95, 0.9))
	var dot_mat := _make_material(Color(0.15, 0.3, 0.6))
	var roundel := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.1
	ring_mesh.bottom_radius = 0.1
	ring_mesh.height = 0.012
	ring_mesh.material = ring_mat
	roundel.mesh = ring_mesh
	roundel.rotation.x = PI / 2.0
	roundel.position = at + Vector3(0, 0.95, 0.205)
	_generated_root.add_child(roundel)
	var roundel_dot := MeshInstance3D.new()
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.055
	dot_mesh.bottom_radius = 0.055
	dot_mesh.height = 0.014
	dot_mesh.material = dot_mat
	roundel_dot.mesh = dot_mesh
	roundel_dot.rotation.x = PI / 2.0
	roundel_dot.position = at + Vector3(0, 0.95, 0.207)
	_generated_root.add_child(roundel_dot)
	# Sealed sibling crate (decor) plus the openable one with the fuse.
	_add_prop(at + Vector3(1.6, 0.25, -0.6), Vector3(0.9, 0.5, 0.55), _crate_material)

	var toy_box := TOY_BOX_SCENE.instantiate() as ToyBox
	toy_box.name = "ToyBox"
	toy_box.position = at + Vector3(1.3, 0, 0.9)
	toy_box.rotation.y = 0.35
	_generated_root.add_child(toy_box)
	# Untyped: the analyzer treats Grabbable and RigidBody3D as siblings,
	# and we need RigidBody3D properties (freeze) here.
	var fuse_a: Node3D = FUSE_SCENE.instantiate()
	fuse_a.name = "Fuse_A"
	fuse_a.set("freeze", true)
	fuse_a.set("collision_layer", 0)
	fuse_a.set("collision_mask", 0)
	toy_box.add_child(fuse_a)
	fuse_a.position = Vector3(0, 0.2, 0)
	toy_box.stash = fuse_a


## Rusted-out car on the junk lot: sunken cabin, hood ajar, one flat
## tire lying beside it.
func _spawn_junk_car(at: Vector3, rust: StandardMaterial3D) -> void:
	_add_prop(at + Vector3(0, 0.55, 0), Vector3(1.35, 0.6, 2.7), rust)
	_add_decor_box(at + Vector3(0, 1.05, 0.35), Vector3(1.2, 0.5, 1.15), _iron_material)
	_add_decor_box(at + Vector3(-0.15, 0.92, -1.05), Vector3(1.1, 0.14, 0.7), rust, 0.35)
	for wheel in [Vector3(0.72, 0.3, 0.95), Vector3(-0.72, 0.3, 0.95), Vector3(0.72, 0.3, -0.95)]:
		_add_decor_cylinder(at + wheel, 0.3, 0.14, _iron_material, true, PI / 2.0)
	_add_decor_cylinder(at + Vector3(-1.1, 0.08, -1.3), 0.3, 0.14, _iron_material)


# --- Imported props (car scene FBX) ---------------------------------------
# One authored FBX carries the vintage car and a tall vintage lantern.
# The importer already turns its Z-up nodes Y-up (each part's basis maps
# local Z to world Y), so instances are used as-is. Its textures are not
# shipped; every surface is recolored by material name into the estate's
# palette so the pieces sit with the rest of the art.

const CAR_SCENE := preload("res://assets/props/car_scene.fbx")
const CAR_PART_NAMES := [
	"car_body", "door_left", "door_right", "hood", "rear_bumper", "front_bumper", "viper_01",
	"viper_02", "bottom", "wheel_00", "wheel_01", "wheel_02", "wheel_03", "wheel_004", "wheel_005",
	"interior_00", "interior_01", "back_door", "lights_00", "lights_01", "lights_02", "lights_03",
	"lights_04", "lights_05", "railings", "logo_01", "glass_00", "glass_01", "glass_02", "glass_03",
	"chest_base",
]
const LANTERN_PART_NAMES := ["vintage_lantern_7_base"]

var _prop_palette := {}


## Palette materials for the FBX surfaces, keyed by the FBX material name.
func _prop_material(fbx_name: String) -> StandardMaterial3D:
	if _prop_palette.is_empty():
		var body := _make_material(Color(0.3, 0.11, 0.13), 0.35, 0.45)     # oxblood coachwork
		var rubber := _make_material(Color(0.07, 0.07, 0.08), 0.0, 0.95)
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(0.55, 0.7, 0.85, 0.35)
		glass.metallic = 0.3
		glass.roughness = 0.1
		var interior := _make_material(Color(0.36, 0.23, 0.14), 0.0, 0.8)   # worn leather
		var chrome := _make_material(Color(0.72, 0.55, 0.25), 0.85, 0.3)     # brass trim
		var wheels := _make_material(Color(0.16, 0.16, 0.18), 0.4, 0.6)
		var lights := _make_glow_material(Color(1.0, 0.75, 0.4), 1.6)
		var chest := _make_material(Color(0.3, 0.2, 0.13), 0.0, 0.7)
		var lantern_iron := _make_material(Color(0.13, 0.13, 0.16), 0.5, 0.55)
		var lantern_glass := _make_glow_material(Color(1.0, 0.75, 0.4), 1.8)
		_prop_palette = {
			"body": body, "rubber": rubber, "glass": glass, "interior": interior,
			"chrome": chrome, "wheels": wheels, "lights": lights, "number": chrome,
			"chest": chest, "shadow": null,
			"lantern_wall_base_1": lantern_iron, "lantern_wall_base_2": lantern_iron,
			"lantern_wall_glass_1": lantern_glass,
		}
	return _prop_palette.get(fbx_name, _iron_material)


## Instance the FBX keeping only the top-level parts in `keep`, recolor
## every surface, and hand back a Y-up wrapper at `at` with `yaw`/`scale`.
func _instance_prop(keep: Array, at: Vector3, yaw: float, prop_scale: float) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.position = at
	wrapper.rotation.y = yaw
	wrapper.scale = Vector3.ONE * prop_scale
	var inst := CAR_SCENE.instantiate()
	for child in inst.get_children():
		if not child.name in keep:
			inst.remove_child(child)
			child.free()
		elif child is Node3D and child.name in LANTERN_PART_NAMES:
			# The lantern is authored off to the side of the car; stand it
			# on the wrapper's origin (its base is at its own local zero).
			(child as Node3D).position = Vector3.ZERO
	# Recolor (walk the whole kept subtree — lantern parts are nested).
	var stack: Array = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh:
				for s in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(s)
					var key := src.resource_name if src else ""
					var mat := _prop_material(key)
					if mat == null:
						mi.visible = false
					else:
						mi.set_surface_override_material(s, mat)
		stack.append_array(node.get_children())
	wrapper.add_child(inst)
	_generated_root.add_child(wrapper)
	return wrapper


## The vintage motor car on the gravel by the garage, with a body-sized
## collision box so it is solid to walk around.
func _spawn_roadster(at: Vector3, yaw: float) -> void:
	var car := _instance_prop(CAR_PART_NAMES, at, yaw, 1.15)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.3, 1.3, 1.5)
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	body.add_child(col)
	car.add_child(body)


func _add_gargoyle(at: Vector3) -> void:
	_add_decor_box(at + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), _stone_material)
	_add_decor_box(at + Vector3(0, 0.62, 0.1), Vector3(0.28, 0.28, 0.28), _stone_material)
	_add_decor_box(at + Vector3(-0.32, 0.5, -0.05), Vector3(0.34, 0.26, 0.06), _stone_material, 0.5)
	_add_decor_box(at + Vector3(0.32, 0.5, -0.05), Vector3(0.34, 0.26, 0.06), _stone_material, -0.5)


## Dense woods ringing the whole estate: a belt beyond the fence on the
## south (parted for the driveway and gate), and thick stands down both
## sides and across the back of the mansion. Every one of those bands is
## sealed off from play (the yard hedges and the mansion's outer walls),
## so the trees never cost a path. Seeded jitter and per-tree scale keep
## it from reading as a grid.
func _spawn_woods() -> void:
	var placed := 0
	# [x0, x1, z0, z1] bands (world).
	var bands := [
		[-46.0, 46.0, 35.5, 50.0],    # south, beyond the fence
		[-46.0, -18.0, -42.0, 34.0],  # west flank and back corner
		[18.0, 46.0, -42.0, 34.0],    # east flank and back corner
		[-18.0, 18.0, -42.0, -17.5],  # north, behind the mansion
	]
	for band in bands:
		var z: float = band[2]
		var row := 0
		while z <= band[3]:
			var x: float = band[0] + (2.0 if row % 2 == 1 else 0.0)
			while x <= band[1]:
				var jitter := Vector3(_rng.randf_range(-1.3, 1.3), 0, _rng.randf_range(-1.3, 1.3))
				var p := Vector3(x, 0, z) + jitter
				if _woods_spot_ok(p) and _rng.randf() < 0.85:
					_add_pine(p, _rng.randf() < 0.22, _rng.randf_range(0.8, 1.35))
					placed += 1
				x += 4.0
			z += 3.6
			row += 1


## Keep the woods off the driveway and lane, out of the gate's sight
## line, and clear of the fence line and the yard's own features.
func _woods_spot_ok(p: Vector3) -> bool:
	# Driveway + gate approach corridor, and the lane.
	if absf(p.x) < 4.5 and p.z > 30.0:
		return false
	if p.z > 49.5:
		return false
	# Not on the fence line itself (z 33 south fence, x +-30 side fences).
	if absf(p.z - 33.0) < 1.6 and absf(p.x) <= 31.5:
		return false
	if absf(absf(p.x) - 30.0) < 1.6 and p.z >= 14.0 and p.z <= 34.5:
		return false
	# Never inside the fenced yard or the mansion footprint.
	if absf(p.x) < 30.0 and p.z > 14.0 and p.z < 33.0:
		return false
	if absf(p.x) < 16.5 and p.z > -16.5 and p.z < 16.5:
		return false
	return true


## Shared pine meshes: a hundred trees must not each own their own.
var _pine_trunk_mesh: CylinderMesh
var _pine_layers: Array = []
var _autumn_layers: Array = []


func _add_pine(at: Vector3, autumn: bool, tree_scale := 1.0) -> void:
	if _pine_trunk_mesh == null:
		_pine_trunk_mesh = CylinderMesh.new()
		_pine_trunk_mesh.top_radius = 0.14
		_pine_trunk_mesh.bottom_radius = 0.2
		_pine_trunk_mesh.height = 2.2
		_pine_trunk_mesh.material = _trunk_material
		for layer in [[2.9, 1.4, 2.4], [4.2, 1.0, 1.8]]:
			for variant in 2:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = layer[1]
				cone.height = layer[2]
				cone.material = _pine_material if variant == 0 else _autumn_material
				(_pine_layers if variant == 0 else _autumn_layers).append([layer[0], cone])
	var tree := SwayProp.new()
	tree.position = at
	tree.rotation.y = _rng.randf_range(0.0, TAU)
	tree.scale = Vector3.ONE * tree_scale
	tree.amplitude = 0.025
	var trunk := MeshInstance3D.new()
	trunk.mesh = _pine_trunk_mesh
	trunk.position = Vector3(0, 1.1, 0)
	tree.add_child(trunk)
	for layer in (_autumn_layers if autumn else _pine_layers):
		var foliage := MeshInstance3D.new()
		foliage.mesh = layer[1]
		foliage.position = Vector3(0, layer[0], 0)
		tree.add_child(foliage)
	_generated_root.add_child(tree)


## Garden lamp post: the FBX's vintage lantern (3.4 m in the source),
## scaled so the head sits at `post_height` above ground, with a warm
## flicker in the glass and a solid post you cannot walk through.
func _add_lantern(at: Vector3, post_height := 1.6) -> void:
	var lantern_scale := (post_height + 0.4) / 3.4
	var lantern := _instance_prop(LANTERN_PART_NAMES, at, _rng.randf_range(0.0, TAU), lantern_scale)
	var head_y := post_height + 0.1
	var light := FlickerLight.new()
	light.base_energy = 0.85
	light.light_color = Color(1.0, 0.75, 0.4)
	light.omni_range = 5.0
	light.position = at + Vector3(0, head_y, 0)
	_generated_root.add_child(light)
	# The post is solid: a slim cylinder the height of the pole.
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.16
	shape.height = post_height + 0.4
	col.shape = shape
	col.position = Vector3(0, (post_height + 0.4) / 2.0, 0)
	body.add_child(col)
	body.position = at
	_generated_root.add_child(body)
	# The FBX head is offset from the post's own axis; drop a lantern node
	# reference so callers could align lights later if needed.
	lantern.name = "Lantern"


func _add_decor_cylinder(at: Vector3, radius: float, height: float, material: StandardMaterial3D, lying := false, yaw := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = material
	mesh.mesh = cyl
	mesh.position = at
	mesh.rotation.y = yaw
	if lying:
		mesh.rotation.z = PI / 2.0
	_generated_root.add_child(mesh)


func _add_decor_sphere(at: Vector3, radius: float, material: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = material
	mesh.mesh = sphere
	mesh.position = at
	_generated_root.add_child(mesh)


func _add_particles(at: Vector3, amount: int, box: Vector3, vel_min: float, vel_max: float, gravity: Vector3, radius: float, color: Color, alpha: float, lifetime: float) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = box / 2.0
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = vel_min
	mat.initial_velocity_max = vel_max
	mat.gravity = gravity
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	mesh.material = m
	particles.draw_pass_1 = mesh
	particles.position = at
	_generated_root.add_child(particles)


static func _make_material(color: Color, metallic := 0.0, roughness := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


static func _make_glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
