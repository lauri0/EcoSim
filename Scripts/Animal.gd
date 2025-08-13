extends LifeForm
class_name Animal

# Movement parameters (units per second)
@export var walk_speed: float = 2.0
@export var swim_speed: float = 1.5
@export var fly_speed: float = 0.0

# Perception
@export var vision_range: float = 20.0

# Daily routine (hours in range 0..24)
@export var sleep_time: float = 22.0
@export var wake_hour: float = 6.0

# Diet preferences: ordered list of class_name strings, e.g., ["Grass", "SmallPlant"].
# Consumers should resolve these names to actual types at runtime.
@export var diet: Array[String] = []

# Eating multiplier for rewards
@export var eatPointsMult: float = 1.0

# Animation directory containing species-specific animations (GLB files, one per action)
@export var animation_dir: String = ""

# Runtime per-day eating progress
var _eaten_today: int = 0
var _daily_target: int = 1
var _last_day_index: int = -1

# Optional helpers
func prefers_prey_of_type(type_name: String) -> bool:
	return diet.has(type_name)

func get_preferred_diet() -> Array[String]:
	return diet

# Find the nearest edible plant in range, based on class_name/species_name matching
func find_food_in_range(center: Vector3, search_range: float) -> Node3D:
	var tm = get_tree().current_scene.find_child("TreeManager", true, false)
	if tm and tm.has_method("get_plants_within"):
		var nearby = tm.get_plants_within(center, search_range)
		var best: Node3D = null
		var best_d2: float = INF
		for n in nearby:
			if not is_instance_valid(n):
				continue
			if not (n is SmallPlant):
				continue
			var sp = n as SmallPlant
			# Match diet by explicit class_name, species_name, or generic SmallPlant
			if diet.has(sp.get_class()) or diet.has(sp.species_name) or diet.has("SmallPlant"):
				var d2 = (sp.global_position - center).length_squared()
				if d2 < best_d2:
					best = sp
					best_d2 = d2
		return best
	return null

func _refresh_daily_target_if_needed() -> void:
	# Sync with TreeManager setting, and reset at day change
	var root = get_tree().current_scene
	var tm = root.find_child("TimeManager", true, false)
	if tm and tm.has_method("get_current_day"):
		var day_idx = tm.get_current_day()
		if day_idx != _last_day_index:
			_last_day_index = day_idx
			_eaten_today = 0
			_on_new_day()
	var trm = root.find_child("TreeManager", true, false)
	if trm and trm.has_method("get_eating_target"):
		# TreeManager keys are browser keys without spaces
		var key = species_name.replace(" ", "")
		_daily_target = trm.get_eating_target(key)
		if _daily_target <= 0:
			_daily_target = 1

func _has_met_daily_target() -> bool:
	return _eaten_today >= _daily_target

func _reward_for_eating(eaten: LifeForm) -> void:
	var root = get_tree().current_scene
	var top_right = root.find_child("TopRightPanel", true, false)
	var price_val: int = 0
	if eaten and eaten is LifeForm:
		price_val = (eaten as LifeForm).price
	var amount: int = int(round(eatPointsMult * float(price_val)))
	if amount <= 0:
		return
	if top_right and top_right.has_method("add_revenue"):
		top_right.add_revenue(amount)
	if top_right and top_right.has_method("add_credits"):
		top_right.add_credits(amount)
	# Track per-species revenue for both eater and eatee
	if top_right and top_right.has_method("add_species_revenue"):
		var eater_species: String = species_name
		var eater_cat: String = "animal"
		var eatee_species: String = eaten.species_name if eaten else ""
		var eatee_cat: String = "plant"
		if eaten is Animal:
			eatee_cat = "animal"
		elif eaten is Plant:
			eatee_cat = "plant"
		top_right.add_species_revenue(eater_species, amount, eater_cat)
		if eatee_species != "":
			top_right.add_species_revenue(eatee_species, amount, eatee_cat)

# Hook for subclasses: called when a new in-game day starts
func _on_new_day() -> void:
	pass
