class_name AudioSliderPhysicsHandle
extends SliderPhysicsHandle

## Specialized slider physics handle for audio player music slider.
##
## This extends SliderPhysicsHandle to add special handling for the audio player's
## music progress slider. It connects slider value changes to audio playback position
## and blocks automatic playback progress updates when the player is interacting.

# Reference to the audio player control
var audio_player_control: Control = null
var audio_stream_player: AudioStreamPlayer = null

# Track if we're blocking automatic progress updates
var is_blocking_progress: bool = false

# Store the original is_dragging state
var original_is_dragging: bool = false


func setup_audio_slider(target_slider: Slider, player: Player, audio_control: Control) -> void:
	"""Initialize the audio slider handle with audio player references.
	
	Args:
		target_slider: The music slider control
		player: The player character
		audio_control: The audio player control script
	"""
	# Call parent setup
	setup(target_slider, player)
	
	# Store audio player references
	audio_player_control = audio_control
	
	# Find the AudioStreamPlayer
	if audio_control:
		audio_stream_player = audio_control.get_node_or_null("%AudioStreamPlayer")
		if not audio_stream_player:
			push_warning("[AudioSliderPhysicsHandle] Could not find AudioStreamPlayer in audio player")


func _on_body_entered(body: Node2D) -> void:
	"""Handle when player enters the collision zone."""
	# Call parent implementation
	super._on_body_entered(body)
	
	# Block automatic progress updates
	if is_player_colliding and audio_player_control:
		is_blocking_progress = true
		# Set the audio player's is_dragging flag to prevent automatic updates
		if audio_player_control.has_method("set") and "is_dragging" in audio_player_control:
			original_is_dragging = audio_player_control.is_dragging
			audio_player_control.is_dragging = true


func _on_body_exited(body: Node2D) -> void:
	"""Handle when player exits the collision zone."""
	# Restore automatic progress updates
	if is_player_colliding and audio_player_control:
		is_blocking_progress = false
		# Restore the audio player's is_dragging flag
		if audio_player_control.has_method("set") and "is_dragging" in audio_player_control:
			audio_player_control.is_dragging = original_is_dragging
	
	# Call parent implementation
	super._on_body_exited(body)


func apply_push(amount: float) -> void:
	"""Apply push force to the slider and update audio playback position."""
	if not slider or not audio_stream_player:
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
		
		# Seek audio to the new position
		if audio_stream_player.stream:
			# Clamp to audio length
			var audio_length = audio_stream_player.stream.get_length()
			var seek_position = clamp(new_value, 0.0, audio_length)
			audio_stream_player.seek(seek_position)
		
		handle_pushed.emit(old_value, new_value)


func _on_slider_value_changed_blocking(new_value: float) -> void:
	"""Handle slider value changes during blocking.
	
	For audio sliders, we also need to update the audio playback position
	when blocking prevents external value changes.
	"""
	# Call parent implementation for blocking logic
	super._on_slider_value_changed_blocking(new_value)
	
	# If the value was clamped by blocking, update audio position
	if is_blocking and slider and audio_stream_player:
		if audio_stream_player.stream:
			var audio_length = audio_stream_player.stream.get_length()
			var seek_position = clamp(slider.value, 0.0, audio_length)
			audio_stream_player.seek(seek_position)


func cleanup() -> void:
	"""Clean up audio-specific resources."""
	# Restore is_dragging if we modified it
	if is_blocking_progress and audio_player_control:
		if audio_player_control.has_method("set") and "is_dragging" in audio_player_control:
			audio_player_control.is_dragging = original_is_dragging
	
	audio_player_control = null
	audio_stream_player = null
	
	# Call parent cleanup
	super.cleanup()
