extends "res://Scripts/Plant.gd"
class_name SmallPlant

# Small plants are simple lifeforms that do not grow in stages.
# They age, have altitude-based health, and die when reaching max_age.

var seconds_per_game_day: float = 90.0
var plant_manager: Node

func _ready():
    seconds_per_game_day = _get_seconds_per_game_day()
    # Register with TreeManager for batched updates (reused for all flora)
    var root = get_tree().current_scene
    plant_manager = root.find_child("TreeManager", true, false)
    if plant_manager and plant_manager.has_method("register_tree"):
        plant_manager.register_tree(self)

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

func _remove_self() -> void:
    queue_free()


