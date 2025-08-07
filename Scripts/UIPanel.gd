# MenuBar.gd
extends Panel

@onready var exit_button = $MenuBar/ExitButton
@onready var trees_button = $MenuBar/CategoryBar/TreesButton
@onready var trees_popup  = $TreesPopup
# Optional label to show selected species - add a Label node as child of MenuBar named "SelectedLabel"
@onready var selected_label: Label = $MenuBar/SelectedLabel if has_node("MenuBar/SelectedLabel") else null
# Date label to show current time
@onready var date_label: Label = $MenuBar/DateLabel if has_node("MenuBar/DateLabel") else null
# Speed label to show current speed
@onready var speed_label: Label = $MenuBar/SpeedLabel if has_node("MenuBar/SpeedLabel") else null

# Speed control buttons
@onready var speed_0x_button: Button = get_node("MenuBar/0XButton") if has_node("MenuBar/0XButton") else null
@onready var speed_1x_button: Button = get_node("MenuBar/1XButton") if has_node("MenuBar/1XButton") else null
@onready var speed_2x_button: Button = get_node("MenuBar/2XButton") if has_node("MenuBar/2XButton") else null
@onready var speed_5x_button: Button = get_node("MenuBar/5XButton") if has_node("MenuBar/5XButton") else null
@onready var speed_10x_button: Button = get_node("MenuBar/10XButton") if has_node("MenuBar/10XButton") else null

# Tree inspection popup - will be created dynamically
var tree_info_popup: PopupPanel
var tree_info_label: RichTextLabel
var currently_inspected_tree: TreeBase
var popup_update_timer: Timer

# Tree species selection popup
var species_selection_popup: PopupPanel
var species_selection_vbox: VBoxContainer
var species_info_label: RichTextLabel
var species_spawn_button: Button
var currently_selected_species: String = ""

# A hard‐coded list, or you could load these from your scenes folder
var species_list = ["Alder","Aspen","Birch","Linden","Maple","Oak","Pine","Rowan","Spruce","Willow"]

# Tree spawning state
var selected_tree_species: String = ""
var is_tree_spawn_mode: bool = false

# Speed control state
var current_time_scale: float = 1.0

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
	
	# 7) Create species selection popup (deferred to avoid busy parent)
	_create_species_selection_popup.call_deferred()
	
	# 8) Connect speed control buttons
	_connect_speed_buttons()

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
	# Show the species info popup for the selected species
	# Don't close the original popup - let it stay open
	_show_species_info_popup(chosen)



func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if mouse is over UI elements before processing terrain clicks
		if _is_mouse_over_ui(event.position):
			return  # Don't process terrain clicks when over UI
			
		if is_tree_spawn_mode and selected_tree_species != "":
			# Tree spawning mode
			_spawn_tree_at_mouse_position(event.position)
			# Don't exit spawn mode - allow multiple spawning
		elif not is_tree_spawn_mode:
			# Tree inspection mode
			_try_inspect_tree_at_mouse_position(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Check if mouse is over UI elements before processing terrain clicks
		if _is_mouse_over_ui(event.position):
			return  # Don't process terrain clicks when over UI
			
		if is_tree_spawn_mode:
			# Right click cancels spawn mode
			_cancel_tree_spawn_mode()
		else:
			# Hide tree info popup if visible
			if tree_info_popup and tree_info_popup.visible:
				tree_info_popup.hide()
				_on_popup_hide()  # Manually call to stop timer
		
		# Hide both popups if visible
		if trees_popup and trees_popup.visible:
			trees_popup.hide()
		if species_selection_popup and species_selection_popup.visible:
			species_selection_popup.hide()

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
		
		# Apply random rotation along the trunk axis (Y-axis)
		var random_y_rotation = randf() * TAU  # Random rotation between 0 and 2π
		tree_instance.rotation.y = random_y_rotation
		
		print("Spawned ", species, " tree at position: ", spawn_position, " with rotation: ", rad_to_deg(random_y_rotation), "°")
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

func _create_species_selection_popup():
	# Create popup panel for species info
	species_selection_popup = PopupPanel.new()
	species_selection_popup.size = Vector2(400, 350)
	species_selection_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	
	# Create main container
	species_selection_vbox = VBoxContainer.new()
	species_selection_vbox.size = Vector2(380, 330)
	species_selection_vbox.position = Vector2(10, 10)
	species_selection_popup.add_child(species_selection_vbox)
	
	# Create title label
	var title_label = Label.new()
	title_label.text = "Tree Species Information"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	species_selection_vbox.add_child(title_label)
	
	# Create info label
	var info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(360, 250)
	species_selection_vbox.add_child(info_label)
	
	# Store reference to info label
	species_info_label = info_label
	
	# Create spawn button
	var spawn_button = Button.new()
	spawn_button.text = "Spawn This Species"
	spawn_button.custom_minimum_size = Vector2(200, 40)
	spawn_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	species_selection_vbox.add_child(spawn_button)
	
	# Store reference to spawn button
	species_spawn_button = spawn_button
	
	# Add popup to the scene tree
	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(species_selection_popup)
	else:
		get_tree().current_scene.add_child(species_selection_popup)

func _format_species_info_detailed(species_name: String) -> String:
	# Create a template tree to get species properties
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene = load(tree_scene_path)
	
	if not tree_scene:
		return "[b]%s[/b]\n\n[color=red]Error: Could not load tree data[/color]" % species_name
	
	var tree_instance = tree_scene.instantiate()
	if not tree_instance or not tree_instance is TreeBase:
		tree_instance.queue_free()
		return "[b]%s[/b]\n\n[color=red]Error: Invalid tree data[/color]" % species_name
	
	var tree = tree_instance as TreeBase
	
	# Get detailed species information
	var info = "[b]%s[/b]\n\n" % species_name
	
	# Altitude preferences
	info += "[b]Altitude Preferences:[/b]\n"
	info += "• Ideal: %.1f m\n" % tree.ideal_altitude
	info += "• Range: %.1f - %.1f m\n\n" % [tree.min_viable_altitude, tree.max_viable_altitude]
	
	# Growth information
	info += "[b]Growth:[/b]\n"
	info += "• Maturity Time: %.1f years\n" % (tree.max_growth_progress / 60.0)  # Convert seconds to years
	info += "• Max Age: %.1f years\n" % (tree.max_age / 60.0)
	info += "• Seed Production: Every %.1f years\n\n" % (tree.ideal_seed_gen_interval / 60.0)
	
	# Seed information
	info += "[b]Seeds:[/b]\n"
	info += "• Germination Chance: %.1f%%\n\n" % (tree.seed_germ_chance * 100.0)
	
	# Clean up the temporary instance
	tree_instance.queue_free()
	
	return info

func _format_species_info_compact(species_name: String) -> String:
	# Create a template tree to get species properties
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene = load(tree_scene_path)
	
	if not tree_scene:
		return "[b]%s[/b]\n[color=red]Error: Could not load tree data[/color]" % species_name
	
	var tree_instance = tree_scene.instantiate()
	if not tree_instance or not tree_instance is TreeBase:
		tree_instance.queue_free()
		return "[b]%s[/b]\n[color=red]Error: Invalid tree data[/color]" % species_name
	
	var tree = tree_instance as TreeBase
	
	# Get compact species information
	var info = "[b]%s[/b]\n" % species_name
	info += "Ideal: %.1fm | Growth: %.1fy | Seeds: %s" % [
		tree.ideal_altitude,
		tree.max_growth_progress / 60.0,
		tree.seed_type
	]
	
	# Clean up the temporary instance
	tree_instance.queue_free()
	
	return info

func _show_species_info_popup(species_name: String):
	currently_selected_species = species_name
	
	if species_selection_popup and species_info_label and species_spawn_button:
		# Format detailed species information
		var info_text = _format_species_info_detailed(species_name)
		species_info_label.text = info_text
		
		# Connect spawn button to the selected species
		# Disconnect any existing connections first
		if species_spawn_button.pressed.is_connected(_on_spawn_button_pressed):
			species_spawn_button.pressed.disconnect(_on_spawn_button_pressed)
		
		# Connect to the new species
		species_spawn_button.pressed.connect(_on_spawn_button_pressed.bind(species_name))
		
		# Position popup next to the trees popup menu
		var trees_popup_rect = trees_popup.get_visible_rect()
		var popup_pos = Vector2(trees_popup_rect.position.x + trees_popup_rect.size.x + 10, trees_popup_rect.position.y)
		
		# Keep popup on screen
		var screen_size = get_viewport().get_visible_rect().size
		if popup_pos.x + species_selection_popup.size.x > screen_size.x:
			# If it doesn't fit to the right, put it to the left of the trees popup
			popup_pos.x = trees_popup_rect.position.x - species_selection_popup.size.x - 10
		if popup_pos.y + species_selection_popup.size.y > screen_size.y:
			# If it doesn't fit vertically, adjust the Y position
			popup_pos.y = screen_size.y - species_selection_popup.size.y - 10
		
		species_selection_popup.position = popup_pos
		species_selection_popup.popup()

func _on_spawn_button_pressed(species_name: String):
	selected_tree_species = species_name
	is_tree_spawn_mode = true
	_update_selected_display()
	
	# Hide the species info popup
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	
	# Hide the original trees popup menu
	if trees_popup and trees_popup.visible:
		trees_popup.hide()
	
	print("Selected tree species: ", species_name, " - Click on terrain to spawn, right click to cancel")

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

# Speed control functions
func _connect_speed_buttons():
	# Connect all speed control buttons
	if speed_0x_button:
		speed_0x_button.pressed.connect(_on_speed_0x_pressed)
	if speed_1x_button:
		speed_1x_button.pressed.connect(_on_speed_1x_pressed)
	if speed_2x_button:
		speed_2x_button.pressed.connect(_on_speed_2x_pressed)
	if speed_5x_button:
		speed_5x_button.pressed.connect(_on_speed_5x_pressed)
	if speed_10x_button:
		speed_10x_button.pressed.connect(_on_speed_10x_pressed)
	
	# Set initial visual state (1x should be pressed by default)
	_update_speed_button_states(1.0)
	_update_speed_label(1.0)

func _on_speed_0x_pressed():
	_set_time_scale(0.0)

func _on_speed_1x_pressed():
	_set_time_scale(1.0)

func _on_speed_2x_pressed():
	_set_time_scale(2.0)

func _on_speed_5x_pressed():
	_set_time_scale(5.0)

func _on_speed_10x_pressed():
	_set_time_scale(10.0)

func _set_time_scale(time_scale: float):
	current_time_scale = time_scale
	Engine.time_scale = time_scale
	_update_speed_button_states(time_scale)
	_update_speed_label(time_scale)
	
	if time_scale == 0.0:
		print("Game paused")
	else:
		print("Time scale set to ", time_scale, "x")

func _update_speed_button_states(current_scale: float):
	# Update button pressed states to show current speed
	if speed_0x_button:
		speed_0x_button.button_pressed = (current_scale == 0.0)
	if speed_1x_button:
		speed_1x_button.button_pressed = (current_scale == 1.0)
	if speed_2x_button:
		speed_2x_button.button_pressed = (current_scale == 2.0)
	if speed_5x_button:
		speed_5x_button.button_pressed = (current_scale == 5.0)
	if speed_10x_button:
		speed_10x_button.button_pressed = (current_scale == 10.0)

func _update_speed_label(current_scale: float):
	# Update speed label to show current speed
	if speed_label:
		if current_scale == 0.0:
			speed_label.text = "Speed: PAUSED"
		else:
			# Format the speed nicely (remove .0 for whole numbers)
			var speed_text = str(current_scale)
			if current_scale == int(current_scale):
				speed_text = str(int(current_scale))
			speed_label.text = "Speed: " + speed_text + "X"

# UI detection function
func _is_mouse_over_ui(mouse_position: Vector2) -> bool:
	# Check if mouse is over this panel (MenuBar area)
	var panel_rect = get_global_rect()
	if panel_rect.has_point(mouse_position):
		return true
	
	# Check if any popup menus are visible and mouse is over them
	if trees_popup and trees_popup.visible:
		var popup_rect = trees_popup.get_visible_rect()
		if popup_rect.has_point(mouse_position):
			return true
	
	# Check if tree info popup is visible and mouse is over it
	if tree_info_popup and tree_info_popup.visible:
		##var info_popup_rect = Rect2(tree_info_popup.global_position, tree_info_popup.size)
		var info_popup_rect = tree_info_popup.get_visible_rect()
		if info_popup_rect.has_point(mouse_position):
			return true
	
	# Check if species selection popup is visible and mouse is over it
	if species_selection_popup and species_selection_popup.visible:
		var species_popup_rect = species_selection_popup.get_visible_rect()
		if species_popup_rect.has_point(mouse_position):
			return true
	
	return false
