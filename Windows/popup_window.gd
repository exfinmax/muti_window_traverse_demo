extends DefaultWindow

@export var distance: int = 20

var initial_pos: Vector2i
var is_closing: bool = false

func _ready() -> void:
	popup_wm_hint = true
	super._ready()
	
	var mgr = get_tree().get_first_node_in_group("window_manager")
	if mgr and spawner:
		initial_pos = mgr._get_node_screen_origin_os(spawner)
		# 调整initial_pos使其在屏幕内
		var screen_size = DisplayServer.screen_get_size()
		if initial_pos.x < 0:
			initial_pos.x = 0
		elif initial_pos.x + size.x > screen_size.x:
			initial_pos.x = screen_size.x - size.x
		if initial_pos.y < 0:
			initial_pos.y = 0
		elif initial_pos.y + size.y > screen_size.y:
			initial_pos.y = screen_size.y - size.y
		self.position = initial_pos
		var tween = create_tween()
		tween.tween_property(self, "position", initial_pos - Vector2i(0, distance), 0.5).from(initial_pos)

# 覆盖以禁用假标题生成
func _setup_fake_title() -> void:
	pass

# 覆盖以禁用拉伸句柄
func _init_resize_handles() -> void:
	pass
