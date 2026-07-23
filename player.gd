extends CharacterBody3D

const DEFAULT_SPEED := 10.0
const CROUCH_SPEED := 4.0
const SPRINT_SPEED := 16.0
const JUMP_VELOCITY := 4.5

const MAX_STAMINA := 100.0
const STAMINA_DRAIN := 25.0
const STAMINA_REGEN := 15.0
const STAMINA_SPRINT_MIN := 10.0

var SPEED := DEFAULT_SPEED

var CROUCH_CAMERA_HEIGHT := 0.5
var STAND_CAMERA_HEIGHT := 1.6

var health := 100
var max_health := 100

var being_killed := false
var is_crouching := false
var hidden := false
var teleporting := false
var CrucifixHeld := false

var wardrobe_timer := 0.0
const WARDROBE_SAFE_TIME := 5.0
const WARDROBE_MAX_TIME := 12.0

@export var void_y := -50.0
@export var respawn_position: Vector3

@onready var voice_player: AudioStreamPlayer3D = $VoicePlayer

var voice_capture: AudioEffectCapture
var voice_playback: AudioStreamGeneratorPlayback

const VOICE_PACKET_SIZE := 960

var inventory := ["", "", "", "", "", "", "", "", ""]
var selected_slot := 0

var item_renders := {
	"key":        "res://assets/card_render.png",
	"flashlight": "res://assets/flashlight_render.png",
	"pills":      "res://assets/pills_render.png",
	"crucifix": "res://icon.svg",
}

var item_scenes := {
	"pills":      preload("res://models/pills.tscn"),
	"flashlight": preload("res://models/flashlight.tscn"),
	"key":        preload("res://models/key.tscn"),
	"clicker":    preload("res://models/clicker/clicker.tscn"),
	"crucifix": preload("res://models/crucifix/crucifix.tscn"),
}

var sensitivity := 0.010
var batteries := 0
const max_batteries := 5
var coins := 0
var knobs := 0
var username := ""

var target_rotation := Vector3.ZERO
var smooth_rotation := Vector3.ZERO

@onready var glitch_layer := $GlitchLayer
@onready var camera := $Camera3D
@onready var raycast := $Camera3D/RayCast3D
@onready var UI := $Control
@onready var coinsLabel := $Control/GameUI/Coins/Label
@onready var coinsUI := $Control/GameUI/Coins
@onready var roomNumLabel := $Control/GameUI/Label2
@onready var DeafAlert := $Control/GameUI/DeafVignette
@onready var timer := $Timer
@onready var timerItem := $TimerItems
@onready var timerItemUse := $TimerItemsUse
@onready var healthUI := $Control/GameUI/health/Health
@onready var deathUI := $Control/GameUI/Death
@onready var item_holder := $items
@onready var shadow_overlay := $Camera3D/ShadowOverlay
@onready var anim_player := $AnimationPlayer
@onready var battery_Label := $Control/GameUI/BatteryAmount/Label
@onready var batteryUI := $Control/GameUI/BatteryAmount
@onready var hotbarUI := $Control/GameUI/Hotbar
@onready var pauseUI := $Control/Pause
@onready var shop := $Control/GameUI/shop
@onready var animationtree := $AnimationTree

var _anim_state_machine: AnimationNodeStateMachinePlayback

var roomNum = 1

const ANIM_BLEND_TABLE := {
	"flashlight": ["parameters/Blend2/blend_amount",       "parameters/flashlight_use/blend_amount"],
	"pills":      ["parameters/Blend2Again/blend_amount",  "parameters/pills take/blend_amount"],
	"key":        ["parameters/Blend2 2/blend_amount",     "parameters/keycard_use/blend_amount"],
	"remote":     ["parameters/Blend2 3/blend_amount",     ""],
}

var interact_handlers: Dictionary

func _build_interact_handlers():
	interact_handlers = {
		"item":       _interact_item,
		"battery":    _interact_battery,
		"ladder":     _interact_ladder,
	}

func _ready() -> void:
	add_to_group("interactors")
	_build_interact_handlers()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	camera.current = is_multiplayer_authority()
	coinsUI.visible = is_multiplayer_authority()
	batteryUI.visible = is_multiplayer_authority()

	STAND_CAMERA_HEIGHT = camera.position.y

	animationtree.active = true
	_anim_state_machine = animationtree["parameters/StateMachine/playback"]

	if username != "":
		print("Player loaded: ", username)
		
	_setup_voice_chat()

func _setup_voice_chat() -> void:
	if _is_singleplayer():
		return

	if is_multiplayer_authority():
		var bus_idx = AudioServer.get_bus_index("Voice")
		voice_capture = AudioServer.get_bus_effect(bus_idx, 0)

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 48000
	generator.buffer_length = 0.1

	voice_player.stream = generator
	voice_player.play()

	voice_playback = voice_player.get_stream_playback()

func _is_singleplayer() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer

func set_username(new_username: String) -> void:
	username = new_username
	$PlayerUser.text = username

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion:
		target_rotation.x -= event.relative.y * sensitivity
		target_rotation.y -= event.relative.x * sensitivity
		target_rotation.x = clamp(target_rotation.x, deg_to_rad(-80), deg_to_rad(80))

	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change_slot(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change_slot(-1)

func _change_slot(direction: int):
	selected_slot = (selected_slot + direction + inventory.size()) % inventory.size()
	update_held_item()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	_smooth_rotation(delta)
	_update_hud()
	_handle_health()
	_handle_gravity(delta)
	_handle_crouch_sprint(delta)
	_handle_wardrobe_timer(delta)
	_handle_camera_height(delta)
	_handle_void_fall()
	_handle_slot_input()
	_handle_use_input()
	_handle_interact_input()
	_handle_pause_input()
	_handle_movement(delta)
	_update_all_anim_blends()
	update_battery_ui()
	_process_voice_chat()

func _process_voice_chat() -> void:
	if not is_multiplayer_authority():
		return
	if _is_singleplayer():
		return
	if voice_capture == null:
		return
	var available := voice_capture.get_frames_available()
	if available < VOICE_PACKET_SIZE:
		return
	var frames := voice_capture.get_buffer(VOICE_PACKET_SIZE)
	send_voice.rpc(frames)

@rpc("unreliable", "any_peer")
func send_voice(frames: PackedVector2Array) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	for player in get_tree().get_nodes_in_group("interactors"):
		if player.get_multiplayer_authority() == sender_id:
			continue
		receive_voice.rpc_id(
			player.get_multiplayer_authority(),
			frames
		)

@rpc("authority", "unreliable")
func receive_voice(frames: PackedVector2Array) -> void:
	if voice_playback == null:
		return
	for frame in frames:
		voice_playback.push_frame(frame)

func _update_hud() -> void:
	coinsLabel.text = "$" + str(coins)
	battery_Label.text = str(batteries) + "/" + str(max_batteries)
	healthUI.value = health
	healthUI.max_value = max_health

	if data.rusher_spawned:
		DeafAlert.material.set_shader_parameter("active", true)
	else:
		DeafAlert.material.set_shader_parameter("active", false)

func _handle_health() -> void:
	if health <= 0 and not being_killed:
		deathUI.visible = true
		if coins > 0:
			knobs = int(coins / 2.5)

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

func _handle_crouch_sprint(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		is_crouching = true
		SPEED = CROUCH_SPEED
	else:
		is_crouching = false
		SPEED = DEFAULT_SPEED

func _handle_wardrobe_timer(delta: float) -> void:
	if hidden:
		wardrobe_timer += delta
	else:
		wardrobe_timer = 0.0

	var shadow_strength := 0.0
	if hidden and wardrobe_timer > WARDROBE_SAFE_TIME:
		shadow_strength = clamp(
			(wardrobe_timer - WARDROBE_SAFE_TIME) / (WARDROBE_MAX_TIME - WARDROBE_SAFE_TIME),
			0.0, 1.0
		)

	if shadow_overlay.material:
		shadow_overlay.material.set_shader_parameter("strength", shadow_strength)
	else:
		shadow_overlay.modulate.a = shadow_strength

func _spawn_someone() -> void:
	if roomNum > 7:
		if randi() % 5 == 0:
			print("test")

func _handle_camera_height(delta: float) -> void:
	var target_cam_height = CROUCH_CAMERA_HEIGHT if is_crouching else STAND_CAMERA_HEIGHT
	camera.position.y = lerp(camera.position.y, target_cam_height, delta * 10.0)

func _handle_void_fall() -> void:
	if global_position.y < void_y and not teleporting:
		teleporting = true
		start_void_teleport()

func _handle_slot_input() -> void:
	if Input.is_action_just_pressed("slot_1"):
		selected_slot = 0; update_held_item()
	elif Input.is_action_just_pressed("slot_2"):
		selected_slot = 1; update_held_item()
	elif Input.is_action_just_pressed("slot_3"):
		selected_slot = 2; update_held_item()

func _handle_use_input() -> void:
	if not Input.is_action_just_pressed("use"):
		return
	if not timerItem.is_stopped():
		return

	var item = inventory[selected_slot]
	if item == "":
		return

	match item:
		"pills":
			timerItem.start(2)
			SPEED = DEFAULT_SPEED * 2
			timerItemUse.start(0.15)
			animationtree["parameters/pills take/blend_amount"] = 1.0
			inventory[selected_slot] = ""
			update_held_item()

func _handle_interact_input() -> void:
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider is Area3D:
			var can_interact := interact_handlers.keys().any(func(g): return collider.is_in_group(g))
			UI.get_node("GameUI/Label").visible = can_interact
			if collider.is_in_group("eye_monster"):
				health -= 20
	else:
		UI.get_node("GameUI/Label").visible = false

	if Input.is_action_just_pressed("interact") and raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider is Area3D:
			try_interact(collider)

	if Input.is_action_just_pressed("drop"):
		_drop_current_item()

func _handle_pause_input() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		pauseUI.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	_handle_animation(direction)

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _handle_animation(direction: Vector3) -> void:
	if not _anim_state_machine:
		return
	var is_moving := direction.length() > 0.1
	if is_moving:
		_anim_state_machine.travel("test_run" if not is_crouching else "test_crouch_walk")
	else:
		_anim_state_machine.travel("test_idle" if not is_crouching else "test_crouch_idle")

func _update_all_anim_blends() -> void:
	var held = inventory[selected_slot]
	for item_name in ANIM_BLEND_TABLE:
		var params: Array = ANIM_BLEND_TABLE[item_name]
		var holding := float(held == item_name)
		if params[0] != "":
			animationtree[params[0]] = holding

func _set_use_blend(item_name: String, value: float) -> void:
	if ANIM_BLEND_TABLE.has(item_name):
		var use_param: String = ANIM_BLEND_TABLE[item_name][1]
		if use_param != "":
			animationtree[use_param] = value

func start_kill_sequence(killer: Node) -> void:
	if being_killed:
		return
	being_killed = true
	velocity = Vector3.ZERO

	if is_instance_valid(killer):
		killer.look_at(global_transform.origin, Vector3.UP)
		if killer.has_node("AnimationPlayer"):
			var killer_anim: AnimationPlayer = killer.get_node("AnimationPlayer")
			if killer_anim.has_animation("stalker/Stalker_mixamo_com"):
				killer_anim.play("stalker/Stalker_mixamo_com")
				await killer_anim.animation_finished
			else:
				await get_tree().create_timer(2.0).timeout
		else:
			await get_tree().create_timer(2.0).timeout

	if anim_player and anim_player.has_animation("test/stalker_death"):
		anim_player.play("test/stalker_death")
		await anim_player.animation_finished
	else:
		await get_tree().create_timer(1.0).timeout

	die()

func die() -> void:
	health = 0
	deathUI.visible = true

func update_held_item() -> void:
	for child in item_holder.get_children():
		child.queue_free()

	var item = inventory[selected_slot]
	if item == "" or not item_scenes.has(item):
		update_hotbar_ui()
		return
		
	if item == "crucifix":
		CrucifixHeld = true
	else:
		CrucifixHeld = false

	update_hotbar_ui()
	var item_instance = item_scenes[item].instantiate()
	item_holder.add_child(item_instance)
	item_instance.rotation_degrees = Vector3(0, 90, 0)
	
	var prompt = item_instance.get_node_or_null("ProximityPrompt")
	if prompt:
		prompt.set_enabled(false)

func _drop_current_item() -> void:
	var item = inventory[selected_slot]
	if item == "" or not item_scenes.has(item):
		return

	var drop_scene = item_scenes[item]
	var dropped = drop_scene.instantiate()
	get_tree().current_scene.add_child(dropped)
	
	dropped.global_position = global_position + (-global_transform.basis.z * 1.5) + Vector3(0, 0.5, 0)

	inventory[selected_slot] = ""
	update_held_item()

func update_hotbar_ui() -> void:
	for i in inventory.size():
		var slot = hotbarUI.get_node("HBoxContainer").get_node_or_null("slot" + str(i + 1))
		if not slot:
			continue
		var item = inventory[i]
		if item != "" and item_renders.has(item):
			slot.visible = true
			slot.texture = load(item_renders[item])
		else:
			slot.visible = false
		var battery_bar = slot.get_node_or_null("ProgressBar")
		if battery_bar:
			battery_bar.visible = false

func update_battery_ui() -> void:
	for i in inventory.size():
		var slot = hotbarUI.get_node("HBoxContainer").get_node_or_null("slot" + str(i + 1))
		if not slot:
			continue
		var battery_bar = slot.get_node_or_null("ProgressBar")
		if not battery_bar:
			continue
		if i != selected_slot:
			battery_bar.visible = false
			continue
		var item_instance: Node = item_holder.get_child(0) if item_holder.get_child_count() > 0 else null
		if item_instance and "battery" in item_instance:
			battery_bar.visible = true
			battery_bar.max_value = 100
			battery_bar.value = item_instance.battery
		else:
			battery_bar.visible = false

func try_interact(collider: Area3D) -> void:
	if not is_multiplayer_authority():
		return
	for group in interact_handlers.keys():
		if collider.is_in_group(group):
			interact_handlers[group].call(collider)
			return

func on_coin_interacted(collider: Area3D) -> void:
	if not is_multiplayer_authority():
		return
	var coin_path = get_path_to(collider)
	rpc("sync_coin_collection", coin_path, collider.coins)
	
func on_bandage_interacted(collider: Area3D) -> void:
	if not is_multiplayer_authority():
		return
	if health >= max_health:
		return
		
	var coin_path = get_path_to(collider)
	rpc("sync_bandage_collection", coin_path, collider.give_health)
	
func on_battery_interacted(collider: Area3D) -> void:
	if not is_multiplayer_authority():
		return
	var battery_path = get_path_to(collider)
	rpc("sync_battery_collection", battery_path)

@rpc("any_peer", "call_local", "reliable")
func sync_coin_collection(coin_path: NodePath, coin_value: int) -> void:
	var coin_node = get_node_or_null(coin_path)
	if coin_node and is_instance_valid(coin_node):
		if is_multiplayer_authority():
			coins += coin_value
			$coin.play()
		coin_node.queue_free()
		
@rpc("any_peer", "call_local", "reliable")
func sync_bandage_collection(coin_path: NodePath, coin_value: int) -> void:
	var coin_node = get_node_or_null(coin_path)
	if coin_node and is_instance_valid(coin_node):
		if is_multiplayer_authority():
			health = min(health + coin_value, max_health)
		coin_node.queue_free()
		
@rpc("any_peer", "call_local", "reliable")
func sync_battery_collection(coin_path: NodePath) -> void:
	var coin_node = get_node_or_null(coin_path)
	if coin_node and is_instance_valid(coin_node):
		if is_multiplayer_authority():
			batteries += 1
		coin_node.queue_free()
	
func _interact_fake_door(_collider) -> void:
	if not is_multiplayer_authority():
		return
	
	await get_tree().create_timer(2).timeout
	health -= 30

func on_room_advanced(new_respawn: Vector3) -> void:
	roomNum += 1
	_spawn_someone()
	respawn_position = new_respawn
	roomNumLabel.text = "Room: " + str(roomNum)
	roomNumLabel.visible = true
	timer.start(1)

func player_has_key() -> bool:
	return inventory.any(func(i): return i == "key")

func consume_key() -> void:
	for i in inventory.size():
		if inventory[i] == "key":
			inventory[i] = ""
			timerItemUse.start(0.15)
			_set_use_blend("key", 1.0)
			update_hotbar_ui()
			if i == selected_slot:
				update_held_item()
			return

func _interact_item(collider: Area3D) -> void:
	if not is_multiplayer_authority():
		return
	
	var item_name: String
	if collider.get_parent().has_meta("item_type"):
		item_name = collider.get_parent().get_meta("item_type")
	else:
		item_name = collider.get_parent().name.to_lower()
		push_warning("Item node '%s' has no item_type metadata — falling back to node name." % collider.get_parent().name)

	for i in inventory.size():
		if inventory[i] == "":
			inventory[i] = item_name
			update_hotbar_ui()
			rpc("sync_item_pickup", get_path_to(collider.get_parent()))
			if i == selected_slot:
				update_held_item()
			return

@rpc("any_peer", "call_local", "reliable")
func sync_item_pickup(item_path: NodePath) -> void:
	var item = get_node_or_null(item_path)
	if item and is_instance_valid(item):
		item.queue_free()

func _interact_ladder(collider: Area3D) -> void:
	if not is_multiplayer_authority():
		return
	var target_pos = collider.get_node("Teleport").global_position
	global_position = target_pos

func _interact_battery(collider) -> void:
	if batteries >= max_batteries:
		return
	rpc("sync_battery_pickup", get_path_to(collider))

@rpc("any_peer", "call_local", "reliable")
func sync_battery_pickup(battery_path: NodePath) -> void:
	var battery = get_node_or_null(battery_path)
	if battery and is_instance_valid(battery):
		if is_multiplayer_authority():
			batteries += 1
		battery.queue_free()

func start_void_teleport() -> void:
	if glitch_layer:
		glitch_layer.start_glitch()
	$glitch.play()
	health -= 30
	await get_tree().create_timer(0.5).timeout
	global_position = respawn_position
	velocity = Vector3.ZERO
	await get_tree().create_timer(0.2).timeout
	if glitch_layer:
		glitch_layer.stop_glitch()
	teleporting = false

func _smooth_rotation(delta: float) -> void:
	smooth_rotation = smooth_rotation.lerp(target_rotation, delta * 10.0)
	rotation.y = smooth_rotation.y
	camera.rotation.x = smooth_rotation.x

func _on_timer_timeout() -> void:
	roomNumLabel.visible = false

func _on_timer_items_timeout() -> void:
	SPEED = DEFAULT_SPEED

func _on_timer_item_use_timeout() -> void:
	var item = inventory[selected_slot]
	_set_use_blend(item, 0.0)
	_set_use_blend("pills", 0.0)
	_set_use_blend("key", 0.0)
