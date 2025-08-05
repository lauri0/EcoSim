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
## Time (s) that it takes for the tree to produce a new seed after losing the previous one given 100% health
@export var ideal_seed_gen_interval:  float = 30.0
## Time that it takes for the seeds to mature after they have spawned on the tree
@export var ideal_seed_maturation_interval: float = 15.0
## Used to decide how much health damage intruding other trees deal to the tree
## So a small tree intruding into teh needs_free_radius of a big tree won't affect the big tree's health much,
## but vice versa the small tree would be affected a lot
@export var adult_size_factor:     float = 10.0

var healthPercentage:              float = 1.0  # Start with full health
var current_age:                   float = 0.0
var state:                         TreeState = TreeState.GROWING
## Growth progress accumulated, in ideal conditions equal to seconds but can be more
## If progress reaches max_growth_progress then the tree is fully grown
var growth_progress:               float = 0.0
var seed_production_progress:      float = 0.0
var seed_maturation_progress:      float = 0.0
var state_percentage:              float = 0.0
var time_until_next_repro_check:   float = 0.0

# Growth and scaling
var initial_scale:                 Vector3 = Vector3.ONE
var model_node:                    Node3D  # Reference to the visual model
var last_scale_update:             float = 0.0  # For performance optimization

func _ready():
	# Initialize tree
	time_until_next_repro_check = ideal_seed_gen_interval
	growth_progress = 0.0
	state = TreeState.GROWING
	
	# Health will be calculated based on altitude in first _update_health() call
	
	# Find the model node (usually named "Model" in tree scenes)
	model_node = find_child("Model", true, false)
	if model_node:
		initial_scale = model_node.scale
		# Start with minimal scale (10% of full size)
		model_node.scale = initial_scale * 0.1
	else:
		print("Warning: No 'Model' node found in tree ", species_name)

func _process(delta):
	current_age += delta
	
	# Update health based on environmental conditions
	_update_health()
	
	# Update growth based on state
	_update_growth(delta)
	
	# Update visual scale (performance optimized)
	_update_scale()
	
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
				state = TreeState.MATURE
				seed_maturation_progress = 0.0
				state_percentage = 0.0
		
		TreeState.MATURE:
			# Mature trees can start seed production cycle
			state_percentage = 1.0
		
		TreeState.DYING:
			# Tree is dying, no growth
			state_percentage = 0.0
	
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
