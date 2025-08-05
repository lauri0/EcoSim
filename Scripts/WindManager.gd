extends Node
class_name WindManager

# Wind configuration
@export var base_wind_strength: float = 0.2
@export var wind_variation: float = 0.1
@export var wind_direction_change_rate: float = 0.5  # How fast wind direction changes
@export var wind_strength_change_rate: float = 0.3   # How fast wind strength changes
@export var wind_turbulence: float = 0.2             # Random turbulence factor

# Current wind state
var current_wind_direction: float = 0.0  # Angle in radians
var current_wind_strength: float = 1.0
var wind_vector: Vector3 = Vector3.ZERO

# Noise for realistic wind patterns
var wind_noise: FastNoiseLite
var time_elapsed: float = 0.0

func _ready():
	# Initialize noise for wind patterns
	wind_noise = FastNoiseLite.new()
	wind_noise.seed = randi()
	wind_noise.frequency = 0.1
	wind_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# Set initial wind
	current_wind_direction = randf() * TAU
	current_wind_strength = base_wind_strength
	
	print("WindManager initialized with base strength: ", base_wind_strength)

func _process(delta):
	time_elapsed += delta
	
	# Update wind direction using noise
	var direction_noise = wind_noise.get_noise_1d(time_elapsed * wind_direction_change_rate)
	if is_finite(direction_noise):
		current_wind_direction += direction_noise * delta * 0.5
		# Keep direction in reasonable range
		current_wind_direction = fmod(current_wind_direction, TAU)
	
	# Update wind strength using noise
	var strength_noise = wind_noise.get_noise_1d(time_elapsed * wind_strength_change_rate + 100.0)
	if is_finite(strength_noise):
		current_wind_strength = base_wind_strength + (strength_noise * wind_variation)
		current_wind_strength = clamp(current_wind_strength, 0.1, base_wind_strength * 3.0)  # Reasonable limits
	
	# Calculate wind vector
	wind_vector = Vector3(
		cos(current_wind_direction) * current_wind_strength,
		0,
		sin(current_wind_direction) * current_wind_strength
	)
	
	# Validate wind vector
	if not wind_vector.is_finite():
		wind_vector = Vector3(1.0, 0, 0) * base_wind_strength  # Fallback to default

func get_wind_at_position(position: Vector3) -> Vector3:
	# Validate input position
	if not position.is_finite():
		return Vector3.ZERO
	
	# Add position-based turbulence
	var turbulence_x = wind_noise.get_noise_2d(position.x * 0.1, time_elapsed * 0.5)
	var turbulence_z = wind_noise.get_noise_2d(position.z * 0.1, time_elapsed * 0.5 + 50.0)
	
	# Validate noise values
	if not is_finite(turbulence_x):
		turbulence_x = 0.0
	if not is_finite(turbulence_z):
		turbulence_z = 0.0
	
	var turbulence = Vector3(
		turbulence_x * wind_turbulence,
		0,
		turbulence_z * wind_turbulence
	)
	
	var result = wind_vector + turbulence
	
	# Final validation
	if not result.is_finite():
		return Vector3.ZERO
	
	return result

func get_wind_strength() -> float:
	return current_wind_strength

func get_wind_direction_degrees() -> float:
	return rad_to_deg(current_wind_direction)

# Debug function to set wind manually
func set_wind(direction_degrees: float, strength: float):
	current_wind_direction = deg_to_rad(direction_degrees)
	current_wind_strength = strength
	base_wind_strength = strength
