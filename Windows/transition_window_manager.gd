class_name WindowManager
extends Node2D

## Portal Transition Window Manager (Screen-Space Traversal)
##
## 坐标口径：统一使用“屏幕坐标(OS)”判定穿越
## - 窗口矩形：Rect2(win.position, win.size)（OS 原点 + 尺寸）
## - 穿越者矩形：以 CollisionShape2D 为基准，四角通过
##   get_global_transform_with_canvas() 变换后，加宿主窗口 OS 原点，取 AABB
## - 相机 zoom/rotation：由 Canvas 变换天然包含，无需单独处理
## - 主窗口非全屏/可移动：使用 Window.position（OS）即可
##
## 进入/退出与相机：
## - 进入窗口：暂停相机（仅玩家）并重排层级，将旅行者放入窗口，位置用“屏幕差”得到局部坐标
## - 退出窗口：通过 inv(canvas) 将“屏幕坐标-主窗OS原点”映射回世界坐标，恢复相机（仅玩家，含延时）
##
## 性能与事件：
## - 子窗口几何变化（移动/拉伸）仅重判该窗口，并对靠近其边界的穿越者做预筛
## - 只允许低→高优先级切换；退出采用相交判断，进入采用完全包围
##
## 注意：本管理器不再依赖“世界/有效坐标”做判定；锚点与嵌入仅影响窗口自身运动表现，
##      与穿越判定解耦（由 default_window.gd 内部维护）。

const DEFAULT_SCRIPT := preload("uid://faq4aabonqir")
const POPUP_SCRIPT := preload("uid://181ye6gctoeo")
const TRANSIENT_SCRIPT := preload("uid://bb8jmfkawtbrm")

# 相机引用（从主场景获取）
var camera: Camera2D

var player: CharacterBody2D
var original_parent: Node = null
var managed_windows: Array[Window] = []
var window_entry_states: Dictionary = {}  # {Window: was_inside_last_frame}
var last_camera_pos: Vector2 = Vector2.ZERO

# 所有可穿越实体的组名（统一管理）
@export var traveler_group: String = "portal_travelers"
@export var geometry_recheck_margin: float = 24.0  ## 窗口几何变化时的快速重判边缘裕量
@export_range(0,1,.01) var proxy_overlap_min_ratio: float = 0.2   ## 生成过渡代理所需的最小交叠面积占旅行者 AABB 面积的比例
@export var debug_enabled: bool = false  ## 调试叠加开关
@export var safe_rect_ratio: float = 0.5  ## 屏幕中心安全矩形占屏幕比例（可调）
@export var cooldown_time: float = 3.0 ##窗口穿越间隔时间
@export var camera_resume_delay: float = 2.0 ##相机延迟时间


# 为每个旅行者维护状态
var traveler_current_window: Dictionary = {}   # {Node: Window|null}
var traveler_cooldowns: Dictionary = {}        # {Node: {Window: float}}

var _debug_labels: Dictionary = {} # {Window: Label}
var _debug_dots: Dictionary = {}    # {Window: ColorRect}
var _debug_hud: Label = null        # 顶层调试文本
var _proxy_slider: HSlider = null   # 代理面积阈值滑块
var _debug_root: VBoxContainer = null  # 调试根容器
var _spawn_seq: int = 0

# transient 窗口列表，用于管理输入阻塞
var transient_windows: Array[Window] = []

# 过渡代理贴图：当旅行者与目标窗口“部分相交”时，
# 在目标容器（子窗口或主世界）内生成一个临时 Sprite/AnimatedSprite 跟随位置，
# 以增强视觉连续性。结构：{ traveler: { container_key(Object|"_world"): Node2D proxy } }
var transition_proxies: Dictionary = {}



func _ready() -> void:
	# 尝试从父节点（主场景）获取相机
	var parent = get_parent()
	if parent.has_node("Camera2D"):
		camera = parent.get_node("Camera2D")
	else:
		# 尝试在场景中查找
		camera = get_tree().root.find_child("Camera2D", true, false)
	
	if camera == null:
		last_camera_pos = Vector2.ZERO
	else:
		last_camera_pos = camera.global_position
	
	# 获取玩家
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player != null:
		original_parent = player.get_parent()
		# 统一使用旅行者系统：自动加入组
		if not player.is_in_group(traveler_group):
			player.add_to_group(traveler_group)
	
	# 自动检测所有 Window 子节点
	_discover_windows()
	# 提供给子窗口脚本读取的安全矩形比例
	set_meta("safe_rect_ratio", safe_rect_ratio)
	# 提供相机引用，供子窗口读取以实现嵌入跟随
	set_meta("camera_ref", camera)
	# 提供相机缓冲时间，供窗口 UI 显示
	set_meta("camera_resume_delay", camera_resume_delay)
	# 加入组，便于其他节点查找
	add_to_group("window_manager")

	# 不再创建全局输入阻挡覆盖层

	# 创建调试 HUD（可选）
	if debug_enabled:
		_ensure_debug_hud()

func _discover_windows() -> void:
	"""自动发现所有子窗口节点"""
	for child in get_children():
		if child is Window:
			if child.get_script() == null:
				child.set_script(DEFAULT_SCRIPT)
				child._ready()
			add_managed_window(child)


func add_managed_window(win: Window) -> void:
	if win == null:
		return
	# 作为管理器子节点，便于统一发现与信号管理（仅当无父节点时）
	if win.get_script() == null:
		win.set_script(DEFAULT_SCRIPT)
	elif win.get_script() == POPUP_SCRIPT:
		win.popup_window = true
		win.popup_wm_hint = true
	if win.get_parent() == null:
		add_child(win)
	managed_windows.append(win)
	window_entry_states[win] = false
	if not win.is_connected("close_requested", Callable(self, "_on_window_close")):
		win.connect("close_requested", Callable(self, "_on_window_close").bind(win))
	if win.has_signal("request_push_out") and not win.is_connected("request_push_out", Callable(self, "_on_request_push_out")):
		win.connect("request_push_out", Callable(self, "_on_request_push_out"))
	if win.has_signal("request_force_exit") and not win.is_connected("request_force_exit", Callable(self, "_on_request_force_exit")):
		win.connect("request_force_exit", Callable(self, "_on_request_force_exit"))
	win.set_meta("safe_rect_ratio", safe_rect_ratio)
	win.set_meta("camera_ref", camera)
	win.set_meta("camera_resume_delay", camera_resume_delay)
	win.set_meta("window_manager", self)
	# 如果是 transient 窗口，添加到列表
	if win.get_meta("is_transient", false):
		transient_windows.append(win)
	print("新增可穿梭窗口: ", win.name)


func spawn_window_ahead_of(spawner: Node2D) -> void:
	# 技能窗口：禁拉伸但可拖动（fixed_enabled=false），
	# 位置以“玩家的屏幕坐标(OS)前方”作为生成点（兼容玩家在子窗口中的情况）。
	var size := Vector2i(100, 100)
	var ahead := float(size.x)
	var dir := 1.0
	if "velocity" in spawner:
		var vx = spawner.velocity.x
		if abs(vx) > 0.01:
			dir = sign(vx)
	# 玩家屏幕(OS)原点（包含相机/Canvas 变换与宿主子窗口 OS 偏移）
	var spawner_os := _get_node_screen_origin_os(spawner)
	var center_os := spawner_os + Vector2(ahead * dir, 0.0)
	var origin_os := center_os - Vector2(size) / 2.0
	var win := DefaultWindow.new()
	win.spawner = spawner
	_spawn_seq += 1
	win.name = "SkillWindow_%d" % _spawn_seq
	win.size = size
	# 可拖动：不固定到屏幕（非嵌入），仅禁拉伸
	win.fixed_enabled = false
	win.lock_resize = true
	win.priority = 3
	win.title = "Skill Window"
	# OS 屏幕坐标直接作为 Window.position
	win.position = Vector2i(origin_os)
	add_managed_window(win)

func _process(delta: float) -> void:
	# 收集当前旅行者集合
	var travelers: Array = get_tree().get_nodes_in_group(traveler_group)
	if travelers.size() == 0:
		return

	# 清理已释放的窗口，避免访问无效对象
	var alive: Array[Window] = []
	for win in managed_windows:
		if is_instance_valid(win):
			alive.append(win)
		else:
			window_entry_states.erase(win)
	managed_windows = alive

	# 记录相机移动量（用于窗口退出时的反向推送）
	var camera_delta := Vector2.ZERO
	if camera != null:
		camera_delta = camera.global_position - last_camera_pos
		last_camera_pos = camera.global_position
	
	# 更新每个旅行者的窗口冷却时间
	for t in travelers:
		if not traveler_cooldowns.has(t):
			traveler_cooldowns[t] = {}
		for win in traveler_cooldowns[t].keys():
			if traveler_cooldowns[t][win] > 0.0:
				traveler_cooldowns[t][win] -= delta
	
	# 为每个旅行者执行穿越检查（含无相机模式）
	for t in travelers:
		_check_all_windows_for_traveler(t, camera_delta)

	# 刷新调试 HUD
	if debug_enabled:
		_update_debug_hud(travelers)

func _unhandled_input(event: InputEvent) -> void:
	# 右键嵌入切换已移回窗口内部处理
	# F3 切换调试 HUD 可见与逻辑开关
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_F3:
			debug_enabled = not debug_enabled
			if debug_enabled:
				_ensure_debug_hud()
				if _debug_hud != null and is_instance_valid(_debug_hud):
					_debug_hud.visible = true
			else:
				if _debug_hud != null and is_instance_valid(_debug_hud):
					_debug_hud.visible = false
#region Denug模块
func _ensure_debug_nodes(win: Window) -> void:
	if not _debug_labels.has(win) or not is_instance_valid(_debug_labels[win]):
		var lbl := Label.new()
		lbl.top_level = true
		lbl.z_index = 1000
		lbl.modulate = Color(1,1,0,1)
		lbl.add_theme_font_size_override("font_size", 12)
		_debug_labels[win] = lbl
		get_tree().root.add_child.call_deferred(lbl)
	if not _debug_dots.has(win) or not is_instance_valid(_debug_dots[win]):
		var dot := ColorRect.new()
		dot.top_level = true
		dot.z_index = 1000
		dot.color = Color(1,0,0,1)
		dot.size = Vector2(6,6)
		_debug_dots[win] = dot
		get_tree().root.add_child.call_deferred(dot)

func _update_debug_overlay(win: Window, anchor_screen: Vector2, fake_pos: Vector2) -> void:
	_ensure_debug_nodes(win)
	var lbl: Label = _debug_labels[win]
	var dot: ColorRect = _debug_dots[win]
	if is_instance_valid(lbl):
		lbl.text = "%s\nwin.pos=%s\nanchor_screen=%s\nfake.pos=%s" % [win.name, str(win.position), str(anchor_screen), str(fake_pos)]
		# 文本放在假标题上方
		lbl.position = fake_pos - Vector2(0, 16)
	if is_instance_valid(dot):
		# 小点标记屏幕坐标
		dot.position = anchor_screen - Vector2(3,3)


func _update_debug_hud(travelers: Array) -> void:
	if _debug_hud == null or not is_instance_valid(_debug_hud):
		return
	var vp = get_viewport()
	var vp_size = Vector2(vp.size)
	var lines: Array[String] = []
	lines.append("[Portal Debug]")
	lines.append("Viewport: %s" % [str(vp_size)])
	lines.append("Windows: %d" % managed_windows.size())
	lines.append("Travelers: %d" % travelers.size())
	for t in travelers:
		var rect = _get_traveler_screen_rect(t)
		var cur_win: Window = t.get_parent() if t.get_parent() is DefaultWindow else traveler_current_window.get(t, null)
		var best_win: Window = null
		var best_pri = -INF
		var max_overlap_ratio: float = 0.0
		for win in managed_windows:
			if not is_instance_valid(win):
				continue
			var wrect = _get_window_rect_screen(win)
			if wrect.size == Vector2.ZERO:
				continue
			if wrect.encloses(rect):
				var p = 0
				if "priority" in win:
					p = win.priority
				if p > best_pri:
					best_pri = p
					best_win = win
			elif wrect.intersects(rect):
				var inter := rect.intersection(wrect)
				if inter != Rect2():
					var base_area: float = rect.size.x * rect.size.y
					if base_area > 0.0:
						var ratio: float = (inter.size.x * inter.size.y) / base_area
						if ratio > max_overlap_ratio:
							max_overlap_ratio = ratio
		var cd = traveler_cooldowns.get(t, {})
		var cd_count = 0
		for w in cd.keys():
			if cd[w] > 0.0:
				cd_count += 1
		lines.append("- %s rect=%s cur=%s best=%s cooldowns_active=%d" % [
			t.name if ("name" in t) else str(t),
			str(rect),
			cur_win.name if (cur_win != null and "name" in cur_win) else "none",
			best_win.name if (best_win != null and "name" in best_win) else "none",
			cd_count
		])
		lines.append("  overlap_ratio=%.3f threshold=%.3f" % [max_overlap_ratio, proxy_overlap_min_ratio])
	_debug_hud.text = "\n".join(lines)
	_debug_hud.visible = true


func _ensure_debug_hud() -> void:
	if _debug_root != null and is_instance_valid(_debug_root):
		return
	_debug_root = VBoxContainer.new()
	_debug_root.set_as_top_level(true)
	_debug_root.z_index = 3000
	_debug_root.modulate = Color(0.9, 1.0, 0.9, 0.95)
	_debug_root.position = Vector2(12, 12)
	_debug_root.visible = true

	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	_debug_hud = Label.new()
	_debug_hud.add_theme_font_size_override("font_size", 12)
	vb.add_child(_debug_hud)

	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "proxy overlap:" 
	hb.add_child(lbl)
	_proxy_slider = HSlider.new()
	_proxy_slider.min_value = 0.0
	_proxy_slider.max_value = 0.6
	_proxy_slider.step = 0.01
	_proxy_slider.value = proxy_overlap_min_ratio
	_proxy_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_proxy_slider)
	vb.add_child(hb)

	_proxy_slider.value_changed.connect(_on_proxy_ratio_changed)

	_debug_root.add_child(panel)
	get_tree().root.add_child.call_deferred(_debug_root)
#endregion

#region ---------- 过渡代理：创建/更新/移除 ----------

func _get_traveler_sprite_node(t: Node) -> Node:
	# 优先寻找 AnimatedSprite2D，其次 Sprite2D
	if t == null:
		return null
	var anim := t.find_child("AnimatedSprite2D", true, false)
	if anim != null:
		return anim
	var spr := t.find_child("Sprite2D", true, false)
	if spr != null:
		return spr
	return null

func _make_proxy_from_traveler(t: Node) -> Node2D:
	var src = _get_traveler_sprite_node(t)
	if src == null:
		return null
	
	# 检测旅行者的朝向
	var facing_right := true  # 默认朝右
	
	# 优先使用 heading 属性
	if "heading" in t:
		var heading = t.heading as Vector2
		facing_right = (heading.x >= 0)
	# 回退到速度逻辑
	elif "velocity" in t:
		var vel = t.velocity as Vector2
		if abs(vel.x) > 0.01:
			facing_right = (vel.x > 0)
	
	# 检测旅行者的 scale（用于自动应用大小）
	var traveler_scale := Vector2.ONE
	if t is Node2D:
		traveler_scale = (t as Node2D).scale
	
	# 获取精灵节点的父节点 scale（如果精灵在 Body 节点下）
	var sprite_parent_scale := Vector2.ONE
	if src.get_parent() is Node2D:
		sprite_parent_scale = (src.get_parent() as Node2D).scale
	
	# 获取精灵节点本身的 scale
	var sprite_scale := Vector2.ONE
	if src is Node2D:
		sprite_scale = (src as Node2D).scale
	
	if src is AnimatedSprite2D:
		var p := AnimatedSprite2D.new()
		var s := src as AnimatedSprite2D
		p.sprite_frames = s.sprite_frames
		p.animation = s.animation
		p.frame = s.frame
		p.playing = s.playing
		p.flip_h = s.flip_h
		p.flip_v = s.flip_v
		p.modulate = s.modulate
		# 应用旅行者、精灵父节点和精灵本身的 scale
		# 注意：如果精灵父节点（如 Body）已经通过 scale.x 负值实现了翻转，这里会自动继承
		p.scale = traveler_scale * sprite_parent_scale * sprite_scale
		return p
	elif src is Sprite2D:
		var p2 := Sprite2D.new()
		var s := src as Sprite2D
		p2.texture = s.texture
		# 以帧表驱动动画：hframes/vframes/frame/flip
		p2.hframes = s.hframes
		p2.vframes = s.vframes
		p2.frame = s.frame
		p2.flip_h = s.flip_h
		p2.flip_v = s.flip_v
		# 同步区域动画（若使用 atlas/region）
		p2.region_enabled = s.region_enabled
		p2.region_rect = s.region_rect
		p2.centered = s.centered
		p2.modulate = s.modulate
		# 应用旅行者、精灵父节点和精灵本身的 scale
		# 注意：如果精灵父节点（如 Body）已经通过 scale.x 负值实现了翻转，这里会自动继承
		p2.scale = traveler_scale * sprite_parent_scale * sprite_scale
		return p2
	return null

func _proxy_key_for_container(container) -> Variant:
	return container if container != null else "_world"

func _ensure_proxy(traveler: Node, container, create_if_missing: bool) -> Node2D:
	if traveler == null:
		return null
	if not transition_proxies.has(traveler):
		transition_proxies[traveler] = {}
	var key = _proxy_key_for_container(container)
	var inner: Dictionary = transition_proxies[traveler]
	if inner.has(key):
		var proxy = inner[key]
		if proxy != null and is_instance_valid(proxy):
			return proxy
		else:
			inner.erase(key)
	if not create_if_missing:
		return null
	var new_proxy := _make_proxy_from_traveler(traveler)
	if new_proxy == null:
		return null
	# 选择父级：子窗口或主世界
	if container != null and is_instance_valid(container):
		(container as Node).add_child(new_proxy)
	else:
		var parent := original_parent if original_parent != null else self
		parent.add_child(new_proxy)
	inner[key] = new_proxy
	return new_proxy

func _remove_proxy(traveler: Node, container) -> void:
	if traveler == null or not transition_proxies.has(traveler):
		return
	var key = _proxy_key_for_container(container)
	var inner: Dictionary = transition_proxies[traveler]
	if inner.has(key):
		var proxy = inner[key]
		if proxy != null and is_instance_valid(proxy):
			(proxy as Node).queue_free()
		inner.erase(key)
	if inner.size() == 0:
		transition_proxies.erase(traveler)

func _clear_all_proxies_for(traveler: Node) -> void:
	if traveler == null or not transition_proxies.has(traveler):
		return
	for key in transition_proxies[traveler].keys():
		var proxy = transition_proxies[traveler][key]
		if proxy != null and is_instance_valid(proxy):
			(proxy as Node).queue_free()
	transition_proxies.erase(traveler)

func _update_proxy_in_window(traveler: Node, win: Window) -> void:
	var proxy := _ensure_proxy(traveler, win, true)
	if proxy == null:
		return
	# 局部位置 = 旅行者屏幕原点 - 窗口 OS 原点
	var traveler_screen_origin := _get_node_screen_origin_os(traveler)
	var win_origin := _get_window_origin_screen(win)
	(proxy as Node2D).position = traveler_screen_origin - win_origin
	_sync_proxy_visual(traveler, proxy)

func _update_proxy_in_world(traveler: Node) -> void:
	var proxy := _ensure_proxy(traveler, null, true)
	if proxy == null:
		return
	# world_pos = inv(canvas) * (screen_pos - MainWindow.OSOrigin)
	var screen_pos := _get_node_screen_origin_os(traveler)
	var inv_tf := get_viewport().get_canvas_transform().affine_inverse()
	var world_pos := inv_tf * (screen_pos - Vector2(get_window().position))
	(proxy as Node2D).global_position = world_pos
	_sync_proxy_visual(traveler, proxy)

func _sync_proxy_visual(traveler: Node, proxy: Node2D) -> void:
	# 将代理的动画/帧与源贴图同步（AnimatedSprite2D 或 Sprite2D）。
	if traveler == null or proxy == null:
		return
	var src = _get_traveler_sprite_node(traveler)
	if src == null:
		return
	
	# 检测旅行者的 scale
	var traveler_scale := Vector2.ONE
	if traveler is Node2D:
		traveler_scale = (traveler as Node2D).scale
	
	# 获取精灵节点的父节点 scale
	var sprite_parent_scale := Vector2.ONE
	if src.get_parent() is Node2D:
		sprite_parent_scale = (src.get_parent() as Node2D).scale
	
	# 获取精灵节点本身的 scale
	var sprite_scale := Vector2.ONE
	if src is Node2D:
		sprite_scale = (src as Node2D).scale
	
	if src is AnimatedSprite2D and proxy is AnimatedSprite2D:
		var s := src as AnimatedSprite2D
		var p := proxy as AnimatedSprite2D
		# 同步关键播放属性
		p.animation = s.animation
		p.frame = s.frame
		p.playing = s.playing
		p.flip_h = s.flip_h
		p.flip_v = s.flip_v
		# 若源帧表发生变化，也一并同步
		if p.sprite_frames != s.sprite_frames:
			p.sprite_frames = s.sprite_frames
		# 同步 scale（旅行者 * 精灵父节点 * 精灵本身）
		# 注意：如果精灵父节点（如 Body）已经通过 scale.x 负值实现了翻转，这里会自动继承
		p.scale = traveler_scale * sprite_parent_scale * sprite_scale
			
	elif src is Sprite2D and proxy is Sprite2D:
		var s2 := src as Sprite2D
		var p2 := proxy as Sprite2D
		# 同步帧表动画参数
		p2.hframes = s2.hframes
		p2.vframes = s2.vframes
		p2.frame = s2.frame
		p2.flip_h = s2.flip_h
		p2.flip_v = s2.flip_v
		# 同步区域模式以兼容 atlas 驱动
		p2.region_enabled = s2.region_enabled
		p2.region_rect = s2.region_rect
		# 如纹理替换，也同步纹理
		if p2.texture != s2.texture:
			p2.texture = s2.texture
		# 同步 scale（旅行者 * 精灵父节点 * 精灵本身）
		# 注意：如果精灵父节点（如 Body）已经通过 scale.x 负值实现了翻转，这里会自动继承
		p2.scale = traveler_scale * sprite_parent_scale * sprite_scale

func _overlap_sufficient(a: Rect2, b: Rect2) -> bool:
	# 使用交叠面积占旅行者 AABB 面积的比例来决定是否生成代理，避免边缘轻微相交时闪烁。
	var inter := a.intersection(b)
	if inter == Rect2():
		return false
	var base_area := a.size.x * a.size.y
	if base_area <= 0.0:
		return false
	var inter_area := inter.size.x * inter.size.y
	var ratio := inter_area / base_area
	return ratio >= proxy_overlap_min_ratio

func _update_transition_proxies(traveler: Node, rect: Rect2, current_win: Window) -> void:
	# 计算需要的代理容器集合，然后清除多余的
	var needed: Array = []
	if current_win != null and is_instance_valid(current_win):
		# 对更高优先级窗口：部分相交（intersects 且 非 encloses）时在目标窗口显示代理
		var cur_pri :int= current_win.priority if ("priority" in current_win) else 0
		for win in managed_windows:
			if not is_instance_valid(win) or win == current_win:
				continue
			var wrect := _get_window_rect_screen(win)
			if wrect.intersects(rect) and not wrect.encloses(rect) and _overlap_sufficient(rect, wrect):
				var wpri := int(win.priority) if ("priority" in win) else 0
				if wpri > cur_pri:
					_update_proxy_in_window(traveler, win)
					needed.append(win)
			else:
				_remove_proxy(traveler, win)
		# 面向主世界的代理：当仍与当前窗口相交但不再被完全包围时（部分相交）
		var cur_rect := _get_window_rect_screen(current_win)
		if cur_rect.intersects(rect) and not cur_rect.encloses(rect) and _overlap_sufficient(rect, cur_rect):
			_update_proxy_in_world(traveler)
			needed.append(null) # 以 null 代表 world
		else:
			_remove_proxy(traveler, null)
	else:
		# 当前不在任何窗口：对所有相交但未完全包围的窗口生成代理
		for win in managed_windows:
			if not is_instance_valid(win):
				continue
			var wrect2 := _get_window_rect_screen(win)
			if wrect2.intersects(rect) and not wrect2.encloses(rect) and _overlap_sufficient(rect, wrect2):
				_update_proxy_in_window(traveler, win)
				needed.append(win)
			else:
				_remove_proxy(traveler, win)
		# 不需要世界代理
		_remove_proxy(traveler, null)

func _on_proxy_ratio_changed(value: float) -> void:
	proxy_overlap_min_ratio = clamp(value, 0.0, 1.0)
	if _proxy_slider != null:
		_proxy_slider.value = proxy_overlap_min_ratio
		
#endregion


#region 窗口进入与退出相关逻辑
func _check_all_windows_for_traveler(traveler: Node, camera_delta: Vector2) -> void:
	"""检查指定旅行者与所有窗口的交互（完美重合 + 优先级）"""
	# 初始化状态容器
	if not traveler_current_window.has(traveler):
		traveler_current_window[traveler] = null
	if not traveler_cooldowns.has(traveler):
		traveler_cooldowns[traveler] = {}

	var current_win: Window = traveler.get_parent() if traveler.get_parent() is DefaultWindow else traveler_current_window[traveler]
	var rect = _get_traveler_screen_rect(traveler)
	var best_win: Window = null
	var best_pri := -INF
	for win in managed_windows:
		if not is_instance_valid(win):
			continue
		if traveler_cooldowns[traveler].get(win, 0.0) > 0.0:
			continue
		# 检查窗口是否可穿越（进入动画期间不可穿越）
		if win.has_method("is_traversable") and not win.is_traversable():
			continue
		if win.visible == false:
			continue
		var wrect := _get_window_rect_screen(win)
		if wrect.size == Vector2.ZERO:
			continue
		if wrect.encloses(rect):
			var p := 0
			if "priority" in win:
				p = win.priority
			if p > best_pri:
				best_pri = p
				best_win = win

	# 在决定切换/进入前，先根据当前判定更新“部分相交”过渡代理
	_update_transition_proxies(traveler, rect, current_win)

	if current_win != null:
		var cur_rect := _get_window_rect_screen(current_win)
		# 检查当前窗口是否允许退出
		if current_win.has_method("is_exit_allowed") and not current_win.is_exit_allowed():
			# 窗口不允许退出，跳过退出逻辑
			return
		if current_win.visible == false:
			return
		if not cur_rect.intersects(rect):
			_clear_all_proxies_for(traveler)
			_exit_window_for_traveler(traveler, current_win, camera_delta)
			return
		# 只有当更高优先级窗口完全包含时才切换，禁止高->低切换
		if best_win != null and best_win != current_win:
			var cur_pri := 0
			if "priority" in current_win:
				cur_pri = current_win.priority
			if "priority" in best_win:
				best_pri = best_win.priority
			if best_pri > cur_pri:
				_clear_all_proxies_for(traveler)
				_exit_window_for_traveler(traveler, current_win, camera_delta)
				_enter_window_for_traveler(traveler, best_win)
			return
		return
	else:
		if best_win != null:
			_clear_all_proxies_for(traveler)
			_enter_window_for_traveler(traveler, best_win)


func _notify_window_enter(win: Window, traveler: Node) -> void:
	if win == null:
		return
	if win.has_method("on_traveler_enter"):
		win.on_traveler_enter(traveler)

func _notify_window_exit(win: Window, traveler: Node) -> void:
	if win == null:
		return
	if win.has_method("on_traveler_exit"):
		win.on_traveler_exit(traveler)

func _enter_window_for_traveler(traveler: Node, win: Window) -> void:
	if traveler == null:
		return
	_clear_all_proxies_for(traveler)
	
	# 获取旅行者当前的 OS 屏幕坐标
	var traveler_screen_origin := _get_node_screen_origin_os(traveler)
	
	# 获取目标窗口的 viewport 和 canvas 变换
	var win_viewport: Viewport = null
	var win_canvas_tf: Transform2D = Transform2D.IDENTITY
	var inv_win_canvas_tf: Transform2D = Transform2D.IDENTITY
	
	if win.is_inside_tree() and win.has_method("get_viewport"):
		var vp = win.call("get_viewport")
		if vp is Viewport:
			win_viewport = vp
			win_canvas_tf = win_viewport.get_canvas_transform()
			inv_win_canvas_tf = win_canvas_tf.affine_inverse()
	
	# 计算在窗口内的屏幕坐标（相对于窗口 OS 原点）
	var win_origin := Vector2(win.position)
	var screen_pos_in_win = traveler_screen_origin - win_origin
	
	# 通过逆 canvas 变换得到窗口内的世界坐标
	var local_pos = inv_win_canvas_tf * screen_pos_in_win
	
	var old_parent = traveler.get_parent()
	if old_parent != null:
		old_parent.remove_child(traveler)
	win.add_child(traveler)
	traveler.global_position = local_pos
	
	# 调用旅行者的窗口进入接口（如果有）
	if traveler.has_method("on_window_entered"):
		traveler.on_window_entered(win)
	
	_notify_window_enter(win, traveler)
	traveler_current_window[traveler] = win

func _exit_window_for_traveler(traveler: Node, win: Window, camera_delta: Vector2) -> void:
	if traveler == null:
		return
	_clear_all_proxies_for(traveler)
	
	# 获取窗口的 viewport 和 canvas 变换
	var win_viewport: Viewport = null
	var win_canvas_tf: Transform2D = Transform2D.IDENTITY
	
	if win.is_inside_tree() and win.has_method("get_viewport"):
		var vp = win.call("get_viewport")
		if vp is Viewport:
			win_viewport = vp
			win_canvas_tf = win_viewport.get_canvas_transform()
	
	# 如果无法获取窗口的 canvas 变换，使用简单的位置计算
	var screen_pos: Vector2
	if win_viewport != null:
		# 旅行者在窗口内的局部位置，通过 canvas 变换转换到屏幕坐标
		var screen_pos_in_win = win_canvas_tf * traveler.global_position
		# 加上窗口的 OS 原点得到 OS 屏幕坐标
		screen_pos = Vector2(win.position) + screen_pos_in_win
	else:
		# 备用方案：直接使用位置（假设无相机变换）
		screen_pos = Vector2(win.position) + traveler.position
	
	var old_parent = traveler.get_parent()
	if old_parent != null:
		old_parent.remove_child(traveler)
	if original_parent != null:
		original_parent.add_child(traveler)
	else:
		add_child(traveler)
	# 计算世界坐标：使用主窗口的 canvas 变换的逆变换
	var main_canvas_tf := get_viewport().get_canvas_transform()
	var inv_tf := main_canvas_tf.affine_inverse()
	var world_pos = inv_tf * (screen_pos - Vector2(get_window().position))
	traveler.global_position = world_pos
	
	# 调用旅行者的窗口退出接口（如果有）
	if traveler.has_method("on_window_exited"):
		traveler.on_window_exited(win)
	
	_notify_window_exit(win, traveler)
	if _is_window_movable(win):
		_push_window_out_of_safe_zone(win, camera_delta)
	if not traveler_cooldowns.has(traveler):
		traveler_cooldowns[traveler] = {}
	traveler_cooldowns[traveler][win] = cooldown_time
	traveler_current_window[traveler] = null


func _push_window_out_of_safe_zone(win: Window, camera_delta: Vector2) -> void:
	# 安全矩形（屏幕中心区域），基于主窗口实际屏幕尺寸
	if win.size < Vector2i(720,405):
		var screen_size :Vector2i= DisplayServer.screen_get_size()
		var safe_size :Vector2i= screen_size * safe_rect_ratio
		var safe_rect = Rect2((screen_size - safe_size) / 2.0, safe_size)

		var win_rect = Rect2(Vector2(win.position), win.size)
		if not win_rect.intersects(safe_rect):
			return

		var direction = -camera_delta
		if direction.length() < 0.001:
			direction = (win_rect.get_center() - safe_rect.get_center())
		if direction.length() < 0.001:
			direction = Vector2.RIGHT
		direction = direction.normalized()

		# 计算沿 direction 推出的最小距离，使窗口离开 safe_rect
		var t = _compute_push_t(win_rect, safe_rect, direction)
		var target_pos = win_rect.position + direction * t
		# 防止推到屏幕外，夹到屏幕范围内
		var clamped = Vector2(
			clamp(target_pos.x, 0.0, screen_size.x - win_rect.size.x),
			clamp(target_pos.y, 0.0, screen_size.y - win_rect.size.y)
		)
		var tween = create_tween()
		tween.tween_property(win, "position", Vector2i(clamped), 0.3)

func _on_request_push_out(win: Window) -> void:
	# 使用最近一次相机移动量反向推离安全区
	var camera_delta = camera.global_position - last_camera_pos
	_push_window_out_of_safe_zone(win, camera_delta)

func _on_request_force_exit(win: Window) -> void:
	# 接收到窗口强制退出请求时，仅驱逐当前窗口内的旅行者
	# 计算相机偏移量（如果相机存在且有效）
	var camera_delta := Vector2.ZERO
	if camera != null and is_instance_valid(camera):
		camera_delta = camera.global_position - last_camera_pos
	
	var occupants: Array = []
	for t in traveler_current_window.keys():
		if traveler_current_window[t] == win:
			occupants.append(t)
	
	# 检查所有旅行者，看是否有在窗口中但不在 traveler_current_window 中的
	var travelers: Array = get_tree().get_nodes_in_group(traveler_group)
	for t in travelers:
		if t != null and is_instance_valid(t) and t.get_parent() == win and not occupants.has(t):
			occupants.append(t)
	
	for t in occupants:
		if t == null or (t is Object and not is_instance_valid(t)):
			continue
		_exit_window_for_traveler(t, win, camera_delta)


func _on_window_close(win: Window) -> void:
	"""子窗口关闭：先驱逐所有旅行者，再播放退出动画，然后删除节点"""
	if win == null or not is_instance_valid(win):
		return
	
	# 立即断开信号连接，防止重复触发
	if win.transient == false && win.is_connected("close_requested", Callable(self, "_on_window_close")):
		win.disconnect("close_requested", Callable(self, "_on_window_close"))
	
	# 在窗口关闭前，先保存窗口的 viewport 和 canvas 变换信息
	var win_viewport: Viewport = null
	var win_canvas_tf: Transform2D = Transform2D.IDENTITY
	var win_position: Vector2 = Vector2(win.position)
	
	if win.is_inside_tree() and win.has_method("get_viewport"):
		var vp = win.call("get_viewport")
		if vp is Viewport:
			win_viewport = vp
			win_canvas_tf = win_viewport.get_canvas_transform()
	
	# 先记录占用者
	var occupants: Array = []
	for t in traveler_current_window.keys():
		if traveler_current_window[t] == win:
			occupants.append(t)
	
	# 检查所有旅行者，看是否有在窗口中但不在 traveler_current_window 中的
	var travelers: Array = get_tree().get_nodes_in_group(traveler_group)
	for t in travelers:
		if t != null and is_instance_valid(t) and t.get_parent() == win and not occupants.has(t):
			occupants.append(t)
	
	# 逐个传送回主世界（使用保存的变换信息）
	for t in occupants:
		if t == null or (t is Object and not is_instance_valid(t)):
			continue
		
		# 手动计算退出位置（不依赖窗口的 viewport）
		var screen_pos: Vector2
		if win_viewport != null and t is Node2D:
			# 使用保存的 canvas 变换
			var screen_pos_in_win = win_canvas_tf * (t as Node2D).global_position
			screen_pos = win_position + screen_pos_in_win
		elif t is Node2D:
			# 备用方案：直接使用位置
			screen_pos = win_position + (t as Node2D).position
		else:
			continue
		
		# 移除旅行者
		var old_parent = t.get_parent()
		if old_parent != null:
			old_parent.remove_child(t)
		if original_parent != null:
			original_parent.add_child.call_deferred(t)
		else:
			add_child(t)
		await original_parent.child_entered_tree
		# 计算世界坐标
		var main_canvas_tf := get_viewport().get_canvas_transform()
		var inv_tf := main_canvas_tf.affine_inverse()
		var world_pos = inv_tf * (screen_pos - Vector2(get_window().position))
		(t as Node2D).global_position = world_pos
		
		# 清理状态
		_clear_all_proxies_for(t)
		_notify_window_exit(win, t)
		if not traveler_cooldowns.has(t):
			traveler_cooldowns[t] = {}
		traveler_cooldowns[t][win] = cooldown_time
		traveler_current_window[t] = null
		
		# 如果是玩家，先发射 in_close_window 信号（在调用 on_window_closed 之前）
		if t == player and t.has_signal("in_close_window"):
			t.in_close_window.emit(win)
			DebugHelper.log("[WindowManager] 发射玩家 in_close_window 信号")
		
		# 调用旅行者的窗口关闭接口（如果有）
		if t.has_method("on_window_closed"):
			t.on_window_closed(win)
	
	# 所有旅行者驱逐完成后，播放退出动画
	if win.has_method("_play_exit_animation"):
		await win._play_exit_animation()
	
	# 处理子 transient 窗口：当父窗口关闭时，子 transient 窗口也应被移除
	for child in win.get_children():
		if child is Window and child.get_meta("is_transient", false):
			transient_windows.erase(child)
			var child_behavior = child.close_behavior if "close_behavior" in child else "delete"
			if child_behavior == "delete":
				child.queue_free()
			else:
				child.visible = false
	
	# 检查是否为 transient 窗口且关闭行为为隐藏
	if win.get_meta("is_transient", false):
		var behavior = win.close_behavior if "close_behavior" in win else "delete"
		if behavior == "hide":
			# 重置窗口到初始状态（恢复大小和位置）
			if win.has_method("_reset_to_initial_state"):
				win._reset_to_initial_state()
			
			win.visible = false
			# 从 transient 列表移除并更新输入阻塞
			if win in transient_windows:
				transient_windows.erase(win)
			return
	
	# 从管理列表中移除并断开信号
	if win in managed_windows:
		managed_windows.erase(win)
	window_entry_states.erase(win)
	# 如果是 transient 窗口，从列表移除并更新输入阻塞
	if win in transient_windows:
		transient_windows.erase(win)
	if _debug_labels.has(win):
		var lbl = _debug_labels[win]
		if is_instance_valid(lbl):
			lbl.queue_free()
		_debug_labels.erase(win)
	if _debug_dots.has(win):
		var dot = _debug_dots[win]
		if is_instance_valid(dot):
			dot.queue_free()
		_debug_dots.erase(win)
	# 删除窗口节点
	if win.popup_wm_hint:
		var tween = win.create_tween()
		tween.tween_property(win, "position", win.initial_pos, 0.5)
		tween.finished.connect(win.queue_free)
		return
	win.queue_free()
#endregion



func _pick_window_at(viewport_pos: Vector2) -> Window:
	# 将主窗口内的视口坐标转换为 OS 屏幕坐标以匹配窗口位置
	var screen_pos := Vector2(get_window().position) + viewport_pos
	# 遍历窗口，选择最后匹配的作为“顶层”
	for i in range(managed_windows.size() - 1, -1, -1):
		var win: DefaultWindow = managed_windows[i]
		if not is_instance_valid(win):
			continue
		var rect := _get_window_rect_screen(win)
		if rect.has_point(screen_pos):
			return win
	return null





func _get_window_rect_screen(win: Window) -> Rect2:
	# OS 屏幕矩形：用于拾取、安全区推离等 OS 相关逻辑
	if win == null or not is_instance_valid(win):
		return Rect2()
	return Rect2(Vector2(win.position), win.size)

func _get_window_origin_screen(win: Window) -> Vector2:
	if win == null or not is_instance_valid(win):
		return Vector2.ZERO
	return Vector2(win.position)

## 已改为纯屏幕坐标(OS)方案：以下“有效坐标(世界)”相关函数已移除


func _compute_push_t(win_rect: Rect2, safe_rect: Rect2, dir: Vector2) -> float:
	var candidates: Array[float] = []
	if dir.x > 0.001:
		candidates.append((safe_rect.position.x + safe_rect.size.x - win_rect.position.x) / dir.x)
	elif dir.x < -0.001:
		candidates.append((safe_rect.position.x - (win_rect.position.x + win_rect.size.x)) / dir.x)
	if dir.y > 0.001:
		candidates.append((safe_rect.position.y + safe_rect.size.y - win_rect.position.y) / dir.y)
	elif dir.y < -0.001:
		candidates.append((safe_rect.position.y - (win_rect.position.y + win_rect.size.y)) / dir.y)

	var t = 0.0
	for c in candidates:
		if c > t:
			t = c
	# 加一点余量，确保不再相交
	return t + 1.0


func _is_window_movable(win: Window) -> bool:
	# 判定窗口是否可移动：非嵌入 + 窗口化模式
	var embedded := false
	if win.has_method("is_window_embedded"):
		embedded = win.is_window_embedded()
	if embedded:
		return false
	# Godot Window 可移动通常在 MODE_WINDOWED，下述判定可按需调整
	return win.mode == Window.MODE_WINDOWED

#region 计算相关方法
func _get_player_screen_rect() -> Rect2:
	"""获取玩家在屏幕(OS)上的碰撞矩形（考虑相机 zoom/rotation）。"""
	if player == null:
		return Rect2()

	# 统一使用穿梭者的矩形计算
	return _get_traveler_screen_rect(player)


##获得任意 CanvasItem 在 OS 屏幕坐标中的坐标原点
func _get_node_screen_origin_os(node: Node) -> Vector2:
	"""获取任意 CanvasItem 在 OS 屏幕坐标中的原点（考虑相机变换）。
	逻辑：origin_screen_os = host_window.OS_origin + canvas_transform * node.global_position
	其中 canvas_transform 包含了相机的 zoom/rotation/offset 变换。
	"""
	if node == null or not (node is CanvasItem):
		return Vector2.ZERO
	var ci: CanvasItem = node
	
	# 查找宿主窗口和对应的 viewport
	var host_window: Window = get_window()
	var host_viewport: Viewport = get_viewport()
	var n: Node = ci
	while n != null:
		if n is DefaultWindow:
			host_window = n as DefaultWindow
			# 获取窗口的 viewport（如果窗口在场景树中）
			if host_window.is_inside_tree() and host_window.has_method("get_viewport"):
				var vp = host_window.call("get_viewport")
				if vp is Viewport:
					host_viewport = vp
			break
		n = n.get_parent()
	
	# 获取该 viewport 的 canvas 变换（包含相机效果）
	var canvas_tf: Transform2D = Transform2D.IDENTITY
	if host_viewport != null:
		canvas_tf = host_viewport.get_canvas_transform()
	
	# 将节点的全局位置通过 canvas 变换转换到屏幕坐标
	var screen_pos: Vector2 = canvas_tf * ci.global_position
	
	# 加上宿主窗口的 OS 原点
	var host_origin_os: Vector2 = Vector2(host_window.position)
	return host_origin_os + screen_pos


func _get_traveler_screen_rect(traveler: Node) -> Rect2:
	"""获取旅行者在 OS 屏幕坐标中的碰撞矩形（AABB），
	考虑所有 2D 变换（包含相机 zoom/rotation 和节点自身旋转缩放）。
	通过 CollisionShape2D 的四角点经过 canvas 变换计算屏幕位置并取包围盒。
	若无碰撞形状，退化为以节点为中心的 32x32 矩形。
	"""
	if traveler == null or not (traveler is Node2D):
		return Rect2()
	var t2d: Node2D = traveler
	
	# 查找宿主窗口和对应的 viewport
	var host_window: Window = get_window()
	var host_viewport: Viewport = get_viewport()
	var n: Node = t2d
	while n != null:
		if n is DefaultWindow:
			host_window = n as DefaultWindow
			# 获取窗口的 viewport（如果窗口在场景树中）
			if host_window.is_inside_tree() and host_window.has_method("get_viewport"):
				var vp = host_window.call("get_viewport")
				if vp is Viewport:
					host_viewport = vp
			break
		n = n.get_parent()
	
	# 获取该 viewport 的 canvas 变换（包含相机效果）
	var canvas_tf: Transform2D = Transform2D.IDENTITY
	if host_viewport != null:
		canvas_tf = host_viewport.get_canvas_transform()
	var host_os: Vector2 = Vector2(host_window.position)

	# 选择用于计算的节点（优先 CollisionShape2D）
	var shape_node: Node2D = t2d
	var collision_shape = t2d.get_node_or_null("CollisionShape2D")
	var size := Vector2(32, 32)
	var shape_type := "none"
	if collision_shape != null and collision_shape is CollisionShape2D and (collision_shape as CollisionShape2D).shape != null:
		shape_node = collision_shape as Node2D
		var shape = (collision_shape as CollisionShape2D).shape
		if shape is RectangleShape2D:
			size = shape.size
			shape_type = "rect"
		elif shape is CircleShape2D:
			size = Vector2((shape as CircleShape2D).radius * 2, (shape as CircleShape2D).radius * 2)
			shape_type = "circle"
		elif shape is CapsuleShape2D:
			size = Vector2((shape as CapsuleShape2D).radius * 2, (shape as CapsuleShape2D).height)
			shape_type = "capsule"

	# 组装局部空间的采样点
	var pts: Array[Vector2] = []
	if shape_type == "rect" or shape_type == "capsule":
		var hx = size.x * 0.5
		var hy = size.y * 0.5
		pts = [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]
	else:
		# circle 或未知：四向采样近似
		var r = max(size.x, size.y) * 0.5
		pts = [Vector2(-r, 0), Vector2(r, 0), Vector2(0, -r), Vector2(0, r)]

	# 将局部点变换到全局坐标，然后通过 canvas 变换到屏幕坐标
	var shape_global_tf: Transform2D = shape_node.global_transform
	var minp = Vector2(INF, INF)
	var maxp = Vector2(-INF, -INF)
	for p in pts:
		# 先变换到世界坐标
		var world_pos = shape_global_tf * p
		# 再通过 canvas 变换到屏幕坐标
		var screen_pos = canvas_tf * world_pos
		# 加上宿主窗口的 OS 原点
		var pos_os = host_os + screen_pos
		minp.x = min(minp.x, pos_os.x)
		minp.y = min(minp.y, pos_os.y)
		maxp.x = max(maxp.x, pos_os.x)
		maxp.y = max(maxp.y, pos_os.y)
	return Rect2(minp, maxp - minp)
#endregion

func _has_active_camera() -> bool:
	return camera != null and camera.is_inside_tree()

func _on_window_geometry_changed(win: Window) -> void:
	# 仅针对变动的这个窗口，逐个穿越者做单窗判定，降低开销
	if win == null or not is_instance_valid(win):
		return
	var wrect := _get_window_rect_screen(win)
	var wrect_grown := wrect.grow(geometry_recheck_margin)
	var travelers := get_tree().get_nodes_in_group("traveler_group")
	for t in travelers:
		if t == null or not is_instance_valid(t):
			continue
		# 当前所在窗口（优先使用父节点判断以兼容嵌入）
		var current_win: Window = t.get_parent() if t.get_parent() is DefaultWindow else traveler_current_window.get(t, null)
		# 若旅行者当前就在此窗口，必须重判；否则仅在靠近该窗口边缘（扩大矩形相交）时才重判
		if current_win == win:
			_recheck_traveler_vs_window(t, win)
		else:
			var trect := _get_traveler_screen_rect(t)
			if wrect_grown.intersects(trect):
				_recheck_traveler_vs_window(t, win)

func _recheck_traveler_vs_window(traveler: Node, win: Window) -> void:
	if traveler == null or win == null:
		return
	if not traveler_current_window.has(traveler):
		traveler_current_window[traveler] = null
	if not traveler_cooldowns.has(traveler):
		traveler_cooldowns[traveler] = {}
	var rect := _get_traveler_screen_rect(traveler)
	var wrect := _get_window_rect_screen(win)
	if wrect.size == Vector2.ZERO:
		return
	# 当前所在窗口（优先使用父节点判断以兼容嵌入）
	var current_win: Window = traveler.get_parent() if traveler.get_parent() is DefaultWindow else traveler_current_window[traveler]
	# 如果当前就在此窗口，检查是否需要退出
	if current_win == win:
		if not wrect.intersects(rect):
			_exit_window_for_traveler(traveler, win, Vector2.ZERO)
		return
	# 非当前窗口：若不在冷却且该窗口完美包含，则按优先级执行进入/切换
	if traveler_cooldowns[traveler].get(win, 0.0) > 0.0:
		return
	if wrect.encloses(rect):
		if current_win == null:
			_enter_window_for_traveler(traveler, win)
			return
		# 仅允许低->高优先级切换
		var cur_pri := 0
		var new_pri := 0
		if "priority" in current_win:
			cur_pri = current_win.priority
		if "priority" in win:
			new_pri = win.priority
		if new_pri > cur_pri:
			_exit_window_for_traveler(traveler, current_win, Vector2.ZERO)
			_enter_window_for_traveler(traveler, win)
