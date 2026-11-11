## Keep the real play-route decision logic; suppress scene setup, rendering and path execution.
extends "res://scenes/main.gd"

var plans := 0
var follows := 0

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

func _replan(_goal: Callable, _every_ms := 600) -> void:
	plans += 1

func _follow() -> bool:
	follows += 1
	return true
