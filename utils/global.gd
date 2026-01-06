extends Node

var player:CharacterBody2D
#var main:Main
var main_window_camera:Camera2D
var current_player_window:Window = null  # 玩家当前所在的窗口

var current_setting:Dictionary={
	"MASTER": .5,
	"BGM": .5,
	"SFX": .5,
	"Language": "en",
	"LanguageDetected": false,
}
