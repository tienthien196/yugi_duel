# ===========================================================================
# NetworkClient.gd - Client ENet for Godot 3.6
# - Sends/receives plain dictionaries via RPC "receive_message"
# - Unified protocol with server
# ===========================================================================
extends Node

var server_ip   = "127.0.0.1"
var server_port = 8080

var peer = null
var connected = false

# Signals
signal connected_to_server
signal connection_failed
signal server_disconnected

signal auth_request(data)
signal auth_success(data)            # { "player_id": "", "token": "" }
signal auth_failed(error_code)

signal game_started(room_id)
signal game_state_received(state)
signal game_event_received(events)
signal action_result_received(result)

signal room_list_received(rooms)
signal room_list_update(rooms)
signal room_created(room_id)

signal error_received(code, message)

func _ready():
	pass

func connect_to_server(ip := "", port := 0):
	if connected:
		return true
	if ip != "":
		server_ip = ip
	if port != 0:
		server_port = port
	peer = NetworkedMultiplayerENet.new()
	var err = peer.create_client(server_ip, server_port)
	if err != OK:
		emit_signal("connection_failed")
		return false
	get_tree().network_peer = peer
	connected = true
	get_tree().connect("connection_failed", self, "_on_connection_failed")
	get_tree().connect("server_disconnected", self, "_on_server_disconnected")
	return true

func _on_connection_failed():
	emit_signal("connection_failed")

func _on_server_disconnected():
	connected = false
	emit_signal("server_disconnected")

# ---------------- Sending ----------------
func send_message(msg: Dictionary):
	if not connected or not get_tree().network_peer:
		push_error("Not connected")
		return
	rpc_id(1, "receive_message", msg) # server peer_id is 1

func send_auth_login(username: String, password: String):
	send_message({
		"type": "AUTH_LOGIN",
		"username": username,
		"password": password
	})

func send_create_room(mode := "pvp_1v1"):
	send_message({ "type": "CREATE_ROOM", "mode": mode })

func send_list_rooms():
	send_message({ "type": "LIST_ROOMS" })

# ---------------- Receiving (from server) ----------------
remote func receive_message(message):
	if typeof(message) != TYPE_DICTIONARY:
		return
	var t = str(message.get("type",""))
	match t:
		"AUTH_REQUEST":
			emit_signal("auth_request", message)
		"AUTH_SUCCESS":
			emit_signal("auth_success", { "player_id": message.get("player_id",""), "token": message.get("token","") })
		"AUTH_ERROR":
			emit_signal("auth_failed", message.get("code","ERROR"))
		"ROOM_LIST":
			emit_signal("room_list_received", message.get("rooms", []))
		"ROOM_LIST_UPDATE":
			emit_signal("room_list_update", message.get("rooms", []))
		"ROOM_CREATED":
			emit_signal("room_created", message.get("room_id",""))
		"GAME_STARTED":
			emit_signal("game_started", message.get("room_id",""))
		"GAME_STATE":
			emit_signal("game_state_received", message.get("state", {}))
		"GAME_EVENT":
			emit_signal("game_event_received", message.get("events", []))
		"ACTION_RESULT":
			emit_signal("action_result_received", message.get("result", {}))
		"ERROR":
			emit_signal("error_received", message.get("code",""), message.get("message",""))
		_:
			print("Unhandled message: ", message)
