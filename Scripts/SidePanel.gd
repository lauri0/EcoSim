extends Panel

@onready var trees_button: Button = $SideMenuBar/TypeSelectBar/TreesButton
@onready var plants_button: Button = $SideMenuBar/TypeSelectBar/PlantsButton if has_node("SideMenuBar/TypeSelectBar/PlantsButton") else null
# Optional label to show selected species (lives under BottomPanel)
@onready var selected_label: Label = (
	get_node("../BottomPanel/BottomMenuBar/SelectedLabel") as Label
) if has_node("../BottomPanel/BottomMenuBar/SelectedLabel") else null

# Tree inspection popup - created dynamically
var tree_info_popup: PopupPanel
var tree_info_label: RichTextLabel
var currently_inspected_tree: TreeBase
var currently_inspected_plant: SmallPlant
var popup_update_timer: Timer

# Tree species selection popup
var species_selection_popup: PopupPanel
var species_selection_vbox: VBoxContainer
var species_info_label: RichTextLabel
var species_spawn_button: Button
var currently_selected_species: String = ""

# Plants species selection popup
var plants_selection_popup: PopupPanel
var plants_selection_vbox: VBoxContainer
 
 # Cached per-species info to avoid instantiating scenes on every open
var species_info_cache: Dictionary = {}
var species_cache_warmed: bool = false
var plants_info_cache: Dictionary = {}
var plants_cache_warmed: bool = false
 

# A hard‐coded list, or you could load these from your scenes folder
var species_list = ["Birch","Pine","Rowan"]
var plants_list = ["Grass", "Lingonberry"]

# Tree spawning state
var selected_tree_species: String = ""
var is_tree_spawn_mode: bool = false

# Plant spawning state
var selected_plant_species: String = ""
var is_plant_spawn_mode: bool = false

# References to world objects (set from world scene)
var camera: Camera3D
var terrain: MeshInstance3D
var top_right_panel: Panel

# Water level configuration
@export var water_level: float = 0.0

func _ready():
	# Connect UI
	trees_button.pressed.connect(_on_trees_button_pressed)
	if plants_button:
		plants_button.pressed.connect(_on_plants_button_pressed)

	# World references and UI setup
	_find_world_references()
	_update_selected_display()
	_create_tree_info_popup.call_deferred()
	_create_species_selection_popup.call_deferred()
	_create_plants_selection_popup.call_deferred()
	# Warm the species info cache in the background to make browser instant
	_warm_species_cache.call_deferred()
	_warm_plants_cache.call_deferred()

func _warm_species_cache():
	for species_name in species_list:
		if not species_info_cache.has(species_name):
			species_info_cache[species_name] = _load_species_info(species_name)
	species_cache_warmed = true

func _warm_plants_cache():
	for plant_name in plants_list:
		if not plants_info_cache.has(plant_name):
			plants_info_cache[plant_name] = _load_smallplant_info(plant_name)
	plants_cache_warmed = true

func _load_species_info(species_name: String) -> Dictionary:
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene: PackedScene = load(tree_scene_path)
	if not tree_scene:
		return {"name": species_name, "ideal": 0.0, "maturity_days": 0.0, "seed_type": "?", "lifespan_days": 0.0, "price": 0, "germ_chance": 0.0, "seed_cycle_days": 0.0, "min_alt": 0.0, "max_alt": 0.0}
	var tree_instance = tree_scene.instantiate()
	if not tree_instance or not tree_instance is TreeBase:
		if tree_instance:
			tree_instance.queue_free()
		return {"name": species_name, "ideal": 0.0, "maturity_days": 0.0, "seed_type": "?", "lifespan_days": 0.0, "price": 0, "germ_chance": 0.0, "seed_cycle_days": 0.0, "min_alt": 0.0, "max_alt": 0.0}
	var tree = tree_instance as TreeBase
	var seed_cycle_days: float = tree.ideal_seed_gen_interval + tree.ideal_seed_maturation_interval
	var info := {
		"name": species_name,
		"ideal": tree.ideal_altitude,
		"maturity_days": tree.max_growth_progress,
		"seed_type": tree.seed_type,
		"lifespan_days": (tree as LifeForm).max_age,
		"price": (tree as LifeForm).price,
		"germ_chance": tree.seed_germ_chance,
		"seed_cycle_days": seed_cycle_days,
		"min_alt": tree.min_viable_altitude,
		"max_alt": tree.max_viable_altitude
	}
	tree_instance.queue_free()
	return info

func _load_smallplant_info(plant_name: String) -> Dictionary:
	var plant_scene_path = "res://Scenes/SmallPlants/" + plant_name + ".tscn"
	var plant_scene: PackedScene = load(plant_scene_path)
	if not plant_scene:
		return {"name": plant_name, "ideal": 0.0, "maturity_days": 0.0, "seed_type": "-", "lifespan_days": 0.0, "price": 0, "germ_chance": 0.0, "seed_cycle_days": 0.0, "min_alt": 0.0, "max_alt": 0.0}
	var plant_instance = plant_scene.instantiate()
	if not plant_instance or not plant_instance is SmallPlant:
		if plant_instance:
			plant_instance.queue_free()
		return {"name": plant_name, "ideal": 0.0, "maturity_days": 0.0, "seed_type": "-", "lifespan_days": 0.0, "price": 0, "germ_chance": 0.0, "seed_cycle_days": 0.0, "min_alt": 0.0, "max_alt": 0.0}
	var plant = plant_instance as SmallPlant
	var info2 := {
		"name": plant_name,
		"ideal": plant.ideal_altitude,
		"maturity_days": 0.0,
		"seed_type": "-",
		"lifespan_days": (plant as LifeForm).max_age,
		"price": (plant as LifeForm).price,
		"germ_chance": 0.0,
		"seed_cycle_days": 0.0,
		"min_alt": plant.min_viable_altitude,
		"max_alt": plant.max_viable_altitude
	}
	plant_instance.queue_free()
	return info2

func _find_world_references():
	var root = get_tree().current_scene
	camera = root.find_child("Camera3D", true, false) as Camera3D
	terrain = root.find_child("Terrain", true, false) as MeshInstance3D
	top_right_panel = root.find_child("TopRightPanel", true, false) as Panel
	if not camera:
		print("Warning: Camera3D not found in scene!")
	if not terrain:
		print("Warning: Terrain not found in scene!")
	if not top_right_panel:
		print("Warning: TopRightPanel not found in scene! Credits will not be deducted")

func _on_trees_button_pressed() -> void:
	_show_species_browser()

func _on_plants_button_pressed() -> void:
	_show_plants_browser()

## Deprecated: selection through PopupMenu removed


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_mouse_over_ui(event.position):
			return
		if is_tree_spawn_mode and selected_tree_species != "":
			_spawn_tree_at_mouse_position(event.position)
		elif is_plant_spawn_mode and selected_plant_species != "":
			_spawn_plant_at_mouse_position(event.position)
		else:
			_try_inspect_entity_at_mouse_position(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_mouse_over_ui(event.position):
			return
		if is_tree_spawn_mode:
			_cancel_tree_spawn_mode()
		elif is_plant_spawn_mode:
			_cancel_plant_spawn_mode()
		else:
			if tree_info_popup and tree_info_popup.visible:
				tree_info_popup.hide()
				_on_popup_hide()
		# no trees_popup anymore
		if species_selection_popup and species_selection_popup.visible:
			species_selection_popup.hide()
		if plants_selection_popup and plants_selection_popup.visible:
			plants_selection_popup.hide()
	elif event is InputEventKey and event.pressed and not event.echo:
		# Performance test: spawn 500 birch trees at random locations when pressing '0'
		if event.keycode == KEY_0:
			_spawn_birch_benchmark()

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

func _spawn_plant_at_mouse_position(mouse_pos: Vector2) -> void:
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
		print("Cannot spawn plant underwater! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
		return
	_spawn_plant(selected_plant_species, intersection_point)

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
		# Validate space and neighbor constraints before spending
		var tm = get_tree().current_scene.find_child("TreeManager", true, false)
		if tm and tm.has_method("can_spawn_plant_at"):
			if not tm.can_spawn_plant_at(tree_scene, spawn_position):
				return
		var tree_instance = tree_scene.instantiate()
		# Charge credits before adding to scene
		var price: int = 0
		if tree_instance is LifeForm:
			price = (tree_instance as LifeForm).price
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price):
				print("Not enough credits to spawn ", species, " (cost: ", price, ")")
				if tree_instance:
					tree_instance.queue_free()
				return
		
		terrain.get_parent().add_child(tree_instance)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		tree_instance.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		tree_instance.rotation.y = random_y_rotation
		print("Spawned ", species, " tree at position: ", spawn_position)
	else:
		print("Failed to load tree scene: ", tree_scene_path)

func _spawn_plant(plant: String, spawn_position: Vector3) -> void:
	var plant_scene_path = "res://Scenes/SmallPlants/" + plant + ".tscn"
	var plant_scene = load(plant_scene_path)
	if plant_scene:
		# Validate space and neighbor constraints before spending
		var tm = get_tree().current_scene.find_child("TreeManager", true, false)
		if tm and tm.has_method("can_spawn_plant_at"):
			if not tm.can_spawn_plant_at(plant_scene, spawn_position):
				return
		var plant_instance = plant_scene.instantiate()
		# Charge credits before adding to scene
		var price: int = 0
		if plant_instance is LifeForm:
			price = (plant_instance as LifeForm).price
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price):
				print("Not enough credits to spawn ", plant, " (cost: ", price, ")")
				if plant_instance:
					plant_instance.queue_free()
				return

		terrain.get_parent().add_child(plant_instance)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		plant_instance.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		plant_instance.rotation.y = random_y_rotation
		print("Spawned ", plant, " plant at position: ", spawn_position)
	else:
		print("Failed to load plant scene: ", plant_scene_path)

func _spawn_tree_no_cost(species: String, spawn_position: Vector3) -> void:
	var tree_scene_path = "res://Scenes/Trees/" + species + ".tscn"
	var tree_scene = load(tree_scene_path)
	if tree_scene and terrain:
		var tree_instance = tree_scene.instantiate()
		terrain.get_parent().add_child(tree_instance)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		tree_instance.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		tree_instance.rotation.y = random_y_rotation
	else:
		print("Failed to load tree scene (free): ", tree_scene_path)

func _spawn_birch_benchmark():
	if not terrain:
		print("Terrain not found; cannot run benchmark")
		return
	var count: int = 0
	var attempts: int = 0
	var max_attempts: int = 2500
	var terrain_size := 128.0
	var half := terrain_size * 0.5
	while count < 125 and attempts < max_attempts:
		attempts += 1
		var x = randf_range(-half, half)
		var z = randf_range(-half, half)
		var y = terrain.get_height(x, z)
		if y >= 0.0 and y > water_level:
			_spawn_tree_no_cost("Birch", Vector3(x, y, z))
			count += 1
	print("Benchmark spawn complete: ", count, " birch trees in ", attempts, " attempts")

func _cancel_tree_spawn_mode():
	is_tree_spawn_mode = false
	selected_tree_species = ""
	_update_selected_display()
	print("Tree spawning cancelled")

func _cancel_plant_spawn_mode():
	is_plant_spawn_mode = false
	selected_plant_species = ""
	_update_selected_display()
	print("Plant spawning cancelled")

func _update_selected_display():
	if selected_label:
		if selected_tree_species != "":
			selected_label.text = "Selected: " + selected_tree_species
		elif selected_plant_species != "":
			selected_label.text = "Selected: " + selected_plant_species
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

func _create_plants_selection_popup():
	plants_selection_popup = PopupPanel.new()
	plants_selection_popup.size = Vector2(560, 740)
	plants_selection_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)

	var root_vbox = VBoxContainer.new()
	root_vbox.size = Vector2(540, 720)
	root_vbox.position = Vector2(10, 10)
	plants_selection_popup.add_child(root_vbox)

	var title_label = Label.new()
	title_label.text = "Plants"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	plants_selection_vbox = list_vbox

	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(plants_selection_popup)
	else:
		get_tree().current_scene.add_child(plants_selection_popup)

	_rebuild_plants_browser_entries()

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

func _show_plants_browser():
	if not plants_selection_popup:
		return
	var btn_rect = plants_button.get_global_rect()
	var popup_pos = Vector2(btn_rect.position.x + btn_rect.size.x + 8, btn_rect.position.y)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + plants_selection_popup.size.x > screen_size.x:
		popup_pos.x = max(0.0, btn_rect.position.x - plants_selection_popup.size.x - 8)
	plants_selection_popup.position = popup_pos
	plants_selection_popup.popup()

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


		var buttons_box = VBoxContainer.new()
		buttons_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var spawn_button = Button.new()
		spawn_button.text = "Spawn"
		spawn_button.custom_minimum_size = Vector2(110, 26)
		spawn_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spawn_button.pressed.connect(_on_spawn_button_pressed.bind(species_name))
		buttons_box.add_child(spawn_button)

		var repro_button = Button.new()
		repro_button.text = "+1 Reproduction"
		repro_button.custom_minimum_size = Vector2(110, 24)
		repro_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		repro_button.pressed.connect(_on_add_reproduction_pressed.bind(species_name))
		buttons_box.add_child(repro_button)

		row.add_child(buttons_box)

		species_selection_vbox.add_child(row)

		# Separator between entries
		var sep = HSeparator.new()
		sep.modulate = Color(1,1,1,0.25)
		species_selection_vbox.add_child(sep)

func _rebuild_plants_browser_entries():
	if not plants_selection_vbox:
		return
	for child in plants_selection_vbox.get_children():
		plants_selection_vbox.remove_child(child)
		child.queue_free()
	for plant_name in plants_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(520, 54)
		row.add_theme_constant_override("separation", 12)

		var texts_box = VBoxContainer.new()
		texts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_label = Label.new()
		name_label.text = plant_name
		name_label.add_theme_font_size_override("font_size", 16)
		texts_box.add_child(name_label)

		var info_label = Label.new()
		info_label.text = _compact_info_text_for_plant(plant_name)
		info_label.add_theme_font_size_override("font_size", 12)
		info_label.modulate = Color(0.9, 0.9, 0.9)
		texts_box.add_child(info_label)

		row.add_child(texts_box)

		var buttons_box = VBoxContainer.new()
		buttons_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var spawn_button = Button.new()
		spawn_button.text = "Spawn"
		spawn_button.custom_minimum_size = Vector2(110, 26)
		spawn_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spawn_button.pressed.connect(_on_plant_spawn_button_pressed.bind(plant_name))
		buttons_box.add_child(spawn_button)

		var repro_button = Button.new()
		repro_button.text = "+1 Reproduction"
		repro_button.custom_minimum_size = Vector2(110, 24)
		repro_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		repro_button.pressed.connect(_on_add_reproduction_pressed.bind(plant_name))
		buttons_box.add_child(repro_button)

		row.add_child(buttons_box)

		plants_selection_vbox.add_child(row)

		var sep = HSeparator.new()
		sep.modulate = Color(1,1,1,0.25)
		plants_selection_vbox.add_child(sep)

func _compact_info_text(species_name: String) -> String:
	if not species_info_cache.has(species_name):
		# Load on-demand if cache not ready
		species_info_cache[species_name] = _load_species_info(species_name)
	var info: Dictionary = species_info_cache[species_name]
	var species: String = info.get("name", species_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
	var maturity_days: float = info.get("maturity_days", 0.0)
	var ideal: float = info.get("ideal", 0.0)
	var min_alt: float = info.get("min_alt", 0.0)
	var max_alt: float = info.get("max_alt", 0.0)
	var _seed_cycle_days: float = info.get("seed_cycle_days", 0.0)
	var _germ_chance: float = info.get("germ_chance", 0.0)

	# Query manager for totals and reproduction
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	var total_living := 0
	var repro_per_day := 0.0
	if tm:
		if tm.has_method("get_total_living"):
			total_living = tm.get_total_living(species)
		if tm.has_method("get_reproduction"):
			repro_per_day = tm.get_reproduction(species)

	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f per day)" % [price, total_living, repro_per_day])
	lines.append("Lifespan: %s | Maturity at: %s" % [_format_days(lifespan_days), _format_days(maturity_days)])
	lines.append("Altitude range: %.1fm - %.1fm (Ideal is %.1fm)" % [min_alt, max_alt, ideal])
	# Seed info removed from UI due to new global reproduction system
	return "\n".join(lines)

func _compact_info_text_for_plant(plant_name: String) -> String:
	if not plants_info_cache.has(plant_name):
		plants_info_cache[plant_name] = _load_smallplant_info(plant_name)
	var info: Dictionary = plants_info_cache[plant_name]
	var species: String = info.get("name", plant_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
	var ideal: float = info.get("ideal", 0.0)
	var min_alt: float = info.get("min_alt", 0.0)
	var max_alt: float = info.get("max_alt", 0.0)

	# Query manager for totals and reproduction
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	var total_living := 0
	var repro_per_day := 0.0
	if tm:
		if tm.has_method("get_total_living"):
			total_living = tm.get_total_living(species)
		if tm.has_method("get_reproduction"):
			repro_per_day = tm.get_reproduction(species)

	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f per day)" % [price, total_living, repro_per_day])
	lines.append("Lifespan: %s" % [_format_days(lifespan_days)])
	lines.append("Altitude range: %.1fm - %.1fm (Ideal is %.1fm)" % [min_alt, max_alt, ideal])
	return "\n".join(lines)

func _on_add_reproduction_pressed(species_or_plant: String) -> void:
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm and tm.has_method("add_reproduction"):
		tm.add_reproduction(species_or_plant, 1.0)
		# Refresh the line for immediate feedback
		_rebuild_species_browser_entries()
		_rebuild_plants_browser_entries()

func _format_days(days: float) -> String:
	# Show without trailing .0 for whole numbers
	if days == int(days):
		return str(int(days)) + " days"
	return "%.1f days" % days

func _on_spawn_button_pressed(species_name: String):
	selected_tree_species = species_name
	is_tree_spawn_mode = true
	_update_selected_display()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	print("Selected tree species: ", species_name, " - Click on terrain to spawn, right click to cancel")

func _on_plant_spawn_button_pressed(plant_name: String):
	selected_plant_species = plant_name
	is_plant_spawn_mode = true
	_update_selected_display()
	if plants_selection_popup and plants_selection_popup.visible:
		plants_selection_popup.hide()
	print("Selected plant: ", plant_name, " - Click on terrain to spawn, right click to cancel")

func _try_inspect_entity_at_mouse_position(mouse_pos: Vector2):
	if not camera:
		return
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Target tree layer (3) and small plant inspect layer (4)
	query.collision_mask = (1 << 2) | (1 << 3)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result = space_state.intersect_ray(query)
	if result and result.collider:
		var clicked_node = result.collider
		var tree_base = _find_tree_base_in_hierarchy(clicked_node)
		if tree_base:
			_show_tree_info(tree_base, mouse_pos)
			return
		var plant = _find_smallplant_in_hierarchy(clicked_node)
		if plant:
			_show_smallplant_info(plant, mouse_pos)

func _find_tree_base_in_hierarchy(node: Node) -> TreeBase:
	if node is TreeBase:
		return node as TreeBase
	var current = node
	while current:
		if current is TreeBase:
			return current as TreeBase
		current = current.get_parent()
	return null

func _find_smallplant_in_hierarchy(node: Node) -> SmallPlant:
	if node is SmallPlant:
		return node as SmallPlant
	var current = node
	while current:
		if current is SmallPlant:
			return current as SmallPlant
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

func _format_smallplant_info(p: SmallPlant) -> String:
	var age_text = "%.1f / %.1f days" % [p.current_age, p.max_age]
	var health_text = "%.1f%%" % (p.healthPercentage * 100.0)
	var actual_altitude = p.global_position.y
	var min_altitude = p.min_viable_altitude
	var ideal_altitude = p.ideal_altitude
	var max_altitude = p.max_viable_altitude
	var altitude_color: String
	if actual_altitude < min_altitude or actual_altitude > max_altitude:
		altitude_color = "[color=red]"
	elif abs(actual_altitude - ideal_altitude) <= abs(actual_altitude - min_altitude) and abs(actual_altitude - ideal_altitude) <= abs(actual_altitude - max_altitude):
		altitude_color = "[color=green]"
	else:
		altitude_color = "[color=yellow]"
	var actual_altitude_text = "%s%.1f m[/color]" % [altitude_color, actual_altitude]
	var altitude_range_text = "%.1f/%.1f/%.1f m" % [min_altitude, ideal_altitude, max_altitude]
	var info = "[b]%s[/b]\n\n" % p.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	info += "[b]Current Altitude:[/b] %s\n" % actual_altitude_text
	info += "[b]Altitude Range (Min/Ideal/Max):[/b] %s" % altitude_range_text
	return info

func _show_smallplant_info(p: SmallPlant, mouse_pos: Vector2):
	if not tree_info_popup or not tree_info_label:
		return
	currently_inspected_plant = p
	var popup_pos = mouse_pos + Vector2(20, -tree_info_popup.size.y - 20)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + tree_info_popup.size.x > screen_size.x:
		popup_pos.x = screen_size.x - tree_info_popup.size.x - 10
	if popup_pos.y < 0:
		popup_pos.y = mouse_pos.y + 20
	tree_info_label.text = _format_smallplant_info(p)
	tree_info_popup.position = popup_pos
	tree_info_popup.popup()
	if popup_update_timer:
		popup_update_timer.start()

func _format_tree_info(tree: TreeBase) -> String:
	var age_text = "%.1f / %.1f days" % [tree.current_age, tree.max_age]
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
	elif currently_inspected_plant and tree_info_label and tree_info_popup and tree_info_popup.visible:
		tree_info_label.text = _format_smallplant_info(currently_inspected_plant)

func _on_popup_hide():
	currently_inspected_tree = null
	currently_inspected_plant = null
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
	if plants_selection_popup and plants_selection_popup.visible:
		var plants_popup_rect = plants_selection_popup.get_visible_rect()
		if plants_popup_rect.has_point(mouse_position):
			return true
	return false
