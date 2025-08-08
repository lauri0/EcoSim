# TimeManager.gd
extends Node

# Time configuration
var year_duration_seconds: float = 360.0  # 6 minutes = 1 year
var days_per_year: int = 4  # 4 seasons = 4 days
var hours_per_day: int = 24

# Current time tracking
var current_year: int = 1
var current_day: int = 0  # 0-3 (Spring, Summer, Autumn, Winter)
var current_hour: float = 12.0  # Start at noon

# Season names
var season_names: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]

# Light control
var directional_light: DirectionalLight3D
var base_light_energy: float = 0.4
var min_light_energy: float = 0.3  # Night time minimum
var max_light_energy: float = 0.9   # Day time maximum

# Time calculation helpers
var day_duration_seconds: float
var hour_duration_seconds: float

# Signals for UI updates
signal time_updated(year: int, season: String, hour: int)
signal season_changed(season: String, winter_factor: float)

# References to world objects
var terrain_mesh: MeshInstance3D

func _ready():
	# Calculate time durations
	day_duration_seconds = year_duration_seconds / days_per_year  # 15 seconds per day
	hour_duration_seconds = day_duration_seconds / hours_per_day  # 0.625 seconds per hour
	
	# Find the directional light in the scene
	_find_directional_light()
	
	print("TimeManager initialized:")
	print("  Year duration: ", year_duration_seconds, " seconds")
	print("  Day duration: ", day_duration_seconds, " seconds") 
	print("  Hour duration: ", hour_duration_seconds, " seconds")
	
	# Connect to UI components (deferred to ensure everything is ready)
	_connect_to_ui.call_deferred()

func _find_directional_light():
	# Find the DirectionalLight3D in the scene tree
	var root = get_tree().current_scene
	directional_light = root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	terrain_mesh = root.find_child("Terrain", true, false) as MeshInstance3D
	
	if directional_light:
		base_light_energy = directional_light.light_energy
		print("Found DirectionalLight3D with base energy: ", base_light_energy)
	else:
		print("Warning: DirectionalLight3D not found in scene!")
	
	if terrain_mesh:
		print("Found Terrain mesh for winter effects")
	else:
		print("Warning: Terrain mesh not found in scene!")

# Removed _last_season as it's not needed for current implementation

func _process(delta):
	# Update current time
	current_hour += delta / hour_duration_seconds
	
	# Handle hour overflow (new day)
	if current_hour >= hours_per_day:
		current_hour = 0.0
		var old_day = current_day
		current_day += 1
		
		# Handle day overflow (new year)
		if current_day >= days_per_year:
			current_day = 0
			current_year += 1
			print("New year! Year ", current_year)
		
		# Check for season change
		if old_day != current_day:
			_on_season_changed()
	
	# Update lighting based on current time
	_update_lighting()
	
	# Update terrain winter effect (continuous updates for gradual transitions)
	_update_terrain_winter_effect()
	
	# Emit signal for UI updates (only emit when hour changes to avoid spam)
	var hour_int = int(current_hour)
	if hour_int != _last_emitted_hour:
		_last_emitted_hour = hour_int
		time_updated.emit(current_year, season_names[current_day], hour_int)

var _last_emitted_hour: int = -1

func _update_lighting():
	if not directional_light:
		return
	
	# Create asymmetric day-night cycle: 16 hours bright, 8 hours dark
	# Day period: 6:00 to 22:00 (16 hours)
	# Night period: 22:00 to 6:00 (8 hours)
	
	var time_factor: float
	
	if current_hour >= 5.0 and current_hour <= 21.0:
		# Daytime (5:00 to 21:00) - 16 hours
		# Use cosine curve centered on noon (13:00) with extended bright period
		var day_progress = (current_hour - 5.0) / 16.0  # 0 to 1 over the day
		var noon_centered = (day_progress - 0.5) * 2.0  # -1 to 1, centered on noon
		time_factor = cos(noon_centered * PI)  # Gentler curve for longer bright time
		time_factor = (time_factor + 1.0) / 2.0  # 0 to 1
		time_factor = pow(time_factor, 0.4)  # Softer falloff, keeps it brighter longer
	else:
		# Nighttime (21:00 to 5:00) - 8 hours
		# Keep lighting consistently low
		time_factor = 0.0
	
	# Map to light energy range
	var target_energy = min_light_energy + (max_light_energy - min_light_energy) * time_factor
	
	# Set the light energy
	directional_light.light_energy = target_energy

# Utility functions for getting current time info
func get_current_season() -> String:
	return season_names[current_day]

func get_current_winter_factor() -> float:
	if current_day != 3:  # Not winter
		return 0.0
	
	# During winter, calculate gradual transition based on time of day
	if current_hour <= 2.0:
		# Beginning of winter: transition from 0 to 1 (00:00 - 02:00)
		return clamp(current_hour / 2.0, 0.0, 1.0)
	elif current_hour >= 22.0:
		# End of winter: transition from 1 to 0 (22:00 - 00:00)
		return clamp((24.0 - current_hour) / 2.0, 0.0, 1.0)
	else:
		# Full winter during the middle hours
		return 1.0

func get_current_hour_int() -> int:
	return int(current_hour)

func get_current_hour() -> float:
	return current_hour

func get_current_year() -> int:
	return current_year

func get_formatted_time() -> String:
	var hour_int = int(current_hour)
	var season = season_names[current_day]
	return "%02d:00 %s Year %d" % [hour_int, season, current_year]

# Debug function to set time manually (useful for testing)
func set_time(year: int, day: int, hour: float):
	current_year = year
	current_day = clamp(day, 0, days_per_year - 1)
	current_hour = clamp(hour, 0.0, float(hours_per_day - 1))
	_update_lighting()
	time_updated.emit(current_year, season_names[current_day], int(current_hour))

# Debug function to speed up time (useful for testing)
func set_time_scale(scale: float):
	year_duration_seconds = 60.0 / scale  # Default 60 seconds, divided by scale
	day_duration_seconds = year_duration_seconds / days_per_year
	hour_duration_seconds = day_duration_seconds / hours_per_day
	print("Time scale set to ", scale, "x (", year_duration_seconds, " seconds per year)")

func _on_season_changed():
	var season_name = season_names[current_day]
	var winter_factor = 1.0 if current_day == 3 else 0.0  # Winter is day 3 (index 3)
	season_changed.emit(season_name, winter_factor)
	print("Season changed to: ", season_name, " (winter factor: ", winter_factor, ")")

func _update_terrain_winter_effect():
	if not terrain_mesh or not terrain_mesh.material_override:
		return
	
	var material = terrain_mesh.material_override as ShaderMaterial
	if material:
		var winter_factor = get_current_winter_factor()  # Use the gradual winter factor
		material.set_shader_parameter("winter_factor", winter_factor)

func _connect_to_ui():
	# Find UI components and connect to them
	var root = get_tree().current_scene
	var ui_panel = root.find_child("BottomPanel", true, false)
	
	if ui_panel and ui_panel.has_method("_on_time_updated"):
		# Connect our time_updated signal to the UI panel
		time_updated.connect(ui_panel._on_time_updated)
		print("TimeManager connected to BottomPanel")
		
		# Initialize the UI with current time
		ui_panel._on_time_updated(current_year, season_names[current_day], int(current_hour))
		
		# Initialize terrain winter effect
		_update_terrain_winter_effect()
	else:
		print("Warning: Could not find BottomPanel or _on_time_updated method!")
