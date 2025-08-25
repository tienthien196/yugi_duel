# ===========================================================================
# Authentication.gd - Client-side auth manager (Godot 3.6)
# ===========================================================================
extends Node

var is_authenticated = false
var player_id = ""
var session_token = ""
var is_guest = false

var auto_login_on_request = true
var saved_username = ""

onready var network_client = NetworkManager

signal login_success(player_id, is_guest)
signal login_failed(error_code)
signal logged_out()

func _ready():
	network_client.connect("auth_success", self, "_on_auth_success")
	network_client.connect("auth_failed", self, "_on_auth_failed")
	network_client.connect("auth_request", self, "_on_auth_request")

func login(username: String, password := ""):
	username = username.strip_edges()
	if username == "":
		emit_signal("login_failed", "USERNAME_EMPTY")
		return false
	network_client.send_auth_login(username, password)
	return true

func create_guest():
	var guest_name = "guest_%d" % (OS.get_unix_time() % 100000)
	network_client.send_auth_login(guest_name, "")

func _on_auth_request(data):
	if not auto_login_on_request:
		return
	if saved_username != "":
		login(saved_username)
	else:
		create_guest()

func _on_auth_success(data: Dictionary):
	var pid = str(data.get("player_id",""))
	var token = str(data.get("token",""))
	if pid == "" or token == "":
		emit_signal("login_failed", "INVALID_AUTH_RESPONSE")
		return
	player_id = pid
	session_token = token
	is_authenticated = true
	is_guest = pid.begins_with("guest_")
	emit_signal("login_success", pid, is_guest)

func _on_auth_failed(error_code):
	_clear_session()
	emit_signal("login_failed", error_code)

func logout():
	if not is_authenticated:
		return
	network_client.send_message({
		"type": "LOGOUT",
		"token": session_token
	})
	_clear_session()
	emit_signal("logged_out")

func _clear_session():
	is_authenticated = false
	player_id = ""
	session_token = ""
	is_guest = false
