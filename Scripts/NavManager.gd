@tool
extends Node3D
class_name NavManager

@export var agent_radius: float = 0.25
@export var agent_height: float = 0.6

# Optional raised navigation layer for flying animals (e.g., birds)
@export var bird_region_enabled: bool = true
@export var bird_region_height: float = 8.0

# NavigationMesh bake parameters (exposed for tuning)
@export var cell_size: float = 0.25
@export var cell_height: float = 0.25
@export var detail_sample_distance: float = 3.0
@export var detail_sample_max_error: float = 1.0
@export var edge_max_error: float = 2.0
@export var edge_max_length: float = 24.0
@export var region_min_size: float = 8.0
@export var region_merge_size: float = 20.0
@export var agent_max_climb: float = 0.5
@export var agent_max_slope: float = 45.0

# Source geometry parsing
# Layer mask used when collecting STATIC_COLLIDERS for the bake
# Defaults to layer 2 (terrain), i.e., 1 << 2 = 4
@export var parse_collision_layer: int = 1 << 2

var region: NavigationRegion3D
var bird_region: NavigationRegion3D
var _debug_mesh_instance: MeshInstance3D
var _debug_visible: bool = false

# Editor/runtime button to rebake the navmesh
var _rebake_now_backing: bool = false
@export var rebake_now: bool:
	get:
		return _rebake_now_backing
	set(value):
		# Trigger only when toggled on in the inspector
		if value:
			_rebake_now_backing = false
			rebake_navmesh()
		else:
			_rebake_now_backing = false

func _ready():
	# Find terrain as the only source for navmesh. Animals ignore vegetation for now.
	var root = get_tree().current_scene
	var terrain: Node3D = root.find_child("Terrain", true, false) as Node3D
	if terrain == null:
		push_warning("NavManager: Terrain not found; skipping navmesh bake")
		return

	# Create region (bake only at runtime by default)
	region = NavigationRegion3D.new()
	region.name = "MammalNavRegion"
	add_child(region)

	# Create optional raised bird region
	if bird_region_enabled:
		bird_region = NavigationRegion3D.new()
		bird_region.name = "BirdNavRegion"
		# Use a separate navigation layer so only birds use this region
		bird_region.navigation_layers = 2
		add_child(bird_region)

	if not Engine.is_editor_hint():
		rebake_navmesh()
		# Optional: build debug mesh (hidden by default)
		_build_debug_mesh()
		_set_debug_visible(false)

func rebake_navmesh() -> void:
	# Rebuild the NavigationMesh from the current terrain and assign it to the region
	var root = get_tree().current_scene
	var terrain: Node3D = root.find_child("Terrain", true, false) as Node3D
	if terrain == null:
		push_warning("NavManager: Terrain not found; cannot rebake navmesh")
		return
	var navmesh := _build_navmesh_from_terrain(terrain)
	if region == null:
		region = NavigationRegion3D.new()
		region.name = "MammalNavRegion"
		add_child(region)
	region.navigation_mesh = navmesh
	region.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	print("NavManager: Navigation mesh rebaked")

	# Assign the same mesh to the bird region but offset in Y
	if bird_region_enabled:
		if bird_region == null:
			bird_region = NavigationRegion3D.new()
			bird_region.name = "BirdNavRegion"
			add_child(bird_region)
			bird_region.navigation_layers = 2
		bird_region.navigation_mesh = navmesh
		bird_region.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, bird_region_height, 0.0))
	_build_debug_mesh()
	_set_debug_visible(_debug_visible)

func _build_navmesh_from_terrain(terrain: Node3D) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	# Apply exported parameters
	navmesh.agent_radius = agent_radius
	# Match default NavigationServer map cell dimensions to avoid assignment errors
	navmesh.cell_size = cell_size
	navmesh.cell_height = cell_height
	# Quantize height to cell-height to avoid precision warning
	var quantized_height: float = max(
		navmesh.cell_height,
		round(agent_height / navmesh.cell_height) * navmesh.cell_height
	)
	navmesh.agent_height = quantized_height
	navmesh.detail_sample_distance = detail_sample_distance
	navmesh.detail_sample_max_error = detail_sample_max_error
	navmesh.edge_max_error = edge_max_error
	navmesh.edge_max_length = edge_max_length
	navmesh.region_min_size = region_min_size
	navmesh.region_merge_size = region_merge_size
	navmesh.agent_max_climb = agent_max_climb
	navmesh.agent_max_slope = agent_max_slope

	# Bake using the recommended parse/bake pipeline
	var src := NavigationMeshSourceGeometryData3D.new()
	# Try to avoid GPU readback by favoring collision shapes
	if src.has_method("set_parsed_geometry_type"):
		# 1 = STATIC_COLLIDERS
		src.set_parsed_geometry_type(1)
		if src.has_method("set_collision_mask"):
			# Only parse selected collision layers (default: terrain layer 2)
			src.set_collision_mask(parse_collision_layer)
		NavigationServer3D.parse_source_geometry_data(navmesh, src, terrain)
	else:
		# Fallback: manually add the terrain collision shape mesh to the source
		var terrain_body := terrain.find_child("TerrainCollision", true, false) as StaticBody3D
		if terrain_body:
			var col_shape := terrain_body.find_child("TerrainCollisionShape", true, false) as CollisionShape3D
			if col_shape and col_shape.shape:
				var arr_mesh := ArrayMesh.new()
				var _gen := MeshDataTool.new()
				# Create a simple flat quad as a placeholder if conversion not feasible
				# This at least gives a navigable surface; replace with robust conversion if needed
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.add_vertex(Vector3(-64, 0, -64))
				st.add_vertex(Vector3(64, 0, -64))
				st.add_vertex(Vector3(64, 0, 64))
				st.add_vertex(Vector3(-64, 0, -64))
				st.add_vertex(Vector3(64, 0, 64))
				st.add_vertex(Vector3(-64, 0, 64))
				arr_mesh = st.commit()
				src.add_mesh(arr_mesh, Transform3D.IDENTITY)
		NavigationServer3D.parse_source_geometry_data(navmesh, src, terrain)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	return navmesh

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Toggle with N key
		if (event.keycode == KEY_N):
			_set_debug_visible(not _debug_visible)

func _build_debug_mesh() -> void:
	if not region or not region.navigation_mesh:
		return
	var navmesh: NavigationMesh = region.navigation_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	# Red unshaded material
	var mat := StandardMaterial3D.new()
	mat.unshaded = true
	mat.albedo_color = Color(1, 0.1, 0.1, 1)
	st.set_material(mat)
	var verts: PackedVector3Array = []
	if navmesh.has_method("get_vertices"):
		verts = navmesh.get_vertices()
	var poly_count := 0
	if navmesh.has_method("get_polygon_count"):
		poly_count = navmesh.get_polygon_count()
	for i in poly_count:
		var poly: PackedInt32Array = navmesh.get_polygon(i) if navmesh.has_method("get_polygon") else PackedInt32Array()
		if poly.size() < 2:
			continue
		for j in poly.size():
			var a_idx = poly[j]
			var b_idx = poly[(j + 1) % poly.size()]
			if a_idx >= 0 and a_idx < verts.size() and b_idx >= 0 and b_idx < verts.size():
				st.add_vertex(verts[a_idx])
				st.add_vertex(verts[b_idx])
	var mesh := st.commit()
	if _debug_mesh_instance == null:
		_debug_mesh_instance = MeshInstance3D.new()
		_debug_mesh_instance.name = "NavDebugMesh"
		_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh_instance)
	_debug_mesh_instance.mesh = mesh

func _set_debug_visible(v: bool) -> void:
	_debug_visible = v
	if _debug_mesh_instance:
		_debug_mesh_instance.visible = v
