# WorldScene.gd
# Main script for the world scene to initialize the time management system
extends Node3D

func _ready():
	# Create and add TimeManager to the scene
	var time_manager = preload("res://Scripts/TimeManager.gd").new()
	time_manager.name = "TimeManager"
	add_child(time_manager)

	# Create and add TreeManager to the scene
	var tree_manager = preload("res://Scripts/TreeManager.gd").new()
	tree_manager.name = "TreeManager"
	add_child(tree_manager)

	# Create and add LifeFormReproManager
	var repro_manager = preload("res://Scripts/LifeFormReproManager.gd").new()
	repro_manager.name = "LifeFormReproManager"
	add_child(repro_manager)

	# Create and add WindManager to the scene
	var wind_manager = preload("res://Scripts/WindManager.gd").new()
	wind_manager.name = "WindManager"
	add_child(wind_manager)

	# Create and add NavManager for mammals
	var nav_manager = preload("res://Scripts/NavManager.gd").new()
	nav_manager.name = "NavManager"
	add_child(nav_manager)

	print("TimeManager, TreeManager, LifeFormReproManager, WindManager and NavManager added to world scene")
