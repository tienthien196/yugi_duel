# ====================================================================
# DuelAPI.gd - Lớp trung gian quản lý và cung cấp API cho UI
# Autoload Singleton
# ====================================================================

extends Node

# =========================
# Signals cho UI
# =========================
signal duel_started
signal duel_ended(winner_id)

signal phase_changed(new_phase)

signal summon_success(player_id, card_id, zone)
signal summon_failed(player_id, reason)

signal set_success(player_id, card_id, zone)
signal set_failed(player_id, reason)

signal attack_declared(attacker_id, target_id)
signal lp_changed(player_id, new_lp)

# =========================
# Ready
# =========================
func _ready():
	# Kết nối signal từ BattleCore
	BattleCore.connect("card_summoned", self, "_on_card_summoned")
	BattleCore.connect("card_set", self, "_on_card_set")
	BattleCore.connect("attack_declared", self, "_on_attack_declared")
	BattleCore.connect("lp_changed", self, "_on_lp_changed")
	BattleCore.connect("phase_changed", self, "_on_phase_changed")
	BattleCore.connect("duel_ended", self, "_on_duel_ended")

# =========================
# Public API cho UI
# =========================
func start_duel(p1_deck, p2_deck):
	BattleCore.start_duel(p1_deck, p2_deck)
	emit_signal("duel_started")

func summon(player_id, card_id, zone):
	var result = BattleCore.summon(player_id, card_id, zone)
	if typeof(result) == TYPE_DICTIONARY and result.has("success"):
		if result.success:
			emit_signal("summon_success", player_id, card_id, zone)
		else:
			emit_signal("summon_failed", player_id, result.reason)
	else:
		# fallback nếu core vẫn trả về true/false
		if result:
			emit_signal("summon_success", player_id, card_id, zone)
		else:
			emit_signal("summon_failed", player_id, "Summon failed")

func set_monster(player_id, card_id, zone):
	var result = BattleCore.set_monster(player_id, card_id, zone)
	if typeof(result) == TYPE_DICTIONARY and result.has("success"):
		if result.success:
			emit_signal("set_success", player_id, card_id, zone)
		else:
			emit_signal("set_failed", player_id, result.reason)
	else:
		if result:
			emit_signal("set_success", player_id, card_id, zone)
		else:
			emit_signal("set_failed", player_id, "Set failed")

func declare_attack(attacker_id, target_id):
	return BattleCore.declare_attack(attacker_id, target_id)

func end_phase():
	BattleCore.end_phase()

# =========================
# Getter tiện dụng cho UI
# =========================
func get_player_lp(player_id):
	return BattleCore.get_lp(player_id)

func get_player_hand(player_id):
	return BattleCore.get_hand(player_id)

func get_current_phase():
	return BattleCore.get_current_phase()

func get_field_state(player_id):
	return BattleCore.get_field(player_id)

# =========================
# Handlers nhận signal từ Core
# =========================
func _on_card_summoned(player_id, card_id, zone):
	emit_signal("summon_success", player_id, card_id, zone)

func _on_card_set(player_id, card_id, zone):
	emit_signal("set_success", player_id, card_id, zone)

func _on_attack_declared(attacker_id, target_id):
	emit_signal("attack_declared", attacker_id, target_id)

func _on_lp_changed(player_id, new_lp):
	emit_signal("lp_changed", player_id, new_lp)

func _on_phase_changed(new_phase):
	emit_signal("phase_changed", new_phase)

func _on_duel_ended(winner_id):
	emit_signal("duel_ended", winner_id)
