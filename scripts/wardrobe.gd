extends StaticBody3D

var _occupant: Node = null

func _ready() -> void:
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)

func _on_interacted(interactor: Node) -> void:
	if not interactor.is_multiplayer_authority():
		return

	if _occupant != null and _occupant != interactor:
		return

	if not interactor.hidden:
		var inside_marker = get_node_or_null("InsideTeleport")
		var target_pos = inside_marker.global_position if inside_marker else get_node("MeshInstance3D").global_position
		interactor.global_position = target_pos
		interactor.hidden = true
		get_node("Camera3D").current = true
		interactor.wardrobe_timer = 0.0
		_occupant = interactor
	else:
		interactor.global_position = get_node("leaveTeleport").global_position
		interactor.hidden = false
		interactor.camera.current = true
		interactor.wardrobe_timer = 0.0
		_occupant = null
