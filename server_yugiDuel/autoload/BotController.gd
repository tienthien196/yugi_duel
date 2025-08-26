# ===========================================================================
# BotController.gd
# Autoload Singleton - Điều khiển các bot trong trận đấu
# Lắng nghe tín hiệu `my_turn` từ DuelScene → ra quyết định tự động
# ===========================================================================

extends Node

# Danh sách bot được điều khiển
var controlled_bots = []

# Tham chiếu LoggerService
onready var Logger = LoggerService

# ===========================================================================
# register_bot(player_id)
# Đăng ký một bot để controller điều khiển
# ===========================================================================
func register_bot(player_id: String):
	if not controlled_bots.has(player_id):
		controlled_bots.append(player_id)
		Logger.info("BotController: Đã đăng ký bot '%s'" % player_id, "BotController")

# ===========================================================================
# _on_my_turn(room_id, player_id, game_state)
# Được gọi từ DuelScene khi đến lượt một người chơi
# Nếu là bot → ra quyết định
# ===========================================================================
func _on_my_turn(room_id: String, player_id: String, game_state):
	if not controlled_bots.has(player_id):
		return

	Logger.enter("BotController", "on_my_turn", "DuelScene", {
		"player_id": player_id,
		"phase": game_state["phase"],
		"turn_count": game_state["current_turn_count"]
	})

	# Chờ 1s để xem mượt
	var timer = get_tree().create_timer(1.0)
	yield(timer, "timeout")

	var actions = DuelAPI.get_available_actions(room_id, player_id)
	var action = _choose_action(actions, game_state, player_id)

	if action:
		var result = DuelAPI.submit_action(room_id, {
			"player_id": player_id,
			"type": action.type,
			"payload": action.payload if action.has("payload") else {}
		})

		if result.success:
			Logger.flow_step("BOT", "Đã thực hiện hành động", { "action": action.type })
		else:
			Logger.warn("Hành động thất bại", "BotController", {
				"action": action.type,
				"error": result.errors[0]
			})
			# Dù lỗi, vẫn end turn
			_end_turn(room_id, player_id)
	else:
		# Không chọn được hành động → end turn
		_end_turn(room_id, player_id)

	Logger.exit("BotController", "on_my_turn", "DuelAPI", "success")

# ===========================================================================
# _end_turn(room_id, player_id)
# Gửi hành động END_TURN
# ===========================================================================
func _end_turn(room_id, player_id):
	Logger.flow_step("BOT", "Không có hành động → kết thúc lượt", { "player_id": player_id })
	DuelAPI.submit_action(room_id, {
		"player_id": player_id,
		"type": "END_TURN"
	})

# ===========================================================================
# _choose_action(available_actions, game_state, player_id)
# Lôgic chọn hành động đơn giản (có thể nâng cấp sau)
# ===========================================================================
func _choose_action(available, game_state, player_id):
	var details = available.details

	# 1. Ưu tiên: tấn công nếu có thể
	var attack = _find_action(details, "DECLARE_ATTACK")
	if attack:
		Logger.flow_step("AI", "Chọn tấn công", { "attacker_zone": attack.payload.atk_zone })
		return attack

	# 2. Triệu hồi quái vật (mặt ngửa tấn công)
	var summon = _find_action(details, "PLAY_MONSTER")
	if summon:
		var card_id = summon.payload.card_id
		var card = CardDatabase.get(card_id)
		Logger.flow_step("AI", "Chọn triệu hồi", { "card": card.name, "atk": card.atk })
		return summon

	# 3. Đặt quái/phép/bẫy
	var set_monster = _find_action(details, "SET_MONSTER")
	if set_monster: return set_monster
	var set_spell = _find_action(details, "SET_SPELL")
	if set_spell: return set_spell
	var set_trap = _find_action(details, "SET_TRAP")
	if set_trap: return set_trap

	# 4. Kích hoạt hiệu ứng (ưu tiên spell/trap)
	var activate = _find_action(details, "ACTIVATE_EFFECT")
	if activate:
		var card_id = activate.payload.card_id
		var card = CardDatabase.get(card_id)
		Logger.flow_step("AI", "Kích hoạt hiệu ứng", { "card": card.name, "effect": card.effect })
		return activate

	# 5. Đổi vị trí (nếu cần)
	var change_pos = _find_action(details, "CHANGE_POSITION")
	if change_pos:
		return change_pos

	# 6. Không làm gì
	return null

# ===========================================================================
# _find_action(details, type_name)
# Tìm hành động đầu tiên theo type
# ===========================================================================
func _find_action(details, type_name):
	for action in details:
		if action.type == type_name:
			return action
	return null
