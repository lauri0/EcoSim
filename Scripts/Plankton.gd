extends "res://Scripts/UnderwaterPlant.gd"
class_name Plankton

@export var circle_radius: float = 0.2
@export var circle_color: Color = Color(0.45, 0.3, 0.15, 1.0) # brown

func _init():
	# Initialize inherited properties
	species_name = "Plankton"
	price = 1
	max_age = 4.0
	blocking_radius = 3.0
	needs_free_radius = 3.0
	repro_radius = 25.0
	required_depth_below_surface = 1.5

func _ready():
	_create_visual()
	super._ready()
	_ensure_pick_body()

func _create_visual() -> void:
	var model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var mi = MeshInstance3D.new()
	mi.name = "MeshInstance3D"
	mi.mesh = _build_disc_mesh(circle_radius)
	var m := StandardMaterial3D.new()
	m.albedo_color = circle_color
	m.vertex_color_use_as_albedo = false
	mi.material_override = m
	# 1 unit below water surface; y-offset handled by spawn logic, but keep slight lift to avoid z-fighting
	mi.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0))
	model.add_child(mi)

func _build_disc_mesh(r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 20
	for i in segs:
		var a0 = (i * TAU) / float(segs)
		var a1 = ((i + 1) * TAU) / float(segs)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * r, 0.0, sin(a0) * r))
		st.add_vertex(Vector3(cos(a1) * r, 0.0, sin(a1) * r))
	return st.commit()

func _ensure_pick_body() -> void:
	var body := find_child("StaticBody3D", true, false) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "StaticBody3D"
		add_child(body)
	var shape := body.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		body.add_child(shape)
	var cs := CylinderShape3D.new()
	cs.radius = circle_radius
	cs.height = 0.05
	shape.shape = cs
	# Set to layer 4 (inspection), colliding with nothing
	body.set_collision_layer_value(1, false)
	body.set_collision_layer_value(3, false)
	body.set_collision_layer_value(4, true)
	body.collision_mask = 0
