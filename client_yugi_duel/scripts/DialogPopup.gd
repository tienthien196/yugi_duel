extends WindowDialog

signal confirmed
signal cancelled

onready var btn_ok = $VBoxContainer/HBoxContainer/ButtonOK
onready var btn_cancel = $VBoxContainer/HBoxContainer/ButtonCancel
onready var lbl = $VBoxContainer/Label

func _ready():
	btn_ok.connect("pressed", self, "_on_ok")
	btn_cancel.connect("pressed", self, "_on_cancel")

func ask(text: String):
	lbl.text = text
	popup_centered()

func _on_ok():
	emit_signal("confirmed")
	hide()

func _on_cancel():
	emit_signal("cancelled")
	hide()
