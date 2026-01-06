class_name VolumeSliderPhysicsHandle
extends SliderPhysicsHandle

## Specialized physics handle for volume sliders in the video panel.
##
## This handle extends the base SliderPhysicsHandle to add special behavior for
## volume sliders (Master, Music, SFX). When the player pushes these sliders,
## it updates the corresponding audio bus volume and saves the settings.

# Audio bus mapping
const BUS_MAPPING = {
	"SliderMaster": "Master",
	"SliderMusic": "BGM",
	"SliderSFX": "SFX"
}

# Settings key mapping
const SETTINGS_MAPPING = {
	"SliderMaster": "MASTER",
	"SliderMusic": "BGM",
	"SliderSFX": "SFX"
}

var audio_bus_name: String = ""
var settings_key: String = ""


func setup(target_slider: Slider, player: Player) -> void:
	"""Setup the volume slider handle with audio bus integration.
	
	Args:
		target_slider: The volume slider to handle
		player: The player that can interact with this slider
	"""
	# Call parent setup
	super.setup(target_slider, player)
	
	# Determine which audio bus this slider controls
	if target_slider.name in BUS_MAPPING:
		audio_bus_name = BUS_MAPPING[target_slider.name]
		settings_key = SETTINGS_MAPPING[target_slider.name]
		DebugHelper.success("[VolumeSliderPhysicsHandle] Setup for %s -> Bus: %s, Setting: %s" % [target_slider.name, audio_bus_name, settings_key])
	else:
		DebugHelper.warning("[VolumeSliderPhysicsHandle] Unknown volume slider: %s" % target_slider.name)


func _on_slider_value_changed(value: float) -> void:
	"""Override to add audio bus volume update and settings save.
	
	When the slider value changes (from player push or other means),
	update the audio bus volume and save the setting.
	
	Args:
		value: The new slider value
	"""
	# Call parent to update collision shape
	super._on_slider_value_changed(value)
	
	# Update audio bus volume if we have a valid bus name
	if audio_bus_name != "":
		var bus_index = AudioServer.get_bus_index(audio_bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
			
			# Save to global settings
			if settings_key != "":
				Global.current_setting[settings_key] = value
				
				DebugHelper.info("[VolumeSliderPhysicsHandle] Updated %s volume to %.2f (%.1f dB)" % [audio_bus_name, value, linear_to_db(value)])
		else:
			DebugHelper.error("[VolumeSliderPhysicsHandle] Audio bus not found: %s" % audio_bus_name)


func apply_push(amount: float) -> void:
	"""Override to ensure audio updates happen when player pushes slider.
	
	Args:
		amount: The amount to push the slider by
	"""
	# Call parent to apply the push
	super.apply_push(amount)
	
	# The _on_slider_value_changed callback will handle audio bus update
	# and settings save automatically when the slider value changes
