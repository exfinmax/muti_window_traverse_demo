extends Node
## 全局输入阻挡管理器
## 当玩家在任何文本输入控件中输入时，自动阻止玩家角色的移动和操作

var player: Node = null
var input_handler: Node = null
var active_input_controls: Array[Control] = []
var is_player_input_blocked: bool = false

func _ready() -> void:
	add_to_group("input_blocker")
	# 延迟获取玩家引用
	call_deferred("_find_player")
	
	# 监听场景树变化，自动连接新的输入控件
	get_tree().node_added.connect(_on_node_added)
	
	_log("[InputBlocker] Initialized")

func _log(message: String) -> void:
	"""输出日志到控制台和调试窗口"""
	print(message)
	var debug_console = get_tree().get_first_node_in_group("debug_console")
	if debug_console and debug_console.has_method("add_info"):
		debug_console.add_info(message)

func _log_error(message: String) -> void:
	"""输出错误到控制台和调试窗口"""
	push_error(message)
	var debug_console = get_tree().get_first_node_in_group("debug_console")
	if debug_console and debug_console.has_method("add_error"):
		debug_console.add_error(message)

func _log_warning(message: String) -> void:
	"""输出警告到控制台和调试窗口"""
	push_warning(message)
	var debug_console = get_tree().get_first_node_in_group("debug_console")
	if debug_console and debug_console.has_method("add_warning"):
		debug_console.add_warning(message)

func _find_player() -> void:
	"""查找玩家节点和输入处理器"""
	player = get_tree().get_first_node_in_group("player")
	if player:
		_log("[InputBlocker] Found player node: " + player.name)
		# 查找 InputHandler
		input_handler = player.get_node_or_null("InputHandler")
		if not input_handler:
			# 尝试使用 unique name
			for child in player.get_children():
				if child.name == "InputHandler":
					input_handler = child
					break
		
		if input_handler:
			_log("[InputBlocker] Found InputHandler: " + input_handler.name)
		else:
			_log_warning("[InputBlocker] InputHandler not found, will use fallback method")
	else:
		_log_warning("[InputBlocker] Player node not found")

func _on_node_added(node: Node) -> void:
	"""当新节点添加到场景树时，检查是否是输入控件"""
	if node is LineEdit or node is TextEdit:
		_connect_input_control(node)

func _connect_input_control(control: Control) -> void:
	"""连接输入控件的焦点信号"""
	if control is LineEdit:
		if not control.focus_entered.is_connected(_on_input_focus_entered):
			control.focus_entered.connect(_on_input_focus_entered.bind(control))
		if not control.focus_exited.is_connected(_on_input_focus_exited):
			control.focus_exited.connect(_on_input_focus_exited.bind(control))
		_log("[InputBlocker] Connected LineEdit: " + str(control.get_path()))
	elif control is TextEdit:
		if not control.focus_entered.is_connected(_on_input_focus_entered):
			control.focus_entered.connect(_on_input_focus_entered.bind(control))
		if not control.focus_exited.is_connected(_on_input_focus_exited):
			control.focus_exited.connect(_on_input_focus_exited.bind(control))
		_log("[InputBlocker] Connected TextEdit: " + str(control.get_path()))

func _on_input_focus_entered(control: Control) -> void:
	"""输入控件获得焦点"""
	if not active_input_controls.has(control):
		active_input_controls.append(control)
	_update_player_input_state()
	_log("[InputBlocker] Input control gained focus: " + str(control.get_path()))
	
	var debug_console = get_tree().get_first_node_in_group("debug_console")
	if debug_console and debug_console.has_method("add_success"):
		debug_console.add_success("[InputBlocker] Player input BLOCKED")

func _on_input_focus_exited(control: Control) -> void:
	"""输入控件失去焦点"""
	active_input_controls.erase(control)
	_update_player_input_state()
	if active_input_controls.is_empty():
		_log("[InputBlocker] All input controls lost focus")
		var debug_console = get_tree().get_first_node_in_group("debug_console")
		if debug_console and debug_console.has_method("add_success"):
			debug_console.add_success("[InputBlocker] Player input RESTORED")

func _update_player_input_state() -> void:
	"""更新玩家输入状态"""
	var should_block = not active_input_controls.is_empty()
	
	if should_block != is_player_input_blocked:
		is_player_input_blocked = should_block
		_set_player_input_enabled(not should_block)

func _set_player_input_enabled(enabled: bool) -> void:
	"""启用或禁用玩家输入"""
	if player == null:
		_find_player()
	
	if player == null:
		_log_error("[InputBlocker] Cannot set player input - player not found")
		return
	
	# 方法1：通过 InputHandler 禁用能力
	if input_handler and is_instance_valid(input_handler):
		# 直接设置 InputHandler 的能力标志
		input_handler.can_move = enabled
		input_handler.can_jump = enabled
		input_handler.can_dash = enabled
		_log("[InputBlocker] Set InputHandler abilities to: " + str(enabled))
	else:
		_log_warning("[InputBlocker] InputHandler not available, using fallback")
	
	# 方法2：直接设置玩家的能力标志（主要方法）
	if player and is_instance_valid(player):
		if "can_move" in player:
			player.can_move = enabled
		if "can_jump" in player:
			player.can_jump = enabled
		if "can_dash" in player:
			player.can_dash = enabled
		_log("[InputBlocker] Set player abilities to: " + str(enabled))
		
		# 如果玩家有自定义的输入启用/禁用方法
		if player.has_method("set_input_enabled"):
			player.set_input_enabled(enabled)

func register_input_control(control: Control) -> void:
	"""手动注册输入控件（用于动态创建的控件）"""
	_connect_input_control(control)

func force_restore_player_input() -> void:
	"""强制恢复玩家输入（用于紧急情况）"""
	active_input_controls.clear()
	_set_player_input_enabled(true)
	is_player_input_blocked = false
	_log("[InputBlocker] Player input forcefully restored")
