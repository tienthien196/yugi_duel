# ===========================================================================
# Agent.gd - CẬP NHẬT: Học từ EVENTS và CHAIN (không chỉ state/action)
# ===========================================================================

extends Node

# --- State ---
var current_game_state
var my_player_id
var learning_mode = true

# --- Q-Table (vẫn giữ để chọn hành động chính) ---
var q_table = {}
var learning_rate = 0.1
var discount_factor = 0.9
var exploration_rate = 0.3

# --- Rule-based Response Database (mới) ---
# Khi có event → phản ứng nào hợp lý?
var response_rules = {
	"TRIGGER_EFFECT": {
		"Mirror Force": ["ACTIVATE_EFFECT", "card_id", "Effect Veiler"],
		"Solemn Judgment": ["ACTIVATE_EFFECT", "card_id", "Infinite Emperor"]
	},
	"DAMAGE_STEP": {
		"common": ["ACTIVATE_EFFECT", "card_id", "Book of Moon"]
	}
}

# --- Feature Extraction ---
func _extract_state_key(game_state, player_id):
	var p = game_state["players"][player_id]
	var opp = game_state["players"][_get_opponent_id(game_state, player_id)]
	var my_lr = int(p.life_points / 2000)
	var opp_lr = int(opp.life_points / 2000)
	var my_mc = 0
	for m in p.monster_zones:
		if m: my_mc += 1
	var opp_mc = 0
	for m in opp.monster_zones:
		if m: opp_mc += 1
	return "%d_%d_%d_%d_%s" % [my_lr, opp_lr, my_mc, opp_mc, game_state["phase"]]

func _get_q_value(state_key, action):
	return q_table.get(state_key, {}).get(action, 0.0)

# ===========================================================================
# get_action(game_state, player_id, available_actions)
# Trả về hành động chính (lượt của tôi)
# ===========================================================================
func get_action(game_state, player_id, available_actions):
	my_player_id = player_id
	current_game_state = game_state.duplicate(true)
	
	var state_key = _extract_state_key(game_state, player_id)
	
	# Khám phá hoặc khai thác
	if randf() < exploration_rate:
		return available_actions[randi() % available_actions.size()]
	
	var best_action = "END_TURN"
	var best_value = -1e9
	for action in available_actions:
		var q = _get_q_value(state_key, action)
		if q > best_value:
			best_value = q
			best_action = action
	return best_action

# ===========================================================================
# on_event(game_state, event_list)
# 🆕 Hàm mới: Khi có sự kiện → xem có cần phản ứng không?
# Dùng để học cách "đáp lại hiệu ứng"
# ===========================================================================
func on_event(game_state, events, player_id):
	my_player_id = player_id
	current_game_state = game_state.duplicate(true)
	
	for event in events:
		match event["type"]:
			"TRIGGER_EFFECT":
				return _handle_trigger_effect(game_state, event)
			"CHAIN_STARTED":
				return _handle_chain_started(game_state, event)
			"DAMAGE_STEP":
				return _handle_damage_step(game_state, event)
			"SUMMON":
				return _handle_summon_reaction(game_state, event)
	return null  # Không phản ứng

# --- Xử lý các loại event ---

func _handle_trigger_effect(game_state, event):
	var card_name = CardDatabase.get(event["card_id"]).name
	if response_rules.TRIGGER_EFFECT.has(card_name):
		var rule = response_rules.TRIGGER_EFFECT[card_name]
		if rule[0] == "ACTIVATE_EFFECT":
			var target_card = rule[2]
			if _has_card_in_hand(game_state, my_player_id, target_card):
				return {
					"type": "ACTIVATE_EFFECT",
					"payload": { "card_id": target_card }
				}
	return null

func _handle_summon_reaction(game_state, event):
	# Nếu đối phương triệu hồi quái mạnh → chặn bằng bẫy
	var card_data = CardDatabase.get(event["card_id"])
	if card_data["attack"] >= 2500:
		if _has_card_in_hand(game_state, my_player_id, "MIRROR_FORCE"):
			return {
				"type": "PLAY_TRAP",
				"payload": { "card_id": "MIRROR_FORCE", "to_zone": 0 }
			}
	return null

func _handle_chain_started(game_state, event):
	# Đang trong chain → có thể phản ứng
	return null  # Tạm thời không làm gì

func _handle_damage_step(game_state, event):
	return response_rules.get("DAMAGE_STEP", {}).get("common", null)

# --- Hỗ trợ ---

func _has_card_in_hand(game_state, player_id, card_id):
	return game_state["players"][player_id].hand.has(card_id)

func _get_opponent_id(game_state, player_id):
	for pid in game_state["players"].keys():
		if pid != player_id:
			return pid
	return null

# ===========================================================================
# learn_from_result(old_state, action, result)
# 🆕 Học từ toàn bộ result, không chỉ reward
# ===========================================================================
func learn_from_result(old_state, action, result):
	if not result["success"]:
		return
	
	var new_state = result["game_state"]
	var events = result["events"]
	var state_key = _extract_state_key(old_state, action["player_id"])
	var next_key = _extract_state_key(new_state, action["player_id"])
	
	# Tính reward từ events
	var reward = 0.0
	for event in events:
		match event["type"]:
			"DAMAGE":
				if event["target"] == action["player_id"]:
					reward -= event["amount"] / 100.0
				else:
					reward += event["amount"] / 100.0
			"WIN":
				if event["winner"] == action["player_id"]:
					reward += 10.0
				else:
					reward -= 10.0
			"SUMMON":
				var card = CardDatabase.get(event["card_id"])
				if card and card["attack"] > 2500:
					reward += 0.5
			"DESTROYED":
				if event["player"] == action["player_id"]:
					reward -= 1.0
				else:
					reward += 1.0
	
	# Cập nhật Q-value
	var old_q = _get_q_value(state_key, action["type"])
	var future = 0.0
	if new_state["status"] != "finished":
		for a in ["END_TURN", "PLAY_MONSTER", "ACTIVATE_EFFECT"]:
			future = max(future, _get_q_value(next_key, a))
	var new_q = (1 - learning_rate) * old_q + learning_rate * (reward + discount_factor * future)
	
	if not q_table.has(state_key):
		q_table[state_key] = {}
	q_table[state_key][action["type"]] = new_q
	
	# 🆕 Học từ events để cập nhật response_rules
	_learn_from_events(events, action["player_id"])

func _learn_from_events(events, player_id):
	for event in events:
		if event["type"] == "TRIGGER_EFFECT" and event["card_id"] == "MIRROR_FORCE":
			# Nếu tôi không phản ứng → bị thiệt → nên học dùng Effect Veiler
			if _recently_lost_battle_due_to(event["card_id"]):
				_add_response_rule("TRIGGER_EFFECT", "Mirror Force", [
					"ACTIVATE_EFFECT", "card_id", "EFFECT_VEILER"
				])

func _add_response_rule(category, trigger, action):
	if not response_rules.has(category):
		response_rules[category] = {}
	response_rules[category][trigger] = action

func _recently_lost_battle_due_to(card_id):
	# Có thể lưu log trận thua
	return false  # Tạm thời



