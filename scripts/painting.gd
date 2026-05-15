extends StaticBody3D

@export var paintingTitle = "Test"
@export var image: Texture2D

func _ready() -> void:
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)

func _on_interacted(interactor: Node) -> void:
	print(paintingTitle)
