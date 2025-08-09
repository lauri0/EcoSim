extends Node3D
class_name LifeForm

# Common lifeform properties
@export var species_name: String = "Unknown"
@export var price: int = 10
@export var max_age: float = 300.0 # in-game days

# Common runtime state
var current_age: float = 0.0
var healthPercentage: float = 1.0

# Hooks for derived classes to override if needed
func _start_dying() -> void:
	pass

func _remove_self() -> void:
	queue_free()

# Time conversion helper: real seconds per in-game day
func _get_seconds_per_game_day() -> float:
	var root = get_tree().current_scene
	if root:
		var tm = root.find_child("TimeManager", true, false)
		if tm:
			return tm.day_duration_seconds
	# Fallback to default derived from TimeManager defaults (360s/year, 4 days/year)
	return 90.0
