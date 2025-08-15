extends Node
class_name TreeManager

@export var tick_interval: float = 1.0
@export var grid_cell_size: float = 8.0
@export var max_tree_updates_per_frame: int = 30

var trees: Array = []
var _scene_cache: Dictionary = {}
var _terrain: Node3D
var _spawn_parent: Node

var _accumulator: float = 0.0
var _tree_index: int = 0
var _tree_quota: int = 0

# Spatial index
var _cell_to_trees: Dictionary = {}
var _tree_to_cell: Dictionary = {}

# Global reproduction per species (plants and trees). Units: instances per in-game day
var _reproduction_per_day: Dictionary = {}

# Animals: target times eaten per day per species (UI/browser species key)
var _eating_target_per_day: Dictionary = {}

# Temporary spawn reservations to avoid rapid double-spawns overlapping
var _reservations: Array = [] # of { pos: Vector3, radius: float, ttl: float }

# Helper: get nearby plants within range
func get_plants_within(pos: Vector3, query_range: float) -> Array:
	var result: Array = []
	var key = _cell_key(pos)
	var r_cells = int(ceil(query_range / grid_cell_size))
	for dx in range(-r_cells, r_cells + 1):
		for dz in range(-r_cells, r_cells + 1):
			var nkey = Vector3i(key.x + dx, 0, key.z + dz)
			var arr = _cell_to_trees.get(nkey, null)
			if arr == null:
				continue
			for t in arr:
				if is_instance_valid(t):
					var d2 = (t.global_position - pos).length_squared()
					if d2 <= query_range * query_range:
						result.append(t)
	return result

func can_spawn_plant_at(plant_scene: PackedScene, pos: Vector3) -> bool:
	# Reject out-of-bounds positions early
	if not _is_within_terrain_bounds(pos):
		return false
	if not plant_scene:
		return false
	var inst = plant_scene.instantiate()
	if not is_instance_valid(inst):
		return false
	var ok := true
	# Altitude constraint (if the instance exposes min/max viable altitude)
	var altitude: float = pos.y
	if _terrain and _terrain.has_method("get_height"):
		altitude = _terrain.get_height(pos.x, pos.z)
	var has_min_alt := false
	var has_max_alt := false
	var min_alt: float = 0.0
	var max_alt: float = 0.0
	if inst and inst.has_method("get"):
		var vmin = inst.get("min_viable_altitude")
		if typeof(vmin) == TYPE_FLOAT or typeof(vmin) == TYPE_INT:
			has_min_alt = true
			min_alt = float(vmin)
		var vmax = inst.get("max_viable_altitude")
		if typeof(vmax) == TYPE_FLOAT or typeof(vmax) == TYPE_INT:
			has_max_alt = true
			max_alt = float(vmax)
	if ok and (has_min_alt or has_max_alt):
		if (has_min_alt and altitude < min_alt) or (has_max_alt and altitude > max_alt):
			ok = false
	# Plants define spacing/neighbor constraints via exported properties
	var needs_free_radius: float = 0.0
	var has_nfr: bool = false
	if inst and inst.has_method("get"):
		var v = inst.get("needs_free_radius")
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			needs_free_radius = float(v)
			has_nfr = true
	if has_nfr and not is_space_free(pos, needs_free_radius):
		ok = false
	# Neighbor constraints
	var neighbor_range: float = 0.0
	var required_neighbors: Array = []
	var forbidden_neighbors: Array = []
	if inst and inst.has_method("get"):
		var nr = inst.get("neighbor_range")
		if typeof(nr) == TYPE_FLOAT or typeof(nr) == TYPE_INT:
			neighbor_range = float(nr)
		var reqn = inst.get("required_neighbors")
		if typeof(reqn) == TYPE_ARRAY:
			required_neighbors = reqn
		var forn = inst.get("forbidden_neighbors")
		if typeof(forn) == TYPE_ARRAY:
			forbidden_neighbors = forn
	var neighbors: Array = []
	if ok and neighbor_range > 0.0:
		neighbors = get_plants_within(pos, neighbor_range)
	# Build name set and type flags (tree detection via method unique to trees)
	var name_set: Dictionary = {}
	var has_tree: bool = false
	for n in neighbors:
		if n is LifeForm:
			name_set[(n as LifeForm).species_name] = true
		if n and n.has_method("get_state_name"):
			has_tree = true
	# required neighbors
	for req in required_neighbors:
		if req == "TreeBase":
			if not has_tree:
				ok = false
				break
		elif not name_set.has(req):
			ok = false
			break
	# forbidden neighbors
	if ok:
		for forb in forbidden_neighbors:
			if forb == "TreeBase" and has_tree:
				ok = false
				break
			elif name_set.has(forb):
				ok = false
				break
	inst.queue_free()
	return ok

func _terrain_half_size() -> float:
	if _terrain and _terrain.has_method("get_size"):
		var s: float = _terrain.get_size()
		return s * 0.5
	return 64.0

func _is_within_terrain_bounds(pos: Vector3) -> bool:
	var half := _terrain_half_size()
	return abs(pos.x) <= half and abs(pos.z) <= half

func _ready():
	process_mode = Node.PROCESS_MODE_INHERIT
	var root = get_tree().current_scene
	_terrain = root.find_child("Terrain", true, false) as Node3D
	_spawn_parent = _terrain.get_parent() if _terrain else root

func _cell_key(pos: Vector3) -> Vector3i:
	var x = int(floor(pos.x / grid_cell_size))
	var z = int(floor(pos.z / grid_cell_size))
	return Vector3i(x, 0, z)

func register_tree(tree: Node3D) -> void:
	if not tree or trees.has(tree):
		return
	trees.append(tree)
	# Add to spatial index
	var key = _cell_key(tree.global_position)
	if not _cell_to_trees.has(key):
		_cell_to_trees[key] = []
	_cell_to_trees[key].append(tree)
	_tree_to_cell[tree] = key

func unregister_tree(tree: Node3D) -> void:
	if trees.has(tree):
		trees.erase(tree)
	# Remove from spatial index
	if _tree_to_cell.has(tree):
		var key = _tree_to_cell[tree]
		_tree_to_cell.erase(tree)
		if _cell_to_trees.has(key):
			_cell_to_trees[key].erase(tree)
			if _cell_to_trees[key].is_empty():
				_cell_to_trees.erase(key)

func update_tree_cell(tree: Node3D) -> void:
	# Call this when a tree may have moved between cells
	var new_key = _cell_key(tree.global_position)
	var old_key = _tree_to_cell.get(tree, null)
	if old_key == new_key:
		return
	if old_key != null and _cell_to_trees.has(old_key):
		_cell_to_trees[old_key].erase(tree)
		if _cell_to_trees[old_key].is_empty():
			_cell_to_trees.erase(old_key)
	if not _cell_to_trees.has(new_key):
		_cell_to_trees[new_key] = []
	_cell_to_trees[new_key].append(tree)
	_tree_to_cell[tree] = new_key

func is_space_free(pos: Vector3, radius: float) -> bool:
	# Query neighboring cells around pos within radius
	var key = _cell_key(pos)
	var r_cells = int(ceil(radius / grid_cell_size))
	for dx in range(-r_cells, r_cells + 1):
		for dz in range(-r_cells, r_cells + 1):
			var nkey = Vector3i(key.x + dx, 0, key.z + dz)
			var arr = _cell_to_trees.get(nkey, null)
			if arr == null:
				continue
			for t in arr:
				if is_instance_valid(t):
					var d2 = (t.global_position - pos).length_squared()
					if d2 < radius * radius:
						return false
	# Also honor temporary reservations (sum of radii)
	for res in _reservations:
		var rpos: Vector3 = res.get("pos", Vector3.ZERO)
		var rrad: float = float(res.get("radius", 0.0))
		var d2 = (rpos - pos).length_squared()
		# Allow the spawn that created the reservation at this exact position to proceed
		if d2 <= 0.0001:
			continue
		var sumr = radius + rrad
		if d2 < sumr * sumr:
			return false
	return true

func _process(delta: float) -> void:
	_accumulator += delta

	if _accumulator >= tick_interval:
		var steps: int = int(floor(_accumulator / tick_interval))
		_accumulator -= steps * tick_interval
		_tree_quota += steps * trees.size()

	# Process a limited number of trees this frame (smear work across frames)
	var trees_processed: int = 0
	while _tree_quota > 0 and trees_processed < max_tree_updates_per_frame and trees.size() > 0:
		# Compact invalid entries lazily
		if _tree_index >= trees.size():
			_tree_index = 0
		var t = trees[_tree_index]
		if not is_instance_valid(t):
			trees.remove_at(_tree_index)
			continue
		if t.has_method("_logic_update"):
			t._logic_update(tick_interval)
			update_tree_cell(t)
		_tree_index += 1
		trees_processed += 1
		_tree_quota -= 1

	# Age out reservations
	if _reservations.size() > 0:
		for res in _reservations:
			res["ttl"] = float(res.get("ttl", 0.0)) - delta
		# remove expired
		for i in range(_reservations.size() - 1, -1, -1):
			if float(_reservations[i].get("ttl", 0.0)) <= 0.0:
				_reservations.remove_at(i)

func _get_tree_scene(species: String) -> PackedScene:
	if _scene_cache.has(species):
		return _scene_cache[species]
	var path = "res://Scenes/Trees/%s.tscn" % species
	var packed: PackedScene = load(path)
	if packed:
		_scene_cache[species] = packed
	return packed

func _get_plant_scene(plant_name: String) -> PackedScene:
	# Cache plants separately by prefixing key
	var key = "PLANT::" + plant_name
	if _scene_cache.has(key):
		return _scene_cache[key]
	var path = "res://Scenes/SmallPlants/%s.tscn" % plant_name
	var packed: PackedScene = load(path)
	if packed:
		_scene_cache[key] = packed
	return packed

func request_smallplant_spawn(plant_name: String, pos: Vector3) -> void:
	var scene = _get_plant_scene(plant_name)
	if not scene:
		return
	if not can_spawn_plant_at(scene, pos):
		return
	if is_instance_valid(_spawn_parent):
		var inst = scene.instantiate()
		_spawn_parent.add_child(inst)
		inst.global_position = pos

func request_tree_spawn(species: String, pos: Vector3) -> void:
	var scene = _get_tree_scene(species)
	if not scene:
		return
	if not can_spawn_plant_at(scene, pos):
		return
	if is_instance_valid(_spawn_parent):
		var inst = scene.instantiate()
		_spawn_parent.add_child(inst)
		inst.global_position = pos
		# Force full growth on spawn for convenience testing
		if inst is TreeBase:
			var t := inst as TreeBase
			t.growth_progress = t.max_growth_progress
			t.state = t.TreeState.MATURE
			t.state_percentage = 0.0
			if t.has_method("_update_scale"):
				t._update_scale()

# Spawn reservations
func reserve_for_scene(plant_scene: PackedScene, pos: Vector3, ttl: float = 1.0) -> bool:
	var radius: float = 0.0
	if plant_scene:
		var inst = plant_scene.instantiate()
		if inst and inst.has_method("get"):
			var v = inst.get("needs_free_radius")
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				radius = float(v)
		inst.queue_free()
	if radius <= 0.0:
		return true # nothing to reserve
	if not is_space_free(pos, radius):
		return false
	_reservations.append({"pos": pos, "radius": radius, "ttl": ttl})
	return true

# ---------- Global reproduction system ----------

func add_reproduction(species: String, amount: float = 1.0) -> void:
	var current: float = _reproduction_per_day.get(species, 0.0)
	_reproduction_per_day[species] = current + amount

func get_reproduction(species: String) -> float:
	return float(_reproduction_per_day.get(species, 0.0))

func get_total_living(species: String) -> int:
	var count: int = 0
	for n in trees:
		if not is_instance_valid(n):
			continue
		if n is LifeForm:
			if (n as LifeForm).species_name == species:
				count += 1
	return count

# ---------- Animal daily eating targets ----------

func add_eating_target(species: String, amount: int = 1) -> void:
	var current: int = int(_eating_target_per_day.get(species, 1))
	_eating_target_per_day[species] = current + amount

func get_eating_target(species: String) -> int:
	return int(_eating_target_per_day.get(species, 1))
