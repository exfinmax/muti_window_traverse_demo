extends Node
class_name ExplorerState

signal files_changed
signal bin_changed

@export var initial_files: Array[String] = ["readme.txt", "notes.md", "todo.txt"]

var files: Array[String] = []
var bin: Array[String] = []

func _ready() -> void:
	files = initial_files.duplicate()
	add_to_group("explorer_state")

func add_file(name: String) -> void:
	name = name.strip_edges()
	if name == "":
		return
	if name in files:
		return
	files.append(name)
	emit_signal("files_changed")

func delete_file(name: String) -> void:
	if name in files:
		files.erase(name)
		bin.append(name)
		emit_signal("files_changed")
		emit_signal("bin_changed")

func restore_file(name: String) -> void:
	if name in bin:
		bin.erase(name)
		files.append(name)
		emit_signal("bin_changed")
		emit_signal("files_changed")

func empty_bin() -> void:
	if bin.is_empty():
		return
	bin.clear()
	emit_signal("bin_changed")
