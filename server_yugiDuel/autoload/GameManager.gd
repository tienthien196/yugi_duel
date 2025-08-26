# ===========================================================================
# GameManager.gd - Quản lý vòng đời trận đấu
# Không xử lý mạng, chỉ dùng BattleCore và DatabaseManager
# ===========================================================================
extends Node

var active_games = {}

onready var database_manager = DatabaseManager
onready var battle_core = BattleCore

signal game_started(room_id, player_a, player_b)
signal game_finished(room_id, winner, reason)
signal game_event(room_id, events)

# ===========================================================================
# create_duel(player_a_id, player_b_id)
# ===========================================================================
func create_duel(player_a_id, player_b_id, room_id):
	var deck_a = database_manager.get_deck(player_a_id)
	var deck_b = database_manager.get_deck(player_b_id)
	var rules = { "start_lp": 8000, "max_hand_size": 6 }

	var duel_id = battle_core.start_duel(player_a_id, player_b_id, deck_a, deck_b, rules)
	if typeof(room_id) != TYPE_STRING:
		return { "success": false, "error": "FAILED_TO_CREATE_DUEL" }

	active_games[duel_id] = {
		"player_a": player_a_id,
		"player_b": player_b_id,
		"duel_id": duel_id,
		"room_id": room_id,
		"status": "started",
		"start_time": OS.get_unix_time(),
		"mode": "pvp_1v1"
	}

	#emit_signal("game_started", room_id, player_a_id, player_b_id)

	# ✅ Gọi get_game_state (tự động inject card_data)
	var state_a = get_game_state(duel_id, player_a_id)
	var state_b = get_game_state(duel_id, player_b_id)

	emit_signal("game_event", room_id, [{ "type": "GAME_STATE", "player_id": player_a_id, "state": state_a }])
	emit_signal("game_event", room_id, [{ "type": "GAME_STATE", "player_id": player_b_id, "state": state_b }])
	
	print("🎮 GameManager: Trận PvP '%s' đã tạo giữa %s và %s" % [room_id, player_a_id, player_b_id])
	return { "success": true, "duel_id": duel_id }

# ===========================================================================
# submit_action(room_id, action)
# ===========================================================================
func submit_action(room_id, action):
	if not active_games.has(room_id):
		return { "success": false, "error": "GAME_NOT_FOUND" }
	
	var player_id = action.get("player_id")
	if not player_id:
		return { "success": false, "error": "MISSING_PLAYER_ID" }
	
	var result = battle_core.submit_action(room_id, action)
	
	# ✅ Gắn available_actions
	result["available_actions"] = battle_core.get_available_actions(room_id, player_id)
	
	# ✅ Gửi events
	emit_signal("game_event", room_id, result.events)
	
	# ✅ Gửi CHAIN_TRIGGERED nếu cần
	for event in result.events:
		if event.type in ["ATTACK_DECLARED", "SUMMON", "FLIP_SUMMON", "SET_MONSTER", "PLAY_SPELL"]:
			var chain_trigger_event = {
				"type": "CHAIN_TRIGGERED",
				"trigger": event,
				"timestamp": OS.get_unix_time(),
				"can_respond": true
			}
			# ✅ Gửi thẳng vào mảng
			emit_signal("game_event", room_id, [chain_trigger_event])
	
	return result

# ===========================================================================
# get_game_state(room_id, player_id = null)
# Trả về trạng thái, đã bao gồm card_data
# ===========================================================================
func get_game_state(room_id, player_id = null):
	if not active_games.has(room_id):
		return null
	var state = battle_core.get_game_state(room_id, player_id)
	_inject_card_data(state)
	return state

# ===========================================================================
# end_game(room_id, winner, reason)
# ===========================================================================
func end_game(room_id, winner, reason):
	if not active_games.has(room_id):
		return

	var game = active_games[room_id]
	var player_a = game["player_a"]
	var player_b = game["player_b"]

	if winner == player_a:
		database_manager.update_stats(player_a, 1, 0, 0)
		database_manager.update_stats(player_b, 0, 1, 0)
		database_manager.add_match_history(player_a, player_b, "win", room_id)
		database_manager.add_match_history(player_b, player_a, "loss", room_id)
	elif winner == player_b:
		database_manager.update_stats(player_b, 1, 0, 0)
		database_manager.update_stats(player_a, 0, 1, 0)
		database_manager.add_match_history(player_b, player_a, "win", room_id)
		database_manager.add_match_history(player_a, player_b, "loss", room_id)

	emit_signal("game_event", room_id, [{"type": "WIN", "winner": winner, "reason": reason}])
	
	active_games.erase(room_id)
	emit_signal("game_finished", room_id, winner, reason)
	print("🏁 GameManager: Trận '%s' kết thúc. Người thắng: %s" % [room_id, winner])

# ===========================================================================
# create_duel_vs_bot(player_id)
# ===========================================================================
func create_duel_vs_bot(player_id):
	var bot_id = "bot_ai"
	var player_deck = database_manager.get_deck(player_id)
	var bot_deck = _get_bot_deck()

	var rules = { "start_lp": 8000, "max_hand_size": 6 }
	var room_id = battle_core.start_duel(player_id, bot_id, player_deck, bot_deck, rules)

	if typeof(room_id) != TYPE_STRING:
		return { "success": false, "error": "FAILED_TO_CREATE_DUEL" }

	active_games[room_id] = {
		"player_a": player_id,
		"player_b": bot_id,
		"room_id": room_id,
		"status": "started",
		"start_time": OS.get_unix_time(),
		"mode": "pve"
	}

	emit_signal("game_started", room_id, player_id, bot_id)
	print("🎮 GameManager: Trận PvE '%s' đã tạo giữa %s và %s" % [room_id, player_id, bot_id])

	_schedule_bot_turn(room_id)
	return { "success": true, "room_id": room_id }

func _get_bot_deck() -> Array:
	return [
		"BLUE_EYES_WHITE_DRAGON", "BLUE_EYES_WHITE_DRAGON", "SUMMONED_SKULL",
		"DARK_MAGICIAN", "GYOUKI", "SUIJIN", "KURIBOH", "MAN_EATER_BUTTERFLY",
		"DARK_HOLE", "MIRROR_FORCE", "TRAP_HOLE", "POT_OF_GREED", "CARD_OF_DESTRUCTION",
		"MONSTER_REBORN", "FACE_UP", "SACRIFICE", "OFFERING", "DRAGON", "WARRIOR", "SPELL"
	]

func _schedule_bot_turn(room_id):
	get_tree().create_timer(1.5).connect("timeout", self, "_run_bot_turn", [room_id])

func _run_bot_turn(room_id):
	if not active_games.has(room_id):
		return

	var game = active_games[room_id]
	var bot_id = game["player_b"]
	if bot_id != "bot_ai":
		return

	var state = battle_core.get_game_state(room_id)
	if not state or state.status != "active":
		return

	if state.turn == bot_id:
		var available_actions = battle_core.get_available_actions(room_id, bot_id)
		if available_actions.empty():
			return

		var action = YugiBot.choose_action(state, bot_id, available_actions)
		if action:
			action.player_id = bot_id
			var result = battle_core.submit_action(room_id, action)

			if Agent.learning_mode:
				Agent.learn_from_result(state, action, result)

			emit_signal("game_event", room_id, result.events)

	if state.turn != bot_id and state.status == "active":
		_schedule_bot_turn(room_id)

# ===========================================================================
# get_available_actions(room_id, player_id)
# ===========================================================================
func get_available_actions(room_id, player_id):
	if not active_games.has(room_id):
		return []
	return battle_core.get_available_actions(room_id, player_id)

# ===========================================================================
# _inject_card_data(state)
# ===========================================================================
func _inject_card_data(state):
	for pid in state.players:
		var player = state.players[pid]
		
		# Monster Zones
		for i in range(5):
			if player.monster_zones[i]:
				var card_id = player.monster_zones[i].card_id
				var data = CardDatabase.get(card_id)
				player.monster_zones[i]["card_data"] = {
					"name": data.get("name", "Unknown"),
					"type": data.get("type", "monster"),
					"atk": data.get("atk", 0),
					"def": data.get("def", 0),
					"effect": data.get("effect", ""),
					"level": data.get("level", 0)
				}
		
		# Spell/Trap Zones
		for i in range(5):
			if player.spell_trap_zones[i]:
				var card_id = player.spell_trap_zones[i].card_id
				var data = CardDatabase.get(card_id)
				player.spell_trap_zones[i]["card_data"] = {
					"name": data.get("name", "Unknown"),
					"type": data.get("type", "spell"),
					"effect": data.get("effect", "")
				}
		
		# Hand
		player["hand_data"] = []
		if player.has("hand") and player.hand is Array:
			for card_id in player.hand:
				var data = CardDatabase.get(card_id)
				player.hand_data.append({
					"card_id": card_id,
					"name": data.get("name", "Unknown"),
					"type": data.get("type", ""),
					"atk": data.get("atk", 0),
					"def": data.get("def", 0),
					"effect": data.get("effect", ""),
					"level": data.get("level", 0)
				})
