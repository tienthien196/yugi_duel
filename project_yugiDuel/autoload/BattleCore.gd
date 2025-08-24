# ===========================================================================
# BattleCore.gd - Core xử lý trận đấu Yu-Gi-Oh! (Godot 3.6)
# Autoload Singleton - Dùng để quản lý toàn bộ logic trận đấu
# Không cần UI, không cần mạng - chỉ cần chạy trong Godot
# ===========================================================================

extends Node

# Danh sách các trận đang diễn ra: room_id → game_state
var active_duels = {}

# Thứ tự các phase trong một lượt
const TURN_PHASES = [
	"draw",
	"standby",
	"main1",
	"battle",
	"main2",
	"end"
]

# Các lý do chiến thắng
const WIN_REASON_LP_ZERO = "lp_zero"
const WIN_REASON_DECK_OUT = "deck_out"
const WIN_REASON_SURRENDER = "surrender"
const WIN_REASON_EXODIA = "exodia"
const WIN_REASON_FORFEIT = "forfeit"

# ===========================================================================
# start_duel(player_a_id, player_b_id, deck_a, deck_b, rules)
# Tạo một trận đấu mới
# ===========================================================================
func start_duel(player_a_id, player_b_id, deck_a, deck_b, rules = {}):
	var room_id = "duel_%d_%d" % [OS.get_unix_time(), randi() % 10000]
	
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
	var game_state = {
		"room_id": room_id,
		"turn": first_player,
		"phase": "draw",
		"current_turn_count": 1,
		"players": {
			player_a_id: _create_player_state(player_a_id, deck_a_copy, hand_a),
			player_b_id: _create_player_state(player_b_id, deck_b_copy, hand_b)
		},
		"status": "active",
		"winner": null,
		"win_reason": null,
		"chain": [],
		"rules": {
			"start_lp": rules.get("start_lp", 8000),
			"max_hand_size": rules.get("max_hand_size", 6),
			"forbidden_cards": rules.get("forbidden_cards", [])
		}
	}
	
	# Lưu vào hệ thống
	active_duels[room_id] = game_state
	print("✅ BattleCore: Trận '%s' đã khởi tạo. Người đi trước: %s" % [room_id, first_player])
	
	return room_id


# ===========================================================================
# submit_action(room_id, action)
# Xử lý hành động từ người chơi hoặc bot
# Trả về: { success, events, available_actions, errors }
# ===========================================================================
func submit_action(room_id, action):
	if not active_duels.has(room_id):
		return _error("ROOM_NOT_FOUND")
	
	var game_state = active_duels[room_id]
	if game_state.status != "active":
		return _error("DUEL_NOT_ACTIVE")
	
	var player_id = action.get("player_id", "")
	if not game_state.players.has(player_id):
		return _error("INVALID_PLAYER")
	
	# Kiểm tra lượt đi (trừ khi là kích hoạt hiệu ứng)
	if game_state.turn != player_id and action.type != "ACTIVATE_EFFECT":
		if not _can_activate_effect_out_of_turn(game_state, action):
			return _error("NOT_YOUR_TURN")
	
	# Xử lý hành động
	var result = _process_action(game_state, action)
	
	# Cập nhật lại trạng thái
	active_duels[room_id] = game_state
	
	# Kiểm tra điều kiện chiến thắng
	var win_check = _check_win_condition(game_state)
	if win_check.winner:
		game_state.winner = win_check.winner
		game_state.win_reason = win_check.reason
		game_state.status = "finished"
		result.events.append({
			"type": "WIN",
			"winner": win_check.winner,
			"reason": win_check.reason
		})
	elif result.success:
		# Chỉ chuyển phase nếu không có chain
		if game_state.chain.empty():
			_update_phase_if_needed(game_state)
	
	# Gán danh sách hành động khả dụng
	result.available_actions = _get_available_actions(game_state, player_id)
	result.game_state = game_state
	
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
	
	if game_state.players.has(opponent_id):
		var opponent = game_state.players[opponent_id]
		opponent.hand = []  # Ẩn bài
		opponent.hand_count = opponent.hand.size()  # Có thể giữ số lượng
	
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
	game_state.winner = winner
	game_state.win_reason = reason
	game_state.status = "finished"
	print("🏁 Trận '%s' kết thúc. Người thắng: %s | Lý do: %s" % [room_id, winner, reason])


# ===========================================================================
# HÀM XỬ LÝ HÀNH ĐỘNG
# ===========================================================================
func _process_action(game_state, action):
	var player_id = action.player_id
	var result = {
		"success": false,
		"events": [],
		"errors": []
	}
	
	match action.type:
		"DRAW_CARD":
			result = _action_draw_card(game_state, player_id)
		"PLAY_MONSTER":
			result = _action_play_monster(game_state, player_id, action.payload)
		"SET_MONSTER":
			result = _action_set_monster(game_state, player_id, action.payload)
		"PLAY_SPELL", "SET_SPELL":
			result = _action_play_spell(game_state, player_id, action.payload, action.type == "SET_SPELL")
		"PLAY_TRAP", "SET_TRAP":
			result = _action_play_trap(game_state, player_id, action.payload, action.type == "SET_TRAP")
		"END_TURN":
			result = _action_end_turn(game_state, player_id)
		"SURRENDER":
			result = _action_surrender(game_state, player_id)
		"CHANGE_POSITION":
			result = _action_change_position(game_state, player_id, action.payload)
		"ACTIVATE_EFFECT":
			result = _action_activate_effect(game_state, player_id, action.payload)
		"DECLARE_ATTACK":
			result = _action_declare_attack(game_state, player_id, action.payload)
		"END_PHASE":
			result = _action_end_phase(game_state, player_id)
		_:
			result.errors.append("UNKNOWN_ACTION")
	
	if result.success:
		print("✅ Action: %s | Player: %s" % [action.type, player_id])
	else:
		var error_msg = result.errors[0] if result.errors.size() > 0 else "Unknown"
		print("❌ Action failed: %s | Error: %s" % [action.type, error_msg])
	
	return result


# ===========================================================================
# CÁC HÀM HÀNH ĐỘNG CHI TIẾT
# ===========================================================================
func _action_draw_card(game_state, player_id):
	var player = game_state.players[player_id]
	if player.deck.empty():
		return _error("DECK_EMPTY")
	
	var card = player.deck[0]
	player.deck.remove(0)
	player.hand.append(card)
	
	return {
		"success": true,
		"events": [
			{ "type": "DRAW_CARD", "card_id": card, "player": player_id }
		]
	}

func _action_play_monster(game_state, player_id, payload):
	var player = game_state.players[player_id]
	var card_id = payload.card_id
	var to_zone = payload.to_zone
	var position = payload.position || "face_up_attack"

	if not player.hand.has(card_id):
		return _error("CARD_NOT_IN_HAND")
	if to_zone < 0 or to_zone >= 5 or player.monster_zones[to_zone] != null:
		return _error("ZONE_OCCUPIED")
	if not game_state.phase  in ["main1", "main2"]:
		return _error("NOT_IN_MAIN_PHASE")

	player.hand.erase(card_id)
	player.monster_zones[to_zone] = {
		"card_id": card_id,
		"position": position,
		"status": "summoned_this_turn"
	}

	return {
		"success": true,
		"events": [
			{ "type": "SUMMON", "card_id": card_id, "player": player_id, "zone": to_zone }
		]
	}

func _action_set_monster(game_state, player_id, payload):
	var player = game_state.players[player_id]
	var card_id = payload.card_id
	var to_zone = payload.to_zone

	if not player.hand.has(card_id):
		return _error("CARD_NOT_IN_HAND")
	if to_zone < 0 or to_zone >= 5 or player.monster_zones[to_zone]:
		return _error("ZONE_OCCUPIED")

	player.hand.erase(card_id)
	player.monster_zones[to_zone] = {
		"card_id": card_id,
		"position": "face_down_defense",
		"status": "set_this_turn"
	}

	return {
		"success": true,
		"events": [
			{ "type": "SET_MONSTER", "card_id": card_id, "player": player_id, "zone": to_zone }
		]
	}

func _action_play_spell(game_state, player_id, payload, is_set):
	var player = game_state.players[player_id]
	var card_id = payload.card_id
	var to_zone = payload.to_zone

	if not player.hand.has(card_id):
		return _error("CARD_NOT_IN_HAND")
	if to_zone < 0 or to_zone >= 5 or player.spell_trap_zones[to_zone]:
		return _error("SPELL_ZONE_OCCUPIED")

	player.hand.erase(card_id)
	var status = "face_down" if is_set  else "face_up"
	player.spell_trap_zones[to_zone] = {
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
	var player = game_state.players[player_id]
	var card_id = payload.card_id
	var to_zone = payload.to_zone

	if not player.hand.has(card_id):
		return _error("CARD_NOT_IN_HAND")
	if to_zone < 0 or to_zone >= 5 or player.spell_trap_zones[to_zone]:
		return _error("TRAP_ZONE_OCCUPIED")

	player.hand.erase(card_id)
	var status = "face_down" if is_set  else "face_up"
	player.spell_trap_zones[to_zone] = {
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
	game_state.turn = _get_opponent_id(game_state, player_id)
	game_state.phase = "draw"
	game_state.current_turn_count += 1

	return {
		"success": true,
		"events": [
			{ "type": "TURN_CHANGED", "next_player": game_state.turn }
		]
	}

func _action_surrender(game_state, player_id):
	var opponent_id = _get_opponent_id(game_state, player_id)
	game_state.winner = opponent_id
	game_state.win_reason = WIN_REASON_SURRENDER
	game_state.status = "finished"

	return {
		"success": true,
		"events": [
			{ "type": "WIN", "winner": opponent_id, "reason": WIN_REASON_SURRENDER }
		]
	}

func _action_change_position(game_state, player_id, payload):
	var player = game_state.players[player_id]
	var card_id = payload.card_id
	var to_position = payload.to_position
	var face = payload.face

	var zone_idx = -1
	for i in range(5):
		var card = player.monster_zones[i]
		if card and card.card_id == card_id:
			zone_idx = i
			break
	if zone_idx == -1:
		return _error("CARD_NOT_ON_FIELD")

	var card_obj = player.monster_zones[zone_idx]
	if card_obj.status == "summoned_this_turn":
		return _error("CANNOT_CHANGE_POS_SUMMON_TURN")

	var new_pos = "%s_%s" % ["face_" + face, to_position]
	card_obj.position = new_pos

	return {
		"success": true,
		"events": [
			{ "type": "CHANGE_POSITION", "card_id": card_id, "to_position": new_pos }
		]
	}

func _action_activate_effect(game_state, player_id, payload):
	var card_id = payload.card_id
	var player = game_state.players[player_id]

	# Kiểm tra có trên field không
	var found = false
	for zone in player.monster_zones:
		if zone and zone.card_id == card_id:
			found = true
			break
	for zone in player.spell_trap_zones:
		if zone and zone.card_id == card_id and zone.status == "face_up":
			found = true
			break
	
	if not found:
		return _error("EFFECT_CANNOT_ACTIVATE")

	return {
		"success": true,
		"events": [
			{ "type": "ACTIVATE_EFFECT", "card_id": card_id, "player": player_id }
		]
	}

func _action_declare_attack(game_state, player_id, payload):
	var attacker_id = payload.attacker
	var target_id = payload.target
	var player = game_state.players[player_id]
	var opponent_id = _get_opponent_id(game_state, player_id)
	var opponent = game_state.players[opponent_id]

	if game_state.phase != "battle":
		return _error("NOT_IN_BATTLE_PHASE")

	# Tìm attacker
	var atk_zone = -1
	for i in range(5):
		var card = player.monster_zones[i]
		if card and card.card_id == attacker_id and card.position == "face_up_attack":
			atk_zone = i
			break
	if atk_zone == -1:
		return _error("INVALID_ATTACKER")

	if player.monster_zones[atk_zone].has("attacked_this_turn"):
		return _error("ALREADY_ATTACKED")

	var atk = _get_card_attack(attacker_id)
	var events = []

	if target_id == null:
		# Direct attack
		opponent.life_points = max(0, opponent.life_points - atk)
		events.append({
			"type": "DIRECT_ATTACK",
			"attacker": attacker_id,
			"damage": atk
		})
	else:
		# Attack monster
		var def = _get_card_defense(target_id)
		var target_zone = -1
		for i in range(5):
			var card = opponent.monster_zones[i]
			if card and card.card_id == target_id:
				target_zone = i
				break
		if target_zone == -1:
			return _error("TARGET_NOT_FOUND")

		if atk > def:
			opponent.life_points = max(0, opponent.life_points - (atk - def))
			events.append({
				"type": "ATTACK_MONSTER",
				"result": "destroy",
				"damage": atk - def
			})
			opponent.monster_zones[target_zone] = null
			opponent.graveyard.append(target_id)
		elif atk == def:
			events.append({ "type": "ATTACK_MONSTER", "result": "destroy_both" })
			player.monster_zones[atk_zone] = null
			opponent.monster_zones[target_zone] = null
			player.graveyard.append(attacker_id)
			opponent.graveyard.append(target_id)
		else:
			player.life_points = max(0, player.life_points - (def - atk))
			events.append({
				"type": "ATTACK_MONSTER",
				"result": "rebound",
				"damage": def - atk
			})
			player.monster_zones[atk_zone] = null
			player.graveyard.append(attacker_id)

	player.monster_zones[atk_zone].attacked_this_turn = true
	return { "success": true, "events": events }

func _action_end_phase(game_state, player_id):
	var idx = TURN_PHASES.find(game_state.phase)
	if idx == -1 or idx >= TURN_PHASES.size() - 1:
		return _error("INVALID_PHASE")
	game_state.phase = TURN_PHASES[idx + 1]
	return {
		"success": true,
		"events": [{ "type": "PHASE_CHANGED", "new_phase": game_state.phase }]
	}


# ===========================================================================
# HÀM HỖ TRỢ
# ===========================================================================
func _create_player_state(player_id, deck, hand):
	return {
		"player_id": player_id,
		"life_points": 8000,
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
	for i in range(array.size()):
		var j = randi() % array.size()
		#array.swap(i, j)
	return array

func _draw_cards(deck, count):
	var cards = []
	for i in range(min(count, deck.size())):
		if not deck.empty():
			cards.append(deck[0])
			deck.remove(0)
	return cards

func _can_activate_effect_out_of_turn(game_state, action):
	return action.type == "ACTIVATE_EFFECT"  # Simplified

func _get_opponent_id(game_state, player_id):
	for pid in game_state.players.keys():
		if pid != player_id:
			return pid
	return null

func _update_phase_if_needed(game_state):
	pass  # Có thể mở rộng sau

func _get_available_actions(game_state, player_id):
	var actions = ["END_TURN", "END_PHASE"]
	var player = game_state.players[player_id]
	
	if game_state.phase in ["main1", "main2"]:
		if player.hand.has("BLUE_EYES_WHITE_DRAGON"):
			actions.append("PLAY_MONSTER")
		actions.append("SET_MONSTER")
		# Thêm spell/trap nếu cần
	if game_state.phase == "battle":
		actions.append("DECLARE_ATTACK")
	
	return actions

func _check_win_condition(game_state):
	for pid in game_state.players.keys():
		var p = game_state.players[pid]
		if p.life_points <= 0:
			return { "winner": _get_opponent_id(game_state, pid), "reason": WIN_REASON_LP_ZERO }
		if p.deck.empty() and game_state.phase == "draw":
			return { "winner": _get_opponent_id(game_state, pid), "reason": WIN_REASON_DECK_OUT }
	return { "winner": null }

func _get_card_attack(card_id):
	return {
		"BLUE_EYES_WHITE_DRAGON": 3000,
		"GYOUKI": 1800
	}.get(card_id, 0)

func _get_card_defense(card_id):
	return {
		"SUIJIN": 2100
	}.get(card_id, 0)

func _error(reason):
	return {
		"success": false,
		"errors": [reason],
		"events": [],
		"available_actions": []
	}


# {
#   "player_id": "player_1",
#   "type": "PLAY_MONSTER",
#   "payload": {
#     "card_id": "BLUE_EYES_WHITE_DRAGON",
#     "from_zone": "hand",
#     "to_zone": 2,
#     "position": "face_up_attack"  // face_up_attack, face_down_defense
#   }
# }


# {
#   "success": true,
#   "game_state": { ... },  // Trạng thái sau khi xử lý
#   "events": [
#     {
#       "type": "CARD_PLAYED",
#       "card_id": "BLUE_EYES",
#       "player": "player_1"
#     },
#     {
#       "type": "TRIGGER_EFFECT",
#       "card_id": "MIRROR_FORCE",
#       "activation_timing": "after_attack_declared"
#     },
#     {
#       "type": "DAMAGE",
#       "amount": 1200,
#       "target": "player_2"
#     },
#     {
#       "type": "WIN",
#       "winner": "player_1",
#       "reason": "lp_zero"
#     }
#   ],
#   "available_actions": ["END_TURN", "PLAY_SPELL"],  // Dùng cho bot
#   "chain_state": {
#     "in_chain": true,
#     "chain_index": 2,
#     "pending_response": "player_1"
#   }
# }
