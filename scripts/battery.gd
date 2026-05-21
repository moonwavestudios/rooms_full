extends Area3D

func _ready() -> void:
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)

func _on_interacted(interactor: Node) -> void:
	interactor.on_battery_interacted(self)
