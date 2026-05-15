extends StaticBody3D

@onready var proximity_prompt = $ProximityPrompt

func _ready() -> void:
	if proximity_prompt:
		proximity_prompt.prompt_triggered.connect(_on_prompt_triggered)

func _on_prompt_triggered(_interactor: Node) -> void:
	rpc("sync_open")

@rpc("any_peer", "call_local", "reliable")
func sync_open() -> void:
	get_node("Open").play()
	var shelf_door = get_node("Shelfdoor")
	var target_position = get_node("Marker3D").global_position
	$ProximityPrompt.set_enabled(false)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(shelf_door, "global_position", target_position, 0.5)
	await tween.finished
