extends RefCounted

# 世界坐标参数按真 3D 构图调校。
const PORTRAIT_HEIGHT: float = 2.8
const FOOT_HEIGHT: float = 0.18
const FACE_HEIGHT: float = 2.48
const SPEAKER_FOV: float = 29.0
const WIDE_FOV: float = 49.0
const TRANSITION_SECONDS: float = 0.4
const DISCUSSION_CAMERA_HEIGHT: float = 1.95
const DISCUSSION_TARGET_HEIGHT: float = 1.65
const SIDE_TARGET_OFFSET: float = 0.35
const POD_WIDTH: float = 2.60
const POD_GAP: float = 0.00
const INTRO_OUTER_PAD: float = 8.0
# 开场外圈沿用立绘巡览里手调过的那套：15m → 7m、机位高 10m、整圈 360°，
# 角速度仍是 110°/秒（330°/3.0s），所以转满一圈需要 3.273 秒。
const INTRO_OUTER_START_RADIUS: float = 15.0
const INTRO_OUTER_END_RADIUS: float = 7.0
const INTRO_OUTER_HEIGHT: float = 10.0
const INTRO_OUTER_SWEEP_DEG: float = 360.0
const INTRO_OUTER_SECONDS: float = 3.0 * 360.0 / 330.0
const INTRO_INNER_RADIUS: float = 2.10
const INTRO_INNER_HEIGHT: float = 2.40
const INTRO_INNER_TARGET: float = 2.20
const INTRO_INNER_FOV: float = 40.0
const INTRO_HEIGHT: float = 5.4
const INTRO_END_RADIUS: float = 1.35
const INTRO_END_TARGET: float = 1.90
const INTRO_END_HEIGHT: float = 2.58
const INTRO_FOV: float = 52.0
const INTRO_END_FOV: float = 41.0
# 机位来源：dr2 = 剧本写了 dr2_shot 的镜头用弹丸论破原版机位；
# legacy = 全部走本项目的 shot_solver。命令行 --camera=legacy 可临时切回。
const CAMERA_MODE: String = "dr2"
const ORBIT_RADIUS: float = 1.1
const ELECTION_LIFT: float = 1.6
const FALL_DEPTH: float = 5.0
const REVEAL_SHAKE: float = 0.018
const MIN_RADIUS: float = 4.0

static func ring_radius(count: int) -> float:
	return maxf(MIN_RADIUS, (POD_WIDTH + POD_GAP) / (2.0 * sin(PI / float(count))))
