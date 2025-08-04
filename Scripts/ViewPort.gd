tool
extends Viewport

@export var tree_scene: PackedScene
@export var output_path: String    = "res://icons/"
@export var icon_size: Vector2     = Vector2(256, 256)

# cache your children
@onready var mesh_instance = $MeshInstance3D
@onready var cam           = $Camera3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	size = icon_size
	update()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or tree_scene == null:
		return

	# instance the scene and grab its mesh
	var inst = tree_scene.instantiate()
	# assumes your mesh is under Model/MeshInstance3D in the species scenes:
	var mesh = inst.get_node("Model/MeshInstance3D").mesh
	mesh_instance.mesh = mesh

	# give one frame to update the viewport texture
	call_deferred("_export_icon", tree_scene.resource_path)

func _export_icon(path: String) -> void:
	# grab the rendered image
	var img = get_texture().get_data()
	img.flip_y()
	# build output filename (e.g. res://icons/Birch.png)
	var name = path.get_file().get_basename() + ".png"
	img.save_png(output_path.plus_file(name))
	print("Exported icon: ", name)

	# clear so we don’t keep re-exporting
	tree_scene = null
