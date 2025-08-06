@tool
extends MeshInstance3D

const size := 256.0

@export_range(4, 256, 4) var resolution := 32:
	set(new_resolution):
		resolution = new_resolution
		update_mesh()

@export var noise: FastNoiseLite:
	set(new_noise):
		noise = new_noise
		update_mesh()
		if noise:
			noise.changed.connect(update_mesh)

@export_range(4.0, 128.0, 4.0) var height := 64.0:
	set(new_height):
		height = new_height
		material_override.set_shader_parameter("height", height * 2.0)
		update_mesh()

# Collision components
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func get_height(x: float, y: float) -> float:
	return (noise.get_noise_2d(x, y) * height) + 5.0

func get_normal(x: float, y: float) -> Vector3:
	var epsilon := size / resolution
	var normal := Vector3(
		(get_height(x + epsilon, y) - get_height(x - epsilon, y)) / (2.0 * epsilon),
		1.0,
		(get_height(x, y + epsilon) - get_height(x, y - epsilon)) / (2.0 * epsilon)
	)
	return normal.normalized()

func update_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.subdivide_depth = resolution
	plane.subdivide_width = resolution
	plane.size = Vector2(size, size)
	
	var plane_arrays := plane.get_mesh_arrays()
	var vertex_array: PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_VERTEX]
	var normal_array: PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_NORMAL]
	var tangent_array: PackedFloat32Array = plane_arrays[ArrayMesh.ARRAY_TANGENT]
	
	for i:int in vertex_array.size():
		var vertex := vertex_array[i]
		var normal := Vector3.UP
		var tangent := Vector3.RIGHT
		if noise:
			vertex.y = get_height(vertex.x, vertex.z)
			normal = get_normal(vertex.x, vertex.z)
			tangent = normal.cross(Vector3.UP)
		vertex_array[i] = vertex
		normal_array[i] = normal
		tangent_array[4 * i] = tangent.x
		tangent_array[4 * i + 1] = tangent.y
		tangent_array[4 * i + 2] = tangent.z
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	mesh = array_mesh
	
	# Update collision shape
	_update_collision_shape(array_mesh)

func _ready():
	# Set up collision components
	_setup_collision()
	
	# Call update_mesh to initialize everything
	if not Engine.is_editor_hint():
		call_deferred("update_mesh")

func _setup_collision():
	# Create StaticBody3D for collision
	static_body = StaticBody3D.new()
	static_body.name = "TerrainCollision"
	
	# Set terrain collision layer (layer 2)
	static_body.set_collision_layer_value(2, true)
	static_body.set_collision_mask_value(1, false)
	
	add_child(static_body)
	
	# Create CollisionShape3D
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "TerrainCollisionShape"
	static_body.add_child(collision_shape)
	
	print("Terrain collision components created")

func _update_collision_shape(array_mesh: ArrayMesh):
	if not collision_shape:
		return
	
	# Create a trimesh collision shape from the mesh
	var trimesh_shape = array_mesh.create_trimesh_shape()
	if trimesh_shape:
		collision_shape.shape = trimesh_shape
		print("Terrain collision shape updated with ", array_mesh.surface_get_array_len(0), " vertices")
	else:
		print("Failed to create terrain collision shape")
