# MenuBar.gd
extends Panel

@onready var exit_button = $MenuBar/ExitButton

func _ready():
	exit_button.pressed.connect(_on_exit_pressed)

func _on_exit_pressed() -> void:
	get_tree().quit()
