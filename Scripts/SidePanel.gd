extends Panel

@onready var trees_button: Button = $SideMenuBar/TypeSelectBar/TreesButton
# Optional label to show selected species (lives under BottomPanel)
@onready var selected_label: Label = (
	get_node("../BottomPanel/BottomMenuBar/SelectedLabel") as Label
) if has_node("../BottomPanel/BottomMenuBar/SelectedLabel") else null

# Tree inspection popup - created dynamically
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

# Cached per-species info to avoid instantiating scenes on every open
var species_info_cache: Dictionary = {}
var species_cache_warmed: bool = false

# A hard‐coded list, or you could load these from your scenes folder
var species_list = ["Alder","Aspen","Birch","Linden","Maple","Oak","Pine","Rowan","Spruce","Willow"]

# Tree spawning state
var selected_tree_species: String = ""
var is_tree_spawn_mode: bool = false

# References to world objects (set from world scene)
var camera: Camera3D
var terrain: MeshInstance3D

# Water level configuration
@export var water_level: float = 0.0

func _ready():
	# Connect UI
	trees_button.pressed.connect(_on_trees_button_pressed)

	# World references and UI setup
	_find_world_references()
	_update_selected_display()
	_create_tree_info_popup.call_deferred()
	_create_species_selection_popup.call_deferred()
	# Warm the species info cache in the background to make browser instant
	_warm_species_cache.call_deferred()

func _warm_species_cache():
	for species_name in species_list:
		if not species_info_cache.has(species_name):
			species_info_cache[species_name] = _load_species_info(species_name)
	species_cache_warmed = true

func _load_species_info(species_name: String) -> Dictionary:
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene: PackedScene = load(tree_scene_path)
	if not tree_scene:
		return {"name": species_name, "ideal": 0.0, "maturity_years": 0.0, "seed_type": "?"}
	var tree_instance = tree_scene.instantiate()
	if not tree_instance or not tree_instance is TreeBase:
		if tree_instance:
			tree_instance.queue_free()
		return {"name": species_name, "ideal": 0.0, "maturity_years": 0.0, "seed_type": "?"}
	var tree = tree_instance as TreeBase
	var info := {
		"name": species_name,
		"ideal": tree.ideal_altitude,
		"maturity_years": tree.max_growth_progress / 60.0,
		"seed_type": tree.seed_type
	}
	tree_instance.queue_free()
	return info

func _find_world_references():
	var root = get_tree().current_scene
	camera = root.find_child("Camera3D", true, false) as Camera3D
	terrain = root.find_child("Terrain", true, false) as MeshInstance3D
	if not camera:
		print("Warning: Camera3D not found in scene!")
	if not terrain:
		print("Warning: Terrain not found in scene!")

func _on_trees_button_pressed() -> void:
	_show_species_browser()

## Deprecated: selection through PopupMenu removed

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_mouse_over_ui(event.position):
			return
		if is_tree_spawn_mode and selected_tree_species != "":
			_spawn_tree_at_mouse_position(event.position)
		else:
			_try_inspect_tree_at_mouse_position(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_mouse_over_ui(event.position):
			return
		if is_tree_spawn_mode:
			_cancel_tree_spawn_mode()
		else:
			if tree_info_popup and tree_info_popup.visible:
				tree_info_popup.hide()
				_on_popup_hide()
		# no trees_popup anymore
		if species_selection_popup and species_selection_popup.visible:
			species_selection_popup.hide()

func _spawn_tree_at_mouse_position(mouse_pos: Vector2) -> void:
	if not camera or not terrain:
		print("Camera or terrain reference not set!")
		return
	var from = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	if ray_dir.y >= 0:
		print("Ray pointing upward, can't hit terrain")
		return
	var intersection_point = _find_terrain_intersection(from, ray_dir)
	if intersection_point == Vector3.INF:
		print("No terrain intersection found")
		return
	if intersection_point.y <= water_level:
		print("Cannot spawn tree underwater! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
		return
	_spawn_tree(selected_tree_species, intersection_point)

func _find_terrain_intersection(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var terrain_size = 256.0
	var max_distance = 1000.0
	var step_size = 1.0
	var current_distance = 0.0
	while current_distance < max_distance:
		var current_point = ray_origin + ray_direction * current_distance
		if abs(current_point.x) > terrain_size/2 or abs(current_point.z) > terrain_size/2:
			current_distance += step_size
			continue
		var terrain_height = terrain.get_height(current_point.x, current_point.z)
		if current_point.y <= terrain_height:
			return _refine_terrain_intersection(ray_origin, ray_direction, current_distance - step_size, current_distance)
		current_distance += step_size
	return Vector3.INF

func _refine_terrain_intersection(ray_origin: Vector3, ray_direction: Vector3, distance_min: float, distance_max: float) -> Vector3:
	var iterations = 10
	for i in iterations:
		var mid_distance = (distance_min + distance_max) * 0.5
		var mid_point = ray_origin + ray_direction * mid_distance
		var terrain_height = terrain.get_height(mid_point.x, mid_point.z)
		if mid_point.y > terrain_height:
			distance_min = mid_distance
		else:
			distance_max = mid_distance
	var final_distance = (distance_min + distance_max) * 0.5
	var intersection_point = ray_origin + ray_direction * final_distance
	intersection_point.y = terrain.get_height(intersection_point.x, intersection_point.z)
	return intersection_point

func _spawn_tree(species: String, spawn_position: Vector3) -> void:
	var tree_scene_path = "res://Scenes/Trees/" + species + ".tscn"
	var tree_scene = load(tree_scene_path)
	if tree_scene:
		var tree_instance = tree_scene.instantiate()
		terrain.get_parent().add_child(tree_instance)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		tree_instance.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		tree_instance.rotation.y = random_y_rotation
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
	tree_info_popup = PopupPanel.new()
	tree_info_popup.size = Vector2(350, 220)
	tree_info_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	tree_info_label = RichTextLabel.new()
	tree_info_label.fit_content = true
	tree_info_label.bbcode_enabled = true
	tree_info_label.size = Vector2(330, 200)
	tree_info_label.position = Vector2(10, 10)
	tree_info_popup.add_child(tree_info_label)
	popup_update_timer = Timer.new()
	popup_update_timer.wait_time = 0.1
	popup_update_timer.timeout.connect(_update_popup_info)
	tree_info_popup.add_child(popup_update_timer)
	tree_info_popup.popup_hide.connect(_on_popup_hide)
	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(tree_info_popup)
	else:
		get_tree().current_scene.add_child(tree_info_popup)

func _create_species_selection_popup():
	# Create the unified browser popup
	species_selection_popup = PopupPanel.new()
	species_selection_popup.size = Vector2(560, 740)
	species_selection_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)

	# Root container inside popup
	var root_vbox = VBoxContainer.new()
	root_vbox.size = Vector2(540, 720)
	root_vbox.position = Vector2(10, 10)
	species_selection_popup.add_child(root_vbox)

	# Title
	var title_label = Label.new()
	title_label.text = "Trees"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title_label)

	# Scroll list of species entries
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	# Store for later rebuild
	species_selection_vbox = list_vbox

	# Add to scene
	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(species_selection_popup)
	else:
		get_tree().current_scene.add_child(species_selection_popup)

	# Initial build
	_rebuild_species_browser_entries()

## Detailed formatter kept for future but not used by browser

func _format_species_info_compact(species_name: String) -> String:
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene = load(tree_scene_path)
	if not tree_scene:
		return "[b]%s[/b]\n[color=red]Error: Could not load tree data[/color]" % species_name
	var tree_instance = tree_scene.instantiate()
	if not tree_instance or not tree_instance is TreeBase:
		tree_instance.queue_free()
		return "[b]%s[/b]\n[color=red]Error: Invalid tree data[/color]" % species_name
	var tree = tree_instance as TreeBase
	var info = "[b]%s[/b]\n" % species_name
	info += "Ideal: %.1fm | Growth: %.1fy | Seeds: %s" % [
		tree.ideal_altitude,
		tree.max_growth_progress / 60.0,
		tree.seed_type
	]
	tree_instance.queue_free()
	return info

func _show_species_browser():
	if not species_selection_popup:
		return
	# Entries are static per session; avoid rebuilding on every open for snappier UI
	# Position near the Trees button
	var btn_rect = trees_button.get_global_rect()
	var popup_pos = Vector2(btn_rect.position.x + btn_rect.size.x + 8, btn_rect.position.y)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + species_selection_popup.size.x > screen_size.x:
		popup_pos.x = max(0.0, btn_rect.position.x - species_selection_popup.size.x - 8)
	species_selection_popup.position = popup_pos
	species_selection_popup.popup()

func _rebuild_species_browser_entries():
	if not species_selection_vbox:
		return
	# Clear existing rows
	for child in species_selection_vbox.get_children():
		species_selection_vbox.remove_child(child)
		child.queue_free()
	# Build rows with compact info and Spawn button
	for species_name in species_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(520, 54)
		row.add_theme_constant_override("separation", 12)

		var texts_box = VBoxContainer.new()
		texts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_label = Label.new()
		name_label.text = species_name
		name_label.add_theme_font_size_override("font_size", 16)
		texts_box.add_child(name_label)

		var info_label = Label.new()
		info_label.text = _compact_info_text(species_name)
		info_label.add_theme_font_size_override("font_size", 12)
		info_label.modulate = Color(0.9, 0.9, 0.9)
		texts_box.add_child(info_label)

		row.add_child(texts_box)

		var spawn_button = Button.new()
		spawn_button.text = "Spawn"
		spawn_button.custom_minimum_size = Vector2(90, 32)
		spawn_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spawn_button.pressed.connect(_on_spawn_button_pressed.bind(species_name))
		row.add_child(spawn_button)

		species_selection_vbox.add_child(row)

		# Separator between entries
		var sep = HSeparator.new()
		sep.modulate = Color(1,1,1,0.25)
		species_selection_vbox.add_child(sep)

func _compact_info_text(species_name: String) -> String:
	if not species_info_cache.has(species_name):
		# Load on-demand if cache not ready
		species_info_cache[species_name] = _load_species_info(species_name)
	var info: Dictionary = species_info_cache[species_name]
	var ideal: float = info.get("ideal", 0.0)
	var maturity_years: float = info.get("maturity_years", 0.0)
	var seed_type: String = info.get("seed_type", "?")
	# Format compact line
	var maturity_text := _format_years(maturity_years)
	return "Ideal: %.0fm  |  Maturity: %s  |  Seeds: %s" % [ideal, maturity_text, seed_type]

func _format_years(years: float) -> String:
	# Show without trailing .0 for whole numbers
	if years == int(years):
		return str(int(years)) + "y"
	return "%.1fy" % years

func _on_spawn_button_pressed(species_name: String):
	selected_tree_species = species_name
	is_tree_spawn_mode = true
	_update_selected_display()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	print("Selected tree species: ", species_name, " - Click on terrain to spawn, right click to cancel")

func _try_inspect_tree_at_mouse_position(mouse_pos: Vector2):
	if not camera:
		return
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	if result and result.collider:
		var clicked_node = result.collider
		var tree_base = _find_tree_base_in_hierarchy(clicked_node)
		if tree_base:
			_show_tree_info(tree_base, mouse_pos)

func _find_tree_base_in_hierarchy(node: Node) -> TreeBase:
	if node is TreeBase:
		return node as TreeBase
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
	if not tree_info_popup.is_inside_tree():
		print("Tree info popup not in scene tree")
		return
	currently_inspected_tree = tree
	var popup_pos = mouse_pos + Vector2(20, -tree_info_popup.size.y - 20)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + tree_info_popup.size.x > screen_size.x:
		popup_pos.x = screen_size.x - tree_info_popup.size.x - 10
	if popup_pos.y < 0:
		popup_pos.y = mouse_pos.y + 20
	var info_text = _format_tree_info(tree)
	tree_info_label.text = info_text
	tree_info_popup.position = popup_pos
	tree_info_popup.popup()
	if popup_update_timer:
		popup_update_timer.start()

func _format_tree_info(tree: TreeBase) -> String:
	var age_text = "%.1f / %.1f years" % [tree.current_age, tree.max_age]
	var health_text = "%.1f%%" % (tree.healthPercentage * 100.0)
	var growth_progress_text = "%.1f%%" % (tree.growth_progress / tree.max_growth_progress * 100.0)
	var actual_altitude = tree.global_position.y
	var min_altitude = tree.min_viable_altitude
	var ideal_altitude = tree.ideal_altitude
	var max_altitude = tree.max_viable_altitude
	var altitude_color: String
	if actual_altitude < min_altitude or actual_altitude > max_altitude:
		altitude_color = "[color=red]"
	elif abs(actual_altitude - ideal_altitude) <= abs(actual_altitude - min_altitude) and abs(actual_altitude - ideal_altitude) <= abs(actual_altitude - max_altitude):
		altitude_color = "[color=green]"
	else:
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
	if currently_inspected_tree and tree_info_label and tree_info_popup and tree_info_popup.visible:
		var info_text = _format_tree_info(currently_inspected_tree)
		tree_info_label.text = info_text

func _on_popup_hide():
	currently_inspected_tree = null
	if popup_update_timer:
		popup_update_timer.stop()

func _is_mouse_over_ui(mouse_position: Vector2) -> bool:
	# Check if mouse is over this side panel
	var panel_rect = get_global_rect()
	if panel_rect.has_point(mouse_position):
		return true
	# Check popups
	# no trees_popup anymore
	if tree_info_popup and tree_info_popup.visible:
		var info_popup_rect = tree_info_popup.get_visible_rect()
		if info_popup_rect.has_point(mouse_position):
			return true
	if species_selection_popup and species_selection_popup.visible:
		var species_popup_rect = species_selection_popup.get_visible_rect()
		if species_popup_rect.has_point(mouse_position):
			return true
	return false
