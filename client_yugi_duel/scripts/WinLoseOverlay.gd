extends ColorRect

onready var lbl = $Label

func show_result(win: bool):
	lbl.text = win ? "YOU WIN" : "YOU LOSE"
	show()
