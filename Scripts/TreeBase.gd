extends Node3D
class_name TreeBase

# Tree state enum
enum TreeState {
	GROWING,
	SEED_PRODUCTION,
	SEED_MATURATION,
	MATURE,
	DYING
}

@export var species_name:          String = "Alder"
@export var ideal_altitude:        float = 10.0
@export var min_viable_altitude:   float = 0.0
@export var max_viable_altitude:   float = 50.0
## The radius in which this tree blocks other trees from spawning
@export var blocking_radius:       float = 5.0
## The radius which this tree needs to be free in order to spawn
@export var needs_free_radius:     float = 6.0
## Time (s) that it takes for the tree to mature given 100% health
@export var max_growth_progress:   float = 60.0
@export var max_age:               float = 300.0
## Idle time in MATURE state at 100% health before the tree starts producing seed
@export var ideal_maturation_idle_time: float = 30.0
## Time (s) that it takes for the tree to produce a new seed after losing the previous one given 100% health
@export var ideal_seed_gen_interval:  float = 30.0
## Time that it takes for the seeds to mature after they have spawned on the tree
@export var ideal_seed_maturation_interval: float = 15.0
## Used to decide how much health damage intruding other trees deal to the tree
## So a small tree intruding into teh needs_free_radius of a big tree won't affect the big tree's health much,
## but vice versa the small tree would be affected a lot
@export var adult_size_factor:     float = 10.0

# Seed system properties
@export var seed_count_per_cycle: int = 5
@export var seed_spawn_radius: float = 2.0
@export var seed_type: String = "spherical"  # Will be overridden per species
@export var seed_size: float = 0.1
@export var seed_mass: float = 0.001
@export var seed_wind_sensitivity: float = 1.0

var healthPercentage:              float = 1.0  # Start with full health
var current_age:                   float = 0.0
var state:                         TreeState = TreeState.GROWING
## Growth progress accumulated, in ideal conditions equal to seconds but can be more
## If progress reaches max_growth_progress then the tree is fully grown
var growth_progress:               float = 0.0
var mature_idle_progress:          float = 0.0
var seed_production_progress:      float = 0.0
var seed_maturation_progress:      float = 0.0
var state_percentage:              float = 0.0
var time_until_next_repro_check:   float = 0.0

# Seed system variables
var spawned_seeds: Array[Node3D] = []
var seeds_ready_to_fly: bool = false

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

# Winter materials
var original_leaf_material:        Material
var winter_leaf_material:          StandardMaterial3D
var is_winter:                     bool = false

func _ready():
	# Initialize tree
	time_until_next_repro_check = ideal_seed_gen_interval
	growth_progress = 0.0
	state = TreeState.GROWING
	
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
			_setup_winter_materials()
		else:
			print("Warning: No MeshInstance3D found in tree ", species_name)
	else:
		print("Warning: No 'Model' node found in tree ", species_name)
	
	# Find collision body for death system
	collision_body = find_child("StaticBody3D", true, false) as StaticBody3D
	if not collision_body:
		print("Warning: No StaticBody3D found in tree ", species_name)
	
	# Connect to TimeManager for seasonal changes
	_connect_to_time_manager.call_deferred()

func _process(delta):
	current_age += delta
	
	# Check for age-based death
	if current_age >= max_age and state != TreeState.DYING:
		_start_dying()
		return
	
	# Update health based on environmental conditions
	_update_health()
	
	# Update growth based on state
	_update_growth(delta)
	
	# Update visual scale (performance optimized)
	_update_scale()
	
	# Handle seed lifecycle
	_handle_seed_lifecycle(delta)
	
	# Handle reproduction
	time_until_next_repro_check -= delta
	if time_until_next_repro_check <= 0.0:
		_try_reproduce()
		time_until_next_repro_check = ideal_seed_gen_interval

func _try_reproduce():
	# check altitude, age, maybe spawn a new TreeBase instance…
	pass

func _update_growth(delta: float):
	match state:
		TreeState.GROWING:
			# Calculate growth rate based on health and environmental factors
			var growth_rate = _calculate_growth_rate()
			growth_progress += delta * growth_rate
			
			# Clamp growth progress to max value
			growth_progress = min(growth_progress, max_growth_progress)
			
			# Update state percentage for UI
			state_percentage = growth_progress / max_growth_progress
			
			# Check if fully grown
			if growth_progress >= max_growth_progress:
				state = TreeState.MATURE
				state_percentage = 1.0
		
		TreeState.SEED_PRODUCTION:
			seed_production_progress += delta * healthPercentage
			seed_production_progress = min(seed_production_progress, ideal_seed_gen_interval)
			state_percentage = seed_production_progress / ideal_seed_gen_interval
			
			if seed_production_progress >= ideal_seed_gen_interval:
				state = TreeState.SEED_MATURATION
				seed_production_progress = 0.0
				state_percentage = 0.0
		
		TreeState.SEED_MATURATION:
			seed_maturation_progress += delta * healthPercentage
			seed_maturation_progress = min(seed_maturation_progress, ideal_seed_maturation_interval)
			state_percentage = seed_maturation_progress / ideal_seed_maturation_interval
			
			if seed_maturation_progress >= ideal_seed_maturation_interval:
				# Release seeds before transitioning to MATURE
				if seeds_ready_to_fly and not spawned_seeds.is_empty():
					_release_seeds()
					seeds_ready_to_fly = false
				
				state = TreeState.MATURE
				seed_maturation_progress = 0.0
				state_percentage = 0.0
		
		TreeState.MATURE:
			# Mature trees wait in idle state before starting seed production
			mature_idle_progress += delta * healthPercentage
			mature_idle_progress = min(mature_idle_progress, ideal_maturation_idle_time)
			state_percentage = mature_idle_progress / ideal_maturation_idle_time
			
			if mature_idle_progress >= ideal_maturation_idle_time:
				state = TreeState.SEED_PRODUCTION
				mature_idle_progress = 0.0
				state_percentage = 0.0
		
		TreeState.DYING:
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

func _update_health():
	# Calculate health based on altitude
	var current_altitude = global_position.y
	
	# Perfect health at ideal altitude
	if abs(current_altitude - ideal_altitude) < 0.1:
		healthPercentage = 1.0
		return
	
	# Check if outside tolerable range (health would be 0%)
	if current_altitude < min_viable_altitude or current_altitude > max_viable_altitude:
		healthPercentage = 0.0
		return
	
	# Linear interpolation between 25% and 100% health within tolerable range
	var distance_from_ideal = abs(current_altitude - ideal_altitude)
	
	# Calculate max distance from ideal to either boundary
	var max_distance_below = ideal_altitude - min_viable_altitude
	var max_distance_above = max_viable_altitude - ideal_altitude
	var max_distance = max_distance_above if current_altitude > ideal_altitude else max_distance_below
	
	# Avoid division by zero
	if max_distance <= 0:
		healthPercentage = 1.0
		return
	
	# Linear scaling: 100% at ideal, 25% at boundaries
	var health_ratio = 1.0 - (distance_from_ideal / max_distance)
	healthPercentage = 0.25 + (health_ratio * 0.75)  # Scale from 25% to 100%
	
	# Clamp to ensure we stay within bounds
	healthPercentage = clamp(healthPercentage, 0.0, 1.0)

func _calculate_growth_rate() -> float:
	# Base rate should be 1.0 progress units per second at 100% health
	var base_rate = 1.0
	
	# Health affects growth rate (calculated automatically based on altitude)
	var health_factor = healthPercentage
	
	# Final rate: max 1.0 per second with perfect health
	return base_rate * health_factor

# Removed _calculate_altitude_factor() - health is now calculated directly in _update_health()

func _update_scale():
	# Only update scale periodically for performance
	if Time.get_ticks_msec() - last_scale_update < 100:  # Update every 100ms
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
		TreeState.SEED_PRODUCTION:
			return "SEED_PRODUCTION"
		TreeState.SEED_MATURATION:
			return "SEED_MATURATION"
		TreeState.MATURE:
			return "MATURE"
		TreeState.DYING:
			return "DYING"
		_:
			return "UNKNOWN"

func _setup_winter_materials():
	# Determine leaf material index based on tree species
	var leaf_material_index = _get_leaf_material_index()
	
	# Store original leaf material (check both override materials and mesh materials)
	var material_count = max(mesh_instance.get_surface_override_material_count(), mesh_instance.mesh.get_surface_count())
	
	if material_count > leaf_material_index:
		# Try to get override material first, then fall back to mesh material
		original_leaf_material = mesh_instance.get_surface_override_material(leaf_material_index)
		if not original_leaf_material and mesh_instance.mesh:
			original_leaf_material = mesh_instance.mesh.surface_get_material(leaf_material_index)
		
		# Create winter version of leaf material
		if original_leaf_material:
			winter_leaf_material = StandardMaterial3D.new()
			winter_leaf_material.resource_name = "Winter " + original_leaf_material.resource_name
			winter_leaf_material.vertex_color_use_as_albedo = true
			winter_leaf_material.albedo_color = Color(0.9, 0.9, 0.95, 1.0)  # Snowy white
			winter_leaf_material.emission_enabled = true
			winter_leaf_material.emission = Color(0.1, 0.1, 0.15)  # Slight blue tint
			print("Created winter material for ", species_name, " (leaf material index: ", leaf_material_index, ")")
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

func _connect_to_time_manager():
	# Find TimeManager and connect to season changes
	var root = get_tree().current_scene
	var time_manager = root.find_child("TimeManager", true, false)
	
	if time_manager and time_manager.has_signal("season_changed"):
		time_manager.season_changed.connect(_on_season_changed)
		
		# Apply current season immediately for newly spawned trees
		if time_manager.has_method("get_current_season") and time_manager.has_method("get_current_winter_factor"):
			var current_season = time_manager.get_current_season()
			var current_winter_factor = time_manager.get_current_winter_factor()
			_on_season_changed(current_season, current_winter_factor)
			print("Tree ", species_name, " connected to TimeManager and applied current season: ", current_season)
		else:
			print("Tree ", species_name, " connected to TimeManager")
	else:
		print("Warning: Could not connect to TimeManager season signal for ", species_name)

func _on_season_changed(_season: String, winter_factor: float):
	# Switch materials based on season
	var should_be_winter = (winter_factor > 0.5)
	
	if should_be_winter != is_winter:
		is_winter = should_be_winter
		_update_seasonal_appearance()

func _update_seasonal_appearance():
	if not mesh_instance or not original_leaf_material or not winter_leaf_material:
		return
	
	var leaf_material_index = _get_leaf_material_index()
	
	if is_winter:
		# Switch to winter (snowy) leaves
		mesh_instance.set_surface_override_material(leaf_material_index, winter_leaf_material)
		print("Tree ", species_name, " switched to winter appearance (leaf index: ", leaf_material_index, ")")
	else:
		# Switch back to original leaves
		mesh_instance.set_surface_override_material(leaf_material_index, original_leaf_material)
		print("Tree ", species_name, " switched to normal appearance (leaf index: ", leaf_material_index, ")")

func _handle_seed_lifecycle(_delta: float):
	match state:
		TreeState.SEED_PRODUCTION:
			# Seeds are being produced - no visual seeds yet
			pass
			
		TreeState.SEED_MATURATION:
			# Seeds are maturing on the tree
			if not seeds_ready_to_fly and spawned_seeds.is_empty():
				_spawn_seeds_on_tree()
			
		TreeState.MATURE:
			# Mature trees are in idle state, no seed actions needed
			pass

func _spawn_seeds_on_tree():
	# Create seeds attached to the tree
	for i in range(seed_count_per_cycle):
		var seed_position = _get_seed_spawn_position()
		var seed_visual = _create_seed_visual(seed_position)
		spawned_seeds.append(seed_visual)
	
	seeds_ready_to_fly = true
	print("Tree ", species_name, " spawned ", seed_count_per_cycle, " seeds")

func _get_seed_spawn_position() -> Vector3:
	# Spawn seeds around the tree canopy
	var angle = randf() * TAU
	var radius = randf_range(1.0, seed_spawn_radius)
	var height = randf_range(2.0, 4.0)  # Spawn in canopy area
	
	return global_position + Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)

func _create_seed_visual(spawn_position: Vector3) -> Node3D:
	# Create a simple visual representation of seeds on tree
	var seed_visual = Node3D.new()
	var mesh_instance_seed = MeshInstance3D.new()
	
	# Create small sphere to represent seed
	var sphere = SphereMesh.new()
	sphere.radius = seed_size * 0.5
	sphere.height = seed_size
	mesh_instance_seed.mesh = sphere
	
	# Set material based on species
	var material = StandardMaterial3D.new()
	material.albedo_color = _get_species_seed_color()
	mesh_instance_seed.material_override = material
	
	seed_visual.add_child(mesh_instance_seed)
	add_child(seed_visual)
	seed_visual.global_position = spawn_position
	
	return seed_visual

func _get_species_seed_color() -> Color:
	match species_name.to_lower():
		"pine", "spruce":
			return Color(0.4, 0.2, 0.1)
		"maple", "birch":
			return Color(0.8, 0.7, 0.4)
		"oak":
			return Color(0.3, 0.2, 0.1)
		"willow":
			return Color(0.9, 0.9, 0.8)
		_:
			return Color(0.6, 0.4, 0.2)

func _release_seeds():
	# Convert visual seeds to physics-based seeds
	var seed_scene = preload("res://Scripts/Seed.gd")
	
	for seed_visual in spawned_seeds:
		# Create physics seed
		var physics_seed = RigidBody3D.new()
		physics_seed.set_script(seed_scene)
		
		# Configure seed properties
		physics_seed.species_name = species_name
		physics_seed.seed_type = seed_type
		physics_seed.base_size = seed_size
		physics_seed.mass_kg = seed_mass
		physics_seed.wind_sensitivity = seed_wind_sensitivity
		physics_seed.parent_tree = self
		
		# Position the seed
		get_parent().add_child(physics_seed)
		physics_seed.global_position = seed_visual.global_position
		
		# Add some initial velocity
		var initial_velocity = Vector3(
			randf_range(-1, 1),
			randf_range(0.5, 2),
			randf_range(-1, 1)
		).normalized() * randf_range(1, 3)
		physics_seed.linear_velocity = initial_velocity
		
		# Remove visual seed
		seed_visual.queue_free()
	
	spawned_seeds.clear()
	print("Tree ", species_name, " released seeds into the wind!")

# Death system functions
func _start_dying():
	print("Tree ", species_name, " is dying from old age at ", current_age, " years")
	state = TreeState.DYING
	dying_timer = 0.0
	has_fallen = false
	
	# Destroy any attached seeds immediately
	_destroy_attached_seeds()

func _destroy_attached_seeds():
	print("Destroying ", spawned_seeds.size(), " attached seeds")
	for seed_visual in spawned_seeds:
		if is_instance_valid(seed_visual):
			seed_visual.queue_free()
	spawned_seeds.clear()

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
