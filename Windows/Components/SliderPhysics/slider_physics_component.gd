class_name SliderPhysicsComponent
extends WindowComponent

## 滑块物理组件
## 自动扫描窗口中的所有滑块并为每个滑块创建物理交互句柄
## 完全自包含，不依赖外部管理器

# Preload specialized handle types
const AudioSliderPhysicsHandle = preload("uid://bomf1g7aay6qo")
const VolumeSliderPhysicsHandle = preload("uid://ckhr1s48lw3jd")

# Signals
signal slider_pushed(slider: Slider, old_value: float, new_value: float)
signal slider_blocked(slider: Slider, player: Player)
signal slider_released(slider: Slider)

# Properties
var handles: Array[SliderPhysicsHandle] = []
var player_inside: Player = null
var enabled: bool = true

# Configuration
@export var auto_scan_on_ready: bool = true
@export var push_sensitivity: float = 1.0
@export var block_threshold: float = 2.0

func _on_component_ready() -> void:
	# 自动扫描滑块
	if auto_scan_on_ready:
		scan_for_sliders()
	
	# 连接到 Global.player 的窗口进入/退出信号
	if Global.player != null:
		if not Global.player.entered_window.is_connected(_on_player_entered_window):
			Global.player.entered_window.connect(_on_player_entered_window)
		if not Global.player.exited_window.is_connected(_on_player_exited_window):
			Global.player.exited_window.connect(_on_player_exited_window)
		DebugHelper.log("SliderPhysicsComponent: Connected to player window signals")
	else:
		DebugHelper.warning("SliderPhysicsComponent: Global.player is null, cannot connect signals")

func _on_player_entered_window(entered_window: Window) -> void:
	"""当玩家进入任何窗口时调用 - 检查是否是自己的窗口"""
	if entered_window == window:
		_on_player_entered(Global.player)

func _on_player_exited_window(exited_window: Window) -> void:
	"""当玩家退出任何窗口时调用 - 检查是否是自己的窗口"""
	if exited_window == window:
		_on_player_exited(Global.player)

func scan_for_sliders() -> void:
	"""递归查找窗口中的所有滑块控件并为每个创建句柄"""
	if window == null:
		DebugHelper.error("[SliderPhysicsComponent] Cannot scan for sliders: window is null")
		return
	
	# 清理现有句柄
	cleanup()
	
	# 递归查找所有滑块
	var sliders: Array[Slider] = []
	_find_sliders_recursive(window, sliders)
	
	# 为每个滑块创建句柄
	for slider in sliders:
		var handle = create_handle_for_slider(slider)
		if handle != null:
			handles.append(handle)
	
	DebugHelper.success("[SliderPhysicsComponent] Found and created handles for %d sliders in window '%s'" % [handles.size(), window.title if window is Window else window.name])

func _find_sliders_recursive(node: Node, result: Array[Slider]) -> void:
	"""递归搜索滑块控件"""
	# 检查此节点是否为滑块
	if node is HSlider or node is VSlider:
		result.append(node as Slider)
	
	# 递归搜索子节点
	for child in node.get_children():
		_find_sliders_recursive(child, result)

func _find_audio_player_control(slider: Slider) -> Control:
	"""查找包含此滑块的音频播放器控件"""
	var current = slider.get_parent()
	while current != null:
		if current is Control:
			# 检查是否具有预期的音频播放器属性/方法
			if current.has_node("%AudioStreamPlayer") and current.has_node("%MusicSlider"):
				return current
		current = current.get_parent()
	return null

func create_handle_for_slider(slider: Slider) -> SliderPhysicsHandle:
	"""为给定的滑块创建物理句柄"""
	if slider == null:
		DebugHelper.error("[SliderPhysicsComponent] Cannot create handle: slider is null")
		return null
	
	var handle: SliderPhysicsHandle = null
	
	# 检查音量滑块 (Master, Music, SFX)
	if slider.name in ["SliderMaster", "SliderMusic", "SliderSFX"]:
		var volume_handle = VolumeSliderPhysicsHandle.new()
		volume_handle.name = "VolumeSliderPhysicsHandle_%s" % slider.name
		handle = volume_handle
		
		# 添加为滑块的子节点以正确定位
		slider.add_child(handle)
		
		# 设置音量特定句柄
		if player_inside != null:
			volume_handle.setup(slider, player_inside)
		else:
			# 暂时不设置玩家
			handle.slider = slider
			# 确定音频总线映射
			if slider.name in VolumeSliderPhysicsHandle.BUS_MAPPING:
				volume_handle.audio_bus_name = VolumeSliderPhysicsHandle.BUS_MAPPING[slider.name]
				volume_handle.settings_key = VolumeSliderPhysicsHandle.SETTINGS_MAPPING[slider.name]
			# 连接到滑块值变化
			if slider and not slider.value_changed.is_connected(handle._on_slider_value_changed):
				slider.value_changed.connect(handle._on_slider_value_changed)
			handle.update_collision_shape()
		
		DebugHelper.success("[SliderPhysicsComponent] Created VolumeSliderPhysicsHandle for %s" % slider.name)
	
	# 检查音频播放器音乐滑块
	elif slider.name == "MusicSlider":
		var audio_control = _find_audio_player_control(slider)
		if audio_control:
			var audio_handle = AudioSliderPhysicsHandle.new()
			audio_handle.name = "AudioSliderPhysicsHandle_%s" % slider.name
			handle = audio_handle
			
			# 添加为滑块的子节点
			slider.add_child(handle)
			
			# 设置音频特定句柄
			if player_inside != null:
				audio_handle.setup_audio_slider(slider, player_inside, audio_control)
			else:
				# 暂时不设置玩家
				handle.slider = slider
				audio_handle.audio_player_control = audio_control
				audio_handle.audio_stream_player = audio_control.get_node_or_null("%AudioStreamPlayer")
				if slider and not slider.value_changed.is_connected(handle._on_slider_value_changed):
					slider.value_changed.connect(handle._on_slider_value_changed)
				handle.update_collision_shape()
			
			DebugHelper.success("[SliderPhysicsComponent] Created AudioSliderPhysicsHandle for MusicSlider")
		else:
			DebugHelper.warning("[SliderPhysicsComponent] Found MusicSlider but could not find audio player control")
	
	# 如果没有创建特殊句柄，创建标准句柄
	if handle == null:
		handle = SliderPhysicsHandle.new()
		handle.name = "SliderPhysicsHandle_%s" % slider.name
		
		# 添加为滑块的子节点
		slider.add_child(handle)
		
		# 设置句柄
		if player_inside != null:
			handle.setup(slider, player_inside)
		else:
			# 暂时不设置玩家
			handle.slider = slider
			# 连接到滑块值变化
			if slider and not slider.value_changed.is_connected(handle._on_slider_value_changed):
				slider.value_changed.connect(handle._on_slider_value_changed)
			handle.update_collision_shape()
		
		DebugHelper.info("[SliderPhysicsComponent] Created standard SliderPhysicsHandle for %s" % slider.name)
	
	# 使用管理器设置配置句柄
	handle.push_sensitivity = push_sensitivity
	handle.block_threshold = block_threshold
	
	# 连接句柄信号到组件信号
	handle.handle_pushed.connect(_on_handle_pushed.bind(slider))
	handle.handle_blocked.connect(_on_handle_blocked.bind(slider))
	handle.handle_released.connect(_on_handle_released.bind(slider))
	
	# 如果玩家在内部则启用监控
	handle.enable_monitoring(player_inside != null and enabled)
	
	return handle

func _on_player_entered(player: Player) -> void:
	"""当玩家进入窗口时调用"""
	if player == null:
		return
	
	player_inside = player
	
	# 为所有句柄设置玩家引用
	for handle in handles:
		if handle != null and is_instance_valid(handle):
			# 如果句柄未完全设置，现在完成设置
			if handle.player_ref == null and handle.slider != null:
				# 检查是否为音频滑块句柄
				if handle is AudioSliderPhysicsHandle:
					var audio_handle = handle as AudioSliderPhysicsHandle
					if audio_handle.audio_player_control:
						audio_handle.setup_audio_slider(handle.slider, player, audio_handle.audio_player_control)
					else:
						handle.setup(handle.slider, player)
				# 检查是否为音量滑块句柄
				elif handle is VolumeSliderPhysicsHandle:
					var volume_handle = handle as VolumeSliderPhysicsHandle
					volume_handle.setup(handle.slider, player)
				else:
					handle.setup(handle.slider, player)
			else:
				handle.player_ref = player
			
			# 启用监控
			if enabled:
				handle.enable_monitoring(true)
	
	DebugHelper.success("[SliderPhysicsComponent] Player entered window, enabled %d slider handles" % handles.size())

func _on_player_exited(player: Player) -> void:
	"""当玩家退出窗口时调用"""
	if player == null:
		return
	
	# 仅在这是我们正在跟踪的玩家时清除
	if player_inside == player:
		player_inside = null
		
		# 禁用所有句柄的监控
		for handle in handles:
			if handle != null and is_instance_valid(handle):
				handle.enable_monitoring(false)
		
		DebugHelper.info("[SliderPhysicsComponent] Player exited window, disabled %d slider handles" % handles.size())

func enable_physics(enable: bool) -> void:
	"""启用或禁用所有滑块句柄的物理"""
	enabled = enable
	
	# 更新所有句柄的监控状态
	for handle in handles:
		if handle != null and is_instance_valid(handle):
			handle.enable_monitoring(enable and player_inside != null)
	
	DebugHelper.info("[SliderPhysicsComponent] Physics %s for %d handles" % ["enabled" if enable else "disabled", handles.size()])

func cleanup() -> void:
	"""清理所有滑块物理句柄并释放资源"""
	# 清理所有句柄
	for handle in handles:
		if handle != null and is_instance_valid(handle):
			handle.cleanup()
	
	# 清空句柄数组
	handles.clear()
	player_inside = null
	
	DebugHelper.info("[SliderPhysicsComponent] Cleaned up all slider handles")

func on_window_embedded() -> void:
	"""窗口嵌入时启用物理"""
	enable_physics(true)
	DebugHelper.log("SliderPhysicsComponent: Enabled physics on embed")

func on_window_unembedded() -> void:
	"""窗口取消嵌入时禁用物理"""
	enable_physics(false)
	DebugHelper.log("SliderPhysicsComponent: Disabled physics on unembed")

func on_window_closed() -> void:
	"""窗口关闭时清理"""
	cleanup()

func _on_handle_pushed(old_value: float, new_value: float, slider: Slider) -> void:
	"""内部回调：当句柄被推动时"""
	slider_pushed.emit(slider, old_value, new_value)

func _on_handle_blocked(slider: Slider) -> void:
	"""内部回调：当句柄被阻挡时"""
	if player_inside != null:
		slider_blocked.emit(slider, player_inside)

func _on_handle_released(slider: Slider) -> void:
	"""内部回调：当句柄被释放时"""
	slider_released.emit(slider)

func _exit_tree() -> void:
	"""从场景树移除时清理"""
	cleanup()
