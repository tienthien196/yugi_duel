# ===========================================================================
# BattleCore.gd - Core xử lý trận đấu Yu-Gi-Oh! (Godot 3.6)
# Autoload Singleton - Dùng để quản lý toàn bộ logic trận đấu
# Không cần UI, không cần mạng - chỉ cần chạy trong Godot
# ===========================================================================

extends Node

# Danh sách các trận đang diễn ra: room_id → game_state
var active_duels = {}

# Thứ tự các phase trong một lượt
const TURN_PHASES = ["draw", "standby", "main1", "battle", "main2", "end"]

# Các lý do chiến thắng
const WIN_REASON_LP_ZERO = "lp_zero"
const WIN_REASON_DECK_OUT = "deck_out"
const WIN_REASON_SURRENDER = "surrender"
const WIN_REASON_EXODIA = "exodia"
const WIN_REASON_FORFEIT = "forfeit"

# Error codes
const ERR_ROOM_NOT_FOUND = "ROOM_NOT_FOUND"
const ERR_DUEL_NOT_ACTIVE = "DUEL_NOT_ACTIVE"
const ERR_INVALID_PLAYER = "INVALID_PLAYER"
const ERR_NOT_YOUR_TURN = "NOT_YOUR_TURN"
const ERR_NOT_IN_DRAW_PHASE = "NOT_IN_DRAW_PHASE"
const ERR_NO_DRAW_FIRST_TURN = "NO_DRAW_FIRST_TURN"
const ERR_DECK_EMPTY = "DECK_EMPTY"
const ERR_CARD_NOT_IN_HAND = "CARD_NOT_IN_HAND"
const ERR_ZONE_OCCUPIED = "ZONE_OCCUPIED"
const ERR_NOT_IN_MAIN_PHASE = "NOT_IN_MAIN_PHASE"
const ERR_NOT_MONSTER_CARD = "NOT_MONSTER_CARD"
const ERR_NOT_SPELL_CARD = "NOT_SPELL_CARD"
const ERR_NOT_TRAP_CARD = "NOT_TRAP_CARD"
const ERR_SPELL_ZONE_OCCUPIED = "SPELL_ZONE_OCCUPIED"
const ERR_TRAP_ZONE_OCCUPIED = "TRAP_ZONE_OCCUPIED"
const ERR_INVALID_ZONE = "INVALID_ZONE"
const ERR_CANNOT_CHANGE_POS_THIS_TURN = "CANNOT_CHANGE_POS_THIS_TURN"
const ERR_SAME_POSITION = "SAME_POSITION"
const ERR_CARD_NOT_ON_FIELD = "CARD_NOT_ON_FIELD"
const ERR_NO_EFFECT = "NO_EFFECT"
const ERR_NOT_IN_BATTLE_PHASE = "NOT_IN_BATTLE_PHASE"
const ERR_INVALID_ATTACKER = "INVALID_ATTACKER"
const ERR_NOT_IN_ATTACK_POSITION = "NOT_IN_ATTACK_POSITION"
const ERR_ALREADY_ATTACKED = "ALREADY_ATTACKED"
const ERR_CANNOT_ATTACK_SUMMON_TURN = "CANNOT_ATTACK_SUMMON_TURN"
const ERR_CANNOT_DIRECT_ATTACK = "CANNOT_DIRECT_ATTACK"
const ERR_INVALID_TARGET = "INVALID_TARGET"
const ERR_INVALID_PHASE = "INVALID_PHASE"
const ERR_INVALID_CARD = "INVALID_CARD"

# ===========================================================================
# start_duel(player_a_id, player_b_id, deck_a, deck_b, rules)
# Tạo một trận đấu mới
# ===========================================================================
func start_duel(player_a_id, player_b_id, deck_a, deck_b, rules = {}):
	var room_id: String = "duel_%d_%d" % [OS.get_unix_time(), randi() % 10000]



	
	# Validate deck
	for card_id in deck_a + deck_b:
		if not CardDatabase.exists(card_id):
			return _error(ERR_INVALID_CARD)
		if card_id in rules.get("forbidden_cards", []):
			return _error("FORBIDDEN_CARD_IN_DECK")
	
	# Sao chép và xáo bài
	var deck_a_copy = deck_a.duplicate(true)
	var deck_b_copy = deck_b.duplicate(true)
	_shuffle(deck_a_copy)
	_shuffle(deck_b_copy)
	
	# Bốc 5 bài đầu
	var hand_a = _draw_cards(deck_a_copy, 5)
	var hand_b = _draw_cards(deck_b_copy, 5)
	
	# Chọn ai đi trước
	var first_player = [player_a_id, player_b_id][randi() % 2]
	
	# Tạo trạng thái trận đấu
	var start_lp = rules.get("start_lp", 8000)
	var game_state = {
		"room_id": room_id,
		"turn": first_player,
		"phase": "draw",
		"current_turn_count": 1,
		"is_first_turn": true,
		"first_player": first_player,
		"players": {
			player_a_id: _create_player_state(player_a_id, deck_a_copy, hand_a, start_lp),
			player_b_id: _create_player_state(player_b_id, deck_b_copy, hand_b, start_lp)
		},
		"status": "active",
		"winner": null,
		"win_reason": null,
		"chain": [],
		"chain_trigger": null,  # Lưu hành động trigger chain
		"rules": {
			"start_lp": start_lp,
			"max_hand_size": rules.get("max_hand_size", 6),
			"forbidden_cards": rules.get("forbidden_cards", [])
		}
	}
	
	# Lưu vào hệ thống
	active_duels[room_id] = game_state
	print("✅ BattleCore: Trận '%s' đã khởi tạo. Người đi trước: %s" % [room_id, first_player])
	var temp: String = room_id
	
	
	return temp


# ===========================================================================
# submit_action(room_id, action)
# Xử lý hành động từ người chơi hoặc bot
# Trả về: { success, events, available_actions, errors }
# ===========================================================================
func submit_action(room_id, action):
	if not active_duels.has(room_id):
		return _error(ERR_ROOM_NOT_FOUND)
	
	var game_state = active_duels[room_id]
	if game_state["status"] != "active":
		return _error(ERR_DUEL_NOT_ACTIVE)
	
	var player_id = action.get("player_id", "")
	if not game_state["players"].has(player_id):
		return _error(ERR_INVALID_PLAYER)
	
	# Kiểm tra lượt đi (trừ khi chain hoặc quick effect)
	if game_state["turn"] != player_id and action["type"] != "ACTIVATE_EFFECT":
		if not _can_activate_effect_out_of_turn(game_state, action):
			return _error(ERR_NOT_YOUR_TURN)
	
	# Xử lý hành động
	var result = _process_action(game_state, action)
	
	# Cập nhật trạng thái
	if result["success"] and action["type"] == "ACTIVATE_EFFECT":
		_resolve_chain(game_state, action)
	
	# Cập nhật lại trạng thái
	active_duels[room_id] = game_state
	
	# Kiểm tra điều kiện chiến thắng
	var win_check = _check_win_condition(game_state)
	if win_check.winner:
		game_state["winner"] = win_check.winner
		game_state["win_reason"] = win_check.reason
		game_state["status"] = "finished"
		result["events"].append({
			"type": "WIN",
			"winner": win_check.winner,
			"reason": win_check.reason
		})
	elif result["success"] and game_state["chain"].empty():
		_update_phase_if_needed(game_state)
	
	# Gán danh sách hành động khả dụng
	result["available_actions"] = _get_available_actions(game_state, player_id)
	result["game_state"] = game_state.duplicate(true)
	
	return result


# ===========================================================================
# get_game_state(room_id, player_id)
# Trả về trạng thái trận, ẩn bài trên tay đối thủ
# ===========================================================================
func get_game_state(room_id, player_id):
	if not active_duels.has(room_id):
		return {}
	
	var game_state = active_duels[room_id].duplicate(true)
	var opponent_id = _get_opponent_id(game_state, player_id)
	
	if game_state["players"].has(opponent_id):
		var opponent = game_state["players"][opponent_id]
		opponent["hand"] = []  # Ẩn bài
		opponent["hand_count"] = len(opponent["hand"])  # Giữ số lượng
	
	return game_state


# ===========================================================================
# get_available_actions(room_id, player_id)
# Trả về danh sách hành động hợp lệ (dùng cho bot)
# ===========================================================================
func get_available_actions(room_id, player_id):
	if not active_duels.has(room_id):
		return []
	var game_state = active_duels[room_id]
	return _get_available_actions(game_state, player_id)


# ===========================================================================
# end_duel(room_id, winner, reason)
# Kết thúc trận đấu (dùng cho test, lỗi, v.v.)
# ===========================================================================
func end_duel(room_id, winner, reason = WIN_REASON_FORFEIT):
	if not active_duels.has(room_id):
		return
	var game_state = active_duels[room_id]
	game_state["winner"] = winner
	game_state["win_reason"] = reason
	game_state["status"] = "finished"
	print("🏁 Trận '%s' kết thúc. Người thắng: %s | Lý do: %s" % [room_id, winner, reason])


# ===========================================================================
# HÀM XỬ LÝ HÀNH ĐỘNG
# ===========================================================================
func _process_action(game_state, action):
	var player_id = action["player_id"]
	var result = {
		"success": false,
		"events": [],
		"errors": []
	}
	
	match action["type"]:
		"DRAW_CARD":
			result = _action_draw_card(game_state, player_id)
		"PLAY_MONSTER":
			result = _action_play_monster(game_state, player_id, action["payload"])
		"SET_MONSTER":
			result = _action_set_monster(game_state, player_id, action["payload"])
		"PLAY_SPELL", "SET_SPELL":
			result = _action_play_spell(game_state, player_id, action["payload"], action["type"] == "SET_SPELL")
		"PLAY_TRAP", "SET_TRAP":
			result = _action_play_trap(game_state, player_id, action["payload"], action["type"] == "SET_TRAP")
		"END_TURN":
			result = _action_end_turn(game_state, player_id)
		"SURRENDER":
			result = _action_surrender(game_state, player_id)
		"CHANGE_POSITION":
			result = _action_change_position(game_state, player_id, action["payload"])
		"ACTIVATE_EFFECT":
			result = _action_activate_effect(game_state, player_id, action["payload"])
		"DECLARE_ATTACK":
			result = _action_declare_attack(game_state, player_id, action["payload"])
		"END_PHASE":
			result = _action_end_phase(game_state, player_id)
		_:
			result["errors"].append("UNKNOWN_ACTION")
	
	if result["success"]:
		print("✅ Action: %s | Player: %s" % [action["type"], player_id])
	else:
		var error_msg = result["errors"][0] if len(result["errors"]) > 0 else "Unknown"
		print("❌ Action failed: %s | Error: %s" % [action["type"], error_msg])
	
	return result


# ===========================================================================
# CÁC HÀM HÀNH ĐỘNG CHI TIẾT
# ===========================================================================
func _action_draw_card(game_state, player_id):
	var player = game_state["players"][player_id]
	if game_state["phase"] != "draw":
		return _error(ERR_NOT_IN_DRAW_PHASE)
	if game_state["is_first_turn"] and player_id == game_state["first_player"]:
		return _error(ERR_NO_DRAW_FIRST_TURN)
	if player["deck"].empty():
		return _error(ERR_DECK_EMPTY)
	
	var card = player["deck"].pop_front()
	player["hand"].append(card)
	
	return {
		"success": true,
		"events": [
			{ "type": "DRAW_CARD", "card_id": card, "player": player_id }
		]
	}

func _action_play_monster(game_state, player_id, payload):
	var player = game_state["players"][player_id]
	var card_id = payload["card_id"]
	var to_zone = payload["to_zone"]
	var position = payload.get("position", "face_up_attack")

	if not player["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or player["monster_zones"][to_zone] != null:
		return _error(ERR_ZONE_OCCUPIED)
	if not game_state["phase"] in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	if CardDatabase.get(card_id).get("type") != "monster":
		return _error(ERR_NOT_MONSTER_CARD)

	player["hand"].erase(card_id)
	player["monster_zones"][to_zone] = {
		"card_id": card_id,
		"position": position,
		"status": "summoned_this_turn",
		"attacked_this_turn": false
	}

	return {
		"success": true,
		"events": [
			{ "type": "SUMMON", "card_id": card_id, "player": player_id, "zone": to_zone }
		]
	}

func _action_set_monster(game_state, player_id, payload):
	var player = game_state["players"][player_id]
	var card_id = payload["card_id"]
	var to_zone = payload["to_zone"]

	if not player["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or player["monster_zones"][to_zone] != null:
		return _error(ERR_ZONE_OCCUPIED)
	if not game_state["phase"] in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	if CardDatabase.get(card_id).get("type") != "monster":
		return _error(ERR_NOT_MONSTER_CARD)

	player["hand"].erase(card_id)
	player["monster_zones"][to_zone] = {
		"card_id": card_id,
		"position": "face_down_defense",
		"status": "set_this_turn",
		"attacked_this_turn": false
	}

	return {
		"success": true,
		"events": [
			{ "type": "SET_MONSTER", "card_id": card_id, "player": player_id, "zone": to_zone }
		]
	}

func _action_play_spell(game_state, player_id, payload, is_set):
	var player = game_state["players"][player_id]
	var card_id = payload["card_id"]
	var to_zone = payload["to_zone"]

	if not player["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or player["spell_trap_zones"][to_zone] != null:
		return _error(ERR_SPELL_ZONE_OCCUPIED)
	if not game_state["phase"] in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	if CardDatabase.get(card_id).get("type") != "spell":
		return _error(ERR_NOT_SPELL_CARD)

	player["hand"].erase(card_id)
	var status = "face_down" if is_set else "face_up"
	player["spell_trap_zones"][to_zone] = {
		"card_id": card_id,
		"status": status
	}

	var event_type = "SET_SPELL" if is_set else "PLAY_SPELL"

	return {
		"success": true,
		"events": [
			{ "type": event_type, "card_id": card_id, "player": player_id, "zone": to_zone }
		]
	}

func _action_play_trap(game_state, player_id, payload, is_set):
	var player = game_state["players"][player_id]
	var card_id = payload["card_id"]
	var to_zone = payload["to_zone"]

	if not player["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or player["spell_trap_zones"][to_zone] != null:
		return _error(ERR_TRAP_ZONE_OCCUPIED)
	if CardDatabase.get(card_id).get("type") != "trap":
		return _error(ERR_NOT_TRAP_CARD)

	player["hand"].erase(card_id)
	var status = "face_down" if is_set else "face_up"
	player["spell_trap_zones"][to_zone] = {
		"card_id": card_id,
		"status": status
	}

	var event_type = "SET_TRAP" if is_set else "ACTIVATE_TRAP"

	return {
		"success": true,
		"events": [
			{ "type": event_type, "card_id": card_id, "player": player_id, "zone": to_zone }
		]
	}

func _action_end_turn(game_state, player_id):
	if game_state["turn"] != player_id:
		return _error(ERR_NOT_YOUR_TURN)
	
	_reset_turn_flags(game_state["players"][player_id])
	game_state["turn"] = _get_opponent_id(game_state, player_id)
	game_state["phase"] = "draw"
	game_state["current_turn_count"] += 1
	game_state["is_first_turn"] = false
	game_state["chain"] = []
	game_state["chain_trigger"] = null

	return {
		"success": true,
		"events": [
			{ "type": "TURN_CHANGED", "next_player": game_state["turn"] }
		]
	}

func _action_surrender(game_state, player_id):
	var opponent_id = _get_opponent_id(game_state, player_id)
	game_state["winner"] = opponent_id
	game_state["win_reason"] = WIN_REASON_SURRENDER
	game_state["status"] = "finished"

	return {
		"success": true,
		"events": [
			{ "type": "WIN", "winner": opponent_id, "reason": WIN_REASON_SURRENDER }
		]
	}

func _action_change_position(game_state, player_id, payload):
	var player = game_state["players"][player_id]
	var zone_idx = payload["zone"]
	var to_position = payload["to_position"]  # e.g., "face_up_attack", "face_up_defense", "face_down_defense"

	if zone_idx < 0 or zone_idx >= 5 or player["monster_zones"][zone_idx] == null:
		return _error(ERR_INVALID_ZONE)
	var card_obj = player["monster_zones"][zone_idx]
	if card_obj.get("status") in ["summoned_this_turn", "set_this_turn"]:
		return _error(ERR_CANNOT_CHANGE_POS_THIS_TURN)
	if card_obj["position"] == to_position:
		return _error(ERR_SAME_POSITION)

	# Validate position
	if not to_position in ["face_up_attack", "face_up_defense", "face_down_defense"]:
		return _error("INVALID_POSITION")
	
	card_obj["position"] = to_position
	if to_position == "face_up_defense" and card_obj["position"] == "face_down_defense":
		# Flip summon
		return {
			"success": true,
			"events": [
				{ "type": "FLIP_SUMMON", "card_id": card_obj["card_id"], "zone": zone_idx, "player": player_id }
			]
		}

	return {
		"success": true,
		"events": [
			{ "type": "CHANGE_POSITION", "zone": zone_idx, "to_position": to_position, "player": player_id }
		]
	}

# ===========================================================================
# _action_activate_effect(game_state, player_id, payload)
# Kích hoạt hiệu ứng của quái, spell, trap → thêm vào chain
# ===========================================================================
func _action_activate_effect(game_state, player_id, payload):
	var card_id = payload["card_id"]
	var zone_type = payload.get("zone_type", "spell_trap")
	var player = game_state["players"][player_id]
	
	# Tìm vị trí
	var zone_idx = -1
	var zones = player["spell_trap_zones"] if zone_type == "spell_trap" else player["monster_zones"]
	for i in range(5):
		if zones[i] and zones[i].card_id == card_id:
			zone_idx = i
			break
	if zone_idx == -1:
		return _error(ERR_CARD_NOT_ON_FIELD)

	# Kiểm tra điều kiện
	if zone_type == "spell_trap" and zones[zone_idx].status != "face_up":
		return _error("CARD_NOT_ACTIVATABLE")
	if zone_type == "monster":
		var card_data = CardDatabase.get(card_id)
		if not card_data.has("effect") or card_data["effect"] == "":
			return _error(ERR_NO_EFFECT)
		# ✅ Kiểm tra: SUIJIN chỉ kích hoạt khi có tấn công
		if card_id == "SUIJIN" and (not game_state["chain_trigger"] or game_state["chain_trigger"].get("type") != "ATTACK_DECLARED"):
			return _error("EFFECT_CANNOT_ACTIVATE_NOW")

	# Thêm vào chain
	game_state["chain"].append({
		"card_id": card_id,
		"player_id": player_id,
		"zone_type": zone_type,
		"zone_idx": zone_idx
	})

	return {
		"success": true,
		"events": [
			{"type": "ACTIVATE_EFFECT", "card_id": card_id, "player": player_id}
		]
	}


func _action_declare_attack(game_state, player_id, payload):
	var player = game_state["players"][player_id]
	var opponent_id = _get_opponent_id(game_state, player_id)
	var opponent = game_state["players"][opponent_id]
	var atk_zone = payload["atk_zone"]
	var target_zone = payload.get("target_zone", -1)

	if game_state["phase"] != "battle":
		return _error(ERR_NOT_IN_BATTLE_PHASE)
	if atk_zone < 0 or atk_zone >= 5 or player["monster_zones"][atk_zone] == null:
		return _error(ERR_INVALID_ATTACKER)
	var attacker = player["monster_zones"][atk_zone]
	if attacker.position != "face_up_attack":
		return _error(ERR_NOT_IN_ATTACK_POSITION)
	if attacker.get("attacked_this_turn", false):
		return _error(ERR_ALREADY_ATTACKED)
	if attacker.get("status") == "summoned_this_turn":
		return _error(ERR_CANNOT_ATTACK_SUMMON_TURN)

	var events = []
	var atk = CardDatabase.get(attacker.card_id).get("atk", 0)

	# Kích hoạt chain cho attack
	game_state["chain_trigger"] = {"type": "ATTACK_DECLARED", "attacker_zone": atk_zone, "player_id": player_id}
	events.append({"type": "ATTACK_DECLARED", "attacker": attacker.card_id, "zone": atk_zone})

	if target_zone == -1:
		# Direct attack
		var has_monster = false
		for zone in opponent["monster_zones"]:
			if zone != null:
				has_monster = true
				break
		if has_monster:
			return _error(ERR_CANNOT_DIRECT_ATTACK)
		opponent["life_points"] = max(0, opponent["life_points"] - atk)
		events.append({"type": "DIRECT_ATTACK", "attacker": attacker.card_id, "damage": atk})
	else:
		if target_zone < 0 or target_zone >= 5 or opponent["monster_zones"][target_zone] == null:
			return _error(ERR_INVALID_TARGET)
		var target = opponent["monster_zones"][target_zone]
		var target_pos = target.position
		# ✅ SỬA: Dùng find() thay vì contains()
		var is_defense = target_pos.find("defense") != -1
		var target_val = CardDatabase.get(target.card_id).get("def", 0) if is_defense else CardDatabase.get(target.card_id).get("atk", 0)

		# Flip if face down
		if target_pos == "face_down_defense":
			target.position = "face_up_defense"
			events.append({"type": "FLIP", "card_id": target.card_id})

		if atk > target_val:
			var damage = atk - target_val
			if is_defense:
				damage = 0
			else:
				opponent["life_points"] = max(0, opponent["life_points"] - damage)
			opponent["monster_zones"][target_zone] = null
			opponent["graveyard"].append(target.card_id)
			events.append({"type": "DESTROY_TARGET", "damage": damage})
		elif atk == target_val:
			if not is_defense:
				player["monster_zones"][atk_zone] = null
				player["graveyard"].append(attacker.card_id)
			opponent["monster_zones"][target_zone] = null
			opponent["graveyard"].append(target.card_id)
			events.append({"type": "DESTROY_BOTH"})
		else:
			var damage = target_val - atk
			player["life_points"] = max(0, player["life_points"] - damage)
			if not is_defense:
				player["monster_zones"][atk_zone] = null
				player["graveyard"].append(attacker.card_id)
			events.append({"type": "REBOUND", "damage": damage})

	attacker.attacked_this_turn = true
	return {"success": true, "events": events}

func _action_end_phase(game_state, player_id):
	if game_state["turn"] != player_id:
		return _error(ERR_NOT_YOUR_TURN)
	var idx = TURN_PHASES.find(game_state["phase"])
	if idx == -1 or idx >= len(TURN_PHASES) - 1:
		return _error(ERR_INVALID_PHASE)
	game_state["phase"] = TURN_PHASES[idx + 1]
	var events = [{"type": "PHASE_CHANGED", "new_phase": game_state["phase"]}]
	
	if game_state["phase"] == "end":
		var player = game_state["players"][player_id]
		if len(player["hand"]) > game_state["rules"].max_hand_size:
			var discard_count = len(player["hand"]) - game_state["rules"].max_hand_size
			for i in range(discard_count):
				var card = player["hand"].pop_back()
				player["graveyard"].append(card)
			events.append({"type": "DISCARD_HAND", "count": discard_count})
	
	return {"success": true, "events": events}


# ===========================================================================
# HÀM HỖ TRỢ
# ===========================================================================
func _create_player_state(player_id, deck, hand, lp):
	return {
		"player_id": player_id,
		"life_points": lp,
		"deck": deck,
		"hand": hand,
		"graveyard": [],
		"banished": [],
		"extra_deck": [],
		"monster_zones": [null, null, null, null, null],
		"spell_trap_zones": [null, null, null, null, null],
		"field_zone": null,
		"pendulum_zones": [null, null]
	}

func _shuffle(array):
	var n = len(array)
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp
	return array

func _draw_cards(deck, count):
	var cards = []
	for i in range(min(count, len(deck))):
		cards.append(deck.pop_front())
	return cards

func _can_activate_effect_out_of_turn(game_state, action):
	if action["type"] != "ACTIVATE_EFFECT":
		return false
	var card_id = action["payload"]["card_id"]
	var card_data = CardDatabase.get(card_id)
	return card_data.get("type") == "trap" or card_data.get("effect") in ["quick_effect"]  # Mở rộng sau

func _get_opponent_id(game_state, player_id):
	for pid in game_state["players"]:
		if pid != player_id:
			return pid
	return null

func _update_phase_if_needed(game_state):
	if game_state["phase"] == "draw" and game_state["chain"].empty():
		if not (game_state["is_first_turn"] and game_state["turn"] == game_state["first_player"]):
			var player = game_state["players"][game_state["turn"]]
			if not player["deck"].empty():
				var card = player["deck"].pop_front()
				player["hand"].append(card)
				print("Auto draw: %s" % card)
		game_state["phase"] = "standby"

func _get_available_actions(game_state, player_id):
	var actions = []
	var phase = game_state["phase"]
	var player = game_state["players"][player_id]
	var opponent_id = _get_opponent_id(game_state, player_id)
	
	var action_details = []
	if game_state["turn"] == player_id:
		action_details += [
			{"type": "END_PHASE"},
			{"type": "END_TURN"},
			{"type": "SURRENDER"}
		]
	
	if phase == "draw" and game_state["turn"] == player_id:
		if not (game_state["is_first_turn"] and player_id == game_state["first_player"]):
			action_details.append({"type": "DRAW_CARD"})
	
	if phase in ["main1", "main2"] and game_state["turn"] == player_id:
		for card_id in player["hand"]:
			var card_data = CardDatabase.get(card_id)
			var card_type = card_data.get("type", "")
			for i in range(5):
				if card_type == "monster" and player["monster_zones"][i] == null:
					action_details.append({
						"type": "PLAY_MONSTER",
						"payload": {"card_id": card_id, "to_zone": i, "position": "face_up_attack"}
					})
					action_details.append({
						"type": "SET_MONSTER",
						"payload": {"card_id": card_id, "to_zone": i}
					})
				elif card_type == "spell" and player["spell_trap_zones"][i] == null:
					action_details.append({
						"type": "PLAY_SPELL",
						"payload": {"card_id": card_id, "to_zone": i}
					})
					action_details.append({
						"type": "SET_SPELL",
						"payload": {"card_id": card_id, "to_zone": i}
					})
				elif card_type == "trap" and player["spell_trap_zones"][i] == null:
					action_details.append({
						"type": "PLAY_TRAP",
						"payload": {"card_id": card_id, "to_zone": i}
					})
					action_details.append({
						"type": "SET_TRAP",
						"payload": {"card_id": card_id, "to_zone": i}
					})
		for i in range(5):
			if player["monster_zones"][i] and not player["monster_zones"][i].get("status") in ["summoned_this_turn", "set_this_turn"]:
				for pos in ["face_up_attack", "face_up_defense", "face_down_defense"]:
					if pos != player["monster_zones"][i].position:
						action_details.append({
							"type": "CHANGE_POSITION",
							"payload": {"zone": i, "to_position": pos}
						})
			if player["monster_zones"][i] and CardDatabase.get(player["monster_zones"][i].card_id).get("effect") != "":
				action_details.append({
					"type": "ACTIVATE_EFFECT",
					"payload": {"card_id": player["monster_zones"][i].card_id, "zone_type": "monster"}
				})
			if player["spell_trap_zones"][i] and player["spell_trap_zones"][i].status == "face_up" and CardDatabase.get(player["spell_trap_zones"][i].card_id).get("effect") != "":
				action_details.append({
					"type": "ACTIVATE_EFFECT",
					"payload": {"card_id": player["spell_trap_zones"][i].card_id, "zone_type": "spell_trap"}
				})
	
	if phase == "battle" and game_state["turn"] == player_id:
		for i in range(5):
			if player["monster_zones"][i] and player["monster_zones"][i].position == "face_up_attack" and not player["monster_zones"][i].get("attacked_this_turn", false) and not player["monster_zones"][i].get("status") == "summoned_this_turn":
				var has_monster = false
				for j in range(5):
					if game_state["players"][opponent_id].monster_zones[j]:
						has_monster = true
						action_details.append({
							"type": "DECLARE_ATTACK",
							"payload": {"atk_zone": i, "target_zone": j}
						})
				if not has_monster:
					action_details.append({
						"type": "DECLARE_ATTACK",
						"payload": {"atk_zone": i}
					})
	
	# Thêm hành động cho chain
	if not game_state["chain"].empty() and game_state["turn"] != player_id:
		for i in range(5):
			var card = player["spell_trap_zones"][i]
			if card and card["status"] == "face_down" and CardDatabase.get(card["card_id"]).get("type") == "trap":
				action_details.append({
					"type": "ACTIVATE_EFFECT",
					"payload": {"card_id": card["card_id"], "zone_type": "spell_trap"}
				})
	
	# Chỉ lấy type để tránh payload ascendedpayload dài
	for action in action_details:
		if not action["type"] in actions:
			actions.append(action["type"])
	
	return {"types": actions, "details": action_details}

func _resolve_chain(game_state, action):
	if game_state["chain"].empty():
		return
	
	# Resolve chain theo thứ tự ngược
	var events = []
	for chain_link in game_state["chain"]:
		var card_id = chain_link["card_id"]
		var player_id = chain_link["player_id"]
		var zone_type = chain_link["zone_type"]
		var zone_idx = chain_link["zone_idx"]
		var player = game_state["players"][player_id]
		var opponent_id = _get_opponent_id(game_state, player_id)
		var opponent = game_state["players"][opponent_id]
		
		var resolve_result = _resolve_effect(game_state, card_id, player, opponent, zone_type, zone_idx)
		events += resolve_result.events
		if not resolve_result.success:
			return resolve_result
	
	game_state["chain"] = []
	game_state["chain_trigger"] = null
	return {"success": true, "events": events}

func _resolve_effect(game_state, card_id, player, opponent, zone_type, zone_idx):
	var effect = CardDatabase.get(card_id).get("effect", "")
	var events = []
	
	match effect:
		"draw_2":
			var drawn = _draw_cards(player["deck"], 2)
			player["hand"] += drawn
			events.append({"type": "DRAW_EFFECT", "cards": drawn, "player": player["player_id"]})
		"special_summon_graveyard":
			if player["graveyard"].empty():
				return _error("NO_CARDS_IN_GRAVEYARD")
			var summon_card = player["graveyard"].pop_back()
			var free_zone = -1
			for i in range(5):
				if player["monster_zones"][i] == null:
					free_zone = i
					break
			if free_zone == -1:
				return _error(ERR_ZONE_OCCUPIED)
			player["monster_zones"][free_zone] = {
				"card_id": summon_card,
				"position": "face_up_attack",
				"status": "summoned_this_turn",
				"attacked_this_turn": false
			}
			events.append({"type": "SPECIAL_SUMMON", "card_id": summon_card, "zone": free_zone})
		"destroy_all_monsters":
			for i in range(5):
				if player["monster_zones"][i]:
					player["graveyard"].append(player["monster_zones"][i].card_id)
					player["monster_zones"][i] = null
				if opponent["monster_zones"][i]:
					opponent["graveyard"].append(opponent["monster_zones"][i].card_id)
					opponent["monster_zones"][i] = null
			events.append({"type": "DESTROY_ALL_MONSTERS"})
		"destroy_all_attackers":
			for i in range(5):
				var zone = opponent["monster_zones"][i]
				if zone and zone.position.find("attack") != -1:
					opponent["graveyard"].append(zone.card_id)
					opponent["monster_zones"][i] = null
			events.append({"type": "DESTROY_MONSTERS", "player": opponent["player_id"]})
		"destroy_summoned_monster":
			var summoned = false
			for i in range(5):
				if opponent["monster_zones"][i] and opponent["monster_zones"][i].get("status") == "summoned_this_turn":
					opponent["graveyard"].append(opponent["monster_zones"][i].card_id)
					opponent["monster_zones"][i] = null
					summoned = true
					break
			if not summoned:
				return _error("NO_SUMMONED_MONSTER")
			events.append({"type": "DESTROY_MONSTER", "player": opponent["player_id"]})
		"reduce_atk_0":
			if game_state["chain_trigger"] and game_state["chain_trigger"].type == "ATTACK_DECLARED":
				var atk_zone = game_state["chain_trigger"].attacker_zone
				var atk_player = game_state["players"][game_state["chain_trigger"].player_id]
				if atk_player.monster_zones[atk_zone]:
					atk_player.monster_zones[atk_zone].atk_modifier = 0
					events.append({"type": "ATK_MODIFIED", "card_id": atk_player.monster_zones[atk_zone].card_id, "new_atk": 0})
		_:
			return _error(ERR_NO_EFFECT)
	
	# Xóa card spell/trap sau khi activate (trừ continuous)
	if zone_type == "spell_trap" and not effect in ["continuous_effect"]:
		player["spell_trap_zones"][zone_idx] = null
		player["graveyard"].append(card_id)
	
	return {"success": true, "events": events}

func _check_win_condition(game_state):
	for pid in game_state["players"]:
		var p = game_state["players"][pid]
		if p.life_points <= 0:
			return {"winner": _get_opponent_id(game_state, pid), "reason": WIN_REASON_LP_ZERO}
		if len(p.deck) == 0 and game_state["phase"] == "draw":
			return {"winner": _get_opponent_id(game_state, pid), "reason": WIN_REASON_DECK_OUT}
		var exodia_pieces = ["EXODIA_HEAD", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"]
		var has_all_exodia = true
		for piece in exodia_pieces:
			if not piece in p.hand:
				has_all_exodia = false
				break
		if has_all_exodia:
			return {"winner": pid, "reason": WIN_REASON_EXODIA}
	return {"winner": null, "reason": null}

func _reset_turn_flags(player):
	for i in range(5):
		if player["monster_zones"][i]:
			player["monster_zones"][i].erase("status")
			player["monster_zones"][i].erase("attacked_this_turn")
			player["monster_zones"][i].erase("atk_modifier")

func _error(reason):
	return {
		"success": false,
		"errors": [reason],
		"events": [],
		"available_actions": []
	}



