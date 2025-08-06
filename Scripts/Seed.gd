extends RigidBody3D
class_name Seed

# Seed properties
@export var species_name: String = ""
@export var seed_type: String = "spherical"  # "spherical", "ovoid", "winged", "cone"
@export var base_size: float = 0.1
@export var mass_kg: float = 0.001
@export var drag_coefficient: float = 0.47  # Sphere drag coefficient
@export var terminal_velocity: float = 2.0
@export var lifespan: float = 30.0  # How long seed stays active
@export var germination_chance: float = 0.1  # Chance to germinate when landing

# State tracking
var age: float = 0.0
var has_landed: bool = false
var landing_position: Vector3
var parent_tree: TreeBase
var wind_manager: Node

# Visual components
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

func _ready():
	# Set up physics properties
	mass = mass_kg
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 10
	
	# Set seed collision layer (layer 4) and mask (collides with terrain layer 2 only)
	set_collision_layer_value(4, true)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, true)
	
	# Ensure physics stability
	continuous_cd = true
	can_sleep = false
	lock_rotation = false  # Allow natural rotation
	
	# Find wind manager
	wind_manager = get_tree().current_scene.find_child("WindManager", true, false)
	
	# Create visual representation
	_create_seed_mesh()
	
	# Set up collision
	_create_collision_shape()
	
	# Connect collision detection
	body_entered.connect(_on_body_entered)
	
	print("Seed created: ", species_name, " type: ", seed_type)

# Static function to create seed mesh - can be used by both visual and physics seeds
static func create_seed_mesh(type: String, size: float) -> Mesh:
	match type:
		"spherical":
			var sphere = SphereMesh.new()
			sphere.radius = size
			sphere.height = size * 2
			return sphere
		
		"ovoid":
			var capsule = CapsuleMesh.new()
			capsule.radius = size
			capsule.height = size * 2.5
			return capsule
		
		"winged":
			# Create a simple winged seed (like maple)
			var box = BoxMesh.new()
			box.size = Vector3(size * 3, size * 0.3, size * 0.5)
			return box
		
		"cone":
			# Create cone-like seed (like spruce)
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = size * 0.3
			cylinder.bottom_radius = size
			cylinder.height = size * 1.5
			return cylinder
		
		_:
			# Default to spherical if unknown type
			var sphere = SphereMesh.new()
			sphere.radius = size
			sphere.height = size * 2
			return sphere

func _create_seed_mesh():
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = _get_seed_color()
	
	# Use the shared static function
	mesh_instance.mesh = Seed.create_seed_mesh(seed_type, base_size)
	
	# Set drag coefficient for winged seeds
	if seed_type == "winged":
		drag_coefficient = 1.2  # Higher drag for winged seeds
	
	mesh_instance.material_override = material

func _create_collision_shape():
	collision_shape = CollisionShape3D.new()
	add_child(collision_shape)
	
	match seed_type:
		"spherical":
			var sphere_shape = SphereShape3D.new()
			sphere_shape.radius = base_size
			collision_shape.shape = sphere_shape
		
		"ovoid":
			var capsule_shape = CapsuleShape3D.new()
			capsule_shape.radius = base_size
			capsule_shape.height = base_size * 2.5
			collision_shape.shape = capsule_shape
		
		"winged":
			var box_shape = BoxShape3D.new()
			box_shape.size = Vector3(base_size * 3, base_size * 0.3, base_size * 0.5)
			collision_shape.shape = box_shape
		
		"cone":
			var cylinder_shape = CylinderShape3D.new()
			cylinder_shape.height = base_size * 1.5
			cylinder_shape.radius = base_size * 0.3
			collision_shape.shape = cylinder_shape

func _get_seed_color() -> Color:
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

func _physics_process(delta):
	age += delta
	
	# Validate position and velocity to prevent NaN errors
	if not global_position.is_finite():
		print("Warning: Seed position became invalid, removing seed")
		queue_free()
		return
	
	if not linear_velocity.is_finite():
		print("Warning: Seed velocity became invalid, resetting")
		linear_velocity = Vector3.ZERO
		return
	
	# Apply wind forces if not landed
	if not has_landed and wind_manager:
		_apply_wind_force(delta)
	
	# Check for landing using velocity and position
	if not has_landed:
		_check_landing()
	
	# Remove old seeds
	if age > lifespan:
		_attempt_germination()

func _apply_wind_force(_delta: float):
	var wind_force = wind_manager.get_wind_at_position(global_position)
	
	# Validate wind force
	if not wind_force.is_finite():
		wind_force = Vector3.ZERO
	
	# Scale wind force by seed properties (limit maximum force)
	wind_force = wind_force.limit_length(50.0)  # Prevent extreme forces
	
	# Apply drag based on seed type and current velocity
	var drag_force = -linear_velocity * drag_coefficient * 0.1
	
	# Validate drag force
	if not drag_force.is_finite():
		drag_force = Vector3.ZERO
	
	# Combine forces
	var total_force = wind_force + drag_force
	
	# Final validation and clamping
	if total_force.is_finite():
		total_force = total_force.limit_length(100.0)  # Cap maximum force
		apply_central_force(total_force)
	else:
		print("Warning: Invalid force calculated, skipping wind application")

func _check_landing():
	# Check if seed is moving slowly or has low velocity
	var velocity_threshold = 2.0
	if linear_velocity.length() > velocity_threshold:
		return  # Still moving too fast
	
	# Use raycast to check if we're close to ground
	var space_state = get_world_3d().direct_space_state
	var ray_length = base_size * 2.0  # Adjust ray length based on seed size
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -ray_length, 0),
		# Check only the terrain's collision layer
		#4294967295 - 4
		2
	)
	
	var result = space_state.intersect_ray(query)
	if result:
		var distance_to_ground = global_position.distance_to(result.position)
		
		# Land if we're very close to the ground
		if distance_to_ground <= base_size * 1.5:
			has_landed = true
			landing_position = result.position + Vector3(0, base_size * 0.5, 0)  # Slightly above ground
			
			# Move to landing position and stop physics
			global_position = landing_position
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			freeze = true
			
			print("Seed landed: ", species_name, " at ", landing_position)

func _attempt_germination():
	if has_landed and randf() < germination_chance:
		_germinate()
	else:
		queue_free()

func _germinate():
	# Try to spawn a new tree at landing position
	var terrain = get_tree().current_scene.find_child("Terrain", true, false)
	if terrain and terrain.has_method("get_height"):
		var terrain_height = terrain.get_height(landing_position.x, landing_position.z)
		var spawn_position = Vector3(landing_position.x, terrain_height, landing_position.z)
		
		# Load and instantiate tree scene
		var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
		var tree_scene = load(tree_scene_path)
		
		if tree_scene:
			var tree_instance = tree_scene.instantiate()
			terrain.get_parent().add_child(tree_instance)
			tree_instance.global_position = spawn_position
			print("Seed germinated! New ", species_name, " tree at ", spawn_position)
	
	queue_free()

func _on_body_entered(body):
	# Handle collision with terrain or other objects
	if not has_landed:
		# Check if we hit terrain or a static body
		if body.name.contains("Terrain"):
			# Reduce velocity on collision to simulate bouncing/rolling
			linear_velocity *= 0.4
			angular_velocity *= 0.6
			
			# Add a small upward bounce
			linear_velocity.y += 1.0
			
			# Force a landing check after a short delay
			call_deferred("_check_landing")
			
			print("Seed collided with: ", body.name, " - velocity: ", linear_velocity.length())
