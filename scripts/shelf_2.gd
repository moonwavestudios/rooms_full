extends MeshInstance3D

@export var proximity_prompt: Area3D
@export var door: Node
@export var marker: Node

func _ready() -> void:
	if proximity_prompt:
		proximity_prompt.prompt_triggered.connect(_on_prompt_triggered)

func _on_prompt_triggered(_interactor: Node) -> void:
	rpc("sync_open")

@rpc("any_peer", "call_local", "reliable")
func sync_open() -> void:
	$"..".get_node("Open").play()
	var target_position = marker.global_position
	proximity_prompt.set_enabled(false)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(door, "global_position", target_position, 0.5)
	await tween.finished
