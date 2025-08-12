extends LifeForm
class_name Plant

# Environmental preferences and spacing
@export var ideal_altitude: float = 10.0
@export var min_viable_altitude: float = 0.0
@export var max_viable_altitude: float = 50.0

@export var blocking_radius: float = 5.0
@export var needs_free_radius: float = 6.0

# Neighbor ecology constraints
@export var required_neighbors: Array[String] = []
@export var forbidden_neighbors: Array[String] = []
@export var neighbor_range: float = 5.0

# Reproduction parameters (shared by all plants)
@export var repro_interval_days: float = 0.5

# Shared health update based on altitude
func _update_health() -> void:
	var current_altitude: float = global_position.y

	if abs(current_altitude - ideal_altitude) < 0.1:
		healthPercentage = 1.0
		return

	if current_altitude < min_viable_altitude or current_altitude > max_viable_altitude:
		healthPercentage = 0.0
		return

	var distance_from_ideal: float = abs(current_altitude - ideal_altitude)
	var max_distance_below: float = ideal_altitude - min_viable_altitude
	var max_distance_above: float = max_viable_altitude - ideal_altitude
	var max_distance: float = max_distance_above if current_altitude > ideal_altitude else max_distance_below

	if max_distance <= 0.0:
		healthPercentage = 1.0
		return

	var health_ratio: float = 1.0 - (distance_from_ideal / max_distance)
	healthPercentage = 0.25 + (health_ratio * 0.75)
	healthPercentage = clamp(healthPercentage, 0.0, 1.0)

# Advance reproduction timer and fire events. Call from subclass logic tick.
func _tick_reproduction(_dt: float, _seconds_per_game_day: float, _is_winter: bool) -> void:
	# Natural/autonomous reproduction disabled. Reproduction is handled by LifeFormReproManager.
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
	var dist = randf_range(repro_radius * 0.25, repro_radius)
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
