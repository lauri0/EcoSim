extends "res://Scripts/Plant.gd"
class_name SmallPlant

# Small plants are simple lifeforms that do not grow in stages.
# They age, have altitude-based health, and die when reaching max_age.

var seconds_per_game_day: float = 90.0
var plant_manager: Node
@export var repro_radius: float = 4.0
@export var repro_interval_days: float = 0.5
var _repro_timer: float = 0.0
var collision_body: StaticBody3D
var is_winter: bool = false

# Seasonal visuals (apply to the plant model only; excludes berries or other children)
var model_node: Node3D
var _mesh_instances: Array = []
var _original_materials: Dictionary = {} # MeshInstance3D -> Array[Material]
static var _winter_material: StandardMaterial3D

func _ready():
	seconds_per_game_day = _get_seconds_per_game_day()
	# Register with TreeManager for batched updates (reused for all flora)
	var root = get_tree().current_scene
	plant_manager = root.find_child("TreeManager", true, false)
	if plant_manager and plant_manager.has_method("register_tree"):
		plant_manager.register_tree(self)

	# Configure optional collision body for mouse picking (layer 4)
	collision_body = find_child("StaticBody3D", true, false) as StaticBody3D
	if collision_body:
		collision_body.set_collision_layer_value(1, false)
		collision_body.set_collision_layer_value(3, false)
		collision_body.set_collision_layer_value(4, true)
		# do not collide with anything actively
		collision_body.set_collision_mask_value(1, false)

	# Seasonal setup (whitening in winter) for the plant model
	_setup_model_refs()
	_connect_to_time_manager.call_deferred()

func _exit_tree():
	if plant_manager and plant_manager.has_method("unregister_tree"):
		plant_manager.unregister_tree(self)

# Called by TreeManager in batches
func _logic_update(dt: float) -> void:
	# Track age in in-game days
	current_age += dt / seconds_per_game_day

	if current_age >= max_age:
		_remove_self()
		return

	# Update health from environment
	_update_health()

	# Reproduction timer scales with health: healthier plants reproduce faster
	# At 0 health, progress is paused; at 100% health, full speed
	if not is_winter:
		_repro_timer += (dt / seconds_per_game_day) * clamp(healthPercentage, 0.0, 1.0)
	if _repro_timer >= repro_interval_days:
		_repro_timer = 0.0
		_try_reproduce()

func _remove_self() -> void:
	queue_free()

func _try_reproduce() -> void:
	# Only reproduce if reasonably healthy
	if is_winter or healthPercentage < 0.5:
		return
	# Choose a random nearby point on terrain and request spawn via manager (budgeted)
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

# ---------- Seasonal helpers ----------
func _setup_model_refs() -> void:
	model_node = find_child("Model", true, false)
	_mesh_instances.clear()
	_original_materials.clear()
	if not model_node:
		return
	var stack: Array = [model_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			var mi = n as MeshInstance3D
			_mesh_instances.append(mi)
			var mat_count = mi.mesh.get_surface_count() if mi.mesh else 0
			var mats: Array = []
			for i in mat_count:
				var override_mat: Material = mi.get_surface_override_material(i)
				if override_mat:
					mats.append(override_mat)
				elif mi.mesh:
					mats.append(mi.mesh.surface_get_material(i))
				else:
					mats.append(null)
			_original_materials[mi] = mats
		for c in n.get_children():
			if c is Node:
				stack.append(c)

func _get_winter_material() -> StandardMaterial3D:
	if _winter_material == null:
		var m := StandardMaterial3D.new()
		m.resource_name = "Winter Plant Material"
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.92, 0.92, 0.96, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.08, 0.08, 0.12)
		_winter_material = m
	return _winter_material

func _connect_to_time_manager() -> void:
	var root = get_tree().current_scene
	var tm = root.find_child("TimeManager", true, false)
	if tm and tm.has_signal("season_changed"):
		tm.season_changed.connect(_on_season_changed)
		if tm.has_method("get_current_season") and tm.has_method("get_current_winter_factor"):
			var current_season = tm.get_current_season()
			var winter_factor = tm.get_current_winter_factor()
			_on_season_changed(current_season, winter_factor)

func _on_season_changed(_season: String, winter_factor: float) -> void:
	var should_winter = winter_factor > 0.5
	if should_winter != is_winter:
		is_winter = should_winter
		_update_seasonal_appearance()

func _update_seasonal_appearance() -> void:
	if _mesh_instances.is_empty():
		return
	if is_winter:
		var wm = _get_winter_material()
		for mi in _mesh_instances:
			if not (mi is MeshInstance3D):
				continue
			var mat_count = mi.mesh.get_surface_count() if mi.mesh else 0
			for i in mat_count:
				mi.set_surface_override_material(i, wm)
	else:
		for mi in _mesh_instances:
			if not (mi is MeshInstance3D):
				continue
			var mats: Array = _original_materials.get(mi, [])
			var mat_count = mi.mesh.get_surface_count() if mi.mesh else 0
			for i in mat_count:
				var orig = mats[i] if i < mats.size() else null
				mi.set_surface_override_material(i, orig)
