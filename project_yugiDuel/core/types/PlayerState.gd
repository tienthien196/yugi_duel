# res://types/PlayerState.gd
class_name PlayerState

var life_points: int = 8000
var deck: Array
var hand: Array
var graveyard: Array
var monster_zones: Array  # 5 ô
var spell_trap_zones: Array  # 5 ô
var extra_deck: Array
var field_zone  = null