# WorldScene.gd
# Main script for the world scene to initialize the time management system
extends Node3D

func _ready():
	# Create and add TimeManager to the scene
	var time_manager = preload("res://Scripts/TimeManager.gd").new()
	time_manager.name = "TimeManager"
	add_child(time_manager)
	
	print("TimeManager added to world scene")
