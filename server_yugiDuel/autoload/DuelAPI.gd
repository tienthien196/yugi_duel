# ===========================================================================
# DuelAPI.gd
# Autoload Singleton - Lớp trung gian giữa GUI và BattleCore
#
# Chức năng:
# - Giao tiếp an toàn với BattleCore
# - Validate input từ GUI
# - Log hành trình bằng LoggerService
# - Trả về kết quả đơn giản, dễ xử lý cho GUI
# - Không để GUI gọi trực tiếp core
# ===========================================================================


extends Node

# Tham chiếu đến các service
onready var battle_core = BattleCore
onready var logger = LoggerService

# ===========================================================================
# Khởi tạo trận đấu mới
# Input: player_a_id, player_b_id, deck_a, deck_b, rules (dict)
# Output: { success: bool, room_id: string, error: string }
# ===========================================================================
func start_duel(player_a_id, player_b_id, deck_a, deck_b, rules = {}):
	logger.enter("DuelAPI", "start_duel", "GUI", {
		"players": [player_a_id, player_b_id],
		"deck_sizes": [deck_a.size(), deck_b.size()],
		"rules": rules
	})

	# Validate input
	if not _is_valid_player_id(player_a_id) or not _is_valid_player_id(player_b_id):
		var error_msg = "INVALID_PLAYER_ID: %s, %s" % [player_a_id, player_b_id]
		logger.warn(error_msg, "DuelAPI.start_duel")
		logger.exit("DuelAPI", "start_duel", "GUI", "fail", null, { "error": error_msg })
		return { "success": false, "error": "INVALID_PLAYER_ID" }

	if not _is_valid_deck(deck_a) or not _is_valid_deck(deck_b):
		var error_msg = "INVALID_DECK: sizes (%d, %d)" % [deck_a.size(), deck_b.size()]
		logger.warn(error_msg, "DuelAPI.start_duel")
		logger.exit("DuelAPI", "start_duel", "GUI", "fail", null, { "error": error_msg })
		return { "success": false, "error": "INVALID_DECK" }

	# Gọi BattleCore
	var start_time = OS.get_ticks_msec()
	var result = battle_core.start_duel(player_a_id, player_b_id, deck_a, deck_b, rules)
	var duration = OS.get_ticks_msec() - start_time

	if result is String:
		logger.success("Duel started", { "room_id": result })
		logger.exit("DuelAPI", "start_duel", "GUI", "success", duration, { "room_id": result })
		return {
			"success": true,
			"room_id": result
		}
	else:
		var error_code = result.get("errors", ["UNKNOWN_ERROR"])[0]
		logger.error("start_duel failed", error_code, result)
		logger.exit("DuelAPI", "start_duel", "GUI", "fail", duration, result)
		return {
			"success": false,
			"error": error_code
		}


# ===========================================================================
# Gửi hành động từ người chơi
# Input: room_id, action_dict
# Output: { success, events, available_actions, game_state }
# ===========================================================================
func submit_action(room_id, action_dict):
	logger.enter("DuelAPI", "submit_action", "GUI", {
		"room_id": room_id,
		"action": action_dict.get("type"),
		"player_id": action_dict.get("player_id")
	})

	var start_time = OS.get_ticks_msec()

	# Validate
	if not _is_valid_room_id(room_id):
		var res = { "success": false, "error": "ROOM_NOT_FOUND" }
		logger.warn("Invalid room_id", "DuelAPI.submit_action", { "room_id": room_id })
		logger.exit("DuelAPI", "submit_action", "GUI", "fail", null, res)
		return res

	if not action_dict.has("player_id") or not action_dict.has("type"):
		var res = { "success": false, "error": "INVALID_ACTION_FORMAT" }
		logger.warn("Missing player_id or type", "DuelAPI.submit_action", { "action": action_dict })
		logger.exit("DuelAPI", "submit_action", "GUI", "fail", null, res)
		return res

	# Gọi core
	var result = battle_core.submit_action(room_id, action_dict)
	var duration = OS.get_ticks_msec() - start_time

	if result["success"]:
		logger.flow_step("ACTION", "Executed: %s" % action_dict["type"], { "events": result["events"] })
		logger.exit("DuelAPI", "submit_action", "GUI", "success", duration, {
			"events": result["events"],
			"action": action_dict["type"]
		})
	else:
		logger.warn("Action failed", "DuelAPI.submit_action", result)
		logger.exit("DuelAPI", "submit_action", "GUI", "fail", duration, result)

	# Trả về kết quả + game_state (ẩn tay đối thủ)
	var game_state = battle_core.get_game_state(room_id, action_dict["player_id"])
	result["game_state"] = game_state
	return result


# ===========================================================================
# Lấy trạng thái trận đấu (cho GUI)
# Input: room_id, player_id
# Output: game_state (ẩn tay đối thủ) hoặc {}
# ===========================================================================
func get_game_state(room_id, player_id):
	if not _is_valid_room_id(room_id) or not _is_valid_player_id(player_id):
		return {}

	logger.enter("DuelAPI", "get_game_state", "GUI", { "room_id": room_id, "player_id": player_id })

	var start_time = OS.get_ticks_msec()
	var state = battle_core.get_game_state(room_id, player_id)
	var duration = OS.get_ticks_msec() - start_time

	if state:
		logger.flow_step("STATE", "Fetched game state", { "phase": state["phase"], "turn": state["turn"] })
		logger.exit("DuelAPI", "get_game_state", "GUI", "success", duration)
	else:
		logger.warn("No state found", "DuelAPI.get_game_state", { "room_id": room_id })

	return state


# ===========================================================================
# Lấy danh sách hành động khả dụng (cho AI hoặc hint)
# Input: room_id, player_id
# Output: { types: [...], details: [...] }
# ===========================================================================
func get_available_actions(room_id, player_id):
	logger.enter("DuelAPI", "get_available_actions", "GUI", { "room_id": room_id, "player_id": player_id })

	if not _is_valid_room_id(room_id) or not _is_valid_player_id(player_id):
		logger.exit("DuelAPI", "get_available_actions", "GUI", "fail")
		return { "types": [], "details": [] }

	var actions = battle_core.get_available_actions(room_id, player_id)
	logger.exit("DuelAPI", "get_available_actions", "GUI", "success", null, { "count": actions.types.size() })
	return actions


# ===========================================================================
# Kết thúc trận đấu (chỉ dùng cho debug/test)
# ===========================================================================
func end_duel(room_id, winner, reason = "forfeit"):
	logger.enter("DuelAPI", "end_duel", "GUI", { "room_id": room_id, "winner": winner, "reason": reason })
	battle_core.end_duel(room_id, winner, reason)
	logger.success("Duel manually ended", { "room_id": room_id, "winner": winner, "reason": reason })
	logger.exit("DuelAPI", "end_duel", "GUI", "success")


# ===========================================================================
# HÀM HỖ TRỢ - VALIDATION
# ===========================================================================
func _is_valid_player_id(id):
	return typeof(id) == TYPE_STRING && id != ""

func _is_valid_deck(deck):
	return typeof(deck) == TYPE_ARRAY && deck.size() >= 40 && deck.size() <= 60

func _is_valid_room_id(room_id):
	return typeof(room_id) == TYPE_STRING && battle_core.active_duels.has(room_id)


# ===========================================================================
# Làm sạch trace khi cần (gọi từ GUI khi kết thúc trận)
# ===========================================================================
func clear_trace():
	logger.clear_trace()
