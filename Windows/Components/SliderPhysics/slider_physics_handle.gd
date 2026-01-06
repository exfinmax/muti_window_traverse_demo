class_name SliderPhysicsHandle
extends Node2D

## Handles physics interaction for a single slider.
##
## This component creates a collision detection zone around a slider's handle
## and manages player interactions including pushing and blocking mechanics.

# Signals
signal handle_pushed(old_value: float, new_value: float)
signal handle_blocked()
signal handle_released()

# Properties
var slider: Slider  # Changed from HSlider to support both HSlider and VSlider
var collision_area: Area2D
var collision_shape: CollisionShape2D
var shape_rect: RectangleShape2D
var player_ref: Player = null
var is_player_colliding: bool = false
var player_last_position: Vector2 = Vector2.ZERO
var is_blocking: bool = false
var visual_feedback: ColorRect = null
var feedback_tween: Tween = null

# Velocity tracking for blocking detection
var velocity_history: Array[Vector2] = []
const VELOCITY_HISTORY_SIZE: int = 5  # Track last 5 frames

# Blocking state
var blocked_value: float = 0.0  # The value where blocking started
var original_value_changed_connection: Callable

# Configuration
@export var push_sensitivity: float = 1.0
@export var block_threshold: float = 2  # pixels per frame
@export var handle_padding: Vector2 = Vector2(4, 4)

# Constants for handle geometry
const DEFAULT_HANDLE_WIDTH: float = 20.0
const POSITION_TOLERANCE: float = 2.0


func _ready() -> void:
	# Create collision area
	collision_area = Area2D.new()
	collision_area.name = "CollisionArea"
	collision_area.collision_layer = 0
	collision_area.collision_mask = 2  # Layer 2 is player
	collision_area.monitoring = false  # Start disabled
	add_child(collision_area)
	
	# Create collision shape
	collision_shape = CollisionShape2D.new()
	collision_shape.name = "CollisionShape"
	shape_rect = RectangleShape2D.new()
	collision_shape.shape = shape_rect
	collision_area.add_child(collision_shape)
	
	# Create visual feedback
	visual_feedback = ColorRect.new()
	visual_feedback.name = "VisualFeedback"
	visual_feedback.color = Color(0, 1, 0, 0)  # Transparent green initially
	visual_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual_feedback)
	
	# Connect signals - use body_entered/exited for CharacterBody2D (Player)
	collision_area.body_entered.connect(_on_body_entered)
	collision_area.body_exited.connect(_on_body_exited)


func setup(target_slider: Slider, player: Player) -> void:
	"""Initialize the handle with a target slider and player reference."""
	slider = target_slider
	player_ref = player
	
	DebugHelper.success("[SliderPhysics] Setup handle for slider: %s" % slider.name)
	
	# Connect to slider value changes to update collision shape
	if slider and not slider.value_changed.is_connected(_on_slider_value_changed):
		slider.value_changed.connect(_on_slider_value_changed)
	
	# Initial collision shape update
	update_collision_shape()


func _process(delta: float) -> void:
	if is_player_colliding and player_ref:
		process_player_interaction(delta)


func update_collision_shape() -> void:
	"""Update the collision shape to match the slider handle position."""
	if not slider or not collision_shape or not shape_rect:
		return
	
	var handle_rect = get_handle_rect()
	
	# Update shape size
	shape_rect.size = handle_rect.size + handle_padding * 2
	
	# Update shape position (center of the handle)
	var handle_center = handle_rect.position + handle_rect.size / 2.0
	collision_shape.position = handle_center
	
	# Update visual feedback
	if visual_feedback:
		visual_feedback.position = handle_rect.position - handle_padding
		visual_feedback.size = handle_rect.size + handle_padding * 2


func get_handle_rect() -> Rect2:
	"""Calculate the handle rectangle based on slider value and size."""
	if not slider:
		return Rect2()
	
	var slider_rect = slider.get_rect()
	var handle_width = DEFAULT_HANDLE_WIDTH
	var handle_height = slider_rect.size.y
	
	# Calculate handle x position based on slider value
	var value_ratio = 0.0
	if slider.max_value != slider.min_value:
		value_ratio = (slider.value - slider.min_value) / (slider.max_value - slider.min_value)
	
	var usable_width = slider_rect.size.x - handle_width
	var handle_x = value_ratio * usable_width
	
	return Rect2(
		Vector2(handle_x, 0),
		Vector2(handle_width, handle_height)
	)


func get_handle_center() -> Vector2:
	"""Get the center position of the slider handle."""
	var rect = get_handle_rect()
	return rect.position + rect.size / 2.0


func _on_body_entered(body: Node2D) -> void:
	"""Handle when a body enters the collision zone."""
	DebugHelper.info("[SliderPhysics] Body entered: %s (type: %s)" % [body.name, body.get_class()])
	
	# Check if this body is the player
	if body is Player:
		is_player_colliding = true
		player_last_position = player_ref.global_position if player_ref else Vector2.ZERO
		DebugHelper.success("[SliderPhysics] Player collision started with slider: %s" % slider.name)
		update_visual_feedback()
	else:
		DebugHelper.warning("[SliderPhysics] Body entered but not player: %s (type: %s)" % [body.name, body.get_class()])


func _on_body_exited(body: Node2D) -> void:
	"""Handle when a body exits the collision zone."""
	DebugHelper.info("[SliderPhysics] Body exited: %s" % body.name)
	
	# Check if this body is the player
	if body is Player:
		is_player_colliding = false
		# Disconnect blocking handler if connected
		if is_blocking and slider and slider.value_changed.is_connected(_on_slider_value_changed_blocking):
			slider.value_changed.disconnect(_on_slider_value_changed_blocking)
		is_blocking = false
		velocity_history.clear()  # Clear velocity history when player exits
		DebugHelper.success("[SliderPhysics] Player collision ended with slider: %s" % slider.name)
		handle_released.emit()
		update_visual_feedback()
	else:
		DebugHelper.warning("[SliderPhysics] Body exited but not player: %s" % body.name)


func process_player_interaction(delta: float) -> void:
	"""Process player interaction with the slider handle."""
	if not player_ref or not slider:
		return
	
	# Calculate player velocity for blocking detection
	var current_position = player_ref.global_position
	var player_velocity = (current_position - player_last_position) / delta if delta > 0 else Vector2.ZERO
	player_last_position = current_position
	
	# Add velocity to history
	velocity_history.append(player_velocity)
	if velocity_history.size() > VELOCITY_HISTORY_SIZE:
		velocity_history.pop_front()
	
	# Check if player is blocking (stationary over multiple frames)
	if check_blocking():
		if not is_blocking:
			is_blocking = true
			blocked_value = slider.value
			# Connect to value_changed to intercept external changes
			if not slider.value_changed.is_connected(_on_slider_value_changed_blocking):
				slider.value_changed.connect(_on_slider_value_changed_blocking, CONNECT_DEFERRED)
			handle_blocked.emit()
			update_visual_feedback()
	else:
		if is_blocking:
			is_blocking = false
			# Disconnect blocking handler
			if slider.value_changed.is_connected(_on_slider_value_changed_blocking):
				slider.value_changed.disconnect(_on_slider_value_changed_blocking)
			update_visual_feedback()
		
		# Calculate and apply push based on player position (not velocity)
		# This makes the slider smoothly follow the player
		var push_amount = calculate_push_amount(player_velocity)
		if abs(push_amount) > 0.0001:  # Lower threshold for smoother movement
			apply_push(push_amount)


func calculate_push_amount(_player_velocity: Vector2) -> float:
	"""Calculate the push amount based on player position.
	
	The slider smoothly follows the player's position when colliding.
	"""
	if not slider or not player_ref:
		return 0.0
	
	# Get player position in slider value space
	var player_value = get_player_position_in_slider_space()
	
	# Calculate difference between current slider value and player position
	var value_difference = player_value - slider.value
	
	# Apply smooth follow factor for gradual movement
	# The slider will gradually move towards the player's position
	var push_amount = value_difference * 0.15 * push_sensitivity
	
	return push_amount


func apply_push(amount: float) -> void:
	"""Apply push force to the slider."""
	if not slider:
		return
	
	var old_value = slider.value
	var new_value = old_value + amount
	
	# Clamp to slider bounds
	new_value = clamp(new_value, slider.min_value, slider.max_value)
	
	# Respect step value
	if slider.step > 0:
		new_value = round(new_value / slider.step) * slider.step
	
	# Update slider value
	if abs(new_value - old_value) > 0.0001:
		slider.value = new_value
		DebugHelper.info("[SliderPhysics] Pushed slider '%s': %.2f -> %.2f (delta: %.2f)" % [slider.name, old_value, new_value, amount])
		handle_pushed.emit(old_value, new_value)


func check_blocking() -> bool:
	"""Check if the player is stationary enough to block the slider.
	
	Returns true if the average velocity over the last few frames is below the threshold.
	"""
	if velocity_history.is_empty():
		return false
	
	# Calculate average velocity magnitude over history
	var total_magnitude: float = 0.0
	for vel in velocity_history:
		total_magnitude += vel.length()
	
	var avg_magnitude = total_magnitude / velocity_history.size()
	
	var is_blocking_now = avg_magnitude < block_threshold
	
	# Log blocking state changes
	if is_blocking_now and not is_blocking:
		DebugHelper.warning("[SliderPhysics] Player blocking slider '%s' (avg velocity: %.2f < %.2f)" % [slider.name, avg_magnitude, block_threshold])
	
	return is_blocking_now


func update_visual_feedback() -> void:
	"""Update the visual feedback based on interaction state."""
	if not visual_feedback:
		return
	
	# Cancel any existing tween
	if feedback_tween:
		feedback_tween.kill()
	
	# Create new tween for smooth transitions
	feedback_tween = create_tween()
	feedback_tween.set_ease(Tween.EASE_OUT)
	feedback_tween.set_trans(Tween.TRANS_CUBIC)
	
	var target_color: Color
	
	if is_blocking:
		# Red tint for blocking
		target_color = Color(1, 0, 0, 0.3)
	elif is_player_colliding:
		# Green tint for collision
		target_color = Color(0, 1, 0, 0.3)
	else:
		# Fade out when player exits
		target_color = Color(0, 1, 0, 0)
	
	# Animate color transition
	feedback_tween.tween_property(visual_feedback, "color", target_color, 0.2)


func _on_slider_value_changed(_value: float) -> void:
	"""Handle slider value changes to update collision shape."""
	update_collision_shape()


func _on_slider_value_changed_blocking(new_value: float) -> void:
	"""Handle slider value changes during blocking to prevent pass-through.
	
	This is called when external code tries to change the slider value while
	the player is blocking. We clamp the value to not pass through the player.
	"""
	if not is_blocking or not slider or not player_ref:
		return
	
	# Calculate player position in slider value space
	var player_value = get_player_position_in_slider_space()
	
	# Clamp the value to not pass through the player
	# The player blocks movement in both directions from their position
	var clamped_value = new_value
	
	# Calculate the direction of attempted movement
	var movement_direction = new_value - blocked_value
	
	if abs(movement_direction) > 0.001:
		# If trying to move past the player, clamp to player position
		if movement_direction > 0 and new_value > player_value:
			clamped_value = player_value
		elif movement_direction < 0 and new_value < player_value:
			clamped_value = player_value
	
	# Apply the clamped value if different
	if abs(clamped_value - new_value) > 0.001:
		# Temporarily disconnect to avoid recursion
		slider.value_changed.disconnect(_on_slider_value_changed_blocking)
		slider.value = clamped_value
		slider.value_changed.connect(_on_slider_value_changed_blocking, CONNECT_DEFERRED)


func get_player_position_in_slider_space() -> float:
	"""Calculate the player's position as a slider value.
	
	Converts the player's global position to a value in the slider's min/max range.
	"""
	if not slider or not player_ref:
		return slider.value if slider else 0.0
	
	# Get player position relative to slider
	var slider_global_pos = slider.global_position
	var player_global_pos = player_ref.global_position
	var relative_pos = player_global_pos - slider_global_pos
	
	# Determine if vertical or horizontal slider
	var is_vertical = slider is VSlider
	
	# Get the relevant position component
	var position_component = relative_pos.y if is_vertical else relative_pos.x
	var slider_dimension = slider.size.y if is_vertical else slider.size.x
	
	# Convert position to value ratio
	var position_ratio = position_component / slider_dimension if slider_dimension > 0 else 0.0
	
	# For vertical sliders, invert the ratio (top = min, bottom = max)
	if is_vertical:
		position_ratio = 1.0 - position_ratio
	
	# Convert ratio to slider value
	var value_range = slider.max_value - slider.min_value
	var player_value = slider.min_value + (position_ratio * value_range)
	
	# Clamp to slider bounds
	return clamp(player_value, slider.min_value, slider.max_value)


func enable_monitoring(enable: bool) -> void:
	"""Enable or disable collision monitoring."""
	if collision_area:
		collision_area.monitoring = enable


func cleanup() -> void:
	"""Clean up resources and disconnect signals."""
	# Kill any active tween
	if feedback_tween:
		feedback_tween.kill()
		feedback_tween = null
	
	if slider:
		if slider.value_changed.is_connected(_on_slider_value_changed):
			slider.value_changed.disconnect(_on_slider_value_changed)
		if slider.value_changed.is_connected(_on_slider_value_changed_blocking):
			slider.value_changed.disconnect(_on_slider_value_changed_blocking)
	
	queue_free()
