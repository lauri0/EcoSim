extends Node3D
class_name LifeForm

# Common lifeform properties
@export var species_name: String = "Unknown"
@export var max_age: float = 300.0

# Common runtime state
var current_age: float = 0.0
var healthPercentage: float = 1.0

# Hooks for derived classes to override if needed
func _start_dying() -> void:
    pass

func _remove_self() -> void:
    queue_free()


