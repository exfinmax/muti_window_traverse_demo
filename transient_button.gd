extends Button


@onready var transient_window: Window = %TransientWindow



func _on_pressed() -> void:
	transient_window.popup()
