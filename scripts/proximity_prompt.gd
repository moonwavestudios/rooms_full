extends Area3D

@export var prompt_text: String = "Press [F] to interact"
@export var action_key: String = "interact"          
@export var hold_duration: float = 1.0               # 0 = tap, >0 = hold to trigger
@export var max_activations: int = -1               # -1 = infinite
@export var cooldown_time: float = 1.0               # seconds between activations
@export var max_distance: float = 5.0
@export var prompt_font: Font
@export var prompt_font_size: int = 18
@export var enabled: bool = true

signal prompt_triggered(interactor: Node)
signal prompt_activated(interactor: Node)
signal prompt_deactivated(interactor: Node)
signal player_entered(interactor: Node)
signal player_exited(interactor: Node)

var _closest_player: Node = null
var _hold_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _activation_count: int = 0
var _is_holding: bool = false
var _exhausted: bool = false
var _ui_label: Label          
var _ui_container: Control

func _ready() -> void:
	if not InputMap.has_action(action_key):
		push_error("ProximityPrompt: Action '%s' not found in Input Map! Please add it via Project > Input Map." % action_key)

	_build_ui()
	_set_ui_visible(false)

func _process(delta: float) -> void:
	if not enabled:
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		
	_update_closest_player()
	
	if _closest_player == null:
		_set_ui_visible(false)
		_reset_hold()
		return

	if _exhausted or (max_activations >= 0 and _activation_count >= max_activations):
		_exhausted = true
		_set_ui_visible(false)
		_reset_hold()
		return
		
	_set_ui_visible(true)
	_update_ui_position()

	if Input.is_action_pressed(action_key):
		if hold_duration > 0.0:
			
			_is_holding = true
			_hold_timer += delta
			_update_progress_bar(_hold_timer / hold_duration)
			if _hold_timer >= hold_duration:
				_try_activate(_closest_player)
				_reset_hold()
		else:
			
			pass
	else:
		if _is_holding:
			_reset_hold()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if _closest_player == null:
		return
	if hold_duration > 0.0:
		return
	if global_position.distance_to(_closest_player.global_position) > max_distance:
		return
	
	if _exhausted or (max_activations >= 0 and _activation_count >= max_activations):
		return

	if event.is_action_pressed(action_key):
		_try_activate(_closest_player)

func _try_activate(interactor: Node) -> void:
	if _cooldown_timer > 0.0:
		return
	if max_activations >= 0 and _activation_count >= max_activations:
		return

	_activation_count += 1
	_cooldown_timer = cooldown_time

	if max_activations >= 0 and _activation_count >= max_activations:
		_exhausted = true
		_set_ui_visible(false)

	emit_signal("prompt_triggered", interactor)

func _update_closest_player() -> void:
	var all_players := get_tree().get_nodes_in_group("interactors")

	var best: Node = null
	var best_dist: float = INF
	for p in all_players:
		if not is_instance_valid(p):
			continue
			
		if p.has_method("is_Killer") and p.is_Killer:
			continue
			
		if "is_Killer" in p and p.is_Killer:
			continue

		var d: float = global_position.distance_to(p.global_position)
		if d <= max_distance and d < best_dist:
			best_dist = d
			best = p

	if best != _closest_player:
		if _closest_player != null:
			emit_signal("prompt_deactivated", _closest_player)
			emit_signal("player_exited", _closest_player)
		_closest_player = best
		if _closest_player != null:
			emit_signal("prompt_activated", _closest_player)
			emit_signal("player_entered", _closest_player)

func _reset_hold() -> void:
	_hold_timer = 0.0
	_is_holding = false
	_update_progress_bar(0.0)

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_set_ui_visible(false)
		_reset_hold()

func set_prompt_text(text: String) -> void:
	prompt_text = text
	if _ui_label:
		_ui_label.text = prompt_text

func reset_activations() -> void:
	_activation_count = 0
	_exhausted = false

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	_ui_container = Control.new()
	_ui_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_ui_container)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left   = 14
	style.content_margin_right  = 14
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	_ui_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	_ui_label = Label.new()
	_ui_label.text = prompt_text
	_ui_label.add_theme_color_override("font_color", Color.WHITE)
	if prompt_font:
		_ui_label.add_theme_font_override("font", prompt_font)
	_ui_label.add_theme_font_size_override("font_size", prompt_font_size)
	_ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_ui_label)

	var progress := ProgressBar.new()
	progress.name = "ProgressBar"
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = 0.0
	if prompt_font:
		progress.add_theme_font_override("font", prompt_font)
	progress.custom_minimum_size = Vector2(160, 6)
	progress.visible = hold_duration > 0.0
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(progress)

	_ui_container.set_meta("panel", panel)

func _set_ui_visible(value: bool) -> void:
	if _ui_container:
		_ui_container.visible = value

func _update_ui_position() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var screen_pos: Vector2 = camera.unproject_position(global_position)
	var panel: PanelContainer = _ui_container.get_meta("panel")
	panel.position = screen_pos - panel.size * 0.5

func _update_progress_bar(value: float) -> void:
	var panel: PanelContainer = _ui_container.get_meta("panel") if _ui_container and _ui_container.has_meta("panel") else null
	if panel == null:
		return
	var pb: ProgressBar = panel.find_child("ProgressBar", true, false)
	if pb:
		pb.value = clamp(value, 0.0, 1.0)
