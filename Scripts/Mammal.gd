extends "res://Scripts/Animal.gd"
class_name Mammal

enum ForageState { EXPLORING, MOVING_TO_FOOD, FEEDING }

@export var model_scene_path: String = "res://Resources/Animals/Jackrabbit/3D Files/GLTF/Merged LOD/Jackrabbit_LOD_All.glb"

# Keep a small offset above terrain to avoid embedding on slopes
@export var ground_clearance: float = 0.0

# Internal runtime
var seconds_per_game_day: float = 90.0
var model_node: Node3D
var animation_player: AnimationPlayer
var nav_agent: NavigationAgent3D
var pick_body: StaticBody3D

var _wander_target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var forage_state: ForageState = ForageState.EXPLORING
var _forage_check_timer: float = 0.0
var _food_target: Node3D
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

	# Ensure NavigationAgent3D exists (used by all mammals). Configure for hare-sized agent.
	nav_agent = find_child("NavigationAgent3D", true, false) as NavigationAgent3D
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child(nav_agent)
	nav_agent.radius = 0.25
	nav_agent.height = 0.6
	nav_agent.max_speed = walk_speed
	nav_agent.target_desired_distance = 0.8
	nav_agent.path_desired_distance = 0.8
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

	forage_state = ForageState.EXPLORING
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
		# Rest: no movement
		_play_anim_if_exists(["Idle"]) 
		return

	_tick_forage(dt)
	match forage_state:
		ForageState.EXPLORING:
			if _has_target:
				_tick_navigation(dt)
				_play_anim_if_exists(["Walk", "Run", "Idle"]) 
				# If path stalls, gently reissue the target to keep the agent solving
				if nav_agent and (Time.get_ticks_msec() % 500) < int(dt * 1000.0):
					nav_agent.set_target_position(_wander_target)
				if _nav_arrived():
					_has_target = false
			else:
				_choose_new_wander_target()
		ForageState.MOVING_TO_FOOD:
			_tick_navigation(dt)
			_play_anim_if_exists(["Walk", "Run", "Idle"]) 
			if nav_agent and is_instance_valid(_food_target) and (Time.get_ticks_msec() % 500) < int(dt * 1000.0):
				nav_agent.set_target_position(_food_target.global_position)
		ForageState.FEEDING:
			_feeding_timer -= dt
			_play_anim_if_exists(["Eat", "Eating", "Idle"]) 
			if _feeding_timer <= 0.0:
				# Consume the current food target and then look again
				if is_instance_valid(_food_target):
					if _food_target.has_method("consume"):
						_food_target.consume()
					else:
						_food_target.queue_free()
					# Reward credits/revenue for eaten lifeform
					if _food_target is LifeForm:
						_reward_for_eating(_food_target as LifeForm)
						_eaten_today += 1
					_food_target = null
				# After eating, look again
				_food_target = find_food_in_range(global_position, vision_range)
				if is_instance_valid(_food_target):
					forage_state = ForageState.MOVING_TO_FOOD
					_set_move_target(_food_target.global_position)
				else:
					forage_state = ForageState.EXPLORING

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

# ---------- Foraging logic ----------
func _tick_forage(dt: float) -> void:
	_forage_check_timer -= dt
	match forage_state:
		ForageState.EXPLORING:
			if _forage_check_timer <= 0.0:
				_forage_check_timer = 2.0
				_food_target = find_food_in_range(global_position, vision_range)
				if is_instance_valid(_food_target):
					forage_state = ForageState.MOVING_TO_FOOD
					_set_move_target(_food_target.global_position)
					return
			# Ensure we are walking somewhere when exploring
			if not _has_target:
				_choose_new_wander_target()
		ForageState.MOVING_TO_FOOD:
			if not is_instance_valid(_food_target):
				forage_state = ForageState.EXPLORING
				return
			# Refresh target every few seconds in case food moved/was eaten
			if _forage_check_timer <= 0.0:
				_forage_check_timer = 2.0
				_set_move_target(_food_target.global_position)
			var reached := false
			if nav_agent:
				reached = nav_agent.is_navigation_finished()
			else:
				reached = (global_position - _food_target.global_position).length() <= 0.35
			if reached:
				forage_state = ForageState.FEEDING
				_start_feeding()
		ForageState.FEEDING:
			pass

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
	forage_state = ForageState.FEEDING
	_feeding_timer = 3.0

func get_forage_state_name() -> String:
	if typeof(forage_state) != TYPE_INT:
		return "Unknown"
	match forage_state:
		ForageState.EXPLORING:
			return "Exploring"
		ForageState.MOVING_TO_FOOD:
			return "MovingToFood"
		ForageState.FEEDING:
			return "Feeding"
	return "Unknown"

func _play_anim_if_exists(names: Array[String]) -> void:
	if not animation_player:
		return
	for n in names:
		if animation_player.has_animation(n):
			if not animation_player.is_playing() or animation_player.current_animation != n:
				animation_player.play(n)
			return
