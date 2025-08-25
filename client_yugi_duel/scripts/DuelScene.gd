extends Control

onready var lbl_phase = $CenterBoard/LabelCurrent
onready var log_panel = $CenterBoard/LogPanel
onready var btn_end_turn = $CenterBoard/ButtonEndTurn
onready var hand_container = $Hand

func _ready():
	GameClientController.connect("game_state_updated", self, "_on_state")
	GameClientController.connect("game_event_received", self, "_on_events")
	GameClientController.connect("phase_changed", self, "_on_phase")
	GameClientController.connect("game_over", self, "_on_game_over")

	btn_end_turn.connect("pressed", self, "_on_end_turn")

func _on_state(state):
	lbl_phase.text = "Phase: %s" % state.get("phase","?")
	log_panel.add_text("\nState update: %s" % str(state))

	var my_id = GameClientController.get_current_player_id()
	if state.has("players") and state.players.has(my_id):
		for c in hand_container.get_children():
			c.queue_free()
		for cid in state.players[my_id].hand:
			var btn = TextureButton.new()
			btn.hint_tooltip = str(cid)
			btn.connect("pressed", self, "_on_play_card", [cid])
			hand_container.add_child(btn)

func _on_events(events):
	for e in events:
		log_panel.add_text("\nEvent: %s" % str(e))

func _on_phase(p):
	lbl_phase.text = "Phase: %s" % p

func _on_end_turn():
	GameClientController.end_turn()

func _on_play_card(cid):
	GameClientController.play_monster(cid, 0)

func _on_game_over(winner, reason):
	log_panel.add_text("\n🏆 Winner: %s | %s" % [winner, reason])
