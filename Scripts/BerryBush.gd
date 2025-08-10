extends "res://Scripts/SmallPlant.gd"
class_name BerryBush

# A small plant that produces a single spherical berry on top.
# The berry regenerates on a timer when missing, and also refreshes
# every time the bush reproduces.

@export var berry_radius: float = 0.12
@export var berry_color: Color = Color(0.8, 0.0, 0.0)
@export var berry_offset_height: float = 0.45
@export var berry_interval_days: float = 0.75

var _berry_timer: float = 0.0
var _berry_node: MeshInstance3D

func _ready():
	super._ready()
	# If a child named "Berry" already exists from scene, track it
	var existing = find_child("Berry", true, false)
	if existing and existing is MeshInstance3D:
		_berry_node = existing as MeshInstance3D

func _logic_update(dt: float) -> void:
	# Run the base small plant logic (age, health, reproduction)
	super._logic_update(dt)

	# If berry missing, tick a timer and spawn when interval elapses
	if not is_winter and not is_instance_valid(_berry_node):
		_berry_timer += (dt / seconds_per_game_day) * clamp(healthPercentage, 0.0, 1.0)
		if _berry_timer >= berry_interval_days:
			_berry_timer = 0.0
			_spawn_berry()

func _try_reproduce() -> void:
	# Match SmallPlant reproduction behavior, then refresh the berry
	if healthPercentage < 0.5:
		return
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	if not terrain or not terrain.has_method("get_height"):
		return
	var angle = randf() * TAU
	var dist = randf_range(repro_radius * 0.25, repro_radius)
	var offset = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var pos = global_position + offset
	var y = terrain.get_height(pos.x, pos.z)
	var spawn_pos = Vector3(pos.x, y, pos.z)
	var tm = root.find_child("TreeManager", true, false)
	if tm and tm.has_method("request_smallplant_spawn"):
		tm.request_smallplant_spawn(species_name, spawn_pos)
	_refresh_berry()

func _refresh_berry() -> void:
	if is_instance_valid(_berry_node):
		_berry_node.queue_free()
		_berry_node = null
	_spawn_berry()

func _spawn_berry() -> void:
	# Create a simple sphere berry mesh and place it on top of the bush
	var sphere = SphereMesh.new()
	sphere.radius = berry_radius
	sphere.height = berry_radius * 2.0

	var m := StandardMaterial3D.new()
	m.albedo_color = berry_color

	var mi = MeshInstance3D.new()
	mi.name = "Berry"
	mi.mesh = sphere
	mi.material_override = m
	add_child(mi)
	mi.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, berry_offset_height, 0.0))
	_berry_node = mi
