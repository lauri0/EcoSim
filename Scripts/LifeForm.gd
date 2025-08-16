extends Node3D
class_name LifeForm

# Common lifeform properties
@export var species_name: String = "Unknown"
@export var price: int = 10
@export var max_hp: int = 10
@export var max_age: float = 30.0 # in-game days
@export var repro_radius: float = 8.0

# Common runtime state
var current_age: float = 0.0
var current_hp: int = max_hp

# Hooks for derived classes to override if needed
func _start_dying() -> void:
	pass

func _remove_self() -> void:
	queue_free()

# Apply direct hit point damage. Returns true if this call destroyed the lifeform
func apply_damage(amount: int) -> bool:
	current_hp -= int(amount)
	if current_hp <= 0:
		_remove_self()
		return true
	return false

# Fractional health in 0..1 derived from HP
func get_health_fraction() -> float:
	if max_hp <= 0:
		return 0.0
	return clamp(float(current_hp) / float(max_hp), 0.0, 1.0)

func _enter_tree():
	# Auto-register with LifeFormReproManager when added to the scene
	# Ensure HP initialized from max_hp after any scene overrides
	current_hp = max_hp
	var root = get_tree().current_scene
	if root:
		var rm = root.find_child("LifeFormReproManager", true, false)
		if rm and rm.has_method("register_lifeform"):
			rm.register_lifeform(self)

func _exit_tree():
	# Unregister on removal
	var root = get_tree().current_scene
	if root:
		var rm = root.find_child("LifeFormReproManager", true, false)
		if rm and rm.has_method("unregister_lifeform"):
			rm.unregister_lifeform(self)

# Time conversion helper: real seconds per in-game day
func _get_seconds_per_game_day() -> float:
	var root = get_tree().current_scene
	if root:
		var tm = root.find_child("TimeManager", true, false)
		if tm:
			return tm.day_duration_seconds
	# Fallback to default derived from TimeManager defaults (360s/year, 4 days/year)
	return 90.0
