# ===================================================================
# BotTestClient.gd - Client test tự động (Godot 3.6)
# ✅ ĐÃ SỬA HOÀN THIỆN:
#   - Luôn END_TURN nếu không có hành động
#   - Log chi tiết: phase, hand, available actions
#   - Truy cập dict an toàn: .get() thay []
#   - Phản ứng trap đúng, không spam
#   - Xử lý người đi trước/đi sau chính xác
# ===================================================================
extends Node

const SERVER_IP = "127.0.0.1"
const SERVER_PORT = 8080
const TIMEOUT_SECONDS = 150

# Tạo username unique
var TEST_USERNAME = "bot_%d_%d" % [OS.get_system_time_msecs(), randi()]

var room_id = ""
var player_id = ""
var has_sent_login = false
var is_waiting_for_action = false

export(bool) var is_host = false
export(String) var bot_name = ""  # Tên hiển thị để dễ debug

var connect_timeout = null

onready var network_client = NetworkManager
onready var authentication = Authentication
onready var game_controller = GameClientController


func _ready():
	randomize()
	var display_name = bot_name if bot_name != "" else TEST_USERNAME
	print("🤖 [BOT] %s (%s) khởi động..." % [display_name, "HOST" if is_host else "GUEST"])
	
	authentication.auto_login_on_request = false
	
	# Kết nối signal
	network_client.connect("connected_to_server", self, "_on_connected_to_server")
	network_client.connect("auth_request", self, "_on_auth_request")
	
	game_controller.connect("room_list_received", self, "_on_room_list_changed")
	network_client.connect("room_list_update", self, "_on_room_list_changed")

	authentication.connect("login_success", self, "_on_login_success")
	authentication.connect("login_failed", self, "_on_login_failed")

	game_controller.connect("joined_room", self, "_on_joined_room")
	game_controller.connect("game_state_updated", self, "_on_game_state_updated")
	game_controller.connect("game_event_received", self, "_on_game_event_received")
	game_controller.connect("error_received", self, "_on_error_received")
	game_controller.connect("game_started", self, "_on_game_started")
	
	network_client.connect("chain_triggered", self, "_on_chain_triggered")

	_connect_to_server()


func _connect_to_server():
	if network_client.connect_to_server(SERVER_IP, SERVER_PORT):
		print("✅ [BOT] Gửi yêu cầu kết nối %s:%d" % [SERVER_IP, SERVER_PORT])
		connect_timeout = get_tree().create_timer(TIMEOUT_SECONDS)
		connect_timeout.connect("timeout", self, "_on_timeout")
	else:
		print("🔴 [BOT] Kết nối thất bại!")
		_finish_test(false)


func _on_connected_to_server():
	if connect_timeout:
		connect_timeout.disconnect("timeout", self, "_on_timeout")
		connect_timeout = null
	print("🟢 [BOT] Đã kết nối, chờ AUTH_REQUEST...")


func _on_auth_request(data):
	if has_sent_login:
		return
	print("🔐 [BOT] Nhận AUTH_REQUEST → gửi login...")
	if authentication.login(TEST_USERNAME):
		has_sent_login = true
		print("📤 [BOT] Gửi login với tên: %s" % TEST_USERNAME)
	else:
		_finish_test(false)


func _on_login_success(pid, is_guest):
	player_id = pid
	print("🟢 [BOT] Login thành công pid=%s" % pid)
	if is_host:
		game_controller.create_room("pvp_1v1")
	else:
		game_controller.request_room_list()


func _on_login_failed(code):
	print("❌ [BOT] Login thất bại: %s" % str(code))
	_finish_test(false)


func _on_room_list_changed(rooms):
	if is_host or is_waiting_for_action:
		return
	for room in rooms:
		if room.get("status", "") == "waiting":
			print("👉 [BOT] Vào phòng: %s" % room["room_id"])
			game_controller.join_room(room["room_id"])
			is_waiting_for_action = true
			return


func _on_joined_room(rid):
	room_id = rid
	is_waiting_for_action = false
	print("✅ [BOT] Đã vào phòng %s" % rid)


func _on_game_started(rid):
	print("⚔️ [BOT] Trận bắt đầu: %s" % rid)


func _on_game_state_updated(state):
	var my_id = game_controller.get_current_player_id()
	if state.get("turn", "") != my_id or is_waiting_for_action:
		return
	
	print("🔄 [BOT] Lượt của mình | Phase: %s | Turn Count: %d" % [state.get("phase", "?"), state.get("current_turn_count", 1)])
	is_waiting_for_action = true
	yield(get_tree().create_timer(0.5), "timeout")
	_send_smart_action(state)


func _send_smart_action(state):
	var my_id = game_controller.get_current_player_id()
	var player = state.players.get(my_id, {})
	var actions = game_controller.current_available_actions

	# ✅ Log chi tiết
	print("🎮 [BOT] Xử lý hành động...")
	print("   ├─ Phase: %s" % state.get("phase", "?"))
	print("   ├─ Hand size: %d" % player.get("hand", []).size())
	if actions.empty(): 
		print("[bot] action empty !!!")
		return 
	print("   ├─ Available actions: %s" % str(actions.types))

	if not actions or not actions.types:
		print("⏭️ [BOT] Không có hành động → END_TURN")
		game_controller.end_turn()
		is_waiting_for_action = false
		return

	# ✅ Kiểm tra hand_data an toàn
	if not player.has("hand_data") or not player.hand_data:
		print("🃏 [BOT] Không có hand_data → END_TURN")
		game_controller.end_turn()
		is_waiting_for_action = false
		return

	# 1. Bốc bài nếu được phép
	if state.get("phase") == "draw":
		if "DRAW_CARD" in actions.types:
			print("🎴 [BOT] Bốc bài (phase draw)")
			game_controller.submit_action("DRAW_CARD", {})
			is_waiting_for_action = false
			return
		else:
			print("🃏 [BOT] Không được bốc bài (người đi trước)")

	# 2. Dùng spell mạnh nếu ở main phase
	if state.get("phase") in ["main1", "main2"]:
		if "PLAY_SPELL" in actions.types:
			for act in actions.details:
				if act.type == "PLAY_SPELL":
					var card_id = act.payload.card_id
					for hand_card in player.hand_data:
						if hand_card.card_id == card_id:
							if hand_card.effect == "draw_2":
								print("⚡ [BOT] Dùng Pot of Greed")
								game_controller.submit_action("PLAY_SPELL", act.payload)
								is_waiting_for_action = false
								return
							elif hand_card.effect == "destroy_all_monsters":
								print("⚡ [BOT] Dùng Dark Hole")
								game_controller.submit_action("PLAY_SPELL", act.payload)
								is_waiting_for_action = false
								return

	# 3. Summon quái ATK cao
	if state.get("phase") in ["main1", "main2"]:
		if "PLAY_MONSTER" in actions.types:
			var best_atk = -1
			var best_action = null
			for act in actions.details:
				if act.type == "PLAY_MONSTER":
					var card_id = act.payload.card_id
					for hand_card in player.hand_data:
						if hand_card.card_id == card_id and hand_card.type == "monster":
							if hand_card.atk > best_atk:
								best_atk = hand_card.atk
								best_action = act
			if best_action:
				print("🃏 [BOT] Triệu hồi: %s (ATK=%d)" % [best_action.payload.card_id, best_atk])
				game_controller.play_monster(best_action.payload.card_id, best_action.payload.to_zone)
				is_waiting_for_action = false
				return

	# 4. Set trap nếu có
	if "SET_TRAP" in actions.types:
		for act in actions.details:
			if act.type == "SET_TRAP":
				print("🛡️ [BOT] Set trap: %s" % act.payload.card_id)
				game_controller.submit_action("SET_TRAP", act.payload)
				is_waiting_for_action = false
				return

	# 5. END_TURN nếu không làm gì được
	print("⏭️ [BOT] Không có hành động tích cực → END_TURN")
	game_controller.end_turn()
	is_waiting_for_action = false
	return  # Đảm bảo dừng lại


func _on_chain_triggered(trigger):
	if is_waiting_for_action:
		return
	var my_id = game_controller.get_current_player_id()
	var player = game_controller.current_game_state.players.get(my_id, {})
	var actions = game_controller.current_available_actions

	if not actions or not "ACTIVATE_EFFECT" in actions.types:
		return

	for act in actions.details:
		if act.type == "ACTIVATE_EFFECT":
			var zone_idx = act.payload.get("zone_idx", -1)
			var card_obj = player.spell_trap_zones.get(zone_idx, null)
			if not card_obj or not card_obj.has("card_data"):
				continue
			var effect = card_obj.card_data.get("effect", "")

			if trigger.get("type") == "ATTACK_DECLARED" and effect == "destroy_all_attackers":
				print("💥 [BOT] Phản ứng bằng Mirror Force")
				is_waiting_for_action = true
				yield(get_tree().create_timer(0.3), "timeout")
				game_controller.submit_action("ACTIVATE_EFFECT", act.payload)
				is_waiting_for_action = false
				return
			elif trigger.get("type") == "SUMMON" and effect == "destroy_summoned_monster":
				print("💥 [BOT] Phản ứng bằng Trap Hole")
				is_waiting_for_action = true
				yield(get_tree().create_timer(0.3), "timeout")
				game_controller.submit_action("ACTIVATE_EFFECT", act.payload)
				is_waiting_for_action = false
				return


func _on_game_event_received(events):
	for event in events:
		if event.get("type", "") == "WIN":
			var winner = event.get("winner", "")
			var reason = event.get("reason", "unknown")
			print("🏆 [BOT] Trận đấu kết thúc! Winner: %s | Lý do: %s" % [winner, reason])
			_finish_test(winner == player_id)


func _on_error_received(code, message):
	print("❌ [BOT] Lỗi từ server: %s | %s" % [code, message])
	_finish_test(false)


func _on_timeout():
	print("⏰ [BOT] TIMEOUT: Không nhận được phản hồi từ server")
	_finish_test(false)


func _finish_test(success):
	if connect_timeout:
		connect_timeout.disconnect("timeout", self, "_on_timeout")
		connect_timeout = null
	print("==================================")
	var result_text = "✅ [BOT] TEST OK" if success else "❌ [BOT] TEST FAIL"
	print(result_text)
	print("==================================")
	network_client._disconnect()
	queue_free()
