extends Node
class_name TreeManager

@export var tick_interval: float = 1.0
@export var seed_tick_interval: float = 0.25
@export var grid_cell_size: float = 8.0
@export var max_tree_updates_per_frame: int = 30
@export var max_seed_updates_per_frame: int = 20
@export var max_germinations_per_frame: int = 8

var trees: Array = []
var seeds: Array = []
var _germination_queue: Array = [] # of {species: String, position: Vector3}
var _scene_cache: Dictionary = {}
var _terrain: Node3D
var _spawn_parent: Node

var _accumulator: float = 0.0
var _seed_accumulator: float = 0.0
var _tree_index: int = 0
var _seed_index: int = 0
var _tree_quota: int = 0
var _seed_quota: int = 0

# Spatial index
var _cell_to_trees: Dictionary = {}
var _tree_to_cell: Dictionary = {}

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
	return true

func register_seed(seed_node: Node) -> void:
	if seed_node and not seeds.has(seed_node):
		seeds.append(seed_node)

func unregister_seed(seed_node: Node) -> void:
	if seeds.has(seed_node):
		seeds.erase(seed_node)

func _process(delta: float) -> void:
	_accumulator += delta
	_seed_accumulator += delta

	if _accumulator >= tick_interval:
		var steps: int = int(floor(_accumulator / tick_interval))
		_accumulator -= steps * tick_interval
		_tree_quota += steps * trees.size()

	if _seed_accumulator >= seed_tick_interval:
		var ssteps: int = int(floor(_seed_accumulator / seed_tick_interval))
		_seed_accumulator -= ssteps * seed_tick_interval
		_seed_quota += ssteps * seeds.size()

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

	# Process a limited number of seeds this frame
	var seeds_processed: int = 0
	while _seed_quota > 0 and seeds_processed < max_seed_updates_per_frame and seeds.size() > 0:
		if _seed_index >= seeds.size():
			_seed_index = 0
		var s = seeds[_seed_index]
		if not is_instance_valid(s):
			seeds.remove_at(_seed_index)
			continue
		if s.has_method("_manager_tick"):
			s._manager_tick(seed_tick_interval)
		_seed_index += 1
		seeds_processed += 1
		_seed_quota -= 1

	# Process limited number of germinations per frame
	var germ_processed := 0
	while germ_processed < max_germinations_per_frame and _germination_queue.size() > 0:
		var req: Dictionary = _germination_queue.pop_front()
		if not req:
			continue
		var species: String = req.get("species", "")
		var pos: Vector3 = req.get("position", Vector3.ZERO)
		var scene := _get_tree_scene(species)
		if scene:
			var inst = scene.instantiate()
			if is_instance_valid(_spawn_parent):
				_spawn_parent.add_child(inst)
				inst.global_position = pos
		germ_processed += 1

func _get_tree_scene(species: String) -> PackedScene:
	if _scene_cache.has(species):
		return _scene_cache[species]
	var path = "res://Scenes/Trees/%s.tscn" % species
	var packed: PackedScene = load(path)
	if packed:
		_scene_cache[species] = packed
	return packed

func request_germination(species: String, position: Vector3) -> void:
	_germination_queue.append({"species": species, "position": position})
