extends Button

@export var popup_window_scene:PackedScene
@export var distance:int


func _on_pressed() -> void:
	var popup_window = popup_window_scene.instantiate()
	var win_manager :WindowManager= get_tree().get_first_node_in_group("window_manager")
	popup_window.position = win_manager._get_node_screen_origin_os(self)
	
	win_manager.add_managed_window(popup_window)
	
	
