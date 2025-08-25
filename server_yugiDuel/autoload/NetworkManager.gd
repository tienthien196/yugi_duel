# ===========================================================================
# NetworkManager.gd - Server ENet for Godot 3.6
# ===========================================================================
extends Node

const DEFAULT_PORT = 8080
const SERVER_PEER_ID = 1

var is_server = false
var peer_to_player = {}

signal client_connected(player_id, peer_id)
signal client_disconnected(peer_id)
signal message_received(player_id, message)

func _ready():
	var enet = NetworkedMultiplayerENet.new()
	var err = enet.create_server(DEFAULT_PORT, 32)
	if err != OK:
		push_error("Cannot create ENet server")
		return
	get_tree().network_peer = enet
	is_server = true
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")

func _process(_d):
	if not is_server or not multiplayer.network_peer:
		return
	multiplayer.poll()

func _on_peer_connected(peer_id):
	var temp_player = "player_%d" % peer_id
	peer_to_player[peer_id] = temp_player
	emit_signal("client_connected", temp_player, peer_id)
	var welcome = {
		"type": "AUTH_REQUEST",
		"message": "Send AUTH_LOGIN to authenticate"
	}
	rpc_id(peer_id, "receive_message", welcome)

func _on_peer_disconnected(peer_id):
	peer_to_player.erase(peer_id)
	emit_signal("client_disconnected", peer_id)

remote func receive_message(message):
	var peer_id = multiplayer.get_rpc_sender_id()
	var player_id = peer_to_player.get(peer_id, "unknown")
	if typeof(message) != TYPE_DICTIONARY or not message.has("type"):
		_send_error(peer_id, "MALFORMED")
		return
	emit_signal("message_received", player_id, message)

func send_message_to_player(player_id: String, data: Dictionary):
	var pid = _get_peer_from_player(player_id)
	if pid == 0:
		return
	rpc_id(pid, "receive_message", data)

func broadcast_message(data: Dictionary, exclude_player := ""):
	for pid in peer_to_player.keys():
		if exclude_player != "" and peer_to_player[pid] == exclude_player:
			continue
		rpc_id(pid, "receive_message", data)

func _get_peer_from_player(player_id):
	for pid in peer_to_player:
		if peer_to_player[pid] == player_id:
			return pid
	return 0

func _send_error(peer_id, code, msg := ""):
	var e = { "type": "ERROR", "code": code, "message": msg }
	rpc_id(peer_id, "receive_message", e)
