# ===========================================================================
# BotClient.gd - Simple automated client bot (Godot 3.6) + Console Debug
# Usage: Add as an Autoload "BotClient". It will connect & play automatically.
# ===========================================================================
extends Node

export(String) var server_ip := "127.0.0.1"
export(int) var server_port := 8080
export(bool) var auto_create_room_if_empty := true
export(float) var action_delay_sec := 0.5

onready var net := NetworkManager
onready var auth := Authentication
onready var game := GameClientController

var _my_id := ""
var _started := false

func _ready():
	print("[BOT] Starting...")
	net.connect("server_disconnected", self, "_on_disconnected")
	auth.connect("login_success", self, "_on_login_success")
	auth.connect("login_failed", self, "_on_login_failed")
	game.connect("room_list_received", self, "_on_room_list_received")
	game.connect("joined_room", self, "_on_joined_room")
	game.connect("game_started", self, "_on_game_started")
	game.connect("game_state_updated", self, "_on_game_state_updated")
	if net.connect_to_server(server_ip, server_port):
		print("[BOT] Connected to server, waiting for AUTH_REQUEST...")

func _on_disconnected():
	print("[BOT] Disconnected from server")

func _on_login_success(pid, is_guest):
	_my_id = pid
	print("[BOT] Logged in as %s (guest=%s)" % [pid, str(is_guest)])
	game.request_room_list()

func _on_login_failed(code):
	print("[BOT] Login failed: %s" % str(code))

func _on_room_list_received(rooms):
	print("[BOT] Room list received: %s" % str(rooms))
	if rooms.size() == 0 and auto_create_room_if_empty:
		print("[BOT] No rooms → creating one")
		game.create_room()
	else:
		# Try join the first room
		for r in rooms:
			if r.has("room_id"):
				print("[BOT] Joining room %s" % r["room_id"])
				game.join_room(r["room_id"])
				return
		print("[BOT] No joinable rooms → creating one")
		game.create_room()

func _on_joined_room(room_id):
	print("[BOT] Joined room %s, waiting start..." % room_id)

func _on_game_started(room_id):
	print("[BOT] Game started in %s" % room_id)
	_started = true

func _on_game_state_updated(state):
	if not _started:
		return
	# Extremely simple strategy: if it's my turn -> end turn after a short delay
	if typeof(state) == TYPE_DICTIONARY and state.get("turn","") == _my_id:
		print("[BOT] My turn -> END_TURN (after delay %.2fs)" % action_delay_sec)
		yield(get_tree().create_timer(action_delay_sec), "timeout")
		game.end_turn()
