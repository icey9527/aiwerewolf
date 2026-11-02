extends RefCounted


const Paths = preload("res://config/game_paths.gd")
# DR2 学级裁判镜头数据采样器（只读，不含节点）。
# 数据来自 参考/dr2/TrialCamStudy/cameras.json：每个镜头两个关键帧，
# 位置相对角色锚点（Y 向上），旋转是叠加在“看向角色”基础上的小角度偏移。
#
# 实测约定（详见 docs/DEVELOPMENT.md）：
#   · 位置 1 单位 = 0.1m；本项目立绘高 2.8m，是原版角色的约 1.6 倍，
#     所以统一再乘 1.6 —— POSITION_SCALE = 0.16。
#   · 旋转 1 单位 = 0.1°（十分之一度），叠加到 look-at 之后，避免镜头抬头看天。
#   · 锚点不是脚底，而是角色胸口附近：ANCHOR_HEIGHT；注视点再高一点到胸口/下巴。
# 本文件不读剧本、不创建相机、不修改节点，只返回变换与时长。
const DATA_PATH: String = Paths.CAMERA_DATA
const POSITION_SCALE: float = 0.30
const ROTATION_SCALE: float = 0.1
# 数据里的俯仰偏移偏大（会把人压到画面下方），实际只取三成左右；偏航/滚转保留。
const PITCH_SCALE: float = 0.35
const ANCHOR_HEIGHT: float = 2.20
const FOCUS_HEIGHT: float = 2.15
const FPS: float = 60.0
const DEFAULT_FOV: float = 45.0

static var _shots: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var text: String = FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Array:
		push_error("DR2 镜头数据读取失败：" + DATA_PATH)
		return
	for shot: Dictionary in parsed:
		_shots[str(shot.get("Name", ""))] = shot

static func has(shot_name: String) -> bool:
	_ensure_loaded()
	return _shots.has(shot_name)

# 预览面板用：时长、是否静止、是否连段、位移量（米）与旋转量（度）。
static func info(shot_name: String) -> Dictionary:
	_ensure_loaded()
	var shot: Dictionary = _shots.get(shot_name, {})
	if shot.is_empty():
		return {}
	var frames: Array = shot.get("Keyframes", [])
	if frames.is_empty():
		return {}
	var kf0: Array = frames[0]
	var kf1: Array = frames[1] if frames.size() > 1 else frames[0]
	var position_delta: float = 0.0
	for i in range(3):
		position_delta = maxf(position_delta, absf(float(kf1[i]) - float(kf0[i])) * POSITION_SCALE)
	var rotation_delta: float = 0.0
	for i in range(3, 6):
		rotation_delta = maxf(rotation_delta, absf(float(kf1[i]) - float(kf0[i])) * ROTATION_SCALE)
	return {
		"duration": maxf(float(shot.get("Duration", 180.0)) / FPS, 0.01),
		"static": position_delta < 0.001 and rotation_delta < 0.01,
		"position_delta": position_delta,
		"rotation_delta": rotation_delta,
		"next": int(shot.get("Next", 0)),
	}

static func shot_names() -> PackedStringArray:
	_ensure_loaded()
	var names: PackedStringArray = PackedStringArray()
	for key: String in _shots.keys():
		names.append(key)
	names.sort()
	return names

# 镜头分类：近景 / 平移 / 广角环视 / 特殊演出。
# 广角类（*_OVER、LOOKOUT、LOOK_AT_PAN）适合开场、全景和结尾绕圈；
# 近景类适合发言；特殊类（ROLL/SPECIAL/SAIBAN/ENO）留给专门桥段。
static func category(shot_name: String) -> String:
	if shot_name.contains("_OVER") or shot_name.begins_with("LOOKOUT") or shot_name.begins_with("LOOK_AT_PAN"):
		return "wide"
	if shot_name.begins_with("ROLL") or shot_name.begins_with("SPECIAL") or shot_name.begins_with("SAIBAN") or shot_name.begins_with("ENO"):
		return "special"
	if shot_name.begins_with("PAN") or shot_name.begins_with("F_PAN") or shot_name.begins_with("Q_PAN"):
		return "pan"
	return "close"

# anchor：角色站位（脚底，含竞选升降）；elapsed：本段已经过的秒数。
# span_seconds > 0 时把这一镜的运动铺满整段台词（否则按原版时长播完后保持末帧）。
# position_scale / anchor_height / focus_height 允许按“角色近景 / 房间广角”两种锚点分别控制。
static func sample(
	shot_name: String,
	anchor: Transform3D,
	elapsed: float,
	span_seconds: float = 0.0,
	position_scale: float = POSITION_SCALE,
	anchor_height: float = ANCHOR_HEIGHT,
	focus_height: float = FOCUS_HEIGHT,
	pitch_scale: float = PITCH_SCALE,
	fov_lock: float = 0.0
) -> Dictionary:
	_ensure_loaded()
	var shot: Dictionary = _shots.get(shot_name, {})
	if shot.is_empty():
		return {}
	var frames: Array = shot.get("Keyframes", [])
	if frames.is_empty():
		return {}
	var kf0: Array = frames[0]
	var kf1: Array = frames[1] if frames.size() > 1 else frames[0]
	var authored: float = maxf(float(shot.get("Duration", 180.0)) / FPS, 0.01)
	var duration: float = authored
	if span_seconds > 0.01:
		duration = span_seconds
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var local := Vector3(
		lerpf(float(kf0[0]), float(kf1[0]), t),
		lerpf(float(kf0[1]), float(kf1[1]), t),
		lerpf(float(kf0[2]), float(kf1[2]), t)
	) * position_scale
	var euler := Vector3(
		lerpf(float(kf0[3]), float(kf1[3]), t),
		lerpf(float(kf0[4]), float(kf1[4]), t),
		lerpf(float(kf0[5]), float(kf1[5]), t)
	) * ROTATION_SCALE
	euler.x *= pitch_scale
	var eye: Vector3 = anchor.origin + Vector3.UP * anchor_height + anchor.basis * local
	var focus: Vector3 = anchor.origin + Vector3.UP * focus_height
	var base: Basis = Basis.looking_at((focus - eye).normalized(), Vector3.UP)
	var offset: Basis = Basis.from_euler(euler * (PI / 180.0), EULER_ORDER_YXZ)
	# 数据的第二个旋转分量随 ZOOMIN/ZOOMOUT 反向变化，行为与视场角一致；
	# 用它当 FOV 能还原原版的紧近景，其余分量仍作为 look-at 后的小角度偏移。
	var fov_value: float = fov_lock if fov_lock > 0.0 else clampf(lerpf(float(kf0[4]), float(kf1[4]), t), 26.0, 60.0)
	return {
		"transform": Transform3D(base * offset, eye),
		"focus": focus,
		"fov": fov_value,
		"duration": duration,
		"progress": t,
	}
