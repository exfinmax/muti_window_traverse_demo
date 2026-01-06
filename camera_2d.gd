extends Camera2D


@export var player:Node2D
@export var in_sub_window: bool
var is_following: bool = true  # 控制是否跟随玩家
var last_position: Vector2  # 记录玩家离开主窗口时的位置
var follow_resume_time: float = 0.0  # 延迟恢复跟随的计时器（秒）




# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# 检查玩家是否存在且有效
	if player == null or not is_instance_valid(player):
		return
	
	if follow_resume_time > 0.0:
		follow_resume_time -= delta
		if follow_resume_time <= 0.0:
			is_following = true

	if is_following:
		# 跟随玩家
		global_position = global_position.lerp(player.global_position, delta * 5)
		last_position = player.global_position
	# 如果不跟随，保持在 last_position（玩家离开主窗口前的位置）
	if in_sub_window:
		limit_bottom = get_window().size.y


func pause_following() -> void:
	"""玩家进入子窗口时调用"""
	is_following = false
	follow_resume_time = 0.0


func resume_following() -> void:
	"""玩家回到主窗口时调用"""
	is_following = true

func resume_following_after(seconds: float) -> void:
	"""在若干秒后恢复相机跟随"""
	is_following = false
	follow_resume_time = seconds
