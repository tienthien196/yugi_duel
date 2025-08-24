extends Node


# Ví dụ: Lấy ATK của bài
var card = CardDatabase.get("BLUE_EYES_WHITE_DRAGON")

func _ready():
	if card:
		print("ATK:", card.attack)  # 3000

	# Kiểm tra tồn tại
	if CardDatabase.exists("DARK_MAGICIAN"):
		print("Có bài Dark Magician!")

	# Tìm theo tên
	var results = CardDatabase.find_by_name("Blue")
	for card in results:
		print("Tìm thấy:", card.name)
