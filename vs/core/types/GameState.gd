# res://types/GameState.gd
class_name GameState

var room_id: String
var turn: String
var phase: String  # "draw", "standby", "main1", "battle", "main2", "end"
var players: Dictionary  # player_id → PlayerState
var chain: Array = []    # Danh sách hiệu ứng đang xử lý
var status: String = "active"
================================================================================

