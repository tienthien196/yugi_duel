# ===========================================================================
# YugiBot.gd - Bot chơi Yu-Gi-Oh! thủ công (Godot 3.6)
# Autoload Singleton - Tự động chọn và thực hiện hành động dựa trên heuristic
# Không cần UI, không cần mạng, tích hợp với BattleCore và CardDatabase
# ===========================================================================
extends Node

# ===========================================================================
# play_turn(room_id, player_id)
# Bot thực hiện toàn bộ lượt của player_id trong room_id
# Trả về: { success: bool, action_taken: Dictionary, result: Dictionary }
# ===========================================================================
func play_turn(room_id, player_id):
	var state = BattleCore.get_game_state(room_id, player_id)
	if state.empty():
		return {"success": false, "action_taken": {}, "result": {"errors": ["ROOM_NOT_FOUND"]}}
	if state["status"] != "active" or state["turn"] != player_id:
		return {"success": false, "action_taken": {}, "result": {"errors": ["NOT_YOUR_TURN"]}}
	var actions = BattleCore.get_available_actions(room_id, player_id)
	var action = _choose_action(state, player_id, actions)
	if action["type"] == "":
		return {"success": false, "action_taken": {}, "result": {"errors": ["NO_ACTION_CHOSEN"]}}
	var result = BattleCore.submit_action(room_id, action)
	return {"success": result["success"], "action_taken": action, "result": result}

# ===========================================================================
# _choose_action(state, player_id, actions)
# Chọn hành động tối ưu dựa trên heuristic
# ✅ ĐÃ SỬA: Ưu tiên END_TURN khi ở phase "end"
# ===========================================================================
func _choose_action(state, player_id, actions):
	var phase = state["phase"]
	var action_details = actions.details

	# Xử lý chain trước (nếu có)
	if not state["chain"].empty():
		var trap_action = _choose_trap_action(state, player_id, action_details)
		if trap_action.type != "":
			trap_action["player_id"] = player_id
			return trap_action

	# Xử lý theo phase
	if phase == "draw" and "DRAW_CARD" in actions.types:
		return {"type": "DRAW_CARD", "player_id": player_id, "payload": {}}

	if phase in ["main1", "main2"]:
		var main_action = _choose_main_phase_action(state, player_id, action_details)
		if main_action.type != "":
			main_action["player_id"] = player_id
			return main_action

	if phase == "battle":
		var attack_action = _choose_attack_action(state, player_id, action_details)
		if attack_action.type != "":
			attack_action["player_id"] = player_id
			return attack_action

	# 🟢 Ưu tiên END_TURN nếu đang ở phase "end"
	if phase == "end":
		if "END_TURN" in actions.types:
			return {"type": "END_TURN", "player_id": player_id, "payload": {}}
		elif "END_PHASE" in actions.types:
			return {"type": "END_PHASE", "player_id": player_id, "payload": {}}
		else:
			return {"type": "END_TURN", "player_id": player_id, "payload": {}}

	# Nếu không phải end phase, thì END_PHASE
	if "END_PHASE" in actions.types:
		return {"type": "END_PHASE", "player_id": player_id, "payload": {}}
	if "END_TURN" in actions.types:
		return {"type": "END_TURN", "player_id": player_id, "payload": {}}

	return {"type": "", "player_id": player_id, "payload": {}}

# ===========================================================================
# _choose_main_phase_action(state, player_id, action_details)
# Chọn hành động trong main phase (summon, spell, trap)
# ===========================================================================
func _choose_main_phase_action(state, player_id, action_details):
	# Ưu tiên 1: Activate spell có effect mạnh (Pot of Greed, Monster Reborn, Dark Hole)
	for act in action_details:
		if act.type == "PLAY_SPELL":
			var card_id = act.payload["card_id"]
			var effect = CardDatabase.get(card_id).get("effect", "")
			if effect in ["draw_2", "special_summon_graveyard", "destroy_all_monsters"]:
				var action = act.duplicate()
				action["player_id"] = player_id
				return action

	# Ưu tiên 2: Summon quái có ATK cao nhất
	var best_atk = -1
	var best_action = null
	for act in action_details:
		if act.type == "PLAY_MONSTER":
			var card_id = act.payload["card_id"]
			var atk = CardDatabase.get(card_id).get("atk", 0)
			if atk > best_atk:
				best_atk = atk
				best_action = act
	if best_action:
		var action = best_action.duplicate()
		action["player_id"] = player_id
		return action

	# Ưu tiên 3: Set trap
	for act in action_details:
		if act.type == "SET_TRAP":
			var action = act.duplicate()
			action["player_id"] = player_id
			return action

	# Ưu tiên 4: Set spell
	for act in action_details:
		if act.type == "SET_SPELL":
			var action = act.duplicate()
			action["player_id"] = player_id
			return action

	# Ưu tiên 5: Set monster nếu không summon được
	for act in action_details:
		if act.type == "SET_MONSTER":
			var action = act.duplicate()
			action["player_id"] = player_id
			return action

	# # Ưu tiên 6: Activate effect trên sân
	# for act in action_details:
	# 	if act.type == "ACTIVATE_EFFECT":
	# 		var card_id = act.payload["card_id"]
	# 		var effect = CardDatabase.get(card_id).get("effect", "")
	# 		if effect != "":
	# 			var action = act.duplicate()
	# 			action["player_id"] = player_id
	# 			return action

	return {"type": "", "player_id": player_id, "payload": {}}

# ===========================================================================
# _choose_attack_action(state, player_id, action_details)
# Chọn hành động tấn công (ưu tiên quái yếu nhất của đối thủ)
# ===========================================================================
func _choose_attack_action(state, player_id, action_details):
	var player = state["players"][player_id]
	var opponent_id = _get_opponent_id(state)
	var opponent = state["players"][opponent_id]

	# Tìm quái mạnh nhất của mình chưa tấn công
	var best_atk = -1
	var best_atk_zone = -1
	for i in range(5):
		var monster_obj = player["monster_zones"][i]
		if monster_obj and monster_obj.position == "face_up_attack" and not monster_obj.get("attacked_this_turn", false):
			var atk = CardDatabase.get(monster_obj.card_id).get("atk", 0)
			if atk > best_atk:
				best_atk = atk
				best_atk_zone = i
	if best_atk_zone == -1:
		return {"type": "", "player_id": player_id, "payload": {}}

	# Kiểm tra direct attack
	var has_monster = false
	for zone in opponent["monster_zones"]:
		if zone != null:
			has_monster = true
			break
	if not has_monster:
		for act in action_details:
			if act.type == "DECLARE_ATTACK" and act.payload["atk_zone"] == best_atk_zone and not act.payload.has("target_zone"):
				var action = act.duplicate()
				action["player_id"] = player_id
				return action

	# Tấn công quái yếu nhất
	var weakest_atk = 999999
	var weakest_zone = -1
	for i in range(5):
		if opponent["monster_zones"][i]:
			var atk = CardDatabase.get(opponent["monster_zones"][i].card_id).get("atk", 0)
			if atk < weakest_atk:
				weakest_atk = atk
				weakest_zone = i
	if weakest_zone != -1:
		for act in action_details:
			if act.type == "DECLARE_ATTACK" and act.payload["atk_zone"] == best_atk_zone and act.payload["target_zone"] == weakest_zone:
				var action = act.duplicate()
				action["player_id"] = player_id
				return action

	return {"type": "", "player_id": player_id, "payload": {}}

# ===========================================================================
# _choose_trap_action(state, player_id, action_details)
# Chọn trap để kích hoạt trong chain
# ===========================================================================
func _choose_trap_action(state, player_id, action_details):
	if state["chain_trigger"]:
		var trigger_type = state["chain_trigger"].get("type", "")
		if trigger_type == "ATTACK_DECLARED":
			for act in action_details:
				if act.type == "ACTIVATE_EFFECT":
					var card_id = act.payload["card_id"]
					var effect = CardDatabase.get(card_id).get("effect", "")
					if effect in ["destroy_all_attackers", "destroy_summoned_monster", "reduce_atk_0"]:
						var action = act.duplicate()
						action["player_id"] = player_id
						return action

		elif trigger_type == "SUMMON":
			for act in action_details:
				if act.type == "ACTIVATE_EFFECT":
					var card_id = act.payload["card_id"]
					var effect = CardDatabase.get(card_id).get("effect", "")
					if effect == "destroy_summoned_monster":
						var action = act.duplicate()
						action["player_id"] = player_id
						return action

	return {"type": "", "player_id": player_id, "payload": {}}

# ===========================================================================
# _get_opponent_id(state)
# Lấy ID của đối thủ
# ===========================================================================
func _get_opponent_id(state):
	for pid in state["players"]:
		if pid != state["turn"]:
			return pid
	return null
