extends Panel

@onready var trees_button: Button = $SideMenuBar/TypeSelectBar/TreesButton
@onready var plants_button: Button = $SideMenuBar/TypeSelectBar/PlantsButton if has_node("SideMenuBar/TypeSelectBar/PlantsButton") else null
@onready var mammals_button: Button = $SideMenuBar/TypeSelectBar/MammalsButton if has_node("SideMenuBar/TypeSelectBar/MammalsButton") else null
@onready var birds_button: Button = $SideMenuBar/TypeSelectBar/BirdsButton if has_node("SideMenuBar/TypeSelectBar/BirdsButton") else null
@onready var fish_button: Button = $SideMenuBar/TypeSelectBar/FishButton if has_node("SideMenuBar/TypeSelectBar/FishButton") else null
# Optional label to show selected species (lives under BottomPanel)
@onready var selected_label: Label = (
	get_node("../BottomPanel/BottomMenuBar/SelectedLabel") as Label
) if has_node("../BottomPanel/BottomMenuBar/SelectedLabel") else null

# Tree inspection popup - created dynamically
var tree_info_popup: PopupPanel
var tree_info_label: RichTextLabel
var currently_inspected_tree: TreeBase
var currently_inspected_plant: SmallPlant
var currently_inspected_mammal: Mammal
var currently_inspected_bird: Bird
var currently_inspected_fish: Fish
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
 
# Mammals species selection popup
var mammals_selection_popup: PopupPanel
var mammals_selection_vbox: VBoxContainer

# Birds species selection popup
var birds_selection_popup: PopupPanel
var birds_selection_vbox: VBoxContainer

# Fish species selection popup
var fish_selection_popup: PopupPanel
var fish_selection_vbox: VBoxContainer

# Cached per-species info to avoid instantiating scenes on every open
var species_info_cache: Dictionary = {}
var species_cache_warmed: bool = false
var plants_info_cache: Dictionary = {}
var plants_cache_warmed: bool = false
var mammals_info_cache: Dictionary = {}
var mammals_cache_warmed: bool = false
var birds_info_cache: Dictionary = {}
var birds_cache_warmed: bool = false
var fish_info_cache: Dictionary = {}
var fish_cache_warmed: bool = false


# A hard‐coded list, or you could load these from your scenes folder
var species_list = ["Birch","Pine","Rowan"]
var plants_list = ["Algae", "Grass", "Lingonberry", "Plankton"]
var mammals_list = ["Hare", "Squirrel"]
var birds_list = ["Crow"]
var fish_list = ["Vendace"]

# Tree spawning state
var selected_tree_species: String = ""
var is_tree_spawn_mode: bool = false

# Plant spawning state
var selected_plant_species: String = ""
var is_plant_spawn_mode: bool = false

# Mammal spawning state
var selected_mammal_species: String = ""
var is_mammal_spawn_mode: bool = false

# Bird spawning state
var selected_bird_species: String = ""
var is_bird_spawn_mode: bool = false

# Fish spawning state
var selected_fish_species: String = ""
var is_fish_spawn_mode: bool = false

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
	if mammals_button:
		mammals_button.pressed.connect(_on_mammals_button_pressed)
	if birds_button:
		birds_button.pressed.connect(_on_birds_button_pressed)
	if fish_button:
		fish_button.pressed.connect(_on_fish_button_pressed)

	# World references and UI setup
	_find_world_references()
	_update_selected_display()
	_create_tree_info_popup.call_deferred()
	_create_species_selection_popup.call_deferred()
	_create_plants_selection_popup.call_deferred()
	_create_mammals_selection_popup.call_deferred()
	_create_birds_selection_popup.call_deferred()
	_create_fish_selection_popup.call_deferred()
	# Warm the species info cache in the background to make browser instant
	_warm_species_cache.call_deferred()
	_warm_plants_cache.call_deferred()
	_warm_mammals_cache.call_deferred()
	_warm_birds_cache.call_deferred()
	_warm_fish_cache.call_deferred()

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

func _warm_mammals_cache():
	for mammal_name in mammals_list:
		if not mammals_info_cache.has(mammal_name):
			mammals_info_cache[mammal_name] = _load_mammal_info(mammal_name)
	mammals_cache_warmed = true

func _warm_birds_cache():
	for bird_name in birds_list:
		if not birds_info_cache.has(bird_name):
			birds_info_cache[bird_name] = _load_bird_info(bird_name)
	birds_cache_warmed = true

func _warm_fish_cache():
	for fish_name in fish_list:
		if not fish_info_cache.has(fish_name):
			fish_info_cache[fish_name] = _load_fish_info(fish_name)
	fish_cache_warmed = true

func _load_species_info(species_name: String) -> Dictionary:
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene: PackedScene = load(tree_scene_path)
	if not tree_scene:
		return {"name": species_name, "maturity_days": 0.0, "seed_type": "?", "lifespan_days": 0.0, "price": 0, "min_alt": 0.0, "max_alt": 0.0}
	var tree_instance = tree_scene.instantiate()
	if not tree_instance or not tree_instance is TreeBase:
		if tree_instance:
			tree_instance.queue_free()
		return {"name": species_name, "maturity_days": 0.0, "seed_type": "?", "lifespan_days": 0.0, "price": 0, "min_alt": 0.0, "max_alt": 0.0}
	var tree = tree_instance as TreeBase
	var info := {
		"name": species_name,
		"maturity_days": tree.max_growth_progress,
		"seed_type": tree.seed_type,
		"lifespan_days": (tree as LifeForm).max_age,
		"price": (tree as LifeForm).price,
		"min_alt": tree.min_viable_altitude,
		"max_alt": tree.max_viable_altitude
	}
	tree_instance.queue_free()
	return info

func _load_smallplant_info(plant_name: String) -> Dictionary:
	var plant_scene_path = "res://Scenes/SmallPlants/" + plant_name + ".tscn"
	var plant_scene: PackedScene = load(plant_scene_path)
	if not plant_scene:
		return {"name": plant_name, "maturity_days": 0.0, "seed_type": "-", "lifespan_days": 0.0, "price": 0, "min_alt": 0.0, "max_alt": 0.0}
	var plant_instance = plant_scene.instantiate()
	if not plant_instance or not plant_instance is SmallPlant:
		if plant_instance:
			plant_instance.queue_free()
		return {"name": plant_name, "maturity_days": 0.0, "seed_type": "-", "lifespan_days": 0.0, "price": 0, "min_alt": 0.0, "max_alt": 0.0}
	var plant = plant_instance as SmallPlant
	var info2 := {
		"name": plant_name,
		"maturity_days": 0.0,
		"seed_type": "-",
		"lifespan_days": (plant as LifeForm).max_age,
		"price": (plant as LifeForm).price,
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

func _on_mammals_button_pressed() -> void:
	_show_mammals_browser()

func _on_birds_button_pressed() -> void:
	_show_birds_browser()

func _on_fish_button_pressed() -> void:
	_show_fish_browser()

## Deprecated: selection through PopupMenu removed


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_mouse_over_ui(event.position):
			return
		if is_tree_spawn_mode and selected_tree_species != "":
			_spawn_tree_at_mouse_position(event.position)
		elif is_plant_spawn_mode and selected_plant_species != "":
			_spawn_plant_at_mouse_position(event.position)
		elif is_mammal_spawn_mode and selected_mammal_species != "":
			_spawn_mammal_at_mouse_position(event.position)
		elif is_bird_spawn_mode and selected_bird_species != "":
			_spawn_bird_at_mouse_position(event.position)
		elif is_fish_spawn_mode and selected_fish_species != "":
			_spawn_fish_at_mouse_position(event.position)
		else:
			_try_inspect_entity_at_mouse_position(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Always clear all selections on right click
		_clear_all_selections()
		# Hide any open popups
		if tree_info_popup and tree_info_popup.visible:
			tree_info_popup.hide()
			_on_popup_hide()
		if species_selection_popup and species_selection_popup.visible:
			species_selection_popup.hide()
		if plants_selection_popup and plants_selection_popup.visible:
			plants_selection_popup.hide()
		if mammals_selection_popup and mammals_selection_popup.visible:
			mammals_selection_popup.hide()
		if birds_selection_popup and birds_selection_popup.visible:
			birds_selection_popup.hide()
		if fish_selection_popup and fish_selection_popup.visible:
			fish_selection_popup.hide()
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
	# Reserve spot to avoid rapid double-spawn overlap
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm:
		var scene = load("res://Scenes/Trees/" + selected_tree_species + ".tscn")
		if scene and tm.has_method("reserve_for_scene"):
			# Disallow immediate subsequent spawn into the same spot by tagging reservation to that exact position
			if not tm.reserve_for_scene(scene, intersection_point, 0.25):
				print("Spawn spot temporarily reserved; try again")
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
	# Decide if target is a water-surface or underwater plant
	var scene2: PackedScene = load("res://Scenes/SmallPlants/" + selected_plant_species + ".tscn")
	var is_water_surface: bool = false
	var is_underwater: bool = false
	if scene2:
		var inst = scene2.instantiate()
		if inst and inst.has_method("is_water_surface_plant") and inst.is_water_surface_plant():
			is_water_surface = true
		if inst and inst.has_method("is_underwater_plant") and inst.is_underwater_plant():
			is_underwater = true
		if inst:
			inst.queue_free()
	# Validate placement against water level depending on plant type
	if is_water_surface:
		if intersection_point.y > water_level:
			print("Cannot spawn water-surface plant on dry ground (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
			return
	elif is_underwater:
		# Require at least 1.5m depth below water level
		if intersection_point.y > water_level - 1.5:
			print("Cannot spawn underwater plant in shallow water (terrain: ", intersection_point.y, ", min: ", water_level - 1.5, ")")
			return
	else:
		if intersection_point.y <= water_level:
			print("Cannot spawn plant underwater! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
			return
	var tm2 = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm2 and scene2:
		if tm2.has_method("reserve_for_scene"):
			if not tm2.reserve_for_scene(scene2, intersection_point, 0.25):
				print("Spawn spot temporarily reserved; try again")
				return
	_spawn_plant(selected_plant_species, intersection_point)

func _spawn_mammal_at_mouse_position(mouse_pos: Vector2) -> void:
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
		print("Cannot spawn mammal underwater! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
		return
	_spawn_mammal(selected_mammal_species, intersection_point)

func _spawn_bird_at_mouse_position(mouse_pos: Vector2) -> void:
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
		print("Cannot spawn bird underwater! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
		return
	_spawn_bird(selected_bird_species, intersection_point)

func _spawn_fish_at_mouse_position(mouse_pos: Vector2) -> void:
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
	if intersection_point.y > -1.5:
		print("Cannot spawn fish on land/in too shallow water! (terrain height: ", intersection_point.y, ", water level: ", water_level, ")")
		return
	_spawn_fish(selected_fish_species, intersection_point)

func _spawn_fish(species: String, spawn_position: Vector3) -> void:
	var scene_path = "res://Scenes/Animals/" + species + ".tscn"
	var scene = load(scene_path)
	if scene:
		var tm = get_tree().current_scene.find_child("TreeManager", true, false)
		if tm and tm.has_method("can_spawn_plant_at"):
			if not tm.can_spawn_plant_at(scene, spawn_position):
				return
		var inst = scene.instantiate()
		var price_val: int = 0
		if inst is LifeForm:
			price_val = _compute_dynamic_spawn_cost(inst as LifeForm)
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price_val):
				print("Not enough credits to spawn ", species, " (cost: ", price_val, ")")
				if inst:
					inst.queue_free()
				return
		var trp = top_right_panel
		if trp and trp.has_method("add_species_expense") and inst is LifeForm:
			trp.add_species_expense((inst as LifeForm).species_name, price_val, "animal")
		terrain.get_parent().add_child(inst)
		spawn_position.y = water_level - 1.0
		inst.global_position = spawn_position
		inst.rotation.y = randf() * TAU
		print("Spawned ", species, " at position: ", spawn_position)
	else:
		print("Failed to load fish scene: ", scene_path)

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
		# Charge dynamic spawn cost before adding to scene
		var price: int = 0
		if tree_instance is LifeForm:
			price = _compute_dynamic_spawn_cost(tree_instance as LifeForm)
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price):
				print("Not enough credits to spawn ", species, " (cost: ", price, ")")
				if tree_instance:
					tree_instance.queue_free()
				return
		# Track expense for this species (plants category for trees)
		var trp = top_right_panel
		if trp and trp.has_method("add_species_expense") and tree_instance is LifeForm:
			trp.add_species_expense((tree_instance as LifeForm).species_name, price, "plant")
		
		terrain.get_parent().add_child(tree_instance)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		tree_instance.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		tree_instance.rotation.y = random_y_rotation
		# Force full growth on spawn for convenience testing
		if tree_instance is TreeBase:
			var t := tree_instance as TreeBase
			t.growth_progress = t.max_growth_progress
			t.state = t.TreeState.MATURE
			t.state_percentage = 0.0
			if t.has_method("_update_scale"):
				t._update_scale()
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
		# Charge dynamic spawn cost before adding to scene
		var price: int = 0
		if plant_instance is LifeForm:
			price = _compute_dynamic_spawn_cost(plant_instance as LifeForm)
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price):
				print("Not enough credits to spawn ", plant, " (cost: ", price, ")")
				if plant_instance:
					plant_instance.queue_free()
				return
		# Track expense for this species (plants category)
		var trp2 = top_right_panel
		if trp2 and trp2.has_method("add_species_expense") and plant_instance is LifeForm:
			trp2.add_species_expense((plant_instance as LifeForm).species_name, price, "plant")

		terrain.get_parent().add_child(plant_instance)
		# Place Y based on plant type
		if plant_instance and plant_instance.has_method("is_water_surface_plant") and plant_instance.is_water_surface_plant():
			spawn_position.y = water_level
		elif plant_instance and plant_instance.has_method("is_underwater_plant") and plant_instance.is_underwater_plant():
			spawn_position.y = water_level - 1.0
		else:
			var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
			spawn_position.y = terrain_height
		plant_instance.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		plant_instance.rotation.y = random_y_rotation
		print("Spawned ", plant, " plant at position: ", spawn_position)
	else:
		print("Failed to load plant scene: ", plant_scene_path)

func _spawn_mammal(species: String, spawn_position: Vector3) -> void:
	var scene_path = "res://Scenes/Animals/" + species + ".tscn"
	var scene = load(scene_path)
	if scene:
		# Use plant spacing validation and reservations re-used from manager
		var tm = get_tree().current_scene.find_child("TreeManager", true, false)
		if tm and tm.has_method("can_spawn_plant_at"):
			if not tm.can_spawn_plant_at(scene, spawn_position):
				return
		var inst = scene.instantiate()
		# Charge dynamic spawn cost
		var price: int = 0
		if inst is LifeForm:
			price = _compute_dynamic_spawn_cost(inst as LifeForm)
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price):
				print("Not enough credits to spawn ", species, " (cost: ", price, ")")
				if inst:
					inst.queue_free()
				return
		# Track expense for this species (animals category)
		var trp3 = top_right_panel
		if trp3 and trp3.has_method("add_species_expense") and inst is LifeForm:
			trp3.add_species_expense((inst as LifeForm).species_name, price, "animal")
		terrain.get_parent().add_child(inst)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		spawn_position.y = terrain_height
		inst.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		inst.rotation.y = random_y_rotation
		print("Spawned ", species, " at position: ", spawn_position)
	else:
		print("Failed to load mammal scene: ", scene_path)

func _spawn_bird(species: String, spawn_position: Vector3) -> void:
	var scene_path = "res://Scenes/Animals/" + species + ".tscn"
	var scene = load(scene_path)
	if scene:
		var tm = get_tree().current_scene.find_child("TreeManager", true, false)
		if tm and tm.has_method("can_spawn_plant_at"):
			if not tm.can_spawn_plant_at(scene, spawn_position):
				return
		var inst = scene.instantiate()
		var price: int = 0
		if inst is LifeForm:
			price = _compute_dynamic_spawn_cost(inst as LifeForm)
		if top_right_panel and top_right_panel.has_method("try_spend"):
			if not top_right_panel.try_spend(price):
				print("Not enough credits to spawn ", species, " (cost: ", price, ")")
				if inst:
					inst.queue_free()
				return
		if top_right_panel and top_right_panel.has_method("add_species_expense") and inst is LifeForm:
			top_right_panel.add_species_expense((inst as LifeForm).species_name, price, "animal")
		terrain.get_parent().add_child(inst)
		var terrain_height = terrain.get_height(spawn_position.x, spawn_position.z)
		# Spawn in the air at the bird's flight height above ground
		var flight_h: float = 6.0
		if inst and inst.has_method("get"):
			var fh = inst.get("flight_height")
			if typeof(fh) == TYPE_FLOAT or typeof(fh) == TYPE_INT:
				flight_h = float(fh)
		spawn_position.y = terrain_height + flight_h
		inst.global_position = spawn_position
		var random_y_rotation = randf() * TAU
		inst.rotation.y = random_y_rotation
		print("Spawned ", species, " at position: ", spawn_position)
	else:
		print("Failed to load bird scene: ", scene_path)

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

func _clear_all_selections():
	is_tree_spawn_mode = false
	selected_tree_species = ""
	is_plant_spawn_mode = false
	selected_plant_species = ""
	is_mammal_spawn_mode = false
	selected_mammal_species = ""
	is_bird_spawn_mode = false
	selected_bird_species = ""
	is_fish_spawn_mode = false
	selected_fish_species = ""
	_update_selected_display()

func _update_selected_display():
	if selected_label:
		if selected_tree_species != "":
			selected_label.text = "Selected: " + selected_tree_species
		elif selected_plant_species != "":
			selected_label.text = "Selected: " + selected_plant_species
		elif selected_mammal_species != "":
			selected_label.text = "Selected: " + selected_mammal_species
		elif selected_bird_species != "":
			selected_label.text = "Selected: " + selected_bird_species
		elif selected_fish_species != "":
			selected_label.text = "Selected: " + selected_fish_species
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
	# Allow background input to continue so right-click outside can close via global handler
	species_selection_popup.exclusive = false

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

	# Close on right-click even when the popup captures input
	species_selection_popup.window_input.connect(_on_popup_gui_input)
	scroll.gui_input.connect(_on_popup_gui_input)

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
	plants_selection_popup.exclusive = false

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

	# Close on right-click even when the popup captures input
	plants_selection_popup.window_input.connect(_on_popup_gui_input)
	scroll.gui_input.connect(_on_popup_gui_input)

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

func _create_mammals_selection_popup():
	mammals_selection_popup = PopupPanel.new()
	mammals_selection_popup.size = Vector2(560, 740)
	mammals_selection_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	mammals_selection_popup.exclusive = false

	var root_vbox = VBoxContainer.new()
	root_vbox.size = Vector2(540, 720)
	root_vbox.position = Vector2(10, 10)
	mammals_selection_popup.add_child(root_vbox)

	var title_label = Label.new()
	title_label.text = "Mammals"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	# Close on right-click even when the popup captures input
	mammals_selection_popup.window_input.connect(_on_popup_gui_input)
	scroll.gui_input.connect(_on_popup_gui_input)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	mammals_selection_vbox = list_vbox

	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(mammals_selection_popup)
	else:
		get_tree().current_scene.add_child(mammals_selection_popup)

	_rebuild_mammals_browser_entries()

func _create_birds_selection_popup():
	birds_selection_popup = PopupPanel.new()
	birds_selection_popup.size = Vector2(560, 740)
	birds_selection_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	birds_selection_popup.exclusive = false

	var root_vbox = VBoxContainer.new()
	root_vbox.size = Vector2(540, 720)
	root_vbox.position = Vector2(10, 10)
	birds_selection_popup.add_child(root_vbox)

	var title_label = Label.new()
	title_label.text = "Birds"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	birds_selection_popup.window_input.connect(_on_popup_gui_input)
	scroll.gui_input.connect(_on_popup_gui_input)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	birds_selection_vbox = list_vbox

	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(birds_selection_popup)
	else:
		get_tree().current_scene.add_child(birds_selection_popup)

	_rebuild_birds_browser_entries()

func _create_fish_selection_popup():
	fish_selection_popup = PopupPanel.new()
	fish_selection_popup.size = Vector2(560, 740)
	fish_selection_popup.set_flag(Window.FLAG_RESIZE_DISABLED, true)
	fish_selection_popup.exclusive = false

	var root_vbox = VBoxContainer.new()
	root_vbox.size = Vector2(540, 720)
	root_vbox.position = Vector2(10, 10)
	fish_selection_popup.add_child(root_vbox)

	var title_label = Label.new()
	title_label.text = "Fish"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	fish_selection_popup.window_input.connect(_on_popup_gui_input)
	scroll.gui_input.connect(_on_popup_gui_input)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	fish_selection_vbox = list_vbox

	var ui_root = get_parent()
	if ui_root:
		ui_root.add_child(fish_selection_popup)
	else:
		get_tree().current_scene.add_child(fish_selection_popup)

	_rebuild_fish_browser_entries()

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
	info += "Growth: %.1fy | Seeds: %s" % [
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
	# Rebuild values when opened
	_rebuild_species_browser_entries()
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
	# Rebuild values when opened
	_rebuild_plants_browser_entries()
	plants_selection_popup.position = popup_pos
	plants_selection_popup.popup()

func _show_mammals_browser():
	if not mammals_selection_popup:
		return
	var btn_rect = mammals_button.get_global_rect() if mammals_button else trees_button.get_global_rect()
	var popup_pos = Vector2(btn_rect.position.x + btn_rect.size.x + 8, btn_rect.position.y)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + mammals_selection_popup.size.x > screen_size.x:
		popup_pos.x = max(0.0, btn_rect.position.x - mammals_selection_popup.size.x - 8)
	_rebuild_mammals_browser_entries()
	mammals_selection_popup.position = popup_pos
	mammals_selection_popup.popup()

func _show_birds_browser():
	if not birds_selection_popup:
		return
	var btn_rect = birds_button.get_global_rect() if birds_button else trees_button.get_global_rect()
	var popup_pos = Vector2(btn_rect.position.x + btn_rect.size.x + 8, btn_rect.position.y)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + birds_selection_popup.size.x > screen_size.x:
		popup_pos.x = max(0.0, btn_rect.position.x - birds_selection_popup.size.x - 8)
	_rebuild_birds_browser_entries()
	birds_selection_popup.position = popup_pos
	birds_selection_popup.popup()

func _show_fish_browser():
	if not fish_selection_popup:
		return
	var btn_rect = fish_button.get_global_rect() if fish_button else trees_button.get_global_rect()
	var popup_pos = Vector2(btn_rect.position.x + btn_rect.size.x + 8, btn_rect.position.y)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + fish_selection_popup.size.x > screen_size.x:
		popup_pos.x = max(0.0, btn_rect.position.x - fish_selection_popup.size.x - 8)
	_rebuild_fish_browser_entries()
	fish_selection_popup.position = popup_pos
	fish_selection_popup.popup()

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

func _compact_info_text_for_mammal(mammal_name: String) -> String:
	if not mammals_info_cache.has(mammal_name):
		mammals_info_cache[mammal_name] = _load_mammal_info(mammal_name)
	var info: Dictionary = mammals_info_cache[mammal_name]
	var species: String = info.get("name", mammal_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
	var walk_speed: float = info.get("walk_speed", 0.0)
	var wake: float = info.get("wake", 0.0)
	var vision: float = info.get("vision", 0.0)
	var diet: Array = info.get("diet", [])

	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	var total_living := 0
	var repro_per_day := 0.0
	var eating_target := 1
	if tm:
		if tm.has_method("get_total_living"):
			total_living = tm.get_total_living(species)
		if tm.has_method("get_reproduction"):
			repro_per_day = tm.get_reproduction(species)
		if tm.has_method("get_eating_target"):
			eating_target = tm.get_eating_target(species)
	var spawn_cost: int = price * (total_living + 1)
	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f/day | eat x%d/day)" % [spawn_cost, total_living, repro_per_day, eating_target])
	lines.append("Lifespan: %s | Walk speed: %.1f m/s" % [_format_days(lifespan_days), walk_speed])
	lines.append("Daily cycle: wakes at %.0f:00 | Vision: %.0fm" % [wake, vision])
	lines.append("Diet: " + ", ".join(diet))
	return "\n".join(lines)

func _compact_info_text_for_bird(bird_name: String) -> String:
	if not birds_info_cache.has(bird_name):
		birds_info_cache[bird_name] = _load_bird_info(bird_name)
	var info: Dictionary = birds_info_cache[bird_name]
	var species: String = info.get("name", bird_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
	var fly_speed: float = info.get("fly_speed", 0.0)
	var wake: float = info.get("wake", 0.0)
	var vision: float = info.get("vision", 0.0)
	var diet: Array = info.get("diet", [])
	var flight_height: float = info.get("flight_height", 0.0)

	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	var total_living := 0
	var repro_per_day := 0.0
	var eating_target := 1
	if tm:
		if tm.has_method("get_total_living"):
			total_living = tm.get_total_living(species)
		if tm.has_method("get_reproduction"):
			repro_per_day = tm.get_reproduction(species)
		if tm.has_method("get_eating_target"):
			eating_target = tm.get_eating_target(species)
	var spawn_cost: int = price * (total_living + 1)
	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f/day | eat x%d/day)" % [spawn_cost, total_living, repro_per_day, eating_target])
	lines.append("Lifespan: %s | Fly speed: %.1f m/s | Cruise: %.1fm" % [_format_days(lifespan_days), fly_speed, flight_height])
	lines.append("Daily cycle: wakes at %.0f:00 | Vision: %.0fm" % [wake, vision])
	lines.append("Diet: " + ", ".join(diet))
	return "\n".join(lines)

func _compact_info_text_for_fish(fish_name: String) -> String:
	if not fish_info_cache.has(fish_name):
		fish_info_cache[fish_name] = _load_fish_info(fish_name)
	var info: Dictionary = fish_info_cache[fish_name]
	var species: String = info.get("name", fish_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
	var swim_speed: float = info.get("swim_speed", 0.0)
	var wake: float = info.get("wake", 0.0)
	var vision: float = info.get("vision", 0.0)
	var diet: Array = info.get("diet", [])

	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	var total_living := 0
	var repro_per_day := 0.0
	var eating_target := 1
	if tm:
		if tm.has_method("get_total_living"):
			total_living = tm.get_total_living(species)
		if tm.has_method("get_reproduction"):
			repro_per_day = tm.get_reproduction(species)
		if tm.has_method("get_eating_target"):
			eating_target = tm.get_eating_target(species)
	var spawn_cost: int = price * (total_living + 1)
	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f/day | eat x%d/day)" % [spawn_cost, total_living, repro_per_day, eating_target])
	lines.append("Lifespan: %s | Swim speed: %.1f m/s" % [_format_days(lifespan_days), swim_speed])
	lines.append("Daily cycle: wakes at %.0f:00 | Vision: %.0fm" % [wake, vision])
	lines.append("Diet: " + ", ".join(diet))
	return "\n".join(lines)

func _load_mammal_info(mammal_name: String) -> Dictionary:
	var path = "res://Scenes/Animals/" + mammal_name + ".tscn"
	var scene: PackedScene = load(path)
	if not scene:
		return {"name": mammal_name, "price": 0, "lifespan_days": 0.0, "walk_speed": 0.0, "sleep": 0.0, "wake": 0.0, "vision": 0.0, "diet": []}
	var inst = scene.instantiate()
	var info := {"name": mammal_name, "price": 0, "lifespan_days": 0.0, "walk_speed": 0.0, "sleep": 0.0, "wake": 0.0, "vision": 0.0, "diet": []}
	if inst and inst is LifeForm:
		info["price"] = (inst as LifeForm).price
		info["lifespan_days"] = (inst as LifeForm).max_age
	if inst and inst.has_method("get"):
		var ws = inst.get("walk_speed")
		if typeof(ws) == TYPE_FLOAT or typeof(ws) == TYPE_INT:
			info["walk_speed"] = float(ws)
		var st = inst.get("sleep_time")
		if typeof(st) == TYPE_FLOAT or typeof(st) == TYPE_INT:
			info["sleep"] = float(st)
		var wh = inst.get("wake_hour")
		if typeof(wh) == TYPE_FLOAT or typeof(wh) == TYPE_INT:
			info["wake"] = float(wh)
		var vr = inst.get("vision_range")
		if typeof(vr) == TYPE_FLOAT or typeof(vr) == TYPE_INT:
			info["vision"] = float(vr)
		var d = inst.get("diet")
		if typeof(d) == TYPE_ARRAY:
			info["diet"] = d
	if inst:
		inst.queue_free()
	return info

func _load_bird_info(bird_name: String) -> Dictionary:
	var path = "res://Scenes/Animals/" + bird_name + ".tscn"
	var scene: PackedScene = load(path)
	if not scene:
		return {"name": bird_name, "price": 0, "lifespan_days": 0.0, "fly_speed": 0.0, "sleep": 0.0, "wake": 0.0, "vision": 0.0, "diet": [], "flight_height": 0.0}
	var inst = scene.instantiate()
	var info := {"name": bird_name, "price": 0, "lifespan_days": 0.0, "fly_speed": 0.0, "sleep": 0.0, "wake": 0.0, "vision": 0.0, "diet": [], "flight_height": 0.0}
	if inst and inst is LifeForm:
		info["price"] = (inst as LifeForm).price
		info["lifespan_days"] = (inst as LifeForm).max_age
	if inst and inst.has_method("get"):
		var fs = inst.get("fly_speed")
		if typeof(fs) == TYPE_FLOAT or typeof(fs) == TYPE_INT:
			info["fly_speed"] = float(fs)
		var st = inst.get("sleep_time")
		if typeof(st) == TYPE_FLOAT or typeof(st) == TYPE_INT:
			info["sleep"] = float(st)
		var wh = inst.get("wake_hour")
		if typeof(wh) == TYPE_FLOAT or typeof(wh) == TYPE_INT:
			info["wake"] = float(wh)
		var vr = inst.get("vision_range")
		if typeof(vr) == TYPE_FLOAT or typeof(vr) == TYPE_INT:
			info["vision"] = float(vr)
		var d = inst.get("diet")
		if typeof(d) == TYPE_ARRAY:
			info["diet"] = d
		var fh = inst.get("flight_height")
		if typeof(fh) == TYPE_FLOAT or typeof(fh) == TYPE_INT:
			info["flight_height"] = float(fh)
	if inst:
		inst.queue_free()
	return info

func _load_fish_info(fish_name: String) -> Dictionary:
	var path = "res://Scenes/Animals/" + fish_name + ".tscn"
	var scene: PackedScene = load(path)
	if not scene:
		return {"name": fish_name, "price": 0, "lifespan_days": 0.0, "swim_speed": 0.0, "sleep": 0.0, "wake": 0.0, "vision": 0.0, "diet": []}
	var inst = scene.instantiate()
	var info := {"name": fish_name, "price": 0, "lifespan_days": 0.0, "swim_speed": 0.0, "sleep": 0.0, "wake": 0.0, "vision": 0.0, "diet": []}
	if inst and inst is LifeForm:
		info["price"] = (inst as LifeForm).price
		info["lifespan_days"] = (inst as LifeForm).max_age
	if inst and inst.has_method("get"):
		var ss = inst.get("swim_speed")
		if typeof(ss) == TYPE_FLOAT or typeof(ss) == TYPE_INT:
			info["swim_speed"] = float(ss)
		var st = inst.get("sleep_time")
		if typeof(st) == TYPE_FLOAT or typeof(st) == TYPE_INT:
			info["sleep"] = float(st)
		var wh = inst.get("wake_hour")
		if typeof(wh) == TYPE_FLOAT or typeof(wh) == TYPE_INT:
			info["wake"] = float(wh)
		var vr = inst.get("vision_range")
		if typeof(vr) == TYPE_FLOAT or typeof(vr) == TYPE_INT:
			info["vision"] = float(vr)
		var d = inst.get("diet")
		if typeof(d) == TYPE_ARRAY:
			info["diet"] = d
	if inst:
		inst.queue_free()
	return info

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

func _rebuild_mammals_browser_entries():
	if not mammals_selection_vbox:
		return
	for child in mammals_selection_vbox.get_children():
		mammals_selection_vbox.remove_child(child)
		child.queue_free()
	for mammal_name in mammals_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(520, 54)
		row.add_theme_constant_override("separation", 12)

		var texts_box = VBoxContainer.new()
		texts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_label = Label.new()
		name_label.text = mammal_name
		name_label.add_theme_font_size_override("font_size", 16)
		texts_box.add_child(name_label)

		var info_label = Label.new()
		info_label.text = _compact_info_text_for_mammal(mammal_name)
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
		spawn_button.pressed.connect(_on_mammal_spawn_button_pressed.bind(mammal_name))
		buttons_box.add_child(spawn_button)

		var repro_button = Button.new()
		repro_button.text = "+1 Reproduction"
		repro_button.custom_minimum_size = Vector2(110, 24)
		repro_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		repro_button.pressed.connect(_on_add_reproduction_pressed.bind(mammal_name))
		buttons_box.add_child(repro_button)

		var eating_button = Button.new()
		eating_button.text = "+1 Eating"
		eating_button.custom_minimum_size = Vector2(110, 24)
		eating_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eating_button.pressed.connect(_on_add_eating_pressed.bind(mammal_name))
		buttons_box.add_child(eating_button)

		row.add_child(buttons_box)

		mammals_selection_vbox.add_child(row)
		var sep = HSeparator.new()
		sep.modulate = Color(1,1,1,0.25)
		mammals_selection_vbox.add_child(sep)

func _rebuild_birds_browser_entries():
	if not birds_selection_vbox:
		return
	for child in birds_selection_vbox.get_children():
		birds_selection_vbox.remove_child(child)
		child.queue_free()
	for bird_name in birds_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(520, 54)
		row.add_theme_constant_override("separation", 12)

		var texts_box = VBoxContainer.new()
		texts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_label = Label.new()
		name_label.text = bird_name
		name_label.add_theme_font_size_override("font_size", 16)
		texts_box.add_child(name_label)

		var info_label = Label.new()
		info_label.text = _compact_info_text_for_bird(bird_name)
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
		spawn_button.pressed.connect(_on_bird_spawn_button_pressed.bind(bird_name))
		buttons_box.add_child(spawn_button)

		var repro_button = Button.new()
		repro_button.text = "+1 Reproduction"
		repro_button.custom_minimum_size = Vector2(110, 24)
		repro_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		repro_button.pressed.connect(_on_add_reproduction_pressed.bind(bird_name))
		buttons_box.add_child(repro_button)

		var eating_button = Button.new()
		eating_button.text = "+1 Eating"
		eating_button.custom_minimum_size = Vector2(110, 24)
		eating_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eating_button.pressed.connect(_on_add_eating_pressed.bind(bird_name))
		buttons_box.add_child(eating_button)

		row.add_child(buttons_box)

		birds_selection_vbox.add_child(row)
		var sep = HSeparator.new()
		sep.modulate = Color(1,1,1,0.25)
		birds_selection_vbox.add_child(sep)

func _rebuild_fish_browser_entries():
	if not fish_selection_vbox:
		return
	for child in fish_selection_vbox.get_children():
		fish_selection_vbox.remove_child(child)
		child.queue_free()
	for fish_name in fish_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(520, 54)
		row.add_theme_constant_override("separation", 12)

		var texts_box = VBoxContainer.new()
		texts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_label = Label.new()
		name_label.text = fish_name
		name_label.add_theme_font_size_override("font_size", 16)
		texts_box.add_child(name_label)

		var info_label = Label.new()
		info_label.text = _compact_info_text_for_fish(fish_name)
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
		spawn_button.pressed.connect(_on_fish_spawn_button_pressed.bind(fish_name))
		buttons_box.add_child(spawn_button)

		var repro_button = Button.new()
		repro_button.text = "+1 Reproduction"
		repro_button.custom_minimum_size = Vector2(110, 24)
		repro_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		repro_button.pressed.connect(_on_add_reproduction_pressed.bind(fish_name))
		buttons_box.add_child(repro_button)

		var eating_button = Button.new()
		eating_button.text = "+1 Eating"
		eating_button.custom_minimum_size = Vector2(110, 24)
		eating_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eating_button.pressed.connect(_on_add_eating_pressed.bind(fish_name))
		buttons_box.add_child(eating_button)

		row.add_child(buttons_box)

		fish_selection_vbox.add_child(row)
		var sep = HSeparator.new()
		sep.modulate = Color(1,1,1,0.25)
		fish_selection_vbox.add_child(sep)

func _compact_info_text(species_name: String) -> String:
	if not species_info_cache.has(species_name):
		# Load on-demand if cache not ready
		species_info_cache[species_name] = _load_species_info(species_name)
	var info: Dictionary = species_info_cache[species_name]
	var species: String = info.get("name", species_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
	var maturity_days: float = info.get("maturity_days", 0.0)
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
		# Reserve a position briefly when user selects Spawn to avoid double-spawn overlaps

	var spawn_cost: int = price * (total_living + 1)
	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f per day)" % [spawn_cost, total_living, repro_per_day])
	lines.append("Lifespan: %s | Maturity at: %s" % [_format_days(lifespan_days), _format_days(maturity_days)])
	# Reproduction parameters (shared via Plant)
	var repro_radius := 0.0
	var tree_scene_path = "res://Scenes/Trees/" + species_name + ".tscn"
	var tree_scene: PackedScene = load(tree_scene_path)
	if tree_scene:
		var inst = tree_scene.instantiate()
		if inst and inst.has_method("get"):
			var rr = inst.get("repro_radius")
			if typeof(rr) == TYPE_FLOAT or typeof(rr) == TYPE_INT:
				repro_radius = float(rr)
		inst.queue_free()
	lines.append("Reproduction: radius %.1fm" % [repro_radius])
	lines.append("Altitude range: %.1fm - %.1fm" % [min_alt, max_alt])
	# Seed info removed from UI due to new global reproduction system
	return "\n".join(lines)

func _compact_info_text_for_plant(plant_name: String) -> String:
	if not plants_info_cache.has(plant_name):
		plants_info_cache[plant_name] = _load_smallplant_info(plant_name)
	var info: Dictionary = plants_info_cache[plant_name]
	var species: String = info.get("name", plant_name)
	var price: int = info.get("price", 0)
	var lifespan_days: float = info.get("lifespan_days", 0.0)
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

	var spawn_cost: int = price * (total_living + 1)
	var lines: Array[String] = []
	lines.append("Cost: %dCr | Total living: %d (+%.0f per day)" % [spawn_cost, total_living, repro_per_day])
	lines.append("Lifespan: %s" % [_format_days(lifespan_days)])
	# Reproduction parameters for plants
	var repro_radius := 0.0
	var plant_scene_path = "res://Scenes/SmallPlants/" + plant_name + ".tscn"
	var plant_scene: PackedScene = load(plant_scene_path)
	if plant_scene:
		var inst = plant_scene.instantiate()
		if inst and inst.has_method("get"):
			var rr = inst.get("repro_radius")
			if typeof(rr) == TYPE_FLOAT or typeof(rr) == TYPE_INT:
				repro_radius = float(rr)
		inst.queue_free()
	lines.append("Reproduction: radius %.1fm" % [repro_radius])
	lines.append("Altitude range: %.1fm - %.1fm" % [min_alt, max_alt])
	return "\n".join(lines)

func _on_add_reproduction_pressed(species_or_plant: String) -> void:
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if not tm:
		return
	var base_price: int = _get_base_price_for(species_or_plant)
	var current_repro: float = 0.0
	if tm.has_method("get_reproduction"):
		current_repro = tm.get_reproduction(species_or_plant)
	var repro_cost: int = int(5.0 * float(base_price) * (current_repro + 1.0))
	if top_right_panel and top_right_panel.has_method("try_spend"):
		if not top_right_panel.try_spend(repro_cost):
			print("Not enough credits to increase reproduction for ", species_or_plant, " (cost: ", repro_cost, ")")
			return
	if tm.has_method("add_reproduction"):
		tm.add_reproduction(species_or_plant, 1.0)
	# Track expense for reproduction increase (category depends on whether species is animal or plant)
	var category: String = "plant"
	if mammals_list.has(species_or_plant):
		category = "animal"
	if top_right_panel and top_right_panel.has_method("add_species_expense"):
		top_right_panel.add_species_expense(species_or_plant, repro_cost, category)
	# Refresh the lines for immediate feedback
	_rebuild_species_browser_entries()
	_rebuild_plants_browser_entries()

func _on_add_eating_pressed(mammal_species: String) -> void:
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if not tm:
		return
	var base_price: int = _get_base_price_for(mammal_species)
	# Eating upgrade cost: 2x base price * (current_target + 1)
	var current_target: int = 1
	if tm.has_method("get_eating_target"):
		current_target = tm.get_eating_target(mammal_species)
	var upgrade_cost: int = int(2.0 * float(base_price) * float(current_target + 1))
	if top_right_panel and top_right_panel.has_method("try_spend"):
		if not top_right_panel.try_spend(upgrade_cost):
			print("Not enough credits to increase eating target for ", mammal_species, " (cost: ", upgrade_cost, ")")
			return
	if tm.has_method("add_eating_target"):
		tm.add_eating_target(mammal_species, 1)
	# Track expense for eating target increase (animals only)
	if top_right_panel and top_right_panel.has_method("add_species_expense"):
		top_right_panel.add_species_expense(mammal_species, upgrade_cost, "animal")
	# Refresh mammals UI for immediate feedback
	_rebuild_mammals_browser_entries()

func _on_popup_gui_input(event: InputEvent) -> void:
	# Ensure species browsers close on right-click even when the popup consumes input
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_clear_all_selections()
		if tree_info_popup and tree_info_popup.visible:
			tree_info_popup.hide()
			_on_popup_hide()
		if species_selection_popup and species_selection_popup.visible:
			species_selection_popup.hide()
		if plants_selection_popup and plants_selection_popup.visible:
			plants_selection_popup.hide()
		if mammals_selection_popup and mammals_selection_popup.visible:
			mammals_selection_popup.hide()
		if birds_selection_popup and birds_selection_popup.visible:
			birds_selection_popup.hide()
		if fish_selection_popup and fish_selection_popup.visible:
			fish_selection_popup.hide()
		accept_event()

func _format_days(days: float) -> String:
	# Show without trailing .0 for whole numbers
	if days == int(days):
		return str(int(days)) + " days"
	return "%.1f days" % days

func _on_spawn_button_pressed(species_name: String):
	# Clear any previous selections across both trees and plants
	_clear_all_selections()
	selected_tree_species = species_name
	is_tree_spawn_mode = true
	_update_selected_display()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	if plants_selection_popup and plants_selection_popup.visible:
		plants_selection_popup.hide()
	print("Selected tree species: ", species_name, " - Click on terrain to spawn, right click to cancel")

func _on_plant_spawn_button_pressed(plant_name: String):
	# Clear any previous selections across both trees and plants
	_clear_all_selections()
	selected_plant_species = plant_name
	is_plant_spawn_mode = true
	_update_selected_display()
	if plants_selection_popup and plants_selection_popup.visible:
		plants_selection_popup.hide()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()

func _on_mammal_spawn_button_pressed(mammal_name: String):
	# Clear any previous selections across all types
	_clear_all_selections()
	selected_mammal_species = mammal_name
	is_mammal_spawn_mode = true
	_update_selected_display()
	if mammals_selection_popup and mammals_selection_popup.visible:
		mammals_selection_popup.hide()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	if plants_selection_popup and plants_selection_popup.visible:
		plants_selection_popup.hide()

func _on_bird_spawn_button_pressed(bird_name: String):
	_clear_all_selections()
	selected_bird_species = bird_name
	is_bird_spawn_mode = true
	_update_selected_display()
	if birds_selection_popup and birds_selection_popup.visible:
		birds_selection_popup.hide()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	if plants_selection_popup and plants_selection_popup.visible:
		plants_selection_popup.hide()

func _on_fish_spawn_button_pressed(fish_name: String):
	_clear_all_selections()
	selected_fish_species = fish_name
	is_fish_spawn_mode = true
	_update_selected_display()
	if fish_selection_popup and fish_selection_popup.visible:
		fish_selection_popup.hide()
	if species_selection_popup and species_selection_popup.visible:
		species_selection_popup.hide()
	if plants_selection_popup and plants_selection_popup.visible:
		plants_selection_popup.hide()

func _compute_dynamic_spawn_cost(lf: LifeForm) -> int:
	var base_price: int = lf.price
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	var count: int = 0
	if tm and tm.has_method("get_total_living"):
		count = tm.get_total_living(lf.species_name)
	return base_price * (count + 1)

func _get_base_price_for(species_or_plant_name: String) -> int:
	# Try caches first
	if species_info_cache.has(species_or_plant_name):
		var info: Dictionary = species_info_cache[species_or_plant_name]
		return int(info.get("price", 0))
	if plants_info_cache.has(species_or_plant_name):
		var pinfo: Dictionary = plants_info_cache[species_or_plant_name]
		return int(pinfo.get("price", 0))
	if mammals_info_cache.has(species_or_plant_name):
		var minfo: Dictionary = mammals_info_cache[species_or_plant_name]
		return int(minfo.get("price", 0))
	# Fallback: load scene and read LifeForm.price using correct category and existence checks
	var paths: Array[String] = []
	# Prefer known category ordering to avoid logging invalid loads
	if mammals_list.has(species_or_plant_name):
		paths.append("res://Scenes/Animals/" + species_or_plant_name + ".tscn")
	elif plants_list.has(species_or_plant_name):
		paths.append("res://Scenes/SmallPlants/" + species_or_plant_name + ".tscn")
	else:
		# Default to tree if in species list; otherwise try all categories safely
		if species_list.has(species_or_plant_name):
			paths.append("res://Scenes/Trees/" + species_or_plant_name + ".tscn")
		else:
			paths.append("res://Scenes/Trees/" + species_or_plant_name + ".tscn")
			paths.append("res://Scenes/SmallPlants/" + species_or_plant_name + ".tscn")
			paths.append("res://Scenes/Animals/" + species_or_plant_name + ".tscn")
	for p in paths:
		if ResourceLoader.exists(p):
			var scene: PackedScene = load(p)
			if scene:
				var inst = scene.instantiate()
				if inst is LifeForm:
					var price_val: int = (inst as LifeForm).price
					inst.queue_free()
					return price_val
				if inst:
					inst.queue_free()
	return 0

func _try_inspect_entity_at_mouse_position(mouse_pos: Vector2):
	if not camera:
		return
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Target tree layer (3) and small plant/mammal inspect layer (4)
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
			return
		var mammal = _find_mammal_in_hierarchy(clicked_node)
		if mammal:
			_show_mammal_info(mammal, mouse_pos)
			return
		var bird = _find_bird_in_hierarchy(clicked_node)
		if bird:
			_show_bird_info(bird, mouse_pos)
		var fish = _find_fish_in_hierarchy(clicked_node)
		if fish:
			_show_fish_info(fish, mouse_pos)

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

func _find_mammal_in_hierarchy(node: Node) -> Mammal:
	if node is Mammal:
		return node as Mammal
	var current = node
	while current:
		if current is Mammal:
			return current as Mammal
		current = current.get_parent()
	return null

func _find_bird_in_hierarchy(node: Node) -> Bird:
	if node is Bird:
		return node as Bird
	var current = node
	while current:
		if current is Bird:
			return current as Bird
		current = current.get_parent()
	return null

func _find_fish_in_hierarchy(node: Node) -> Fish:
	if node is Fish:
		return node as Fish
	var current = node
	while current:
		if current is Fish:
			return current as Fish
		current = current.get_parent()
	return null

func _format_mammal_info(m: Mammal) -> String:
	var age_text = "%.1f / %.1f days" % [m.current_age, m.max_age]
	var health_text = "%d / %d HP" % [m.current_hp, m.max_hp]
	var info = "[b]%s[/b]\n\n" % m.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	var mstate_nice := "Unknown"
	if m.has_method("get_state_display_name"):
		mstate_nice = m.get_state_display_name()
	info += "[b]State:[/b] %s\n" % [mstate_nice]
	info += "[b]Walk Speed:[/b] %.1f m/s | [b]Vision:[/b] %.1f m\n" % [m.walk_speed, m.vision_range]
	info += "[b]Diet:[/b] " + ", ".join(m.get_preferred_diet())
	return info

func _format_bird_info(b: Bird) -> String:
	var age_text = "%.1f / %.1f days" % [b.current_age, b.max_age]
	var health_text = "%d / %d HP" % [b.current_hp, b.max_hp]
	var info = "[b]%s[/b]\n\n" % b.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	var bstate_nice := "Unknown"
	if b.has_method("get_state_display_name"):
		bstate_nice = b.get_state_display_name()
	info += "[b]State:[/b] %s\n" % [bstate_nice]
	info += "[b]Fly Speed:[/b] %.1f m/s | [b]Vision:[/b] %.1f m\n" % [b.fly_speed, b.vision_range]
	info += "[b]Diet:[/b] " + ", ".join(b.get_preferred_diet())
	return info

func _format_fish_info(f: Fish) -> String:
	var age_text = "%.1f / %.1f days" % [f.current_age, f.max_age]
	var health_text = "%d / %d HP" % [f.current_hp, f.max_hp]
	var info = "[b]%s[/b]\n\n" % f.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	var fstate_nice := "Unknown"
	if f.has_method("get_state_display_name"):
		fstate_nice = f.get_state_display_name()
	info += "[b]State:[/b] %s\n" % [fstate_nice]
	info += "[b]Swim Speed:[/b] %.1f m/s | [b]Vision:[/b] %.1f m\n" % [f.swim_speed, f.vision_range]
	info += "[b]Diet:[/b] " + ", ".join(f.get_preferred_diet())
	return info

func _show_mammal_info(m: Mammal, mouse_pos: Vector2):
	if not tree_info_popup or not tree_info_label:
		return
	currently_inspected_mammal = m
	var popup_pos = mouse_pos + Vector2(20, -tree_info_popup.size.y - 20)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + tree_info_popup.size.x > screen_size.x:
		popup_pos.x = screen_size.x - tree_info_popup.size.x - 10
	if popup_pos.y < 0:
		popup_pos.y = mouse_pos.y + 20
	tree_info_label.text = _format_mammal_info(m)
	tree_info_popup.position = popup_pos
	tree_info_popup.popup()
	if popup_update_timer:
		popup_update_timer.start()

func _show_bird_info(b: Bird, mouse_pos: Vector2):
	if not tree_info_popup or not tree_info_label:
		return
	currently_inspected_bird = b
	var popup_pos = mouse_pos + Vector2(20, -tree_info_popup.size.y - 20)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + tree_info_popup.size.x > screen_size.x:
		popup_pos.x = screen_size.x - tree_info_popup.size.x - 10
	if popup_pos.y < 0:
		popup_pos.y = mouse_pos.y + 20
	tree_info_label.text = _format_bird_info(b)
	tree_info_popup.position = popup_pos
	tree_info_popup.popup()
	if popup_update_timer:
		popup_update_timer.start()

func _show_fish_info(f: Fish, mouse_pos: Vector2):
	if not tree_info_popup or not tree_info_label:
		return
	currently_inspected_fish = f
	var popup_pos = mouse_pos + Vector2(20, -tree_info_popup.size.y - 20)
	var screen_size = get_viewport().get_visible_rect().size
	if popup_pos.x + tree_info_popup.size.x > screen_size.x:
		popup_pos.x = screen_size.x - tree_info_popup.size.x - 10
	if popup_pos.y < 0:
		popup_pos.y = mouse_pos.y + 20
	tree_info_label.text = _format_fish_info(f)
	tree_info_popup.position = popup_pos
	tree_info_popup.popup()
	if popup_update_timer:
		popup_update_timer.start()

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
	var health_text = "%d / %d HP" % [p.current_hp, p.max_hp]
	var actual_altitude = p.global_position.y
	var min_altitude = p.min_viable_altitude
	var max_altitude = p.max_viable_altitude
	var actual_altitude_text = "%.1f m" % [actual_altitude]
	var altitude_range_text = "%.1f/%.1f m" % [min_altitude, max_altitude]
	var info = "[b]%s[/b]\n\n" % p.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	info += "[b]Current Altitude:[/b] %s\n" % actual_altitude_text
	info += "[b]Altitude Range (Min/Max):[/b] %s" % altitude_range_text
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
	var health_text = "%d / %d HP" % [tree.current_hp, tree.max_hp]
	var growth_progress_text = "%.1f%%" % (tree.growth_progress / tree.max_growth_progress * 100.0)
	var actual_altitude = tree.global_position.y
	var min_altitude = tree.min_viable_altitude
	var max_altitude = tree.max_viable_altitude
	var actual_altitude_text = "%.1f m" % [actual_altitude]
	var altitude_range_text = "%.1f/%.1f m" % [min_altitude, max_altitude]
	var info = "[b]%s[/b]\n\n" % tree.species_name
	info += "[b]Age:[/b] %s\n" % age_text
	info += "[b]Health:[/b] %s\n" % health_text
	info += "[b]State:[/b] %s\n" % tree.get_state_name()
	info += "[b]Growth Progress:[/b] %s\n" % growth_progress_text
	info += "[b]Current Altitude:[/b] %s\n" % actual_altitude_text
	info += "[b]Altitude Range (Min/Max):[/b] %s" % altitude_range_text
	return info

func _update_popup_info():
	if currently_inspected_tree and tree_info_label and tree_info_popup and tree_info_popup.visible:
		var info_text = _format_tree_info(currently_inspected_tree)
		tree_info_label.text = info_text
	elif currently_inspected_plant and tree_info_label and tree_info_popup and tree_info_popup.visible:
		tree_info_label.text = _format_smallplant_info(currently_inspected_plant)
	elif currently_inspected_mammal and tree_info_label and tree_info_popup and tree_info_popup.visible:
		tree_info_label.text = _format_mammal_info(currently_inspected_mammal)
	elif currently_inspected_bird and tree_info_label and tree_info_popup and tree_info_popup.visible:
		tree_info_label.text = _format_bird_info(currently_inspected_bird)
	elif currently_inspected_fish and tree_info_label and tree_info_popup and tree_info_popup.visible:
		tree_info_label.text = _format_fish_info(currently_inspected_fish)

func _on_popup_hide():
	currently_inspected_tree = null
	currently_inspected_plant = null
	currently_inspected_mammal = null
	currently_inspected_bird = null
	currently_inspected_fish = null
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
	if birds_selection_popup and birds_selection_popup.visible:
		var birds_popup_rect = birds_selection_popup.get_visible_rect()
		if birds_popup_rect.has_point(mouse_position):
			return true
	if fish_selection_popup and fish_selection_popup.visible:
		var fish_popup_rect = fish_selection_popup.get_visible_rect()
		if fish_popup_rect.has_point(mouse_position):
			return true
	return false
