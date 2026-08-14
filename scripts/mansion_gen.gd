class_name MansionGenerator
extends Node3D

## Procedurally builds the estate: a 3x3 grid of interconnected rooms, the
## Front Porch, and a moonlit 60x60 walled yard with gate, trees, and
## driveway. A randomized spanning tree carved from the Foyer (excluding
## the Vault Study) guarantees reachability; the vault's only entrance is
## the gate-guarded doorway. Spawns all puzzles (laser mirror maze, steam
## valves, breaker box, grandfather clock), hinged doors, fog-of-war
## shrouds, furniture, and ambient atmosphere.
## Grid convention: x grows east, y (grid) grows south (+Z in world).

signal generated
signal puzzle_solved

const GRID_SIZE := Vector2i(3, 3)
const FOYER_CELL := Vector2i(1, 2)
const VAULT_STUDY_CELL := Vector2i(1, 0)
const PARLOR_CELL := Vector2i(2, 0)         ## Fireplace parlor.

const LIGHT_EMITTER_SCENE := preload("res://scenes/Puzzles/LightEmitter.tscn")
const ROTATING_MIRROR_SCENE := preload("res://scenes/Puzzles/RotatingMirror.tscn")
const LIGHT_RECEIVER_SCENE := preload("res://scenes/Puzzles/LightReceiver.tscn")
const STEAM_VALVE_SCENE := preload("res://scenes/Puzzles/SteamValve.tscn")
const BREAKER_BOX_SCENE := preload("res://scenes/Puzzles/BreakerBox.tscn")
const VAULT_DOOR_SCENE := preload("res://scenes/VaultDoor.tscn")
const WILL_ITEM_SCENE := preload("res://scenes/WillItem.tscn")
const BRASS_WRENCH_SCENE := preload("res://scenes/BrassWrench.tscn")
const DOOR_SCENE := preload("res://scenes/Door.tscn")
const ROOM_SHROUD_SCENE := preload("res://scenes/RoomShroud.tscn")
const CLOCKWORK_SCENE := preload("res://scenes/Puzzles/ClockworkMechanism.tscn")
const BRASS_GEAR_SCENE := preload("res://scenes/BrassGear.tscn")

## Three hand-authored, guaranteed-solvable laser routes; one is drawn per
## run. Every route ends with a mirror at the parlor center turning the
## beam north through the vault gate's slit. "solutions" are the solved
## root yaws in degrees (panels are mounted at 45 degrees locally), so
## different routes need genuinely different alignments.
const ROUTE_VARIANTS := [
	{
		"name": "west_maze",
		"emitter": Vector3(-10, 0, 12.5),
		"maze_cell": Vector2i(0, 1),
		"mirrors": [Vector3(-10, 0, 3), Vector3(-7, 0, 3), Vector3(-7, 0, 0), Vector3(0, 0, 0)],
		"solutions": [0.0, 0.0, 0.0, 0.0],
		"screen": Vector3(-10, 1.5, 1.2),
		"doors": [[Vector2i(0, 2), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(1, 1)]],
	},
	{
		"name": "east_maze",
		"emitter": Vector3(10, 0, 12.5),
		"maze_cell": Vector2i(2, 1),
		"mirrors": [Vector3(10, 0, 3), Vector3(7, 0, 3), Vector3(7, 0, 0), Vector3(0, 0, 0)],
		"solutions": [90.0, 90.0, 90.0, 90.0],
		"screen": Vector3(10, 1.5, 1.2),
		"doors": [[Vector2i(2, 2), Vector2i(2, 1)], [Vector2i(2, 1), Vector2i(1, 1)]],
	},
	{
		"name": "parlor_loop",
		"emitter": Vector3(0, 0, 13.0),
		"maze_cell": Vector2i(1, 1),
		"mirrors": [Vector3(0, 0, 3), Vector3(3, 0, 3), Vector3(3, 0, 0), Vector3(0, 0, 0)],
		"solutions": [0.0, 0.0, 90.0, 90.0],
		"screen": Vector3(0, 1.5, 1.8),
		"doors": [[Vector2i(1, 2), Vector2i(1, 1)]],
	},
]
## Adjacent room pairs eligible to host the two steam valves (the pair's
## connecting door is forced open so the 25 s sync sprint stays fair).
const VALVE_PAIR_OPTIONS := [
	[Vector2i(2, 1), Vector2i(2, 2)], [Vector2i(0, 1), Vector2i(0, 2)],
	[Vector2i(2, 0), Vector2i(2, 1)], [Vector2i(0, 0), Vector2i(0, 1)],
]
const CLOCK_CELL_OPTIONS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 0), Vector2i(0, 0)]
const GEAR_CELL_OPTIONS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(2, 0),
	Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2),
]
const DECOY_CELL_OPTIONS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
	Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
]
const TABLE_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 2)]
## teeth, label, mesh radius (hiding rooms are drawn per run)
const GEAR_SPECS := [
	[8, "Small Gear (8-tooth)", 0.2],
	[12, "Medium Gear (12-tooth)", 0.28],
	[16, "Large Gear (16-tooth)", 0.36],
]

## Test hook: force a specific ROUTE_VARIANTS index (-1 = seeded random).
@export var route_override: int = -1

## The layout drawn for this run (read by tests and debug tools).
var active_route: Dictionary
var _valve_cells: Array = []
var _clock_cell := Vector2i(1, 1)
var _gear_cells: Array = []
var _decoy_cell := Vector2i(2, 1)

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

	if rng_seed != 0:
		_rng.seed = rng_seed
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


func get_spawn_position() -> Vector3:
	return get_room_center(FOYER_CELL) + Vector3(0.0, 0.1, room_size * 0.8)


## Draw this run's structural layout from the seeded rng: laser route,
## valve rooms, clock location, gear hiding rooms, and the decoy's spot.
## Combined with door carving, wiring, and spawn rotations, no two seeds
## play the same.
func _pick_run_layout() -> void:
	if route_override >= 0 and route_override < ROUTE_VARIANTS.size():
		active_route = ROUTE_VARIANTS[route_override]
	else:
		active_route = ROUTE_VARIANTS[_rng.randi_range(0, ROUTE_VARIANTS.size() - 1)]
	var maze: Vector2i = active_route["maze_cell"]

	var pair_options: Array = VALVE_PAIR_OPTIONS.filter(
		func(pair: Array) -> bool: return not maze in pair)
	_valve_cells = pair_options[_rng.randi_range(0, pair_options.size() - 1)]

	var clock_options: Array = CLOCK_CELL_OPTIONS.filter(
		func(cell: Vector2i) -> bool: return cell != maze)
	_clock_cell = clock_options[_rng.randi_range(0, clock_options.size() - 1)]

	var gear_pool: Array = GEAR_CELL_OPTIONS.duplicate()
	for i in range(gear_pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Vector2i = gear_pool[i]
		gear_pool[i] = gear_pool[j]
		gear_pool[j] = tmp
	_gear_cells = gear_pool.slice(0, GEAR_SPECS.size())

	var decoy_options: Array = DECOY_CELL_OPTIONS.filter(
		func(cell: Vector2i) -> bool: return cell != maze)
	_decoy_cell = decoy_options[_rng.randi_range(0, decoy_options.size() - 1)]


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

	# Force this run's route doors, the vault doorway, and the valve pair's
	# connecting door open, whatever the random rolls decided.
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
	lawn.size = Vector3(60, 0.4, 60)
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
	var emitter := LIGHT_EMITTER_SCENE.instantiate() as Node3D
	emitter.position = active_route["emitter"]
	_generated_root.add_child(emitter)

	# Route mirrors at free random 15-degree detents (closed doors block
	# the beam anyway, so no spawn can pre-solve the circuit).
	for spot in active_route["mirrors"]:
		var mirror := ROTATING_MIRROR_SCENE.instantiate() as Node3D
		mirror.position = spot
		mirror.rotation.y = deg_to_rad(15.0 * float(_rng.randi_range(0, 23)))
		_generated_root.add_child(mirror)

	# Decoy mirror: interactable, reflective, entirely useless.
	var decoy := ROTATING_MIRROR_SCENE.instantiate() as Node3D
	decoy.position = get_room_center(_decoy_cell)
	decoy.rotation.y = deg_to_rad(15.0 * float(_rng.randi_range(0, 23)))
	_generated_root.add_child(decoy)

	# Maze obstacles: this route's tall privacy screen forces the bounces;
	# a high bookcase breaks sightlines in the central parlor.
	_add_prop(active_route["screen"], Vector3(3, 3, 0.4), _shelf_material)
	_add_prop(Vector3(2.0, 1.5, -2.0), Vector3(2.2, 3, 0.5), _shelf_material)

	var receiver := LIGHT_RECEIVER_SCENE.instantiate() as Node3D
	receiver.position = get_room_center(VAULT_STUDY_CELL) + Vector3(0, 0, 3.0)
	_generated_root.add_child(receiver)
	receiver.puzzle_completed.connect(func() -> void: puzzle_solved.emit())

	var door := VAULT_DOOR_SCENE.instantiate() as VaultDoor
	door.position = (get_room_center(Vector2i(1, 1)) + get_room_center(VAULT_STUDY_CELL)) / 2.0
	_generated_root.add_child(door)
	receiver.puzzle_completed.connect(door.on_light_puzzle_completed)

	door.valves_required = _valve_cells.size()
	for cell in _valve_cells:
		var valve := STEAM_VALVE_SCENE.instantiate() as SteamValve
		valve.position = get_room_center(cell) + Vector3(2.0, 0, 2.0)
		_generated_root.add_child(valve)
		valve.valve_activated.connect(door.on_valve_activated)
		valve.valve_reset.connect(door.on_valve_reset)

	# Grandfather clock in this run's chosen room; the Brass Wrench is
	# stashed in its compartment until the gear puzzle runs the pendulum.
	# Socket requirements are shuffled and their numerals re-engraved.
	var clock := CLOCKWORK_SCENE.instantiate() as ClockworkMechanism
	clock.position = get_room_center(_clock_cell) + Vector3(-3.0, 0, 3.2)
	clock.rotation.y = PI
	_generated_root.add_child(clock)
	var teeth_perm := [8, 12, 16]
	for i in range(teeth_perm.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: int = teeth_perm[i]
		teeth_perm[i] = teeth_perm[j]
		teeth_perm[j] = tmp
	var numerals := {8: "VIII", 12: "XII", 16: "XVI"}
	for i in clock._sockets.size():
		var socket: GearSocket = clock._sockets[i]
		socket.required_teeth = teeth_perm[i]
		socket.display_name = "Gear Socket %s" % numerals[teeth_perm[i]]
		socket.get_node("Numeral").text = numerals[teeth_perm[i]]
	var wrench := BRASS_WRENCH_SCENE.instantiate() as Grabbable
	clock.stash_item(wrench)

	for i in GEAR_SPECS.size():
		var spec: Array = GEAR_SPECS[i]
		_spawn_gear(spec[0], spec[1], spec[2],
			get_room_center(_gear_cells[i]) + Vector3(-1.8, 0.3, -4.2))

	_build_pedestal(get_room_center(VAULT_STUDY_CELL))
	var will := WILL_ITEM_SCENE.instantiate() as Node3D
	will.position = get_room_center(VAULT_STUDY_CELL) + Vector3(0, 1.05, 0)
	_generated_root.add_child(will)

	_build_exit_zone()


func _spawn_gear(teeth: int, label: String, radius: float, at: Vector3) -> void:
	var gear := BRASS_GEAR_SCENE.instantiate() as Grabbable
	gear.display_name = label
	gear.set_meta("teeth", teeth)
	gear.position = at
	var mesh_node: MeshInstance3D = gear.get_node("Mesh")
	var mesh := mesh_node.mesh.duplicate() as CylinderMesh
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh_node.mesh = mesh
	var col: CollisionShape3D = gear.get_node("CollisionShape3D")
	var shape := col.shape.duplicate() as CylinderShape3D
	shape.radius = radius + 0.02
	col.shape = shape
	_generated_root.add_child(gear)


# --- Doors, entrance, props, shrouds -------------------------------------


func _spawn_doors() -> void:
	var vault_edge := _edge_key(Vector2i(1, 1), VAULT_STUDY_CELL)
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			var center := get_room_center(cell)
			var east := cell + Vector2i(1, 0)
			if _has_door(cell, east) and _edge_key(cell, east) != vault_edge:
				_spawn_hinged_door(center + Vector3(room_size / 2.0, 0, 1.0), PI / 2.0)
				_add_door_frame(center + Vector3(room_size / 2.0, 0, 0), PI / 2.0)
			var south := cell + Vector2i(0, 1)
			if _has_door(cell, south) and _edge_key(cell, south) != vault_edge:
				_spawn_hinged_door(center + Vector3(-1.0, 0, room_size / 2.0), 0.0)
				_add_door_frame(center + Vector3(0, 0, room_size / 2.0), 0.0)


func _spawn_hinged_door(at: Vector3, yaw: float, locked := false, width := 2.0) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
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
	breaker.position = Vector3(3.5, 0, front_z + 0.16)
	_generated_root.add_child(breaker)
	breaker.powered.connect(left.unlock_and_open)
	breaker.powered.connect(right.unlock_and_open)

	# Brass house number beside the breaker box.
	var number := Label3D.new()
	number.text = "No. 1887"
	number.font_size = 64
	number.pixel_size = 0.004
	number.modulate = Color(0.85, 0.68, 0.3)
	number.position = Vector3(4.6, 2.0, front_z + 0.2)
	_generated_root.add_child(number)


func _spawn_props() -> void:
	var crate_spots: Array[Vector3] = [
		Vector3(3.4, 0.4, 3.2), Vector3(-3.2, 0.4, 3.5), Vector3(3.3, 0.4, -3.3),
	]
	for z in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, z)
			if cell == VAULT_STUDY_CELL:
				continue
			var center := get_room_center(cell)
			var side := 3.5 if _rng.randf() < 0.5 else -3.5
			_add_prop(center + Vector3(side, 1.1, -4.25), Vector3(1.8, 2.2, 0.45), _shelf_material)
			if cell != _clock_cell:  # keep the clock's corner clear
				for spot in crate_spots:
					if _rng.randf() < 0.6:
						_add_prop(center + spot, Vector3(0.8, 0.8, 0.8), _crate_material)
			if cell in TABLE_CELLS:
				_add_prop(center + Vector3(0, 0.45, 0), Vector3(1.6, 0.9, 1.0), _table_material)


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

			# Swinging ceiling lamp (offset in the parlor so it clears the
			# clock and mirror B) and drifting dust motes.
			var lamp := SwingingLamp.new()
			var lamp_offset := Vector3(1.8, 2.95, 1.8) if cell == _clock_cell else Vector3(0, 2.95, 0)
			lamp.position = center + lamp_offset
			_generated_root.add_child(lamp)
			_add_particles(center + Vector3(0, 1.6, 0), 20, Vector3(8, 2.4, 8),
				0.02, 0.1, Vector3.ZERO, 0.012, Color(1, 0.95, 0.8), 0.22, 6.0)

			# Baseboard trim along each wall.
			var inset := room_size / 2.0 - 0.22
			_add_decor_box(center + Vector3(0, 0.075, -inset), Vector3(room_size - 0.5, 0.15, 0.06), _shelf_material)
			_add_decor_box(center + Vector3(0, 0.075, inset), Vector3(room_size - 0.5, 0.15, 0.06), _shelf_material)
			_add_decor_box(center + Vector3(-inset, 0.075, 0), Vector3(0.06, 0.15, room_size - 0.5), _shelf_material)
			_add_decor_box(center + Vector3(inset, 0.075, 0), Vector3(0.06, 0.15, room_size - 0.5), _shelf_material)

	# Area rugs in the foyer and both parlors (deduped if they coincide).
	var rug_cells: Array[Vector2i] = [FOYER_CELL]
	for cell: Vector2i in [_clock_cell, PARLOR_CELL]:
		if not cell in rug_cells:
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
	for wx in [-2.4, 2.4, -10.0, 10.0]:
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

	var tree_i := 0
	for tx in range(-28, 29, 4):
		_add_pine(Vector3(tx, 0, 34.6), tree_i % 3 == 0)
		tree_i += 1
	for tz in range(17, 33, 4):
		_add_pine(Vector3(31.6, 0, tz), tree_i % 3 == 0)
		_add_pine(Vector3(-31.6, 0, tz), tree_i % 2 == 0)
		tree_i += 1

	# Antique steam roadster on the gravel driveway.
	_spawn_roadster(Vector3(9.5, 0, 28.5), -0.35)

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


func _spawn_roadster(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_add_prop(at + basis * Vector3(0, 0.7, 0), Vector3(2.6, 0.7, 1.3), _iron_material)
	_add_decor_box(at + basis * Vector3(-0.6, 1.35, 0), Vector3(1.2, 0.6, 1.2), _shelf_material, yaw)
	_add_decor_cylinder(at + basis * Vector3(0.9, 0.95, 0), 0.32, 0.8, _lantern_glass_material, true, yaw)
	for corner in [Vector3(0.9, 0.35, 0.7), Vector3(0.9, 0.35, -0.7), Vector3(-0.9, 0.35, 0.7), Vector3(-0.9, 0.35, -0.7)]:
		_add_decor_cylinder(at + basis * corner, 0.35, 0.12, _iron_material, true, yaw)


func _add_gargoyle(at: Vector3) -> void:
	_add_decor_box(at + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), _stone_material)
	_add_decor_box(at + Vector3(0, 0.62, 0.1), Vector3(0.28, 0.28, 0.28), _stone_material)
	_add_decor_box(at + Vector3(-0.32, 0.5, -0.05), Vector3(0.34, 0.26, 0.06), _stone_material, 0.5)
	_add_decor_box(at + Vector3(0.32, 0.5, -0.05), Vector3(0.34, 0.26, 0.06), _stone_material, -0.5)


func _add_pine(at: Vector3, autumn: bool) -> void:
	var tree := SwayProp.new()
	tree.position = at
	tree.amplitude = 0.025
	var trunk := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 0.14
	tcyl.bottom_radius = 0.2
	tcyl.height = 2.2
	tcyl.material = _trunk_material
	trunk.mesh = tcyl
	trunk.position = Vector3(0, 1.1, 0)
	tree.add_child(trunk)
	var mat := _autumn_material if autumn else _pine_material
	for layer in [[2.9, 1.4, 2.4], [4.2, 1.0, 1.8]]:
		var foliage := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = layer[1]
		cone.height = layer[2]
		cone.material = mat
		foliage.mesh = cone
		foliage.position = Vector3(0, layer[0], 0)
		tree.add_child(foliage)
	_generated_root.add_child(tree)


func _add_lantern(at: Vector3, post_height := 1.6) -> void:
	_add_decor_box(at + Vector3(0, post_height / 2.0, 0), Vector3(0.08, post_height, 0.08), _iron_material)
	var head_y := post_height + 0.16
	_add_decor_box(at + Vector3(0, head_y, 0), Vector3(0.22, 0.3, 0.22), _lantern_glass_material)
	var light := FlickerLight.new()
	light.base_energy = 0.85
	light.light_color = Color(1.0, 0.75, 0.4)
	light.omni_range = 5.0
	light.position = at + Vector3(0, head_y, 0)
	_generated_root.add_child(light)


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


static func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


static func _make_glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
