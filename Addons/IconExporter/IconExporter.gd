@tool
extends EditorScript

# Folder containing your per-species .tscn files
@export var source_folder: String = "res://Scenes/Trees"
# Folder where icon PNGs will be written (must already exist)
@export var output_folder: String = "res://Resources/Icons"
# Size of each icon
@export var icon_size: Vector2 = Vector2(256, 256)
# Camera transform for the icon render
@export var camera_position: Vector3        = Vector3(0, 2, 5)
@export var camera_rotation_degrees: Vector3 = Vector3(-30, 45, 0)

func _run():
	var dir = DirAccess.open(source_folder)
	if dir == null:
		printerr("Could not open source folder: ", source_folder)
		return

	# Create the offscreen SubViewport
	var viewport = SubViewport.new()
	viewport.size = icon_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Give it its own 3D world resource
	viewport.world_3d = World3D.new()

	# Now add your 3D nodes under the SubViewport, not under the World3D
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 0, 0)
	viewport.add_child(light)

	var cam = Camera3D.new()
	cam.position = camera_position
	cam.rotation_degrees = camera_rotation_degrees
	cam.current = true
	viewport.add_child(cam)

	var mesh_inst = MeshInstance3D.new()
	viewport.add_child(mesh_inst)

	# Iterate over .tscn files in source_folder
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".tscn"):
			var folder_path = source_folder
			if !source_folder.ends_with("/"):
				folder_path = source_folder + "/"
			var path = folder_path + file_name
			var packed: PackedScene = ResourceLoader.load(path)
			if packed:
				var inst = packed.instantiate()
				var mesh_node = inst.find_node("MeshInstance3D", true, false)
				if mesh_node and mesh_node is MeshInstance3D:
					mesh_inst.mesh = mesh_node.mesh
				else:
					printerr("⚠️ No MeshInstance3D found")
					file_name = dir.get_next()
					continue

				var img = viewport.get_texture().get_image()
				img.flip_y()
				var base = file_name.get_basename() + ".png"

				var out_folder = output_folder
				if !output_folder.ends_with("/"):
					out_folder = output_folder + "/"
				var out_path = out_folder + base

				img.save_png(out_path)
				print("Exported icon: ", out_path)
			else:
				printerr("Failed to load scene: ", path)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("All icons exported.")
