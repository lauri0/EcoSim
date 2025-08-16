extends "res://Scripts/Mammal.gd"
class_name ClimbingMammal

# Additional climbing behavior for tree seed foragers (e.g., squirrel)

# Vertical climbing speed in meters per second
@export var climb_speed: float = 1.5

# Internal (no persistent climb fields to avoid linter warnings)

class ExploringForTreesState:
	extends Mammal.State
	func name() -> String:
		return "exploring"
	func enter(_prev: String) -> void:
		if not mammal._has_target:
			mammal._choose_new_wander_target()
		mammal._play_state_anim("exploring")
	func tick(dt: float) -> void:
		mammal.forage_check_timer -= dt
		if mammal.forage_check_timer <= 0.0:
			mammal.forage_check_timer = 2.0
			# Only target trees when the diet explicitly includes TreeSeed
			if mammal.diet.has("TreeSeed"):
				# Only target trees that currently have a consumable seed
				mammal.food_target = mammal._find_tree_with_seed_in_range(mammal.global_position, mammal.vision_range)
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

class MovingToFoodForTree:
	extends Mammal.State
	func name() -> String:
		return "moving_to_food"
	func enter(_prev: String) -> void:
		if is_instance_valid(mammal.food_target):
			# For trees, head to the trunk center for climbing
			var dest: Vector3 = mammal.food_target.global_position if mammal.food_target else mammal.global_position
			mammal._set_move_target(dest)
		else:
			mammal.switch_state("exploring")
			return
		mammal._play_state_anim("moving_to_food")
	func tick(dt: float) -> void:
		if not is_instance_valid(mammal.food_target):
			mammal.switch_state("exploring")
			return
		mammal.forage_check_timer -= dt
		if mammal.forage_check_timer <= 0.0:
			mammal.forage_check_timer = 2.0
			# If the target no longer has a seed, abandon and search again
			if not mammal._tree_has_seed(mammal.food_target):
				if mammal.diet.has("TreeSeed"):
					mammal.food_target = mammal._find_tree_with_seed_in_range(mammal.global_position, mammal.vision_range)
					if is_instance_valid(mammal.food_target):
						mammal._set_move_target(mammal.food_target.global_position)
					else:
						mammal.switch_state("exploring")
						return
				else:
					mammal.switch_state("exploring")
					return
			else:
				mammal._set_move_target(mammal.food_target.global_position)
		mammal._tick_navigation(dt)
		mammal._play_state_anim("moving_to_food")
		var reached := false
		if mammal.nav_agent:
			reached = mammal.nav_agent.is_navigation_finished()
		else:
			reached = (mammal.global_position - mammal.food_target.global_position).length() <= 0.35
		if reached:
			# If the target is a tree and still has a seed, begin climbing; otherwise, feed or explore
			if mammal.food_target is TreeBase:
				if mammal._tree_has_seed(mammal.food_target):
					mammal.switch_state("climb_up")
				else:
					mammal.switch_state("exploring")
			else:
				mammal.switch_state("feeding")

class ClimbUpState:
	extends Mammal.State
	var target_y: float = 0.0
	func name() -> String:
		return "climb_up"
	func enter(_prev: String) -> void:
		# Lock horizontal position to tree center and aim for seed spawn point height
		if mammal.food_target is TreeBase:
			var t: TreeBase = mammal.food_target as TreeBase
			mammal.global_position.x = t.global_position.x
			mammal.global_position.z = t.global_position.z
			var wp: Vector3 = mammal._compute_tree_seed_world_position(t)
			target_y = wp.y
			# Pitch model to face upwards while climbing
			mammal._set_model_pitch(-PI * 0.5)
		else:
			mammal.switch_state("exploring")
			return
		mammal._play_state_anim("climb_up")
	func exit(_next: String) -> void:
		# Reset to neutral when leaving climbing state unless transitioning to feeding
		if _next != "feeding":
			mammal._set_model_pitch(0.0)
	func tick(dt: float) -> void:
		# Move vertically towards target
		var pos: Vector3 = mammal.global_position
		var dir := signf(target_y - pos.y)
		var step: float = mammal.climb_speed * dt
		if abs(target_y - pos.y) <= step:
			pos.y = target_y
			mammal.global_position = pos
			# Double-check seed presence before eating
			if mammal._tree_has_seed(mammal.food_target):
				mammal.switch_state("feeding")
			else:
				mammal.switch_state("climb_down")
			return
		pos.y += dir * step
		mammal.global_position = pos
		mammal._play_state_anim("climb_up")

class ClimbDownState:
	extends Mammal.State
	var target_y: float = 0.0
	func name() -> String:
		return "climb_down"
	func enter(_prev: String) -> void:
		# Set downward pitch and compute ground at tree base
		if mammal.food_target is TreeBase:
			var t: TreeBase = mammal.food_target as TreeBase
			var tpos: Vector3 = t.global_position
			mammal.global_position.x = tpos.x
			mammal.global_position.z = tpos.z
			var ground_y: float = mammal._get_terrain_height_at(tpos)
			target_y = ground_y
			mammal._set_model_pitch(PI * 0.5)
		else:
			mammal.switch_state("exploring")
			return
		mammal._play_state_anim("climb_down")
	func exit(_next: String) -> void:
		mammal._set_model_pitch(0.0)
	func tick(dt: float) -> void:
		var pos: Vector3 = mammal.global_position
		var step: float = mammal.climb_speed * dt
		if pos.y <= target_y + step:
			pos.y = target_y
			mammal.global_position = pos
			# Decide next action based on daily target
			if mammal._has_met_daily_target():
				mammal.switch_state("resting")
			else:
				# Seek next tree with seed
				if mammal.diet.has("TreeSeed"):
					mammal.food_target = mammal._find_tree_with_seed_in_range(mammal.global_position, mammal.vision_range)
				else:
					mammal.food_target = null
				if is_instance_valid(mammal.food_target):
					mammal._set_move_target(mammal.food_target.global_position)
					mammal.switch_state("moving_to_food")
				else:
					mammal.switch_state("exploring")
			return
		pos.y -= step
		mammal.global_position = pos
		mammal._play_state_anim("climb_down")

class FeedingOnTreeState:
	extends Mammal.State
	func name() -> String:
		return "feeding"
	func enter(_prev: String) -> void:
		# Ensure horizontal orientation while eating
		mammal._set_model_pitch(0.0)
		mammal._start_feeding()
		mammal._play_state_anim("feeding")
	func tick(dt: float) -> void:
		mammal._feeding_timer -= dt
		mammal._play_state_anim("feeding")
		if mammal._feeding_timer > 0.0:
			return
		# Finished eating: if on a tree, only consume and award if the seed still exists
		if is_instance_valid(mammal.food_target) and mammal.food_target is TreeBase:
			var tree := mammal.food_target as TreeBase
			if tree and mammal._tree_has_seed(tree) and tree.has_method("_destroy_attached_seed"):
				tree._destroy_attached_seed()
				mammal._award_seed_revenue(tree)
				mammal._eaten_today += 1
		# After eating at the top, either look for more or rest on top
		if mammal._has_met_daily_target():
			mammal.switch_state("resting")
		else:
			mammal.switch_state("climb_down")

func _define_states() -> void:
	# Replace moving_to_food and feeding behaviors; keep others and add climb states
	register_state("exploring", ExploringForTreesState.new(self))
	register_state("moving_to_food", MovingToFoodForTree.new(self))
	register_state("feeding", FeedingOnTreeState.new(self))
	register_state("resting", RestingState.new(self))
	register_state("climb_up", ClimbUpState.new(self))
	register_state("climb_down", ClimbDownState.new(self))

func _ready():
	# Ensure animations include our climb states (reusing Walk)
	_state_anim_choices["climb_up"] = ["Walk"]
	_state_anim_choices["climb_down"] = ["Walk"]
	super._ready()

# -------- Helpers specific to climbing mammals --------

func _compute_tree_seed_world_position(tree: TreeBase) -> Vector3:
	if not is_instance_valid(tree):
		return global_position
	var spawn_local: Vector3 = tree.seed_spawn_point if "seed_spawn_point" in tree else Vector3(0, 3.0, 0)
	var model := tree.find_child("Model", true, false)
	var model_scale: Vector3 = model.scale if model and "scale" in model else Vector3.ONE
	return tree.global_position + Vector3(spawn_local.x * model_scale.x, spawn_local.y * model_scale.y, spawn_local.z * model_scale.z)

func _get_terrain_height_at(pos: Vector3) -> float:
	var root = get_tree().current_scene
	var terrain = root.find_child("Terrain", true, false)
	if terrain and terrain.has_method("get_height"):
		return terrain.get_height(pos.x, pos.z)
	return pos.y

func _set_model_pitch(angle_rad: float) -> void:
	if model_node:
		# Apply pitch by setting the model's rotation around X axis only
		var r = model_node.rotation
		r.x = angle_rad
		model_node.rotation = r

func _find_tree_with_seed_in_range(center: Vector3, search_range: float) -> Node3D:
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
			# Consider trees with a present attached seed
			if not _tree_has_seed(tb):
				continue
			var d2 = (tb.global_position - center).length_squared()
			if d2 < best_d2:
				best = tb
				best_d2 = d2
		return best
	return null

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

func _award_seed_revenue(tree: TreeBase) -> void:
	var value: int = 0
	if "seed_value" in tree:
		value = int(tree.seed_value)
	if value <= 0:
		return
	var root = get_tree().current_scene
	var top_right = root.find_child("TopRightPanel", true, false)
	if top_right and top_right.has_method("add_species_revenue"):
		# Count for eater (animal)
		top_right.add_species_revenue(species_name, value, "animal")
		# Count for plant/tree as well
		top_right.add_species_revenue(tree.species_name, value, "plant")
