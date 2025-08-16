extends "res://Scripts/Animal.gd"
class_name Bird

# Default cruising altitude above terrain while exploring (meters)
@export var flight_height: float = 6.0
@export var model_scene_path: String = ""

# State machine (mirrors Mammal pattern, with flying logic)
class State:
	var bird
	func _init(b):
		bird = b
	func name() -> String:
		return ""
	func enter(_prev: String) -> void:
		pass
	func exit(_next: String) -> void:
		pass
	func tick(_dt: float) -> void:
		pass

class ExploringState:
	extends State
	func name() -> String:
		return "exploring"
	func enter(_prev: String) -> void:
		if not bird._has_target:
			bird._choose_new_wander_target()
		bird._play_state_anim("exploring")
	func tick(dt: float) -> void:
		bird.forage_check_timer -= dt
		if bird.forage_check_timer <= 0.0:
			bird.forage_check_timer = 2.0
			bird.food_target = bird.find_food_in_range(bird.global_position, bird.vision_range)
			if is_instance_valid(bird.food_target):
				bird._set_move_target(bird._xz_of_target(bird.food_target))
				bird.switch_state("flying_to_food")
				return
		if bird._has_target:
			bird._tick_flying_navigation(dt, bird._cruising_y())
			bird._play_state_anim("exploring")
			if bird.nav_agent and (Time.get_ticks_msec() % 500) < int(dt * 1000.0):
				bird.nav_agent.set_target_position(bird._wander_target)
			if bird._nav_arrived():
				bird._has_target = false
		else:
			bird._choose_new_wander_target()

class FlyingToFoodState:
	extends State
	func name() -> String:
		return "flying_to_food"
	func enter(_prev: String) -> void:
		if is_instance_valid(bird.food_target):
			# Aim for the projection of the food on the raised bird navmesh
			bird._set_move_target(bird._xz_of_target(bird.food_target))
		else:
			bird.switch_state("exploring")
			return
		bird._play_state_anim("moving_to_food")
	func tick(dt: float) -> void:
		if not is_instance_valid(bird.food_target):
			bird.switch_state("exploring")
			return
		bird.forage_check_timer -= dt
		if bird.forage_check_timer <= 0.0:
			bird.forage_check_timer = 2.0
			# Refresh target toward the navmesh projection of food
			bird._set_move_target(bird._xz_of_target(bird.food_target))
		# While pathing on the raised navmesh, follow the navmesh height at the next path point
		var desired_y: float = bird._wander_target.y
		if bird.nav_agent:
			var np: Vector3 = bird.nav_agent.get_next_path_position()
			if bird.nav_agent.is_navigation_finished():
				desired_y = bird._wander_target.y
			else:
				desired_y = np.y
		bird._tick_flying_navigation(dt, desired_y)
		bird._play_state_anim("moving_to_food")
		var reached := false
		if bird.nav_agent:
			reached = bird.nav_agent.is_navigation_finished()
		else:
			reached = (bird.global_position - Vector3(bird._wander_target.x, bird.global_position.y, bird._wander_target.z)).length() <= 0.4
		if reached:
			bird.switch_state("descending_to_food")

class DescendingToFoodState:
	extends State
	func name() -> String:
		return "descending_to_food"
	func enter(_prev: String) -> void:
		# Stop horizontal navigation while descending vertically
		if bird.nav_agent:
			bird.nav_agent.set_target_position(bird.global_position)
		bird._play_state_anim("moving_to_food")
	func tick(dt: float) -> void:
		if not is_instance_valid(bird.food_target):
			bird.switch_state("ascending_to_altitude")
			return
		# Vertical descent towards the actual food position (no horizontal drift)
		var target_pos: Vector3 = bird._food_actual_position(bird.food_target)
		var reached: bool = bird._tick_vertical_move(target_pos.y, dt)
		if reached:
			# If food is still available, start feeding; otherwise, ascend back
			if bird._can_eat_target(bird.food_target):
				bird.switch_state("feeding")
			else:
				bird.switch_state("ascending_to_altitude")

class AscendingToAltitudeState:
	extends State
	func name() -> String:
		return "ascending_to_altitude"
	func enter(_prev: String) -> void:
		# Stop any nav movement during vertical ascent
		if bird.nav_agent:
			bird.nav_agent.set_target_position(bird.global_position)
		bird._play_state_anim("exploring")
	func tick(dt: float) -> void:
		var target_y: float = bird._cruising_y()
		var reached: bool = bird._tick_vertical_move(target_y, dt)
		if reached:
			bird._has_target = false
			bird.switch_state("exploring")

class FeedingState:
	extends State
	func name() -> String:
		return "feeding"
	func enter(_prev: String) -> void:
		bird._start_feeding()
		bird._play_state_anim("feeding")
	func tick(dt: float) -> void:
		bird._feeding_timer -= dt
		bird._play_state_anim("feeding")
		if bird._feeding_timer > 0.0:
			return
		if is_instance_valid(bird.food_target):
			# Prefer seeds on trees; never delete the whole tree
			if bird.food_target is TreeBase:
				var t: TreeBase = bird.food_target as TreeBase
				if bird._tree_has_seed(t) and t and t.has_method("_destroy_attached_seed"):
					t._destroy_attached_seed()
					bird._award_seed_revenue(t)
					bird._eaten_today += 1
			# Berry from bush if available (recheck berry still exists)
			elif bird.food_target is BerryBush and bird._bush_has_berry(bird.food_target):
				var b: BerryBush = bird.food_target as BerryBush
				b.consume_berry()
				bird._award_berry_revenue(b)
				bird._eaten_today += 1
			# Other animals/birds: deal damage; destroy only if HP <= 0
			elif bird.food_target is Animal:
				var a: Animal = bird.food_target as Animal
				if is_instance_valid(a):
					a.apply_damage(bird.eating_damage)
					bird._reward_for_eating(a)
					bird._eaten_today += 1
			# Fallback: generic edible nodes (e.g., small plants/lifeforms); prefer damage for lifeforms
			else:
				if bird.food_target is LifeForm:
					var lf: LifeForm = bird.food_target as LifeForm
					lf.apply_damage(bird.eating_damage)
					bird._reward_for_eating(lf)
					bird._eaten_today += 1
				elif bird.food_target.has_method("consume"):
					bird.food_target.consume()
				# Do not delete trees in any case
				elif not (bird.food_target is TreeBase):
					bird.food_target.queue_free()
			bird.food_target = null
		# After eating (or if food vanished), ascend back to cruising altitude
		bird.switch_state("ascending_to_altitude")

class RestingState:
	extends State
	func name() -> String:
		return "resting"
	func tick(_dt: float) -> void:
		bird._play_state_anim("resting")

var _states: Dictionary = {}
var _current_state: State
var _current_state_name: String = ""

# Reuse Mammal fields where sensible
var model_node: Node3D
var animation_player: AnimationPlayer
var _anim_lib: AnimationLibrary
var nav_agent: NavigationAgent3D
var pick_body: StaticBody3D

var _wander_target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var forage_check_timer: float = 0.0
var food_target: Node3D
var _feeding_timer: float = 0.0

func _ready():
	# Flying animals don't walk by default
	walk_speed = 0.0
	swim_speed = 0.0
	if fly_speed <= 0.0:
		fly_speed = 5.0

	# Ensure visual model
	model_node = find_child("Model", true, false)
	if model_node == null and model_scene_path != "":
		var packed: PackedScene = load(model_scene_path)
		if packed:
			var inst = packed.instantiate()
			inst.name = "Model"
			add_child(inst)
			model_node = inst
	if model_node:
		animation_player = model_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation_player == null:
			animation_player = AnimationPlayer.new()
			animation_player.name = "AnimationPlayer"
			model_node.add_child(animation_player)
		animation_player.root_node = model_node.get_path()
	if animation_dir != "" and animation_player:
		_load_animations_from_dir(animation_dir)

	# Navigation: reuse hare-sized agent for horizontal pathing
	nav_agent = find_child("NavigationAgent3D", true, false) as NavigationAgent3D
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child(nav_agent)
	nav_agent.radius = 0.25
	nav_agent.height = 0.6
	nav_agent.max_speed = fly_speed
	# Require getting closer to the goal before finishing navigation
	nav_agent.target_desired_distance = 0.25
	nav_agent.path_desired_distance = 0.25
	# Use only the raised bird navigation region (layer 2)
	if "navigation_layers" in nav_agent:
		nav_agent.navigation_layers = 2
	# Allow starting far above the navmesh when flying
	if "path_max_distance" in nav_agent:
		nav_agent.path_max_distance = max(50.0, flight_height + 10.0)
	if nav_agent.has_method("set_avoidance_enabled"):
		nav_agent.set_avoidance_enabled(false)
	elif "avoidance_enabled" in nav_agent:
		nav_agent.avoidance_enabled = false

	# Pick body for inspection (layer 4)
	pick_body = find_child("PickBody", true, false) as StaticBody3D
	if pick_body == null:
		pick_body = StaticBody3D.new()
		pick_body.name = "PickBody"
		add_child(pick_body)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.2
		capsule.height = 0.4
		shape.shape = capsule
		pick_body.add_child(shape)
		pick_body.set_collision_layer_value(1, false)
		pick_body.set_collision_layer_value(3, false)
		pick_body.set_collision_layer_value(4, true)
		pick_body.collision_mask = 0

	_create_state_machine()
	set_process(true)
	set_physics_process(false)

	# Anim mapping override for flying
	_state_anim_choices["exploring"] = ["Fly", "Walk"]
	_state_anim_choices["moving_to_food"] = ["Fly", "Walk"]
	_state_anim_choices["resting"] = ["Idle_A", "Idle"]
	_state_anim_choices["feeding"] = ["Eat", "Peck", "Idle"]

func _process(delta: float) -> void:
	_logic_update(delta)

func _logic_update(dt: float) -> void:
	# Age & rest handling from Animal
	current_age += dt / _get_seconds_per_game_day()
	if current_age >= max_age:
		_remove_self()
		return
	_refresh_daily_target_if_needed()
	if _has_met_daily_target():
		if _current_state_name != "resting":
			switch_state("resting")
		if _current_state:
			_current_state.tick(dt)
		return
	if _current_state == null:
		switch_state("exploring")
		return
	_current_state.tick(dt)

func _on_new_day() -> void:
	if _current_state_name == "resting":
		switch_state("exploring")

func _create_state_machine() -> void:
	_states.clear()
	_define_states()
	switch_state("exploring")

func _define_states() -> void:
	register_state("exploring", ExploringState.new(self))
	register_state("flying_to_food", FlyingToFoodState.new(self))
	register_state("descending_to_food", DescendingToFoodState.new(self))
	register_state("ascending_to_altitude", AscendingToAltitudeState.new(self))
	register_state("feeding", FeedingState.new(self))
	register_state("resting", RestingState.new(self))

func register_state(state_name: String, state: State) -> void:
	_states[state_name] = state

func switch_state(state_name: String) -> void:
	if _current_state_name == state_name:
		return
	var next: State = _states.get(state_name, null)
	if next == null:
		return
	if _current_state:
		_current_state.exit(state_name)
	var prev_name := _current_state_name
	_current_state = next
	_current_state_name = state_name
	_current_state.enter(prev_name)

# ------------ Flying helpers ------------
func _get_terrain_height_at(pos: Vector3) -> float:
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	if terrain and terrain.has_method("get_height"):
		return terrain.get_height(pos.x, pos.z)
	return pos.y

func _cruising_y() -> float:
	var y = _get_terrain_height_at(global_position) + flight_height
	return y

func _tick_flying_navigation(dt: float, desired_y: float) -> void:
	if not nav_agent:
		# Move directly toward wander target in 3D with altitude control
		var target3: Vector3 = Vector3(_wander_target.x, desired_y, _wander_target.z)
		_move_towards_3d(target3, fly_speed * dt)
		return
	nav_agent.max_speed = fly_speed
	var next_point: Vector3 = nav_agent.get_next_path_position()
	if nav_agent.is_navigation_finished():
		next_point = _wander_target
	var horiz = next_point - global_position
	horiz.y = 0.0
	var d = horiz.length()
	if d > 0.0001:
		var dir = horiz / d
		global_position += dir * fly_speed * dt
		if dir.length() > 0.0:
			rotation.y = atan2(dir.x, dir.z)
	# Adjust altitude smoothly toward desired_y
	var y_now = global_position.y
	var y_step = fly_speed * dt
	if abs(desired_y - y_now) <= y_step:
		global_position.y = desired_y
	else:
		global_position.y += signf(desired_y - y_now) * y_step

func _move_towards_3d(target: Vector3, max_step: float) -> bool:
	var to = target - global_position
	var dist = to.length()
	if dist <= 0.05:
		_has_target = false
		return true
	var dir = to / max(dist, 0.0001)
	global_position += dir * max_step
	if dir.length() > 0.0001:
		rotation.y = atan2(dir.x, dir.z)
	return false

func _nav_arrived() -> bool:
	var d = (global_position - _wander_target)
	d.y = 0.0
	return d.length() <= 0.35

func _xz_of_target(t: Node3D) -> Vector3:
	if not is_instance_valid(t):
		return _wander_target
	var p = t.global_position
	return Vector3(p.x, global_position.y, p.z)

func _desired_food_y(t: Node) -> float:
	if t is TreeBase and _tree_has_seed(t):
		var wp = _compute_tree_seed_world_position(t as TreeBase)
		return wp.y
	if t is SmallPlant:
		# Hover slightly above plant
		return (t as SmallPlant).global_position.y + 0.4
	if t is Animal:
		return (t as Animal).global_position.y + 0.2
	# Default to cruising
	return _cruising_y()

func _target_point_3d(t: Node) -> Vector3:
	var p = (t as Node3D).global_position if (t is Node3D) else global_position
	return p

func _choose_new_wander_target() -> void:
	var radius := 10.0
	var angle := randf() * TAU
	var offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var base = global_position + offset
	var y = _get_terrain_height_at(base) + flight_height
	base.y = y
	_wander_target = _project_to_navmesh(base)
	_has_target = true
	if nav_agent:
		nav_agent.set_target_position(_wander_target)

func _set_move_target(pos: Vector3) -> void:
	_wander_target = _project_to_navmesh(Vector3(pos.x, _cruising_y(), pos.z))
	_has_target = true
	if nav_agent:
		nav_agent.set_target_position(_wander_target)

func _project_to_navmesh(point: Vector3) -> Vector3:
	# Snap to the closest point on the bird navigation map (raised region on layer 2)
	if nav_agent and nav_agent.get_navigation_map() != RID():
		var map_rid: RID = nav_agent.get_navigation_map()
		return NavigationServer3D.map_get_closest_point(map_rid, point)
	return point

func _start_feeding() -> void:
	_feeding_timer = 2.0

# Move vertically toward target_y at fly_speed; returns true when reached
func _tick_vertical_move(target_y: float, dt: float) -> bool:
	var y_now := global_position.y
	var y_step := fly_speed * dt
	if abs(target_y - y_now) <= y_step:
		global_position.y = target_y
		return true
	global_position.y += signf(target_y - y_now) * y_step
	return false

# Determine the exact world position of the food item for descent
func _food_actual_position(t: Node) -> Vector3:
	if t is TreeBase and _tree_has_seed(t):
		return _compute_tree_seed_world_position(t as TreeBase)
	if t is Node3D:
		return (t as Node3D).global_position
	return global_position

# Check whether the target still has something edible
func _can_eat_target(t: Node) -> bool:
	if not is_instance_valid(t):
		return false
	if t is TreeBase:
		return _tree_has_seed(t)
	if t is BerryBush:
		return _bush_has_berry(t)
	if t is Animal:
		return is_instance_valid(t)
	# Generic edible nodes with consume() assumed available
	return true

# --------------- Food search override ---------------
func find_food_in_range(center: Vector3, search_range: float) -> Node3D:
	var candidates: Array[Node3D] = []
	# Trees with seeds
	if diet.has("TreeSeed"):
		var t = _find_tree_with_seed_in_range(center, search_range)
		if is_instance_valid(t):
			candidates.append(t)
	# Berry bushes with berries
	if diet.has("BerryBush") or diet.has("Berry") or diet.has("SmallPlant"):
		var b = _find_berry_bush_with_berry(center, search_range)
		if is_instance_valid(b):
			candidates.append(b)
	# Other animals/birds
	if diet.has("Animal") or diet.has("Mammal") or diet.has("Bird"):
		var a = _find_prey_animal(center, search_range)
		if is_instance_valid(a):
			candidates.append(a)
	# Fallback to base plant search
	var p = super.find_food_in_range(center, search_range)
	if is_instance_valid(p):
		candidates.append(p)
	# Choose nearest
	var best: Node3D = null
	var best_d2: float = INF
	for c in candidates:
		if not is_instance_valid(c):
			continue
		var d2 = (c.global_position - center).length_squared()
		if d2 < best_d2:
			best = c
			best_d2 = d2
	return best

func _find_tree_with_seed_in_range(center: Vector3, search_range: float) -> TreeBase:
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm and tm.has_method("get_plants_within"):
		var nearby = tm.get_plants_within(center, search_range)
		var best: TreeBase = null
		var best_d2: float = INF
		for n in nearby:
			if not is_instance_valid(n):
				continue
			if not (n is TreeBase):
				continue
			var tb: TreeBase = n as TreeBase
			if not _tree_has_seed(tb):
				continue
			var d2 = (tb.global_position - center).length_squared()
			if d2 < best_d2:
				best = tb
				best_d2 = d2
		return best
	return null

func _find_berry_bush_with_berry(center: Vector3, search_range: float) -> BerryBush:
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm and tm.has_method("get_plants_within"):
		var nearby = tm.get_plants_within(center, search_range)
		var best: BerryBush = null
		var best_d2: float = INF
		for n in nearby:
			if not is_instance_valid(n):
				continue
			if not (n is BerryBush):
				continue
			var bb: BerryBush = n as BerryBush
			if not _bush_has_berry(bb):
				continue
			var d2 = (bb.global_position - center).length_squared()
			if d2 < best_d2:
				best = bb
				best_d2 = d2
		return best
	return null

func _find_prey_animal(center: Vector3, search_range: float) -> Animal:
	var root = get_tree().current_scene
	var best: Animal = null
	var best_d2: float = INF
	# Scan scene tree for other animals
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		if n is Animal and n != self:
			# Filter by diet by type name or species name
			var a: Animal = n as Animal
			if diet.has("Animal") or diet.has(a.get_class()) or diet.has(a.species_name):
				# Only consider prey if we can deal at least their remaining HP in one bite
				if eating_damage >= a.current_hp:
					var d2 = ((a as Node3D).global_position - center).length_squared()
					if d2 <= search_range * search_range and d2 < best_d2:
						best = a
						best_d2 = d2
		for c in n.get_children():
			if c is Node:
				queue.append(c)
	return best

func _tree_has_seed(tree: Node) -> bool:
	if not is_instance_valid(tree):
		return false
	if not (tree is TreeBase):
		return false
	var tb: TreeBase = tree as TreeBase
	var present: bool = false
	if "spawned_seed" in tb:
		present = is_instance_valid(tb.spawned_seed)
	if not present and "seed_ready_to_fly" in tb:
		present = bool(tb.seed_ready_to_fly)
	return present

func _bush_has_berry(b: Node) -> bool:
	if not is_instance_valid(b):
		return false
	if not (b is BerryBush):
		return false
	# Consider there is a berry if Berry child exists
	var existing = (b as Node).find_child("Berry", true, false)
	return existing != null and existing is MeshInstance3D

func _compute_tree_seed_world_position(tree: TreeBase) -> Vector3:
	if not is_instance_valid(tree):
		return global_position
	var spawn_local: Vector3 = tree.seed_spawn_point if "seed_spawn_point" in tree else Vector3(0, 3.0, 0)
	var model := tree.find_child("Model", true, false)
	var model_scale: Vector3 = model.scale if model and "scale" in model else Vector3.ONE
	return tree.global_position + Vector3(spawn_local.x * model_scale.x, spawn_local.y * model_scale.y, spawn_local.z * model_scale.z)

func _award_seed_revenue(tree: TreeBase) -> void:
	if tree == null:
		return
	var value: int = 0
	if "seed_value" in tree:
		value = int(tree.seed_value)
	if value <= 0:
		return
	var root = get_tree().current_scene
	var top_right = root.find_child("TopRightPanel", true, false)
	if top_right and top_right.has_method("add_species_revenue"):
		top_right.add_species_revenue(species_name, value, "animal")
		top_right.add_species_revenue(tree.species_name, value, "plant")

func _award_berry_revenue(bush: BerryBush) -> void:
	if bush == null:
		return
	var value: int = 0
	if "berry_value" in bush:
		value = int(bush.berry_value)
	if value <= 0:
		return
	var root = get_tree().current_scene
	var top_right = root.find_child("TopRightPanel", true, false)
	if top_right and top_right.has_method("add_species_revenue"):
		top_right.add_species_revenue(species_name, value, "animal")
		top_right.add_species_revenue(bush.species_name, value, "plant")

func get_state_display_name() -> String:
	match _current_state_name:
		"exploring":
			return "Exploring (Flying)"
		"flying_to_food":
			return "Flying To Food"
		"descending_to_food":
			return "Descending To Food"
		"ascending_to_altitude":
			return "Ascending To Altitude"
		"feeding":
			return "Feeding"
		"resting":
			return "Resting"
		_:
			return _current_state_name.capitalize()

# --------------- Animation helpers (mirroring Mammal) ---------------
func _play_anim_if_exists(names: Array) -> void:
	if not animation_player:
		return
	for n in names:
		var name_str: String = String(n)
		if animation_player.has_animation(name_str):
			if not animation_player.is_playing() or animation_player.current_animation != name_str:
				animation_player.play(name_str)
			return
		var qualified: String = "default/" + name_str
		if animation_player.has_animation(qualified):
			if not animation_player.is_playing() or animation_player.current_animation != qualified:
				animation_player.play(qualified)
			return

func _play_state_anim(state_name: String) -> void:
	var choices: Array = _state_anim_choices.get(state_name, [])
	if choices.is_empty():
		return
	_play_anim_if_exists(choices)

var _state_anim_choices: Dictionary = {
	"exploring": ["Fly"],
	"flying_to_food": ["Fly"],
	"descending_to_food": ["Fly"],
	"ascending_to_altitude": ["Fly"],
	"feeding": ["Eat"],
	"resting": ["Idle_A"]
}

func _load_animations_from_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array = dir.get_files()
	for f in files:
		if not (f.ends_with(".glb") or f.ends_with(".tscn")):
			continue
		var full_path = dir_path.rstrip("/") + "/" + f
		var canonical := _canonical_anim_name_from_filename(f)
		if canonical == "":
			continue
		var packed: PackedScene = load(full_path)
		if packed:
			_import_animations_from_scene(packed, canonical)

func _canonical_anim_name_from_filename(file_name: String) -> String:
	var base := file_name
	var dot := base.rfind(".")
	if dot > 0:
		base = base.substr(0, dot)
	var first_under := base.find("_")
	if first_under >= 0 and first_under < base.length() - 1:
		return base.substr(first_under + 1)
	return base

func _import_animations_from_scene(packed: PackedScene, canonical_name: String) -> void:
	var inst := packed.instantiate()
	if inst == null:
		return
	var src_player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if src_player == null:
		inst.free()
		return
	var anim_names := src_player.get_animation_list()
	if anim_names.size() == 0:
		inst.free()
		return
	var anim_name: String = anim_names[0]
	var anim: Animation = src_player.get_animation(anim_name)
	if anim:
		var dup := anim.duplicate() as Animation
		if dup:
			var lib := _ensure_anim_library()
			if lib:
				if lib.has_animation(canonical_name):
					lib.remove_animation(canonical_name)
				lib.add_animation(canonical_name, dup)
	inst.free()

func _ensure_anim_library() -> AnimationLibrary:
	if animation_player == null:
		return null
	if _anim_lib != null:
		return _anim_lib
	var lib: AnimationLibrary = null
	if animation_player.has_animation_library(""):
		lib = animation_player.get_animation_library("")
	elif animation_player.has_animation_library("default"):
		lib = animation_player.get_animation_library("default")
	if lib == null:
		lib = AnimationLibrary.new()
		animation_player.add_animation_library("", lib)
	_anim_lib = lib
	return _anim_lib
