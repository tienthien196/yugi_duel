# ===========================================================================
# BotTestClient.gd - Client test tự động (phiên bản độc lập)
# ✅ Đã sửa: chỉ gửi login khi server yêu cầu, tránh mất gói
# ===========================================================================
extends Node

const SERVER_IP = "127.0.0.1"
const SERVER_PORT = 8080
var TEST_USERNAME = "bot_%d" % (randi() % 1000)  # → bot_123 (5-7 ký tự)

var room_id = ""
var player_id = ""
var has_sent_login = false

export var is_host = true

onready var network_client = NetworkManager
onready var authentication = Authentication
onready var game_controller = GameClientController


func _ready():
	authentication.auto_login_on_request = false

	network_client.connect("connected_to_server", self, "_on_connected_to_server")
	network_client.connect("auth_request", self, "_on_auth_request")  # ← BẮT BUỘC
	network_client.connect("room_list_update", self, "_on_room_list_update")
	authentication.connect("login_success", self, "_on_login_success")
	authentication.connect("login_failed", self, "_on_login_failed")
	game_controller.connect("joined_room", self, "_on_joined_room")
	game_controller.connect("game_state_updated", self, "_on_game_state_updated")
	game_controller.connect("game_event_received", self, "_on_game_event_received")
	game_controller.connect("error_received", self, "_on_error_received")
	game_controller.connect("game_started", self, "_on_game_started")

	_connect_to_server()


func _connect_to_server():
	if network_client.connect_to_server(SERVER_IP, SERVER_PORT):
		print("✅ [BOT] Đã gửi yêu cầu kết nối đến %s:%d" % [SERVER_IP, SERVER_PORT])
	else:
		print("🔴 [BOT] Kết nối thất bại!")
		_finish_test(false)


func _on_connected_to_server():
	print("🟢 [BOT] Kết nối thành công. Đang chờ server yêu cầu xác thực...")


func _on_auth_request(data):
	if has_sent_login:
		return
	print("🔐 [BOT] Server yêu cầu xác thực → gửi đăng nhập...")
	if authentication.login(TEST_USERNAME):
		has_sent_login = true
		print("📤 [BOT] Đã gửi đăng nhập: %s" % TEST_USERNAME)
	else:
		print("❌ [BOT] Gửi đăng nhập thất bại!")
		_finish_test(false)


func _on_login_success(pid, is_guest):
	self.player_id = pid
	print("🟢 [BOT] ✅ Xác thực thành công: %s (guest=%s)" % [pid, is_guest])

	if is_host:
		print("🎮 [BOT] Tạo phòng mới...")
		game_controller.create_room("pvp_1v1")
	else:
		print("🔍 [BOT] Yêu cầu danh sách phòng...")
		game_controller.request_room_list()


func _on_login_failed(error_code):
	match error_code:
		"INVALID_USERNAME":
			print("❌ Tên quá dài hoặc quá ngắn!")
		"USERNAME_EMPTY":
			print("❌ Tên trống!")
		"AUTH_REQUIRED":
			print("❌ Cần đăng nhập!")
		_:
			print("❌ Lỗi: %s" % error_code)
	_finish_test(false)


func _on_joined_room(rid):
	room_id = rid
	print("✅ [BOT] Đã vào phòng: %s" % room_id)


func _on_room_list_update(rooms):
	if is_host:
		return
	for room in rooms:
		if room.status == "waiting" and room.player_count == 1:
			print("👉 [BOT] Vào phòng: %s" % room.room_id)
			game_controller.join_room(room.room_id)
			return


func _on_game_started(rid):
	print("🎮 [BOT] ⚔️ Trận đấu bắt đầu: %s" % rid)


func _on_game_state_updated(state):
	print("🔄 [BOT] Nhận trạng thái: Lượt=%s, Phase=%s" % [state.turn, state.phase])
	_send_test_actions(state)


func _send_test_actions(state):
	var my_id = game_controller.get_current_player_id()
	if state.turn != my_id:
		return
	if state.phase in ["main1", "main2"]:
		var hand = state.players[my_id].hand
		var zones = state.players[my_id].field.monster_zones
		for i in range(zones.size()):
			if zones[i] == null and hand.size() > 0:
				game_controller.play_monster(hand[0], i)
				return
		game_controller.end_turn()


func _on_game_event_received(events):
	for event in events:
		if event.type == "WIN":
			print("🏆 [BOT] Trận kết thúc! Người thắng: %s" % event.winner)
			_finish_test(event.winner == player_id)


func _on_error_received(code, message):
	print("❌ [BOT] Lỗi: %s | %s" % [code, message])
	_finish_test(false)


func _finish_test(success):
	var status = "✅ [BOT] TEST THÀNH CÔNG!" if success else "❌ [BOT] TEST THẤT BẠI!"
	print("==================================")
	print(status)
	print("==================================")
	network_client._disconnect()
	queue_free()
