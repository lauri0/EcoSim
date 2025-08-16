extends Node
class_name LifeFormReproManager

# Tracks living lifeforms by a normalized species key (UI/species browser key)
# Key normalization removes spaces to match entries like "EuropeanHare".
var _species_to_lifeforms: Dictionary = {}
# Daily schedule: species_key -> Dictionary[int hour, int count]
var _daily_schedule: Dictionary = {}

func _ready():
	# Listen to hourly updates to detect start-of-day
	var root = get_tree().current_scene
	var tm = root.find_child("TimeManager", true, false)
	if tm and tm.has_signal("time_updated"):
		tm.time_updated.connect(_on_time_updated)

func register_lifeform(lf: LifeForm) -> void:
	if not is_instance_valid(lf):
		return
	var key := _to_species_key(lf)
	if not _species_to_lifeforms.has(key):
		_species_to_lifeforms[key] = []
	var arr: Array = _species_to_lifeforms[key]
	if arr.has(lf):
		return
	arr.append(lf)

func unregister_lifeform(lf: LifeForm) -> void:
	var key := _to_species_key(lf)
	if _species_to_lifeforms.has(key):
		var arr: Array = _species_to_lifeforms[key]
		arr.erase(lf)
		if arr.is_empty():
			_species_to_lifeforms.erase(key)

func get_total_living(species_or_key: String) -> int:
	# Public accessor for UI/managers: returns number of living individuals
	# Accepts either display species name or normalized key; normalization removes spaces
	var key := species_or_key.replace(" ", "")
	var arr: Array = _species_to_lifeforms.get(key, [])
	# Compact invalid references defensively
	var alive: int = 0
	for n in arr:
		if is_instance_valid(n):
			alive += 1
	return alive

func _to_species_key(lf: LifeForm) -> String:
	# Normalize to UI/browser key by removing spaces.
	return lf.species_name.replace(" ", "")

func _on_time_updated(_year: int, _season: String, hour: int) -> void:
	# Rebuild schedule at start of each in-game day
	if hour == 0:
		_build_todays_schedule()
	# Execute any scheduled reproduction events for this hour
	_run_scheduled_reproduction(hour)

func _build_todays_schedule() -> void:
	var root = get_tree().current_scene
	var tmgr = root.find_child("TreeManager", true, false)
	if not tmgr:
		return
	_daily_schedule.clear()
	# For each species key with living individuals, schedule births across the day
	for key in _species_to_lifeforms.keys():
		var rpd: float = 0.0
		if tmgr.has_method("get_reproduction"):
			rpd = tmgr.get_reproduction(key)
		var births: int = int(floor(rpd))
		if births <= 0:
			continue
		# Compute evenly spaced integer hours using round to nearest hour for symmetry
		# Times h_k = round(k * 24 / (births + 1)), k=1..births
		var schedule_for_species: Dictionary = {}
		for k in range(1, births + 1):
			var h: int = int(round(float(k) * 24.0 / float(births + 1)))
			h = clamp(h, 0, 23)
			schedule_for_species[h] = int(schedule_for_species.get(h, 0)) + 1
		_daily_schedule[key] = schedule_for_species

func _run_scheduled_reproduction(hour: int) -> void:
	if _daily_schedule.is_empty():
		return
	var root = get_tree().current_scene
	var tmgr = root.find_child("TreeManager", true, false)
	var terrain = root.find_child("Terrain", true, false)
	if not tmgr:
		return
	for key in _daily_schedule.keys():
		var schedule_for_species: Dictionary = _daily_schedule.get(key, {})
		var count: int = int(schedule_for_species.get(hour, 0))
		if count <= 0:
			continue
		for i in range(count):
			_perform_one_reproduction(key, tmgr, terrain)

func _perform_one_reproduction(species_key: String, tmgr: Node, terrain: Node) -> void:
	# Build candidate list of living individuals with health >= 50%
	var arr: Array = _species_to_lifeforms.get(species_key, [])
	var candidates: Array = []
	for n in arr:
		if not is_instance_valid(n):
			continue
		var lf := n as LifeForm
		if not lf:
			continue
		if lf.get_health_fraction() >= 0.5:
			candidates.append(lf)
	if candidates.is_empty():
		return
	# Pick one random candidate
	candidates.shuffle()
	var parent: LifeForm = candidates[0]
	# Choose strategy depending on whether the parent is a water-surface plant
	var is_water_surface_parent: bool = false
	if parent and parent.has_method("is_water_surface_plant"):
		is_water_surface_parent = bool(parent.is_water_surface_plant())
	# Try multiple times; water needs a few more attempts to find an underwater spot
	var max_attempts: int = 3
	if is_water_surface_parent:
		max_attempts = 8
	var spawned: bool = false
	for attempt in range(max_attempts):
		var pos: Vector3
		if is_water_surface_parent:
			pos = _pick_spawn_near_water(parent, terrain)
		else:
			pos = _pick_spawn_near(parent, terrain)
		spawned = _try_spawn_same_species(parent, species_key, pos, tmgr, terrain)
		if spawned:
			break
	# Done (if all attempts failed, skip silently)

func _pick_spawn_near(plf: LifeForm, terrain: Node) -> Vector3:
	var angle = randf() * TAU
	var dist = randf_range(plf.repro_radius * 0.25, plf.repro_radius)
	var offset = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var base = plf.global_position + offset
	if terrain and terrain.has_method("get_height"):
		base.y = terrain.get_height(base.x, base.z)
	return base

func _pick_spawn_near_water(plf: LifeForm, terrain: Node) -> Vector3:
	# Try a handful of samples around the parent that are underwater
	var wl := _get_water_level()
	for _i in range(6):
		var angle = randf() * TAU
		var dist = randf_range(plf.repro_radius * 0.25, plf.repro_radius)
		var offset = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var base = plf.global_position + offset
		var th: float = base.y
		if terrain and terrain.has_method("get_height"):
			th = terrain.get_height(base.x, base.z)
		if th <= wl:
			base.y = wl
			return base
	# Fallback: return parent position at water level
	var p = plf.global_position
	p.y = wl
	return p

func _try_spawn_same_species(parent: LifeForm, species_key: String, pos: Vector3, tmgr: Node, terrain: Node) -> bool:
	# Trees: pre-validate then request spawn
	if parent is TreeBase:
		var scene_path = "res://Scenes/Trees/%s.tscn" % species_key
		var packed: PackedScene = load(scene_path)
		if not packed:
			return false
		if tmgr.has_method("can_spawn_plant_at") and not tmgr.can_spawn_plant_at(packed, pos):
			return false
		if tmgr.has_method("request_tree_spawn"):
			tmgr.request_tree_spawn(species_key, pos)
			return true
		return false
	# Small plants: pre-validate then request spawn
	if parent is SmallPlant:
		var plant_scene_path = "res://Scenes/SmallPlants/%s.tscn" % species_key
		var plant_packed: PackedScene = load(plant_scene_path)
		if not plant_packed:
			return false
		# If water-surface parent, prefer setting Y to water level for clarity (manager also snaps)
		if parent and parent.has_method("is_water_surface_plant") and parent.is_water_surface_plant():
			pos.y = _get_water_level()
		if tmgr.has_method("can_spawn_plant_at") and not tmgr.can_spawn_plant_at(plant_packed, pos):
			return false
		if tmgr.has_method("request_smallplant_spawn"):
			tmgr.request_smallplant_spawn(species_key, pos)
			return true
		return false
	# Animals: instantiate directly after validation
	var animal_scene_path = "res://Scenes/Animals/%s.tscn" % species_key
	var animal_packed: PackedScene = load(animal_scene_path)
	if not animal_packed:
		return false
	if tmgr.has_method("can_spawn_plant_at") and not tmgr.can_spawn_plant_at(animal_packed, pos):
		return false
	var parent_node: Node = terrain.get_parent() if terrain else get_tree().current_scene
	if not is_instance_valid(parent_node):
		parent_node = get_tree().current_scene
	var inst = animal_packed.instantiate()
	parent_node.add_child(inst)
	if terrain and terrain.has_method("get_height"):
		pos.y = terrain.get_height(pos.x, pos.z)
	inst.global_position = pos
	if inst is Node3D:
		(inst as Node3D).rotation.y = randf() * TAU
	return true

func _get_water_level() -> float:
	var root = get_tree().current_scene
	if root:
		var side = root.find_child("SidePanel", true, false)
		if side and side.has_method("get"):
			var v = side.get("water_level")
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				return float(v)
	return 0.0
