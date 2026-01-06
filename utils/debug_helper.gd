extends Node

## Global debug helper for easy access to debug console
##
## Usage:
##   DebugHelper.log("Message")
##   DebugHelper.error("Error message")
##   DebugHelper.warning("Warning message")
##   DebugHelper.info("Info message")
##   DebugHelper.success("Success message")

var debug_console: Node = null

func _ready() -> void:
	# Find debug console on ready
	_find_debug_console()

func _find_debug_console() -> void:
	"""Find the debug console in the scene tree."""
	if not debug_console:
		debug_console = get_tree().get_first_node_in_group("debug_console")

func log(message: String) -> void:
	"""Add a regular message to the debug console."""
	_ensure_console()
	print(message)
	if debug_console and debug_console.has_method("add_message"):
		debug_console.add_message(message)

func error(message: String) -> void:
	"""Add an error message to the debug console."""
	_ensure_console()
	push_error(message)
	if debug_console and debug_console.has_method("add_error"):
		debug_console.add_error(message)

func warning(message: String) -> void:
	"""Add a warning message to the debug console."""
	_ensure_console()
	push_warning(message)
	if debug_console and debug_console.has_method("add_warning"):
		debug_console.add_warning(message)

func info(message: String) -> void:
	"""Add an info message to the debug console."""
	_ensure_console()
	print_rich(message)
	if debug_console and debug_console.has_method("add_info"):
		debug_console.add_info(message)

func success(message: String) -> void:
	"""Add a success message to the debug console."""
	_ensure_console()
	if debug_console and debug_console.has_method("add_success"):
		debug_console.add_success(message)

func _ensure_console() -> void:
	"""Ensure debug console reference is valid."""
	if not debug_console or not is_instance_valid(debug_console):
		_find_debug_console()
