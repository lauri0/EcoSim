extends "res://Scripts/SmallPlant.gd"
class_name WaterSurfacePlant

@export var water_level: float = 0.0

func _ready():
	# Use SmallPlant setup (registration, picking body, seasons)
	super._ready()
	_snap_to_water()

func _logic_update(dt: float) -> void:
	# Run base small plant logic (age, health, reproduction tick)
	super._logic_update(dt)

func _update_health() -> void:
	# Water-surface plants are healthy only where terrain is underwater
	var wl := _get_global_water_level()
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	var th: float = global_position.y
	if terrain and terrain.has_method("get_height"):
		th = terrain.get_height(global_position.x, global_position.z)
	# Healthy if the terrain at this XZ is at or below water level
	if th <= wl:
		healthPercentage = 1.0
	else:
		healthPercentage = 0.0

func _snap_to_water() -> void:
	var wl := _get_global_water_level()
	if abs(global_position.y - wl) > 0.0001:
		var p = global_position
		p.y = wl
		global_position = p

func _get_global_water_level() -> float:
	# Prefer SidePanel configuration if present; otherwise use local export (default 0.0)
	var root = get_tree().current_scene
	if root:
		var side = root.find_child("SidePanel", true, false)
		if side and side.has_method("get"):
			var v = side.get("water_level")
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				return float(v)
	return water_level

func is_water_surface_plant() -> bool:
	return true
