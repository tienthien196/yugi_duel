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
onready var battle_core = BattleCore

func _ready():
	auth_manager.connect("player_authenticated", self, "_on_player_authenticated")
	network_manager.connect("message_received", self, "_on_message_received")
	game_manager.connect("game_started", self, "_on_game_started")
	game_manager.connect("game_finished", self, "_on_game_finished")
	game_manager.connect("game_event", self, "_on_game_event")

func _on_player_authenticated(player_id, token, peer_id):
	# Optionally also send player info here if you keep a DB
	# Main fix: AUTH_SUCCESS already sent by AuthManager
	pass

func _on_message_received(player_id, message):
	var t = str(message.get("type",""))
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
	var mode = str(message.get("mode","pvp_1v1"))
	if mode == "pve":
		# Start PvE via GameManager if supported
		if PvEManager and PvEManager.has_method("start_pve_game"):
			var deck = DatabaseManager.get_deck(player_id)
			PvEManager.start_pve_game(player_id, deck)
		return
	# PvP room waiting for opponent
	var room_id = "room_%d" % (OS.get_unix_time() % 100000)
	rooms[room_id] = { "player_a": player_id, "player_b": "", "status": "waiting" }
	player_to_room[player_id] = room_id
	network_manager.send_message_to_player(player_id, { "type": "ROOM_CREATED", "room_id": room_id })

func _handle_join_room(player_id, message):
	var room_id = str(message.get("room_id",""))
	if room_id == "" or not rooms.has(room_id):
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "ROOM_NOT_FOUND", "message": "" })
		return
	if rooms[room_id]["player_b"] == "" and rooms[room_id]["player_a"] != player_id:
		rooms[room_id]["player_b"] = player_id
		player_to_room[player_id] = room_id
		# start duel
		var ra = rooms[room_id]["player_a"]
		var rb = rooms[room_id]["player_b"]
		var deck_a = DatabaseManager.get_deck(ra)
		var deck_b = DatabaseManager.get_deck(rb)
		var rules = { "start_lp": 8000, "max_hand_size": 6 }
		var duel_id = battle_core.start_duel(ra, rb, deck_a, deck_b, rules)
		rooms[room_id]["duel_id"] = duel_id
		rooms[room_id]["status"] = "playing"
		network_manager.send_message_to_player(ra, { "type": "GAME_STARTED", "room_id": room_id })
		network_manager.send_message_to_player(rb, { "type": "GAME_STARTED", "room_id": room_id })
	else:
		network_manager.send_message_to_player(player_id, { "type": "ERROR", "code": "ROOM_FULL", "message": "" })

func _handle_get_state(player_id, message):
	var room_id = str(message.get("room_id",""))
	if room_id == "" or not rooms.has(room_id):
		return
	var state = battle_core.get_game_state(rooms[room_id].get("duel_id",""))
	network_manager.send_message_to_player(player_id, { "type": "GAME_STATE", "state": state })

func _handle_submit_action(player_id, message):
	var room_id = str(message.get("room_id",""))
	var action = message.get("action", {})
	if room_id == "" or not rooms.has(room_id):
		return
	var duel_id = rooms[room_id].get("duel_id","")
	if typeof(action) != TYPE_DICTIONARY:
		return
	action["player_id"] = player_id
	var result = battle_core.submit_action(duel_id, action)
	# Push result and (optionally) updated state
	network_manager.send_message_to_player(player_id, { "type": "ACTION_RESULT", "result": result })
	var state = battle_core.get_game_state(duel_id)
	network_manager.send_message_to_player(player_id, { "type": "GAME_STATE", "state": state })

func _send_room_list(player_id):
	var list = []
	for k in rooms.keys():
		list.append({ "room_id": k, "status": rooms[k]["status"] })
	network_manager.send_message_to_player(player_id, { "type": "ROOM_LIST", "rooms": list })

func _on_game_started(room_id, a, b):
	# If using GameManager signals, forward events as needed
	pass

func _on_game_finished(room_id, winner, reason):
	pass

func _on_game_event(room_id, events):
	# Broadcast to players in that room
	for pid in player_to_room.keys():
		if player_to_room[pid] == room_id:
			network_manager.send_message_to_player(pid, { "type": "GAME_EVENT", "events": events })
