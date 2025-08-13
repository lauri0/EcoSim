extends Panel

@onready var credits_label: Label = find_child("CreditsLabel", true, false)
@onready var revenue_label: Label = find_child("RevenueLabel", true, false)
@onready var no1_animal_label: Label = find_child("No1AnimalLabel", true, false)
@onready var no2_animal_label: Label = find_child("No2AnimalLabel", true, false)
@onready var no3_animal_label: Label = find_child("No3AnimalLabel", true, false)
@onready var no4_animal_label: Label = find_child("No4AnimalLabel", true, false)
@onready var no5_animal_label: Label = find_child("No5AnimalLabel", true, false)
@onready var no1_plant_label: Label = find_child("No1PlantLabel", true, false)
@onready var no2_plant_label: Label = find_child("No2PlantLabel", true, false)
@onready var no3_plant_label: Label = find_child("No3PlantLabel", true, false)
@onready var no4_plant_label: Label = find_child("No4PlantLabel", true, false)
@onready var no5_plant_label: Label = find_child("No5PlantLabel", true, false)

var credits: int = 1000
var revenue: int = 0

# Per-species finance tracking
# Dictionaries map species_name -> {"revenue": int, "expenses": int}
var animal_finance: Dictionary = {}
var plant_finance: Dictionary = {}

func _ready():
	_update_labels()
	_update_top5_labels()

func _update_labels():
	if credits_label:
		credits_label.text = "Credits: %d" % credits
	if revenue_label:
		revenue_label.text = "Revenue: %d" % revenue
	_update_top5_labels()

func _format_finance_line(species: String, rec: Dictionary) -> String:
	var rev: int = int(rec.get("revenue", 0))
	var cost: int = int(rec.get("expenses", 0))
	var prof: int = rev - cost
	return "%s: %d - %d (%d)" % [species, rev, cost, prof]

func _update_top5_labels():
	# Sort by revenue descending
	var animal_entries: Array = []
	for k in animal_finance.keys():
		animal_entries.append([k, animal_finance[k]])
	animal_entries.sort_custom(Callable(self, "_compare_by_revenue_desc"))

	var plant_entries: Array = []
	for k in plant_finance.keys():
		plant_entries.append([k, plant_finance[k]])
	plant_entries.sort_custom(Callable(self, "_compare_by_revenue_desc"))

	_fill_top5_labels(animal_entries, [no1_animal_label, no2_animal_label, no3_animal_label, no4_animal_label, no5_animal_label])
	_fill_top5_labels(plant_entries, [no1_plant_label, no2_plant_label, no3_plant_label, no4_plant_label, no5_plant_label])

func _compare_by_revenue_desc(a, b) -> bool:
	return int(a[1].get("revenue", 0)) > int(b[1].get("revenue", 0))

func _fill_top5_labels(entries: Array, labels: Array) -> void:
	for i in range(5):
		var lbl: Label = labels[i] if i < labels.size() else null
		if not lbl:
			continue
		if i < entries.size():
			var pair = entries[i]
			var s: String = String(pair[0])
			var rec: Dictionary = pair[1]
			lbl.text = _format_finance_line(s, rec)
		else:
			lbl.text = ""

func try_spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if credits >= amount:
		credits -= amount
		_update_labels()
		return true
	return false

func add_revenue(amount: int) -> void:
	if amount <= 0:
		return
	revenue += amount
	_update_labels()

func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	credits += amount
	_update_labels()

func get_credits() -> int:
	return credits

func get_revenue() -> int:
	return revenue

# --------- Public API: per-species finance ---------
func add_species_revenue(species: String, amount: int, category: String) -> void:
	if amount <= 0 or species == "":
		return
	var table: Dictionary = animal_finance if category == "animal" else plant_finance
	var rec: Dictionary = table.get(species, {"revenue": 0, "expenses": 0})
	rec["revenue"] = int(rec.get("revenue", 0)) + amount
	table[species] = rec
	_update_top5_labels()

func add_species_expense(species: String, amount: int, category: String) -> void:
	if amount <= 0 or species == "":
		return
	var table: Dictionary = animal_finance if category == "animal" else plant_finance
	var rec: Dictionary = table.get(species, {"revenue": 0, "expenses": 0})
	rec["expenses"] = int(rec.get("expenses", 0)) + amount
	table[species] = rec
	_update_top5_labels()
