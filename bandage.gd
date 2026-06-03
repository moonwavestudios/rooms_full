extends Area3D

var give_health = 25

func _ready() -> void:
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)

func _on_interacted(interactor: Node) -> void:
	interactor.on_bandage_interacted(self)
