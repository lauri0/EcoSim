extends "res://Scripts/LifeForm.gd"
class_name Plant

# Environmental preferences and spacing
@export var ideal_altitude: float = 10.0
@export var min_viable_altitude: float = 0.0
@export var max_viable_altitude: float = 50.0

@export var blocking_radius: float = 5.0
@export var needs_free_radius: float = 6.0

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
