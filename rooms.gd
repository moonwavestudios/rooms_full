extends Node3D

var LIGHT_BREAK_CHANCE := 0.2

const NORMAL_FLICKER_COUNT := 2
const NORMAL_FLICKER_INTERVAL := 0.08

const RUSH_FLICKER_TIME := 1.5
const RUSH_FLICKER_INTERVAL := 0.04

@onready var rng = get_node("../..").rng
@onready var mod_loader = get_node_or_null("/root/ModLoader")

var room_scenes: Array[PackedScene] = [
	preload("res://rooms/room_a.tscn"),
	preload("res://rooms/room_b.tscn"),
	preload("res://rooms/room_c.tscn"),
	preload("res://rooms/room_d.tscn"),
	preload("res://rooms/room_e.tscn"),
	preload("res://rooms/room_f.tscn"),
	preload("res://rooms/room_g.tscn"),
	preload("res://rooms/room_h.tscn"),
	preload("res://rooms/room_i.tscn"),
	preload("res://rooms/room_j.tscn"),
	preload("res://rooms/another_room.tscn"),
	preload("res://rooms/room_yes.tscn"),
	preload("res://rooms/room_1.tscn"),
	preload("res://rooms/collab_room.tscn"),
]

var specialRooms = {
	"Room 30": preload("res://rooms/room_30.tscn"),
	"Room 50": preload("res://rooms/room_50.tscn"),
}

var secret_rooms := [
	{
		"scene": preload("res://rooms/secret_room_a.tscn"),
		"chance": 0.01,
	},
	{
		"scene": preload("res://rooms/placeholder_room.tscn"),
		"chance": 0.1,
	},
]

var room_variants := [
	{
		"name": "Flesh Rooms",
		"min_rooms": 3,
		"max_rooms": 6,
		"spawn_chance": 0.15,
		"tags": ["flesh"],
		"rooms": [
			preload("res://rooms/variants/room_flesh_a.tscn"),
			preload("res://rooms/variants/room_flesh_b.tscn"),
		],
	},
]

var active_variant: Dictionary = {}
var variant_rooms_remaining := 0

var spawned_variants: Array[String] = []

var spawned_secret_rooms: Array[PackedScene] = []
var all_available_rooms: Array[PackedScene] = []

const MAX_ROOMS := 5

var roomNum := 1

var RushMonsters: Array[PackedScene] = [
	preload("res://monster.tscn"),
]

const STALKER_MONSTER_SCENE := preload("res://stalker.tscn")
const KEY_SCENE := preload("res://models/key.tscn")

const LOCKED_DOOR_CHANCE := 0.35

var active_rush = null
var active_stalker = null

const RUSH_COOLDOWN_ROOMS := 4
const RUSH_START_ROOM := 7
const RUSH_SPAWN_OFFSET := 3
const RUSH_SPAWN_CHANCE := 0.5

const STALKER_START_ROOM := 10
const STALKER_CHECK_INTERVAL := 3.0
const STALKER_NO_LOOK_DURATION := 8.0
const STALKER_SPAWN_DISTANCE := 15.0
const STALKER_SPAWN_CHANCE := 0.3

const DIFFICULTY_RAMP_START := 50
const DIFFICULTY_RAMP_END := 100

var time_since_stalker_check := 0.0
var player_not_looking_back_time := 0.0
var rooms_since_last_rush := RUSH_COOLDOWN_ROOMS
var has_seen_wardrobe := false

var generated_rooms = []

signal rush_spawned(rush_node: Node)
signal stalker_spawned(stalker_node: Node)
signal room_generated(room_node: Node, room_num: int)

func _ready():
	var spawn_room = $spawnroom_v2
	generated_rooms.append(spawn_room)
	_initialize_room_pool()

	if mod_loader and mod_loader.has_signal("all_mods_loaded"):
		mod_loader.all_mods_loaded.connect(_on_mods_loaded)

func _initialize_room_pool():
	all_available_rooms.clear()
	all_available_rooms.append_array(room_scenes)

	if mod_loader:
		var modded_rooms = mod_loader.get_all_room_scenes()
		if not modded_rooms.is_empty():
			all_available_rooms.append_array(modded_rooms)
			print("[MODDING] Added %d modded rooms. Total: %d" % [modded_rooms.size(), all_available_rooms.size()])

		var modded_monsters = mod_loader.get_all_monster_scenes()
		if not modded_monsters.is_empty():
			RushMonsters.append_array(modded_monsters)
			print("[MODDING] Added %d modded monsters." % modded_monsters.size())

func _on_mods_loaded():
	print("[MODDING] Mods loaded — reinitialising room pool.")
	_initialize_room_pool()

func _process(delta):
	if not multiplayer.is_server():
		return

	if roomNum >= STALKER_START_ROOM:
		time_since_stalker_check += delta
		if time_since_stalker_check >= STALKER_CHECK_INTERVAL:
			time_since_stalker_check = 0.0
			check_stalker_spawn()

	_update_difficulty()

func _update_difficulty():
	if roomNum < DIFFICULTY_RAMP_START:
		LIGHT_BREAK_CHANCE = 0.2
	elif roomNum >= DIFFICULTY_RAMP_END:
		LIGHT_BREAK_CHANCE = 1.0
	else:
		var t = float(roomNum - DIFFICULTY_RAMP_START) / float(DIFFICULTY_RAMP_END - DIFFICULTY_RAMP_START)
		LIGHT_BREAK_CHANCE = lerp(0.2, 1.0, t)

func check_stalker_spawn():
	if active_stalker != null and is_instance_valid(active_stalker):
		player_not_looking_back_time = 0.0
		return

	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var player = players[0]

	if is_player_looking_backward(player):
		player_not_looking_back_time = 0.0
	else:
		player_not_looking_back_time += STALKER_CHECK_INTERVAL

	if player_not_looking_back_time >= STALKER_NO_LOOK_DURATION:
		if seeded_randf() <= STALKER_SPAWN_CHANCE:
			spawn_stalker_monster(player)
			player_not_looking_back_time = 0.0

func is_player_looking_backward(player: Node) -> bool:
	var head: Node = null
	if player.has_node("Head"):
		head = player.get_node("Head")
	elif player.has_node("Camera3D"):
		head = player.get_node("Camera3D")
	else:
		return false

	var player_forward = -head.global_transform.basis.z.normalized()
	var look_dir = -head.global_transform.basis.z.normalized()
	var backward_dir = head.global_transform.basis.z.normalized()  # true backward
	return look_dir.dot(backward_dir) > 0.5  # within ~60° of looking directly behind

func spawn_stalker_monster(player: Node):
	if not multiplayer.is_server():
		return

	var stalker = STALKER_MONSTER_SCENE.instantiate()
	var player_head = player.get_node("Head") if player.has_node("Head") else player
	var backward_dir = player_head.global_transform.basis.z.normalized()
	var spawn_pos = player.global_transform.origin + (backward_dir * STALKER_SPAWN_DISTANCE)
	spawn_pos.y = player.global_transform.origin.y

	add_child(stalker)
	active_stalker = stalker
	stalker.global_transform.origin = spawn_pos

	print("Stalker spawned behind player at %s" % spawn_pos)
	emit_signal("stalker_spawned", stalker)

	rpc("sync_stalker_spawn", spawn_pos)

@rpc("authority", "call_local", "reliable")
func sync_stalker_spawn(spawn_position: Vector3):
	if multiplayer.is_server():
		return
	
	if active_stalker != null and is_instance_valid(active_stalker):
		return

	var stalker = STALKER_MONSTER_SCENE.instantiate()
	add_child(stalker)
	active_stalker = stalker
	stalker.global_transform.origin = spawn_position

func check_and_activate_variant():
	if variant_rooms_remaining > 0:
		return

	var eligible: Array = []
	for variant in room_variants:
		var name: String = variant.get("name", "Unknown")
		if not spawned_variants.has(name):
			eligible.append(variant)

	eligible.shuffle()

	for variant in eligible:
		if seeded_randf() <= float(variant.get("spawn_chance", 0.1)):
			active_variant = variant
			variant_rooms_remaining = rng.randi_range(
				int(variant.get("min_rooms", 3)),
				int(variant.get("max_rooms", 6))
			)
			spawned_variants.append(variant.get("name", "Unknown"))
			print("VARIANT ACTIVATED: %s for %d rooms" % [active_variant.get("name"), variant_rooms_remaining])
			break

func get_variant_room() -> PackedScene:
	if variant_rooms_remaining <= 0 or active_variant.is_empty():
		return null
	var pool: Array = active_variant.get("rooms", [])
	return seeded_pick_random(pool)

func get_room_scene_for_door(door_number: int) -> PackedScene:
	var key = "Room " + str(door_number)
	if specialRooms.has(key):
		return specialRooms[key]

	var variant_room = get_variant_room()
	if variant_room != null:
		variant_rooms_remaining -= 1
		if variant_rooms_remaining <= 0:
			print("VARIANT ENDED: %s" % active_variant.get("name", "Unknown"))
			active_variant = {}
		return variant_room

	check_and_activate_variant()

	variant_room = get_variant_room()
	if variant_room != null:
		variant_rooms_remaining -= 1
		return variant_room

	var secret = roll_secret_room()
	if secret != null:
		print("SECRET ROOM at door %d" % door_number)
		spawned_secret_rooms.append(secret)
		return secret

	if all_available_rooms.is_empty():
		push_error("all_available_rooms is empty — cannot pick a room!")
		return room_scenes[0]

	return seeded_pick_random(all_available_rooms)

func roll_secret_room() -> PackedScene:
	for entry in secret_rooms:
		if spawned_secret_rooms.has(entry["scene"]):
			continue
		if seeded_randf() <= float(entry["chance"]):
			return entry["scene"]
	return null

func generate_room(previous_room):
	if not multiplayer.is_server():
		return

	var next_door_number = roomNum + 1
	var room_scene = get_room_scene_for_door(next_door_number)
	if not room_scene:
		push_error("room_scene is null for door %d!" % next_door_number)
		return

	var new_room = room_scene.instantiate()
	var new_begin_pos = new_room.get_node("Begin_Pos") as MeshInstance3D
	var new_begin_local_offset = new_begin_pos.transform.origin

	add_child(new_room)

	var prev_end_pos = previous_room.get_node("End_Pos") as MeshInstance3D
	new_room.global_transform.basis = prev_end_pos.global_transform.basis
	var rotated_offset = new_room.global_transform.basis * new_begin_local_offset
	new_room.global_transform.origin = prev_end_pos.global_transform.origin - rotated_offset

	maybe_break_lights_normal(new_room)
	maybe_make_room_locked(new_room)

	generated_rooms.append(new_room)
	roomNum += 1

	if generated_rooms.size() > MAX_ROOMS:
		var old_room = generated_rooms[0]
		if is_instance_valid(old_room):
			old_room.queue_free()
		generated_rooms.remove_at(0)

	rooms_since_last_rush += 1

	if room_has_tag(new_room, "has_wardrobe"):
		has_seen_wardrobe = true

	if roomNum >= RUSH_START_ROOM:
		if has_seen_wardrobe:
			if rooms_since_last_rush >= RUSH_COOLDOWN_ROOMS:
				if generated_rooms.size() > RUSH_SPAWN_OFFSET:
					if seeded_randf() <= RUSH_SPAWN_CHANCE:
						spawn_rush_monster()
						rooms_since_last_rush = 0

	update_rush_target()

	emit_signal("room_generated", new_room, roomNum)

	var scene_index = get_room_scene_index(room_scene)
	var prev_room_path = get_path_to(previous_room)
	rpc("sync_room_generation", scene_index, prev_room_path, next_door_number)

func room_has_tag(room: Node, tag: String) -> bool:
	if room.has_meta("tags"):
		var tags = room.get_meta("tags")
		if tags is Array and tags.has(tag):
			return true

	if room.has_node("RoomTags"):
		var tag_node = room.get_node("RoomTags")
		if tag_node.get("tags") is Array and tag_node.tags.has(tag):
			return true

	match tag:
		"has_wardrobe":
			return room.has_node("Wardrobe")

	return false

func get_room_scene_index(scene: PackedScene) -> int:
	var variant_index = 30000
	for variant in room_variants:
		var variant_rooms: Array = variant.get("rooms", [])
		for i in range(variant_rooms.size()):
			if variant_rooms[i] == scene:
				return variant_index + i
		variant_index += 100

	for i in range(all_available_rooms.size()):
		if all_available_rooms[i] == scene:
			return i

	var special_index = 10000
	for key in specialRooms.keys():
		if specialRooms[key] == scene:
			return special_index
		special_index += 1

	var secret_index = 20000
	for entry in secret_rooms:
		if entry["scene"] == scene:
			return secret_index
		secret_index += 1

	return 0

func get_scene_from_index(index: int) -> PackedScene:
	if index < 10000:
		if index < all_available_rooms.size():
			return all_available_rooms[index]
	elif index < 20000:
		var special_index = index - 10000
		var keys = specialRooms.keys()
		if special_index < keys.size():
			return specialRooms[keys[special_index]]
	elif index < 30000:
		var secret_index = index - 20000
		if secret_index < secret_rooms.size():
			return secret_rooms[secret_index]["scene"]
	else:
		var variant_offset = index - 30000
		var current_offset = 0
		for variant in room_variants:
			var variant_rooms: Array = variant.get("rooms", [])
			var variant_size = variant_rooms.size()
			if variant_offset < current_offset + variant_size:
				return variant_rooms[variant_offset - current_offset]
			current_offset += 100

	if not all_available_rooms.is_empty():
		return all_available_rooms[0]
	return room_scenes[0]

@rpc("authority", "call_local", "reliable")
func sync_room_generation(scene_index: int, prev_room_path: NodePath, _door_number: int):
	if multiplayer.is_server():
		return

	var room_scene = get_scene_from_index(scene_index)
	var previous_room = get_node_or_null(prev_room_path)
	if not previous_room:
		push_error("Client: could not find previous room!")
		return

	var new_room = room_scene.instantiate()
	var new_begin_pos = new_room.get_node("Begin_Pos") as MeshInstance3D
	var new_begin_local_offset = new_begin_pos.transform.origin

	add_child(new_room)

	var prev_end_pos = previous_room.get_node("End_Pos") as MeshInstance3D
	new_room.global_transform.basis = prev_end_pos.global_transform.basis
	var rotated_offset = new_room.global_transform.basis * new_begin_local_offset
	new_room.global_transform.origin = prev_end_pos.global_transform.origin - rotated_offset

	generated_rooms.append(new_room)
	roomNum += 1

	if generated_rooms.size() > MAX_ROOMS:
		var old_room = generated_rooms[0]
		if is_instance_valid(old_room):
			old_room.queue_free()
		generated_rooms.remove_at(0)

func _collect_lights(node: Node, arr: Array):
	if node is Light3D:
		arr.append(node)
	for child in node.get_children():
		_collect_lights(child, arr)

func get_all_lights() -> Array[Light3D]:
	var lights: Array[Light3D] = []
	for room in generated_rooms:
		_collect_lights(room, lights)
	return lights

func maybe_break_lights_normal(room: Node):
	var lights: Array[Light3D] = []
	_collect_lights(room, lights)
	for light in lights:
		if seeded_randf() <= LIGHT_BREAK_CHANCE:
			flicker_n_times_then_break(light, NORMAL_FLICKER_COUNT, NORMAL_FLICKER_INTERVAL)

func flicker_n_times_then_break(light: Light3D, count: int, interval: float):
	if not is_instance_valid(light):
		return

	var timer := Timer.new()
	timer.wait_time = interval
	timer.one_shot = false
	timer.set_meta("light", light)
	timer.set_meta("original_energy", light.light_energy)
	timer.set_meta("flicks", 0)
	timer.set_meta("max_flicks", count * 2)

	add_child(timer)
	timer.timeout.connect(_on_normal_flicker_timer.bind(timer))
	timer.start()

func _on_normal_flicker_timer(timer: Timer):
	if not is_instance_valid(timer):
		return
	if not timer.has_meta("light"):
		timer.queue_free()
		return

	var light = timer.get_meta("light")
	if not is_instance_valid(light):
		timer.queue_free()
		return

	var original_energy: float = timer.get_meta("original_energy")
	var flicks: int = timer.get_meta("flicks")
	var max_flicks: int = timer.get_meta("max_flicks")

	light.light_energy = 0.0 if light.light_energy > 0.0 else original_energy
	flicks += 1
	timer.set_meta("flicks", flicks)

	if flicks >= max_flicks:
		if is_instance_valid(light):
			light.queue_free()
		timer.queue_free()

func flicker_lights_rush():
	var lights := get_all_lights()
	for light in lights:
		flicker_for_time_then_break(light, RUSH_FLICKER_TIME, RUSH_FLICKER_INTERVAL)
	rpc("sync_flicker_lights_rush")

@rpc("authority", "call_local", "reliable")
func sync_flicker_lights_rush():
	if multiplayer.is_server():
		return
	for light in get_all_lights():
		flicker_for_time_then_break(light, RUSH_FLICKER_TIME, RUSH_FLICKER_INTERVAL)

func flicker_for_time_then_break(light: Light3D, duration: float, interval: float):
	if not is_instance_valid(light):
		return

	var timer := Timer.new()
	timer.wait_time = interval
	timer.one_shot = false
	timer.set_meta("light", light)
	timer.set_meta("original_energy", light.light_energy)
	timer.set_meta("elapsed", 0.0)
	timer.set_meta("duration", duration)

	add_child(timer)
	timer.timeout.connect(_on_rush_flicker_timer.bind(timer))
	timer.start()

func _on_rush_flicker_timer(timer: Timer):
	if not is_instance_valid(timer):
		return
	if not timer.has_meta("light"):
		timer.queue_free()
		return

	var light = timer.get_meta("light")
	if not is_instance_valid(light):
		timer.queue_free()
		return

	var original_energy: float = timer.get_meta("original_energy")
	var elapsed: float = timer.get_meta("elapsed")
	var duration: float = timer.get_meta("duration")

	light.light_energy = original_energy * seeded_randf_range(0.0, 1.2)
	elapsed += timer.wait_time
	timer.set_meta("elapsed", elapsed)

	if elapsed >= duration:
		if is_instance_valid(light):
			light.queue_free()
		timer.queue_free()

func maybe_make_room_locked(room: Node):
	if not room.get_node("DoorSpawn").has_node("door"):
		return
	if seeded_randf() > LOCKED_DOOR_CHANCE:
		return

	var door = room.get_node("DoorSpawn").get_node("door")
	door.locked = true
	spawn_key_for_room(room)

	var door_path = get_path_to(door)
	rpc("sync_door_locked", door_path)

@rpc("authority", "call_local", "reliable")
func sync_door_locked(door_path: NodePath):
	if multiplayer.is_server():
		return
	var door = get_node_or_null(door_path)
	if door and is_instance_valid(door):
		door.locked = true

func spawn_key_for_room(room: Node):
	var spawn_points := []
	_collect_key_spawns(room, spawn_points)
	if spawn_points.is_empty():
		push_warning("Locked room has no KeySpawn points!")
		return

	var point = seeded_pick_random(spawn_points)
	var key = KEY_SCENE.instantiate()
	add_child(key)
	key.global_position = point.global_position
	rpc("sync_key_spawn", key.global_position)

@rpc("authority", "call_local", "reliable")
func sync_key_spawn(key_position: Vector3):
	if multiplayer.is_server():
		return
	var key = KEY_SCENE.instantiate()
	add_child(key)
	key.global_transform.origin = key_position

func _collect_key_spawns(node: Node, arr: Array):
	if node.name.begins_with("KeySpawn"):
		arr.append(node)
	for child in node.get_children():
		_collect_key_spawns(child, arr)

func spawn_rush_monster():
	if not multiplayer.is_server():
		return

	if RushMonsters.is_empty():
		push_error("RushMonsters pool is empty!")
		return

	var rush_index = rng.randi() % RushMonsters.size()
	var rush_scene := RushMonsters[rush_index]
	var rush = rush_scene.instantiate()

	var spawn_room: Node = null
	for i in range(generated_rooms.size() - 1 - RUSH_SPAWN_OFFSET, -1, -1):
		if room_has_tag(generated_rooms[i], "has_wardrobe"):
			spawn_room = generated_rooms[i]
			break

	if spawn_room == null:
		return

	var begin_pos = spawn_room.get_node("Begin_Pos") as Node3D
	add_child(rush)
	active_rush = rush
	flicker_lights_rush()

	rush.global_transform.origin = begin_pos.global_transform.origin + Vector3(0, 2, 0)

	emit_signal("rush_spawned", rush)

	rpc("sync_rush_spawn", rush.global_transform.origin, rush_index)

@rpc("authority", "call_local", "reliable")
func sync_rush_spawn(spawn_position: Vector3, rush_index: int):
	if multiplayer.is_server():
		return

	if rush_index < 0 or rush_index >= RushMonsters.size():
		rush_index = 0

	var rush = RushMonsters[rush_index].instantiate()
	add_child(rush)
	active_rush = rush
	rush.global_transform.origin = spawn_position

func update_rush_target():
	if active_rush == null:
		return
	if not is_instance_valid(active_rush):
		active_rush = null
		return
	var end_room = generated_rooms[generated_rooms.size() - 1]
	var end_pos = end_room.get_node("End_Pos") as Node3D
	active_rush.set("target_position", end_pos.global_transform.origin + Vector3(0, 2, 0))

func seeded_pick_random(array: Array):
	if array.is_empty():
		return null
	return array[rng.randi() % array.size()]

func seeded_randf() -> float:
	return rng.randf()

func seeded_randf_range(min_val: float, max_val: float) -> float:
	return rng.randf_range(min_val, max_val)

func get_debug_state() -> Dictionary:
	return {
		"roomNum": roomNum,
		"active_variant": active_variant.get("name", "none"),
		"variant_rooms_remaining": variant_rooms_remaining,
		"rooms_since_last_rush": rooms_since_last_rush,
		"stalker_no_look_time": player_not_looking_back_time,
		"light_break_chance": LIGHT_BREAK_CHANCE,
		"has_seen_wardrobe": has_seen_wardrobe,
		"rush_alive": active_rush != null and is_instance_valid(active_rush),
		"stalker_alive": active_stalker != null and is_instance_valid(active_stalker),
	}
