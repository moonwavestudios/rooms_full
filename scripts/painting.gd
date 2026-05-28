extends StaticBody3D

@export var paintingTitle = "Test"
@export var image: Texture2D

func _ready() -> void:
	$ProximityPrompt.prompt_triggered.connect(_on_interacted)
	var mesh_instance = $Painting
	var material = mesh_instance.get_surface_override_material(3)
	if material == null:
		material = mesh_instance.mesh.surface_get_material(3)
	if material is StandardMaterial3D:
		material = material.duplicate()
		material.albedo_texture = image
		mesh_instance.set_surface_override_material(3, material)

func _on_interacted(interactor: Node) -> void:
	print(paintingTitle)
