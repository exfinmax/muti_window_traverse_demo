class_name Player
extends CharacterBody2D

signal entered_window(win:DefaultWindow)
signal exited_window(win:DefaultWindow)

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

func _ready() -> void:
	add_to_group("player")
	add_to_group("portal_travelers")

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	if Input.is_action_just_pressed("spawn_window"):
		var manager :WindowManager= get_tree().get_first_node_in_group("window_manager")
		manager.spawn_window_ahead_of(self)
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func on_window_entered(_window: Window) -> void:
	"""窗口进入接口 - 当玩家进入窗口时调用"""
	# 发送进入窗口信号
	entered_window.emit(_window)
	
	# 暂停相机跟随
	var camera_out = get_tree().get_root().get_viewport().get_camera_2d()
	var camera_in = get_viewport().get_camera_2d()
	if camera_in != null:
		camera_in.resume_following()
	if camera_out != null and camera_out.has_method("pause_following"):
		camera_out.pause_following()
	
	DebugHelper.log("Player entered window, camera paused")

func on_window_exited(_window: DefaultWindow) -> void:
	"""窗口退出接口 - 当玩家退出窗口时调用"""
	# 发送退出窗口信号
	exited_window.emit(_window)
	
	# 恢复相机跟随
	var embedded = _window.is_window_embedded()
	var camera_out = get_viewport().get_camera_2d()
	var camera_in = _window.get_viewport().get_camera_2d()
	if camera_in != null:
		camera_in.pause_following()
	if camera_out != null:
		if embedded:
			# 嵌入窗口：立即恢复相机
			if camera_out.has_method("resume_following"):
				camera_out.resume_following()
		else:
			# 非嵌入窗口：延迟恢复相机
			var wm = get_tree().get_first_node_in_group("window_manager")
			var delay = 2.0
			if wm != null and wm.has_meta("camera_resume_delay"):
				delay = wm.get_meta("camera_resume_delay")
			
			if camera_out.has_method("resume_following_after"):
				camera_out.resume_following_after(delay)
			else:
				camera_out.resume_following()
	
	# 触发退出对话（使用fake_screen的方法）
	
	DebugHelper.log("Player exited window, camera resumed (embedded=%s)" % embedded)
