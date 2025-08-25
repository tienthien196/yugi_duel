extends Control

onready var room_list = $VBoxContainer/RoomList
onready var btn_create = $VBoxContainer/HBoxContainer/ButtonCreate
onready var btn_join   = $VBoxContainer/HBoxContainer/ButtonJoin

var rooms = []

func _ready():
	GameClientController.connect("room_list_received", self, "_on_room_list")
	GameClientController.connect("joined_room", self, "_on_joined_room")
	GameClientController.connect("game_started", self, "_on_game_started")

	btn_create.connect("pressed", self, "_on_create_pressed")
	btn_join.connect("pressed", self, "_on_join_pressed")

	GameClientController.request_room_list()

func _on_room_list(rlist):
	rooms = rlist
	room_list.clear()
	for r in rooms:
		var txt = "%s | host=%s | %s | %d/%d" % [
			r.get("room_id","?"), r.get("host","?"),
			r.get("status","?"), r.get("player_count",0), r.get("max_players",2)
		]
		room_list.add_item(txt)

func _on_create_pressed():
	GameClientController.create_room("pvp_1v1")

func _on_join_pressed():
	var idx = room_list.get_selected_items()
	if idx.size() > 0:
		var rid = rooms[idx[0]].get("room_id","")
		if rid != "":
			GameClientController.join_room(rid)

func _on_joined_room(rid):
	print("👉 Đã join phòng %s" % rid)

func _on_game_started(rid):
	print("⚔️ Trận bắt đầu")
	get_tree().change_scene("res://scenes/DuelScene.tscn")
