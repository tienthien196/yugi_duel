# ===========================================================================
# DatabaseManager.gd - Quản lý dữ liệu người chơi (Godot 3.6)
# Autoload Singleton
# Chức năng:
#   - Đăng ký / đăng nhập người chơi
#   - Lưu deck, stats, lịch sử
#   - Dùng JSON để lưu trữ đơn giản
# ===========================================================================
extends Node

const SAVE_PATH = "user://players.json"
var players_data = {}

# ===========================================================================
# _ready()
# Nạp dữ liệu người chơi từ file
# ===========================================================================
func _ready():
	_load_players()
	randomize()  # Đảm bảo randi() hoạt động

# ===========================================================================
# _load_players()
# Đọc file JSON, nếu không có thì tạo mới
# ===========================================================================
func _load_players():
	if not File.new().file_exists(SAVE_PATH):
		players_data = {}
		print("🆕 Tạo file dữ liệu người chơi mới.")
		return

	var file = File.new()
	if file.open(SAVE_PATH, File.READ) != OK:
		push_error("❌ Không thể mở file: %s" % SAVE_PATH)
		players_data = {}
		return

	var json_str = file.get_as_text()
	file.close()

	var parse = JSON.parse(json_str)
	if parse.error != OK:
		push_error("❌ Lỗi parse JSON: %s" % parse.error_string)
		players_data = {}
		return

	players_data = parse.result if typeof(parse.result) == TYPE_DICTIONARY else {}
	print("✅ Đã nạp dữ liệu %d người chơi." % players_data.size())

# ===========================================================================
# _save_players()
# Lưu dữ liệu người chơi xuống file
# ===========================================================================
func _save_players():
	var file = File.new()
	if file.open(SAVE_PATH, File.WRITE) != OK:
		push_error("❌ Không thể ghi file: %s" % SAVE_PATH)
		return

	file.store_string(JSON.print(players_data))
	file.close()
	print("💾 Đã lưu dữ liệu người chơi.")

# ===========================================================================
# register(username, password) → Dict
# Đăng ký người chơi mới
# ===========================================================================
func register(username, password):
	if players_data.has(username):
		return { "success": false, "error": "USERNAME_EXISTS" }

	players_data[username] = {
		"username": username,
		"password_hash": _hash_password(password),
		"created_at": OS.get_unix_time(),
		"last_login": 0,
		"lp": 8000,
		"deck": [
			"BLUE_EYES_WHITE_DRAGON", "DARK_MAGICIAN",
			"POT_OF_GREED", "MONSTER_REBORN", "MIRROR_FORCE",
			"GYOUKI", "SUMMONED_SKULL"
		],
		"stats": {
			"win": 0,
			"loss": 0,
			"draw": 0
		},
		"match_history": []
	}
	_save_players()
	return { "success": true, "player": players_data[username].duplicate() }

# ===========================================================================
# login(username, password) → Dict
# Xác thực đăng nhập
# ===========================================================================
func login(username, password):
	if not players_data.has(username):
		return { "success": false, "error": "USER_NOT_FOUND" }

	var data = players_data[username]
	if data["password_hash"] != _hash_password(password):
		return { "success": false, "error": "INVALID_PASSWORD" }

	data["last_login"] = OS.get_unix_time()
	_save_players()

	return { "success": true, "player": data.duplicate() }

# ===========================================================================
# get_player(username) → Dict
# Lấy thông tin người chơi (không bao gồm password)
# ===========================================================================
func get_player(username):
	if not players_data.has(username):
		return {}
	var p = players_data[username].duplicate()
	p.erase("password_hash")
	return p

# ===========================================================================
# update_stats(username, win, loss, draw)
# Cập nhật thống kê sau trận đấu
# ===========================================================================
func update_stats(username, win=0, loss=0, draw=0):
	if not players_data.has(username):
		return
	players_data[username]["stats"]["win"] += win
	players_data[username]["stats"]["loss"] += loss
	players_data[username]["stats"]["draw"] += draw
	_save_players()

# ===========================================================================
# add_match_history(username, opponent, result, room_id)
# Thêm lịch sử trận đấu
# ===========================================================================
func add_match_history(username, opponent, result, room_id):
	if not players_data.has(username):
		return
	players_data[username]["match_history"].append({
		"opponent": opponent,
		"result": result,  # "win", "loss", "draw"
		"room_id": room_id,
		"timestamp": OS.get_unix_time()
	})
	_save_players()

# ===========================================================================
# get_deck(username) → Array
# Lấy bộ bài của người chơi
# ===========================================================================
func get_deck(username):
	return players_data.get(username, {}).get("deck", [
		"BLUE_EYES_WHITE_DRAGON", "DARK_MAGICIAN",
		"POT_OF_GREED", "MONSTER_REBORN", "MIRROR_FORCE"
	])

# ===========================================================================
# _hash_password(password) → String
# Hash đơn giản (không dùng MD5 thật, chỉ mô phỏng)
# ===========================================================================
func _hash_password(password):
	var hash_ = 5381
	for c in password.to_ascii():
		hash_ = (hash_ * 33) + c
	return str(hash_)

# ===========================================================================
# create_guest() → Dict
# Tạo người chơi tạm (guest)
# ===========================================================================
func create_guest():
	var guest_id = "guest_%d" % (OS.get_unix_time() % 10000)
	var deck = [
		"GYOUKI", "SUMMONED_SKULL", "POT_OF_GREED",
		"TRAP_HOLE", "SUIJIN", "DARK_MAGICIAN"
	]
	players_data[guest_id] = {
		"username": guest_id,
		"password_hash": "",
		"created_at": OS.get_unix_time(),
		"last_login": OS.get_unix_time(),
		"lp": 8000,
		"deck": deck,
		"stats": { "win": 0, "loss": 0, "draw": 0 },
		"match_history": [],
		"is_guest": true
	}
	_save_players()
	return { "success": true, "player": players_data[guest_id].duplicate() }
