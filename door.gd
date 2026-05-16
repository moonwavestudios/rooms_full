extends StaticBody3D

@export var open = false
@export var locked = false
@export var is_side_door = false

func _ready():
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)

func _on_interacted(interactor: Node) -> void:
	try_open(interactor)

func try_open(interactor: Node) -> void:
	if open:
		return
	if locked:
		if not interactor.player_has_key():
			$LockedSound.play()
			$ProximityPrompt._activation_count = 0
			return
		interactor.consume_key()
		locked = false
	rpc("sync_open_door")
	if not is_side_door:
		interactor.on_room_advanced(global_position)

@rpc("any_peer", "call_local", "reliable")
func sync_open_door() -> void:
	_open_door()

func _open_door() -> void:
	open = true
	$CollisionShape3D.disabled = true
	$OpenSound.play()
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position", global_position + Vector3(0, 3.0, 0), 0.5)
	if not is_side_door and multiplayer.is_server():
		var rooms_node = get_tree().current_scene.get_node("Game").get_node("Rooms")
		rooms_node.generate_room(get_parent().get_parent())
	await tween.finished
