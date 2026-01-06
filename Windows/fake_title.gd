extends Control

@export var max_drag_distance: float = 200.0
@export var enabled: bool = true
var _drag_blocked: bool = false

signal request_close()
var _target_win: Window = null
var _target_anchor: Node2D = null

@onready var _icon: TextureRect = $HBoxContainer/Icon
@onready var _title_label: Label = $HBoxContainer/Title
@onready var _close_btn: Button = $HBoxContainer/Close
@onready var _bg: ColorRect = $Background

func _ready() -> void:
	_close_btn.pressed.connect(func():
		request_close.emit()
	)
	_update_background_style()
	_load_project_icon()
	_apply_enabled()



func set_title(text: String, hor_allgnment:HorizontalAlignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT,color: Color = Color.WHITE) -> void:
	if _title_label:
		_title_label.text = text
		_title_label.horizontal_alignment = hor_allgnment
		_title_label.modulate = color
	else:
		await ready
		if _title_label:
			_title_label.text = text
			_title_label.horizontal_alignment = hor_allgnment
			_title_label.modulate = color

func set_icon(tex: Texture2D) -> void:
	_icon.texture = tex

func set_target_window(win: Window) -> void:
	_target_win = win

func set_target_anchor(anchor: Node2D) -> void:
	_target_anchor = anchor

func set_enabled(v: bool) -> void:
	enabled = v
	_apply_enabled()

func _apply_enabled() -> void:
	# 不再控制可见性，由父窗口控制；仅更新样式
	_update_background_style()

func _load_project_icon() -> void:
	# 从项目设置读取图标
	var icon_path := ""
	if ProjectSettings.has_setting("application/config/icon"):
		icon_path = String(ProjectSettings.get_setting("application/config/icon"))
	if icon_path != "":
		var tex = load(icon_path)
		if tex is Texture2D:
			_icon.texture = tex

func _update_background_style() -> void:
	# 使用默认样式，未来会通过专门主题设置
	pass

func _gui_input(event: InputEvent) -> void:
	# 在假标题上拖拽移动窗口
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				# 开始拖拽，捕获输入
				_drag_blocked = false
				if _target_win != null and is_instance_valid(_target_win) and _target_win.has_method("move_to_front"):
					_target_win.move_to_front()
				get_viewport().set_input_as_handled()
			else:
				# 释放拖拽
				_drag_blocked = false
				if _target_win != null and is_instance_valid(_target_win):
					_target_win._title_dragging_active = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		# 拖拽：通过窗口接口移动锚点，假标题自身不再单独偏移
		if _target_win != null and is_instance_valid(_target_win):
			# 嵌入时允许按钮，但不允许拖拽
			if "pinned_to_screen" in _target_win and _target_win.pinned_to_screen:
				return
			if _drag_blocked:
				return
			# 防止单次拖拽跳变：检测单次移动距离（本控件的导出变量）
			var drag_distance = event.relative.length()
			if drag_distance > max_drag_distance:
				return
			# 边界预判：命中边界则阻断后续拖拽直到松开，不移动坐标
			if _target_win.has_method("will_hit_bounds") and _target_win.will_hit_bounds(event.relative):
				_drag_blocked = true
				return
			if _target_win.has_method("_apply_title_drag"):
				_target_win._apply_title_drag(event.relative)
		else:
			# 回退：无目标窗口时不处理位移
			return
		get_viewport().set_input_as_handled()
