# ===========================================================================
# GameManager.gd - Quản lý vòng đời trận đấu
# Không xử lý mạng, chỉ dùng BattleCore và DatabaseManager
# ===========================================================================
extends Node

# Danh sách trận đấu: room_id → { player_a, player_b, status, ... }
var active_games = {}

# Tham chiếu
onready var database_manager = DatabaseManager
onready var battle_core = BattleCore

# Signal
signal game_started(room_id, player_a, player_b)
signal game_finished(room_id, winner, reason)
signal game_event(room_id, events)  # ✅ Thêm signal để thông báo event từ bot

# ===========================================================================
# create_duel(player_a_id, player_b_id)
# Tạo trận đấu mới (PvP 1v1)
# ===========================================================================
func create_duel(player_a_id, player_b_id):
	var deck_a = database_manager.get_deck(player_a_id)
	var deck_b = database_manager.get_deck(player_b_id)
	var rules = { "start_lp": 8000, "max_hand_size": 6 }

	var room_id = battle_core.start_duel(player_a_id, player_b_id, deck_a, deck_b, rules)
	if typeof(room_id) != TYPE_STRING:
		return { "success": false, "error": "FAILED_TO_CREATE_DUEL" }

	active_games[room_id] = {
		"player_a": player_a_id,
		"player_b": player_b_id,
		"room_id": room_id,
		"status": "started",
		"start_time": OS.get_unix_time(),
		"mode": "pvp_1v1"
	}

	emit_signal("game_started", room_id, player_a_id, player_b_id)
	print("🎮 GameManager: Trận PvP '%s' đã tạo giữa %s và %s" % [room_id, player_a_id, player_b_id])
	return { "success": true, "room_id": room_id }

# ===========================================================================
# submit_action(room_id, action)
# Gửi hành động đến BattleCore
# ===========================================================================
func submit_action(room_id, action):
	if not active_games.has(room_id):
		return { "success": false, "error": "GAME_NOT_FOUND" }
	return battle_core.submit_action(room_id, action)

# ===========================================================================
# get_game_state(room_id, player_id)
# Lấy trạng thái trận (ẩn bài đối thủ)
# ===========================================================================
func get_game_state(room_id, player_id):
	return battle_core.get_game_state(room_id, player_id)

# ===========================================================================
# end_game(room_id, winner, reason)
# Kết thúc trận, cập nhật stats
# ===========================================================================
func end_game(room_id, winner, reason):
	if not active_games.has(room_id):
		return

	var game = active_games[room_id]
	var player_a = game["player_a"]
	var player_b = game["player_b"]

	# Cập nhật stats
	if winner == player_a:
		database_manager.update_stats(player_a, 1)
		database_manager.update_stats(player_b, 1)
		database_manager.add_match_history(player_a, player_b, "win", room_id)
		database_manager.add_match_history(player_b, player_a, "loss", room_id)
	elif winner == player_b:
		database_manager.update_stats(player_b, 1)
		database_manager.update_stats(player_a, 1)
		database_manager.add_match_history(player_b, player_a, "win", room_id)
		database_manager.add_match_history(player_a, player_b, "loss", room_id)

	# Dọn dẹp
	active_games.erase(room_id)
	emit_signal("game_finished", room_id, winner, reason)
	print("🏁 GameManager: Trận '%s' kết thúc. Người thắng: %s" % [room_id, winner])

# ===========================================================================
# create_duel_vs_bot(player_id)
# Tạo trận đấu giữa người chơi và bot (AI)
# ===========================================================================
func create_duel_vs_bot(player_id):
	var bot_id = "bot_ai"
	var player_deck = database_manager.get_deck(player_id)
	var bot_deck = _get_bot_deck()

	var rules = { "start_lp": 8000, "max_hand_size": 6 }
	var room_id = battle_core.start_duel(player_id, bot_id, player_deck, bot_deck, rules)

	if typeof(room_id) != TYPE_STRING:
		return { "success": false, "error": "FAILED_TO_CREATE_DUEL" }

	# Lưu vào danh sách trận
	active_games[room_id] = {
		"player_a": player_id,
		"player_b": bot_id,
		"room_id": room_id,
		"status": "started",
		"start_time": OS.get_unix_time(),
		"mode": "pve"
	}

	# Thông báo trận bắt đầu
	emit_signal("game_started", room_id, player_id, bot_id)
	print("🎮 GameManager: Trận PvE '%s' đã tạo giữa %s và %s" % [room_id, player_id, bot_id])

	# Bắt đầu vòng lặp bot
	_schedule_bot_turn(room_id)

	return { "success": true, "room_id": room_id }

# ===========================================================================
# _get_bot_deck() → Array
# Trả về bộ bài mẫu cho bot
# ===========================================================================
func _get_bot_deck() -> Array:
	return [
		"BLUE_EYES_WHITE_DRAGON", "BLUE_EYES_WHITE_DRAGON", "SUMMONED_SKULL",
		"DARK_MAGICIAN", "GYOUKI", "SUIJIN", "KURIBOH", "MAN_EATER_BUTTERFLY",
		"DARK_HOLE", "MIRROR_FORCE", "TRAP_HOLE", "POT_OF_GREED", "CARD_OF_DESTRUCTION",
		"MONSTER_REBORN", "FACE_UP", "SACRIFICE", "OFFERING", "DRAGON", "WARRIOR", "SPELL"
	]

# ===========================================================================
# _schedule_bot_turn(room_id)
# Lập lịch để bot chơi lượt (dùng deferred để tránh lỗi tree)
# ===========================================================================
func _schedule_bot_turn(room_id):
	get_tree().create_timer(1.5).connect("timeout", self, "_run_bot_turn", [room_id])

# ===========================================================================
# _run_bot_turn(room_id)
# Xử lý lượt của bot
# ===========================================================================
func _run_bot_turn(room_id):
	# Kiểm tra trận còn tồn tại
	if not active_games.has(room_id):
		return

	var game = active_games[room_id]
	var bot_id = game["player_b"]
	if bot_id != "bot_ai":
		return

	var state = battle_core.get_game_state(room_id)
	if not state or state.status != "active":
		return

	# Nếu đến lượt bot
	if state.turn == bot_id:
		var available_actions = battle_core.get_available_actions(room_id, bot_id)
		if available_actions.empty():
			return

		# Bot chọn hành động
		var action = YugiBot.choose_action(state, bot_id, available_actions)
		if action:
			action.player_id = bot_id
			var result = battle_core.submit_action(room_id, action)

			# Học từ kết quả nếu bật learning
			if Agent.learning_mode:
				Agent.learn_from_result(state, action, result)

			# Phát tín hiệu để ServerManager gửi về client
			emit_signal("game_event", room_id, result.events)

	# Nếu chưa phải lượt bot, tiếp tục schedule (để kiểm tra sau)
	if state.turn != bot_id and state.status == "active":
		_schedule_bot_turn(room_id)
