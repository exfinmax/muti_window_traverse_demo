extends DefaultWindow


# Called when the node enters the scene tree for the first time.
var window_manager: Node = null

@export var close_behavior: String = "delete"  ## 关闭行为 "delete" 或 "hide"

func _ready() -> void:
	transient = true
	super._ready()
	can_embed = false
	if transient:
		always_on_top = false
	# 设置 meta 标记为 transient 窗口
	set_meta("is_transient", true)
	# 连接可见性变化信号
	connect("visibility_changed", Callable(self, "_on_visibility_changed"))
	# 如果初始可见，启用 exclusive 和更新输入阻塞
	if visible:
		exclusive = true
		if window_manager != null and window_manager.has_method("update_input_blocking"):
			window_manager.update_input_blocking()
	# 递归查找 transition_window_manager 并缓存
	window_manager = _find_transition_window_manager()
	if window_manager != null:
		# 让管理器能发现并管理本窗口
		if window_manager.has_method("add_managed_window"):
			window_manager.add_managed_window(self)

func _on_visibility_changed() -> void:
	exclusive = visible
	if window_manager != null and window_manager.has_method("update_input_blocking"):
		window_manager.update_input_blocking()

func _exit_tree() -> void:
	# 退出时解除 exclusive
	exclusive = false
	if window_manager != null and window_manager.has_method("update_input_blocking"):
		window_manager.update_input_blocking()

# 递归向上查找 transition_window_manager 节点
func _find_transition_window_manager() -> Node:
	var node = get_parent()
	while node != null:
		if node.get_script() != null and node.get_script().resource_path.ends_with("transition_window_manager.gd"):
			return node
		node = node.get_parent()
	return null
