class_name ProgressBarPhysicsComponent
extends WindowComponent

## 进度条物理碰撞组件
## 自动为窗口中所有可见的进度条添加物理碰撞
## 碰撞箱大小动态跟随进度条的进度变化

class ProgressBarCollider:
	var progress_bar: ProgressBar
	var collision_body: StaticBody2D
	var collision_shape: CollisionShape2D
	var rect_shape: RectangleShape2D

var colliders: Array[ProgressBarCollider] = []
var update_interval: float = 0.1  # 更新间隔（秒）
var update_timer: float = 0.0

func _on_component_ready() -> void:
	_find_and_setup_progress_bars()

func _find_and_setup_progress_bars() -> void:
	"""递归查找所有 ProgressBar 并为可见的创建碰撞体"""
	var progress_bars = _find_all_progress_bars(window)
	
	for pb in progress_bars:
		if pb.visible:
			_create_collider_for_progress_bar(pb)
	
	DebugHelper.log("ProgressBarPhysicsComponent: Found and setup %d progress bars in window '%s'" % [colliders.size(), window.title])

func _find_all_progress_bars(node: Node) -> Array:
	"""递归查找所有 ProgressBar 节点"""
	var result = []
	
	if node is ProgressBar:
		result.append(node)
	
	for child in node.get_children():
		result.append_array(_find_all_progress_bars(child))
	
	return result

func _create_collider_for_progress_bar(pb: ProgressBar) -> void:
	"""为进度条创建碰撞体"""
	var collider = ProgressBarCollider.new()
	collider.progress_bar = pb
	
	# 创建 StaticBody2D
	collider.collision_body = StaticBody2D.new()
	collider.collision_body.name = "ProgressBarCollider_%s" % pb.name
	
	# 创建 CollisionShape2D
	collider.collision_shape = CollisionShape2D.new()
	collider.rect_shape = RectangleShape2D.new()
	collider.collision_shape.shape = collider.rect_shape
	
	# 添加到场景树
	collider.collision_body.add_child(collider.collision_shape)
	pb.add_child(collider.collision_body)
	
	# 初始更新
	_update_collider(collider)
	
	colliders.append(collider)
	
	DebugHelper.log("ProgressBarPhysicsComponent: Created collider for progress bar '%s'" % pb.name)

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_all_colliders()

func _update_all_colliders() -> void:
	"""更新所有碰撞体"""
	for collider in colliders:
		if not collider.progress_bar or not is_instance_valid(collider.progress_bar):
			continue
			
		if collider.progress_bar.visible:
			_update_collider(collider)
			if collider.collision_body:
				collider.collision_body.visible = true
		else:
			if collider.collision_body:
				collider.collision_body.visible = false

func _update_collider(collider: ProgressBarCollider) -> void:
	"""更新单个碰撞体的大小和位置"""
	var pb = collider.progress_bar
	
	# 计算进度百分比
	var progress_ratio = 0.0
	if pb.max_value > pb.min_value:
		progress_ratio = (pb.value - pb.min_value) / (pb.max_value - pb.min_value)
	
	# 获取进度条的大小
	var pb_size = pb.size
	
	# 判断是垂直还是水平进度条
	var is_vertical = pb_size.y > pb_size.x
	
	# 获取填充模式（如果有的话）
	var fill_mode = 0  # 默认：Begin to End
	if pb.has_method("get_fill_mode"):
		fill_mode = pb.get_fill_mode()
	
	if is_vertical:
		# 垂直进度条
		var height = pb_size.y * progress_ratio
		collider.rect_shape.size = Vector2(pb_size.x, height)
		
		if fill_mode == 3:  # Bottom to Top
			collider.collision_body.position = Vector2(0, pb_size.y - height)
		else:  # Top to Bottom (默认)
			collider.collision_body.position = Vector2(0, 0)
	else:
		# 水平进度条
		var width = pb_size.x * progress_ratio
		collider.rect_shape.size = Vector2(width, pb_size.y)
		
		if fill_mode == 1:  # End to Begin (右到左)
			collider.collision_body.position = Vector2(pb_size.x - width, 0)
		else:  # Begin to End (左到右，默认)
			collider.collision_body.position = Vector2(0, 0)
	
	# 设置碰撞形状的中心点
	collider.collision_shape.position = collider.rect_shape.size / 2

func on_window_closed() -> void:
	"""窗口关闭时清理所有碰撞体"""
	for collider in colliders:
		if collider.collision_body and is_instance_valid(collider.collision_body):
			collider.collision_body.queue_free()
	
	colliders.clear()
	DebugHelper.log("ProgressBarPhysicsComponent: Cleaned up all colliders")
