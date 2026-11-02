extends RefCounted

# 机位预设。mode：
#   inner    相机在圈内、与发言者同轴，正面看人
#   outer    相机在圈外、发言者对面，越过桌面看整排
#   overhead 高位俯视，适合阶段转换
# radius 为绝对半径；ring_offset 表示相对席位圈外扩的米数。
const PRESETS: Dictionary = {
	"close": {
		"mode": "inner", "radius": 2.30, "height": 2.42,
		"fov": 38.5, "target": 2.12, "drift": 0.10, "drift_speed": 0.55, "yaw": 0.10,
	},
	"medium": {
		"mode": "inner", "radius": 1.35, "height": 2.58,
		"fov": 41.0, "target": 1.90, "drift": 0.12, "drift_speed": 0.60, "yaw": 0.08,
	},
	"outer": {
		"mode": "outer", "radius": 0.0, "ring_offset": 3.2, "angle_offset": 2.00,
		"height": 5.60, "fov": 48.0, "target": 1.20, "drift": 0.06, "drift_speed": 0.30,
	},
	"high": {
		"mode": "overhead", "radius": 0.80, "height": 14.00,
		"fov": 52.0, "target": 0.70, "drift": 0.03, "drift_speed": 0.20,
	},
}

static func preset(name: String) -> Dictionary:
	return PRESETS.get(name, PRESETS["medium"])
