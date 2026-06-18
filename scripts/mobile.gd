extends Control

func _ready() -> void:
	match OS.get_name():
		"Android":
			visible = true
