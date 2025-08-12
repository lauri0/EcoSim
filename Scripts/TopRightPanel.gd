extends Panel

@onready var credits_label: Label = find_child("CreditsLabel", true, false)
@onready var revenue_label: Label = find_child("RevenueLabel", true, false)

var credits: int = 1000
var revenue: int = 0

func _ready():
	_update_labels()

func _update_labels():
	if credits_label:
		credits_label.text = "Credits: %d" % credits
	if revenue_label:
		revenue_label.text = "Revenue: %d" % revenue

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
