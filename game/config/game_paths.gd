extends RefCounted

# 资源路径集中在这里。代码里不要直接写死 res:// 文件名字符串（配置文件除外），
# 换字体、换默认剧本、换角色目录时只改这一处。
# 用法：每个脚本顶部 const Paths = preload("res://config/game_paths.gd")，再写 Paths.FONT_UI

## 界面、台词、钟面数字、讲台铭牌共用的字体（思源宋体粗体）。
const FONT_UI: String = "res://assets/fonts/SourceHanSerifCN-Bold.otf"
## 角色运行目录：每个子目录一份 chara.yaml + 立绘 PNG。
const CHARACTER_ROOT: String = "res://assets/characters/"
## 每个角色目录里的配置文件名。
const CHARACTER_CONFIG: String = "chara.yaml"
## DR2 原版镜头数据（860 个镜头，只读采样）。
const CAMERA_DATA: String = "res://data/trial_cameras.json"
## 剧本目录与默认剧本；命令行 --script= 只写名字时会到 SCRIPT_DIR 里找。
const SCRIPT_DIR: String = "res://scripted/demos/"
const DEFAULT_SCRIPT: String = "first_trial_v3.json"
const DEFAULT_SCRIPT_PATH: String = SCRIPT_DIR + DEFAULT_SCRIPT

static func font_ui() -> Font:
	return load(FONT_UI) as Font
