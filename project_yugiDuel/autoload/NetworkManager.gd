# ===========================================================================
# NetworkManager.gd - Quản lý kết nối multiplayer dùng ENet (Godot 3.6)
# Autoload Singleton
# Chức năng:
#   - Khởi tạo server ENet
#   - Quản lý kết nối/disconnect
#   - Nhận và định tuyến tin nhắn
#   - Gửi dữ liệu về client
# ===========================================================================
extends Node

# Cổng server sẽ lắng nghe
const DEFAULT_PORT = 8080

# Peer ID của server (luôn là 1)
const SERVER_PEER_ID = 1

# Trạng thái
var multiplayer_peer = null
var is_server = false

# Danh sách peer_id → player_id (mapping)
var peer_to_player = {}

# Signal để gửi tin hiệu đến các manager khác
signal client_connected(player_id, peer_id)
signal client_disconnected(peer_id)
signal message_received(player_id, message)

# ===========================================================================
# _ready()
# Khởi tạo server ENet
# ===========================================================================
func _ready():
	# Thiết lập multiplayer
	get_tree().network_peer = _create_server(DEFAULT_PORT)
	var error = get_tree().network_peer
	if error:
		is_server = true
		print("🌐 NetworkManager: Server đang chạy trên cổng %d" % DEFAULT_PORT)
	else:
		push_error("❌ NetworkManager: Không thể khởi tạo server ENet")
		return

	# Kết nối các signal
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected_to_server")
	get_tree().connect("connection_failed", self, "_on_connection_failed")

# ===========================================================================
# _create_server(port) → NetworkedMultiplayerENet
# Tạo server ENet lắng nghe trên cổng
# ===========================================================================
func _create_server(port):
	var enet = NetworkedMultiplayerENet.new()
	var err = enet.create_server(port, 32)  # Tối đa 32 client
	if err != OK:
		push_error("Lỗi tạo server ENet: %d" % err)
		return null
	return enet

# ===========================================================================
# _process(delta)
# Xử lý tin nhắn mạng
# ===========================================================================
func _process(delta):
	if not is_server or not multiplayer.network_peer:
		return
	# Đảm bảo xử lý tất cả tin nhắn
	multiplayer.poll()

# ===========================================================================
# _on_peer_connected(peer_id)
# Khi client kết nối thành công
# peer_id: ID do ENet cấp (2, 3, 4,...)
# ===========================================================================
func _on_peer_connected(peer_id):
	print("🟢 Client kết nối: peer_id=%d" % peer_id)
	# Gán tạm player_id theo peer_id
	var player_id = "player_%d" % peer_id
	peer_to_player[peer_id] = player_id
	# Phát tín hiệu để các manager khác xử lý (ví dụ AuthManager)
	emit_signal("client_connected", player_id, peer_id)
	# Gửi phản hồi chào mừng
	var welcome_msg = {
		"type": "WELCOME",
		"your_player_id": player_id,
		"server_time": OS.get_unix_time()
	}
	rpc_id(peer_id, "receive_message", welcome_msg)

# ===========================================================================
# _on_peer_disconnected(peer_id)
# Khi client ngắt kết nối
# ===========================================================================
func _on_peer_disconnected(peer_id):
	var player_id = peer_to_player.get(peer_id, "unknown")
	print("🔴 Client ngắt kết nối: peer_id=%d, player_id=%s" % [peer_id, player_id])
	peer_to_player.erase(peer_id)
	emit_signal("client_disconnected", peer_id)

# ===========================================================================
# _on_connected_to_server()
# (Chỉ dùng nếu là client – không cần thiết cho server)
# ===========================================================================
func _on_connected_to_server():
	pass

# ===========================================================================
# _on_connection_failed()
# (Chỉ dùng nếu là client)
# ===========================================================================
func _on_connection_failed():
	pass

# ===========================================================================
# receive_message(message) ← RPC
# Hàm nhận tin nhắn từ client (gọi qua RPC)
# ===========================================================================
remote func receive_message(message):
	var peer_id = get_tree().get_network_peer().get_packet_peer()
	var player_id = peer_to_player.get(peer_id, "unknown")
	
	if message.type == null:
		_send_error(peer_id, "MISSING_MESSAGE_TYPE")
		return
	
	print("📩 Nhận tin: peer_id=%d | player_id=%s | type=%s" % [peer_id, player_id, message.type])
	
	# Phát tín hiệu để các manager khác xử lý (AuthManager, ServerManager)
	emit_signal("message_received", player_id, message)

# ===========================================================================
# send_message_to_player(player_id, data)
# Gửi tin về 1 người chơi
# ===========================================================================
func send_message_to_player(player_id, data):
	var peer_id = _get_peer_from_player(player_id)
	if peer_id == 0:
		push_warning("Không tìm thấy peer cho player: %s" % player_id)
		return
	rpc_id(peer_id, "receive_message", data)

# ===========================================================================
# broadcast_message(data, exclude_player = null)
# Gửi tin đến tất cả client (trừ 1 nếu cần)
# ===========================================================================
func broadcast_message(data, exclude_player = null):
	for peer_id in peer_to_player:
		if exclude_player:
			var p = peer_to_player[peer_id]
			if p == exclude_player:
				continue
		rpc_id(peer_id, "receive_message", data)

# ===========================================================================
# _get_peer_from_player(player_id) → int
# Tìm peer_id từ player_id
# ===========================================================================
func _get_peer_from_player(player_id):
	for pid in peer_to_player:
		if pid == player_id:
			return peer_to_player[pid]
	return 0

# ===========================================================================
# _send_error(peer_id, error_code, message = "")
# Gửi phản hồi lỗi về client
# ===========================================================================
func _send_error(peer_id, error_code, message = ""):
	var err_msg = {
		"type": "ERROR",
		"code": error_code,
		"message": message if message else "Lỗi: %s" % error_code
	}
	rpc_id(peer_id, "receive_message", err_msg)

# ===========================================================================
# shutdown()
# Tắt server
# ===========================================================================
func shutdown():
	if multiplayer.network_peer:
		multiplayer.network_peer.close()
		multiplayer.network_peer = null
		print("🛑 NetworkManager: Server đã tắt")
