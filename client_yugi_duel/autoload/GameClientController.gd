# ===========================================================================
# GameClientController.gd - Client duel flow (Godot 3.6) + Console Debug
# ===========================================================================
extends Node

var current_room_id = ""
var current_player_id = ""
var current_game_state = null

onready var network_client = NetworkManager
onready var authentication = Authentication

signal game_state_updated(state)
signal game_event_received(events)
signal player_turn_changed(next_player)
signal phase_changed(new_phase)
signal game_over(winner, reason)
signal joined_room(room_id)
signal error_received(code, message)
signal game_started(room_id)
signal room_list_received(rooms)

func _ready():
	print("[GAME] Ready and wiring signals")
	authentication.connect("login_success", self, "_on_login_success")
	authentication.connect("logged_out", self, "_on_logged_out")

	network_client.connect("game_state_received", self, "_on_game_state_received")
	network_client.connect("game_event_received", self, "_on_game_event_received")
	network_client.connect("room_created", self, "_on_room_created")
	network_client.connect("error_received", self, "_on_error_received")
	network_client.connect("room_list_received", self, "_on_room_list_received")
	network_client.connect("game_started", self, "_on_game_started")

func _on_login_success(pid, _is_guest):
	current_player_id = pid
	print("[GAME] Logged in as '%s'" % pid)

func _on_logged_out():
	print("[GAME] Logged out → clearing local state")
	current_player_id = ""
	current_room_id = ""
	current_game_state = null

# ---------------- Outgoing ----------------
func request_room_list():
	print("[GAME] ▶️ Requesting room list")
	network_client.send_list_rooms()

func create_room(mode := "pvp_1v1"):
	if mode == "":
		mode = "pvp_1v1"
	print("[GAME] ▶️ Creating room mode=%s" % mode)
	network_client.send_create_room(mode)

func join_room(room_id: String):
	var token = authentication.session_token
	print("[GAME] ▶️ Joining room '%s'" % room_id)
	network_client.send_message({
		"type": "JOIN_ROOM",
		"room_id": room_id,
		"token": token
	})

func get_game_state(room_id: String):
	var token = authentication.session_token
	print("[GAME] ▶️ Requesting state for room '%s'" % room_id)
	network_client.send_message({
		"type": "GET_STATE",
		"room_id": room_id,
		"token": token
	})

# Unified submit_action API
func submit_action(action_type: String, payload: Dictionary):
	if current_room_id == "" or not authentication.is_authenticated:
		print("[GAME] ❌ submit_action refused (room empty or not authenticated). action=%s" % action_type)
		return false
	var token = authentication.session_token
	var action = payload.duplicate()
	action["type"] = action_type
	print("[GAME] ▶️ SUBMIT_ACTION type=%s payload=%s" % [action_type, str(payload)])
	network_client.send_message({
		"type": "SUBMIT_ACTION",
		"room_id": current_room_id,
		"token": token,
		"action": action
	})
	return true

# Convenience wrappers
func play_monster(card_id: String, to_zone := -1, position := "attack"):
	return submit_action("PLAY_MONSTER", {
		"card_id": card_id,
		"to_zone": to_zone,
		"position": position
	})

func set_spell_trap(card_id: String, to_zone := -1):
	return submit_action("SET_SPELL_TRAP", {
		"card_id": card_id,
		"to_zone": to_zone
	})

func activate_effect(card_id: String, zone_type := "spell_trap"):
	return submit_action("ACTIVATE_EFFECT", {
		"card_id": card_id,
		"zone_type": zone_type
	})

func declare_attack(attacker_zone: int, target_zone := -1):
	return submit_action("DECLARE_ATTACK", {
		"atk_zone": attacker_zone,
		"target_zone": target_zone
	})

func change_position(zone: int, to_position: String):
	return submit_action("CHANGE_POSITION", {
		"zone": zone,
		"to_position": to_position
	})

func end_phase():
	return submit_action("END_PHASE", {})

func end_turn():
	return submit_action("END_TURN", {})

func surrender():
	return submit_action("SURRENDER", {})

# ---------------- Incoming ----------------
func _on_room_created(room_id):
	current_room_id = room_id
	print("[GAME] 🆕 Room created: %s" % room_id)
	emit_signal("joined_room", room_id)

func _on_room_list_received(rooms):
	print("[GAME] 📋 Room list received (%d): %s" % [rooms.size(), str(rooms)])
	emit_signal("room_list_received", rooms)

func _on_game_started(room_id):
	current_room_id = room_id
	print("[GAME] 🎮 Game started in room: %s" % room_id)
	emit_signal("game_started", room_id)

func _on_game_state_received(state: Dictionary):
	current_game_state = state
	if state.has("turn"):
		emit_signal("player_turn_changed", state["turn"])
	if state.has("phase"):
		emit_signal("phase_changed", state["phase"])
	if state.get("status","") == "finished":
		emit_signal("game_over", state.get("winner",""), state.get("reason",""))
	print("[GAME] 🔄 State update: turn=%s phase=%s status=%s" % [str(state.get("turn","?")), str(state.get("phase","?")), str(state.get("status","active"))])
	emit_signal("game_state_updated", state)

func _on_game_event_received(events):
	print("[GAME] 📣 Events: %s" % str(events))
	emit_signal("game_event_received", events)

func _on_error_received(code, message):
	print("[GAME] ❌ Error from server: %s | %s" % [str(code), str(message)])
	emit_signal("error_received", code, message)

func get_current_player_id():
	return current_player_id
