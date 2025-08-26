# ===========================================================================
# StartMenu.gd
# Màn hình khởi động: Tạo trận đấu giữa 2 bot
# Tương thích Godot 3.6
# ===========================================================================

extends Node2D

# === Tham chiếu UI ===
onready var debug_log = $DebugLog

# === Bộ bài mẫu ===
var base_deck = [
	"BLUE_EYES_WHITE_DRAGON",
	"DARK_MAGICIAN",
	"SUMMONED_SKULL",
	"GYOUKI",
	"POT_OF_GREED",
	"MONSTER_REBORN",
	"DARK_HOLE",
	"MIRROR_FORCE",
	"TRAP_HOLE",
	"SUIJIN"
]

# ===========================================================================
# _ready
# ===========================================================================
func _ready():
	debug_log.bbcode_enabled = true
	debug_log.text = "[i]โปรแตรเริ่ม sẵn sàng. Nhấn 'Start Bot Battle' để bắt đầu.[/i]"

# ===========================================================================
# Nút: Bắt đầu trận đấu Bot vs Bot
# ===========================================================================
func _on_StartBotBattleButton_pressed():
	add_log("[b]🔄 Đang khởi tạo trận đấu Bot vs Bot...[/b]")

	# Tạo bộ bài 40 lá
	var full_deck = _create_deck(base_deck, 40)
	if not full_deck:
		add_log("[color=red]❌ Không thể tạo bộ bài: thiếu lá trong CardDatabase[/color]")
		return

	# Khởi tạo trận đấu
	add_log("🔹 Gọi DuelAPI.start_duel('bot_1', 'bot_2', deck, deck, {start_lp: 4000})")
	var result = DuelAPI.start_duel("bot_1", "bot_2", full_deck, full_deck, { "start_lp": 4000 })

	if result.success:
		add_log("[color=green]✅ Trận đấu đã khởi tạo thành công![/color]")
		add_log("🔹 Room ID: [b]%s[/b]" % result.room_id)
		add_log("🔹 LP bắt đầu: 4000")

		# Tải và tạo scene DuelScene
		var duel_scene_path = "res://scenes/DuelScene.tscn"
		if not File.new().file_exists(duel_scene_path):
			add_log("[color=red]❌ Không tìm thấy file: %s[/color]" % duel_scene_path)
			return

		var duel_scene = load(duel_scene_path).instance()
		if not duel_scene:
			add_log("[color=red]❌ Không thể tạo instance DuelScene[/color]")
			return

		# Gán dữ liệu
		duel_scene.room_id = result.room_id
		duel_scene.player_id = "bot_1"  # Giao diện xem từ góc nhìn bot_1

		# Đăng ký bot với BotController (nếu tồn tại)
		if BotController:
			BotController.register_bot("bot_1")
			BotController.register_bot("bot_2")
			add_log("🤖 BotController: Đã đăng ký bot_1 và bot_2")
		else:
			add_log("[color=yellow]⚠️ BotController không tồn tại – bot sẽ không hành động[/color]")
			return

		# Thêm vào cây scene và đóng menu
		get_tree().root.add_child(duel_scene)
		add_log("[b]🎮 Trận đấu đã bắt đầu! Chuyển sang DuelScene...[/b]")
		self.queue_free()

	else:
		var error = result.get("error", "UNKNOWN")
		add_log("[color=red]❌ Lỗi khởi tạo trận đấu: %s[/color]" % error)

# ===========================================================================
# Tạo bộ bài 40 lá từ danh sách mẫu
# Trả về mảng 40 lá, kiểm tra tồn tại trong CardDatabase
# ===========================================================================
func _create_deck(template, target_size):
	var deck = []
	for i in range(target_size):
		var card_id = template[i % template.size()]
		if not CardDatabase.exists(card_id):
			push_error("Card không tồn tại: %s" % card_id)
			return null
		deck.append(card_id)
	return deck

# ===========================================================================
# Thêm log với BBCode
# ===========================================================================
func add_log(text):
	debug_log.append_bbcode("\n" + text)
