# ===========================================================================
# AuthManager.gd - Quản lý xác thực & bảo mật người chơi (Godot 3.6)
# Autoload Singleton
# Chức năng:
#   - Đăng nhập / tạo session
#   - Tạo và kiểm tra token
#   - Liên kết player_id với peer_id
#   - Gửi tín hiệu khi xác thực thành công
# ===========================================================================
extends Node

# Thời hạn token (giây) - 1 giờ
const TOKEN_EXPIRE_TIME = 3600

# Cấu trúc session: token → { player_id, peer_id, created_time }
var sessions = {}

# Signal
signal player_authenticated(player_id, session_token, peer_id)
signal player_logged_out(player_id)
signal auth_failed(peer_id, error_code)

# Tham chiếu đến NetworkManager
onready var network_manager = NetworkManager

# ===========================================================================
# _ready()
# Kết nối với NetworkManager để lắng nghe kết nối
# ===========================================================================
func _ready():
	# yield(get_tree().create_timer(1), "timeout")
	#if not Engine.has_singleton("NetworkManager"):
	if not network_manager:
		push_error("❌ AuthManager: NetworkManager không tồn tại trong Autoload!")
		return
	# Lắng nghe khi client kết nối
	network_manager.connect("client_connected", self, "_on_client_connected")
	network_manager.connect("message_received", self, "_on_message_received")

# ===========================================================================
# _on_client_connected(player_id, peer_id)
# Khi client kết nối → yêu cầu đăng nhập
# player_id ở đây chỉ là tạm "player_X"
# ===========================================================================
func _on_client_connected(player_id, peer_id):
	print("🔐 AuthManager: Client peer=%d cần xác thực." % peer_id)
	# Gửi yêu cầu đăng nhập
	var msg = {
		"type": "AUTH_REQUEST",
		"message": "Vui lòng gửi AUTH_LOGIN để xác thực."
	}
	network_manager.send_message_to_player(player_id, msg)

# ===========================================================================
# _on_message_received(player_id, message)
# Xử lý tin nhắn, đặc biệt là AUTH_LOGIN
# ===========================================================================
func _on_message_received(player_id, message):
	if message.type == "AUTH_LOGIN":
		_handle_auth_login(message, player_id)
	elif message.type == "AUTH_VERIFY":
		_handle_auth_verify(message, player_id)
	elif message.type == "LOGOUT":
		_handle_logout(message, player_id)
	else:
		# Nếu chưa xác thực, chặn mọi tin nhắn không phải AUTH
		if not _is_player_authenticated(player_id):
			_send_error(player_id, "AUTH_REQUIRED")
			return

# ===========================================================================
# _handle_auth_login(message, temp_player_id)
# Xử lý đăng nhập: client gửi username, có thể kèm guest/token
# ===========================================================================
func _handle_auth_login(message, temp_player_id):
	var username = message.get("username", "").strip_edges()
	var token = message.get("token", "")  # Nếu dùng token trước đó
	var peer_id = _get_peer_from_player(temp_player_id)
	if peer_id == 0:
		_send_error(temp_player_id, "INVALID_PEER")
		return
	# Kiểm tra username
	if username == "":
		# Tạo username tạm (guest)
		username = "guest_%d" % OS.get_unix_time() % 10000
		print("🎮 Tạo guest user: %s" % username)
	# Nếu có token → kiểm tra lại
	if token != "" and _is_valid_token(token):
		var existing = sessions[token]
		if existing.player_id == username:
			# Dùng lại session
			_renew_session(token)
			_complete_auth(username, token, peer_id)
			return
	# Tạo session mới
	var new_token = _generate_token()
	sessions[new_token] = {
		"player_id": username,
		"peer_id": peer_id,
		"created_time": OS.get_unix_time(),
		"last_active": OS.get_unix_time()
	}
	print("✅ AuthManager: '%s' đã đăng nhập với token: %s" % [username, new_token])
	_complete_auth(username, new_token, peer_id)

# ===========================================================================
# _handle_auth_verify(message, temp_player_id)
# Client gửi token để xác minh
# ===========================================================================
func _handle_auth_verify(message, temp_player_id):
	var token = message.get("token", "")
	var peer_id = _get_peer_from_player(temp_player_id)
	if not _is_valid_token(token):
		_send_error(temp_player_id, "INVALID_TOKEN")
		return
	var session = sessions[token]
	if session.peer_id != peer_id:
		_send_error(temp_player_id, "TOKEN_MISMATCH")
		return
	_complete_auth(session.player_id, token, peer_id)

# ===========================================================================
# _handle_logout(message, temp_player_id)
# Người chơi đăng xuất
# ===========================================================================
func _handle_logout(message, temp_player_id):
	var token = message.get("token", "")
	if token in sessions:
		var player_id = sessions[token].player_id
		sessions.erase(token)
		emit_signal("player_logged_out", player_id)
		print("🔐 AuthManager: '%s' đã đăng xuất." % player_id)
	# Gửi phản hồi
	network_manager.send_message_to_player(temp_player_id, {
		"type": "LOGOUT_SUCCESS"
	})

# ===========================================================================
# _complete_auth(player_id, token, peer_id)
# Hoàn tất xác thực → cập nhật player_id thật, phát tín hiệu
# ===========================================================================
func _complete_auth(player_id, token, peer_id):
	# Cập nhật lại ánh xạ trong NetworkManager
	network_manager.peer_to_player[peer_id] = player_id
	# Phát tín hiệu cho ServerManager
	emit_signal("player_authenticated", player_id, token, peer_id)
	# Gửi phản hồi thành công
	var response = {
		"type": "AUTH_SUCCESS",
		"player_id": player_id,
		"token": token,
		"server_time": OS.get_unix_time()
	}
	network_manager.send_message_to_player(player_id, response)
	print("🟢 AuthManager: '%s' đã xác thực thành công (peer=%d)" % [player_id, peer_id])

# ===========================================================================
# _is_player_authenticated(player_id) → bool
# Kiểm tra player_id đã xác thực chưa
# ===========================================================================
func _is_player_authenticated(player_id):
	for token in sessions:
		if sessions[token].player_id == player_id:
			return true
	return false

# ===========================================================================
# is_token_valid(token) → bool
# Dùng bên ngoài để kiểm tra token (vd: trong ServerManager)
# ===========================================================================
func is_token_valid(token):
	return _is_valid_token(token)

# ===========================================================================
# get_player_id_by_token(token) → String
# Trả về player_id nếu token hợp lệ
# ===========================================================================
func get_player_id_by_token(token):
	if _is_valid_token(token):
		return sessions[token].player_id
	return ""

# ===========================================================================
# get_peer_id_by_player(player_id) → int
# Trả về peer_id
# ===========================================================================
func get_peer_id_by_player(player_id):
	for token in sessions:
		if sessions[token].player_id == player_id:
			return sessions[token].peer_id
	return 0

# ===========================================================================
# _is_valid_token(token) → bool
# Kiểm tra token tồn tại và chưa hết hạn
# ===========================================================================
func _is_valid_token(token):
	if not sessions.has(token):
		return false
	var session = sessions[token]
	var now = OS.get_unix_time()
	if now - session.created_time > TOKEN_EXPIRE_TIME:
		sessions.erase(token)
		return false
	# Cập nhật last_active
	session.last_active = now
	return true

# ===========================================================================
# _renew_session(token)
# Làm mới thời gian session
# ===========================================================================
func _renew_session(token):
	if sessions.has(token):
		sessions[token].created_time = OS.get_unix_time()


# ===========================================================================
# _generate_token() → String
# Tạo token ngẫu nhiên 32 ký tự (chỉ dùng tính năng Godot 3.6)
# ===========================================================================
func _generate_token():
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var len_ = chars.length()
	var rand_str = ""
	for i in range(32):
		var c = chars[randi() % len_]
		rand_str += c
	return rand_str

# ===========================================================================
# _get_peer_from_player(temp_player_id) → int
# Lấy peer_id từ NetworkManager
# ===========================================================================
func _get_peer_from_player(player_id):
	return network_manager._get_peer_from_player(player_id)

# ===========================================================================
# _send_error(player_id, error_code)
# Gửi lỗi xác thực
# ===========================================================================
func _send_error(player_id, error_code):
	var msg = {
		"type": "AUTH_ERROR",
		"code": error_code,
		"message": _get_error_message(error_code)
	}
	network_manager.send_message_to_player(player_id, msg)

# ===========================================================================
# _get_error_message(code) → String
# Bản mô tả lỗi
# ===========================================================================
func _get_error_message(code):
	match code:
		"AUTH_REQUIRED": return "Cần đăng nhập trước khi thực hiện hành động."
		"INVALID_TOKEN": return "Token không hợp lệ hoặc đã hết hạn."
		"TOKEN_MISMATCH": return "Token không khớp với kết nối hiện tại."
		"INVALID_PEER": return "Không tìm thấy peer."
		"INVALID_CREDENTIALS": return "Tên đăng nhập hoặc mật khẩu sai."
		_:
			return "Lỗi xác thực không xác định."

# ===========================================================================
# cleanup_expired_sessions()
# Dọn dẹp session hết hạn (gọi từ ServerManager._process)
# ===========================================================================
func cleanup_expired_sessions():
	var now = OS.get_unix_time()
	var expired = []
	for token in sessions:
		if now - sessions[token].created_time > TOKEN_EXPIRE_TIME:
			expired.append(token)
	for token in expired:
		var player_id = sessions[token].player_id
		sessions.erase(token)
		print("🧹 AuthManager: Session hết hạn đã xóa: %s" % player_id)
