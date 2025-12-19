extends Window
class_name DefaultWindow
#
# DefaultWindow（无边框窗口，含假标题/内置拉伸/嵌入锚点）
# - 本脚本负责窗口自身的运动表现与交互（拖拽、拉伸、嵌入/退出、移动边界、倒计时等）。
# - 穿越判定由管理器以“屏幕坐标(OS)”统一完成，本脚本仅在移动/拉伸时通知管理器几何变化。
# - 锚点/嵌入逻辑：仅用于“窗口如何跟随世界/相机”——与穿越判定解耦；
#   嵌入时用锚点世界坐标 +（主相机 or 无相机）映射到窗口屏幕位置；非嵌入时锚点跟随窗口。
# - 鼠标游标：悬停句柄显示系统拉伸形状，拖拽过程中不改变。
#
# 提示：若你启用子窗口内部相机，这里不需要感知；穿越判定的屏幕坐标由 Canvas 变换天然处理。
#
# Called when the node enters the scene tree for the first time.
const FAKE_TITLE_SCENE := preload("uid://crfmn6sp14ivx")

signal anchor_screen_pos_changed(pos: Vector2)

signal request_push_out(win: Window)
signal request_force_exit(win: Window)

@export_group("基础")
@export var fixed_enabled: bool = true
@export var enter_limit: int = 0    ## 达到次数后，在下一次退出时销毁

@export_group("嵌入设置")
@export var inside_time_limit: float = 0.0  ## 在窗口内停留的时间限制（秒），超过则强制退出
@export var max_embed_time: float = 0.0     ## 最大可嵌入时间，超过后不再允许嵌入（秒），0 表示无限
@export var embed_attempts_left: int = -1   ## 嵌入次数上限，-1 表示无限；>0 时每次嵌入减 1，==0 时不可嵌入
@export var embed_lock_time: float = 0.5    ## 最短嵌入持续时间（秒）

@export_group("移动限制")
@export var has_movement_bounds: bool = false
@export var movement_bounds: Rect2 = Rect2()  ## 相对屏幕坐标的限制矩形，position 与 size 分量范围 [0,1]

@export_group("DEBUG")
@export var debug: bool
@export_group("外观与行为")
@export var icon: Texture2D
@export var priority: int = 0
@export var lock_resize: bool = false   # 玩家生成的窗口将置为 true 禁止拉伸
@export var resize_handle_thickness: float = 6.0
@export var min_size_x: int = 100
@export var min_size_y: int = 100

var pinned_to_screen: bool = true
var _pin_locked_pos: Vector2
var _enter_count: int = 0
var _travelers_inside: Array = []
var _inside_time_left: float = 0.0
var _transition_rect: ColorRect
var _title_overlay: ColorRect
var _embed_elapsed_total: float = 0.0
var _embed_locked_out: bool = false
var _last_camera_pos: Vector2 = Vector2.ZERO
var _status_label: Label
var _anchor_world_pos: Vector2 = Vector2.ZERO
var _anchor_node: Node2D = null
var _camera_buffer_left: float = 0.0
var _embed_lock_elapsed: float = 0.0
var _drag_active: bool = false
var _last_valid_pos: Vector2 = Vector2.ZERO
 

const BOUNDS_INSET: float = 10.0
var _fake_title: Control = null
var _title_height: float = 0.0
var _content_offset: float = 0.0
var _title_input_enabled: bool = true
var _resize_handles: Dictionary = {}
var _resize_dragging_dir: String = ""
var _resize_drag_start_mouse: Vector2 = Vector2.ZERO
var _resize_drag_start_pos: Vector2 = Vector2.ZERO
var _resize_drag_start_size: Vector2 = Vector2.ZERO
var _min_size: Vector2i = Vector2i(64, 64)
var _resize_corner_handles: Dictionary = {}
var _title_dragging_active: bool = false
var _title_drag_start_mouse: Vector2 = Vector2.ZERO
var _title_drag_start_pos: Vector2 = Vector2.ZERO

func _get_screen_size() -> Vector2:
	# 使用当前屏幕的物理尺寸，确保相对坐标针对电脑屏幕而非主窗口视口
	var win := get_window()
	var screen_id := win.current_screen if win != null else DisplayServer.get_primary_screen()
	var s := DisplayServer.screen_get_size(screen_id)
	return Vector2(s)


func _ready() -> void:
	# 初始位置为编辑器场景坐标 + 主窗口屏幕位置
	minimize_disabled = true
	maximize_disabled = true
	always_on_top = true
	close_requested.connect(_on_close_requested)
	var viewport := get_tree().root
	var scene_pos := position
	var screen_pos := viewport.position + scene_pos
	position = screen_pos
	_last_valid_pos = Vector2(position)
	# 若启用了移动限制，初始时将窗口夹取到限制矩形内
	_ensure_within_movement_bounds()
	# 默认固定
	pinned_to_screen = fixed_enabled
	_pin_locked_pos = position
	# 设置为无边框窗口
	borderless = true
	min_size = Vector2(min_size_x,min_size_y)
	# 是否允许拉伸
	unresizable = lock_resize
	_last_camera_pos = _get_camera_pos()
	# 立即创建假标题，避免依赖外部 hide/show
	_setup_fake_title()
	_update_fake_title_layout()
	_update_fake_title_state()
	_init_resize_handles()
	_update_resize_handles_layout()
	_inside_time_left = inside_time_limit
	# 可选：某些平台需要可见性稳定化，按照你的建议统一做一次
	_stabilize_visibility_deferred()
	# 轻量状态 UI
	if debug:
		_status_label = Label.new()
		_status_label.text = ""
		_status_label.z_index = 2000
		_status_label.add_theme_color_override("font_color", Color(1,1,1,0.9))
		_status_label.add_theme_font_size_override("font_size", 14)
		_status_label.position = Vector2(8, 8 + _content_offset)
		add_child(_status_label)
	# 监听窗口位置变化信号以在原生拖拽时即时夹取
	if has_signal("position_changed") and not is_connected("position_changed", Callable(self, "_on_window_position_changed")):
		connect("position_changed", Callable(self, "_on_window_position_changed"))
	# 监听尺寸变化以适配假标题
	if has_signal("size_changed") and not is_connected("size_changed", Callable(self, "_on_window_size_changed")):
		connect("size_changed", Callable(self, "_on_window_size_changed"))
	
	# 初始化时创建锚点节点
	_create_anchor_node()

func _create_anchor_node() -> void:
	"""在主场景中创建锚点节点"""
	var wm = get_parent()
	var scene_root := wm.get_parent() if wm != null else get_parent()
	if scene_root == null:
		return
	
	_anchor_node = Node2D.new()
	_anchor_node.name = "%s_anchor" % name
	scene_root.add_child.call_deferred(_anchor_node)
	
	# 初始化锚点位置为窗口的屏幕坐标（顶层对齐）
	_anchor_node.global_position = Vector2(position)
	_anchor_world_pos = Vector2(position)

	# 内置假标题：锚点保持原逻辑，无需额外同步

func _process(delta: float) -> void:
	var cam := _get_camera()
	if cam != null:
		var cam_pos := cam.global_position
		var cam_delta := cam_pos - _last_camera_pos
		_last_camera_pos = cam_pos
		# 锚点逻辑（仅影响窗口视觉/输入表现，与穿越判定解耦）：
		# - 嵌入时：窗口屏幕坐标 = 锚点世界坐标 - 相机世界坐标 + 视口中心
		# - 非嵌入时：锚点世界坐标跟随窗口屏幕坐标
		if _anchor_node != null and is_instance_valid(_anchor_node):
			var viewport_size := Vector2(cam.get_viewport().size)
			if pinned_to_screen:
				# 嵌入：世界坐标 -> 视口坐标（窗口坐标已是屏幕坐标）
				var screen_pos_os := _anchor_node.global_position - cam.global_position + viewport_size / 2.0
				# 若启用了移动限制且屏幕坐标超出限制，夹取并同时回写锚点世界坐标
				if has_movement_bounds:
					var screen_size: Vector2 = _get_screen_size()
					var abs_min: Vector2 = movement_bounds.position * screen_size
					var abs_max: Vector2 = (movement_bounds.position + movement_bounds.size) * screen_size - Vector2(size)
					var clamped_os := Vector2(
						clamp(screen_pos_os.x, abs_min.x, abs_max.x),
						clamp(screen_pos_os.y, abs_min.y, abs_max.y)
					)
					if clamped_os != screen_pos_os:
						# 将夹取后的屏幕坐标反投影到世界坐标，更新锚点
						var new_world := clamped_os + cam.global_position - viewport_size / 2.0
						_anchor_node.global_position = new_world
						_anchor_world_pos = new_world
						screen_pos_os = clamped_os
				position = Vector2i(screen_pos_os)
				_pin_locked_pos = screen_pos_os
				
			# 未嵌入时不在每帧同步锚点，由拖拽逻辑负责更新
	else:
		_last_camera_pos = Vector2.ZERO
		# 无相机：世界坐标 == 视口坐标；OS 屏幕坐标需加上主窗口 OS 原点
		# 注：穿越判定仍基于屏幕坐标，与本处逻辑无关。
		if pinned_to_screen and _anchor_node != null and is_instance_valid(_anchor_node):
			var screen_pos_os_nc := _anchor_node.global_position
			if has_movement_bounds:
				var screen_size: Vector2 = _get_screen_size()
				var abs_min: Vector2 = movement_bounds.position * screen_size
				var abs_max: Vector2 = (movement_bounds.position + movement_bounds.size) * screen_size - Vector2(size)
				var clamped_os_nc := Vector2(
					clamp(screen_pos_os_nc.x, abs_min.x, abs_max.x),
					clamp(screen_pos_os_nc.y, abs_min.y, abs_max.y)
				)
				if clamped_os_nc != screen_pos_os_nc:
					# 回写锚点世界坐标：world = screen
					var new_world_nc := clamped_os_nc
					_anchor_node.global_position = new_world_nc
					_anchor_world_pos = new_world_nc
					screen_pos_os_nc = clamped_os_nc
			position = Vector2i(screen_pos_os_nc)
			_pin_locked_pos = screen_pos_os_nc



	# 不在进程中限制窗口移动或做跳变检测，改为仅由假标题拖拽控制
	_last_valid_pos = Vector2(position)

	# 不在此处进行边界贴近/夹取逻辑，避免窗口移动被强制限制

	# 在窗口内的计时逻辑（多穿越者共享倒计时）
	if inside_time_limit > 0.0 and not _travelers_inside.is_empty():
		_prune_invalid_travelers()
		_inside_time_left -= delta
		if _inside_time_left <= 0.0:
			_inside_time_left = 0.0
			_notify_manager_close()
			return

	# 嵌入总时长限制
	if pinned_to_screen:
		_embed_lock_elapsed += delta
		if max_embed_time > 0.0 and not _embed_locked_out:
			_embed_elapsed_total += delta
			if _embed_elapsed_total >= max_embed_time:
				_embed_locked_out = true
				_toggle_embed(false)

	# 若嵌入状态下窗口超出屏幕则自动退出嵌入（统一按物理屏幕判定）
	if pinned_to_screen and _embed_lock_elapsed >= embed_lock_time:
		if cam != null:
			var viewport_size := Vector2(cam.get_viewport().size)
			var anchor_pos := _anchor_node.global_position if (_anchor_node != null and _anchor_node.is_inside_tree()) else _anchor_world_pos
			var anchor_screen_os := anchor_pos - cam.global_position + viewport_size / 2.0
			var screen_size_os: Vector2 = _get_screen_size()
			var within := anchor_screen_os.x >= 0.0 and anchor_screen_os.y >= 0.0 and anchor_screen_os.x <= screen_size_os.x and anchor_screen_os.y <= screen_size_os.y
			if not within:
				_toggle_embed(false)
		else:
			# 无相机：世界坐标==视口坐标；判断需转为 OS 屏幕坐标
			var screen_size_os: Vector2 = _get_screen_size()
			var anchor_world_nc := _anchor_node.global_position if (_anchor_node != null and _anchor_node.is_inside_tree()) else _anchor_world_pos
			var anchor_screen_os_nc := anchor_world_nc
			var within_nc := anchor_screen_os_nc.x >= 0.0 and anchor_screen_os_nc.y >= 0.0 and anchor_screen_os_nc.x <= screen_size_os.x and anchor_screen_os_nc.y <= screen_size_os.y
			if not within_nc:
				_toggle_embed(false)

	# 相机缓冲倒计时（窗口退出到主窗口后）
	if _camera_buffer_left > 0.0:
		_camera_buffer_left = max(0.0, _camera_buffer_left - delta)

	_update_status_ui()
	_update_fake_title_layout()
	_update_fake_title_state()

func _prune_invalid_travelers() -> void:
	var alive: Array = []
	for t in _travelers_inside:
		if t != null and is_instance_valid(t):
			alive.append(t)
	_travelers_inside = alive

func _unhandled_input(event: InputEvent) -> void:
	# 右键切换嵌入
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		# 有穿越者在窗口内时不允许切换
		if _travelers_inside.is_empty():
			_toggle_embed(not pinned_to_screen)
			get_viewport().set_input_as_handled()
			return

	# 全局鼠标左键松开时，重置标题拖拽状态，避免多次拖拽起点错乱
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
		_title_dragging_active = false
		_drag_active = false

func _push_out_of_safe_rect() -> void:
	var screen_size := _get_screen_size()
	var wm = get_parent()
	var ratio: float = 0.5
	if wm and wm.has_meta("safe_rect_ratio"):
		ratio = wm.get_meta("safe_rect_ratio")
	var safe_size := screen_size * ratio
	var safe_rect := Rect2((screen_size - safe_size) / 2.0, safe_size)
	var win_rect := Rect2(Vector2(position), size)
	# 如果不相交则只夹到屏幕范围即可
	if not win_rect.intersects(safe_rect):
		var clamped := Vector2(
			clamp(position.x, 0.0, max(0.0, screen_size.x - size.x)),
			clamp(position.y, 0.0, max(0.0, screen_size.y - size.y))
		)
		position = Vector2i(clamped)
		return
	# 计算最小推出向量
	var dx_left := (safe_rect.position.x - (win_rect.position.x + win_rect.size.x))
	var dx_right := ((safe_rect.position.x + safe_rect.size.x) - win_rect.position.x)
	var dy_top := (safe_rect.position.y - (win_rect.position.y + win_rect.size.y))
	var dy_bottom := ((safe_rect.position.y + safe_rect.size.y) - win_rect.position.y)
	# 选择绝对值最小的非零位移方向
	var candidates := [abs(dx_left), abs(dx_right), abs(dy_top), abs(dy_bottom)]
	var min_val = candidates[0]
	var idx := 0
	for i in range(1, candidates.size()):
		if candidates[i] < min_val:
			min_val = candidates[i]
			idx = i
	var new_pos := Vector2(position)
	match idx:
		0:
			new_pos.x = position.x + dx_left - BOUNDS_INSET
		1:
			new_pos.x = position.x + dx_right + BOUNDS_INSET
		2:
			new_pos.y = position.y + dy_top - BOUNDS_INSET
		3:
			new_pos.y = position.y + dy_bottom + BOUNDS_INSET
	# 最后夹到屏幕范围，并确保窗口不在边界（留出边距）
	var margin := 10.0  # 离边界的最小距离
	new_pos = Vector2(
		clamp(new_pos.x, margin, max(margin, screen_size.x - size.x - margin)),
		clamp(new_pos.y, margin, max(margin, screen_size.y - size.y - margin))
	)
	position = Vector2i(new_pos)

func _ensure_away_from_screen_edges() -> void:
	# 确保窗口不贴近屏幕边界，如果贴近则往里移动
	var screen_size := _get_screen_size()
	var edge_threshold := 5.0  # 距离边界多少像素算"贴近"
	var move_inset := 20.0     # 往里移动的距离
	var new_pos := Vector2(position)
	var changed := false
	
	# 检查左边界
	if new_pos.x < edge_threshold:
		new_pos.x = move_inset
		changed = true
	# 检查右边界
	if new_pos.x + size.x > screen_size.x - edge_threshold:
		new_pos.x = screen_size.x - size.x - move_inset
		changed = true
	# 检查上边界
	if new_pos.y < edge_threshold:
		new_pos.y = move_inset
		changed = true
	# 检查下边界
	if new_pos.y + size.y > screen_size.y - edge_threshold:
		new_pos.y = screen_size.y - size.y - move_inset
		changed = true
	
	if changed:
		position = Vector2i(new_pos)

# 初始与必要时确保窗口在移动限制矩形内（使用屏幕坐标比例）
func _ensure_within_movement_bounds() -> void:
	if not has_movement_bounds:
		return
	var screen_size: Vector2 = _get_screen_size()
	var abs_min: Vector2 = movement_bounds.position * screen_size
	var abs_max: Vector2 = (movement_bounds.position + movement_bounds.size) * screen_size - Vector2(size)
	var clamped := Vector2(
		clamp(position.x, abs_min.x, abs_max.x),
		clamp(position.y, abs_min.y, abs_max.y)
	)
	if clamped != Vector2(position):
		position = Vector2i(clamped)
		_last_valid_pos = clamped

func _show_transition_effect(is_enter: bool) -> void:
	if _transition_rect == null:
		_transition_rect = ColorRect.new()
		_transition_rect.color = Color(0,0,0,0)
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transition_rect.size = size
		add_child(_transition_rect)
		_transition_rect.z_index = 1000
	# 设置不同状态的颜色
	var target_color :=  Color(0,1,0,0.3) if is_enter else Color(1,0.5,0,0.3)
	_transition_rect.size = size
	# 动画效果
	var tw = create_tween()
	tw.tween_property(_transition_rect, "color", target_color, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_transition_rect, "color", Color(target_color.r, target_color.g, target_color.b, 0.0), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# 由管理器在穿越者进入时调用（兼容旧入口）
func on_traveler_enter(traveler: Node = null) -> void:
	_register_traveler_enter(traveler)

func on_player_enter(traveler: Node = null) -> void:
	_register_traveler_enter(traveler)

# 由管理器在穿越者退出时调用（兼容旧入口）
func on_traveler_exit(traveler: Node = null) -> void:
	_register_traveler_exit(traveler)

func on_player_exit(traveler: Node = null) -> void:
	_register_traveler_exit(traveler)

func _register_traveler_enter(traveler: Node) -> void:
	if traveler != null:
		if not _travelers_inside.has(traveler):
			_travelers_inside.append(traveler)
		# 首个进入时重置共享倒计时
		if _travelers_inside.size() == 1:
			_inside_time_left = inside_time_limit
	_enter_count += 1
	_show_transition_effect(true)

func _register_traveler_exit(traveler: Node) -> void:
	if traveler == null:
		_travelers_inside.clear()
	else:
		_travelers_inside.erase(traveler)
	# 无人时重置倒计时
	if _travelers_inside.is_empty():
		_inside_time_left = inside_time_limit
	_show_transition_effect(false)
	# 若达到进入次数限制，则在退出后销毁
	if enter_limit > 0 and _enter_count >= enter_limit:
		_notify_manager_close()
		return
	# 开始显示相机缓冲倒计时（从管理器读取秒数）
	var wm = get_parent()
	if wm and wm.has_meta("camera_resume_delay"):
		var d = wm.get_meta("camera_resume_delay")
		if typeof(d) == TYPE_FLOAT or typeof(d) == TYPE_INT:
			_camera_buffer_left = float(d)

func _on_close_requested() -> void:
	hide()

# 已移除测试用数字键嵌入逻辑

func _get_camera() -> Camera2D:
	var wm = get_parent()
	if wm and wm.has_meta("camera_ref"):
		var cam = wm.get_meta("camera_ref")
		if cam is Camera2D:
			return cam
	return get_tree().root.find_child("Camera2D", true, false)

func _get_camera_pos() -> Vector2:
	var cam := _get_camera()
	return cam.global_position if cam != null else Vector2.ZERO

func _toggle_embed(target_state: bool) -> void:
	if target_state and _embed_locked_out:
		return
	# 检查次数上限
	if target_state:
		if embed_attempts_left == 0:
			return
		if embed_attempts_left > 0:
			embed_attempts_left -= 1
	pinned_to_screen = target_state
	if pinned_to_screen:
		# 嵌入：将当前窗口屏幕坐标转换为世界坐标设置给锚点
		var cam := _get_camera()
		if _anchor_node != null:
			if cam != null:
				var viewport_size := Vector2(cam.get_viewport().size)
				# world = screen + cam - viewport/2 （Window.position 已是屏幕坐标）
				var world_pos := Vector2(position) + cam.global_position - viewport_size / 2.0
				_anchor_node.global_position = world_pos
				_anchor_world_pos = world_pos
			else:
				# 无相机：world == screen
				var world_pos_nc := Vector2(position)
				_anchor_node.global_position = world_pos_nc
				_anchor_world_pos = world_pos_nc
		_pin_locked_pos = Vector2(position)
		_last_camera_pos = _get_camera_pos()
		_embed_lock_elapsed = 0.0
		_show_transition_effect(true)
		# 嵌入时禁用标题输入但保持可见
		_title_input_enabled = false
		_update_fake_title_state()
	else:
		_show_transition_effect(false)
		# 退出嵌入时：将窗口推到距离安全矩形最近的不相交位置（屏幕中心相对安全矩形）
		_push_out_of_safe_rect()
		# 退出后再检查是否贴近屏幕边界，如果是则往里移动
		_ensure_away_from_screen_edges()
		# 退出嵌入时不删除锚点，锚点会在 _process 中跟随窗口
		_title_input_enabled = true
		_update_fake_title_state()

func _on_window_position_changed() -> void:
	# 原生标题栏拖拽时的位置变化回调
	# 边界处理已移至 _process，这里不再重复处理
	
	# 即时更新锚点（非嵌入时），避免一帧延迟
	if not pinned_to_screen and _anchor_node != null and is_instance_valid(_anchor_node):
		_anchor_node.global_position = Vector2(position)
		_anchor_world_pos = _anchor_node.global_position
		_emit_anchor_signal()
	# 位置变化也属于几何变化，通知管理器做快速重判
	_notify_manager_geometry_changed()

func _on_window_size_changed() -> void:
	_update_fake_title_layout()
	_update_fake_title_state()
	_update_resize_handles_layout()
	_notify_manager_geometry_changed()


func _update_status_ui() -> void:
	if _status_label == null:
		return
	var embed_state := "嵌入" if pinned_to_screen else "未嵌入"
	var time_left := 0.0
	if max_embed_time > 0.0:
		time_left = max(0.0, max_embed_time - _embed_elapsed_total)
	var inside_left := 0.0
	if inside_time_limit > 0.0 and not _travelers_inside.is_empty():
		inside_left = max(0.0, _inside_time_left)
	var attempts := embed_attempts_left
	var attempts_str := "无限" if attempts < 0 else str(attempts)
	var cam_buf := _camera_buffer_left
	_status_label.text = "状态: %s\n嵌入剩余: %.1fs\n内停剩余: %.1fs\n相机缓冲剩余: %.1fs\n已进入: %d\n嵌入次数余: %s" % [embed_state, time_left, inside_left, cam_buf, _enter_count, attempts_str]

# 供管理器判定嵌入状态的接口
func is_window_embedded() -> bool:
	return pinned_to_screen

func _notify_manager_close() -> void:
	var wm = get_parent()
	if wm != null and wm.has_method("_on_window_close"):
		wm._on_window_close(self)


# 供假标题预判本次拖拽是否会命中边界，命中时假标题应阻断后续拖拽直到松开
func will_hit_bounds(delta: Vector2) -> bool:
	if delta.length() <= 0.0:
		return false
	var accelerated_delta := delta * 2.0
	var cam := _get_camera()
	var current_pos := Vector2.ZERO
	var target_pos := Vector2.ZERO
	if pinned_to_screen and _anchor_node != null and is_instance_valid(_anchor_node) and cam != null:
		current_pos = _anchor_node.global_position
		target_pos = current_pos + accelerated_delta
		# 将目标位置投影到屏幕空间再做边界判断
		if has_movement_bounds:
			var viewport_size := Vector2(cam.get_viewport().size)
			var target_screen := target_pos - cam.global_position + viewport_size / 2.0
			var screen_size: Vector2 = _get_screen_size()
			var abs_min: Vector2 = movement_bounds.position * screen_size
			var abs_max: Vector2 = (movement_bounds.position + movement_bounds.size) * screen_size - Vector2(size)
			var unclamped := target_screen
			var clamped := Vector2(
				clamp(unclamped.x, abs_min.x, abs_max.x),
				clamp(unclamped.y, abs_min.y, abs_max.y)
			)
			return clamped != unclamped
		return false
	else:
		current_pos = Vector2(position)
		var unclamped2 := current_pos + accelerated_delta
		if has_movement_bounds:
			var screen_size2: Vector2 = _get_screen_size()
			var abs_min2: Vector2 = movement_bounds.position * screen_size2
			var abs_max2: Vector2 = (movement_bounds.position + movement_bounds.size) * screen_size2 - Vector2(size)
			var clamped2 := Vector2(
				clamp(unclamped2.x, abs_min2.x, abs_max2.x),
				clamp(unclamped2.y, abs_min2.y, abs_max2.y)
			)
			return clamped2 != unclamped2
		return false


func _apply_title_drag(delta: Vector2) -> void:
	# 标题拖动采用“起始位置 + 鼠标增量”，拖拽期间不改变鼠标图标
	var cam := _get_camera()
	var mouse_screen := _get_mouse_screen_pos()
	# 未按下左键则视为结束拖拽
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_title_dragging_active = false
		return
	# 初始化拖拽起点
	if not _title_dragging_active:
		_title_dragging_active = true
		_title_drag_start_mouse = mouse_screen
		if pinned_to_screen and _anchor_node != null and is_instance_valid(_anchor_node) and cam != null:
			_title_drag_start_pos = _anchor_node.global_position
		else:
			_title_drag_start_pos = Vector2(position)
	# 鼠标增量（屏幕空间）
	var mouse_delta := mouse_screen - _title_drag_start_mouse
	# 目标位置：起始位置 + 增量
	var target_pos := _title_drag_start_pos + mouse_delta
	# 钳制：窗口顶点与鼠标在窗口内的 y 差值保持在 [0, _title_height]
	var screen_top := _get_screen_top_left_from_target(target_pos, cam)
	var clamped_top_y = clamp(screen_top.y, mouse_screen.y - _title_height, mouse_screen.y)
	if pinned_to_screen and cam != null:
		var viewport_size := Vector2(cam.get_viewport().size)
				# 回投影：world = screen + cam - viewport/2
		target_pos.y = clamped_top_y + cam.global_position.y - viewport_size.y / 2.0
	else:
		target_pos.y = clamped_top_y
	
	# 如果有边界限制，夹取到边界内
	if has_movement_bounds:
		var screen_size: Vector2 = _get_screen_size()
		var abs_min: Vector2 = movement_bounds.position * screen_size
		var abs_max: Vector2 = (movement_bounds.position + movement_bounds.size) * screen_size - Vector2(size)
		if pinned_to_screen and cam != null:
			# 目标为锚点世界坐标，需先转为 OS 屏幕坐标再夹取
			var viewport_size := Vector2(cam.get_viewport().size)
			var target_os := target_pos - cam.global_position + viewport_size / 2.0
			var clamped_os := Vector2(
				clamp(target_os.x, abs_min.x, abs_max.x),
				clamp(target_os.y, abs_min.y, abs_max.y)
			)
			if clamped_os != target_os:
				# 反投影回世界坐标
				target_pos = clamped_os + cam.global_position - viewport_size / 2.0
		else:
			# 目标为窗口 OS 屏幕坐标，直接夹取
			target_pos = Vector2(
				clamp(target_pos.x, abs_min.x, abs_max.x),
				clamp(target_pos.y, abs_min.y, abs_max.y)
			)
	# 更新锚点与窗口位置
	if pinned_to_screen and _anchor_node != null and is_instance_valid(_anchor_node):
		# 嵌入时：更新锚点世界坐标，窗口位置会在 _process 中同步
		_anchor_node.global_position = target_pos
		_anchor_world_pos = target_pos
	else:
		# 未嵌入时：直接更新窗口屏幕坐标
		position = Vector2i(target_pos)
		_pin_locked_pos = target_pos
		
		# 同步锚点世界坐标
		if _anchor_node != null and is_instance_valid(_anchor_node):
			if cam != null:
				var viewport_size := Vector2(cam.get_viewport().size)
				var world_pos := target_pos + cam.global_position - viewport_size / 2.0
				_anchor_node.global_position = world_pos
				_anchor_world_pos = world_pos
			else:
				# 无相机：world == screen
				_anchor_node.global_position = target_pos
				_anchor_world_pos = target_pos

	# 拖拽过程中窗口几何发生变化，通知管理器做快速重判
	_notify_manager_geometry_changed()

func _get_mouse_screen_pos() -> Vector2:
	# 获取屏幕空间的鼠标位置（DisplayServer 全局坐标）
	return DisplayServer.mouse_get_position()

func _predict_center_screen_after_move(target_pos: Vector2, cam: Camera2D) -> Vector2:
	# 根据目标位置与当前嵌入状态，预测窗口屏幕中心位置
	var screen_pos: Vector2
	if pinned_to_screen and cam != null and _anchor_node != null and is_instance_valid(_anchor_node):
		# target_pos 是锚点世界坐标，转换为 OS 屏幕坐标
		var viewport_size := Vector2(cam.get_viewport().size)
		screen_pos = target_pos - cam.global_position + viewport_size / 2.0
	else:
		# target_pos 是窗口屏幕坐标
		screen_pos = target_pos
	return screen_pos + Vector2(size) / 2.0

func _get_screen_top_left_from_target(target_pos: Vector2, cam: Camera2D) -> Vector2:
	# 根据目标位置与嵌入状态，计算窗口屏幕顶点坐标
	if pinned_to_screen and cam != null:
		var viewport_size := Vector2(cam.get_viewport().size)
		return target_pos - cam.global_position + viewport_size / 2.0
	else:
		return target_pos


func _emit_anchor_signal() -> void:
	if _anchor_node != null and is_instance_valid(_anchor_node):
		emit_signal("anchor_screen_pos_changed", _anchor_node.global_position)


func _get_title_height() -> float:
	# 返回假标题高度（与 fake_title.tscn 中的高度匹配）
	return 40.0


func _setup_fake_title() -> void:
	# 创建并内置假标题到窗口内部，增加可视标题高度并下移内容
	if _fake_title != null and is_instance_valid(_fake_title):
		return
	# 先计算标题高度
	_title_height = _get_title_height()
	_content_offset = _title_height
	# 扩大窗口高度以容纳假标题（这是唯一修改窗口size的地方，必要的）
	# 如果编辑器中设置的size与运行时不同，是因为这里增加了标题栏高度
	size = Vector2i(size.x, int(size.y + _title_height))
	# 实例化假标题
	_fake_title = FAKE_TITLE_SCENE.instantiate()
	_fake_title.name = "InlineFakeTitle"
	# 重置锚点和位置
	_fake_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_fake_title.position = Vector2.ZERO
	_fake_title.size = Vector2(size.x, _title_height)
	_fake_title.mouse_filter = Control.MOUSE_FILTER_STOP
	# 降低 z_index，确保上边与四角句柄可覆盖并阻挡输入
	_fake_title.z_index = 10
	# 设定标题文本与目标窗口引用
	if _fake_title.has_method("set_title"):
		_fake_title.set_title(String(title))
	if _fake_title.has_method("set_target_window"):
		_fake_title.set_target_window(self)
	
	# 连接关闭信号，确保按钮有效
	if _fake_title.has_signal("request_close") and not _fake_title.is_connected("request_close", Callable(self, "_on_fake_title_request_close")):
		_fake_title.connect("request_close", Callable(self, "_on_fake_title_request_close"))
	# 添加到窗口
	add_child(_fake_title)
	print("[DefaultWindow] 创建假标题: ", _fake_title.name, " 高度=", _title_height)
	# 将现有子节点整体下移一个标题高度（仅在创建时执行一次）
	for child in get_children():
		if child == _fake_title:
			continue
		if child is CanvasItem:
			var ci := child as CanvasItem
			ci.position += Vector2(0, _content_offset)
	# 设定图标（若支持）
	if icon != null and _fake_title.has_method("set_icon"):
		_fake_title.set_icon(icon)
	# 此时窗口内已有的子控件还未创建，不需要下移
	_update_fake_title_layout()
	_update_fake_title_state()


func _on_fake_title_request_close() -> void:
	# 优先通知管理器关闭；没有管理器时直接隐藏窗口
	var wm = get_parent()
	if wm != null and wm.has_method("_on_window_close"):
		_notify_manager_close()
	else:
		hide()


func _update_fake_title_layout() -> void:
	if _fake_title == null or not is_instance_valid(_fake_title):
		return
	# 维持标题宽度与窗口一致，贴合顶部
	_fake_title.size = Vector2(size.x, _title_height)
	_fake_title.position = Vector2.ZERO
	# 主题淡入遮罩尺寸同步
	if _title_overlay != null:
		_title_overlay.position = Vector2.ZERO
		_title_overlay.size = Vector2(size.x, max(1.0, _title_height))
	# 状态标签保持在标题下方
	if _status_label != null:
		_status_label.position = Vector2(8, 8 + _content_offset)


func _update_fake_title_state() -> void:
	if _fake_title == null or not is_instance_valid(_fake_title):
		return
	# 假标题跟随窗口可见性
	_fake_title.visible = visible
	# 允许嵌入状态下点击按钮；仅禁用拖拽在假标题内部判断
	var input_enabled := _title_input_enabled
	_fake_title.mouse_filter = Control.MOUSE_FILTER_STOP if input_enabled else Control.MOUSE_FILTER_IGNORE
	if _fake_title.has_method("set_enabled"):
		_fake_title.set_enabled(input_enabled)

	# 根据锁定状态启用/禁用边框拉伸
	for dir in _resize_handles.keys():
		var h: Control = _resize_handles[dir]
		if is_instance_valid(h):
			var enable := visible and (not lock_resize) and (not pinned_to_screen)
			h.visible = enable
			h.mouse_filter = Control.MOUSE_FILTER_STOP if enable else Control.MOUSE_FILTER_IGNORE
	for dir in _resize_corner_handles.keys():
		var hc: Control = _resize_corner_handles[dir]
		if is_instance_valid(hc):
			var enable_c := visible and (not lock_resize) and (not pinned_to_screen)
			hc.visible = enable_c
			hc.mouse_filter = Control.MOUSE_FILTER_STOP if enable_c else Control.MOUSE_FILTER_IGNORE

func set_window_icon(tex: Texture2D) -> void:
	icon = tex
	if _fake_title != null and is_instance_valid(_fake_title) and _fake_title.has_method("set_icon"):
		_fake_title.set_icon(tex)

func _init_resize_handles() -> void:
	if lock_resize:
		return
	# 创建四条贴边可抓取的控件：left, right, top, bottom
	var make_handle := func(dir: String) -> Control:
		var h := Control.new()
		h.name = "Resize_" + dir
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.z_index = 2000
		h.focus_mode = Control.FOCUS_NONE
		add_child(h)
		# 统一使用 gui_input 处理拖拽
		h.gui_input.connect(Callable(self, "_on_handle_gui_input").bind(dir))
		# 悬停/离开时手动切换系统光标
		h.mouse_entered.connect(Callable(self, "_on_handle_mouse_enter").bind(dir))
		h.mouse_exited.connect(Callable(self, "_on_handle_mouse_exit").bind(dir))
		return h
	_resize_handles["left"] = make_handle.call("left")
	_resize_handles["right"] = make_handle.call("right")
	_resize_handles["top"] = make_handle.call("top")
	_resize_handles["bottom"] = make_handle.call("bottom")
	# 创建四角控件：tl,tr,bl,br
	var make_corner := func(dir: String) -> Control:
		var h := Control.new()
		h.name = "ResizeCorner_" + dir
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.z_index = 2001
		h.focus_mode = Control.FOCUS_NONE
		add_child(h)
		h.gui_input.connect(Callable(self, "_on_corner_gui_input").bind(dir))
		# 悬停/离开时手动切换系统光标
		h.mouse_entered.connect(Callable(self, "_on_corner_mouse_enter").bind(dir))
		h.mouse_exited.connect(Callable(self, "_on_corner_mouse_exit").bind(dir))
		return h
	_resize_corner_handles["tl"] = make_corner.call("tl")
	_resize_corner_handles["tr"] = make_corner.call("tr")
	_resize_corner_handles["bl"] = make_corner.call("bl")
	_resize_corner_handles["br"] = make_corner.call("br")

	# 设置各句柄的默认光标形状（悬停时自动显示）
	_set_handle_cursor_shapes()

func _update_resize_handles_layout() -> void:
	# 顶部需避开假标题高度
	if _resize_handles.is_empty():
		return
	var t := float(_title_height)
	var thickness = max(1.0, resize_handle_thickness)
	var w := float(size.x)
	var hgt := float(size.y)
	var left: Control = _resize_handles.get("left", null)
	var right: Control = _resize_handles.get("right", null)
	var top: Control = _resize_handles.get("top", null)
	var bottom: Control = _resize_handles.get("bottom", null)
	if is_instance_valid(left):
		left.position = Vector2(0.0, t)
		left.size = Vector2(thickness, max(0.0, hgt - t - thickness))
	if is_instance_valid(right):
		right.position = Vector2(max(0.0, w - thickness), t)
		right.size = Vector2(thickness, max(0.0, hgt - t - thickness))
	if is_instance_valid(top):
		# 顶部从 y=0 覆盖标题区域，阻挡标题输入；左右各留出角区域
		top.position = Vector2(thickness, 0.0)
		top.size = Vector2(max(0.0, w - 2.0 * thickness), thickness)
	if is_instance_valid(bottom):
		# 底边左右各留出角区域，避免覆盖角控件
		bottom.position = Vector2(thickness, max(0.0, hgt - thickness))
		bottom.size = Vector2(max(0.0, w - 2.0 * thickness), thickness)
	# 四角尺寸使用 thickness 的正方形
	var ctl: Control = _resize_corner_handles.get("tl", null)
	var ctr: Control = _resize_corner_handles.get("tr", null)
	var cbl: Control = _resize_corner_handles.get("bl", null)
	var cbr: Control = _resize_corner_handles.get("br", null)
	if is_instance_valid(ctl):
		# 顶左覆盖标题区域
		ctl.position = Vector2(0.0, 0.0)
		ctl.size = Vector2(thickness, thickness)
	if is_instance_valid(ctr):
		# 顶右覆盖标题区域
		ctr.position = Vector2(max(0.0, w - thickness), 0.0)
		ctr.size = Vector2(thickness, thickness)
	if is_instance_valid(cbl):
		cbl.position = Vector2(0.0, max(0.0, hgt - thickness))
		cbl.size = Vector2(thickness, thickness)
	if is_instance_valid(cbr):
		cbr.position = Vector2(max(0.0, w - thickness), max(0.0, hgt - thickness))
		cbr.size = Vector2(thickness, thickness)

func _set_handle_cursor_shapes() -> void:
	# 为每个句柄设置默认光标形状（悬停时自动显示）
	var left: Control = _resize_handles.get("left", null)
	var right: Control = _resize_handles.get("right", null)
	var top: Control = _resize_handles.get("top", null)
	var bottom: Control = _resize_handles.get("bottom", null)
	if is_instance_valid(left):
		left.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	if is_instance_valid(right):
		right.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	if is_instance_valid(top):
		top.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	if is_instance_valid(bottom):
		bottom.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	var ctl: Control = _resize_corner_handles.get("tl", null)
	var ctr: Control = _resize_corner_handles.get("tr", null)
	var cbl: Control = _resize_corner_handles.get("bl", null)
	var cbr: Control = _resize_corner_handles.get("br", null)
	# 'tl' 与 'br' 使用同一对角形状；'tr' 与 'bl' 使用另一对角形状
	if is_instance_valid(ctl):
		ctl.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	if is_instance_valid(cbr):
		cbr.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	if is_instance_valid(ctr):
		ctr.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	if is_instance_valid(cbl):
		cbl.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE

func _shape_for_dir(dir: String) -> int:
	match dir:
		"left", "right":
			return Input.CURSOR_HSIZE
		"top", "bottom":
			return Input.CURSOR_VSIZE
		"tl", "br":
			return Input.CURSOR_FDIAGSIZE
		"tr", "bl":
			return Input.CURSOR_BDIAGSIZE
		_:
			return Input.CURSOR_ARROW

func _set_default_cursor_for_dir(dir: String) -> void:
	Input.set_default_cursor_shape(_shape_for_dir(dir))

func _restore_default_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_handle_mouse_enter(dir: String) -> void:
	if lock_resize or pinned_to_screen:
		return
	# 悬停时显示拉伸形状，拖拽中不变更
	if _resize_dragging_dir == "":
		_set_default_cursor_for_dir(dir)

func _on_handle_mouse_exit(dir: String) -> void:
	# 离开时若非拖拽，恢复箭头
	if _resize_dragging_dir == "":
		_restore_default_cursor()

func _on_corner_mouse_enter(dir: String) -> void:
	if lock_resize or pinned_to_screen:
		return
	if _resize_dragging_dir == "":
		_set_default_cursor_for_dir(dir)

func _on_corner_mouse_exit(dir: String) -> void:
	if _resize_dragging_dir == "":
		_restore_default_cursor()


func _on_handle_gui_input(event: InputEvent, dir: String) -> void:
	if lock_resize:
		return
	# 嵌入状态禁止拉伸
	if pinned_to_screen:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.is_pressed():
				_resize_dragging_dir = dir
				_resize_drag_start_mouse = _get_mouse_screen_pos()
				_resize_drag_start_pos = Vector2(position)
				_resize_drag_start_size = Vector2(size)
			else:
				_resize_dragging_dir = ""
	elif event is InputEventMouseMotion:
		if _resize_dragging_dir != "":
			var mm := event as InputEventMouseMotion
			# 使用全局鼠标位移，避免因句柄位置变化造成抽搐
			_apply_resize_dir(_resize_dragging_dir)

func _on_corner_gui_input(event: InputEvent, dir: String) -> void:
	if lock_resize or pinned_to_screen:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.is_pressed():
				_resize_dragging_dir = dir
				_resize_drag_start_mouse = _get_mouse_screen_pos()
				_resize_drag_start_pos = Vector2(position)
				_resize_drag_start_size = Vector2(size)
			else:
				_resize_dragging_dir = ""
	elif event is InputEventMouseMotion:
		if _resize_dragging_dir != "":
			_apply_resize_dir(dir)

func _apply_resize_dir(dir: String) -> void:
	var mouse := _get_mouse_screen_pos()
	var delta := mouse - _resize_drag_start_mouse
	var sp := _resize_drag_start_pos
	var ss := _resize_drag_start_size
	var re := sp.x + ss.x
	var be := sp.y + ss.y
	var screen_size := _get_screen_size()
	# 从起始矩形和鼠标位移计算新矩形，保持对边锚定，避免抽搐
	var np := sp
	var ns := ss
	match dir:
		"left":
			np.x = sp.x + delta.x
			# 夹到 [0, re - min]
			var minx := float(re - max(min_size_x, 1))
			np.x = clamp(np.x, 0.0, minx)
			ns.x = re - np.x
		"right":
			ns.x = ss.x + delta.x
			ns.x = clamp(ns.x, float(max(min_size_x,1)), max(1.0, screen_size.x - sp.x))
		"top":
			np.y = sp.y + delta.y
			var miny := float(be - max(min_size_y, 1))
			np.y = clamp(np.y, 0.0, miny)
			ns.y = be - np.y
		"bottom":
			ns.y = ss.y + delta.y
			ns.y = clamp(ns.y, float(max(min_size_y,1)), max(1.0, screen_size.y - sp.y))
		"tl":
			# 左 + 上 合并
			# left
			var nx := sp.x + delta.x
			nx = clamp(nx, 0.0, float(re - max(min_size_x,1)))
			# top
			var ny := sp.y + delta.y
			ny = clamp(ny, 0.0, float(be - max(min_size_y,1)))
			np = Vector2(nx, ny)
			ns = Vector2(re - nx, be - ny)
		"tr":
			# 右 + 上
			var ny2 := sp.y + delta.y
			ny2 = clamp(ny2, 0.0, float(be - max(min_size_y,1)))
			np = Vector2(sp.x, ny2)
			var nxw := ss.x + delta.x
			nxw = clamp(nxw, float(max(min_size_x,1)), max(1.0, screen_size.x - sp.x))
			ns = Vector2(nxw, be - ny2)
		"bl":
			# 左 + 下
			var nx2 := sp.x + delta.x
			nx2 = clamp(nx2, 0.0, float(re - max(min_size_x,1)))
			var nyh := ss.y + delta.y
			nyh = clamp(nyh, float(max(min_size_y,1)), max(1.0, screen_size.y - sp.y))
			np = Vector2(nx2, sp.y)
			ns = Vector2(re - nx2, nyh)
		"br":
			# 右 + 下
			ns = Vector2(
				clamp(ss.x + delta.x, float(max(min_size_x,1)), max(1.0, screen_size.x - sp.x)),
				clamp(ss.y + delta.y, float(max(min_size_y,1)), max(1.0, screen_size.y - sp.y))
			)
	_apply_resize(np, ns)

func _apply_resize(new_pos: Vector2, new_size: Vector2) -> void:
	# 更新导出最小尺寸
	_min_size = Vector2i(max(min_size_x, 1), max(min_size_y, 1))
	# 最终安全夹取
	new_size.x = max(float(_min_size.x), new_size.x)
	new_size.y = max(float(_min_size.y), new_size.y)
	var screen_size := _get_screen_size()
	new_pos.x = clamp(new_pos.x, 0.0, max(0.0, screen_size.x - new_size.x))
	new_pos.y = clamp(new_pos.y, 0.0, max(0.0, screen_size.y - new_size.y))
	size = Vector2i(new_size)
	position = Vector2i(new_pos)
	_update_fake_title_layout()
	_update_resize_handles_layout()
	_sync_anchor_to_position_if_pinned()
	_notify_manager_geometry_changed()

func _notify_manager_geometry_changed() -> void:
	var wm = get_parent()
	if wm != null and wm.has_method("_on_window_geometry_changed"):
		wm._on_window_geometry_changed(self)

func _sync_anchor_to_position_if_pinned() -> void:
	if not pinned_to_screen:
		return
	if _anchor_node == null or not is_instance_valid(_anchor_node):
		return
	var cam := _get_camera()
	if cam != null:
		var viewport_size := Vector2(cam.get_viewport().size)
		var world_pos := Vector2(position) + cam.global_position - viewport_size / 2.0
		_anchor_node.global_position = world_pos
		_anchor_world_pos = world_pos
	else:
		_anchor_node.global_position = Vector2(position)
		_anchor_world_pos = Vector2(position)

func _exit_tree() -> void:
	# 释放时清理锚点，避免重名锚点残留导致后续窗口无法正常重建
	if _anchor_node != null and is_instance_valid(_anchor_node):
		_anchor_node.queue_free()
		_anchor_node = null

func _stabilize_visibility_deferred() -> void:
	# 平台兼容：执行一次性 hide->show 稳定化
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	hide()
	await get_tree().process_frame
	if is_instance_valid(self):
		show()
