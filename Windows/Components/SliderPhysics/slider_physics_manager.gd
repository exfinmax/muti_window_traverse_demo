class_name SliderPhysicsManager
extends Node

## Manages all slider physics interactions within a window.
##
## This component automatically detects all HSlider and VSlider controls in a window,
## creates SliderPhysicsHandle instances for each, and manages their lifecycle.
## It enables/disables physics when the player enters/exits the window.

# Preload specialized handle types
const AudioSliderPhysicsHandle = preload("uid://bomf1g7aay6qo")
const VolumeSliderPhysicsHandle = preload("uid://ckhr1s48lw3jd")

# Signals
signal slider_pushed(slider: Slider, old_value: float, new_value: float)
signal slider_blocked(slider: Slider, player: Player)
signal slider_released(slider: Slider)

# Properties
var window: DefaultWindow = null
var handles: Array[SliderPhysicsHandle] = []
var player_inside: Player = null
var enabled: bool = true

# Configuration
@export var auto_scan_on_ready: bool = true
@export var push_sensitivity: float = 1.0
@export var block_threshold: float = 2.0


func _ready() -> void:
	# Auto-scan for sliders if enabled
	if auto_scan_on_ready and window != null:
		scan_for_sliders()


func setup(target_window: DefaultWindow) -> void:
	"""Initialize the manager with a target window.
	
	Args:
		target_window: The DefaultWindow that contains sliders to manage
	"""
	window = target_window
	
	# Scan for sliders immediately after setup
	if is_inside_tree():
		scan_for_sliders()


func scan_for_sliders() -> void:
	"""Recursively find all Slider controls in the window and create handles for them.
	
	This method searches through all children of the window to find HSlider and VSlider
	controls, then creates a SliderPhysicsHandle for each one.
	"""
	if window == null:
		DebugHelper.error("[SliderPhysicsManager] Cannot scan for sliders: window is null")
		return
	
	# Clear existing handles
	cleanup()
	
	# Recursively find all sliders
	var sliders: Array[Slider] = []
	_find_sliders_recursive(window, sliders)
	
	# Create handles for each slider
	for slider in sliders:
		var handle = create_handle_for_slider(slider)
		if handle != null:
			handles.append(handle)
	
	DebugHelper.success("[SliderPhysicsManager] Found and created handles for %d sliders in window '%s'" % [handles.size(), window.name])


func _find_sliders_recursive(node: Node, result: Array[Slider]) -> void:
	"""Recursively search for Slider controls in the node tree.
	
	Args:
		node: The node to search from
		result: Array to append found sliders to
	"""
	# Check if this node is a slider
	if node is HSlider or node is VSlider:
		result.append(node as Slider)
	
	# Recursively search children
	for child in node.get_children():
		_find_sliders_recursive(child, result)


func _find_audio_player_control(slider: Slider) -> Control:
	"""Find the audio player control that contains this slider.
	
	Searches up the parent tree to find a Control node with the audio player script.
	
	Args:
		slider: The slider to search from
		
	Returns:
		The audio player Control node, or null if not found
	"""
	var current = slider.get_parent()
	while current != null:
		# Check if this is a Control with the audio player script
		if current is Control:
			# Check if it has the expected audio player properties/methods
			if current.has_node("%AudioStreamPlayer") and current.has_node("%MusicSlider"):
				return current
		current = current.get_parent()
	return null


func create_handle_for_slider(slider: Slider) -> SliderPhysicsHandle:
	"""Create a SliderPhysicsHandle for the given slider.
	
	Args:
		slider: The Slider control to create a handle for
		
	Returns:
		The created SliderPhysicsHandle, or null if creation failed
	"""
	if slider == null:
		DebugHelper.error("[SliderPhysicsManager] Cannot create handle: slider is null")
		return null
	
	# Check if this is a special slider that needs custom handling
	var handle: SliderPhysicsHandle = null
	
	# Check for volume sliders (Master, Music, SFX)
	if slider.name in ["SliderMaster", "SliderMusic", "SliderSFX"]:
		var volume_handle = VolumeSliderPhysicsHandle.new()
		volume_handle.name = "VolumeSliderPhysicsHandle_%s" % slider.name
		handle = volume_handle
		
		# Add as child of the slider for proper positioning
		slider.add_child(handle)
		
		# Setup volume-specific handle
		if player_inside != null:
			volume_handle.setup(slider, player_inside)
		else:
			# Setup without player for now
			handle.slider = slider
			# Determine audio bus mapping
			if slider.name in VolumeSliderPhysicsHandle.BUS_MAPPING:
				volume_handle.audio_bus_name = VolumeSliderPhysicsHandle.BUS_MAPPING[slider.name]
				volume_handle.settings_key = VolumeSliderPhysicsHandle.SETTINGS_MAPPING[slider.name]
			# Connect to slider value changes
			if slider and not slider.value_changed.is_connected(handle._on_slider_value_changed):
				slider.value_changed.connect(handle._on_slider_value_changed)
			handle.update_collision_shape()
		
		DebugHelper.success("[SliderPhysicsManager] Created VolumeSliderPhysicsHandle for %s" % slider.name)
	
	# Check for audio player music slider
	elif slider.name == "MusicSlider":
		# Find the audio player control (parent of the slider)
		var audio_control = _find_audio_player_control(slider)
		if audio_control:
			var audio_handle = AudioSliderPhysicsHandle.new()
			audio_handle.name = "AudioSliderPhysicsHandle_%s" % slider.name
			handle = audio_handle
			
			# Add as child of the slider for proper positioning
			slider.add_child(handle)
			
			# Setup audio-specific handle
			if player_inside != null:
				audio_handle.setup_audio_slider(slider, player_inside, audio_control)
			else:
				# Setup without player for now
				handle.slider = slider
				audio_handle.audio_player_control = audio_control
				audio_handle.audio_stream_player = audio_control.get_node_or_null("%AudioStreamPlayer")
				if slider and not slider.value_changed.is_connected(handle._on_slider_value_changed):
					slider.value_changed.connect(handle._on_slider_value_changed)
				handle.update_collision_shape()
			
			DebugHelper.success("[SliderPhysicsManager] Created AudioSliderPhysicsHandle for MusicSlider")
		else:
			DebugHelper.warning("[SliderPhysicsManager] Found MusicSlider but could not find audio player control")
	
	# If no special handle was created, create a standard handle
	if handle == null:
		handle = SliderPhysicsHandle.new()
		handle.name = "SliderPhysicsHandle_%s" % slider.name
		
		# Add as child of the slider for proper positioning
		slider.add_child(handle)
		
		# Setup handle with slider and player reference
		if player_inside != null:
			handle.setup(slider, player_inside)
		else:
			# Setup without player for now, will be set when player enters
			handle.slider = slider
			# Connect to slider value changes
			if slider and not slider.value_changed.is_connected(handle._on_slider_value_changed):
				slider.value_changed.connect(handle._on_slider_value_changed)
			handle.update_collision_shape()
		
		DebugHelper.info("[SliderPhysicsManager] Created standard SliderPhysicsHandle for %s" % slider.name)
	
	# Configure handle with manager settings
	handle.push_sensitivity = push_sensitivity
	handle.block_threshold = block_threshold
	
	# Connect handle signals to manager signals
	handle.handle_pushed.connect(_on_handle_pushed.bind(slider))
	handle.handle_blocked.connect(_on_handle_blocked.bind(slider))
	handle.handle_released.connect(_on_handle_released.bind(slider))
	
	# Enable monitoring if player is inside
	handle.enable_monitoring(player_inside != null and enabled)
	
	return handle


func on_player_entered(player: Player) -> void:
	"""Called when a player enters the window.
	
	Enables physics interactions for all slider handles.
	
	Args:
		player: The Player that entered the window
	"""
	if player == null:
		return
	
	player_inside = player
	
	# Setup all handles with player reference
	for handle in handles:
		if handle != null and is_instance_valid(handle):
			# If handle wasn't fully setup, complete setup now
			if handle.player_ref == null and handle.slider != null:
				# Check if this is an audio slider handle
				if handle is AudioSliderPhysicsHandle:
					var audio_handle = handle as AudioSliderPhysicsHandle
					if audio_handle.audio_player_control:
						audio_handle.setup_audio_slider(handle.slider, player, audio_handle.audio_player_control)
					else:
						handle.setup(handle.slider, player)
				# Check if this is a volume slider handle
				elif handle is VolumeSliderPhysicsHandle:
					var volume_handle = handle as VolumeSliderPhysicsHandle
					volume_handle.setup(handle.slider, player)
				else:
					handle.setup(handle.slider, player)
			else:
				handle.player_ref = player
			
			# Enable monitoring
			if enabled:
				handle.enable_monitoring(true)
	
	DebugHelper.success("[SliderPhysicsManager] Player entered window '%s', enabled %d slider handles" % [window.name if window else "unknown", handles.size()])


func on_player_exited(player: Player) -> void:
	"""Called when a player exits the window.
	
	Disables physics interactions for all slider handles.
	
	Args:
		player: The Player that exited the window
	"""
	if player == null:
		return
	
	# Only clear if this is the player we're tracking
	if player_inside == player:
		player_inside = null
		
		# Disable monitoring for all handles
		for handle in handles:
			if handle != null and is_instance_valid(handle):
				handle.enable_monitoring(false)
		
		DebugHelper.info("[SliderPhysicsManager] Player exited window '%s', disabled %d slider handles" % [window.name if window else "unknown", handles.size()])


func enable_physics(enable: bool) -> void:
	"""Enable or disable physics for all slider handles.
	
	Args:
		enable: True to enable physics, false to disable
	"""
	enabled = enable
	
	# Update monitoring state for all handles
	for handle in handles:
		if handle != null and is_instance_valid(handle):
			handle.enable_monitoring(enable and player_inside != null)
	
	DebugHelper.info("[SliderPhysicsManager] Physics %s for %d handles in window '%s'" % ["enabled" if enable else "disabled", handles.size(), window.name if window else "unknown"])


func cleanup() -> void:
	"""Clean up all slider physics handles and free resources.
	
	This should be called when the window is closed or the manager is no longer needed.
	"""
	# Clean up all handles
	for handle in handles:
		if handle != null and is_instance_valid(handle):
			handle.cleanup()
	
	# Clear the handles array
	handles.clear()
	player_inside = null
	
	DebugHelper.info("[SliderPhysicsManager] Cleaned up all slider handles for window '%s'" % [window.name if window else "unknown"])


func _on_handle_pushed(old_value: float, new_value: float, slider: Slider) -> void:
	"""Internal callback when a handle is pushed.
	
	Forwards the signal to external listeners with slider reference.
	"""
	slider_pushed.emit(slider, old_value, new_value)


func _on_handle_blocked(slider: Slider) -> void:
	"""Internal callback when a handle is blocked.
	
	Forwards the signal to external listeners with slider reference.
	"""
	if player_inside != null:
		slider_blocked.emit(slider, player_inside)


func _on_handle_released(slider: Slider) -> void:
	"""Internal callback when a handle is released.
	
	Forwards the signal to external listeners with slider reference.
	"""
	slider_released.emit(slider)


func _exit_tree() -> void:
	"""Clean up when the manager is removed from the scene tree."""
	cleanup()
