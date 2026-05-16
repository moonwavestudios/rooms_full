extends Area3D

@export var coins := 25

func _ready() -> void:
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)

func _on_interacted(interactor: Node) -> void:
	interactor.on_coin_interacted(self)
