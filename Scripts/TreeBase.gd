extends Plant
class_name TreeBase

# Tree state enum
enum TreeState {
	GROWING,
	MATURE,
	DORMANT,
	DYING
}

## Time (in-game days) that it takes for the tree to mature given 100% health
@export var max_growth_progress:   float = 60.0

## Used to decide how much health damage intruding other trees deal to the tree
## So a small tree intruding into teh needs_free_radius of a big tree won't affect the big tree's health much,
## but vice versa the small tree would be affected a lot
@export var adult_size_factor:     float = 10.0
	
# Seed system properties
@export var seed_spawn_point: Vector3 = Vector3(0, 4.0, 0)  # Base spawn point in local tree coordinates as multiple of scale
@export var seed_type: String = "spherical"  # Will be overridden per species
@export var seed_size: float = 0.1
@export var seed_mass: float = 0.001
@export var seed_germ_chance: float = 0.1
@export var seed_value: int = 5  # Revenue gained by animals when eating this seed

## Inherited from LifeForm:
## var healthPercentage: float
## var current_age: float
var state:                         TreeState = TreeState.GROWING
## Growth progress accumulated, in ideal conditions equal to seconds but can be more
## If progress reaches max_growth_progress then the tree is fully grown
var growth_progress:               float = 0.0

var seed_production_progress:      float = 0.0 # deprecated
var seed_maturation_progress:      float = 0.0 # deprecated
var state_percentage:              float = 0.0
var time_until_next_repro_check:   float = 0.0

# Seed system variables - now only one seed at a time
var spawned_seed: Node3D = null
var seed_ready_to_fly: bool = false

# Death system variables
var dying_timer: float = 0.0
var death_duration: float = 30.0
var has_fallen: bool = false
var collision_body: StaticBody3D

# Growth and scaling
var initial_scale:                 Vector3 = Vector3.ONE
var model_node:                    Node3D  # Reference to the visual model
var mesh_instance:                 MeshInstance3D  # Reference to the mesh for material changes
var last_scale_update:             float = 0.0  # For performance optimization

# Seasonal materials
var original_leaf_material:        Material
var winter_leaf_material:          StandardMaterial3D
var autumn_leaf_material:          StandardMaterial3D
var is_winter:                     bool = false
var is_autumn:                     bool = false
var autumn_progress:               float = 0.0  # 0.0 to 1.0 for gradual color transition
var winter_progress:               float = 0.0  # 0.0 to 1.0 for gradual winter transition
var seconds_per_game_day:          float = 90.0
var time_manager:                  Node
var winter_transition_material:    StandardMaterial3D
var autumn_transition_material:    StandardMaterial3D
var transition_material:           StandardMaterial3D
var tree_manager:                  Node
var _season_accumulator:           float = 0.0
var _season_update_interval:       float = 5.0
var _seed_accumulator:             float = 0.0
var _seed_update_interval:         float = 0.25

# Static caches for seasonal/default materials
static var _winter_material_cache: Dictionary = {}
static var _autumn_material_cache: Dictionary = {}
static var _default_surface_material: StandardMaterial3D

static func _get_default_surface_material() -> StandardMaterial3D:
	if _default_surface_material == null:
		_default_surface_material = StandardMaterial3D.new()
		_default_surface_material.resource_name = "Default Surface Material"
	return _default_surface_material

static func _get_cached_winter_material(species: String, base_resource_name: String) -> StandardMaterial3D:
	if not _winter_material_cache.has(species):
		var m := StandardMaterial3D.new()
		m.resource_name = "Winter " + base_resource_name
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.9, 0.9, 0.95, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.1, 0.1, 0.15)
		_winter_material_cache[species] = m
	return _winter_material_cache[species]

static func _get_cached_autumn_material(species: String, autumn_color: Color, base_resource_name: String) -> StandardMaterial3D:
	if not _autumn_material_cache.has(species):
		var m := StandardMaterial3D.new()
		m.resource_name = "Autumn " + base_resource_name
		m.vertex_color_use_as_albedo = true
		m.albedo_color = autumn_color
		_autumn_material_cache[species] = m
	return _autumn_material_cache[species]

func _ready():
	# Initialize tree
	seconds_per_game_day = _get_seconds_per_game_day()
	growth_progress = 0.0
	state = TreeState.GROWING
	# Stagger seasonal updates per tree to avoid frame spikes
	_season_accumulator = randf_range(0.0, _season_update_interval)
	
	# Health will be calculated based on altitude in first _update_health() call
	
	# Find the model node and mesh instance
	model_node = find_child("Model", true, false)
	if model_node:
		initial_scale = model_node.scale
		# Start with minimal scale (10% of full size)
		model_node.scale = initial_scale * 0.1
		
		# Find the mesh instance for material changes
		mesh_instance = model_node.find_child("MeshInstance3D", true, false) as MeshInstance3D
		if mesh_instance:
			_setup_seasonal_materials()
			# Disable shadow casting to reduce GPU cost
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			print("Warning: No MeshInstance3D found in tree ", species_name)
	else:
		print("Warning: No 'Model' node found in tree ", species_name)
	
	# Find collision body for death system
	collision_body = find_child("StaticBody3D", true, false) as StaticBody3D
	if not collision_body:
		print("Warning: No StaticBody3D found in tree ", species_name)
	else:
		# Set tree collision layer (layer 3)
		collision_body.set_collision_layer_value(1, false)
		collision_body.set_collision_layer_value(3, true)
		collision_body.set_collision_mask_value(1, false)
	
	# Connect to TimeManager for seasonal changes
	_connect_to_time_manager.call_deferred()

	# Register with TreeManager for batched logic updates
	var root = get_tree().current_scene
	tree_manager = root.find_child("TreeManager", true, false)
	if tree_manager and tree_manager.has_method("register_tree"):
		tree_manager.register_tree(self)

func _process(delta):
	# Lightweight visual work only and throttled seasonal transitions
	_update_scale()
	_season_accumulator += delta
	if _season_accumulator >= _season_update_interval:
		_season_accumulator = 0.0
		# Throttled seasonal transitions to reduce spikes
		if is_autumn and autumn_leaf_material:
			_update_autumn_color_transition()
		elif is_winter and winter_leaf_material:
			_update_winter_color_transition()

func _logic_update(dt: float) -> void:
	# Age tracked in in-game days
	current_age += dt / seconds_per_game_day
	
	# Check for age-based death
	if current_age >= max_age and state != TreeState.DYING:
		_start_dying()
		return
	
	# Update health based on environmental conditions
	_update_health()
	
	# Update growth based on state using the batched dt
	_update_growth(dt)

	# Handle seed lifecycle at a reduced tick (visuals only)
	_seed_accumulator += dt
	if _seed_accumulator >= _seed_update_interval:
		_handle_seed_lifecycle(_seed_accumulator)
		_seed_accumulator = 0.0

func _exit_tree():
	if tree_manager and tree_manager.has_method("unregister_tree"):
		tree_manager.unregister_tree(self)

func _try_reproduce():
	# Disabled: reproduction is centrally managed
	pass

func _update_growth(delta: float):
	# Handle dying state regardless of season (death should continue during winter)
	if state == TreeState.DYING:
		# Tree is dying, handle death timer
		dying_timer += delta
		state_percentage = dying_timer / death_duration
		
		# Handle falling animation
		if not has_fallen and dying_timer > 1.0:  # Start falling after 1 second
			_start_falling()
		
		# Remove tree after death duration
		if dying_timer >= death_duration:
			_remove_tree()
		
		# Safety clamp to ensure state_percentage never exceeds 100%
		state_percentage = clamp(state_percentage, 0.0, 1.0)
		return
	
	# Skip growth while dormant (winter)
	if state == TreeState.DORMANT:
		return
	
	match state:
		TreeState.GROWING:
			# Calculate growth rate in days/second based on health
			var growth_rate = _calculate_growth_rate()
			growth_progress += delta * growth_rate
			
			# Clamp growth progress to max value
			growth_progress = min(growth_progress, max_growth_progress)
			
			# Update state percentage for UI
			state_percentage = growth_progress / max_growth_progress
			
			# Check if fully grown - switch to resting (MATURE) until spring
			if growth_progress >= max_growth_progress:
				state = TreeState.MATURE
				state_percentage = 0.0
		
		TreeState.MATURE:
			# Resting; seeds are spawned at season changes
			pass
	
	# Safety clamp to ensure state_percentage never exceeds 100%
	state_percentage = clamp(state_percentage, 0.0, 1.0)

## _update_health now provided by Plant

func _calculate_growth_rate() -> float:
	# Base rate is 1.0 progress unit per in-game day at 100% health,
	# expressed as days per real second
	var base_rate_days_per_second: float = 1.0 / seconds_per_game_day
	var health_factor = healthPercentage
	return base_rate_days_per_second * health_factor

# Removed _calculate_altitude_factor() - health is now calculated directly in _update_health()

func _update_scale():
	# Only update scale periodically for performance
	if Time.get_ticks_msec() - last_scale_update < 250:  # Update every 250ms
		return
	
	last_scale_update = Time.get_ticks_msec()
	
	if not model_node:
		return
	
	# Calculate scale based on growth progress (10% to 100% of original size)
	var growth_ratio = growth_progress / max_growth_progress
	var scale_factor = 0.1 + (growth_ratio * 0.9)  # 0.1 to 1.0
	
	# Apply scale
	model_node.scale = initial_scale * scale_factor

# Helper function to get state name for UI
func get_state_name() -> String:
	match state:
		TreeState.GROWING:
			return "GROWING"
		TreeState.MATURE:
			return "MATURE"
		TreeState.DORMANT:
			return "DORMANT"
		TreeState.DYING:
			return "DYING"
		_:
			return "UNKNOWN"

func get_state_display_name() -> String:
	match state:
		TreeState.GROWING:
			return "Growing"
		TreeState.MATURE:
			return "Mature"
		TreeState.DORMANT:
			return "Dormant"
		TreeState.DYING:
			return "Dying"
		_:
			return "Unknown"

func _setup_seasonal_materials():
	# Ensure all mesh surfaces have a valid material to avoid renderer null-material errors
	if mesh_instance and mesh_instance.mesh:
		var surface_count = mesh_instance.mesh.get_surface_count()
		for i in surface_count:
			var override_mat: Material = mesh_instance.get_surface_override_material(i)
			var mesh_mat: Material = mesh_instance.mesh.surface_get_material(i) if mesh_instance.mesh else null
			if not override_mat and not mesh_mat:
				mesh_instance.set_surface_override_material(i, _get_default_surface_material())

	# Determine leaf material index based on tree species
	var leaf_material_index = _get_leaf_material_index()
	
	# Store original leaf material (check both override materials and mesh materials)
	var material_count = max(mesh_instance.get_surface_override_material_count(), mesh_instance.mesh.get_surface_count())
	
	if material_count > leaf_material_index:
		# Try to get override material first, then fall back to mesh material
		original_leaf_material = mesh_instance.get_surface_override_material(leaf_material_index)
		if not original_leaf_material and mesh_instance.mesh:
			original_leaf_material = mesh_instance.mesh.surface_get_material(leaf_material_index)
		
		# Create or reuse seasonal versions of leaf material
		if original_leaf_material:
			winter_leaf_material = _get_cached_winter_material(species_name, original_leaf_material.resource_name)
			var autumn_color = _get_autumn_color_for_species()
			if autumn_color != Color.TRANSPARENT:
				autumn_leaf_material = _get_cached_autumn_material(species_name, autumn_color, original_leaf_material.resource_name)
			else:
				autumn_leaf_material = null
		else:
			print("Warning: No leaf material found for ", species_name, " at index ", leaf_material_index)
	else:
		print("Warning: Not enough materials for ", species_name, " (expected index: ", leaf_material_index, ", available: ", material_count, ")")

func _get_leaf_material_index() -> int:
	# Special case for Birch: has 2 bark materials (indices 0,1) and leaves at index 2
	if species_name.to_lower() == "birch":
		return 2
	else:
		# Standard case: bark at index 0, leaves at index 1
		return 1

func _get_autumn_color_for_species() -> Color:
	# Return autumn colors based on species
	match species_name.to_lower():
		"aspen":
			return Color(1.0, 0.6, 0.2, 1.0)  # Orange
		"maple":
			return Color(0.8, 0.2, 0.1, 1.0)  # Red
		"pine", "spruce":
			return Color.TRANSPARENT  # Conifers don't change color
		_:
			return Color(1.0, 0.9, 0.3, 1.0)  # Yellow for most other deciduous trees

func _connect_to_time_manager():
	# Find TimeManager and connect to season changes
	var root = get_tree().current_scene
	time_manager = root.find_child("TimeManager", true, false)
	
	if time_manager and time_manager.has_signal("season_changed"):
		time_manager.season_changed.connect(_on_season_changed)
		
		# Apply current season immediately for newly spawned trees
		if time_manager.has_method("get_current_season") and time_manager.has_method("get_current_winter_factor"):
			var current_season = time_manager.get_current_season()
			var current_winter_factor = time_manager.get_current_winter_factor()
			_on_season_changed(current_season, current_winter_factor)
			#print("Tree ", species_name, " connected to TimeManager and applied current season: ", current_season)
		#else:
			#print("Tree ", species_name, " connected to TimeManager")
	else:
		print("Warning: Could not connect to TimeManager season signal for ", species_name)

func _on_season_changed(season: String, winter_factor: float):
	# Switch materials based on season
	var should_be_winter = (winter_factor > 0.5)
	var should_be_autumn = (season.to_lower() == "autumn")
	
	if should_be_winter != is_winter or should_be_autumn != is_autumn:
		is_winter = should_be_winter
		is_autumn = should_be_autumn
		_update_seasonal_appearance()

	# Seasonal transitions and seed spawn policy
	var s := season.to_lower()
	if s == "winter":
		# Enter dormancy during winter
		if state != TreeState.DYING:
			state = TreeState.DORMANT
	elif s == "summer":
		# At summer start, spawn a seed if fully grown and none present
		if state != TreeState.DYING and growth_progress >= max_growth_progress:
			if not is_instance_valid(spawned_seed):
				_spawn_seed_on_tree()
	else:
		# Leaving winter: if we were dormant, resume mature/growing depending on growth
		if state == TreeState.DORMANT:
			if growth_progress >= max_growth_progress:
				state = TreeState.MATURE
			else:
				state = TreeState.GROWING

func _update_seasonal_appearance():
	if not mesh_instance or not original_leaf_material or not winter_leaf_material:
		return
	
	var leaf_material_index = _get_leaf_material_index()
	
	if is_winter:
		# Use gradual winter transition
		_update_winter_color_transition()
		#print("Tree ", species_name, " updating winter appearance with gradual transition (leaf index: ", leaf_material_index, ")")
	elif is_autumn and autumn_leaf_material:
		# For autumn, we need to gradually interpolate between normal and autumn colors
		_update_autumn_color_transition()
	else:
		# Switch back to original leaves
		mesh_instance.set_surface_override_material(leaf_material_index, original_leaf_material)
		#print("Tree ", species_name, " switched to normal appearance (leaf index: ", leaf_material_index, ")")

func _ensure_transition_material():
	if transition_material == null:
		transition_material = StandardMaterial3D.new()
		transition_material.resource_name = "Transition " + (original_leaf_material.resource_name if original_leaf_material else species_name)
		transition_material.vertex_color_use_as_albedo = true

func _apply_transition(from_color: Color, to_color: Color, progress: float, is_winter_transition: bool) -> void:
	_ensure_transition_material()
	var current_color = from_color.lerp(to_color, progress)
	transition_material.albedo_color = current_color
	if is_winter_transition:
		transition_material.emission_enabled = true
		transition_material.emission = Color(0.1, 0.1, 0.15) * progress
	var leaf_index = _get_leaf_material_index()
	mesh_instance.set_surface_override_material(leaf_index, transition_material)

func _get_original_leaf_color() -> Color:
	# Get original material color (default to green if we can't get it)
	var original_color = Color(0.3, 0.8, 0.2, 1.0)  # Default green
	if original_leaf_material is StandardMaterial3D:
		var original_std_mat = original_leaf_material as StandardMaterial3D
		original_color = original_std_mat.albedo_color
	return original_color

func _update_autumn_color_transition():
	if not autumn_leaf_material or not original_leaf_material:
		return
	
	# Get the current time from TimeManager to calculate autumn progress
	var root = get_tree().current_scene
	time_manager = root.find_child("TimeManager", true, false)
	
	if time_manager and time_manager.has_method("get_current_hour"):
		var current_hour = time_manager.get_current_hour()
		# Calculate autumn progress: 0.0 at midnight (00:00), 1.0 at noon (12:00)
		autumn_progress = clamp(current_hour / 12.0, 0.0, 1.0)
		
		var original_color = _get_original_leaf_color()
		var autumn_color = autumn_leaf_material.albedo_color
		
		# Apply transition using a single reusable material
		_apply_transition(original_color, autumn_color, autumn_progress, false)

func _update_winter_color_transition():
	if not winter_leaf_material or not original_leaf_material:
		return
	
	# Get the current time from TimeManager to calculate winter progress
	var root = get_tree().current_scene
	time_manager = root.find_child("TimeManager", true, false)
	
	if time_manager and time_manager.has_method("get_current_hour"):
		var current_hour = time_manager.get_current_hour()
		
		# Calculate winter progress based on time of day
		var transition_progress: float
		var from_color: Color
		var to_color: Color
		
		if current_hour <= 2.0:
			# Beginning of winter: transition from autumn to winter (00:00 - 02:00)
			transition_progress = clamp(current_hour / 2.0, 0.0, 1.0)
			# Get autumn color for this species (or default green if no autumn color)
			var autumn_color = Color.TRANSPARENT
			if autumn_leaf_material:
				autumn_color = autumn_leaf_material.albedo_color
			else:
				autumn_color = _get_original_leaf_color()  # Fall back to green for conifers
			
			from_color = autumn_color
			to_color = winter_leaf_material.albedo_color
		elif current_hour >= 22.0:
			# End of winter: transition from winter to default (22:00 - 00:00)
			transition_progress = clamp((24.0 - current_hour) / 2.0, 0.0, 1.0)
			from_color = _get_original_leaf_color()
			to_color = winter_leaf_material.albedo_color
		else:
			# Full winter during the middle hours - just use winter material directly
			var leaf_material_index = _get_leaf_material_index()
			mesh_instance.set_surface_override_material(leaf_material_index, winter_leaf_material)
			return
		
		# Apply transition using a single reusable material
		_apply_transition(from_color, to_color, transition_progress, true)

func _handle_seed_lifecycle(_delta: float):
	# Seeds are spawned at summer start; nothing to do each tick here.
	pass

func _spawn_seed_on_tree():
	# Create single seed at the designated spawn point
	var current_scale = model_node.scale if model_node else Vector3.ONE
	var world_spawn_position = global_position + (seed_spawn_point * current_scale)
	
	spawned_seed = _create_seed_visual(world_spawn_position)
	seed_ready_to_fly = true
	#print("Tree ", species_name, " spawned 1 seed at designated spawn point")

func _on_reproduction_event() -> void:
	# Ensure a seed visual exists upon reproduction (like berries refresh)
	if not is_instance_valid(spawned_seed):
		_spawn_seed_on_tree()

func _request_spawn(spawn_pos: Vector3) -> void:
	# Trees route reproduction spawns to tree spawner
	var root = get_tree().current_scene
	var tm = root.find_child("TreeManager", true, false)
	if tm and tm.has_method("request_tree_spawn"):
		tm.request_tree_spawn(species_name, spawn_pos)

func _create_seed_visual(spawn_position: Vector3) -> Node3D:
	# Create a simple spherical seed visual and attach to the tree
	var seed_visual = Node3D.new()
	var mesh_instance_seed = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = max(0.02, seed_size)
	sphere.height = sphere.radius * 2.0
	mesh_instance_seed.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = _get_species_seed_color()
	mesh_instance_seed.material_override = m
	seed_visual.add_child(mesh_instance_seed)
	add_child(seed_visual)
	seed_visual.global_position = spawn_position
	return seed_visual

func _get_species_seed_color() -> Color:
	match species_name.to_lower():
		"pine", "spruce":
			return Color(0.4, 0.2, 0.1)  # Brown
		"maple", "birch":
			return Color(0.8, 0.7, 0.4)  # Light brown
		"oak":
			return Color(0.3, 0.2, 0.1)  # Dark brown
		"rowan":
			return Color(0.7, 0.0, 0.0)  # Red
		"willow":
			return Color(0.9, 0.9, 0.8)  # White/cream
		_:
			return Color(0.6, 0.4, 0.2)  # Default brown


## Removed seed release and germination

# Death system functions
func _start_dying():
	print("Tree ", species_name, " is dying from old age at ", current_age, " years")
	state = TreeState.DYING
	dying_timer = 0.0
	has_fallen = false
	
	# Destroy any attached seed immediately
	_destroy_attached_seed()

func _destroy_attached_seed():
	if spawned_seed and is_instance_valid(spawned_seed):
		print("Destroying attached seed")
		spawned_seed.queue_free()
		spawned_seed = null
		seed_ready_to_fly = false

func _start_falling():
	if has_fallen:
		return
		
	has_fallen = true
	print("Tree ", species_name, " starts falling over")
	
	# Disable collision body
	if collision_body:
		collision_body.process_mode = Node.PROCESS_MODE_DISABLED
		# Hide collision shape visually (if it has debug shapes)
		var collision_shape = collision_body.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if collision_shape:
			collision_shape.disabled = true
	
	# Start falling animation
	if model_node:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_QUAD)
		
		# Rotate tree to fallen position (90 degrees around random horizontal axis)
		var fall_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var fall_axis = fall_direction.cross(Vector3.UP).normalized()
		var target_rotation = model_node.rotation + fall_axis * PI/2
		
		# Animate the fall over 3-5 seconds
		var fall_duration = randf_range(3.0, 5.0)
		tween.tween_property(model_node, "rotation", target_rotation, fall_duration)

func _remove_tree():
	print("Removing dead tree: ", species_name)
	# Final cleanup and removal
	queue_free()
