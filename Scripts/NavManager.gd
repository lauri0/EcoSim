@tool
extends Node3D
class_name NavManager

@export var agent_radius: float = 0.25
@export var agent_height: float = 0.6

# Optional raised navigation layer for flying animals (e.g., birds)
@export var bird_region_enabled: bool = true
@export var bird_region_height: float = 8.0

# Optional underwater navigation layer for fish
@export var fish_region_enabled: bool = true
@export var fish_depth_offset: float = 1.0         # 1 unit below water level
@export var fish_required_depth: float = 1.5       # only where terrain is at least this far below water level
@export var fish_grid_resolution: int = 64         # sampling grid resolution for fish plane

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
var fish_region: NavigationRegion3D
var _debug_mesh_instance: MeshInstance3D
var _debug_visible: bool = false
var _current_debug_nav: String = "mammal"

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

	# Create optional underwater fish region
	if fish_region_enabled:
		fish_region = NavigationRegion3D.new()
		fish_region.name = "FishNavRegion"
		# Use a separate navigation layer so only fish use this region (bit 3 => value 4)
		fish_region.navigation_layers = 4
		add_child(fish_region)

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
	var mammal_polys := 0
	if navmesh and navmesh.has_method("get_polygon_count"):
		mammal_polys = navmesh.get_polygon_count()
	print("NavManager: Mammal navmesh rebaked (polygons: ", mammal_polys, ")")

	# Assign the same mesh to the bird region but offset in Y
	if bird_region_enabled:
		if bird_region == null:
			bird_region = NavigationRegion3D.new()
			bird_region.name = "BirdNavRegion"
			add_child(bird_region)
			bird_region.navigation_layers = 2
		bird_region.navigation_mesh = navmesh
		bird_region.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, bird_region_height, 0.0))

	# Build dedicated flat fish mesh at water_level - fish_depth_offset over sufficiently deep terrain
	if fish_region_enabled:
		if fish_region == null:
			fish_region = NavigationRegion3D.new()
			fish_region.name = "FishNavRegion"
			add_child(fish_region)
			fish_region.navigation_layers = 4
		var fish_nav := _build_fish_navmesh(terrain)
		fish_region.navigation_mesh = fish_nav
		fish_region.global_transform = Transform3D.IDENTITY
		var fish_polys := 0
		if fish_nav and fish_nav.has_method("get_polygon_count"):
			fish_polys = fish_nav.get_polygon_count()
		print("NavManager: Fish navmesh rebaked (polygons: ", fish_polys, ")")
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

func _build_fish_navmesh(terrain: Node3D) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	# Match parameters to main mesh for consistency
	navmesh.agent_radius = agent_radius
	navmesh.cell_size = cell_size
	navmesh.cell_height = cell_height
	navmesh.detail_sample_distance = detail_sample_distance
	navmesh.detail_sample_max_error = detail_sample_max_error
	navmesh.edge_max_error = edge_max_error
	navmesh.edge_max_length = edge_max_length
	navmesh.region_min_size = region_min_size
	navmesh.region_merge_size = region_merge_size
	navmesh.agent_max_climb = agent_max_climb
	navmesh.agent_max_slope = agent_max_slope

	# Build a flat grid mesh at y = water_level - fish_depth_offset
	var wl := _get_water_level()
	var target_y := wl - fish_depth_offset

	# Determine terrain size extents
	var size: float = 128.0
	if terrain and terrain.has_method("get_size"):
		size = terrain.get_size()
	var half := size * 0.5

	var res: int = max(8, fish_grid_resolution)
	var step: float = size / float(res)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Simple unshaded material for debug if needed
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.6)
	st.set_material(mat)

	var deep_enough := func(x: float, z: float) -> bool:
		var th: float = target_y
		if terrain and terrain.has_method("get_height"):
			th = terrain.get_height(x, z)
		return th <= (wl - fish_required_depth)

	# Add quads as two triangles if sufficiently deep (center or all 4 corners)
	var accepted_quads: int = 0
	for iz in range(res):
		var z0 := -half + iz * step
		var z1 := z0 + step
		for ix in range(res):
			var x0 := -half + ix * step
			var x1 := x0 + step
			var ok00: bool = deep_enough.call(x0, z0)
			var ok10: bool = deep_enough.call(x1, z0)
			var ok11: bool = deep_enough.call(x1, z1)
			var ok01: bool = deep_enough.call(x0, z1)
			# Center sample as a relaxed criterion
			var okC: bool = deep_enough.call((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			if (ok00 and ok10 and ok11 and ok01) or okC:
				accepted_quads += 1
				# tri 1: (x0,z0) (x1,z0) (x1,z1)
				st.add_vertex(Vector3(x0, target_y, z0))
				st.add_vertex(Vector3(x1, target_y, z0))
				st.add_vertex(Vector3(x1, target_y, z1))
				# tri 2: (x0,z0) (x1,z1) (x0,z1)
				st.add_vertex(Vector3(x0, target_y, z0))
				st.add_vertex(Vector3(x1, target_y, z1))
				st.add_vertex(Vector3(x0, target_y, z1))

	var mesh := st.commit()

	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_mesh(mesh, Transform3D.IDENTITY)
	# For synthetic meshes we add ourselves, skip scene parsing and bake directly
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	# Debug: report accepted tiles to help diagnose empty mesh
	print("NavManager: Fish mesh tiles accepted: ", accepted_quads)
	return navmesh

func _get_water_level() -> float:
	var root = get_tree().current_scene
	if root:
		var side = root.find_child("SidePanel", true, false)
		if side and side.has_method("get"):
			var v = side.get("water_level")
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				return float(v)
	return 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# N toggles mammal navmesh, M toggles fish navmesh
		if (event.keycode == KEY_N):
			_toggle_debug_for("mammal")
		elif (event.keycode == KEY_M):
			_toggle_debug_for("fish")

func _toggle_debug_for(which: String) -> void:
	if _debug_visible and _current_debug_nav == which:
		_set_debug_visible(false)
		return
	_current_debug_nav = which
	_build_debug_mesh()
	_set_debug_visible(true)

func _build_debug_mesh() -> void:
	var navmesh: NavigationMesh = null
	if _current_debug_nav == "mammal":
		if region and region.navigation_mesh:
			navmesh = region.navigation_mesh
		else:
			return
	elif _current_debug_nav == "fish":
		if fish_region and fish_region.navigation_mesh:
			navmesh = fish_region.navigation_mesh
		else:
			return
	else:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	# Red unshaded material
	var mat := StandardMaterial3D.new()
	#mat.unshaded = true
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
