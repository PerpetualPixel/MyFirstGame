class_name SwingingLamp
extends Node3D

## Ceiling lamp on a chain that sways gently, casting moving shadows.
## Builds its own chain/shade/bulb/light; position the node at the ceiling.

var _phase := randf() * TAU
var _speed := randf_range(0.7, 1.1)


func _ready() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.15, 0.15, 0.17)
	iron.metallic = 0.6

	var chain := MeshInstance3D.new()
	var rod := BoxMesh.new()
	rod.size = Vector3(0.03, 0.7, 0.03)
	rod.material = iron
	chain.mesh = rod
	chain.position = Vector3(0, -0.35, 0)
	add_child(chain)

	var shade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.24
	cone.height = 0.22
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.6, 0.45, 0.2)
	brass.metallic = 0.7
	cone.material = brass
	shade.mesh = cone
	shade.position = Vector3(0, -0.78, 0)
	add_child(shade)

	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.85, 0.55)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.45)
	glow.emission_energy_multiplier = 2.0
	sphere.material = glow
	bulb.mesh = sphere
	bulb.position = Vector3(0, -0.86, 0)
	add_child(bulb)

	var light := OmniLight3D.new()
	light.position = Vector3(0, -0.9, 0)
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 0.7
	light.omni_range = 6.5
	light.shadow_enabled = true
	# Distance fade culls far rooms' lamps (and their shadow renders) —
	# the isometric camera only ever frames a couple of rooms at once.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 22.0
	light.distance_fade_length = 8.0
	add_child(light)


func _process(delta: float) -> void:
	_phase += delta * _speed
	rotation.z = sin(_phase) * 0.06
	rotation.x = sin(_phase * 0.77) * 0.04
