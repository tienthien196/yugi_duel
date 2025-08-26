# ===========================================================================
# BattleCore.gd - Full(ish) Yu-Gi-Oh! Battle Core for Godot 3.6
# Autoload Singleton - Pure logic, no UI, no networking
# NOTE:
#   - This is a production-ready *core* with extensive mechanics implemented
#     and clear extension points. Official TCG/OCG has thousands of edge cases;
#     you can register card-specific effects via CardDatabase to reach parity.
#   - Designed to be deterministic & event-driven, bot-friendly.
# ===========================================================================

extends Node

# ------------------------------ GLOBAL STATE -------------------------------

# room_id -> game_state
var active_duels := {}

# Turn phases (primary). Battle sub-steps are handled inside "battle".
const TURN_PHASES := ["draw", "standby", "main1", "battle", "main2", "end"]

# Battle sub-steps used internally for timing windows
const BATTLE_STEPS := ["start_step", "declare_attack", "damage_step_start", "damage_calculation", "damage_step_end", "end_step"]

# Win reasons
const WIN_REASON_LP_ZERO := "lp_zero"
const WIN_REASON_DECK_OUT := "deck_out"
const WIN_REASON_SURRENDER := "surrender"
const WIN_REASON_EXODIA := "exodia"
const WIN_REASON_FORFEIT := "forfeit"

# Error codes
const ERR_ROOM_NOT_FOUND := "ROOM_NOT_FOUND"
const ERR_DUEL_NOT_ACTIVE := "DUEL_NOT_ACTIVE"
const ERR_INVALID_PLAYER := "INVALID_PLAYER"
const ERR_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const ERR_NOT_IN_DRAW_PHASE := "NOT_IN_DRAW_PHASE"
const ERR_NO_DRAW_FIRST_TURN := "NO_DRAW_FIRST_TURN"
const ERR_DECK_EMPTY := "DECK_EMPTY"
const ERR_CARD_NOT_IN_HAND := "CARD_NOT_IN_HAND"
const ERR_ZONE_OCCUPIED := "ZONE_OCCUPIED"
const ERR_NOT_IN_MAIN_PHASE := "NOT_IN_MAIN_PHASE"
const ERR_NOT_MONSTER_CARD := "NOT_MONSTER_CARD"
const ERR_NOT_SPELL_CARD := "NOT_SPELL_CARD"
const ERR_NOT_TRAP_CARD := "NOT_TRAP_CARD"
const ERR_SPELL_ZONE_OCCUPIED := "SPELL_ZONE_OCCUPIED"
const ERR_TRAP_ZONE_OCCUPIED := "TRAP_ZONE_OCCUPIED"
const ERR_INVALID_ZONE := "INVALID_ZONE"
const ERR_CANNOT_CHANGE_POS_THIS_TURN := "CANNOT_CHANGE_POS_THIS_TURN"
const ERR_SAME_POSITION := "SAME_POSITION"
const ERR_CARD_NOT_ON_FIELD := "CARD_NOT_ON_FIELD"
const ERR_NO_EFFECT := "NO_EFFECT"
const ERR_NOT_IN_BATTLE_PHASE := "NOT_IN_BATTLE_PHASE"
const ERR_INVALID_ATTACKER := "INVALID_ATTACKER"
const ERR_NOT_IN_ATTACK_POSITION := "NOT_IN_ATTACK_POSITION"
const ERR_ALREADY_ATTACKED := "ALREADY_ATTACKED"
const ERR_CANNOT_ATTACK_SUMMON_TURN := "CANNOT_ATTACK_SUMMON_TURN"
const ERR_CANNOT_DIRECT_ATTACK := "CANNOT_DIRECT_ATTACK"
const ERR_INVALID_TARGET := "INVALID_TARGET"
const ERR_INVALID_PHASE := "INVALID_PHASE"
const ERR_INVALID_CARD := "INVALID_CARD"
const ERR_SUMMON_LIMIT := "SUMMON_LIMIT"
const ERR_TRIBUTE_INVALID := "TRIBUTE_INVALID"
const ERR_SPELL_SPEED := "SPELL_SPEED_RULE"
const ERR_TIMING := "TIMING_WINDOW"
const ERR_SET_TURN_LIMIT := "SET_TURN_LIMIT"
const ERR_ILLEGAL_ACT := "ILLEGAL_ACTION"
const ERR_REQUIREMENT := "REQUIREMENT_NOT_MET"
const ERR_NO_FREE_ZONE := "NO_FREE_ZONE"

# Spell Speeds
const SPELL_SPEED_1 := 1 # Ignition, Normal Spell, Monster Ignition effects
const SPELL_SPEED_2 := 2 # Quick-Play Spells (if set prev turn), Normal Traps, Continuous Traps
const SPELL_SPEED_3 := 3 # Counter Traps

# Card Types (high-level). CardDatabase should supply concrete fields.
const TYPE_MONSTER := "monster"
const TYPE_SPELL := "spell"
const TYPE_TRAP := "trap"

# Monster sub-types for summoning logic (level/rank/link are provided by CardDatabase)
const MTYPE_EFFECT := "effect"
const MTYPE_NORMAL := "normal"
const MTYPE_RITUAL := "ritual"
const MTYPE_FUSION := "fusion"
const MTYPE_SYNCHRO := "synchro"
const MTYPE_XYZ := "xyz"
const MTYPE_LINK := "link"
const MTYPE_PENDULUM := "pendulum"
const MTYPE_TOKEN := "token"

# Spell/Trap sub-types
const STYPE_NORMAL := "normal"
const STYPE_CONTINUOUS := "continuous"
const STYPE_QUICKPLAY := "quick_play"
const STYPE_EQUIP := "equip"
const STYPE_FIELD := "field"
const STYPE_RITUAL := "ritual"
const STYPE_COUNTER := "counter" # (Traps only)

# Position constants
const POS_FACEUP_ATK := "face_up_attack"
const POS_FACEUP_DEF := "face_up_defense"
const POS_FACEDOWN_DEF := "face_down_defense"

# ------------------------------ PUBLIC API ---------------------------------

# start_duel(player_a_id, player_b_id, deck_a:Array, deck_b:Array, rules:Dictionary) -> room_id or error dict
func start_duel(player_a_id, player_b_id, deck_a, deck_b, rules := {}):
	var room_id:String = "duel_%d_%d" % [OS.get_unix_time(), randi() % 10000]

	# Validate decks
	for card_id in deck_a + deck_b:
		if not CardDatabase.exists(card_id):
			return _error(ERR_INVALID_CARD)
		if card_id in rules.get("forbidden_cards", []):
			return _error("FORBIDDEN_CARD_IN_DECK")

	var deck_a_copy = deck_a.duplicate(true)
	var deck_b_copy = deck_b.duplicate(true)
	_shuffle(deck_a_copy)
	_shuffle(deck_b_copy)

	# Opening hand (TCG default 5; optional rule: first player doesn't draw on first turn)
	var hand_a = _draw_cards(deck_a_copy, rules.get("starting_hand", 5))
	var hand_b = _draw_cards(deck_b_copy, rules.get("starting_hand", 5))

	var first_player = [player_a_id, player_b_id][randi() % 2]
	var start_lp = rules.get("start_lp", 8000)

	var game_state = {
		"room_id": room_id,
		"status": "active",
		"first_player": first_player,
		"turn": first_player,
		"phase": "draw",
		"current_turn_count": 1,
		"is_first_turn": true,
		"battle_step": null,

		"players": {
			player_a_id: _create_player_state(player_a_id, deck_a_copy, hand_a, start_lp),
			player_b_id: _create_player_state(player_b_id, deck_b_copy, hand_b, start_lp)
		},

		# Chain & timing
		"chain": [],                 # Array of chain links (see _push_chain_link)
		"chain_window": null,        # info about current timing window
		"priority": first_player,    # priority holder for activations
		"chain_resolving": false,

		# Rules/Options
		"rules": {
			"start_lp": start_lp,
			"max_hand_size": rules.get("max_hand_size", 7),
			"forbidden_cards": rules.get("forbidden_cards", []),
			"first_player_draws": rules.get("first_player_draws", false), # OCG yes, TCG no
			"normal_summon_per_turn": 1
		},

		# Result
		"winner": null,
		"win_reason": null
	}

	active_duels[room_id] = game_state
	print("✅ BattleCore: Room '%s' created. First player: %s" % [room_id, first_player])
	return room_id


# submit_action(room_id, action: {type, player_id, payload}) -> { success, events, errors, available_actions, game_state }
func submit_action(room_id, action):
	if not active_duels.has(room_id):
		return _error(ERR_ROOM_NOT_FOUND)

	var gs = active_duels[room_id]
	if gs["status"] != "active":
		return _error(ERR_DUEL_NOT_ACTIVE)

	var pid = action.get("player_id", null)
	if pid == null or not gs["players"].has(pid):
		return _error(ERR_INVALID_PLAYER)

	# Enforce turn ownership for non-chain activations (responding is allowed)
	if gs["turn"] != pid and not action["type"]  in ["ACTIVATE_EFFECT", "ACTIVATE_SET_CARD", "CHAIN_PASS"]:
		return _error(ERR_NOT_YOUR_TURN)

	# Dispatch
	var result = _process_action(gs, action)

	# If chain got new link, don't auto advance phases until chain is resolved
	if result["success"] and action["type"] in ["ACTIVATE_EFFECT", "ACTIVATE_SET_CARD"]:
		# Open response window for opponent by giving priority
		gs["priority"] = _get_opponent_id(gs, pid)

	# Resolve chain when both players pass
	if result["success"] and action["type"] == "CHAIN_PASS":
		_try_resolve_chain(gs)

	active_duels[room_id] = gs

	# Win checks
	var win_check = _check_win_condition(gs)
	if win_check.winner != null:
		gs["winner"] = win_check.winner
		gs["win_reason"] = win_check.reason
		gs["status"] = "finished"
		result["events"].append({"type": "WIN", "winner": win_check.winner, "reason": win_check.reason})
	elif result["success"] and gs["chain"].empty():
		_update_phase_if_needed(gs)

	result["available_actions"] = _get_available_actions(gs, pid)
	result["game_state"] = gs.duplicate(true)
	return result


# get_game_state(room_id, player_id) -> redacted state for that player
func get_game_state(room_id, player_id):
	if not active_duels.has(room_id):
		return {}
	var gs = active_duels[room_id].duplicate(true)
	var oid = _get_opponent_id(gs, player_id)
	if gs["players"].has(oid):
		var opp = gs["players"][oid]
		# Hide opponent hand but keep count
		opp["hand_count"] = opp["hand"].size()
		opp["hand"] = []
	return gs


# get_available_actions(room_id, player_id)
func get_available_actions(room_id, player_id):
	if not active_duels.has(room_id):
		return []
	return _get_available_actions(active_duels[room_id], player_id)


# end_duel(room_id, winner, reason="forfeit")
func end_duel(room_id, winner, reason := WIN_REASON_FORFEIT):
	if not active_duels.has(room_id):
		return
	var gs = active_duels[room_id]
	gs["winner"] = winner
	gs["win_reason"] = reason
	gs["status"] = "finished"
	print("🏁 Duel '%s' ended. Winner: %s | Reason: %s" % [room_id, winner, reason])


# ------------------------------ ACTION ROUTER ------------------------------

func _process_action(gs, action):
	var pid = action["player_id"]
	var res = {"success": false, "events": [], "errors": []}

	match action["type"]:
		# Turn/Phase flow
		"DRAW_CARD":
			res = _action_draw_card(gs, pid)
		"END_PHASE":
			res = _action_end_phase(gs, pid)
		"END_TURN":
			res = _action_end_turn(gs, pid)

		# Summon/Set
		"NORMAL_SUMMON":
			res = _action_normal_summon(gs, pid, action["payload"])
		"SET_MONSTER":
			res = _action_set_monster(gs, pid, action["payload"])
		"FLIP_SUMMON":
			res = _action_flip_summon(gs, pid, action["payload"])
		"SPECIAL_SUMMON":
			res = _action_special_summon(gs, pid, action["payload"]) # validated by effect or rule

		# Spell/Trap
		"PLAY_SPELL":
			res = _action_play_spell(gs, pid, action["payload"], false)
		"SET_SPELL":
			res = _action_play_spell(gs, pid, action["payload"], true)
		"SET_TRAP":
			res = _action_set_trap(gs, pid, action["payload"])
		"ACTIVATE_EFFECT":        # From field (face-up monster/spell/trap) or hand if allowed
			res = _action_activate_effect(gs, pid, action["payload"])
		"ACTIVATE_SET_CARD":      # Flip set S/T or QS in opponent turn
			res = _action_activate_set(gs, pid, action["payload"])

		# Battle
		"DECLARE_ATTACK":
			res = _action_declare_attack(gs, pid, action["payload"])
		"CHAIN_PASS":
			res = _action_chain_pass(gs, pid)

		# Position
		"CHANGE_POSITION":
			res = _action_change_position(gs, pid, action["payload"])

		# Concede
		"SURRENDER":
			res = _action_surrender(gs, pid)

		_:
			res["errors"].append("UNKNOWN_ACTION")

	if res["success"]:
		print("✅ Action: %s | Player: %s" % [action["type"], pid])
	else:
		var msg = res["errors"][0] if res["errors"].size() > 0 else "Unknown"
		print("❌ Action failed: %s | Error: %s" % [action["type"], msg])
	return res


# ------------------------------ ACTIONS ------------------------------------

func _action_draw_card(gs, pid):
	var p = gs["players"][pid]
	if gs["phase"] != "draw":
		return _error(ERR_NOT_IN_DRAW_PHASE)
	if gs["is_first_turn"] and pid == gs["first_player"] and not gs["rules"]["first_player_draws"]:
		return _error(ERR_NO_DRAW_FIRST_TURN)
	if p["deck"].empty():
		return _error(ERR_DECK_EMPTY)
	var card = p["deck"].pop_front()
	p["hand"].append(card)
	return {"success": true, "events": [{"type": "DRAW_CARD", "player": pid, "card_id": card}]}


func _action_end_phase(gs, pid):
	if gs["turn"] != pid:
		return _error(ERR_NOT_YOUR_TURN)
	var idx = TURN_PHASES.find(gs["phase"])
	if idx == -1 or idx >= TURN_PHASES.size() - 1:
		return _error(ERR_INVALID_PHASE)
	gs["phase"] = TURN_PHASES[idx + 1]
	var events = [{"type": "PHASE_CHANGED", "new_phase": gs["phase"]}]

	# End Phase effects (hand size, lingering OTK safe)
	if gs["phase"] == "end":
		var p = gs["players"][pid]
		var maxh = gs["rules"]["max_hand_size"]
		if p["hand"].size() > maxh:
			var discard_count = p["hand"].size() - maxh
			for i in range(discard_count):
				var dc = p["hand"].pop_back()
				p["graveyard"].append(dc)
			events.append({"type": "DISCARD_HAND", "player": pid, "count": discard_count})

	return {"success": true, "events": events}


func _action_end_turn(gs, pid):
	if gs["turn"] != pid:
		return _error(ERR_NOT_YOUR_TURN)
	_reset_turn_flags(gs["players"][pid])
	gs["turn"] = _get_opponent_id(gs, pid)
	gs["phase"] = "draw"
	gs["current_turn_count"] += 1
	gs["is_first_turn"] = false
	gs["chain"] = []
	gs["priority"] = gs["turn"]
	gs["battle_step"] = null
	return {"success": true, "events": [{"type": "TURN_CHANGED", "next_player": gs["turn"]}]}


# --- Summon & Set -----------------------------------------------------------

func _action_normal_summon(gs, pid, payload):
	if not gs["phase"]  in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	var p = gs["players"][pid]
	if p["turn_flags"]["normal_summon_used"] >= gs["rules"]["normal_summon_per_turn"]:
		return _error(ERR_SUMMON_LIMIT)

	var card_id = payload.get("card_id", null)
	var to_zone = payload.get("to_zone", -1)
	var tributes:Array = payload.get("tributes", [])
	if card_id == null or not p["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or p["monster_zones"][to_zone] != null:
		return _error(ERR_ZONE_OCCUPIED)

	var cd = CardDatabase.get(card_id)
	if cd.get("type") != TYPE_MONSTER:
		return _error(ERR_NOT_MONSTER_CARD)

	var need_tribute := _calc_tribute_required(cd)
	if tributes.size() != need_tribute:
		return _error(ERR_TRIBUTE_INVALID)
	# Release tributes
	for z in tributes:
		if z < 0 or z >= 5 or p["monster_zones"][z] == null:
			return _error(ERR_TRIBUTE_INVALID)
	for z in tributes:
		var rel = p["monster_zones"][z]
		p["graveyard"].append(rel["card_id"])
		p["monster_zones"][z] = null

	# Summon
	p["hand"].erase(card_id)
	p["monster_zones"][to_zone] = {
		"card_id": card_id,
		"position": POS_FACEUP_ATK,
		"status": "summoned_this_turn",
		"attacked_this_turn": false,
		"position_changed": false
	}
	p["turn_flags"]["normal_summon_used"] += 1
	return {"success": true, "events": [{"type": "NORMAL_SUMMON", "player": pid, "card_id": card_id, "zone": to_zone, "tributes": tributes}]}


func _action_set_monster(gs, pid, payload):
	if not gs["phase"]  in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	var p = gs["players"][pid]
	if p["turn_flags"]["normal_summon_used"] >= gs["rules"]["normal_summon_per_turn"]:
		return _error(ERR_SUMMON_LIMIT)
	var card_id = payload.get("card_id", null)
	var to_zone = payload.get("to_zone", -1)
	var tributes:Array = payload.get("tributes", [])
	if card_id == null or not p["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or p["monster_zones"][to_zone] != null:
		return _error(ERR_ZONE_OCCUPIED)

	var cd = CardDatabase.get(card_id)
	if cd.get("type") != TYPE_MONSTER:
		return _error(ERR_NOT_MONSTER_CARD)

	var need_tribute := _calc_tribute_required(cd)
	if tributes.size() != need_tribute:
		return _error(ERR_TRIBUTE_INVALID)
	for z in tributes:
		if z < 0 or z >= 5 or p["monster_zones"][z] == null:
			return _error(ERR_TRIBUTE_INVALID)
	for z in tributes:
		var rel = p["monster_zones"][z]
		p["graveyard"].append(rel["card_id"])
		p["monster_zones"][z] = null

	p["hand"].erase(card_id)
	p["monster_zones"][to_zone] = {
		"card_id": card_id,
		"position": POS_FACEDOWN_DEF,
		"status": "set_this_turn",
		"attacked_this_turn": false,
		"position_changed": false
	}
	p["turn_flags"]["normal_summon_used"] += 1
	return {"success": true, "events": [{"type": "SET_MONSTER", "player": pid, "card_id": card_id, "zone": to_zone, "tributes": tributes}]}


func _action_flip_summon(gs, pid, payload):
	if not gs["phase"]  in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	var p = gs["players"][pid]
	var zone = payload.get("zone", -1)
	if zone < 0 or zone >= 5 or p["monster_zones"][zone] == null:
		return _error(ERR_INVALID_ZONE)
	var mo = p["monster_zones"][zone]
	if mo["position"] != POS_FACEDOWN_DEF:
		return _error(ERR_ILLEGAL_ACT)
	mo["position"] = POS_FACEUP_ATK
	mo["status"] = "flip_summoned"
	return {"success": true, "events": [{"type": "FLIP_SUMMON", "player": pid, "zone": zone, "card_id": mo["card_id"]}]}


func _action_special_summon(gs, pid, payload):
	# This action should be called by card effects or rule-validated methods.
	# Payload: {card_id?, source: "hand"/"graveyard"/"banished"/"deck"/"extra", to_zone, position?, params?}
	# If card_id is null, effect should have selected it previously and stored in gs["chain_window"].
	if not gs["phase"]  in ["main1", "main2", "battle", "end", "standby", "draw"]:
		return _error(ERR_TIMING)
	var p = gs["players"][pid]
	var to_zone = payload.get("to_zone", -1)
	if to_zone < 0 or to_zone >= 5 or p["monster_zones"][to_zone] != null:
		return _error(ERR_ZONE_OCCUPIED)

	var source = payload.get("source", "hand")
	var card_id = payload.get("card_id", null)
	if card_id == null:
		return _error(ERR_REQUIREMENT)

	var container:Array = []
	match source:
		"hand":
			container = p["hand"]
		"graveyard":
			container = p["graveyard"]
		"banished":
			container = p["banished"]
		"deck":
			container = p["deck"]
		"extra":
			container = p["extra_deck"]
		_:
			return _error(ERR_REQUIREMENT)

	if not container.has(card_id):
		return _error(ERR_REQUIREMENT)

	container.erase(card_id)
	p["monster_zones"][to_zone] = {
		"card_id": card_id,
		"position": payload.get("position", POS_FACEUP_ATK),
		"status": "special_summoned",
		"attacked_this_turn": false,
		"position_changed": false
	}
	return {"success": true, "events": [{"type": "SPECIAL_SUMMON", "player": pid, "card_id": card_id, "zone": to_zone}]}


# --- Spell / Trap -----------------------------------------------------------

func _action_play_spell(gs, pid, payload, is_set):
	if not gs["phase"]  in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	var p = gs["players"][pid]
	var card_id = payload.get("card_id", null)
	var to_zone = payload.get("to_zone", -1)
	if card_id == null or not p["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or p["spell_trap_zones"][to_zone] != null:
		return _error(ERR_SPELL_ZONE_OCCUPIED)

	var cd = CardDatabase.get(card_id)
	if cd.get("type") != TYPE_SPELL:
		return _error(ERR_NOT_SPELL_CARD)

	p["hand"].erase(card_id)
	var st = {
		"card_id": card_id,
		"status": "face_down" if is_set else "face_up",
		"set_turn": gs["current_turn_count"] if is_set else null
	}

	# Field spell handling
	if cd.get("subtype") == STYPE_FIELD:
		# Replace if existing
		if p["field_zone"] != null:
			p["graveyard"].append(p["field_zone"]["card_id"])
		p["field_zone"] = st
	else:
		p["spell_trap_zones"][to_zone] = st

	var etype = "SET_SPELL" if is_set else "PLAY_SPELL"
	return {"success": true, "events": [{"type": etype, "player": pid, "card_id": card_id, "zone": to_zone}]}


func _action_set_trap(gs, pid, payload):
	if not gs["phase"]  in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	var p = gs["players"][pid]
	var card_id = payload.get("card_id", null)
	var to_zone = payload.get("to_zone", -1)
	if card_id == null or not p["hand"].has(card_id):
		return _error(ERR_CARD_NOT_IN_HAND)
	if to_zone < 0 or to_zone >= 5 or p["spell_trap_zones"][to_zone] != null:
		return _error(ERR_TRAP_ZONE_OCCUPIED)

	var cd = CardDatabase.get(card_id)
	if cd.get("type") != TYPE_TRAP:
		return _error(ERR_NOT_TRAP_CARD)

	p["hand"].erase(card_id)
	p["spell_trap_zones"][to_zone] = {
		"card_id": card_id,
		"status": "face_down",
		"set_turn": gs["current_turn_count"]
	}
	return {"success": true, "events": [{"type": "SET_TRAP", "player": pid, "card_id": card_id, "zone": to_zone}]}


# Activation from face-up card or ignition/quick effects on monsters
func _action_activate_effect(gs, pid, payload):
	# Payload: {zone_type: "monster"/"spell_trap"/"hand"/"field", zone_idx?, card_id, effect_id?}
	var zone_type = payload.get("zone_type", "monster")
	var card_id = payload.get("card_id", null)
	var p = gs["players"][pid]
	if card_id == null:
		return _error(ERR_REQUIREMENT)

	var cd = CardDatabase.get(card_id)
	var link = {}

	if zone_type == "monster":
		var idx = payload.get("zone_idx", -1)
		if idx < 0 or idx >= 5 or p["monster_zones"][idx] == null or p["monster_zones"][idx]["card_id"] != card_id:
			return _error(ERR_CARD_NOT_ON_FIELD)
		# Monster ignition effects => speed 1 (your turn, main phases), quick effects => speed 2
		var speed = CardDatabase.get_spell_speed(card_id, payload.get("effect_id", null))
		if speed == SPELL_SPEED_1 and (gs["turn"] != pid or not gs["phase"]  in ["main1", "main2"]):
			return _error(ERR_SPELL_SPEED)
		link = _push_chain_link(gs, pid, card_id, speed, zone_type, idx, payload)
	elif zone_type == "spell_trap":
		# Face-up S/T only
		var idx2 = payload.get("zone_idx", -1)
		if idx2 < 0 or idx2 >= 5 or p["spell_trap_zones"][idx2] == null or p["spell_trap_zones"][idx2]["card_id"] != card_id:
			return _error(ERR_CARD_NOT_ON_FIELD)
		if p["spell_trap_zones"][idx2]["status"] != "face_up":
			return _error(ERR_ILLEGAL_ACT)
		var spd = CardDatabase.get_spell_speed(card_id, payload.get("effect_id", null))
		if spd == SPELL_SPEED_1 and gs["turn"] != pid:
			return _error(ERR_SPELL_SPEED)
		link = _push_chain_link(gs, pid, card_id, spd, zone_type, idx2, payload)
	elif zone_type == "field":
		if p["field_zone"] == null or p["field_zone"]["card_id"] != card_id:
			return _error(ERR_CARD_NOT_ON_FIELD)
		var spd2 = CardDatabase.get_spell_speed(card_id, payload.get("effect_id", null))
		if spd2 == SPELL_SPEED_1 and gs["turn"] != pid:
			return _error(ERR_SPELL_SPEED)
		link = _push_chain_link(gs, pid, card_id, spd2, "field", -1, payload)
	elif zone_type == "hand":
		# Some hand traps / quick-play from hand if allowed by card text (CardDatabase tells timing & speed)
		var hand_speed = CardDatabase.get_spell_speed(card_id, payload.get("effect_id", null))
		if not p["hand"].has(card_id):
			return _error(ERR_CARD_NOT_IN_HAND)
		link = _push_chain_link(gs, pid, card_id, hand_speed, "hand", -1, payload)
	else:
		return _error(ERR_ILLEGAL_ACT)

	gs["priority"] = _get_opponent_id(gs, pid)
	return {"success": true, "events": [{"type": "ACTIVATE_EFFECT", "player": pid, "card_id": card_id, "link": link}]}


# Flip a set S/T (or Quick-Play in opponent turn if set previously)
func _action_activate_set(gs, pid, payload):
	# Payload: {zone_idx, card_id}
	var p = gs["players"][pid]
	var idx = payload.get("zone_idx", -1)
	if idx < 0 or idx >= 5 or p["spell_trap_zones"][idx] == null:
	 return _error(ERR_CARD_NOT_ON_FIELD)
	var st = p["spell_trap_zones"][idx]
	if st["card_id"] != payload.get("card_id", null):
		return _error(ERR_CARD_NOT_ON_FIELD)

	var cd = CardDatabase.get(st["card_id"])
	# Trap cannot be activated the turn it was set; Quick-Play can be activated in opponent turn only if set previous turn
	if cd.get("type") == TYPE_TRAP:
		if st["set_turn"] == gs["current_turn_count"]:
		 return _error(ERR_SET_TURN_LIMIT)
		var spd = CardDatabase.get_spell_speed(st["card_id"], null) # likely 2 or 3
		# Counter Traps are speed 3
		_push_chain_link(gs, pid, st["card_id"], spd, "spell_trap", idx, payload)
	elif cd.get("type") == TYPE_SPELL:
		var subtype = cd.get("subtype")
		if subtype == STYPE_QUICKPLAY:
			if gs["turn"] == pid:
				# Activating a set QS on your own turn is allowed (if set previous turn per TCG? Actually you can activate Quick-Play on your own turn even the turn you set it only if it's from hand. Set QS cannot activate same turn at all)
				if st["set_turn"] == gs["current_turn_count"]:
					return _error(ERR_SET_TURN_LIMIT)
			else:
				# Opponent turn requires set previous turn
				if st["set_turn"] == gs["current_turn_count"]:
					return _error(ERR_SET_TURN_LIMIT)
			_push_chain_link(gs, pid, st["card_id"], SPELL_SPEED_2, "spell_trap", idx, payload)
		else:
			# Normal/Continuous/Equip/Field when set face-down: follow general set-turn restriction (you can normally activate your own set Normal Spell on your turn? In TCG, you cannot activate a Normal Spell the turn it was set; must be set before? Actually Normal Spell cannot be set to activate later by default; you either play it face-up from hand or set it and wait a turn; we'll enforce wait-a-turn.)
			if st["set_turn"] == gs["current_turn_count"]:
				return _error(ERR_SET_TURN_LIMIT)
			var spd2 = 1 if subtype in [STYPE_NORMAL, STYPE_RITUAL] else 2
			_push_chain_link(gs, pid, st["card_id"], spd2, "spell_trap", idx, payload)
	else:
		return _error(ERR_ILLEGAL_ACT)

	st["status"] = "face_up"
	gs["priority"] = _get_opponent_id(gs, pid)
	return {"success": true, "events": [{"type": "ACTIVATE_SET", "player": pid, "zone": idx, "card_id": st["card_id"]}]}


# --- Chain management -------------------------------------------------------

func _push_chain_link(gs, pid, card_id, spell_speed, zone_type, zone_idx, payload):
	# Validate spell speed responses: if chain is non-empty, your speed must be >= last link's speed unless timing allows (officially any speed can chain if its own speed allows; only speed 3 can respond to Counter Trap? In TCG, Counter Trap (speed 3) can only be responded by speed 3.)
	if gs["chain"].size() > 0:
		var last = gs["chain"][gs["chain"].size()-1]
		if last["speed"] == SPELL_SPEED_3 and spell_speed < SPELL_SPEED_3:
			return _error(ERR_SPELL_SPEED)
	# Ask CardDatabase/EffectSystem whether timing/cost/targets are legal
	if not EffectSystem.can_activate(gs, pid, card_id, payload):
		return _error(ERR_TIMING)

	var costs_ok = EffectSystem.pay_costs(gs, pid, card_id, payload)
	if not costs_ok:
		return _error(ERR_REQUIREMENT)

	var targets = EffectSystem.select_targets(gs, pid, card_id, payload)
	var link = {
		"player_id": pid,
		"card_id": card_id,
		"speed": spell_speed,
		"zone_type": zone_type,
		"zone_idx": zone_idx,
		"payload": payload,
		"targets": targets
	}
	gs["chain"].append(link)
	return link


func _action_chain_pass(gs, pid):
	# Only the current priority player can pass to potentially start resolution
	if gs["priority"] != pid:
		return _error(ERR_ILLEGAL_ACT)
	gs["priority"] = _get_opponent_id(gs, pid)
	return {"success": true, "events": [{"type": "CHAIN_PASS", "player": pid}]}


func _try_resolve_chain(gs):
	# Chain resolves when both players pass consecutively and chain is not empty
	# We'll detect by having priority return to the original holder without new links
	if gs["chain"].empty():
		return
	# Simple rule: if priority switched to original activator again, resolve. For single-thread usage, call resolve immediately when someone passes and the other also passes without adding link.
	# Here we'll just resolve immediately when CHAIN_PASS is called by second player in a row (priority cycles); this function is called right after CHAIN_PASS.
	_resolve_chain(gs)


func _resolve_chain(gs):
	if gs["chain"].empty():
		return
	gs["chain_resolving"] = true
	var events = []
	# LIFO
	for i in range(gs["chain"].size()-1, -1, -1):
		var link = gs["chain"][i]
		var pid = link["player_id"]
		var oid = _get_opponent_id(gs, pid)
		var pres = EffectSystem.resolve(gs, link)
		events += pres.get("events", [])
		if not pres.get("success", true):
			events.append({"type": "EFFECT_FAILED", "card_id": link["card_id"], "player": pid})
		# Send non-continuous S/T to GY after resolve
		var cd = CardDatabase.get(link["card_id"])
		if link["zone_type"] in ["spell_trap", "field", "hand"] and cd.get("type") in [TYPE_SPELL, TYPE_TRAP]:
			var subtype = cd.get("subtype", STYPE_NORMAL)
			if not subtype  in [STYPE_CONTINUOUS, STYPE_EQUIP, STYPE_FIELD]:
				var p = gs["players"][pid]
				if link["zone_type"] == "spell_trap" and link["zone_idx"] >= 0:
					if p["spell_trap_zones"][link["zone_idx"]] != null and p["spell_trap_zones"][link["zone_idx"]]["card_id"] == link["card_id"]:
						p["spell_trap_zones"][link["zone_idx"]] = null
						p["graveyard"].append(link["card_id"])
				elif link["zone_type"] == "field":
					if p["field_zone"] != null and p["field_zone"]["card_id"] == link["card_id"]:
						p["graveyard"].append(link["card_id"])
						p["field_zone"] = null
				elif link["zone_type"] == "hand":
					# If the card was activated from hand (e.g., hand trap spell/trap), CardDatabase can mark it as "reveal_only". If it became on-field, it will be handled elsewhere.
					if p["hand"].has(link["card_id"]):
						p["hand"].erase(link["card_id"])
						p["graveyard"].append(link["card_id"])
	# Clear chain
	gs["chain"] = []
	gs["chain_resolving"] = false
	# After chain, timing windows like "after resolving" can open; here we just emit events for consumer.
	# No direct return to caller; submit_action already appended available actions.


# --- Battle -----------------------------------------------------------------

func _action_declare_attack(gs, pid, payload):
	if gs["phase"] != "battle":
		return _error(ERR_NOT_IN_BATTLE_PHASE)
	var p = gs["players"][pid]
	var oid = _get_opponent_id(gs, pid)
	var o = gs["players"][oid]
	var atk_zone = payload.get("atk_zone", -1)
	var target_zone = payload.get("target_zone", -1)

	if atk_zone < 0 or atk_zone >= 5 or p["monster_zones"][atk_zone] == null:
		return _error(ERR_INVALID_ATTACKER)
	var attacker = p["monster_zones"][atk_zone]
	if attacker["position"] != POS_FACEUP_ATK:
		return _error(ERR_NOT_IN_ATTACK_POSITION)
	if attacker.get("attacked_this_turn", false):
		return _error(ERR_ALREADY_ATTACKED)
	if attacker.get("status") == "summoned_this_turn" or attacker.get("status") == "special_summoned":
		# Many cards that are Special Summoned can still attack; default: can attack. We'll only block if effect set "cannot_attack_this_turn" flag
		if attacker.get("cannot_attack_this_turn", false):
			return _error(ERR_CANNOT_ATTACK_SUMMON_TURN)

	var events = []
	# Open attack declaration timing window
	gs["battle_step"] = "declare_attack"

	# Determine if direct attack
	var has_monster = false
	for z in o["monster_zones"]:
		if z != null:
			has_monster = true
			break

	if target_zone == -1:
		if has_monster:
			return _error(ERR_CANNOT_DIRECT_ATTACK)
		# Direct
		var atk_val = _calculate_current_atk(gs, pid, atk_zone)
		o["life_points"] = max(0, o["life_points"] - atk_val)
		attacker["attacked_this_turn"] = true
		events.append({"type": "DIRECT_ATTACK", "attacker": attacker["card_id"], "damage": atk_val, "defender": oid})
	else:
		if target_zone < 0 or target_zone >= 5 or o["monster_zones"][target_zone] == null:
			return _error(ERR_INVALID_TARGET)
		var target = o["monster_zones"][target_zone]
		var target_pos = target["position"]
		var is_def = target_pos.find("defense") != -1
		# Flip if face-down
		if target_pos == POS_FACEDOWN_DEF:
			target["position"] = POS_FACEUP_DEF
			events.append({"type": "FLIP", "card_id": target["card_id"], "player": oid})

		# Damage calculation timing (window for counters/boosts handled by chain in consumer side)
		var atk_val2 = _calculate_current_atk(gs, pid, atk_zone)
		var def_val = _calculate_current_def_or_atk(gs, oid, target_zone, is_def)

		if atk_val2 > def_val:
			var damage = atk_val2 - def_val
			if is_def:
				damage = 0
			else:
				o["life_points"] = max(0, o["life_points"] - damage)
			o["graveyard"].append(target["card_id"])
			o["monster_zones"][target_zone] = null
			events.append({"type": "BATTLE_DESTROY", "winner": attacker["card_id"], "loser": target["card_id"], "damage": damage})
		elif atk_val2 == def_val:
			# Both destroyed if target was ATK; if DEF, neither destroyed
			if not is_def:
				p["graveyard"].append(attacker["card_id"])
				o["graveyard"].append(target["card_id"])
				p["monster_zones"][atk_zone] = null
				o["monster_zones"][target_zone] = null
				events.append({"type": "BATTLE_TIE_DESTROY_BOTH"})
			else:
				events.append({"type": "BATTLE_TIE_NO_DESTROY"})
		else:
			var damage2 = def_val - atk_val2
			p["life_points"] = max(0, p["life_points"] - damage2) if not is_def else p["life_points"]
			if not is_def:
				p["graveyard"].append(attacker["card_id"])
				p["monster_zones"][atk_zone] = null
			events.append({"type": "BATTLE_LOSE", "loser": attacker["card_id"], "damage_to_self": damage2 if not is_def else 0})
		attacker["attacked_this_turn"] = true

	return {"success": true, "events": events}


func _calculate_current_atk(gs, pid, zone_idx):
	var p = gs["players"][pid]
	var mo = p["monster_zones"][zone_idx]
	if mo == null:
		return 0
	var cd = CardDatabase.get(mo["card_id"])
	var base_atk = cd.get("atk", 0)
	var mod = mo.get("atk_modifier", null)
	if typeof(mod) == TYPE_NIL:
		return base_atk
	if typeof(mod) == TYPE_INT or typeof(mod) == TYPE_REAL:
		return max(0, base_atk + int(mod))
	if typeof(mod) == TYPE_DICTIONARY:
		var add = mod.get("add", 0)
		var setv = mod.get("set", null)
		return int(setv) if setv != null else max(0, base_atk + int(add))
	return base_atk


func _calculate_current_def_or_atk(gs, pid, zone_idx, is_def):
	var p = gs["players"][pid]
	var mo = p["monster_zones"][zone_idx]
	if mo == null:
		return 0
	var cd = CardDatabase.get(mo["card_id"])
	if is_def:
		var base_def = cd.get("def", 0)
		# TODO: defense modifiers (similar to atk_modifier)
		return base_def
	else:
		return _calculate_current_atk(gs, pid, zone_idx)


# --- Position change --------------------------------------------------------

func _action_change_position(gs, pid, payload):
	if not gs["phase"]  in ["main1", "main2"]:
		return _error(ERR_NOT_IN_MAIN_PHASE)
	var p = gs["players"][pid]
	var zone_idx = payload.get("zone", -1)
	var to_pos = payload.get("to_position", POS_FACEUP_DEF)
	if zone_idx < 0 or zone_idx >= 5 or p["monster_zones"][zone_idx] == null:
		return _error(ERR_INVALID_ZONE)
	var mo = p["monster_zones"][zone_idx]

	if mo.get("status") in ["summoned_this_turn", "set_this_turn", "special_summoned"]:
		return _error(ERR_CANNOT_CHANGE_POS_THIS_TURN)
	if mo.get("position_changed", false):
		return _error(ERR_CANNOT_CHANGE_POS_THIS_TURN)
	if mo["position"] == to_pos:
		return _error(ERR_SAME_POSITION)
	if not to_pos  in [POS_FACEUP_ATK, POS_FACEUP_DEF, POS_FACEDOWN_DEF]:
		return _error("INVALID_POSITION")

	# Can't turn face-down if it has been flipped face-up this turn (simplified)
	if to_pos == POS_FACEDOWN_DEF and mo.get("status") == "flip_summoned":
		return _error(ERR_ILLEGAL_ACT)

	mo["position"] = to_pos
	mo["position_changed"] = true
	var ev = {"success": true, "events": [{"type": "CHANGE_POSITION", "player": pid, "zone": zone_idx, "to": to_pos}]}
	# If flipped from face-down to face-up DEF during main phase via manual change -> it's a Flip Summon per rules; we keep it simple: use explicit FLIP_SUMMON action for clarity.
	return ev


# --- Surrender --------------------------------------------------------------

func _action_surrender(gs, pid):
	var oid = _get_opponent_id(gs, pid)
	gs["winner"] = oid
	gs["win_reason"] = WIN_REASON_SURRENDER
	gs["status"] = "finished"
	return {"success": true, "events": [{"type": "WIN", "winner": oid, "reason": WIN_REASON_SURRENDER}]}


# ------------------------------ SUPPORT ------------------------------------

func _create_player_state(player_id, deck, hand, lp):
	return {
		"player_id": player_id,
		"life_points": lp,
		"deck": deck,
		"hand": hand,
		"graveyard": [],
		"banished": [],
		"extra_deck": [],
		"monster_zones": [null, null, null, null, null],
		"spell_trap_zones": [null, null, null, null, null],
		"field_zone": null,
		"pendulum_zones": [null, null],
		"turn_flags": {
			"normal_summon_used": 0
		}
	}


func _calc_tribute_required(cd:Dictionary) -> int:
	# Tribute rules for Level monsters; Rank/Link usually not tribute-summoned
	if cd.get("type") != TYPE_MONSTER:
		return 0
	# Tokens cannot exist in hand; ignore
	var lvl = cd.get("level", 4)
	if lvl <= 4:
		return 0
	if lvl >= 5 and lvl <= 6:
		return 1
	return 2 # 7+


func _shuffle(arr:Array) -> Array:
	var n = arr.size()
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr


func _draw_cards(deck:Array, count:int) -> Array:
	var out := []
	for i in range(min(count, deck.size())):
		out.append(deck.pop_front())
	return out


func _can_activate_effect_out_of_turn(gs, action) -> bool:
	if not action["type"]  in ["ACTIVATE_EFFECT", "ACTIVATE_SET_CARD"]:
		return false
	var card_id = action["payload"]["card_id"]
	return CardDatabase.can_activate_out_of_turn(card_id, action.get("payload", {}))


func _get_opponent_id(gs, pid):
	for k in gs["players"].keys():
		if k != pid:
			return k
	return null


func _update_phase_if_needed(gs):
	if gs["phase"] == "draw" and gs["chain"].empty():
		var pid = gs["turn"]
		var p = gs["players"][pid]
		if not (gs["is_first_turn"] and pid == gs["first_player"] and not gs["rules"]["first_player_draws"]):
			if not p["deck"].empty():
				var c = p["deck"].pop_front()
				p["hand"].append(c)
				print("Auto draw: %s" % str(c))
		gs["phase"] = "standby"


func _get_available_actions(gs, pid):
	var actions := []
	var details := []
	var p = gs["players"][pid]
	var oid = _get_opponent_id(gs, pid)
	var phase = gs["phase"]

	# Base always available (turn owner)
	if gs["turn"] == pid and not gs["chain_resolving"]:
		details += [{"type": "END_PHASE"}, {"type": "END_TURN"}, {"type": "SURRENDER"}]

	# Draw
	if phase == "draw" and gs["turn"] == pid:
		if not (gs["is_first_turn"] and pid == gs["first_player"] and not gs["rules"]["first_player_draws"]):
			details.append({"type": "DRAW_CARD"})

	# Main actions
	if phase in ["main1", "main2"] and gs["turn"] == pid:
		# Monster play options
		for cid in p["hand"]:
			var cd = CardDatabase.get(cid)
			var ctype = cd.get("type", "")
			for i in range(5):
				if ctype == TYPE_MONSTER and p["monster_zones"][i] == null:
					# Normal summon or set (consider tribute requirements)
					details.append({"type": "NORMAL_SUMMON", "payload": {"card_id": cid, "to_zone": i, "tributes": []}})
					details.append({"type": "SET_MONSTER", "payload": {"card_id": cid, "to_zone": i, "tributes": []}})
				elif ctype == TYPE_SPELL and p["spell_trap_zones"][i] == null:
					details.append({"type": "PLAY_SPELL", "payload": {"card_id": cid, "to_zone": i}})
					details.append({"type": "SET_SPELL", "payload": {"card_id": cid, "to_zone": i}})
				elif ctype == TYPE_TRAP and p["spell_trap_zones"][i] == null:
					details.append({"type": "SET_TRAP", "payload": {"card_id": cid, "to_zone": i}})

		# Position change & effect activations
		for i in range(5):
			if p["monster_zones"][i] != null and not p["monster_zones"][i].get("status")  in ["summoned_this_turn", "set_this_turn", "special_summoned"] and not p["monster_zones"][i].get("position_changed", false):
				for pos in [POS_FACEUP_ATK, POS_FACEUP_DEF, POS_FACEDOWN_DEF]:
					if pos != p["monster_zones"][i]["position"]:
						details.append({"type": "CHANGE_POSITION", "payload": {"zone": i, "to_position": pos}})
			# On-field activations
			if p["monster_zones"][i] != null and CardDatabase.has_activatable_effect(p["monster_zones"][i]["card_id"]):
				details.append({"type": "ACTIVATE_EFFECT", "payload": {"zone_type": "monster", "zone_idx": i, "card_id": p["monster_zones"][i]["card_id"]}})
			if p["spell_trap_zones"][i] != null:
				var st = p["spell_trap_zones"][i]
				if st["status"] == "face_up" and CardDatabase.has_activatable_effect(st["card_id"]):
					details.append({"type": "ACTIVATE_EFFECT", "payload": {"zone_type": "spell_trap", "zone_idx": i, "card_id": st["card_id"]}})
				if st["status"] == "face_down":
					# Activating set this turn may be restricted; still list for UI, validator will reject if illegal
					details.append({"type": "ACTIVATE_SET_CARD", "payload": {"zone_idx": i, "card_id": st["card_id"]}})
		# Field
		if p["field_zone"] != null:
			if p["field_zone"]["status"] == "face_up" and CardDatabase.has_activatable_effect(p["field_zone"]["card_id"]):
				details.append({"type": "ACTIVATE_EFFECT", "payload": {"zone_type": "field", "card_id": p["field_zone"]["card_id"]}})

	# Battle actions
	if phase == "battle" and gs["turn"] == pid:
		for i in range(5):
			if p["monster_zones"][i] != null and p["monster_zones"][i]["position"] == POS_FACEUP_ATK and not p["monster_zones"][i].get("attacked_this_turn", false):
				var has_mon = false
				for j in range(5):
					if gs["players"][oid]["monster_zones"][j] != null:
						has_mon = true
						details.append({"type": "DECLARE_ATTACK", "payload": {"atk_zone": i, "target_zone": j}})
				if not has_mon:
					details.append({"type": "DECLARE_ATTACK", "payload": {"atk_zone": i}})

	# Chain responses for non-turn player
	if not gs["chain"].empty() and gs["turn"] != pid:
		for i in range(5):
			var st2 = p["spell_trap_zones"][i]
			if st2 != null and st2["status"] == "face_down":
				details.append({"type": "ACTIVATE_SET_CARD", "payload": {"zone_idx": i, "card_id": st2["card_id"]}})
		# Hand traps
		for cid in p["hand"]:
			if CardDatabase.can_activate_out_of_turn(cid, {}):
				details.append({"type": "ACTIVATE_EFFECT", "payload": {"zone_type": "hand", "card_id": cid}})
		# Pass
		details.append({"type": "CHAIN_PASS"})

	# Compact types
	for d in details:
		if not d["type"]  in actions:
			actions.append(d["type"])

	return {"types": actions, "details": details}


func _resolve_effect_basic(gs, card_id, p, o, zone_type, zone_idx, payload):
	# Deprecated legacy hook; use EffectSystem.resolve
	return {"success": false, "events": []}


func _check_win_condition(gs):
	for pid in gs["players"].keys():
		var p = gs["players"][pid]
		if p["life_points"] <= 0:
			return {"winner": _get_opponent_id(gs, pid), "reason": WIN_REASON_LP_ZERO}
		# Deck-out: Player fails to draw when required. We check at start of draw (phase transition), but keep here if phase == draw and empty.
		if gs["phase"] == "draw" and p["deck"].empty():
			return {"winner": _get_opponent_id(gs, pid), "reason": WIN_REASON_DECK_OUT}
		# Exodia check
		var exo = ["EXODIA_HEAD", "LEFT_ARM", "RIGHT_ARM", "LEFT_LEG", "RIGHT_LEG"]
		var ok = true
		for e in exo:
			if not p["hand"].has(e):
				ok = false
				break
		if ok:
			return {"winner": pid, "reason": WIN_REASON_EXODIA}
	return {"winner": null, "reason": null}


func _reset_turn_flags(p):
	p["turn_flags"]["normal_summon_used"] = 0
	for i in range(5):
		if p["monster_zones"][i] != null:
			p["monster_zones"][i].erase("status") # loses "summoned_this_turn" etc.
			p["monster_zones"][i]["attacked_this_turn"] = false
			p["monster_zones"][i]["position_changed"] = false
			p["monster_zones"][i].erase("atk_modifier")
		if p["spell_trap_zones"][i] != null:
			# nothing per-turn generic
			pass


func _error(reason):
	return {"success": false, "errors": [reason], "events": [], "available_actions": []}


# ------------------------------ EFFECT SYSTEM ------------------------------
# The EffectSystem delegates timing/cost/target/resolve to CardDatabase-defined
# descriptors so you can reach full TCG parity gradually.

class EffectSystem:
	static func can_activate(gs, pid, card_id, payload) -> bool:
		# Ask CardDatabase for timing window rules (e.g., "on_attack_declared", "ignition_main", etc.)
		return CardDatabase.can_activate(card_id, gs, pid, payload)

	static func pay_costs(gs, pid, card_id, payload) -> bool:
		return CardDatabase.pay_costs(card_id, gs, pid, payload)

	static func select_targets(gs, pid, card_id, payload):
		return CardDatabase.select_targets(card_id, gs, pid, payload)

	static func resolve(gs, link:Dictionary) -> Dictionary:
		return CardDatabase.resolve_effect(link, gs)
