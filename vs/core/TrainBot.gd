# ===========================================================================
# train_agent.gd - Huấn luyện Agent học từ trận đấu Yu-Gi-Oh!
# Dùng Agent.gd (hybrid: Q-Learning + Rule-based response)
# ===========================================================================

extends Node

# Số trận để huấn luyện
const TRAINING_GAMES = 100

# Bộ bài mẫu
var deck = [
	"BLUE_EYES_WHITE_DRAGON",
	"DARK_MAGICIAN",
	"MIRROR_FORCE",
	"GYOUKI",
	"SACK",
	"EFFECT_VEILER",
	"BOOK_OF_MOON",
	"CARD_001",
	"CARD_002",
	"CARD_003"
]

# ===========================================================================
# _ready()
# Bắt đầu huấn luyện
# ===========================================================================
func _ready():
	print("🚀 Bắt đầu huấn luyện Agent cho %d trận..." % TRAINING_GAMES)
	
	for i in range(TRAINING_GAMES):
		print("🎮 Trận #%d" % (i + 1))
		_train_one_game(deck, deck)
	
	# Lưu model sau khi học xong
	Agent.save_q_table()
	print("🎉 Hoàn thành huấn luyện %d trận! Model đã được lưu." % TRAINING_GAMES)


# ===========================================================================
# _train_one_game(deck_a, deck_b)
# Chạy một trận đấu giữa Agent và Bot (random)
# ===========================================================================
func _train_one_game(deck_a, deck_b):
	# Khởi tạo trận đấu
	var room_id = BattleCore.start_duel("agent", "bot", deck_a, deck_b)
	if not room_id:
		print("❌ Không thể khởi tạo trận đấu")
		return
	
	var game_over = false
	var current_state = BattleCore.get_game_state(room_id, "agent")
	
	# Vòng lặp trận đấu
	while not game_over:
		var game_data = BattleCore.active_duels[room_id]
		if not game_data:
			break
		
		var current_player = game_data.turn
		
		if current_player == "agent":
			# Lượt của Agent
			var available_actions = BattleCore.get_available_actions(room_id, "agent")
			if available_actions.empty():
				game_over = true
				continue
			
			# 1. Agent chọn hành động chính
			var action_type = Agent.get_action(current_state, "agent", available_actions)
			var action = {
				"player_id": "agent",
				"type": action_type
			}
			
			# 2. Điền payload (có thể mở rộng sau)
			action["payload"] = _build_payload(action_type, current_state, "agent")
			
			# 3. Gửi hành động
			var result = BattleCore.submit_action(room_id, action)
			
			# 4. Học từ kết quả
			Agent.learn_from_result(current_state, action, result)
			
			# 5. Cập nhật trạng thái
			var new_state = BattleCore.get_game_state(room_id, "agent")
			current_state = new_state
			
			# 6. Xử lý sự kiện: có cần phản ứng không?
			var response = Agent.on_event(new_state, result["events"], "agent")
			if response:
				var response_result = BattleCore.submit_action(room_id, response)
				# Có thể học thêm từ phản ứng
				Agent.learn_from_result(new_state, response, response_result)
				current_state = BattleCore.get_game_state(room_id, "agent")
			
			# 7. Kiểm tra kết thúc
			if result["events"].find({"type": "WIN"}) or new_state["status"] == "finished":
				game_over = true
				
		else:
			# Lượt của bot đối thủ (random)
			var available = BattleCore.get_available_actions(room_id, "bot")
			if available.empty():
				game_over = true
				continue
			
			var action_type = available[randi() % available.size()]
			var action = {
				"player_id": "bot",
				"type": action_type
			}
			
			# Tạo payload đơn giản
			action["payload"] = _build_payload(action_type, BattleCore.get_game_state(room_id, "bot"), "bot")
			
			BattleCore.submit_action(room_id, action)
		
		# Kiểm tra trạng thái trận
		var duel = BattleCore.active_duels.get(room_id)
		if not duel or duel.status == "finished":
			game_over = true
	
	print("✅ Trận đấu kết thúc.")


# ===========================================================================
# _build_payload(action_type, game_state, player_id)
# Tạo payload hợp lệ cho hành động
# (Có thể mở rộng thành logic chọn bài thông minh)
# ===========================================================================
func _build_payload(action_type, game_state, player_id):
	var payload = {}
	var player = game_state["players"][player_id]
	
	match action_type:
		"PLAY_MONSTER":
			# Chọn quái đầu tiên trên tay
			for card_id in player["hand"]:
				if CardDatabase.exists(card_id):
					var card = CardDatabase.get(card_id)
					if card["type"] == "Monster":
						payload["card_id"] = card_id
						payload["from_zone"] = "hand"
						payload["to_zone"] = _find_empty_zone(player["monster_zones"])
						payload["position"] = "face_up_attack"
						return payload
			return null  # Không có quái
			
		"SET_MONSTER", "SET_SPELL", "SET_TRAP":
			payload["to_zone"] = _find_empty_zone(
				player["spell_trap_zones"] if "SPELL" in action_type or "TRAP" in action_type 
				else player["monster_zones"]
			)
			# Tìm bài phù hợp
			for card_id in player["hand"]:
				if CardDatabase.exists(card_id):
					var card = CardDatabase.get(card_id)
					if ("SPELL" in action_type and card["type"] == "Spell") or \
					   ("TRAP" in action_type and card["type"] == "Trap") or \
					   ("MONSTER" in action_type and card["type"] == "Monster"):
						payload["card_id"] = card_id
						return payload
			return null
			
		"PLAY_SPELL", "PLAY_TRAP":
			payload["to_zone"] = _find_empty_zone(player["spell_trap_zones"])
			# Tương tự như trên
			for card_id in player["hand"]:
				if CardDatabase.exists(card_id):
					var card = CardDatabase.get(card_id)
					if ("SPELL" in action_type and card["type"] == "Spell") or \
					   ("TRAP" in action_type and card["type"] == "Trap"):
						payload["card_id"] = card_id
						return payload
			return null
			
		"DECLARE_ATTACK":
			# Tìm quái tấn công
			for i in range(5):
				var card = player["monster_zones"][i]
				if card and card["position"] == "face_up_attack" and not card.has("attacked_this_turn"):
					var opp = game_state["players"][_get_opponent_id(game_state, player_id)]
					# Tìm mục tiêu
					for j in range(5):
						if opp.monster_zones[j]:
							payload["attacker"] = card["card_id"]
							payload["target"] = opp.monster_zones[j].card_id
							return payload
					# Nếu không có quái → tấn công trực tiếp
					payload["attacker"] = card["card_id"]
					payload["target"] = null
					return payload
			return null
			
		"CHANGE_POSITION":
			for i in range(5):
				var card = player["monster_zones"][i]
				if card and card["position"] == "face_up_attack":
					payload["card_id"] = card["card_id"]
					payload["to_position"] = "defense"
					payload["face"] = "up"
					return payload
			return null
			
		"ACTIVATE_EFFECT":
			# Tìm bài có thể kích hoạt
			for zone in player["monster_zones"]:
				if zone:
					payload["card_id"] = zone["card_id"]
					return payload
			for zone in player["spell_trap_zones"]:
				if zone and zone["status"] == "face_up":
					payload["card_id"] = zone["card_id"]
					return payload
			return null
			
		"END_TURN", "END_PHASE", "DRAW_CARD", "SURRENDER":
			# Không cần payload
			pass
	
	return payload


# ===========================================================================
# Hàm hỗ trợ
# ===========================================================================
func _find_empty_zone(zones):
	for i in range(zones.size()):
		if zones[i] == null:
			return i
	return 0  # Mặc định

func _get_opponent_id(game_state, player_id):
	for pid in game_state["players"].keys():
		if pid != player_id:
			return pid
	return null

================================================================================

