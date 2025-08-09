extends Node3D
class_name Seed

# Seed properties
@export var species_name: String = ""
@export var seed_type: String = "spherical"  # "spherical", "ovoid", "winged", "cone"
@export var base_size: float = 0.1
@export var mass_kg: float = 0.001
@export var drag_coefficient: float = 0.47  # Deprecated with non-physics seeds
@export var terminal_velocity: float = 2.0   # Deprecated with non-physics seeds
@export var lifespan: float = 30.0  # How long seed stays active
@export var germination_chance: float = 0.1  # Chance to germinate when landing

# State tracking
var age: float = 0.0
var has_landed: bool = false
var landing_position: Vector3
var parent_tree: TreeBase
var wind_manager: Node
var tree_manager: Node
var velocity: Vector3 = Vector3.ZERO

# Visual components
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

func _ready():
	# Find wind manager
	wind_manager = get_tree().current_scene.find_child("WindManager", true, false)
	# Find tree manager for batched updates and spatial queries
	tree_manager = get_tree().current_scene.find_child("TreeManager", true, false)
	
	# Create visual representation
	_create_seed_mesh()
	
	# Register this seed to TreeManager for batched updates
	var manager = get_tree().current_scene.find_child("TreeManager", true, false)
	if manager and manager.has_method("register_seed"):
		manager.register_seed(self)
	
	# Initialize constant velocity: horizontal from wind, vertical from mass
	var horizontal := Vector3.ZERO
	if wind_manager and wind_manager.has_method("get_wind_at_position"):
		var wind_vec: Vector3 = wind_manager.get_wind_at_position(global_position)
		horizontal = Vector3(wind_vec.x, 0.0, wind_vec.z).limit_length(3.0)
	var down_speed: float = max(0.5, mass_kg * 100.0)
	velocity = horizontal + Vector3(0.0, -down_speed, 0.0)

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
	# No physics shape required for constant-velocity seeds
	pass

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

func _process(delta):
	age += delta
	if has_landed:
		if age > lifespan:
			_attempt_germination()
		return
	
	if not global_position.is_finite():
		queue_free()
		return
	
	var next_pos = global_position + velocity * delta
	# Raycast from current to next position to robustly detect terrain
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, next_pos)
	# Limit to terrain layer (2)
	query.collision_mask = 1 << 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit = space_state.intersect_ray(query)
	if hit:
		has_landed = true
		var hp: Vector3 = hit.position
		landing_position = hp + Vector3(0, base_size * 0.5, 0)
		global_position = landing_position
		velocity = Vector3.ZERO
	else:
		global_position = next_pos
	
	if age > lifespan:
		_attempt_germination()

# Called by TreeManager in batches
func _manager_tick(_dt: float) -> void:
	if not has_landed:
		return
	# Try germination sooner in manager when landed and old enough
	if age > lifespan:
		_attempt_germination()

func _apply_wind_force(_delta: float):
	pass

func _check_landing():
	pass

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
		# Abort if space is not free within species' needs_free_radius
		if not _is_space_free_for_species(spawn_position):
			queue_free()
			return
		
		# Defer creation to TreeManager queue (cached and budgeted)
		var tm = get_tree().current_scene.find_child("TreeManager", true, false)
		if tm and tm.has_method("request_germination"):
			tm.request_germination(species_name, spawn_position)
			#print("Seed germinated! New ", species_name, " tree at ", spawn_position)
	
	# Unregister from manager before freeing
	var tm2 = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm2 and tm2.has_method("unregister_seed"):
		tm2.unregister_seed(self)
	queue_free()

func _is_space_free_for_species(spawn_position: Vector3) -> bool:
	var required_radius: float = 6.0
	if parent_tree and parent_tree is TreeBase:
		required_radius = (parent_tree as TreeBase).needs_free_radius

	# Use TreeManager spatial index if available, else fall back to physics query
	if tree_manager and tree_manager.has_method("is_space_free"):
		return tree_manager.is_space_free(spawn_position, required_radius)

	var space_state = get_world_3d().direct_space_state
	var sphere = SphereShape3D.new()
	sphere.radius = required_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, spawn_position)
	params.collision_mask = 1 << 2  # layer 3
	if parent_tree and parent_tree.collision_body:
		params.exclude = [parent_tree.collision_body.get_rid()]
	var results = space_state.intersect_shape(params, 1)
	return results.size() == 0

func _on_body_entered(_body):
	pass
