# ===========================================================================
# ServerManager.gd - Quản lý toàn bộ server multiplayer
# ===========================================================================
extends Node

# Danh sách phòng: room_id → { player_a, player_b, status }
var rooms = {}
# player_id → room_id
var player_to_room = {}

# Tham chiếu
onready var network_manager = NetworkManager
onready var auth_manager = AuthManager
onready var game_manager = GameManager

# ===========================================================================
# _ready()
# Kết nối các signal
# ===========================================================================
func _ready():
	
	auth_manager.connect("player_authenticated", self, "_on_player_authenticated")
	network_manager.connect("message_received", self, "_on_message_received")
	game_manager.connect("game_started", self, "_on_game_started")
	game_manager.connect("game_finished", self, "_on_game_finished")

# ===========================================================================
# _on_player_authenticated(player_id, token, peer_id)
# Khi người chơi xác thực thành công
# ===========================================================================
func _on_player_authenticated(player_id, token, peer_id):
	print("🟢 ServerManager: '%s' đã xác thực thành công." % player_id)
	network_manager.send_message_to_player(player_id, {
		"type": "AUTH_SUCCESS",
		"player": DatabaseManager.get_player(player_id)
	})

# ===========================================================================
# _on_message_received(player_id, message)
# Xử lý tin nhắn từ client
# ===========================================================================
func _on_message_received(player_id, message):
	match message.type:
		"CREATE_ROOM":
			_handle_create_room(player_id)
		"JOIN_ROOM":
			_handle_join_room(player_id, message.room_id)
		"LIST_ROOMS":
			_handle_list_rooms(player_id)
		"SUBMIT_ACTION":
			_handle_submit_action(player_id, message.action)
		"GET_STATE":
			_handle_get_state(player_id, message.room_id)

# ===========================================================================
# _handle_create_room(player_id)
# Tạo phòng mới
# ===========================================================================
func _handle_create_room(player_id):
	var room_id = "room_%d" % OS.get_unix_time()
	rooms[room_id] = {
		"host": player_id,
		"player_a": player_id,
		"player_b": null,
		"status": "waiting"
	}
	player_to_room[player_id] = room_id
	network_manager.send_message_to_player(player_id, {
		"type": "ROOM_CREATED",
		"room_id": room_id
	})
	_broadcast_rooms()

# ===========================================================================
# _handle_join_room(player_id, room_id)
# Vào phòng
# ===========================================================================
func _handle_join_room(player_id, room_id):
	if not rooms.has(room_id):
		_send_error(player_id, "ROOM_NOT_FOUND")
		return
	var room = rooms[room_id]
	if room.player_b != null:
		_send_error(player_id, "ROOM_FULL")
		return
	room.player_b = player_id
	player_to_room[player_id] = room_id
	# Bắt đầu trận
	var result = game_manager.create_duel(room.player_a, room.player_b)
	if result.success:
		room.status = "started"
		# Thông báo cho cả hai
		_broadcast_to_room(room_id, {
			"type": "GAME_STARTED",
			"room_id": result.room_id
		})
	else:
		_send_error(player_id, "FAILED_TO_START_GAME")

# ===========================================================================
# _handle_list_rooms(player_id)
# Gửi danh sách phòng
# ===========================================================================
func _handle_list_rooms(player_id):
	var list = []
	for rid in rooms:
		var r = rooms[rid]
		list.append({
			"room_id": rid,
			"host": r.host,
			"player_count": 1 if r.player_b == null else 2,
			"status": r.status
		})
	network_manager.send_message_to_player(player_id, {
		"type": "ROOM_LIST",
		"rooms": list
	})

# ===========================================================================
# _handle_submit_action(player_id, action)
# Gửi hành động vào trận
# ===========================================================================
func _handle_submit_action(player_id, action):
	var room_id = player_to_room.get(player_id)
	if not room_id:
		_send_error(player_id, "NOT_IN_ROOM")
		return
	action["player_id"] = player_id
	var result = game_manager.submit_action(room_id, action)
	# Gửi kết quả về người chơi
	network_manager.send_message_to_player(player_id, {
		"type": "ACTION_RESULT",
		"result": result
	})
	# Nếu có events → broadcast
	if result.success and result.events:
		_broadcast_to_room(room_id, {
			"type": "GAME_EVENT",
			"events": result.events
		})

# ===========================================================================
# _handle_get_state(player_id, room_id)
# Gửi trạng thái trận
# ===========================================================================
func _handle_get_state(player_id, room_id):
	var state = game_manager.get_game_state(room_id, player_id)
	network_manager.send_message_to_player(player_id, {
		"type": "GAME_STATE",
		"state": state
	})

# ===========================================================================
# _on_game_started(room_id, player_a, player_b)
# Khi trận đấu bắt đầu
# ===========================================================================
func _on_game_started(room_id, player_a, player_b):
	_broadcast_to_room(room_id, {
		"type": "BATTLE_STARTED",
		"room_id": room_id
	})

# ===========================================================================
# _on_game_finished(room_id, winner, reason)
# Khi trận kết thúc
# ===========================================================================
func _on_game_finished(room_id, winner, reason):
	if rooms.has(room_id):
		var player_a = rooms[room_id].player_a
		var player_b = rooms[room_id].player_b
		_broadcast_to_room(room_id, {
			"type": "GAME_OVER",
			"winner": winner,
			"reason": reason
		})
		# Dọn dẹp
		if player_a: player_to_room.erase(player_a)
		if player_b: player_to_room.erase(player_b)
		rooms.erase(room_id)
	_broadcast_rooms()

# ===========================================================================
# _broadcast_rooms()
# Gửi danh sách phòng cho tất cả
# ===========================================================================
func _broadcast_rooms():
	var list = []
	for rid in rooms:
		var r = rooms[rid]
		list.append({
			"room_id": rid,
			"host": r.host,
			"player_count": 1 if r.player_b == null else 2,
			"status": r.status
		})
	network_manager.broadcast_message({
		"type": "ROOM_LIST_UPDATE",
		"rooms": list
	})

# ===========================================================================
# _broadcast_to_room(room_id, msg)
# Gửi tin đến tất cả trong phòng
# ===========================================================================
func _broadcast_to_room(room_id, msg):
	var room = rooms.get(room_id)
	if not room: return
	for p in [room.player_a, room.player_b]:
		if p: network_manager.send_message_to_player(p, msg)

# ===========================================================================
# _send_error(player_id, error_code)
# Gửi lỗi
# ===========================================================================
func _send_error(player_id, error_code):
	network_manager.send_message_to_player(player_id, {
		"type": "ERROR",
		"code": error_code
	})
