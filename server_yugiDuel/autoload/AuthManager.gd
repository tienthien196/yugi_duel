# ===========================================================================
# AuthManager.gd - Simple token auth (Godot 3.6) + Console Debug
# ===========================================================================
extends Node

const TOKEN_EXPIRE_TIME = 3600

var sessions = {}    # token -> { player_id, peer_id, created_time }
signal player_authenticated(player_id, session_token, peer_id)
signal player_logged_out(player_id)
signal auth_failed(peer_id, error_code)

onready var network_manager = NetworkManager

func _ready():
	print("[S-AUTH] Ready")
	network_manager.connect("client_connected", self, "_on_client_connected")
	network_manager.connect("message_received", self, "_on_message_received")

func _on_client_connected(player_id, peer_id):
	print("[S-AUTH] Client connected player_id=%s peer_id=%s" % [str(player_id), str(peer_id)])
	# No-op; NetworkManager already sent AUTH_REQUEST
	pass

func _on_message_received(player_id, message):
	var t = str(message.get("type",""))
	match t:
		"AUTH_LOGIN":
			_handle_login(player_id, message)
		"LOGOUT":
			_handle_logout(player_id, message)
		_:
			pass

func _handle_login(temp_player_id, message):
	var username = str(message.get("username","")).strip_edges()
	print("[S-AUTH] ▶️ AUTH_LOGIN from temp_pid=%s username='%s'" % [str(temp_player_id), username])
	# Accept all usernames (guest or real); generate token and bind to current peer
	var token = _generate_token()
	var peer_id = network_manager._get_peer_from_player(temp_player_id)
	sessions[token] = {
		"player_id": username,
		"peer_id": peer_id,
		"created_time": OS.get_unix_time()
	}
	# Update mapping in NetworkManager
	for pid in network_manager.peer_to_player.keys():
		if pid == peer_id:
			network_manager.peer_to_player[pid] = username
	# Notify server-side managers
	emit_signal("player_authenticated", username, token, peer_id)
	# SEND AUTH_SUCCESS so client can store token
	network_manager.send_message_to_player(username, {
		"type": "AUTH_SUCCESS",
		"player_id": username,
		"token": token
	})
	print("[S-AUTH] ✅ Authenticated '%s' token_len=%d (peer=%s)" % [username, token.length(), str(peer_id)])

func _handle_logout(player_id, message):
	var token = str(message.get("token",""))
	print("[S-AUTH] ▶️ LOGOUT player_id=%s token_len=%d" % [player_id, token.length()])
	if token == "" or not sessions.has(token):
		var peer = network_manager._get_peer_from_player(player_id)
		if peer != 0:
			print("[S-AUTH] ❌ Invalid token on logout")
			network_manager.rpc_id(peer, "receive_message", { "type": "AUTH_ERROR", "code": "INVALID_TOKEN" })
		return
	sessions.erase(token)
	print("[S-AUTH] 🚪 Player logged out: %s" % player_id)
	emit_signal("player_logged_out", player_id)

func verify(player_id: String, token: String) -> bool:
	if token == "" or not sessions.has(token):
		return false
	var s = sessions[token]
	return s.player_id == player_id and (OS.get_unix_time() - int(s.created_time)) <= TOKEN_EXPIRE_TIME

func _generate_token() -> String:
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var s = ""
	for i in range(32):
		s += chars[randi() % chars.length()]
	return s
