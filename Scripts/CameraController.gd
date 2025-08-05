extends Camera3D

@export var rotate_speed: float = 0.005
@export var pan_speed:    float = 0.4
@export var zoom_amount:  float = 5.0
@export var move_speed:   float = 100.0    # units per second
@export var terrain_clearance: float = 3.0  # minimum distance from terrain

var rotating: bool = false
var panning:  bool = false

# track yaw & pitch ourselves
var yaw:   float
var pitch: float

# Reference to terrain for collision checking
var terrain: MeshInstance3D

func _ready() -> void:
	yaw   = rotation.y
	pitch = rotation.x
	
	# Find terrain reference
	_find_terrain_reference()

func _find_terrain_reference():
	var root = get_tree().current_scene
	terrain = root.find_child("Terrain", true, false) as MeshInstance3D
	if not terrain:
		print("Warning: Terrain not found for camera collision!")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = event.pressed
			if rotating:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			panning = event.pressed

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_safe_translate(Vector3(0, 0, -zoom_amount))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_safe_translate(Vector3(0, 0,  zoom_amount))

	elif event is InputEventMouseMotion:
		if rotating:
			yaw   -= event.relative.x * rotate_speed
			pitch -= event.relative.y * rotate_speed
			pitch  = clamp(pitch, -PI/2, PI/2)
			rotation = Vector3(pitch, yaw, 0)

		elif panning:
			# side-to-side (flattened) & up/down panning
			var right = transform.basis.x
			right.y = 0; right = right.normalized()
			_safe_translate(right * -event.relative.x * pan_speed)
			_safe_translate(Vector3(0,1,0) * event.relative.y * pan_speed)

func _physics_process(delta: float) -> void:
	# Use physics process which uses unscaled delta time (unaffected by Engine.time_scale)
	# 1) Compute your horizontal "forward" (where camera is looking) and "right" vectors:
	var forward = -transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var right = transform.basis.x
	right.y = 0
	right = right.normalized()
	
	# 2) Accumulate movement on those axes:
	var motion = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		motion += forward
	if Input.is_key_pressed(KEY_S):
		motion -= forward
	if Input.is_key_pressed(KEY_D):
		motion += right
	if Input.is_key_pressed(KEY_A):
		motion -= right
	
	# 3) Apply it in world‐space so Y never changes:
	if motion != Vector3.ZERO:
		motion = motion.normalized() * move_speed * delta
		_safe_global_translate(motion)

func _safe_translate(offset: Vector3) -> void:
	if not terrain:
		translate(offset)
		return
		
	var new_position = global_position + transform.basis * offset
	var terrain_height = terrain.get_height(new_position.x, new_position.z)
	
	# Check if new position would be too close to terrain
	if new_position.y < terrain_height + terrain_clearance:
		# Clamp to minimum height above terrain
		new_position.y = terrain_height + terrain_clearance
	
	global_position = new_position

func _safe_global_translate(offset: Vector3) -> void:
	if not terrain:
		global_translate(offset)
		return
		
	var new_position = global_position + offset
	var terrain_height = terrain.get_height(new_position.x, new_position.z)
	
	# Check if new position would be too close to terrain
	if new_position.y < terrain_height + terrain_clearance:
		# Clamp to minimum height above terrain
		new_position.y = terrain_height + terrain_clearance
	
	global_position = new_position
