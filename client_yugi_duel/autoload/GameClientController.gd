extends Node

var current_room_id = ""
var current_player_id = ""
var current_game_state = null
var current_available_actions = []  # ✅ Thêm
var is_waiting_for_action = false  # ✅ Thêm

onready var network_client = NetworkManager
onready var authentication = Authentication

# Signals
signal game_state_updated(state)
signal game_event_received(events)
signal joined_room(room_id)
signal error_received(code, message)
signal game_started(room_id)
signal room_list_received(rooms)

func _ready():
	print("[GAME] Ready")
	authentication.connect("login_success", self, "_on_login_success")
	network_client.connect("game_state_received", self, "_on_game_state_received")
	network_client.connect("game_event_received", self, "_on_game_event_received")
	network_client.connect("room_created", self, "_on_room_created")
	network_client.connect("error_received", self, "_on_error_received")
	network_client.connect("room_list_received", self, "_on_room_list_received")
	network_client.connect("game_started", self, "_on_game_started")
	network_client.connect("action_result_received", self, "_on_action_result")
	network_client.connect("chain_triggered", self, "_on_chain_triggered")

# ---------------- Incoming ----------------
func _on_login_success(pid, _is_guest):
	current_player_id = pid

func _on_room_created(room_id):
	current_room_id = room_id
	emit_signal("joined_room", room_id)

func _on_room_list_received(rooms):
	emit_signal("room_list_received", rooms)

func _on_game_started(room_id):
	current_room_id = room_id
	emit_signal("game_started", room_id)

func _on_game_state_received(state: Dictionary):
	current_game_state = state
	if state.has("available_actions"):
		current_available_actions = state.available_actions
	# ✅ Cập nhật room_id thực tế của trận đấu
	if state.has("room_id"):
		current_room_id = state.room_id
	emit_signal("game_state_updated", state)

func _on_game_event_received(events):
	emit_signal("game_event_received", events)

func _on_error_received(code, message):
	emit_signal("error_received", code, message)

func _on_action_result(result: Dictionary):
	if not result:
		return
	if not result.get("success", false):
		print("[GAME] ❌ Action failed - errors: %s" % str(result.get("errors", [])))
	else:
		print("[GAME] ✅ Action success - events: %s" % str(result.get("events", [])))

# ✅ Xử lý CHAIN_TRIGGERED
func _on_chain_triggered(trigger):
	if is_waiting_for_action or not current_game_state:
		return
	var my_id = get_current_player_id()
	if my_id == "" or current_game_state.turn != my_id:
		return

	var player = current_game_state.players.get(my_id, {})
	if not "ACTIVATE_EFFECT" in get_available_actions().types:
		return

	for act in get_available_actions().details:
		if act.type == "ACTIVATE_EFFECT":
			var zone_idx = act.payload.zone_idx
			var card_obj = player.spell_trap_zones.get(zone_idx, null)
			if not card_obj or not card_obj.has("card_data"):
				continue
			var effect = card_obj.card_data.effect

			if trigger.type == "ATTACK_DECLARED" and effect == "destroy_all_attackers":
				# ✅ Dùng timer thay yield
				is_waiting_for_action = true
				var timer = get_tree().create_timer(0.3)
				timer.connect("timeout", self, "_activate_trap", [act.payload])
				return
			elif trigger.type == "SUMMON" and effect == "destroy_summoned_monster":
				is_waiting_for_action = true
				var timer = get_tree().create_timer(0.3)
				timer.connect("timeout", self, "_activate_trap", [act.payload])
				return

# ✅ Hàm phụ để activate trap sau delay
func _activate_trap(payload):
	submit_action("ACTIVATE_EFFECT", payload)
	is_waiting_for_action = false

# ---------------- Outgoing ----------------
func get_current_player_id():
	return current_player_id

func get_available_actions():
	return current_available_actions

func request_room_list():
	network_client.send_list_rooms()

func create_room(mode := "pvp_1v1"):
	network_client.send_create_room(mode)

func join_room(room_id: String):
	var token = authentication.session_token
	network_client.send_message({
		"type": "JOIN_ROOM",
		"room_id": room_id,
		"token": token
	})

func submit_action(action_type: String, payload: Dictionary):
	if current_room_id == "" or not authentication.is_authenticated:
		return false
	var token = authentication.session_token
	var action = payload.duplicate()
	action["type"] = action_type
	network_client.send_message({
		"type": "SUBMIT_ACTION",
		"room_id": current_room_id,
		"token": token,
		"action": action
	})
	return true

# Convenience wrappers
func play_monster(card_id: String, to_zone := -1, position := "face_up_attack"):
	return submit_action("PLAY_MONSTER", {
		"card_id": card_id,
		"to_zone": to_zone,
		"position": position
	})

func declare_attack(attacker_zone: int, target_zone := -1):
	return submit_action("DECLARE_ATTACK", {
		"atk_zone": attacker_zone,
		"target_zone": target_zone
	})

func end_turn():
	return submit_action("END_TURN", {})
