# MenuBar.gd
extends Panel

@onready var exit_button = $MenuBar/ExitButton
@onready var trees_button = $MenuBar/CategoryBar/TreesButton
@onready var trees_popup  = $TreesPopup
# Optional label to show selected species - add a Label node as child of MenuBar named "SelectedLabel"
@onready var selected_label: Label = $MenuBar/SelectedLabel if has_node("MenuBar/SelectedLabel") else null
# Date label to show current time
@onready var date_label: Label = $MenuBar/DateLabel if has_node("MenuBar/DateLabel") else null

# Tree inspection popup - will be created dynamically
var tree_info_popup: PopupPanel
var tree_info_label: RichTextLabel
var currently_inspected_tree: TreeBase
var popup_update_timer: Timer

# A hard‐coded list, or you could load these from your scenes folder
var species_list = ["Alder","Aspen","Birch","Linden","Maple","Oak","Pine","Rowan","Spruce","Willow"]

# Tree spawning state
var selected_tree_species: String = ""
var is_tree_spawn_mode: bool = false

# References to world objects (set from world scene)
var camera: Camera3D
var terrain: MeshInstance3D

# Water level configuration  
@export var water_level: float = 0.0  # Y coordinate of water surface (now aligned with WaterPlane at 0m)

func _ready():
	exit_button.pressed.connect(_on_exit_pressed)
	# 1) Fill the PopupMenu
	trees_popup.clear()
	for i in species_list.size():
		trees_popup.add_item(species_list[i], i)

	# 2) When the button's pressed, popup the menu
	trees_button.pressed.connect(_on_trees_button_pressed)
	# 3) When the user picks one, handle it
	trees_popup.id_pressed.connect(_on_trees_popup_item)
	
	# 4) Find references to world objects
	_find_world_references()
	
	# 5) Initialize the selected display
	_update_selected_display()
	
	# 6) Create tree inspection popup (deferred to avoid busy parent)
	_create_tree_info_popup.call_deferred()

func _find_world_references():
	# Find camera and terrain in the scene tree
	var root = get_tree().current_scene
	camera = root.find_child("Camera3D", true, false) as Camera3D
	terrain = root.find_child("Terrain", true, false) as MeshInstance3D
	
	if not camera:
		print("Warning: Camera3D not found in scene!")
	if not terrain:
		print("Warning: Terrain not found in scene!")

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_trees_button_pressed() -> void:
	# 1) Make sure the PopupMenu is empty, then add your items
	trees_popup.clear()
	for i in species_list.size():
		trees_popup.add_item(species_list[i], i)

	# 2) Force it to recalc its size
	#    (you only need this if you read rect_size immediately after adding items)
	trees_popup.hide()
	trees_popup.show()  

	# 3) Grab the button’s global position + size
	var btn_rect = trees_button.get_global_rect()
	#    bottom-center of the popup = top-center of the button
	var popup_size = trees_popup.size
	var popup_pos = Vector2(
		btn_rect.position.x + btn_rect.size.x * 0.5 - popup_size.x * 0.5,
		btn_rect.position.y - popup_size.y
	)

	# 4) Show it at that spot
	trees_popup.popup(Rect2i(popup_pos, popup_size))


func _on_trees_popup_item(id: int):
	var chosen = species_list[id]
	selected_tree_species = chosen
	is_tree_spawn_mode = true
	_update_selected_display()
	print("Selected tree species: ", chosen, " - Click on terrain to spawn, right click to cancel")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_tree_spawn_mode and selected_tree_species != "":
			# Tree spawning mode
			_spawn_tree_at_mouse_position(event.position)
			# Don't exit spawn mode - allow multiple spawning
		elif not is_tree_spawn_mode:
			# Tree inspection mode
			_try_inspect_tree_at_mouse_position(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_tree_spawn_mode:
			# Right click cancels spawn mode
			_cancel_tree_spawn_mode()
		else:
			# Hide tree info popup if visible
			if tree_info_popup and tree_info_popup.visible:
				tree_info_popup.hide()
				_on_popup_hide()  # Manually call to stop timer

func _spawn_tree_at_mouse_position(mouse_pos: Vector2) -> void:
	if not camera or not terrain:
		print("Camera or terrain reference not set!")
		return
		
	# Project ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	if ray_dir.y >= 0:
		print("Ray pointing upward, can't hit terrain")
		return
		
	# Find intersection with actual terrain surface using iterative approach
	var intersection_point = _find_terrain_intersection(from, ray_dir)
	
	if intersection_point == Vector3.INF:
		print("No terrain intersection found")
		return
	
	# Check if spawn point is underwater
	if intersection_point.y <= water_level:
		print("Cannot spawn tree underwater! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
		return
		
	_spawn_tree(selected_tree_species, intersection_point)
	# Stay in spawn mode for multiple spawning

func _find_terrain_intersection(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var terrain_size = 256.0
	var max_distance = 1000.0
	var step_size = 1.0
	
	# March along the ray and check for terrain intersection
	var current_distance = 0.0
	
	while current_distance < max_distance:
		var current_point = ray_origin + ray_direction * current_distance
		
		# Check if we're within terrain bounds
		if abs(current_point.x) > terrain_size/2 or abs(current_point.z) > terrain_size/2:
			current_distance += step_size
			continue
			
		# Get terrain height at this XZ position
		var terrain_height = terrain.get_height(current_point.x, current_point.z)
		
		# Check if ray point is below terrain surface
		if current_point.y <= terrain_height:
			# We've intersected! Now refine the intersection point
			return _refine_terrain_intersection(ray_origin, ray_direction, current_distance - step_size, current_distance)
			
		current_distance += step_size
	
	return Vector3.INF  # No intersection found

func _refine_terrain_intersection(ray_origin: Vector3, ray_direction: Vector3, distance_min: float, distance_max: float) -> Vector3:
	# Binary search to find precise intersection point
	var iterations = 10
	
	for i in iterations:
		var mid_distance = (distance_min + distance_max) * 0.5
		var mid_point = ray_origin + ray_direction * mid_distance
		var terrain_height = terrain.get_height(mid_point.x, mid_point.z)
		
		if mid_point.y > terrain_height:
			distance_min = mid_distance
		else:
			distance_max = mid_distance
	
	# Final intersection point
	var final_distance = (distance_min + distance_max) * 0.5
	var intersection_point = ray_origin + ray_direction * final_distance
	
	# Snap to exact terrain height
	intersection_point.y = terrain.get_height(intersection_point.x, intersection_point.z)
	
	return intersection_point

func _spawn_tree(species: String, spawn_position: Vector3) -> void:
	var tree_scene_path = "res://Scenes/Trees/" + species + ".tscn"
	var tree_scene = load(tree_scene_path)
	
	if tree_scene:
		var tree_instance = tree_scene.instantiate()
		
		# Add to the world scene first (so it's in the scene tree)
		terrain.get_parent().add_child(tree_instance)
		
		# Get terrain height at the spawn position
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		
		# Now set the position (after it's in the scene tree)
		tree_instance.global_position = spawn_position
		
		print("Spawned ", species, " tree at position: ", spawn_position)
	else:
		print("Failed to load tree scene: ", tree_scene_path)

func _cancel_tree_spawn_mode():
	is_tree_spawn_mode = false
	selected_tree_species = ""
	_update_selected_display()
	print("Tree spawning cancelled")

func _update_selected_display():
	if selected_label:
		if selected_tree_species != "":
			selected_label.text = "Selected: " + selected_tree_species
		else:
			selected_label.text = ""

func _create_tree_info_popup():
	# Create popup panel
	tree_info_popup = PopupPanel.new()
	tree_info_popup.size = Vector2(350, 220)  # Made slightly larger for altitude info
	tree_info_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	
	# Create rich text label for formatted content
	tree_info_label = RichTextLabel.new()
	tree_info_label.fit_content = true
	tree_info_label.bbcode_enabled = true
	tree_info_label.size = Vector2(330, 200)
	tree_info_label.position = Vector2(10, 10)
	
	# Add label to popup
	tree_info_popup.add_child(tree_info_label)
	
	# Create update timer
	popup_update_timer = Timer.new()
	popup_update_timer.wait_time = 0.1  # Update 10 times per second
	popup_update_timer.timeout.connect(_update_popup_info)
	tree_info_popup.add_child(popup_update_timer)
	
	# Connect popup visibility changes
	tree_info_popup.popup_hide.connect(_on_popup_hide)
	
	# Add popup to the scene tree - find the UI root or use current scene
	var ui_root = get_parent()  # This should be UIRoot
	if ui_root:
		ui_root.add_child(tree_info_popup)
	else:
		# Fallback: add to current scene
		get_tree().current_scene.add_child(tree_info_popup)

func _try_inspect_tree_at_mouse_position(mouse_pos: Vector2):
	if not camera:
		return
	
	# Cast ray from camera to find what we clicked on
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		# Check if we clicked on a tree (TreeBase or its child)
		var clicked_node = result.collider
		var tree_base = _find_tree_base_in_hierarchy(clicked_node)
		
		if tree_base:
			_show_tree_info(tree_base, mouse_pos)

func _find_tree_base_in_hierarchy(node: Node) -> TreeBase:
	# Check current node
	if node is TreeBase:
		return node as TreeBase
	
	# Check parent nodes
	var current = node
	while current:
		if current is TreeBase:
			return current as TreeBase
		current = current.get_parent()
	
	return null

func _show_tree_info(tree: TreeBase, mouse_pos: Vector2):
	if not tree_info_popup or not tree_info_label:
		print("Tree info popup not properly initialized")
		return
	
	# Make sure popup is in the scene tree
	if not tree_info_popup.is_inside_tree():
		print("Tree info popup not in scene tree")
		return
	
	# Store reference to currently inspected tree
	currently_inspected_tree = tree
	
	# Calculate popup position (top-right of click)
	var popup_pos = mouse_pos + Vector2(20, -tree_info_popup.size.y - 20)
	
	# Keep popup on screen
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + tree_info_popup.size.x > screen_size.x:
		popup_pos.x = screen_size.x - tree_info_popup.size.x - 10
	if popup_pos.y < 0:
		popup_pos.y = mouse_pos.y + 20
	
	# Format tree information
	var info_text = _format_tree_info(tree)
	tree_info_label.text = info_text
	
	# Show popup at calculated position
	tree_info_popup.position = popup_pos
	tree_info_popup.popup()
	
	# Start updating the popup info
	if popup_update_timer:
		popup_update_timer.start()

func _format_tree_info(tree: TreeBase) -> String:
	var age_text = "%.1f / %.1f years" % [tree.current_age, tree.max_age]
	var health_text = "%.1f%%" % (tree.healthPercentage * 100.0)
	var growth_progress_text = "%.1f%%" % (tree.growth_progress / tree.max_growth_progress * 100.0)
	
	# Get altitude information
	var actual_altitude = tree.global_position.y
	var min_altitude = tree.min_viable_altitude
	var ideal_altitude = tree.ideal_altitude
	var max_altitude = tree.max_viable_altitude
	
	# Determine altitude color based on position within viable range
	var altitude_color: String
	if actual_altitude < min_altitude or actual_altitude > max_altitude:
		# Out of tolerable range - red
		altitude_color = "[color=red]"
	elif abs(actual_altitude - ideal_altitude) <= abs(actual_altitude - min_altitude) and abs(actual_altitude - ideal_altitude) <= abs(actual_altitude - max_altitude):
		# Closer to ideal than to min or max - green
		altitude_color = "[color=green]"
	else:
		# Closer to min or max than to ideal - yellow
		altitude_color = "[color=yellow]"
	
	var actual_altitude_text = "%s%.1f m[/color]" % [altitude_color, actual_altitude]
	var altitude_range_text = "%.1f/%.1f/%.1f m" % [min_altitude, ideal_altitude, max_altitude]
	
	var info = "[b]%s[/b]\n\n" % tree.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	info += "[b]Status:[/b] %s\n" % tree.get_state_name()
	info += "[b]Growth Progress:[/b] %s\n" % growth_progress_text
	info += "[b]Current Altitude:[/b] %s\n" % actual_altitude_text
	info += "[b]Altitude Range (Min/Ideal/Max):[/b] %s" % altitude_range_text
	
	return info

func _update_popup_info():
	# Update popup info if a tree is currently being inspected
	if currently_inspected_tree and tree_info_label and tree_info_popup and tree_info_popup.visible:
		var info_text = _format_tree_info(currently_inspected_tree)
		tree_info_label.text = info_text

func _on_popup_hide():
	# Stop updating when popup is hidden
	currently_inspected_tree = null
	if popup_update_timer:
		popup_update_timer.stop()

func _on_time_updated(year: int, season: String, hour: int):
	# Update the date label when time changes (called by TimeManager)
	if date_label:
		date_label.text = "%02d:00 %s Year %d" % [hour, season, year]
	else:
		print("Warning: DateLabel not found!")
