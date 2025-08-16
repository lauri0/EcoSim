extends "res://Scripts/Animal.gd"
class_name Fish

# Fish-specific movement and setup
@export var model_scene_path: String = ""

# Fish always swim; lock to a fixed offset below water level
@export var depth_below_surface: float = 1.0

# Navmesh is not used for fish; they swim on a flat plane using depth checks

# --------------- State Machine (mirrors Mammal) ---------------
class State:
	var fish
	func _init(f):
		fish = f
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
		if not fish._has_target:
			fish._choose_new_wander_target()
		fish._play_state_anim("exploring")
	func tick(dt: float) -> void:
		fish.forage_check_timer -= dt
		if fish.forage_check_timer <= 0.0:
			fish.forage_check_timer = 2.0
			fish.food_target = fish.find_food_in_range(fish.global_position, fish.vision_range)
			if is_instance_valid(fish.food_target):
				fish._set_move_target((fish.food_target as Node3D).global_position)
				fish.switch_state("moving_to_food")
				return
		if fish._has_target:
			fish._tick_swim_navigation(dt)
			fish._play_state_anim("exploring")
			if fish._nav_arrived():
				fish._has_target = false
		else:
			fish._choose_new_wander_target()

class MovingToFoodState:
	extends State
	func name() -> String:
		return "moving_to_food"
	func enter(_prev: String) -> void:
		if is_instance_valid(fish.food_target):
			fish._set_move_target((fish.food_target as Node3D).global_position)
		else:
			fish.switch_state("exploring")
		fish._play_state_anim("moving_to_food")
	func tick(dt: float) -> void:
		if not is_instance_valid(fish.food_target):
			fish.switch_state("exploring")
			return
		fish.forage_check_timer -= dt
		if fish.forage_check_timer <= 0.0:
			fish.forage_check_timer = 2.0
			fish._set_move_target((fish.food_target as Node3D).global_position)
		fish._tick_swim_navigation(dt)
		fish._play_state_anim("moving_to_food")
		var to = (fish.food_target as Node3D).global_position - fish.global_position
		to.y = 0.0
		var reached: bool = to.length() <= 0.35
		if reached:
			fish.switch_state("feeding")

class FeedingState:
	extends State
	func name() -> String:
		return "feeding"
	func enter(_prev: String) -> void:
		fish._start_feeding()
		fish._play_state_anim("feeding")
	func tick(dt: float) -> void:
		fish._feeding_timer -= dt
		fish._play_state_anim("feeding")
		if fish._feeding_timer > 0.0:
			return
		if is_instance_valid(fish.food_target):
			# Damage lifeforms; destroy only on HP <= 0
			if fish.food_target is LifeForm:
				var lf: LifeForm = fish.food_target as LifeForm
				lf.apply_damage(fish.eating_damage)
				fish._reward_for_eating(lf)
				fish._eaten_today += 1
			# Fallback consume for non-lifeforms
			elif fish.food_target.has_method("consume"):
				fish.food_target.consume()
			else:
				fish.food_target.queue_free()
			fish.food_target = null
		# Look again after eating
		fish.food_target = fish.find_food_in_range(fish.global_position, fish.vision_range)
		if is_instance_valid(fish.food_target):
			fish.switch_state("moving_to_food")
		else:
			fish.switch_state("exploring")

class RestingState:
	extends State
	func name() -> String:
		return "resting"
	func tick(_dt: float) -> void:
		fish._play_state_anim("resting")

var _states: Dictionary = {}
var _current_state: State
var _current_state_name: String = ""

# Runtime
var model_node: Node3D
var animation_player: AnimationPlayer
var _anim_lib: AnimationLibrary
var pick_body: StaticBody3D

var _wander_target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var forage_check_timer: float = 0.0
var food_target: Node3D
var _feeding_timer: float = 0.0
 

@export var min_depth: float = 1.5
var _terrain: Node3D

func _ready():
	# Fish don't walk or fly
	walk_speed = 0.0
	fly_speed = 0.0
	if swim_speed <= 0.0:
		swim_speed = 2.0

	# Ensure visual model (optional packed scene)
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
	# Snap to desired swim depth on spawn
	var p := global_position
	var y := _desired_swim_y()
	global_position = Vector3(p.x, y, p.z)

	# Initialize first target
	_choose_new_wander_target()

func _process(delta: float) -> void:
	_logic_update(delta)

func _logic_update(dt: float) -> void:
	# Age & rest handling
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

# Called from Animal when a new in-game day starts
func _on_new_day() -> void:
	if _current_state_name == "resting":
		switch_state("exploring")

func _init_first_target() -> void:
	_choose_new_wander_target()

# --------------- State machine helpers ---------------
func _create_state_machine() -> void:
	_states.clear()
	_define_states()
	switch_state("exploring")

func _define_states() -> void:
	register_state("exploring", ExploringState.new(self))
	register_state("moving_to_food", MovingToFoodState.new(self))
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

# --------------- Swimming/navigation helpers ---------------
func _get_global_water_level() -> float:
	var root = get_tree().current_scene
	if root:
		var side = root.find_child("SidePanel", true, false)
		if side and side.has_method("get"):
			var v = side.get("water_level")
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				return float(v)
	return 0.0

func _desired_swim_y() -> float:
	return _get_global_water_level() - depth_below_surface

func _tick_swim_navigation(dt: float) -> void:
	_move_towards_flat(_wander_target, swim_speed * dt)

func _move_towards_flat(target: Vector3, max_step: float) -> bool:
	var to = target - global_position
	to.y = 0.0
	var dist = to.length()
	if dist <= 0.05:
		_has_target = false
		# Keep Y locked
		var p = global_position
		p.y = _desired_swim_y()
		global_position = p
		return true
	var dir = to / max(dist, 0.0001)
	var proposed: Vector3 = global_position + dir * max_step
	var y := _desired_swim_y()
	proposed = _clamp_step_to_deep_area(Vector3(proposed.x, y, proposed.z))
	global_position = Vector3(proposed.x, y, proposed.z)
	if dir.length() > 0.0001:
		rotation.y = atan2(dir.x, dir.z)
	return false

func _nav_arrived() -> bool:
	var d = (global_position - _wander_target)
	d.y = 0.0
	return d.length() <= 0.35

func _set_move_target(pos: Vector3) -> void:
	var t = Vector3(pos.x, _desired_swim_y(), pos.z)
	if _is_deep_enough(t.x, t.z):
		_wander_target = t
	else:
		_wander_target = _pick_random_swim_point(global_position, 10.0)
	_has_target = true

func _choose_new_wander_target() -> void:
	_wander_target = _pick_random_swim_point(global_position, 10.0)
	_has_target = true

# Navmesh helpers removed; movement is purely depth-gated now

func _get_terrain() -> Node3D:
	if _terrain == null:
		var root = get_tree().current_scene
		if root:
			_terrain = root.find_child("Terrain", true, false) as Node3D
	return _terrain

func _is_deep_enough(x: float, z: float) -> bool:
	var wl := _get_global_water_level()
	var t := _get_terrain()
	var h := -INF
	if t and t.has_method("get_height"):
		h = t.get_height(x, z)
	return h <= (wl - min_depth)

func _pick_random_swim_point(center: Vector3, search_radius: float) -> Vector3:
	var desired_y := _desired_swim_y()
	for _i in range(16):
		var r := randf() * search_radius
		var a := randf() * TAU
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		if _is_deep_enough(x, z):
			return Vector3(x, desired_y, z)
	# fallback: stay where we are (depth guard in mover will re-pick)
	return Vector3(center.x, desired_y, center.z)

func _clamp_step_to_deep_area(p: Vector3) -> Vector3:
	if _is_deep_enough(p.x, p.z):
		return p
	_has_target = false
	_choose_new_wander_target()
	return Vector3(global_position.x, p.y, global_position.z)

# --------------- Animation helpers ---------------
func _start_feeding() -> void:
	_feeding_timer = 2.0

func get_state_display_name() -> String:
	match _current_state_name:
		"exploring":
			return "Exploring (Swimming)"
		"moving_to_food":
			return "Swimming To Food"
		"feeding":
			return "Feeding"
		"resting":
			return "Resting"
		_:
			return _current_state_name.capitalize()

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
	"exploring": ["Swim"],
	"moving_to_food": ["Swim"],
	"feeding": ["Eat"],
	"resting": ["Idle_A"]
}

# --------------- Animation library helpers (mirroring Mammal/Bird) ---------------
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
