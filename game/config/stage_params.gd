extends RefCounted

# 舞台尺寸、材质与灯光参数（世界单位：米，Y 向上）。
# 舱宽与主会话的席位环反推共用一个灰盒值；若 camera_params.gd 的
# POD_WIDTH / POD_GAP 调整，这里必须同步，否则桌沿与舱体净距会变化。
# 本文件只存常量，不创建节点、不读剧本、不持有运行时状态。

# --- 席位 / 舱体 ---------------------------------------------------------
const POD_WIDTH: float = 2.60
const POD_GAP: float = 0.00
const POD_HALF_WIDTH: float = 1.30
const POD_REAR_Z: float = -1.05
const POD_FRONT_Z: float = 1.50
const WALL_HEIGHT: float = 3.24
const WALL_THICKNESS: float = 0.09
const FIXED_SIDE_DEPTH: float = 1.50
# 固定侧墙绕后缘内收 3.134°，前端中心线半宽 1.718，与闭合侧翼齐平。
const FIXED_SIDE_YAW_DEG: float = 3.134
const WING_DEPTH: float = 1.05
# 12 席半径约 7.3 m 时邻舱净距很小；开放侧翼滑到固定侧墙后方，
# 不再向前支出，避免白天把人物框成箱子。
const WING_OPEN_CENTER_Z: float = -0.20
# 闭合时侧翼以后缘为铰点向内偏航，前缘中心线半宽由 1.718 收到 1.446。
const WING_HINGE_X: float = 1.24
const WING_HINGE_CLOSED_Z: float = 0.45
const WING_CLOSED_YAW_DEG: float = 15.0
const SHUTTER_OPEN_Y: float = -1.70
const SHUTTER_CLOSED_Y: float = 1.62
# 闭合前挡板收窄到与侧翼前缘等宽（2.892m），与前缘互相搭接密封。
const SHUTTER_WIDTH: float = 2.09
# 后壁与固定侧墙共用的升降 shell：白天整体沉入地下，夜晚升回 0。
# 下沉量多留 0.25m，保证墙顶、导轨等结构在白天完全低于地面。
const SHELL_OPEN_Y: float = -WALL_HEIGHT - 0.25
const SHELL_CLOSED_Y: float = 0.0
# 顶罩闭合时是两段梯形：后段 -1.05..0.45、前段 0.45..1.50，
# 半宽按侧壁外表面取 1.845→1.763→1.491；邻舱保留约 10mm 净空。
# 白天顶罩收至贴近天花板（房间高 11.0m），不占据人物上方空间。
const CANOPY_RADIUS: float = POD_WIDTH * 0.42
const CANOPY_CLOSED_Z: float = 0.225
const CANOPY_OPEN_Z: float = -0.45
const CANOPY_Z_SCALE: float = 0.62
const CANOPY_OPEN_Y: float = 10.30
const CANOPY_CLOSED_Y: float = 3.30
const CANOPY_REAR_Z: float = -1.05
const CANOPY_JOINT_Z: float = 0.45
const CANOPY_FRONT_Z: float = 1.50
const CANOPY_REAR_HALF: float = 1.33
const CANOPY_JOINT_HALF: float = 1.27
const CANOPY_FRONT_HALF: float = 1.08
const CANOPY_BODY_HEIGHT: float = 0.12
const CANOPY_GLOW_HEIGHT: float = 0.025
const CANOPY_TOP_HEIGHT: float = 0.035

# 翻板/地台半径独立于舱宽，保证 2.8m 立绘能落入开口。
const FLOOR_PAD_RADIUS: float = 1.20

# 立绘占位基准，仅用于说明舱内净空，不在本舞台创建立绘。
const PORTRAIT_HEIGHT: float = 2.8
const FOOT_Y: float = 0.18

# --- 处刑舱底 / 退场 -----------------------------------------------------
# 舱底由左右翻板组成；开口后移，给讲台留出固定地板，避免翻板扫到讲台。
const HATCH_CENTER_Z: float = -0.30
const HATCH_LEAF_WIDTH_SCALE: float = 0.82
const HATCH_LEAF_DEPTH_SCALE: float = 1.00
const HATCH_THICKNESS: float = 0.06
const FLOOR_UNDER_Y: float = 0.010
const FLOOR_COLLAR_Y: float = 0.050
const EXIT_FALL_ANGLE_DEG: float = 86.0
const EXIT_SPOT_LOCAL: Vector3 = Vector3(0.0, 3.18, 0.10)
const EXIT_SPOT_TARGET: Vector3 = Vector3(0.0, 1.20, 0.0)
const EXIT_SPOT_ENERGY: float = 5.0
const EXIT_SPOT_RANGE: float = 8.5
const EXIT_SPOT_ANGLE: float = 26.0
const EXIT_CONFETTI_COUNT: int = 30
const EXIT_CONFETTI_SPREAD: float = 1.05
const EXIT_CONFETTI_RISE: float = 2.20
const EXIT_CONFETTI_SIZE: Vector3 = Vector3(0.030, 0.010, 0.080)
const EXIT_CONFETTI_ENERGY: float = 1.60
# 彩带按弹道模拟：进度 0..1 映射到 FLIGHT 秒，之后受重力落回地面并淡出，
# 不会停在半空。所有量都是确定性的，seek 可复现。
const EXIT_CONFETTI_FLIGHT: float = 2.60
const EXIT_CONFETTI_GRAVITY: float = 9.80
const EXIT_CONFETTI_DELAY: float = 0.45
const EXIT_PODIUM_FLOOR_SIZE: Vector3 = Vector3(1.70, 0.06, 0.53)
const EXIT_PODIUM_FLOOR_CENTER: Vector3 = Vector3(0.0, FOOT_Y - 0.03, 0.635)

# --- 讲台 / 编号 ---------------------------------------------------------
# 台沿顶面绝对高度 1.45m，约等于 2.8m 立绘的腰腹。
# 造型：整体实心封闭的下墩+柜体，正面无镂空；平面台沿，不做凸起屏幕。
# 前缘 0.88m，与固定讲台地板（z 0.37..0.90）和退场翻板前沿保持净空。
const PODIUM_WIDTH: float = 2.05
const PODIUM_DEPTH: float = 0.52
const PODIUM_Z: float = 0.62
const PODIUM_LEDGE_TOP_Y: float = 1.45
const PODIUM_LEDGE_THICKNESS: float = 0.08
# 十二席共用桌心：每席占 30°，闭合后是零几何间隙的完整圆环。
const PODIUM_RING_INNER_RADIUS: float = 4.14
const PODIUM_RING_OUTER_RADIUS: float = 4.66
const PODIUM_RING_SEATS: int = 12
const PODIUM_RING_ARC_STEPS: int = 48
const PODIUM_RING_SEAM_WIDTH: float = 0.003
const PODIUM_RING_SEAM_DEPTH: float = 0.005
const PODIUM_RING_TENON_SIZE: float = 0.070
# 圆地台前部固定，后部左右翻板；前界避开讲台外圆，坠落口不扫过柜体。
const PODIUM_PAD_FIXED_FRONT: float = 0.30
# 隔离舱收在人物与讲台之间；板件在圆地台上方伸展，不再穿盘升出。
const ISOLATION_PANEL_BASE_Y: float = FOOT_Y + 0.04
const ISOLATION_FRONT_Z: float = 0.28
const ISOLATION_WING_DEPTH: float = 0.28
const ISOLATION_WING_HINGE_Z: float = -0.01
const ISOLATION_SIDE_DEPTH: float = 1.04
const ISOLATION_SIDE_YAW_DEG: float = 3.302
const ISOLATION_SHUTTER_WIDTH: float = 2.40
const ISOLATION_CANOPY_CLOSED_Y: float = 3.52
const ISOLATION_CANOPY_CLOSED_Z: float = -0.30
# 旧名字保留给既有引用，值跟随新造型。
const PODIUM_HEIGHT: float = PODIUM_LEDGE_TOP_Y
const PODIUM_TOP_THICKNESS: float = PODIUM_LEDGE_THICKNESS

# 实心基座：略宽的下墩 + 收到台沿下表面的主柜体，两者都落地封闭。
const PODIUM_BASE_WIDTH: float = 1.56
const PODIUM_BASE_HEIGHT: float = 0.14
const PODIUM_BASE_DEPTH: float = 0.52
const PODIUM_BODY_WIDTH: float = 1.48
const PODIUM_BODY_DEPTH: float = 0.48
const PODIUM_BODY_HEIGHT: float = PODIUM_LEDGE_TOP_Y - PODIUM_LEDGE_THICKNESS - PODIUM_BASE_HEIGHT
const PODIUM_BODY_FRONT_Z: float = PODIUM_Z + PODIUM_BODY_DEPTH * 0.5

# 正面中央大号编号圆盘（①式）：常态深灰哑光底 + 白灰数字。
const PODIUM_DISC_RADIUS: float = 0.27
const PODIUM_DISC_THICKNESS: float = 0.022
const PODIUM_DISC_Y: float = 0.92
const PODIUM_DISC_Z: float = PODIUM_BODY_FRONT_Z + PODIUM_DISC_THICKNESS * 0.5
const PODIUM_DISC_RING_INNER: float = PODIUM_DISC_RADIUS + 0.012
const PODIUM_DISC_RING_OUTER: float = PODIUM_DISC_RADIUS + 0.040
const PODIUM_DISC_RING_Z: float = PODIUM_DISC_Z + 0.001
const PODIUM_DISC_LABEL_Z: float = PODIUM_BODY_FRONT_Z + PODIUM_DISC_THICKNESS + 0.004
const PODIUM_NUMBER_FONT_SIZE: int = 96
const PODIUM_NUMBER_PIXEL_SIZE: float = 0.004
const PODIUM_NUMBER_OUTLINE_SIZE: int = 8

# 警长态金色光：只照亮编号圆盘与台沿正面，能量低、范围小。
const PODIUM_SHERIFF_LIGHT_POS: Vector3 = Vector3(0.0, PODIUM_DISC_Y, PODIUM_BODY_FRONT_Z + 0.12)
const PODIUM_SHERIFF_LIGHT_RANGE: float = 2.40
const PODIUM_SHERIFF_LIGHT_ENERGY: float = 0.25

# --- 席位专属色灯 --------------------------------------------------------
# 每个席位常亮自己的颜色：脚下光池、讲台上下光带、舱内竖向灯条、低位补光。
# 不再加地面圆环——席位会随竞选整体升高，环状网格会在升降途中穿过固定席位环。
# 立绘材质是 unshaded，灯光主要落在讲台、地面与舱体上，形成一块同色光池。
const ACCENT_TRIM_ENERGY: float = 1.60
const ACCENT_GLOW_ENERGY: float = 1.10
const ACCENT_LIGHT_ENERGY: float = 0.70

# --- 中央圆桌 ------------------------------------------------------------
const TABLE_MAX_RADIUS: float = 4.8
const TABLE_MIN_RADIUS: float = 1.0
const TABLE_CLEARANCE: float = 1.20
const TABLE_HEIGHT: float = 0.72
const TABLE_TOP_THICKNESS: float = 0.12
const TABLE_TOP_SEGMENTS: int = 64
# 十二块平齐扇形板零间隙拼装；拼缝只用顶面 2mm 深色细线表达。
const TABLE_INNER_RADIUS: float = 0.0
const TABLE_SEAM_GAP: float = 0.0
const TABLE_SEAM_LINE_WIDTH: float = 0.002

# --- 房间 ----------------------------------------------------------------
const ROOM_RADIUS_PAD: float = 11.0
const ROOM_FLOOR_EXTRA: float = 0.7
const ROOM_WALL_HEIGHT: float = 11.0
const ROOM_WALL_THICKNESS: float = 0.35
const ROOM_WALL_SEGMENTS: int = 24
const ROOM_STRIP_INTERVAL: int = 2
const ROOM_RIB_INTERVAL: int = 4

# --- 服务器机房（环形数据中心） -----------------------------------------
# 只由 arena._build_room() 使用；不改变既有房间尺寸与灯光。
# 48 个 7.5° 单元沿 16m 墙线排成闭环，每个单元正面再分成两列 0.96m 柜面，
# 用一张程序化 2D 贴图表达槽位，不为每个槽位建模。
const SERVER_CABINET_COUNT: int = 48
const SERVER_CABINET_HEIGHT: float = 2.40
const SERVER_CABINET_DEPTH: float = 0.60
const SERVER_CABINET_GAP: float = 0.07
const SERVER_CABINET_BASE_Y: float = 0.10
# 柜背与墙内表面的净距；柜正面因此停在约 15.17m，仍给开场 15m 机位留出余量。
const SERVER_CABINET_WALL_GAP: float = 0.08
# 第二层：机柜顶以上的检修走道与退进暗墙带。
const SERVER_WALKWAY_INNER: float = 14.55
const SERVER_WALKWAY_OUTER: float = 15.88
const SERVER_WALKWAY_BOTTOM: float = 2.97
const SERVER_WALKWAY_TOP: float = 3.10
const SERVER_UPPER_BAND_RADIUS: float = 15.76
const SERVER_UPPER_BAND_BOTTOM: float = 3.10
const SERVER_UPPER_BAND_TOP: float = 6.30
const SERVER_UPPER_BAND_DEPTH: float = 0.12
const SERVER_UPPER_RIB_COUNT: int = 24
const SERVER_TOP_LIGHT_Y: float = 6.52
const SERVER_TOP_LIGHT_INNER: float = 15.55
const SERVER_TOP_LIGHT_OUTER: float = 15.63
# 地面细线：3 圈同心 + 12 条 30° 径向线，全部落在隔离栏台之外。
const SERVER_FLOOR_RING_RADIUS_A: float = 8.90
const SERVER_FLOOR_RING_RADIUS_B: float = 11.75
const SERVER_FLOOR_RING_RADIUS_C: float = 14.55
const SERVER_FLOOR_RADIAL_COUNT: int = 12
const SERVER_FLOOR_RADIAL_INNER: float = 7.60
const SERVER_FLOOR_RADIAL_OUTER: float = 14.55
# 程序化柜面贴图：固定种子，运行时只生成一次。
const SERVER_TEXTURE_WIDTH: int = 256
const SERVER_TEXTURE_HEIGHT: int = 512
const SERVER_TEXTURE_SEED: int = 20261102
const SERVER_SLOT_ROWS: int = 10

# --- 服务器机房颜色 / 发光 ------------------------------------------------
const COLOR_SERVER_SHELL: Color = Color(0.050, 0.058, 0.074, 1.0)
const COLOR_SERVER_BODY: Color = Color(0.078, 0.090, 0.112, 1.0)
const COLOR_SERVER_FACE_BASE: Color = Color(0.043, 0.051, 0.066, 1.0)
const COLOR_SERVER_SEAM: Color = Color(0.290, 0.430, 0.960, 1.0)
const COLOR_SERVER_LED_BLUE: Color = Color(0.300, 0.520, 1.000, 1.0)
const COLOR_SERVER_LED_VIOLET: Color = Color(0.560, 0.380, 1.000, 1.0)
const COLOR_SERVER_FLOOR_INLAY: Color = Color(0.190, 0.260, 0.400, 1.0)
const SERVER_SEAM_EMISSION: float = 0.30
const SERVER_INLAY_EMISSION: float = 0.10

# --- 发言灯 --------------------------------------------------------------
# 发言灯移到讲台前方（z=1.30，台沿前沿之外），不再做台面中心光圈。
const SPEAKER_LIGHT_POS: Vector3 = Vector3(0.0, 2.20, 1.30)
const SPEAKER_LIGHT_TARGET: Vector3 = Vector3(0.0, 2.05, 0.0)
const SPEAKER_LIGHT_RANGE: float = 7.0
const SPEAKER_LIGHT_ANGLE: float = 34.0
const SPEAKER_LIGHT_ACTIVE_ENERGY: float = 3.2

# --- 投票反馈 ------------------------------------------------------------
const VOTE_SEGMENTS: int = 18
const VOTE_TUBE_RADIUS: float = 0.075
const VOTE_ENDPOINT_Y: float = 1.65
const VOTE_ARC_LIFT: float = 2.30
const VOTE_MARKER_RADIUS: float = 0.09

# --- 颜色 ----------------------------------------------------------------
const COLOR_PUBLIC: Color = Color(0.301961, 0.419608, 0.996078, 1.0)
const COLOR_LOCK: Color = Color(0.725490, 0.823529, 1.0, 1.0)
const COLOR_METAL_DARK: Color = Color(0.086275, 0.101961, 0.125490, 1.0)
const COLOR_METAL_MID: Color = Color(0.23, 0.24, 0.26, 1.0)
const COLOR_METAL_LIGHT: Color = Color(0.43, 0.44, 0.46, 1.0)
const COLOR_FLOOR: Color = Color(0.062745, 0.078431, 0.101961, 1.0)
const COLOR_TABLE: Color = Color(0.075, 0.09, 0.115, 1.0)
const COLOR_GLASS: Color = Color(0.035294, 0.050980, 0.078431, 1.0)
# 大面积结构用低金属度哑光面板，白天靠漫反射出层次，而不是靠自发光。
const COLOR_PANEL: Color = Color(0.30, 0.29, 0.28, 1.0)
const COLOR_PANEL_DARK: Color = Color(0.105, 0.115, 0.135, 1.0)
const COLOR_TRIM: Color = Color(0.341176, 0.392157, 0.470588, 1.0)
const COLOR_DAY_AMBIENT: Color = Color(0.63, 0.65, 0.69, 1.0)
const COLOR_NIGHT_AMBIENT: Color = Color(0.32, 0.39, 0.52, 1.0)
const COLOR_DAY_BG: Color = Color(0.062745, 0.094118, 0.145098, 1.0)
const COLOR_NIGHT_BG: Color = Color(0.011765, 0.023529, 0.047059, 1.0)
const COLOR_DAY_SUN: Color = Color(0.941176, 0.964706, 1.0, 1.0)
const COLOR_NIGHT_SUN: Color = Color(0.243137, 0.360784, 0.588235, 1.0)
const COLOR_TABLE_LIGHT_DAY: Color = Color(0.784314, 0.843137, 1.0, 1.0)
const COLOR_TABLE_LIGHT_NIGHT: Color = Color(0.301961, 0.419608, 0.996078, 1.0)
const COLOR_DAY_FILL: Color = Color(0.760784, 0.819608, 0.941176, 1.0)
const COLOR_NIGHT_FILL: Color = Color(0.239216, 0.341176, 0.560784, 1.0)
const COLOR_EXIT_SPOT: Color = Color(1.0, 0.929412, 0.819608, 1.0)
# 席位编号常态白灰，警长态切换为金色。
const COLOR_NUMBER_IDLE: Color = Color(0.839216, 0.866667, 0.909804, 1.0)
const COLOR_SHERIFF_GOLD: Color = Color(1.0, 0.760784, 0.294118, 1.0)

# --- 光照强度（绝对采样端点） -------------------------------------------
const DAY_AMBIENT_ENERGY: float = 0.72
const NIGHT_AMBIENT_ENERGY: float = 0.55
const INTERIOR_LIGHT_POS: Vector3 = Vector3(0.0, 2.55, 0.85)
const INTERIOR_LIGHT_RANGE: float = 4.0
const INTERIOR_LIGHT_ENERGY: float = 0.75
const DAY_SUN_ENERGY: float = 0.45
const NIGHT_SUN_ENERGY: float = 0.10
const DAY_TABLE_LIGHT_ENERGY: float = 0.35
const NIGHT_TABLE_LIGHT_ENERGY: float = 0.30
const ROOM_GLOW_DAY: float = 0.45
const ROOM_GLOW_NIGHT: float = 1.60
const GLOW_DAY: float = 0.35
const GLOW_NIGHT: float = 0.95

# --- 环形中性补光 --------------------------------------------------------
const FILL_LIGHT_COUNT: int = 3
const FILL_LIGHT_HEIGHT: float = 2.55
const FILL_LIGHT_RADIUS_SCALE: float = 0.62
const FILL_LIGHT_RANGE: float = 11.0
const FILL_LIGHT_ATTENUATION: float = 1.0
const DAY_FILL_ENERGY: float = 0.55
const NIGHT_FILL_ENERGY: float = 0.28

const TOP_LIGHT_POS: Vector3 = Vector3(0.0, 7.2, 0.0)
const TOP_LIGHT_RANGE: float = 24.0
const DAY_TOP_ENERGY: float = 1.45
const NIGHT_TOP_ENERGY: float = 0.55

# --- 桌面主灯 ------------------------------------------------------------
const TABLE_LIGHT_POS: Vector3 = Vector3(0.0, 2.95, 0.0)
const TABLE_LIGHT_RANGE: float = 16.0
const TABLE_LIGHT_ATTENUATION: float = 1.15

# --- 舱体自发光端点（绝对采样） -----------------------------------------
const SEAM_OPEN: float = 0.25
const SEAM_CLOSED: float = 0.8
const CANOPY_GLOW_OPEN: float = 0.12
const CANOPY_GLOW_CLOSED: float = 0.18
const SPEAKER_GLOW_IDLE: float = 0.18
const SPEAKER_GLOW_ACTIVE: float = 2.80
const SHERIFF_GLOW_ENERGY: float = 0.85
const VOTE_GLOW_MAX: float = 3.00
