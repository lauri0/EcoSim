extends Node
class_name LifeFormReproManager

# Tracks living lifeforms by a normalized species key (UI/species browser key)
# Key normalization removes spaces to match entries like "EuropeanHare".
var _species_to_lifeforms: Dictionary = {}

func _ready():
    # Listen to hourly updates to detect start-of-day
    var root = get_tree().current_scene
    var tm = root.find_child("TimeManager", true, false)
    if tm and tm.has_signal("time_updated"):
        tm.time_updated.connect(_on_time_updated)

func register_lifeform(lf: LifeForm) -> void:
    if not is_instance_valid(lf):
        return
    var key := _to_species_key(lf)
    if not _species_to_lifeforms.has(key):
        _species_to_lifeforms[key] = []
    var arr: Array = _species_to_lifeforms[key]
    if arr.has(lf):
        return
    arr.append(lf)

func unregister_lifeform(lf: LifeForm) -> void:
    var key := _to_species_key(lf)
    if _species_to_lifeforms.has(key):
        var arr: Array = _species_to_lifeforms[key]
        arr.erase(lf)
        if arr.is_empty():
            _species_to_lifeforms.erase(key)

func _to_species_key(lf: LifeForm) -> String:
    # Normalize to UI/browser key by removing spaces.
    return lf.species_name.replace(" ", "")

func _on_time_updated(_year: int, _season: String, hour: int) -> void:
    # Trigger at start of each in-game day
    if hour == 0:
        _perform_daily_reproduction()

func _perform_daily_reproduction() -> void:
    var root = get_tree().current_scene
    var tmgr = root.find_child("TreeManager", true, false)
    var terrain = root.find_child("Terrain", true, false)
    if not tmgr:
        return
    # For each species key with living individuals, spawn according to invested reproduction
    for key in _species_to_lifeforms.keys():
        var rpd: float = 0.0
        if tmgr.has_method("get_reproduction"):
            rpd = tmgr.get_reproduction(key)
        var births: int = int(floor(rpd))
        if births <= 0:
            continue
        var candidates: Array = []
        # Collect valid instances; registration might contain freed nodes
        var arr: Array = _species_to_lifeforms.get(key, [])
        for n in arr:
            if is_instance_valid(n):
                candidates.append(n)
        if candidates.is_empty():
            continue
        # Pick 2x births at random (or as many as population allows)
        var sample_size: int = min(births * 2, candidates.size())
        candidates.shuffle()
        var sampled: Array = candidates.slice(0, sample_size)
        # Sort by health descending
        sampled.sort_custom(func(a, b):
            var ha = (a as LifeForm).healthPercentage if a is LifeForm else 0.0
            var hb = (b as LifeForm).healthPercentage if b is LifeForm else 0.0
            return hb < ha
        )
        # Top half become parents
        var parents: Array = sampled.slice(0, int(ceil(sample_size * 0.5)))
        # Spawn near each parent up to the number of births
        var spawned: int = 0
        for p in parents:
            if spawned >= births:
                break
            if not is_instance_valid(p):
                continue
            var plf := p as LifeForm
            if not plf:
                continue
            if plf.healthPercentage < 0.5:
                continue
            var pos := _pick_spawn_near(plf, terrain)
            _spawn_same_species(plf, key, pos, tmgr, terrain)
            spawned += 1

func _pick_spawn_near(plf: LifeForm, terrain: Node) -> Vector3:
    var angle = randf() * TAU
    var dist = randf_range(plf.repro_radius * 0.25, plf.repro_radius)
    var offset = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
    var base = plf.global_position + offset
    if terrain and terrain.has_method("get_height"):
        base.y = terrain.get_height(base.x, base.z)
    return base

func _spawn_same_species(parent: LifeForm, species_key: String, pos: Vector3, tmgr: Node, terrain: Node) -> void:
    # Trees delegate to TreeManager tree spawn
    if parent is TreeBase:
        if tmgr.has_method("request_tree_spawn"):
            tmgr.request_tree_spawn(species_key, pos)
        return
    # Small plants delegate to TreeManager small plant spawn
    if parent is SmallPlant:
        if tmgr.has_method("request_smallplant_spawn"):
            tmgr.request_smallplant_spawn(species_key, pos)
        return
    # Animals: instantiate their scene directly (Scenes/Animals/<key>.tscn)
    var scene_path = "res://Scenes/Animals/%s.tscn" % species_key
    var packed: PackedScene = load(scene_path)
    if not packed:
        return
    # Optional: validate bounds/spacing using existing helper
    if tmgr.has_method("can_spawn_plant_at"):
        if not tmgr.can_spawn_plant_at(packed, pos):
            return
    var parent_node: Node = terrain.get_parent() if terrain else get_tree().current_scene
    if not is_instance_valid(parent_node):
        parent_node = get_tree().current_scene
    var inst = packed.instantiate()
    parent_node.add_child(inst)
    # Snap to ground height
    if terrain and terrain.has_method("get_height"):
        pos.y = terrain.get_height(pos.x, pos.z)
    inst.global_position = pos
    # Random yaw
    if inst is Node3D:
        (inst as Node3D).rotation.y = randf() * TAU


