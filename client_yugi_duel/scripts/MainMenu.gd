extends Control

onready var btn_login = $MarginContainer/VBoxContainer/ButtonLogin
onready var btn_play  = $MarginContainer/VBoxContainer/ButtonPlay
onready var btn_deck  = $MarginContainer/VBoxContainer/ButtonDeck
onready var btn_settings = $MarginContainer/VBoxContainer/ButtonSettings
onready var lbl_info  = $Label
onready var net = NetworkManager

func _ready():
	# đảm bảo kết nối trướ
	if not net.connected:
		net.connect_to_server("127.0.0.1", 8080)



	Authentication.connect("login_success", self, "_on_login_success")
	Authentication.connect("login_failed", self, "_on_login_failed")
	btn_login.connect("pressed", self, "_on_login_pressed")
	btn_play.connect("pressed", self, "_on_play_pressed")

func _on_login_pressed():
	if not Authentication.is_authenticated:
		Authentication.create_guest()


func _on_play_pressed():
	if Authentication.is_authenticated:
		get_tree().change_scene("res://scenes/Lobby.tscn")
	else:
		print("⚠️ Chưa đăng nhập")

func _on_login_success(pid, is_guest):
	lbl_info.text = "Xin chào %s" % pid

func _on_login_failed(code):
	lbl_info.text = "Login lỗi: %s" % str(code)


func _on_ButtonLogin_pressed():
	pass # Replace with function body.


func _on_ButtonPlay_pressed():
	pass # Replace with function body.


func _on_ButtonDeck_pressed():
	pass # Replace with function body.


func _on_ButtonSettings_pressed():
	pass # Replace with function body.
