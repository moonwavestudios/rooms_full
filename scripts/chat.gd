extends Control

@onready var panel = $Panel
@onready var messages_container = $Panel/ScrollContainer/Messages
@onready var input_field = $Panel/LineEdit
@onready var send_button = $Panel/SendButton
@onready var scroll_container = $Panel/ScrollContainer
@onready var auto_hide_timer = $AutoHideTimer

var chat_open := false

const FILTERED_WORDS: Array[String] = [
	"nigga",
	"tranny",
	"faggot",
	"nudes",
	"sex",
	"blowjob",
	"handjob",
	"deepthroat",
	"anal",
	"whore",
	"breedable",
	"nigger",
	"nibba",
	"niga",
	"digga",
	"niggah",
	"slut",
	"fag",
	"fagg",
	"He-she",
	"She-he",
	"She-male",
	"bigga",
	"fatass",
	"trannie",
	"kys",
	"kill yourself",
	"fuck me",
]

const LEET_MAP: Dictionary = {
	"@": "a", "4": "a", "^": "a",
	"8": "b",
	"(": "c", "<": "c",
	"3": "e", "&": "e",
	"9": "g", "6": "g",
	"#": "h",
	"1": "i", "!": "i", "|": "i",
	"0": "o",
	"$": "s", "5": "s",
	"+": "t", "7": "t",
	"2": "z",
}

func _normalize(text: String) -> String:
	var result := text.to_lower()

	var expanded := ""
	for ch in result:
		if ch in LEET_MAP:
			expanded += LEET_MAP[ch]
		else:
			expanded += ch
	result = expanded

	var stripped := ""
	for ch in result:
		if ch.unicode_at(0) >= 32:
			stripped += ch
	result = stripped

	var no_spaces := ""
	for ch in result:
		if ch != " " and ch != "\t":
			no_spaces += ch
	result = no_spaces

	var deduped := ""
	var prev := ""
	for ch in result:
		if ch != prev:
			deduped += ch
		prev = ch

	var letters_only := ""
	for ch in deduped:
		var code := ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			letters_only += ch
	result = letters_only

	return result

func _contains_filtered_word(message: String) -> bool:
	var normalized := _normalize(message)
	for word in FILTERED_WORDS:
		var normalized_word := _normalize(word)
		if normalized.contains(normalized_word):
			return true
	return false

func _ready():
	panel.visible = false
	input_field.editable = false
	send_button.pressed.connect(_send_message)
	input_field.text_submitted.connect(_on_text_submitted)
	auto_hide_timer.timeout.connect(_hide_chat_preview)

func _input(event):
	if event.is_action_pressed("open_chat"):
		if !chat_open:
			open_chat()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_text_submit"):
		if chat_open:
			_send_message()
			get_viewport().set_input_as_handled()

func open_chat():
	chat_open = true
	panel.visible = true
	auto_hide_timer.stop()
	input_field.editable = true
	input_field.grab_focus()
	input_field.clear()

func close_chat():
	chat_open = false
	input_field.release_focus()
	input_field.clear()
	input_field.editable = false
	auto_hide_timer.start()

func _hide_chat_preview():
	if !chat_open:
		panel.visible = false

func _send_message():
	var text = input_field.text.strip_edges()
	if text.is_empty():
		close_chat()
		return
	if _contains_filtered_word(text):
		input_field.clear()
		input_field.placeholder_text = "Message blocked."
		return
	var username = $"..".player_name
	send_chat_message.rpc(username, text)
	close_chat()

func _on_text_submitted(_text: String):
	_send_message()

@rpc("any_peer", "call_local", "reliable")
func send_chat_message(username: String, message: String):
	if _contains_filtered_word(message):
		return
	add_message(username, message)
	panel.visible = true
	if !chat_open:
		auto_hide_timer.start()

func add_message(username: String, message: String):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 400
	label.text = "[b]%s:[/b] %s" % [username, message]
	messages_container.add_child(label)
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
