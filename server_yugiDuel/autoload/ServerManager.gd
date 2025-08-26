# ===========================================================================
# ServerManager.gd - Message router for gameplay (Godot 3.6)
# Depends on GameManager + BattleCore existing in autoloads.
# ===========================================================================
extends Node

var rooms = {}
var player_to_room = {}

onready var network_manager = NetworkManager
onready var auth_manager = AuthManager
onready var game_manager = GameManager

func _ready():
	auth_manager.connect("player_authenticated", self, "_on_player_authenticated")
	network_manager.connect("message_received", self, "_on_message_received")
	game_manager.connect("game_started", self, "_on_game_started")
	game_manager.connect("game_finished", self, "_on_game_finished")
	game_manager.connect("game_event", self, "_on_game_event")
	print("[S-SERVER] Ready")

func _on_player_authenticated(player_id, token, peer_id):
	pass  # AUTH_SUCCESS already sent by AuthManager

func _on_message_received(player_id, message):
	var t = str(message.get("type", ""))
	match t:
		"LIST_ROOMS":
			_send_room_list(player_id)
		"CREATE_ROOM":
			_handle_create_room(player_id, message)
		"JOIN_ROOM":
			_handle_join_room(player_id, message)
		"GET_STATE":
			_handle_get_state(player_id, message)
		"SUBMIT_ACTION":
			_handle_submit_action(player_id, message)
		_:
			pass

func _handle_create_room(player_id, message):
	var mode = str(message.get("mode", "pvp_1v1"))
	if mode == "pve":
		var result = game_manager.create_duel_vs_bot(player_id)
		if not result.success:
			network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": result.error, "message": "" })
			return
		var room_id = result.room_id
		rooms[room_id] = { "player_a": player_id, "player_b": "bot_ai", "status": "playing", "duel_id": room_id }
		player_to_room[player_id] = room_id
		network_manager.send_message_to_player(player_id, { "type": "ROOM_CREATED", "room_id": room_id })
		return
	
	var room_id = "room_%d" % (OS.get_unix_time() % 100000)
	rooms[room_id] = { "player_a": player_id, "player_b": "", "status": "waiting" }
	player_to_room[player_id] = room_id
	network_manager.send_message_to_player(player_id, { "type": "ROOM_CREATED", "room_id": room_id })

func _handle_join_room(player_id, message):
	var room_id = str(message.get("room_id", ""))
	if room_id == "" or not rooms.has(room_id):
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "ROOM_NOT_FOUND", "message": "" })
		return
	if rooms[room_id]["player_b"] == "" and rooms[room_id]["player_a"] != player_id:
		rooms[room_id]["player_b"] = player_id
		player_to_room[player_id] = room_id
		var ra = rooms[room_id]["player_a"]
		var rb = rooms[room_id]["player_b"]
		var result = game_manager.create_duel(ra, rb, room_id)
		if not result.success:
			network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": result.error, "message": "" })
			return
		rooms[room_id]["duel_id"] = result.duel_id
		rooms[room_id]["status"] = "playing"
		game_manager.emit_signal("game_started", room_id, ra, rb)
	else:
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "ROOM_FULL", "message": "" })

func _handle_get_state(player_id, message):
	var room_id = str(message.get("room_id", ""))
	if room_id == "" or not rooms.has(room_id):
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "ROOM_NOT_FOUND", "message": "" })
		return
	var duel_id = rooms[room_id].get("duel_id", "")
	var state = game_manager.get_game_state(duel_id, player_id)
	var actions = game_manager.get_available_actions(duel_id, player_id)
	network_manager.send_message_to_player(player_id, { 
		"type": "GAME_STATE", 
		"state": state, 
		"available_actions": actions 
	})

func _handle_submit_action(player_id, message):
	var room_id = str(message.get("room_id", ""))
	var action = message.get("action", {})
	if room_id == "" or not rooms.has(room_id):
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "ROOM_NOT_FOUND", "message": "" })
		return
	var duel_id = rooms[room_id].get("duel_id", "")
	if typeof(action) != TYPE_DICTIONARY:
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "INVALID_ACTION", "message": "" })
		return
	action["player_id"] = player_id
	var result = game_manager.submit_action(room_id, action)
	
	# ✅ Gửi ACTION_RESULT cho cả phòng
	_broadcast_to_room(room_id, { "type": "ACTION_RESULT", "result": result })
	
	# ✅ Gửi GAME_STATE riêng cho từng người
	var state = game_manager.get_game_state(duel_id)
	for pid in [rooms[room_id].get("player_a"), rooms[room_id].get("player_b")]:
		if pid != "" and pid != "bot_ai":
			var actions = game_manager.get_available_actions(duel_id, pid)
			network_manager.send_message_to_player(pid, {
				"type": "GAME_STATE",
				"state": state,
				"available_actions": actions
			})

func _send_room_list(player_id):
	var list = []
	for k in rooms.keys():
		list.append({ "room_id": k, "status": rooms[k]["status"] })
	network_manager.send_message_to_player(player_id, { "type": "ROOM_LIST", "rooms": list })

func _on_game_started(room_id, player_a, player_b):
	_broadcast_to_room(room_id, { "type": "GAME_STARTED", "room_id": room_id })
	
	var duel_id = rooms[room_id].get("duel_id", "")
	var state = game_manager.get_game_state(duel_id)
	for pid in [player_a, player_b]:
		if pid != "" and pid != "bot_ai":
			var actions = game_manager.get_available_actions(duel_id, pid)
			network_manager.send_message_to_player(pid, {
				"type": "GAME_STATE",
				"state": state,
				"available_actions": actions
			})

func _on_game_finished(room_id, winner, reason):
	_broadcast_to_room(room_id, { "type": "GAME_OVER", "winner": winner, "reason": reason })
	if rooms.has(room_id):
		var room = rooms[room_id]
		for pid in [room.get("player_a", ""), room.get("player_b", "")]:
			if pid != "" and pid != "bot_ai":
				player_to_room.erase(pid)
		rooms.erase(room_id)

func _on_game_event(room_id, events):
	_broadcast_to_room(room_id, { "type": "GAME_EVENT", "events": events })

	for event in events:
		if event.type in ["ATTACK_DECLARED", "SUMMON", "FLIP_SUMMON", "PLAY_SPELL", "SET_SPELL", "SET_MONSTER"]:
			_broadcast_to_room(room_id, {
				"type": "CHAIN_TRIGGERED",
				"trigger": event,
				"timestamp": OS.get_unix_time(),
				"can_respond": true
			})

	var duel_id = rooms[room_id].get("duel_id", "")
	if duel_id != "":
		var state = game_manager.get_game_state(duel_id)
		for pid in [rooms[room_id].get("player_a"), rooms[room_id].get("player_b")]:
			if pid != "" and pid != "bot_ai":
				var actions = game_manager.get_available_actions(duel_id, pid)
				network_manager.send_message_to_player(pid, {
					"type": "GAME_STATE",
					"state": state,
					"available_actions": actions
				})

# Helper to broadcast message to all players in room
func _broadcast_to_room(room_id: String, message: Dictionary):
	if not rooms.has(room_id):
		print("[ServerManager] Room not found: %s" % room_id)
		return
	
	var room_data = rooms[room_id]
	var duel_id = room_data.get("duel_id", "")
	if duel_id == "":
		return
	
	for player_id in [room_data.get("player_a"), room_data.get("player_b")]:
		if player_id != "" and player_id != "bot_ai":
			network_manager.send_message_to_player(player_id, message)
