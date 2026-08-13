extends Control


func _on_animation_player_animation_finished(_anim_name: StringName) -> void:
	# Use `load()` instead of `preload()` to avoid delaying the splash screen's appearance.
	visible = false
