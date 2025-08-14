extends Animal
class_name Mammal

## -------------------- State Machine Core --------------------
class State:
	var mammal
	func _init(m):
		mammal = m
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
		# Ensure we have somewhere to go
		if not mammal._has_target:
			mammal._choose_new_wander_target()
		mammal._play_state_anim("exploring")
	func tick(dt: float) -> void:
		mammal.forage_check_timer -= dt
		if mammal.forage_check_timer <= 0.0:
			mammal.forage_check_timer = 2.0
			mammal.food_target = mammal.find_food_in_range(mammal.global_position, mammal.vision_range)
			if is_instance_valid(mammal.food_target):
				mammal._set_move_target(mammal.food_target.global_position)
				mammal.switch_state("moving_to_food")
				return
		if mammal._has_target:
			mammal._tick_navigation(dt)
			mammal._play_state_anim("exploring")
			if mammal.nav_agent and (Time.get_ticks_msec() % 500) < int(dt * 1000.0):
				mammal.nav_agent.set_target_position(mammal._wander_target)
			if mammal._nav_arrived():
				mammal._has_target = false
		else:
			mammal._choose_new_wander_target()

class MovingToFoodState:
	extends State
	func name() -> String:
		return "moving_to_food"
	func enter(_prev: String) -> void:
		if is_instance_valid(mammal.food_target):
			mammal._set_move_target(mammal.food_target.global_position)
		else:
			mammal.switch_state("exploring")
		mammal._play_state_anim("moving_to_food")
	func tick(dt: float) -> void:
		if not is_instance_valid(mammal.food_target):
			mammal.switch_state("exploring")
			return
		mammal.forage_check_timer -= dt
		if mammal.forage_check_timer <= 0.0:
			mammal.forage_check_timer = 2.0
			mammal._set_move_target(mammal.food_target.global_position)
		mammal._tick_navigation(dt)
		mammal._play_state_anim("moving_to_food")
		var reached := false
		if mammal.nav_agent:
			reached = mammal.nav_agent.is_navigation_finished()
		else:
			reached = (mammal.global_position - mammal.food_target.global_position).length() <= 0.35
		if reached:
			mammal.switch_state("feeding")

class FeedingState:
	extends State
	func name() -> String:
		return "feeding"
	func enter(_prev: String) -> void:
		# Ensure body is horizontal while eating (pitch neutral) for all mammals
		mammal._set_model_pitch(0.0)
		mammal._start_feeding()
		mammal._play_state_anim("feeding")
	func tick(dt: float) -> void:
		mammal._feeding_timer -= dt
		mammal._play_state_anim("feeding")
		if mammal._feeding_timer > 0.0:
			return
		# Consume the current food target and then look again
		if is_instance_valid(mammal.food_target):
			if mammal.food_target.has_method("consume"):
				mammal.food_target.consume()
			else:
				mammal.food_target.queue_free()
			if mammal.food_target is LifeForm:
				mammal._reward_for_eating(mammal.food_target as LifeForm)
				mammal._eaten_today += 1
			mammal.food_target = null
		# After eating, look again
		mammal.food_target = mammal.find_food_in_range(mammal.global_position, mammal.vision_range)
		if is_instance_valid(mammal.food_target):
			mammal.switch_state("moving_to_food")
		else:
			mammal.switch_state("exploring")

class RestingState:
	extends State
	func name() -> String:
		return "resting"
	func tick(_dt: float) -> void:
		mammal._play_state_anim("resting") 

var _states: Dictionary = {}
var _current_state: State
var _current_state_name: String = ""

@export var model_scene_path: String = "res://Resources/Animals/Jackrabbit/3D Files/GLTF/Merged LOD/Jackrabbit_LOD_All.glb"

# Keep a small offset above terrain to avoid embedding on slopes
@export var ground_clearance: float = 0.0

# Internal runtime
var seconds_per_game_day: float = 90.0
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
	seconds_per_game_day = _get_seconds_per_game_day()
	# Mammals do not fly or swim by default
	swim_speed = 0.0
	fly_speed = 0.0

	var _root = get_tree().current_scene

	# Ensure we have a visual model; instance if needed
	model_node = find_child("Model", true, false)
	if model_node == null and model_scene_path != "":
		var packed: PackedScene = load(model_scene_path)
		if packed:
			var inst = packed.instantiate()
			inst.name = "Model"
			add_child(inst)
			model_node = inst
	# Try to find AnimationPlayer within the model tree
	if model_node:
		animation_player = model_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation_player == null:
			animation_player = AnimationPlayer.new()
			animation_player.name = "AnimationPlayer"
			model_node.add_child(animation_player)
		# Ensure animations resolve against the model hierarchy
		animation_player.root_node = model_node.get_path()

	# Load species-specific animations from directory, if provided
	if animation_dir != "" and animation_player:
		_load_animations_from_dir(animation_dir)

	# Ensure NavigationAgent3D exists (used by all mammals). Configure for hare-sized agent.
	nav_agent = find_child("NavigationAgent3D", true, false) as NavigationAgent3D
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child(nav_agent)
	nav_agent.radius = 0.25
	nav_agent.height = 0.6
	nav_agent.max_speed = walk_speed
	nav_agent.target_desired_distance = 1.0
	nav_agent.path_desired_distance = 1.0
	if nav_agent.has_method("set_avoidance_enabled"):
		nav_agent.set_avoidance_enabled(false)
	elif "avoidance_enabled" in nav_agent:
		nav_agent.avoidance_enabled = false

	# Ensure we have a lightweight collision body for mouse picking (layer 4, mask 0)
	pick_body = find_child("PickBody", true, false) as StaticBody3D
	if pick_body == null:
		pick_body = StaticBody3D.new()
		pick_body.name = "PickBody"
		add_child(pick_body)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.2
		capsule.height = 0.6
		shape.shape = capsule
		pick_body.add_child(shape)
		# Set to layer 4 for SidePanel inspection ray
		pick_body.set_collision_layer_value(1, false) # layer 1 off
		pick_body.set_collision_layer_value(3, false) # layer 3 off
		pick_body.set_collision_layer_value(4, true)  # layer 4 on
		# Don't collide actively
		pick_body.collision_mask = 0

	_create_state_machine()
	set_process(true)
	set_physics_process(false)

func _exit_tree():
	pass

func _process(delta: float) -> void:
	_logic_update(delta)

 

func _logic_update(dt: float) -> void:
	# Age tracking
	current_age += dt / seconds_per_game_day
	if current_age >= max_age:
		_remove_self()
		return

	# Sync/reset daily target and decide if we rest
	_refresh_daily_target_if_needed()
	if _has_met_daily_target():
		if _current_state_name != "resting":
			switch_state("resting")
		# While resting, do not tick other behaviors
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

func _choose_new_wander_target() -> void:
	var radius := 6.0
	var angle := randf() * TAU
	var offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	var base = global_position + offset
	if terrain and terrain.has_method("get_height"):
		base.y = terrain.get_height(base.x, base.z)
	# Snap target to nearest walkable point to avoid unreachable slope targets
	_wander_target = _project_to_navmesh(base)
	_has_target = true
	if nav_agent:
		nav_agent.set_target_position(_wander_target)

func _move_towards(target: Vector3, max_step: float) -> bool:
	var to = target - global_position
	to.y = 0.0
	var dist = to.length()
	if dist <= 0.05:
		_has_target = false
		return true
	var dir = to / max(dist, 0.0001)
	global_position += dir * max_step
	# Rotate to face direction
	if dir.length() > 0.0001:
		rotation.y = atan2(dir.x, dir.z)
	_update_height(dir)
	return false

func _tick_navigation(dt: float) -> void:
	if not nav_agent:
		# Fallback to simple move if no nav
		_move_towards(_wander_target, walk_speed * dt)
		return
	nav_agent.max_speed = walk_speed
	var next_point: Vector3 = nav_agent.get_next_path_position()
	# If the agent reports finished, aim directly for the final target
	if nav_agent.is_navigation_finished():
		next_point = _wander_target
	var to3d = next_point - global_position
	# Drive movement based only on horizontal (XZ) delta for consistent slope behavior
	var to_flat = Vector3(to3d.x, 0.0, to3d.z)
	var dist = to_flat.length()
	if dist <= 0.0001:
		return
	var dir = to_flat / dist
	var speed = walk_speed
	global_position += dir * speed * dt
	_update_height(dir)
	if dir.length() > 0.0001:
		rotation.y = atan2(dir.x, dir.z)

func _nav_arrived() -> bool:
	var d = (global_position - _wander_target)
	d.y = 0.0
	return d.length() <= 0.35

func _set_move_target(pos: Vector3) -> void:
	# Snap to nearest walkable point
	_wander_target = _project_to_navmesh(pos)
	_has_target = true
	if nav_agent:
		nav_agent.set_target_position(_wander_target)

func _project_to_navmesh(point: Vector3) -> Vector3:
	if nav_agent and nav_agent.get_navigation_map() != RID():
		var map_rid: RID = nav_agent.get_navigation_map()
		return NavigationServer3D.map_get_closest_point(map_rid, point)
	return point

# ---- Helpers: terrain height ----
func _update_height(_move_dir_flat: Vector3) -> void:
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	if terrain and terrain.has_method("get_height"):
		var y = terrain.get_height(global_position.x, global_position.z)
		global_position.y = y + ground_clearance

func _reset_model_basis_if_needed() -> void:
	if model_node:
		model_node.basis = Basis.IDENTITY

func _start_feeding() -> void:
	_feeding_timer = 3.0

func get_state_name() -> String:
	if _current_state_name == "":
		return "UNKNOWN"
	return _current_state_name.to_upper()

func get_forage_state_name() -> String:
	# Deprecated: kept for compatibility with older UI code paths
	return get_state_name()

func get_state_display_name() -> String:
	# Title-cased, human-friendly names for UI
	match _current_state_name:
		"exploring":
			return "Exploring"
		"moving_to_food":
			return "Moving To Food"
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
		# Try plain name first (default unnamed library)
		if animation_player.has_animation(name_str):
			if not animation_player.is_playing() or animation_player.current_animation != name_str:
				animation_player.play(name_str)
			return
		# Also try in a library named "default" if present
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
	"exploring": ["Walk"],
	"moving_to_food": ["Walk"],
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
	# Examples:
	#  - Jackrabbit_Walk.glb -> Walk
	#  - Jackrabbit_Idle_A.glb -> Idle_A
	var base := file_name
	var dot := base.rfind(".")
	if dot > 0:
		base = base.substr(0, dot)
	var first_under := base.find("_")
	if first_under >= 0 and first_under < base.length() - 1:
		return base.substr(first_under + 1)
	# Fallback to full base name
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
	# Prefer the unnamed default library so animations can be referenced as plain names
	if animation_player.has_animation_library(""):
		lib = animation_player.get_animation_library("")
	elif animation_player.has_animation_library("default"):
		lib = animation_player.get_animation_library("default")
	if lib == null:
		lib = AnimationLibrary.new()
		animation_player.add_animation_library("", lib)
	_anim_lib = lib
	return _anim_lib

# --------------- Model orientation helpers ---------------
func _set_model_pitch(angle_rad: float) -> void:
	if model_node:
		var r = model_node.rotation
		r.x = angle_rad
		model_node.rotation = r

# --------------- State Machine helpers ---------------
func _create_state_machine() -> void:
	_states.clear()
	_define_states()
	# Default to exploring at start of day
	switch_state("exploring")

func _define_states() -> void:
	# Subclasses can override this to add/replace states (e.g., climbing)
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
