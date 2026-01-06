class_name WindowComponent
extends Node

## 窗口组件基类
## 所有窗口组件都应继承此类以获得标准的生命周期接口

var window: Window = null

func _ready() -> void:
	# 自动获取父窗口
	var parent = get_parent()
	if parent is Window:
		window = parent
		# 组件在窗口之后创建，直接调用初始化
		call_deferred("_on_component_ready")
	else:
		DebugHelper.warning("WindowComponent: Parent is not a Window, component may not work correctly")

## 子类重写此方法来初始化组件
## 在组件准备完成后调用（组件后于窗口创建）
func _on_component_ready() -> void:
	pass

## 窗口嵌入到游戏世界时调用
func on_window_embedded() -> void:
	pass

## 窗口从游戏世界取消嵌入时调用
func on_window_unembedded() -> void:
	pass

## 窗口关闭时调用
func on_window_closed() -> void:
	pass
