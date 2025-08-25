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

# ===========================================================================
# create_duel(player_a_id, player_b_id)
# Tạo trận đấu mới, gọi BattleCore
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
		"start_time": OS.get_unix_time()
	}

	emit_signal("game_started", room_id, player_a_id, player_b_id)
	print("🎮 GameManager: Trận '%s' đã tạo giữa %s và %s" % [room_id, player_a_id, player_b_id])
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

	active_games.erase(room_id)
	emit_signal("game_finished", room_id, winner, reason)
	print("🏁 GameManager: Trận '%s' kết thúc. Người thắng: %s" % [room_id, winner])
