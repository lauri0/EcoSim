extends LifeForm
class_name Plant

# Environmental preferences and spacing
@export var min_viable_altitude: float = 0.0
@export var max_viable_altitude: float = 50.0

@export var blocking_radius: float = 5.0
@export var needs_free_radius: float = 6.0

# Neighbor ecology constraints
@export var required_neighbors: Array[String] = []
@export var forbidden_neighbors: Array[String] = []
@export var neighbor_range: float = 5.0

# Shared health update based on altitude
func _update_health() -> void:
	var current_altitude: float = global_position.y

	healthPercentage = 1.0

	if current_altitude < min_viable_altitude or current_altitude > max_viable_altitude:
		healthPercentage = 0.0
		return

# Default reproduction: ask manager to spawn same species near this plant
func _try_reproduce() -> void:
	if healthPercentage < 0.5:
		return
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	if not terrain or not terrain.has_method("get_height"):
		return
	var angle = randf() * TAU
	var dist = randf_range(blocking_radius, repro_radius)
	var offset = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var pos = global_position + offset
	var y = terrain.get_height(pos.x, pos.z)
	var spawn_pos = Vector3(pos.x, y, pos.z)
	_request_spawn(spawn_pos)
	_on_reproduction_event()

# Default spawn request goes to smallplant spawner; trees override
func _request_spawn(spawn_pos: Vector3) -> void:
	var root = get_tree().current_scene
	var tm = root.find_child("TreeManager", true, false)
	if tm and tm.has_method("request_smallplant_spawn"):
		tm.request_smallplant_spawn(species_name, spawn_pos)

# Hook for subclasses for visual side-effects on reproduction
func _on_reproduction_event() -> void:
	pass
