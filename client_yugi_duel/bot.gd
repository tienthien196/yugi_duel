# ===========================================================================
# ClientBot.gd - Bot client for testing Yu-Gi-Oh! server in Godot 3.6
# This script connects to the server, handles authentication (if needed),
# creates/joins rooms, and automatically submits random actions to test all possible actions.
# Usage:
# - Attach this script to a Node in a scene.
# - Set 'is_host' to true for the host instance, false for the join instance.
# - Run two Godot instances: one with is_host=true (creates room), one with false (joins room).
# - Assumes server is running on localhost:8080.
# - For testing, assumes no auth token needed or uses a dummy token; adjust as per your AuthManager.
# ===========================================================================

extends Node

export(bool) var is_host = true  # Set to true for host (create room), false for join
export(String) var server_ip = "127.0.0.1"
export(int) var server_port = 8080
export(String) var room_id = ""  # For join mode, set this to the room_id created by host (manually copy from console)

var peer: NetworkedMultiplayerENet
var player_id: String = "bot_" + str(randi() % 10000)  # Dummy player_id
var auth_token: String = "dummy_token"  # Adjust if your AuthManager requires a real token
var current_room_id: String = ""
var game_state = {}  # Store received game_state
var available_actions = []  # Store available_actions

# List of all possible action types from BattleCore for testing
var all_action_types = [
	"DRAW_CARD",
	"PLAY_MONSTER",
	"SET_MONSTER",
	"PLAY_SPELL",
	"SET_SPELL",
	"PLAY_TRAP",
	"SET_TRAP",
	"END_TURN",
	"SURRENDER",
	"CHANGE_POSITION",
	"ACTIVATE_EFFECT",
	"DECLARE_ATTACK",
	"END_PHASE"
]

func _ready():
	peer = NetworkedMultiplayerENet.new()
	var err = peer.create_client(server_ip, server_port)
	if err != OK:
		print("Failed to connect to server: ", err)
		return
	get_tree().network_peer = peer
	get_tree().connect("network_peer_connected", self, "_on_connected_to_server")
	get_tree().connect("network_peer_disconnected", self, "_on_disconnected_from_server")
	get_tree().connect("server_disconnected", self, "_on_server_disconnected")
	print("Connecting to server...")

func _on_connected_to_server(id):
	print("Connected to server: ", id)

func _on_disconnected_from_server():
	print("Disconnected from server")

func _on_server_disconnected():
	print("Server disconnected")

# Remote function called by server
remote func receive_message(message):
	print("Received message: ", message)
	var type = message.get("type", "")
	match type:
		"AUTH_REQUEST":
			# Send AUTH_LOGIN
			send_message_to_server({
				"type": "AUTH_LOGIN",
				"token": auth_token
			})
		"ERROR":
			print("Error: ", message.get("code"), " - ", message.get("message"))
		"ROOM_CREATED":
			current_room_id = message.get("room_id", "")
			print("Room created: ", current_room_id)
			# After create, request game state
			send_message_to_server({
				"type": "GET_STATE",
				"room_id": current_room_id
			})
		"GAME_STARTED":
			print("Game started in room: ", message.get("room_id"))
			# Request initial state
			send_message_to_server({
				"type": "GET_STATE",
				"room_id": message.get("room_id")
			})
		"GAME_STATE":
			game_state = message.get("state", {})
			available_actions = message.get("available_actions", {})
			print("Received game state: ", game_state)
			print("Available actions: ", available_actions)
			# Automatically test actions after receiving state
			_test_random_action()
		"ACTION_RESULT":
			print("Action result: ", message.get("result"))
			# After action, request updated state
			send_message_to_server({
				"type": "GET_STATE",
				"room_id": current_room_id
			})
		"GAME_EVENT":
			print("Game event: ", message.get("events"))
		"CHAIN_TRIGGERED":
			print("Chain triggered: ", message)
			# Optionally respond to chain by activating effect if available
			_test_chain_response()
		"GAME_OVER":
			print("Game over: Winner ", message.get("winner"), " Reason: ", message.get("reason"))
			# Quit or restart test
			get_tree().quit()
		_:
			print("Unhandled message type: ", type)

# Function to send message to server
func send_message_to_server(message: Dictionary):
	rpc_id(1, "receive_message", message)  # Server is peer_id 1

# After connecting and auth, create or join room
func _process(delta):
	if get_tree().network_peer and get_tree().network_peer.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		if current_room_id == "" and Input.is_action_just_pressed("ui_accept"):  # Press Enter to start
			if is_host:
				send_message_to_server({
					"type": "CREATE_ROOM",
					"mode": "pvp_1v1"
				})
			else:
				if room_id != "":
					send_message_to_server({
						"type": "JOIN_ROOM",
						"room_id": room_id
					})
				else:
					print("Set room_id for join mode")

# Function to test a random action from available_actions
func _test_random_action():
	if available_actions.has("details") and available_actions["details"].size() > 0:
		# Pick a random action detail
		var rand_idx = randi() % available_actions["details"].size()
		var action = available_actions["details"][rand_idx]
		print("Testing action: ", action)
		send_message_to_server({
			"type": "SUBMIT_ACTION",
			"room_id": current_room_id,
			"action": action
		})
	elif available_actions.has("types") and available_actions["types"].size() > 0:
		# If no details, pick a random type and generate dummy payload
		var rand_type = all_action_types[randi() % all_action_types.size()]
		var payload = _generate_dummy_payload(rand_type)
		print("Testing dummy action: ", rand_type, " with payload: ", payload)
		send_message_to_server({
			"type": "SUBMIT_ACTION",
			"room_id": current_room_id,
			"action": {
				"type": rand_type,
				"payload": payload
			}
		})
	else:
		print("No available actions, ending turn or phase")
		send_message_to_server({
			"type": "SUBMIT_ACTION",
			"room_id": current_room_id,
			"action": {
				"type": "END_PHASE"
			}
		})

# Generate dummy payload for action types (adjust based on your card IDs and zones)
func _generate_dummy_payload(action_type: String) -> Dictionary:
	match action_type:
		"PLAY_MONSTER", "SET_MONSTER":
			return {
				"card_id": "DARK_MAGICIAN",  # Assume this card exists
				"to_zone": randi() % 5,
				"position": "face_up_attack"
			}
		"PLAY_SPELL", "SET_SPELL", "PLAY_TRAP", "SET_TRAP":
			return {
				"card_id": "POT_OF_GREED",  # Assume spell/trap
				"to_zone": randi() % 5
			}
		"CHANGE_POSITION":
			return {
				"zone": randi() % 5,
				"to_position": "face_up_defense"
			}
		"ACTIVATE_EFFECT":
			return {
				"card_id": "SUIJIN",  # Assume effect card
				"zone_type": "monster"
			}
		"DECLARE_ATTACK":
			return {
				"atk_zone": randi() % 5,
				"target_zone": randi() % 5
			}
		_:
			return {}  # For actions without payload like DRAW_CARD, END_TURN

# Handle chain response (e.g., activate trap/effect)
func _test_chain_response():
	if available_actions.has("details"):
		for act in available_actions["details"]:
			if act["type"] == "ACTIVATE_EFFECT":
				print("Responding to chain with: ", act)
				send_message_to_server({
					"type": "SUBMIT_ACTION",
					"room_id": current_room_id,
					"action": act
				})
				return
	print("No chain response available")
