# MenuBar.gd
extends Panel

@onready var exit_button = $BottomMenuBar/ExitButton
# Side Trees button logic has been moved to SidePanel.gd
# Optional label to show selected species - add a Label node as child of BottomMenuBar named "SelectedLabel"
@onready var selected_label: Label = $BottomMenuBar/SelectedLabel if has_node("BottomMenuBar/SelectedLabel") else null
# Date label to show current time
@onready var date_label: Label = $BottomMenuBar/DateLabel if has_node("BottomMenuBar/DateLabel") else null
# Speed label to show current speed
@onready var speed_label: Label = $BottomMenuBar/SpeedLabel if has_node("BottomMenuBar/SpeedLabel") else null
@onready var fps_label: Label = $BottomMenuBar/FPSLabel if has_node("BottomMenuBar/FPSLabel") else null

# Speed control buttons
@onready var speed_0x_button: Button = get_node("BottomMenuBar/0XButton") if has_node("BottomMenuBar/0XButton") else null
@onready var speed_1x_button: Button = get_node("BottomMenuBar/1XButton") if has_node("BottomMenuBar/1XButton") else null
@onready var speed_2x_button: Button = get_node("BottomMenuBar/2XButton") if has_node("BottomMenuBar/2XButton") else null
@onready var speed_5x_button: Button = get_node("BottomMenuBar/5XButton") if has_node("BottomMenuBar/5XButton") else null
@onready var speed_10x_button: Button = get_node("BottomMenuBar/10XButton") if has_node("BottomMenuBar/10XButton") else null

# Tree and species selection logic moved to SidePanel.gd

# Speed control state
var current_time_scale: float = 1.0

# World references and water logic moved to SidePanel.gd

func _ready():
	exit_button.pressed.connect(_on_exit_pressed)
	# Connect speed control buttons
	_connect_speed_buttons()
	# Initialize FPS label immediately
	_update_fps_label()

var _fps_accumulator: float = 0.0
var _fps_update_interval: float = 0.25

func _process(delta: float) -> void:
	_fps_accumulator += delta
	if _fps_accumulator >= _fps_update_interval:
		_fps_accumulator = 0.0
		_update_fps_label()

func _on_exit_pressed() -> void:
	get_tree().quit()

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

func _update_fps_label():
	if fps_label:
		var fps = int(Engine.get_frames_per_second())
		fps_label.text = "FPS: " + str(fps)

## UI hit-testing for trees moved to SidePanel.gd
