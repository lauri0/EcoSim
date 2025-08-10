extends "res://Scripts/BerryBush.gd"
class_name Lingonberry

@export var bush_scale: float = 0.9

func _ready():
    species_name = "Lingonberry"
    berry_color = Color(0.8, 0.0, 0.0)  # red berries
    super._ready()

