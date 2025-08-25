extends Panel

onready var card_image = $VBoxContainer/CardImage
onready var lbl_name = $VBoxContainer/LabelName
onready var lbl_stats = $VBoxContainer/LabelStats
onready var desc = $VBoxContainer/RichTextDescription

func show_card(card: Dictionary):
	if card.has("name"):
		lbl_name.text = card.name
	if card.has("atk") and card.has("def"):
		lbl_stats.text = "ATK %d / DEF %d" % [card.atk, card.def]
	if card.has("desc"):
		desc.text = card.desc
	# card["texture"] should be Texture resource if available
	if card.has("texture"):
		card_image.texture = card.texture
