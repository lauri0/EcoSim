extends Node3D
class_name TreeBase

@export var species_name:          String = "Alder"
@export var ideal_altitude:        float = 10.0
@export var min_viable_altitude:   float = 0.0
@export var max_viable_altitude:   float = 50.0
## The radius in which this tree blocks other trees from spawning
@export var blocking_radius:       float = 5.0
## The radius which this tree needs to be free in order to spawn
@export var needs_free_radius:     float = 6.0
## Time (s) that it takes for the tree to mature given 100% health
@export var ideal_growth_time:     float = 60.0
@export var max_age:               float = 300.0
## Time (s) that it takes for the tree to reproduce again given 100% health
@export var ideal_repro_interval:  float = 30.0
## Used to decide how much health damage intruding other trees deal to the tree
## So a small tree intruding into teh needs_free_radius of a big tree won't affect the big tree's health much,
## but vice versa the small tree would be affected a lot
@export var adult_size_factor:     float = 10.0

var healthPercentage:              float = 0.0
var growthPercentage:              float = 0.0
var current_age:                   float = 0.0
var time_until_next_repro_check:   float = 0.0

func _ready():
	# start your timers, etc.
	time_until_next_repro_check = ideal_repro_interval

func _process(delta):
	current_age += delta
	time_until_next_repro_check -= delta
	if time_until_next_repro_check <= 0.0:
		_try_reproduce()
		time_until_next_repro_check = ideal_repro_interval

func _try_reproduce():
	# check altitude, age, maybe spawn a new TreeBase instance…
	pass
