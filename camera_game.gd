extends Control

@onready var camera_2d: Camera2D = $"../Camera2D"

func _process(delta: float) -> void:
	if get_window().get_node_or_null("Player") != null:
		camera_2d.player = get_window().get_node("Player")
	else:
		camera_2d.player = null
