extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

var _spawn_down := false


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

	# 技能：Q 生成一个 100x100 的窗口（优先级 3），位于前方
	var pressed := Input.is_key_pressed(KEY_Q)
	if pressed and not _spawn_down:
		var mgr := get_tree().get_first_node_in_group("window_manager")
		if mgr != null and mgr.has_method("spawn_window_ahead_of"):
			mgr.spawn_window_ahead_of(self)
	_spawn_down = pressed
