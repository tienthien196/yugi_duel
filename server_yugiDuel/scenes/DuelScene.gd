# ===========================================================================
# DuelScene.gd
# Scene chính: Hiển thị trận đấu Yu-Gi-Oh! (chỉ xem)
# - Không log, không debug
# - Xử lý chiến thắng, dừng cập nhật
# - Tương thích với bot vs bot
# ===========================================================================

extends Node2D

# === Export ===
export(String) var room_id = ""
export(String) var player_id = "player_1"

# === UI References ===
onready var phase_label = $CenterPanel/PhaseLabel
onready var turn_label = $CenterPanel/TurnLabel
onready var end_turn_button = $CenterPanel/EndTurnButton
onready var action_log = $ActionLogPanel/ActionLog

onready var player_lp_label = $PlayerField/PlayerInfo/PlayerLPLabel
onready var opponent_lp_label = $OpponentField/OpponentInfo/OpponentLPLabel
onready var player_hand_container = $PlayerField/VBoxContainer/PlayerHand
onready var player_monster_zones = $PlayerField/VBoxContainer/PlayerMonsterZones
onready var player_spelltrap_zones = $PlayerField/VBoxContainer/PlayerSpellTrapZones
onready var opponent_monster_zones = $OpponentField/VBoxContainer2/OpponentMonsterZones
onready var opponent_spelltrap_zones = $OpponentField/VBoxContainer2/OpponentSpellTrapZones
onready var timer = $Clock

# === Autoload ===
onready var duel = DuelAPI

# === State ===
var game_state = {}
var opponent_id = ""

# ===========================================================================
# _ready
# ===========================================================================
func _ready():
	if room_id == "":
		get_tree().quit()
		return
	timer.connect("timeout", self, "_on_Timer_timeout")
	timer.start(0.5)
	_on_Timer_timeout()

# ===========================================================================
# Cập nhật trạng thái
# ===========================================================================
func _on_Timer_timeout():
	var new_state = duel.get_game_state(room_id, player_id)
	if not new_state:
		return

	# Nếu trạng thái thay đổi
	if str(new_state) != str(game_state):
		game_state = new_state
		opponent_id = _get_opponent_id()

		# ✅ Kiểm tra NGAY nếu trận đã kết thúc
		if game_state["winner"]:
			_show_victory_screen(game_state["winner"], game_state["win_reason"])
			timer.stop()  # Dừng cập nhật
			return

		_update_ui()

# ===========================================================================
# Cập nhật UI
# ===========================================================================
func _update_ui():
	phase_label.text = "Phase: " + game_state["phase"].capitalize()
	turn_label.text = "Turn: " + ("You" if game_state["turn"] == player_id else "Opponent")

	var player = game_state["players"][player_id]
	var opponent = game_state["players"].get(opponent_id, {})

	player_lp_label.text = "LP: %d" % player["life_points"]
	opponent_lp_label.text = "LP: %d" % opponent.get("life_points", 0)

	end_turn_button.visible = (game_state["turn"] == player_id)

	_update_player_hand(player["hand"])
	_update_field_group(player_monster_zones, player["monster_zones"], false)
	_update_field_group(player_spelltrap_zones, player["spell_trap_zones"], false)
	_update_field_group(opponent_monster_zones, opponent.get("monster_zones", []), true)
	_update_field_group(opponent_spelltrap_zones, opponent.get("spell_trap_zones", []), true)

# ===========================================================================
# Cập nhật bài tay
# ===========================================================================
func _update_player_hand(hand):
	for btn in player_hand_container.get_children():
		btn.queue_free()
	for card_id in hand:
		var card = CardDatabase.get(card_id)
		var btn = Button.new()
		btn.text = card.get("name", card_id)
		btn.size_flags_horizontal = 2
		btn.connect("pressed", self, "_on_hand_card_pressed", [card_id])
		btn.disabled = game_state["turn"] != player_id
		player_hand_container.add_child(btn)

# ===========================================================================
# Cập nhật ô sân
# ===========================================================================
func _update_field_group(container, zones, is_opponent):
	for btn in container.get_children():
		btn.queue_free()
	for i in range(5):
		var slot = Button.new()
		slot.size_flags_horizontal = 2
		slot.connect("pressed", self, "_on_field_clicked", [i, is_opponent])
		if zones[i]:
			var card = CardDatabase.get(zones[i]["card_id"])
			var name = card.get("name", zones[i]["card_id"])
			var pos = zones[i].get("position", "unknown")
			slot.text = "%s\n%s" % [name if not is_opponent else "(Ẩn)", pos.replace("_", " ")]
		else:
			slot.text = "[Trống]"
		slot.disabled = game_state["turn"] != player_id or is_opponent
		container.add_child(slot)

# ===========================================================================
# Xử lý tương tác
# ===========================================================================
func _on_hand_card_pressed(card_id):
	var actions = duel.get_available_actions(room_id, player_id)
	for action in actions.details:
		if action.payload.card_id == card_id and action.type in ["PLAY_MONSTER", "SET_MONSTER"]:
			_submit_action(action.type, action.payload)
			return

func _on_field_clicked(zone_idx, is_opponent):
	if is_opponent or game_state["turn"] != player_id:
		return
	var actions = duel.get_available_actions(room_id, player_id)
	for action in actions.details:
		if action.type == "CHANGE_POSITION" and action.payload.zone == zone_idx:
			_submit_action("CHANGE_POSITION", action.payload)
			return
		if action.type == "ACTIVATE_EFFECT" and action.payload.get("zone_type") == ("monster" if not is_opponent else "spell_trap"):
			_submit_action("ACTIVATE_EFFECT", action.payload)
			return

func _on_EndTurnButton_pressed():
	_submit_action("END_TURN", {})

func _submit_action(type, payload):
	var result = duel.submit_action(room_id, {
		"player_id": player_id,
		"type": type,
		"payload": payload
	})
	if result.success:
		for event in result.events:
			_append_event(event)

# ===========================================================================
# Hiển thị sự kiện
# ===========================================================================
func _append_event(event):
	var msg = ""
	var who
	match event.type:
		"DRAW_CARD":
			who = "Bạn" if event.player == player_id else "Đối thủ"
			msg = "[b]%s[/b] rút bài." % who
		"SUMMON":
			who = "Bạn" if event.player == player_id else "Đối thủ"
			name = CardDatabase.get(event.card_id).get("name", event.card_id)
			msg = "[b]%s[/b] triệu hồi [color=blue]%s[/color]!" % [who, name]
		"SET_MONSTER", "SET_SPELL", "SET_TRAP":
			who = "Bạn" if event.player == player_id else "Đối thủ"
			name = CardDatabase.get(event.card_id).get("name", event.card_id)
			msg = "[b]%s[/b] đặt [color=purple]%s[/color]." % [who, name]
		"DECLARE_ATTACK":
			who = "Bạn" if event.player == player_id else "Đối thủ"
			msg = "[b]%s[/b] tuyên bố tấn công!" % who
		"DIRECT_ATTACK":
			msg = "→ Tấn công trực tiếp! [color=red]%d[/color] sát thương." % event.damage
		"WIN":
			var winner = "Bạn" if event.winner == player_id else "Đối thủ"
			msg = "[size=18][b][color=gold]🏆 %s THẮNG![/color][/b][/size]" % winner
		_:
			return
	action_log.append_bbcode("\n" + msg)

# ===========================================================================
# Hiển thị màn hình chiến thắng
# ===========================================================================
func _show_victory_screen(winner, reason):
	# Dừng mọi tương tác
	end_turn_button.visible = false
	for btn in player_hand_container.get_children():
		btn.disabled = true
	for btn in player_monster_zones.get_children():
		btn.disabled = true
	for btn in player_spelltrap_zones.get_children():
		btn.disabled = true

	# Cập nhật nhãn
	phase_label.text = "KẾT THÚC"
	turn_label.text = "Người thắng: %s" % ("Bạn" if winner == player_id else "Đối thủ")

	# Xóa log cũ, hiển thị kết quả
	action_log.clear()
	action_log.add_color_override("default_color", Color(1, 0.9, 0))  # vàng nhạt
	action_log.append_bbcode(
		"[center][size=28][b]🏆 %s THẮNG![/b][/size]\n[size=16](%s)[/size][/center]" % [
			"Bạn" if winner == player_id else "Đối thủ",
			reason
		]
	)

# ===========================================================================
# Hỗ trợ
# ===========================================================================
func _get_opponent_id():
	for pid in game_state["players"]:
		if pid != player_id:
			return pid
	return null

# ===========================================================================
# Dọn dẹp
# ===========================================================================
func _exit_tree():
	timer.stop()
