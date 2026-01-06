# Slider Physics Component Guide

## Overview

`SliderPhysicsComponent` is a self-contained window component that automatically detects all sliders in a window and enables physics-based player interactions with them. It replaces the previous two-part system (component + manager) with a single, unified component.

## Features

- **Automatic Slider Detection**: Recursively scans the window for all `HSlider` and `VSlider` controls
- **Specialized Handles**: Automatically creates appropriate handle types:
  - `VolumeSliderPhysicsHandle` for volume sliders (Master, Music, SFX)
  - `AudioSliderPhysicsHandle` for audio player music sliders
  - `SliderPhysicsHandle` for standard sliders
- **Player Interaction**: Players can push sliders by colliding with them
- **Blocking Mechanic**: Stationary players block slider movement
- **Lifecycle Management**: Automatically handles embed/unembed and cleanup

## Usage

### Basic Setup

1. Add `SliderPhysicsComponent` as a child of your window (load from script):
   ```gdscript
   # In Godot Editor:
   # 1. Select your window node
   # 2. Add Child Node
   # 3. Search for "Script" and select it
   # 4. In the inspector, set Script to: res://scenes/Windows/Components/SliderPhysics/slider_physics_component.gd
   ```

2. The component will automatically:
   - Scan for all sliders when the window is ready
   - Create appropriate physics handles for each slider
   - Connect to window player enter/exit signals
   - Enable/disable physics based on embed state

### Configuration

The component exposes several export variables:

```gdscript
@export var auto_scan_on_ready: bool = true  # Automatically scan for sliders
@export var push_sensitivity: float = 1.0    # How easily sliders are pushed
@export var block_threshold: float = 2.0     # Velocity threshold for blocking
```

### Signals

The component emits signals for slider interactions:

```gdscript
signal slider_pushed(slider: Slider, old_value: float, new_value: float)
signal slider_blocked(slider: Slider, player: Player)
signal slider_released(slider: Slider)
```

Connect to these signals to respond to player interactions:

```gdscript
func _ready():
	var slider_component = $SliderPhysicsComponent
	slider_component.slider_pushed.connect(_on_slider_pushed)

func _on_slider_pushed(slider: Slider, old_value: float, new_value: float):
	print("Slider %s pushed from %.2f to %.2f" % [slider.name, old_value, new_value])
```

## How It Works

### Initialization Flow

1. **Window Ready**: Component detects parent window and calls `_on_window_ready()`
2. **Slider Scan**: Recursively searches window for all slider controls
3. **Handle Creation**: Creates specialized handles based on slider type:
   - Volume sliders → `VolumeSliderPhysicsHandle` (updates audio bus volume)
   - Music sliders → `AudioSliderPhysicsHandle` (seeks audio playback)
   - Other sliders → `SliderPhysicsHandle` (standard physics)
4. **Signal Connection**: Connects to window's `player_entered` and `player_exited` signals

### Player Interaction Flow

1. **Player Enters Window**: 
   - Component receives `player_entered` signal
   - Sets up all handles with player reference
   - Enables collision monitoring

2. **Player Collides with Slider**:
   - Handle detects collision via Area2D
   - Tracks player velocity for blocking detection
   - Applies push force based on player position
   - Updates slider value smoothly

3. **Player Blocks Slider**:
   - If player velocity drops below threshold
   - Handle enters blocking state
   - Prevents external code from moving slider past player

4. **Player Exits Window**:
   - Component receives `player_exited` signal
   - Disables collision monitoring for all handles
   - Clears player reference

### Embed/Unembed Flow

- **On Embed**: Enables physics for all handles
- **On Unembed**: Disables physics for all handles
- **On Close**: Cleans up all handles and resources

## Specialized Handle Types

### VolumeSliderPhysicsHandle

Used for volume sliders (SliderMaster, SliderMusic, SliderSFX):
- Updates corresponding audio bus volume in real-time
- Saves volume settings to Global.current_setting
- Persists changes via SaveManager

### AudioSliderPhysicsHandle

Used for audio player music sliders (MusicSlider):
- Seeks audio playback position when pushed
- Blocks automatic progress updates during interaction
- Restores automatic updates when player exits

### SliderPhysicsHandle

Standard handle for all other sliders:
- Smooth position-based following
- Velocity-based blocking detection
- Visual feedback (green = collision, red = blocking)

## Migration from Old System

### Before (Two-Part System)

```gdscript
# Window had both:
# 1. SliderPhysicsComponent (just forwarded events)
# 2. SliderPhysicsManager (did all the work)

# In window script:
var slider_manager: SliderPhysicsManager

func _ready():
    slider_manager = $SliderPhysicsManager
    slider_manager.setup(self)
    slider_manager.scan_for_sliders()

func on_player_entered(player):
    slider_manager.on_player_entered(player)
```

### After (Self-Contained Component)

```gdscript
# Window only needs:
# 1. SliderPhysicsComponent (does everything)

# No window script changes needed!
# Component automatically:
# - Scans for sliders
# - Connects to player signals
# - Manages lifecycle
```

### Removing Old Manager

If your window still has a `SliderPhysicsManager` node:

1. Open the window scene in Godot Editor
2. Select the `SliderPhysicsManager` node
3. Delete it (the component handles everything now)
4. Save the scene

## Troubleshooting

### Sliders Not Responding

**Problem**: Player can't interact with sliders

**Solutions**:
1. Check that window emits `player_entered` and `player_exited` signals
2. Verify component is child of the window
3. Check that sliders are descendants of the window
4. Ensure player is on collision layer 2

### Sliders Moving Too Fast/Slow

**Problem**: Slider movement feels wrong

**Solutions**:
1. Adjust `push_sensitivity` (higher = faster movement)
2. Modify `block_threshold` (lower = easier to block)
3. Check slider's `step` value (affects granularity)

### Volume Not Updating

**Problem**: Volume sliders don't change audio

**Solutions**:
1. Verify slider names match: "SliderMaster", "SliderMusic", "SliderSFX"
2. Check that audio buses exist: "Master", "BGM", "SFX"
3. Ensure Global.current_setting is accessible

### Audio Seeking Not Working

**Problem**: Music slider doesn't seek audio

**Solutions**:
1. Verify slider name is "MusicSlider"
2. Check that parent has `%AudioStreamPlayer` node
3. Ensure audio stream is loaded and playing

## Performance Considerations

- **Slider Scanning**: Done once on window ready, minimal overhead
- **Handle Updates**: Only active when player is inside window
- **Collision Detection**: Uses Area2D, very efficient
- **Memory**: Handles are cleaned up when window closes

## Best Practices

1. **Naming Conventions**: Use standard names for special sliders:
   - Volume: "SliderMaster", "SliderMusic", "SliderSFX"
   - Audio: "MusicSlider"

2. **Component Loading**: Load from script in editor for easier configuration

3. **Signal Handling**: Connect to component signals for custom behavior

4. **Cleanup**: Component handles cleanup automatically, no manual intervention needed

5. **Testing**: Test with different slider types to ensure proper handle creation

## Example: Custom Window with Sliders

```gdscript
# custom_window.gd
extends DefaultWindow

func _ready():
    super._ready()
    
    # Component is already set up automatically!
    # Just connect to signals if you need custom behavior
    var slider_component = get_node_or_null("SliderPhysicsComponent")
    if slider_component:
        slider_component.slider_pushed.connect(_on_slider_pushed)
        slider_component.slider_blocked.connect(_on_slider_blocked)

func _on_slider_pushed(slider: Slider, old_value: float, new_value: float):
    print("Player pushed %s from %.2f to %.2f" % [slider.name, old_value, new_value])

func _on_slider_blocked(slider: Slider, player: Player):
    print("Player is blocking %s" % slider.name)
```

## Architecture Benefits

### Self-Contained Design

- **Single Responsibility**: Component handles all slider physics
- **No External Dependencies**: Doesn't require separate manager node
- **Easier Setup**: Just add component, everything works
- **Better Encapsulation**: All logic in one place

### Automatic Lifecycle

- **Auto-Discovery**: Finds sliders automatically
- **Auto-Setup**: Creates appropriate handles
- **Auto-Cleanup**: Frees resources on close
- **Auto-Enable/Disable**: Responds to embed state

### Extensibility

- **Custom Handles**: Easy to add new specialized handle types
- **Signal System**: Connect to component signals for custom behavior
- **Export Variables**: Configure behavior without code changes
- **Override Methods**: Extend component for custom windows

## Related Files

- `slider_physics_component.gd` - Main component implementation
- `slider_physics_handle.gd` - Base handle class
- `audio_slider_physics_handle.gd` - Audio player slider handle
- `volume_slider_physics_handle.gd` - Volume slider handle
- `window_component.gd` - Base component class
