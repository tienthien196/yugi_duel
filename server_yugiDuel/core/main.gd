# ===========================================================================
# Main.gd - Scene chính để test hệ thống Yu-Gi-Oh! (Godot 3.6)
# Khởi tạo trận đấu, để YugiBot chơi tự động và giả lập người chơi
# Không dùng UI, chỉ in kết quả qua console
# ===========================================================================

extends Node

var room_id = ""
var human_player = "player_a"
var bot_player = "player_b"

# ===========================================================================
# _ready()
# Khởi tạo trận đấu khi scene chạy
# ===========================================================================
func _ready():
	# Đảm bảo CardDatabase đã nạp
	if CardDatabase.get_all().empty():
		print("❌ Lỗi: CardDatabase chưa nạp dữ liệu!")
		return
	
	# Tạo deck mẫu
	var deck_a = [
		"BLUE_EYES_WHITE_DRAGON", "BLUE_EYES_WHITE_DRAGON",
		"POT_OF_GREED", "MONSTER_REBORN", "DARK_HOLE",
		"SUMMONED_SKULL", "GYOUKI"
	]
	var deck_b = [
		"DARK_MAGICIAN", "DARK_MAGICIAN",
		"MIRROR_FORCE", "TRAP_HOLE", "SUIJIN",
		"GYOUKI", "SUMMONED_SKULL"
	]
	
	# Khởi tạo trận đấu
	room_id = BattleCore.start_duel(human_player, bot_player, deck_a, deck_b, {
		"start_lp": 8000,
		"max_hand_size": 6,
		"forbidden_cards": []
	})
	print("this is room", room_id)
	if room_id == "":
		print("❌ Lỗi: Không thể tạo trận đấu!")
		return
	
	print("🎮 Trận đấu bắt đầu: %s" % room_id)
	_play_next_turn()


# ===========================================================================
# _play_next_turn()
# Xử lý lượt tiếp theo, gọi bot hoặc giả lập người chơi
# ===========================================================================
# ===========================================================================
# _play_next_turn()
# ✅ ĐÃ SỬA: Thêm vòng lặp cho bot để thực hiện nhiều hành động trong 1 lượt
# ===========================================================================
func _play_next_turn():
	var state = BattleCore.get_game_state(room_id, human_player)
	if state.empty() or state["status"] != "active":
		print("🏁 Kết thúc trận.")
		return

	_print_game_state(state)

	if state["turn"] == bot_player:
		# 🔁 VÒNG LẶP: Cho phép bot thực hiện nhiều hành động
		while true:
			# Lấy trạng thái mới nhất
			var current_state = BattleCore.get_game_state(room_id, bot_player)
			if current_state.empty() or current_state["status"] != "active" or current_state["turn"] != bot_player:
				break

			var bot_result = YugiBot.play_turn(room_id, bot_player)
			if bot_result.success:
				print("🤖 Bot action: %s" % bot_result.action_taken)
				print("📈 Kết quả: %s", bot_result.result["events"])
			else:
				print("❌ Bot thất bại: %s" % bot_result.result["errors"])
				break

			# ✅ THÊM DÒNG NÀY: Dừng 0.1s để tránh treo
			yield(get_tree().create_timer(0.1), "timeout")
	else:
		# 👤 Người chơi (giả lập)
		var actions = BattleCore.get_available_actions(room_id, human_player)
		var action = _simulate_human_action(state, human_player, actions)
		var result = BattleCore.submit_action(room_id, action)
		if result["success"]:
			print("👤 Human action: %s" % action)
			print("📈 Kết quả: %s" , result["events"])
		else:
			print("❌ Human thất bại: %s" % result["errors"])

	# Chờ 1 giây rồi tiếp tục
	yield(get_tree().create_timer(1.0), "timeout")
	_play_next_turn()

# ===========================================================================
# _simulate_human_action(state, player_id, actions)
# Giả lập hành động cho người chơi (dựa trên heuristic đơn giản)
# ===========================================================================
func _simulate_human_action(state, player_id, actions):
	# Ưu tiên: Activate spell mạnh
	for act in actions.details:
		if act.type == "PLAY_SPELL":
			var effect = CardDatabase.get(act.payload["card_id"]).get("effect", "")
			if effect in ["draw_2", "special_summon_graveyard", "destroy_all_monsters"]:
				return _with_player(act, player_id)  # ✅ Đã có player_id
	# Ưu tiên 2: Summon quái có ATK cao nhất
	var best_atk = -1
	var best_action = null
	for act in actions.details:
		if act.type == "PLAY_MONSTER":
			var atk = CardDatabase.get(act.payload["card_id"]).get("atk", 0)
			if atk > best_atk:
				best_atk = atk
				best_action = act
	if best_action:
		return _with_player(best_action, player_id)  # ✅
	# Ưu tiên 3: Attack quái yếu nhất
	if state["phase"] == "battle":
		var opponent_id = _get_opponent_id(state)
		var opponent = state["players"][opponent_id]
		var weakest_atk = 999999
		var weakest_zone = -1
		for i in range(5):
			if opponent["monster_zones"][i]:
				var atk = CardDatabase.get(opponent["monster_zones"][i].card_id).get("atk", 0)
				if atk < weakest_atk:
					weakest_atk = atk
					weakest_zone = i
		if weakest_zone != -1:
			for act in actions.details:
				if act.type == "DECLARE_ATTACK" and act.payload["target_zone"] == weakest_zone:
					return _with_player(act, player_id)  # ✅
		# Direct attack
		for act in actions.details:
			if act.type == "DECLARE_ATTACK" and not act.payload.has("target_zone"):
				return _with_player(act, player_id)  # ✅
	# Ưu tiên 4: Set trap/spell
	for act in actions.details:
		if act.type in ["SET_TRAP", "SET_SPELL"]:
			return _with_player(act, player_id)  # ✅
	# Ưu tiên 5: Set monster
	for act in actions.details:
		if act.type == "SET_MONSTER":
			return _with_player(act, player_id)  # ✅
	# Ưu tiên 6: END_PHASE hoặc END_TURN
	if state["phase"] == "end":
		for act in actions.details:
			if act.type == "END_TURN":
				return _with_player(act, player_id)  # ✅
		return _with_player({"type": "END_TURN", "payload": {}}, player_id)  # ✅
	for act in actions.details:
		if act.type == "END_PHASE":
			return _with_player(act, player_id)  # ✅
		if act.type == "END_TURN":
			return _with_player(act, player_id)  # ✅
	# Fallback
	return _with_player({"type": "END_TURN", "payload": {}}, player_id)  # ✅

func _with_player(action, player_id):
	var new_action = action.duplicate()
	new_action["player_id"] = player_id
	return new_action

# ===========================================================================
# _print_game_state(state)
# In trạng thái trận đấu để debug
# ===========================================================================
func _print_game_state(state):
	var player = state["players"][human_player]
	var opponent_id = _get_opponent_id(state)
	var opponent = state["players"][opponent_id]
	
	print("=== Trạng thái trận đấu ===")
	print("Lượt: %s | Phase: %s | Turn count: %d" % [state["turn"], state["phase"], state["current_turn_count"]])
	print("Người chơi %s: LP=%d, Hand=%d, Deck=%d" % [human_player, player["life_points"], len(player["hand"]), len(player["deck"])])
	for i in range(5):
		if player["monster_zones"][i]:
			var card = CardDatabase.get(player["monster_zones"][i].card_id)
			print("  Monster zone %d: %s (%s, ATK=%d, DEF=%d)" % [i, card["name"], player["monster_zones"][i].position, card["atk"], card["def"]])
		if player["spell_trap_zones"][i]:
			var card = CardDatabase.get(player["spell_trap_zones"][i].card_id)
			print("  Spell/Trap zone %d: %s (%s)" % [i, card["name"], player["spell_trap_zones"][i].status])
	print("Đối thủ %s: LP=%d, Hand=%d, Deck=%d" % [opponent_id, opponent["life_points"], len(opponent["hand"]), len(opponent["deck"])])
	for i in range(5):
		if opponent["monster_zones"][i]:
			var card = CardDatabase.get(opponent["monster_zones"][i].card_id)
			print("  Opponent Monster zone %d: %s (%s, ATK=%d, DEF=%d)" % [i, card["name"], opponent["monster_zones"][i].position, card["atk"], card["def"]])
		if opponent["spell_trap_zones"][i]:
			var card = CardDatabase.get(opponent["spell_trap_zones"][i].card_id)
			print("  Opponent Spell/Trap zone %d: %s (%s)" % [i, card["name"], opponent["spell_trap_zones"][i].status])
	if not state["chain"].empty():
		print("Chain: %s" % state["chain"])
	if state["winner"]:
		print("Người thắng: %s | Lý do: %s" % [state["winner"], state["win_reason"]])
	print("==========================")


# ===========================================================================
# _get_opponent_id(state)
# Lấy ID của đối thủ
# ===========================================================================
func _get_opponent_id(state):
	for pid in state["players"]:
		if pid != state["turn"]:
			return pid
	return null



