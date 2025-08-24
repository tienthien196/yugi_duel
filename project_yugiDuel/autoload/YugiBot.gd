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
# Trả về: Dictionary {type, player_id, payload}
# ===========================================================================
func _choose_action(state, player_id, actions):
	var phase = state["phase"]
	var player = state["players"][player_id]
	var opponent_id = _get_opponent_id(state)
	var opponent = state["players"][opponent_id]
	
	var action = {"type": "", "player_id": player_id, "payload": {}}
	
	# Xử lý chain trước (nếu có)
	if not state["chain"].empty():
		var trap_action = _choose_trap_action(state, player_id, actions.details)
		if trap_action.type != "":
			return trap_action
	
	# Xử lý theo phase
	if phase == "draw" and "DRAW_CARD" in actions.types:
		return {"type": "DRAW_CARD", "player_id": player_id, "payload": {}}
	
	if phase in ["main1", "main2"]:
		var main_action = _choose_main_phase_action(state, player_id, actions.details)
		if main_action.type != "":
			return main_action
	
	if phase == "battle":
		var attack_action = _choose_attack_action(state, player_id, actions.details)
		if attack_action.type != "":
			return attack_action
	
	# Nếu không có hành động tối ưu, end phase hoặc turn
	if "END_PHASE" in actions.types:
		return {"type": "END_PHASE", "player_id": player_id, "payload": {}}
	if "END_TURN" in actions.types:
		return {"type": "END_TURN", "player_id": player_id, "payload": {}}
	
	return action


# ===========================================================================
# _choose_main_phase_action(state, player_id, action_details)
# Chọn hành động trong main phase (summon, spell, trap)
# ===========================================================================
func _choose_main_phase_action(state, player_id, action_details):
	var player = state["players"][player_id]
	var action = {"type": "", "player_id": player_id, "payload": {}}
	
	# Ưu tiên 1: Activate spell có effect mạnh (Pot of Greed, Monster Reborn, Dark Hole)
	for act in action_details:
		if act.type == "PLAY_SPELL":
			var card_id = act.payload["card_id"]
			var effect = CardDatabase.get(card_id).get("effect", "")
			if effect in ["draw_2", "special_summon_graveyard", "destroy_all_monsters"]:
				return act
	
	# Ưu tiên 2: Summon quái có ATK cao nhất
	var best_monster = null
	var best_atk = -1
	var monster_action = null
	for act in action_details:
		if act.type == "PLAY_MONSTER":
			var card_id = act.payload["card_id"]
			var atk = CardDatabase.get(card_id).get("atk", 0)
			if atk > best_atk:
				best_atk = atk
				best_monster = card_id
				monster_action = act
	if monster_action:
		return monster_action
	
	# Ưu tiên 3: Set trap
	for act in action_details:
		if act.type == "SET_TRAP":
			return act
	
	# Ưu tiên 4: Set spell
	for act in action_details:
		if act.type == "SET_SPELL":
			return act
	
	# Ưu tiên 5: Set monster nếu không summon được
	for act in action_details:
		if act.type == "SET_MONSTER":
			return act
	
	# Ưu tiên 6: Activate effect trên sân
	for act in action_details:
		if act.type == "ACTIVATE_EFFECT":
			var card_id = act.payload["card_id"]
			var effect = CardDatabase.get(card_id).get("effect", "")
			if effect != "":
				return act
	
	return action


# ===========================================================================
# _choose_attack_action(state, player_id, action_details)
# Chọn hành động tấn công (ưu tiên quái yếu nhất của đối thủ)
# ===========================================================================
func _choose_attack_action(state, player_id, action_details):
	var player = state["players"][player_id]
	var opponent_id = _get_opponent_id(state)
	var opponent = state["players"][opponent_id]
	var action = {"type": "", "player_id": player_id, "payload": {}}
	
	# Tìm quái mạnh nhất của mình
	var best_atk = -1
	var best_atk_zone = -1
	for i in range(5):
		if player["monster_zones"][i] and player["monster_zones"][i].position == "face_up_attack" and not player["monster_zones"][i].get("attacked_this_turn", false):
			var atk = CardDatabase.get(player["monster_zones"][i].card_id).get("atk", 0)
			if atk > best_atk:
				best_atk = atk
				best_atk_zone = i
	
	if best_atk_zone == -1:
		return action
	
	# Direct attack nếu đối thủ không có quái
	var has_monster = false
	for zone in opponent["monster_zones"]:
		if zone != null:
			has_monster = true
			break
	if not has_monster:
		for act in action_details:
			if act.type == "DECLARE_ATTACK" and act.payload["atk_zone"] == best_atk_zone and not act.payload.has("target_zone"):
				return act
	
	# Tấn công quái yếu nhất của đối thủ
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
				return act
	
	return action


# ===========================================================================
# _choose_trap_action(state, player_id, action_details)
# Chọn trap để kích hoạt trong chain
# ===========================================================================
func _choose_trap_action(state, player_id, action_details):
	var action = {"type": "", "player_id": player_id, "payload": {}}
	
	if state["chain_trigger"] and state["chain_trigger"].type == "ATTACK_DECLARED":
		for act in action_details:
			if act.type == "ACTIVATE_EFFECT":
				var card_id = act.payload["card_id"]
				var effect = CardDatabase.get(card_id).get("effect", "")
				if effect in ["destroy_all_attackers", "destroy_summoned_monster", "reduce_atk_0"]:
					return act
	
	if state["chain_trigger"] and state["chain_trigger"].type == "SUMMON":
		for act in action_details:
			if act.type == "ACTIVATE_EFFECT" and CardDatabase.get(act.payload["card_id"]).get("effect") == "destroy_summoned_monster":
				return act
	
	return action


# ===========================================================================
# _get_opponent_id(state)
# Lấy ID của đối thủ
# ===========================================================================
func _get_opponent_id(state):
	for pid in state["players"]:
		if pid != state["turn"]:
			return pid
	return null


