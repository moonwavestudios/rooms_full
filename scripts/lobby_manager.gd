extends Node

const PORT := 7777
const MAX_PLAYERS := 8
const CODE_LENGTH := 6
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var lobby_code := ""
var players := {}

signal player_joined(id: int, name: String)
signal player_left(id: int)
signal lobby_ready()
signal connection_failed()
signal connection_succeeded()

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func generate_code() -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code

func host_lobby(player_name: String) -> Error:
	lobby_code = generate_code()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players[1] = player_name
	lobby_ready.emit()
	return OK

func join_lobby(code: String, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("localhost", PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	lobby_code = code.to_upper().strip_edges()
	_send_join_request.call_deferred(player_name)
	return OK

func leave_lobby() -> void:
	players.clear()
	lobby_code = ""
	multiplayer.multiplayer_peer = null

func _send_join_request(player_name: String) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_rpc_request_join.rpc_id(1, lobby_code, player_name)

@rpc("any_peer", "reliable")
func _rpc_request_join(code: String, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if code != lobby_code:
		_rpc_reject.rpc_id(sender_id)
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	players[sender_id] = player_name
	_rpc_accept.rpc_id(sender_id, players)
	for id in players:
		if id != sender_id:
			_rpc_player_joined.rpc_id(id, sender_id, player_name)
	player_joined.emit(sender_id, player_name)

@rpc("authority", "reliable")
func _rpc_accept(current_players: Dictionary) -> void:
	players = current_players
	connection_succeeded.emit()

@rpc("authority", "reliable")
func _rpc_reject() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

@rpc("authority", "reliable")
func _rpc_player_joined(id: int, name: String) -> void:
	players[id] = name
	player_joined.emit(id, name)

func _on_peer_connected(id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_left.emit(id)

func _on_connected_to_server() -> void:
	pass

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave_lobby()
