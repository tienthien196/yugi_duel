# ===========================================================================
# CardDatabase.gd - Nạp và quản lý toàn bộ dữ liệu bài Yu-Gi-Oh!
# Autoload Singleton - Dùng để truy vấn thông tin bài
# ===========================================================================

extends Node

# Lưu toàn bộ dữ liệu bài: card_id → card_data
var cards = {}

# Signal để thông báo lỗi cho bot hoặc debug
signal card_database_error(error_code, message)

# Error codes
const ERR_FILE_NOT_FOUND = "FILE_NOT_FOUND"
const ERR_JSON_INVALID = "JSON_INVALID"
const ERR_CARD_INVALID = "CARD_INVALID"
const ERR_CARD_NOT_FOUND = "CARD_NOT_FOUND"

# ===========================================================================
# _ready()
# Tự động nạp file JSON khi game khởi động
# ===========================================================================
func _ready():
	randomize()  # Cần cho randi()
	var error = _load_cards("res://data/cards.json")
	if error:
		emit_signal("card_database_error", error[0], error[1])
		push_error("❌ CardDatabase: Không thể nạp cards.json - %s" % error[1])
	else:
		print("✅ CardDatabase: Đã nạp %d lá bài." % cards.size())


# ===========================================================================
# _load_cards(path)
# Nạp file JSON và lưu vào bộ nhớ
# Trả về [error_code, message] nếu có lỗi, null nếu thành công
# ===========================================================================
func _load_cards(path):
	if not File.new().file_exists(path):
		return [ERR_FILE_NOT_FOUND, "File không tồn tại: %s" % path]

	var file = File.new()
	var err = file.open(path, File.READ)
	if err != OK:
		return [ERR_FILE_NOT_FOUND, "Không thể mở file: %s (mã lỗi: %d)" % [path, err]]

	var json_data = file.get_as_text()
	file.close()

	if json_data.empty():
		return [ERR_JSON_INVALID, "File JSON rỗng: %s" % path]

	var parse_result = JSON.parse(json_data)
	if parse_result.error != OK:
		return [ERR_JSON_INVALID, "Lỗi parse JSON tại dòng %d: %s" % [parse_result.error_line, parse_result.error_string]]

	var data = parse_result.result
	if typeof(data) != TYPE_DICTIONARY:
		return [ERR_JSON_INVALID, "JSON không phải object: %s" % path]

	# Validate và gán
	cards = {}
	for card_id in data:
		var card = data[card_id]
		var error = _validate_card(card_id, card)
		if error:
			emit_signal("card_database_error", ERR_CARD_INVALID, "Card %s không hợp lệ: %s" % [card_id, error])
			continue
		cards[card_id] = card

	return null


# ===========================================================================
# _validate_card(card_id, card)
# Kiểm tra dữ liệu lá bài hợp lệ
# Trả về null nếu ok, hoặc string mô tả lỗi
# ===========================================================================
func _validate_card(card_id, card):
	if not card is Dictionary:
		return "Không phải dictionary"
	if not card.has("id") or card.id != card_id:
		card.id = card_id  # Tự điền
	if not card.has("name"):
		push_warning("Card %s thiếu 'name'" % card_id)
		card.name = card_id
	if not card.has("type") or not card.type in ["monster", "spell", "trap"]:
		return "Thiếu hoặc type không hợp lệ: %s" % card.get("type", "missing")
	if card.type == "monster":
		if not card.has("atk") or typeof(card.atk) != TYPE_INT or card.atk < 0:
			return "Monster thiếu hoặc atk không hợp lệ"
		if not card.has("def") or typeof(card.def) != TYPE_INT or card.def < 0:
			return "Monster thiếu hoặc def không hợp lệ"
	if card.type in ["spell", "trap"]:
		if not card.has("effect"):
			push_warning("Card %s thiếu 'effect'" % card_id)
			card.effect = ""
	return null


# ===========================================================================
# get(card_id) → Dictionary
# Lấy dữ liệu lá bài theo ID
# Trả về {} nếu không tìm thấy
# ===========================================================================
func get(card_id):
	if cards.has(card_id):
		return cards[card_id].duplicate()  # Trả bản sao
	else:
		emit_signal("card_database_error", ERR_CARD_NOT_FOUND, "Không tìm thấy bài với ID '%s'" % card_id)
		return {}


# ===========================================================================
# exists(card_id) → bool
# Kiểm tra bài có tồn tại không
# ===========================================================================
func exists(card_id):
	return cards.has(card_id)


# ===========================================================================
# find_by_name(name) → Array[card]
# Tìm bài theo tên (phần trăm trùng khớp - đơn giản)
# ===========================================================================
func find_by_name(name):
	name = name.to_lower()
	var results = []
	for card_id in cards:
		var card = cards[card_id]
		if str(card.get("name", "")).to_lower().find(name) != -1:
			results.append(card.duplicate())
	return results


# ===========================================================================
# get_cards_by_type(type) → Array[card]
# Lấy tất cả bài theo type (monster, spell, trap)
# ===========================================================================
func get_cards_by_type(type):
	var results = []
	for card_id in cards:
		if cards[card_id].get("type") == type:
			results.append(cards[card_id].duplicate())
	return results


# ===========================================================================
# get_random_card(type=null) → Dictionary
# Lấy ngẫu nhiên một lá bài, tùy chọn lọc theo type
# ===========================================================================
func get_random_card(type=null):
	var valid_cards = cards.keys()
	if type:
		valid_cards = valid_cards.filter(func(id): return cards[id].get("type") == type)
	if valid_cards.empty():
		return {}
	var card_id = valid_cards[randi() % valid_cards.size()]
	return cards[card_id].duplicate()


# ===========================================================================
# get_all() → Dictionary
# Trả về toàn bộ cơ sở dữ liệu (dùng cho debug)
# ===========================================================================
func get_all():
	return cards.duplicate(true)