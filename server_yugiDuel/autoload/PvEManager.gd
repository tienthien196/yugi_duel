# res://autoload/PvEManager.gd
extends Node

# Tham chiếu
onready var battle_core = BattleCore
onready var network_manager = NetworkManager
onready var card_db = CardDatabase

# ID bot ảo
const BOT_ID = "bot_ai_1"
const BOT_DECK = ["BLUE_EYES_WHITE_DRAGON", "BLUE_EYES_WHITE_DRAGON", "BLUE_EYES_WHITE_DRAGON", "SUIJIN", "POT_OF_GREED", "MIRROR_FORCE", "DARK_HOLE", "TRAP_HOLE", "MONSTER_REBORN", "KURIBOH"] # Ví dụ

func start_pve_game(player_id, deck_player):
	# Tạo deck cho bot (có thể random sau)
	var deck_bot = BOT_DECK.duplicate()
	
	# Dùng BattleCore có sẵn để tạo trận
	var room_id = battle_core.start_duel(player_id, BOT_ID, deck_player, deck_bot, {})
	
	if not room_id:
		return false

	# Gửi thông báo cho client
	network_manager.send_message_to_player(player_id, {
		"type": "GAME_STARTED",
		"room_id": room_id,
		"side": "player", # hoặc random
		"mode": "pve"
	})

	# Bắt đầu vòng lặp bot
	_schedule_bot_turn(room_id)

	return true

# Hàm lập lịch lượt bot
func _schedule_bot_turn(room_id):
	# Dùng timer để chạy sau khi frame hiện tại xong
	get_tree().call_deferred("_run_bot_turn", room_id)

func _run_bot_turn(room_id):
	if not battle_core.active_duels.has(room_id):
		return
	
	var game_state = battle_core.get_game_state(room_id)
	if not game_state:
		return

	# Kiểm tra xem có phải lượt bot không
	if game_state.turn == BOT_ID and game_state.status == "active":
		# Lấy các hành động khả dụng
		var available_actions = battle_core.get_available_actions(room_id, BOT_ID)
		
		# Bot chọn hành động (dùng YugiBot hiện có)
		var action = YugiBot.choose_action(game_state, BOT_ID, available_actions)
		
		if action:
			# Gửi hành động vào core
			var result = battle_core.submit_action(room_id, action)
			
			# Gửi kết quả về cho người chơi (để update UI)
			for player in [game_state.players.keys()[0]]: # chỉ player thật
				if player != BOT_ID:
					network_manager.send_message_to_player(player, {
						"type": "ACTION_RESULT",
						"result": result
					})
	
	# Luôn schedule lại để kiểm tra tiếp
	get_tree().create_timer(1.5).connect("timeout", self, "_schedule_bot_turn", [room_id])
