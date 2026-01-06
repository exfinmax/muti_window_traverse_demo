class_name SaveGame
extends Resource

@export var saved_data: Array[SavedData] = []
@export var recycle_bin_data: Array = []  # 回收站数据（序列化后的 DeletedItem）
@export var antivirus_completed: bool = false  # 杀毒软件是否已通关
@export var intro_completed: bool = false  # 开场对话是否已完成
@export var current_stage_name: String = ""  # 当前关卡名称
@export var awakening_shown: bool = false  # awakening对话是否已显示
@export var mio_folder_shown: bool = false  # mio_folder对话是否已显示
@export var audio_game_completed: bool = false  # 音频游戏完成标记
@export var password_fragments: Array[String] = []  # 收集到的密码片段
@export var first_die_shown: bool = false  # 回收站死亡对话已显示
@export var mio_folder_end_shown: bool = false  # Mio文件夹关闭对话已显示
