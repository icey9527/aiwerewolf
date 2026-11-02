extends Node3D

# 单个隔离舱。局部坐标：+Z 朝桌心，人物位于 z=0，脚底 y=0.18。
# 开合全部由 set_closed(amount) 绝对采样；本文件不含 Tween/await，
# 不读取剧本、身份或游戏状态，也不创建人物、相机或 UI。

const StageParams = preload("res://config/stage_params.gd")
const CameraParams = preload("res://config/camera_params.gd")
const Geometry = preload("res://stage/geometry.gd")
const SevenSeg = preload("res://stage/seven_segment.gd")
const Catalog = preload("res://resources/character_catalog.gd")

var _seat_index: int = -1
var _built: bool = false
var _closed: float = 0.0
var _speaking: bool = false

var _wing_left_root: Node3D
var _wing_right_root: Node3D
var _shell_root: Node3D
var _canopy_root: Node3D
var _shutter_root: Node3D
var _spot: SpotLight3D
var _interior_light: OmniLight3D

var _hatch_left_root: Node3D
var _hatch_right_root: Node3D
var _floor_seam_ring: MeshInstance3D
var _speaker_ring: MeshInstance3D
var _exit_spot: SpotLight3D
var _confetti_root: Node3D
var _confetti_parts: Array[MeshInstance3D] = []
var _exit_active: bool = false

var _seam_mat: StandardMaterial3D
var _canopy_glow_mat: StandardMaterial3D
var _speaker_mat: StandardMaterial3D

# 旧接口保留：_number_disc / _number_ring 现在分别指向匾额内板与外框，
# set_sheriff 仍按原来的方式切换它们的材质。
var _number_disc: MeshInstance3D
var _number_ring: MeshInstance3D
var _plaque_frame: MeshInstance3D
var _plaque_panel: MeshInstance3D
var _canopy_number_panel: MeshInstance3D
var _canopy_number_mat: ShaderMaterial
var _sheriff_light: OmniLight3D
var _accent_light: OmniLight3D
var _accent_mat: StandardMaterial3D
var _accent_glow_mat: StandardMaterial3D
var _accent_trims: Array[MeshInstance3D] = []
var _accent_color: Color = Color("8fa9ff")
var _number_idle_mat: StandardMaterial3D
var _number_ring_idle_mat: StandardMaterial3D
var _sheriff_gold_mat: StandardMaterial3D
var _sheriff_active: bool = false

func setup(seat_index: int) -> void:
	if _built:
		push_warning("IsolationPod.setup() 只允许调用一次")
		return
	_seat_index = seat_index
	_build_materials()
	_build_floor()
	_build_accent()
	_build_shell()
	_build_rear()
	_build_fixed_sides()
	_build_wings()
	_build_shutter()
	_build_canopy()
	_build_podium()
	_build_exit()
	_build_speaker_light()
	_interior_light = OmniLight3D.new()
	_interior_light.name = "InteriorFill"
	_interior_light.position = StageParams.INTERIOR_LIGHT_POS
	_interior_light.light_color = StageParams.COLOR_LOCK
	_interior_light.omni_range = StageParams.INTERIOR_LIGHT_RANGE
	_interior_light.shadow_enabled = false
	add_child(_interior_light)
	_built = true
	set_closed(0.0)
	set_speaker(false)

func get_seat_index() -> int:
	return _seat_index

func set_speaker(speaking: bool) -> void:
	if not _built or _speaking == speaking:
		return
	_speaking = speaking
	# 普通发言只打人物独立聚光；讲台、地台与编号圆盘不随发言发光。
	if _spot != null:
		_spot.visible = speaking
		_spot.light_energy = StageParams.SPEAKER_LIGHT_ACTIVE_ENERGY if speaking else 0.0

# 警长态只切换匾额外框/内板的材质与轻量金色光，与发言状态完全解耦。
func set_sheriff(active: bool) -> void:
	if not _built or _sheriff_active == active:
		return
	_sheriff_active = active
	var disc_mat: StandardMaterial3D = _number_idle_mat
	var ring_mat: StandardMaterial3D = _sheriff_gold_mat if active else _number_ring_idle_mat
	if _number_disc != null:
		_number_disc.material_override = disc_mat
	if _number_ring != null:
		_number_ring.material_override = ring_mat
	var number_color: Color = StageParams.COLOR_SHERIFF_GOLD if active else _accent_color.lightened(0.35)
	_apply_number_color(number_color)
	if _sheriff_light != null:
		_sheriff_light.visible = active
		_sheriff_light.light_energy = StageParams.PODIUM_SHERIFF_LIGHT_ENERGY if active else 0.0

func set_closed(amount: float) -> void:
	if not _built:
		return
	var t: float = clampf(amount, 0.0, 1.0)
	_closed = t
	_interior_light.light_energy = StageParams.INTERIOR_LIGHT_ENERGY * t
	# 墙与前挡在圆地台上方伸展，底缘始终高于 .18m 地台，避开翻板。
	var panel_scale: float = maxf(t, 0.0001)
	if _shell_root != null:
		_shell_root.position.y = StageParams.ISOLATION_PANEL_BASE_Y
		_shell_root.scale.y = panel_scale
		_shell_root.visible = t > 0.0001
	var yaw: float = deg_to_rad(StageParams.WING_CLOSED_YAW_DEG) * t
	for wing: Node3D in [_wing_left_root, _wing_right_root]:
		if wing == null:
			continue
		wing.position.y = StageParams.ISOLATION_PANEL_BASE_Y
		wing.position.z = StageParams.ISOLATION_WING_HINGE_Z
		wing.scale.y = panel_scale
		wing.visible = t > 0.0001
		wing.rotation.y = yaw if wing == _wing_left_root else -yaw
	if _shutter_root != null:
		_shutter_root.position.y = StageParams.ISOLATION_PANEL_BASE_Y + StageParams.WALL_HEIGHT * t * 0.5
		_shutter_root.scale.y = panel_scale
		_shutter_root.visible = t > 0.0001
	if _canopy_root != null:
		var canopy_pos: Vector3 = _canopy_root.position
		canopy_pos.y = lerpf(StageParams.CANOPY_OPEN_Y, StageParams.ISOLATION_CANOPY_CLOSED_Y, t)
		canopy_pos.z = lerpf(StageParams.CANOPY_OPEN_Z, StageParams.ISOLATION_CANOPY_CLOSED_Z, t)
		_canopy_root.position = canopy_pos
	Geometry.set_emission(_seam_mat, lerpf(StageParams.SEAM_OPEN, StageParams.SEAM_CLOSED, t))
	Geometry.set_emission(_canopy_glow_mat, lerpf(StageParams.CANOPY_GLOW_OPEN, StageParams.CANOPY_GLOW_CLOSED, t))

# 绝对采样：fall 开翻板，spotlight 开聚光，confetti 抬升确定性彩带。
# active=false 时无条件归零；调用方每帧先清其他舱再设置目标。
func set_exit(active: bool, fall: float, spotlight: float, confetti: float) -> void:
	if not _built:
		return
	var on: bool = active
	if not on:
		fall = 0.0
		spotlight = 0.0
		confetti = 0.0
	if not on and not _exit_active:
		return
	_exit_active = on
	var f: float = clampf(fall, 0.0, 1.0)
	var s: float = clampf(spotlight, 0.0, 1.0)
	var c: float = clampf(confetti, 0.0, 1.0)
	var angle: float = deg_to_rad(StageParams.EXIT_FALL_ANGLE_DEG) * f
	if _hatch_left_root != null:
		_hatch_left_root.rotation.z = -angle
	if _hatch_right_root != null:
		_hatch_right_root.rotation.z = angle
	# 地面光环随翻板开启下沉并隐藏，避免悬在打开的舱口上。
	var ring_y: float = StageParams.FOOT_Y + 0.005 - 0.55 * f
	if _floor_seam_ring != null:
		var seam_pos: Vector3 = _floor_seam_ring.position
		seam_pos.y = ring_y
		_floor_seam_ring.position = seam_pos
		_floor_seam_ring.visible = f < 0.55
	if _speaker_ring != null:
		var speaker_pos: Vector3 = _speaker_ring.position
		speaker_pos.y = ring_y + 0.001
		_speaker_ring.position = speaker_pos
		_speaker_ring.visible = f < 0.55
	if _exit_spot != null:
		_exit_spot.visible = on and s > 0.001
		_exit_spot.light_energy = StageParams.EXIT_SPOT_ENERGY * s
	if _confetti_root != null:
		_confetti_root.visible = on and c > 0.001
		if _confetti_root.visible:
			_update_confetti(c)

func _update_confetti(amount: float) -> void:
	# amount 0..1 → FLIGHT 秒的绝对时间，再做重力弹道：先上抛，落回地面后
	# 留 0.35s 再收起。每片有固定延迟和固定黄金角分布，seek/回放完全一致。
	var gravity: float = StageParams.EXIT_CONFETTI_GRAVITY
	var speed: float = sqrt(2.0 * gravity * StageParams.EXIT_CONFETTI_RISE)
	var floor_y: float = StageParams.FOOT_Y + 0.02
	var hatch_z: float = -0.30
	for i in range(_confetti_parts.size()):
		var part: MeshInstance3D = _confetti_parts[i]
		var fi: float = float(i)
		var delay: float = StageParams.EXIT_CONFETTI_DELAY * fmod(fi * 0.754877666 + 0.113, 1.0)
		var t: float = amount * StageParams.EXIT_CONFETTI_FLIGHT - delay
		if t <= 0.0:
			part.visible = false
			continue
		var ang: float = TAU * fmod(fi * 0.38196601125 + 0.137, 1.0)
		var radial: float = StageParams.EXIT_CONFETTI_SPREAD * (0.25 + 0.75 * fmod(fi * 0.61803398875 + 0.071, 1.0))
		var base_y: float = StageParams.FOOT_Y + 1.05 + 0.30 * fmod(fi * 0.754877666 + 0.193, 1.0)
		var y: float = base_y + speed * t - 0.5 * gravity * t * t
		var drift: float = 0.30 * t
		var land_t: float = (speed + sqrt(speed * speed + 2.0 * gravity * (base_y - floor_y))) / gravity
		if y <= floor_y:
			if t > land_t + 0.35:
				part.visible = false
				continue
			part.visible = true
			var fade: float = clampf((t - land_t) / 0.35, 0.0, 1.0)
			part.position = Vector3(cos(ang) * (radial + drift), floor_y, sin(ang) * (radial + drift) + hatch_z)
			part.rotation_degrees = Vector3(-90.0, fi * 53.0, fi * 29.0)
			part.scale = Vector3.ONE * lerpf(1.0, 0.15, fade)
			continue
		part.visible = true
		part.scale = Vector3.ONE
		part.position = Vector3(cos(ang) * (radial + drift), y, sin(ang) * (radial + drift) + hatch_z)
		part.rotation_degrees = Vector3(320.0 * t + fi * 37.0, 210.0 * t + fi * 53.0, 140.0 * t + fi * 29.0)

func _build_materials() -> void:
	_seam_mat = Geometry.make_emissive(StageParams.COLOR_LOCK, StageParams.SEAM_OPEN)
	_canopy_glow_mat = Geometry.make_emissive(StageParams.COLOR_LOCK, StageParams.CANOPY_GLOW_OPEN)
	_speaker_mat = Geometry.make_emissive(StageParams.COLOR_PUBLIC, StageParams.SPEAKER_GLOW_IDLE)
	# 匾额内板用深色面板，外框用金属亮边；警长态只把外框换成金色。
	_number_idle_mat = Geometry.material(&"panel_dark")
	_number_ring_idle_mat = Geometry.material(&"metal_light")
	_sheriff_gold_mat = Geometry.make_emissive(StageParams.COLOR_SHERIFF_GOLD, StageParams.SHERIFF_GLOW_ENERGY)

func _build_floor() -> void:
	var pad_radius: float = StageParams.FLOOR_PAD_RADIUS
	var metal_mid: StandardMaterial3D = Geometry.material(&"metal_mid")
	var panel: StandardMaterial3D = Geometry.material(&"panel")
	var glass: StandardMaterial3D = Geometry.material(&"glass")
	# 舱底中间是左右翻板，翻板下方是暗色井口；讲台下方保留固定小地板。
	Geometry.add_cylinder(self, "ExitUnder", pad_radius * 0.84, pad_radius * 0.84, 0.020, Vector3(0.0, StageParams.FLOOR_UNDER_Y, 0.0), glass, 32, false)
	Geometry.add_torus(self, "FloorCollar", pad_radius * 0.78, pad_radius * 1.02, Vector3(0.0, StageParams.FLOOR_COLLAR_Y, 0.0), metal_mid, 48, 8, false)
	_floor_seam_ring = Geometry.add_torus(self, "FloorSeam", pad_radius * 0.93 - 0.025, pad_radius * 0.93 + 0.025, Vector3(0.0, StageParams.FOOT_Y + 0.005, 0.0), _seam_mat, 48, 8, false)
	_speaker_ring = Geometry.add_torus(self, "SpeakerRing", pad_radius * 0.68 - 0.020, pad_radius * 0.68 + 0.020, Vector3(0.0, StageParams.FOOT_Y + 0.006, 0.0), _speaker_mat, 48, 8, false)
	# 前部固定圆弧与圆地台同心；不再创建方形垫板或梯形补板。
	var fixed_outline: Array[Vector2] = _clip_pad_outline(_pad_outline(), 1, StageParams.PODIUM_PAD_FIXED_FRONT, true)
	var fixed_surface: SurfaceTool = _podium_surface()
	_append_pad_prism(fixed_surface, fixed_outline, StageParams.FOOT_Y - StageParams.HATCH_THICKNESS, StageParams.FOOT_Y)
	_commit_podium_mesh("PodiumRoundFloor", panel, fixed_surface, false)
	# 铰轴位于圆盘最外缘，整片只向下翻，外侧不会翘出圆座。
	var hatch_width: float = pad_radius
	var hinge_y: float = StageParams.FOOT_Y - StageParams.HATCH_THICKNESS * 0.5
	_hatch_left_root = Node3D.new()
	_hatch_left_root.name = "HatchLeft"
	_hatch_left_root.position = Vector3(-hatch_width, hinge_y, StageParams.HATCH_CENTER_Z)
	add_child(_hatch_left_root)
	_build_round_hatch(_hatch_left_root, "HatchLeafL", true, panel)
	_hatch_right_root = Node3D.new()
	_hatch_right_root.name = "HatchRight"
	_hatch_right_root.position = Vector3(hatch_width, hinge_y, StageParams.HATCH_CENTER_Z)
	add_child(_hatch_right_root)
	_build_round_hatch(_hatch_right_root, "HatchLeafR", false, panel)

func _build_accent() -> void:
	var pad: float = StageParams.FLOOR_PAD_RADIUS
	_accent_mat = Geometry.make_emissive(_accent_color, StageParams.ACCENT_TRIM_ENERGY)
	_accent_glow_mat = Geometry.make_emissive(_accent_color, StageParams.ACCENT_GLOW_ENERGY)
	# 不再在地面铺同色光池：用户要求去掉这块自发光地面。
	# 光带沿同心圆表面走弧线，避免旧直灯条悬在圆柜体外。
	var trim_surface: SurfaceTool = _podium_surface()
	var half_angle: float = PI / float(StageParams.PODIUM_RING_SEATS)
	for radius: float in [StageParams.PODIUM_RING_INNER_RADIUS, StageParams.PODIUM_RING_OUTER_RADIUS]:
		for height: float in [1.20, StageParams.FOOT_Y + 0.195]:
			_append_podium_ring(trim_surface, radius - 0.001, radius + 0.001, height - 0.012, height + 0.012, -half_angle + 0.025, half_angle - 0.025)
	_accent_trims.append(_commit_podium_mesh("AccentTrims", _accent_mat, trim_surface, false))
	_accent_light = OmniLight3D.new()
	_accent_light.name = "SeatAccentLight"
	_accent_light.position = Vector3(0.0, 1.55, 0.10)
	_accent_light.light_color = _accent_color
	_accent_light.omni_range = 2.2
	# 席位色灯不打高光，避免在桌面/讲台上映出角色色的反光。
	_accent_light.light_specular = 0.0
	_accent_light.light_energy = StageParams.ACCENT_LIGHT_ENERGY
	_accent_light.shadow_enabled = false
	add_child(_accent_light)

# 每个席位常亮的专属色：脚边光环 + 低位补光 + 讲台数码管同色。
func set_accent_color(color: Color) -> void:
	_accent_color = color
	if _accent_mat != null:
		_accent_mat.albedo_color = color.darkened(0.55)
		_accent_mat.emission = color
	if _accent_glow_mat != null:
		_accent_glow_mat.albedo_color = color.darkened(0.55)
		_accent_glow_mat.emission = color
	if _accent_light != null:
		_accent_light.light_color = color
	if _spot != null:
		_spot.light_color = color.lightened(0.18)
	if not _sheriff_active:
		_apply_number_color(color.lightened(0.35))

func _apply_number_color(color: Color) -> void:
	# 正面已改为文字匾额；席位色仍同步到舱顶七段数码管的点亮颜色。
	if _canopy_number_mat != null:
		_canopy_number_mat.set_shader_parameter("lit_color", color)

func _build_shell() -> void:
	# 后壁与固定侧墙共用伸展根节点；白天收起，夜间从圆地台上方长出。
	_shell_root = Node3D.new()
	_shell_root.name = "Shell"
	_shell_root.position = Vector3(0.0, StageParams.ISOLATION_PANEL_BASE_Y, 0.0)
	add_child(_shell_root)

func _build_rear() -> void:
	var panel_dark: StandardMaterial3D = Geometry.material(&"panel_dark")
	var panel: StandardMaterial3D = Geometry.material(&"panel")
	var trim: StandardMaterial3D = Geometry.material(&"trim")
	Geometry.add_box(_shell_root, "RearWall", Vector3(StageParams.POD_WIDTH + 0.06, StageParams.WALL_HEIGHT, 0.18), Vector3(0.0, StageParams.WALL_HEIGHT * 0.5, StageParams.POD_REAR_Z), panel, Vector3.ZERO, true)
	var spine_height: float = StageParams.WALL_HEIGHT + 0.10
	Geometry.add_box(_shell_root, "RearSpine", Vector3(StageParams.POD_WIDTH * 0.34, spine_height, 0.24), Vector3(0.0, spine_height * 0.5, StageParams.POD_REAR_Z - 0.20), panel_dark, Vector3.ZERO, true)
	# 原高处导轨会随 shell 下沉后在地面以上留下短柱，也容易挡住人物，故不再创建。
	Geometry.add_box(_shell_root, "RearLockStrip", Vector3(StageParams.POD_WIDTH * 0.62, 0.035, 0.015), Vector3(0.0, 2.55, StageParams.POD_REAR_Z - 0.095), _seam_mat, Vector3.ZERO, false)
	var inner_z: float = StageParams.POD_REAR_Z + 0.095
	Geometry.add_box(_shell_root, "RearInnerGlowL", Vector3(0.035, 2.30, 0.015), Vector3(-StageParams.POD_WIDTH * 0.30, 1.80, inner_z), _accent_glow_mat, Vector3.ZERO, false)
	Geometry.add_box(_shell_root, "RearInnerGlowR", Vector3(0.035, 2.30, 0.015), Vector3(StageParams.POD_WIDTH * 0.30, 1.80, inner_z), _accent_glow_mat, Vector3.ZERO, false)
	# 横向饰条把后壁分成几段，白天靠明暗层次而不是发光区分结构。
	Geometry.add_box(_shell_root, "RearBandLow", Vector3(StageParams.POD_WIDTH * 0.88, 0.050, 0.025), Vector3(0.0, 1.10, StageParams.POD_REAR_Z + 0.102), trim, Vector3.ZERO, false)
	Geometry.add_box(_shell_root, "RearBandHigh", Vector3(StageParams.POD_WIDTH * 0.88, 0.050, 0.025), Vector3(0.0, 2.28, StageParams.POD_REAR_Z + 0.102), trim, Vector3.ZERO, false)

func _build_fixed_sides() -> void:
	var panel: StandardMaterial3D = Geometry.material(&"panel")
	var trim: StandardMaterial3D = Geometry.material(&"trim")
	var depth: float = StageParams.ISOLATION_SIDE_DEPTH
	for side_index in range(2):
		var side: float = -1.0 if side_index == 0 else 1.0
		var tag: String = "L" if side < 0.0 else "R"
		# 侧墙前端收至半宽约 1.24m，与短侧翼后铰点对齐。
		var root: Node3D = Node3D.new()
		root.name = "FixedSide" + tag
		root.position = Vector3(side * StageParams.POD_HALF_WIDTH, 0.0, StageParams.POD_REAR_Z)
		root.rotation.y = -side * deg_to_rad(StageParams.ISOLATION_SIDE_YAW_DEG)
		_shell_root.add_child(root)
		Geometry.add_box(root, "SideFixed" + tag, Vector3(StageParams.WALL_THICKNESS, StageParams.WALL_HEIGHT, depth), Vector3(0.0, StageParams.WALL_HEIGHT * 0.5, depth * 0.5), panel, Vector3.ZERO, true)
		var inner_x: float = -side * (StageParams.WALL_THICKNESS * 0.5 + 0.008)
		Geometry.add_box(root, "SideInnerGlow" + tag, Vector3(0.012, StageParams.WALL_HEIGHT * 0.72, 0.035), Vector3(inner_x, StageParams.WALL_HEIGHT * 0.55, depth * 0.5), _accent_glow_mat, Vector3.ZERO, false)
		var outer_x: float = side * (StageParams.WALL_THICKNESS * 0.5 + 0.010)
		Geometry.add_box(root, "SideOuterTrim" + tag, Vector3(0.020, StageParams.WALL_HEIGHT * 0.84, 0.050), Vector3(outer_x, StageParams.WALL_HEIGHT * 0.5, depth * 0.5), trim, Vector3.ZERO, false)

func _build_wings() -> void:
	var panel: StandardMaterial3D = Geometry.material(&"panel")
	for side_index in range(2):
		var side: float = -1.0 if side_index == 0 else 1.0
		var tag: String = "L" if side < 0.0 else "R"
		var root: Node3D = Node3D.new()
		root.name = "Wing" + tag
		# 短翼在讲台后方合拢，整段的径向距离始终大于讲台外半径。
		root.position = Vector3(side * StageParams.WING_HINGE_X, StageParams.ISOLATION_PANEL_BASE_Y, StageParams.ISOLATION_WING_HINGE_Z)
		add_child(root)
		if side < 0.0:
			_wing_left_root = root
		else:
			_wing_right_root = root
		var mid_z: float = StageParams.ISOLATION_WING_DEPTH * 0.5
		Geometry.add_box(root, "Panel", Vector3(StageParams.WALL_THICKNESS, StageParams.WALL_HEIGHT, StageParams.ISOLATION_WING_DEPTH), Vector3(0.0, StageParams.WALL_HEIGHT * 0.5, mid_z), panel, Vector3.ZERO, true)
		Geometry.add_box(root, "FrontSeam", Vector3(StageParams.WALL_THICKNESS + 0.03, StageParams.WALL_HEIGHT * 0.86, 0.025), Vector3(0.0, StageParams.WALL_HEIGHT * 0.5, StageParams.ISOLATION_WING_DEPTH), _seam_mat, Vector3.ZERO, false)
		var inner_x: float = -side * (StageParams.WALL_THICKNESS * 0.5 + 0.007)
		Geometry.add_box(root, "InnerGlow", Vector3(0.012, StageParams.WALL_HEIGHT * 0.66, 0.030), Vector3(inner_x, StageParams.WALL_HEIGHT * 0.54, mid_z), _accent_glow_mat, Vector3.ZERO, false)

func _build_shutter() -> void:
	var panel_dark: StandardMaterial3D = Geometry.material(&"panel_dark")
	_shutter_root = Node3D.new()
	_shutter_root.name = "FrontShutter"
	_shutter_root.position = Vector3(0.0, StageParams.ISOLATION_PANEL_BASE_Y + StageParams.WALL_HEIGHT * 0.5, StageParams.ISOLATION_FRONT_Z)
	add_child(_shutter_root)
	Geometry.add_box(_shutter_root, "ShutterPanel", Vector3(StageParams.ISOLATION_SHUTTER_WIDTH, StageParams.WALL_HEIGHT, 0.10), Vector3.ZERO, panel_dark, Vector3.ZERO, true)
	Geometry.add_box(_shutter_root, "ShutterSeamA", Vector3(StageParams.ISOLATION_SHUTTER_WIDTH * 0.82, 0.035, 0.018), Vector3(0.0, 0.62, 0.06), _accent_glow_mat, Vector3.ZERO, false)
	Geometry.add_box(_shutter_root, "ShutterSeamB", Vector3(StageParams.ISOLATION_SHUTTER_WIDTH * 0.82, 0.035, 0.018), Vector3(0.0, -0.62, 0.06), _accent_glow_mat, Vector3.ZERO, false)
	Geometry.add_box(_shutter_root, "ShutterSeamC", Vector3(0.030, StageParams.WALL_HEIGHT * 0.78, 0.018), Vector3(0.0, 0.0, 0.06), _accent_glow_mat, Vector3.ZERO, false)

func _build_canopy() -> void:
	var canopy_mat: StandardMaterial3D = Geometry.material(&"canopy")
	var metal_light: StandardMaterial3D = Geometry.material(&"metal_light")
	_canopy_root = Node3D.new()
	_canopy_root.name = "Canopy"
	_canopy_root.position = Vector3(0.0, StageParams.CANOPY_OPEN_Y, StageParams.CANOPY_OPEN_Z)
	add_child(_canopy_root)
	# 顶罩覆盖缩短后的舱体，所有半宽位于本席 30° 分界内。
	var closed_z: float = StageParams.ISOLATION_CANOPY_CLOSED_Z
	Geometry.add_trapezoid(_canopy_root, "CanopyRear", StageParams.POD_REAR_Z - closed_z, StageParams.ISOLATION_WING_HINGE_Z - closed_z, 1.36, 1.30, StageParams.CANOPY_BODY_HEIGHT, 0.0, canopy_mat)
	Geometry.add_trapezoid(_canopy_root, "CanopyFront", StageParams.ISOLATION_WING_HINGE_Z - closed_z, StageParams.ISOLATION_FRONT_Z - closed_z, 1.30, 1.25, StageParams.CANOPY_BODY_HEIGHT, 0.0, canopy_mat)
	var glow: MeshInstance3D = Geometry.add_cylinder(_canopy_root, "CanopyGlow", StageParams.CANOPY_RADIUS * 0.96, StageParams.CANOPY_RADIUS * 0.96, StageParams.CANOPY_GLOW_HEIGHT, Vector3(0.0, -0.073, 0.0), _canopy_glow_mat, 8, false)
	glow.scale = Vector3(1.0, 1.0, 0.45)
	var top: MeshInstance3D = Geometry.add_cylinder(_canopy_root, "CanopyTop", StageParams.CANOPY_RADIUS * 0.86, StageParams.CANOPY_RADIUS * 0.86, StageParams.CANOPY_TOP_HEIGHT, Vector3(0.0, 0.077, 0.0), metal_light, 8, false)
	top.scale = Vector3(1.0, 1.0, 0.45)
	var rim: MeshInstance3D = Geometry.add_cylinder(_canopy_root, "CanopyRim", StageParams.CANOPY_RADIUS * 1.005, StageParams.CANOPY_RADIUS * 1.005, 0.030, Vector3.ZERO, _seam_mat, 8, false)
	rim.scale = Vector3(1.0, 1.0, 0.45 * 0.995)
	# 棚顶朝上的数码管编号：高位俯视和开场俯拍能直接读出座位号。
	_canopy_number_mat = SevenSeg.make_material(_seat_index + 1, StageParams.COLOR_NUMBER_IDLE)
	_canopy_number_panel = SevenSeg.make_panel(_canopy_number_mat, Vector2(0.92, 0.50))
	_canopy_number_panel.name = "CanopyNumber"
	_canopy_number_panel.position = Vector3(0.0, 0.100, 0.0)
	_canopy_number_panel.rotation.x = -PI * 0.5
	_canopy_root.add_child(_canopy_number_panel)


func _build_podium() -> void:
	# 各席以桌心为圆心生成同半径的 30° 环段，端面不缩角、不留洞。
	# 整段与脚下圆地台均留在 Pod 根下，竞选时由 Arena 整体升降。
	var metal_mid: StandardMaterial3D = Geometry.material(&"metal_mid")
	var metal_light: StandardMaterial3D = Geometry.material(&"metal_light")
	var panel: StandardMaterial3D = Geometry.material(&"panel")
	var panel_dark: StandardMaterial3D = Geometry.material(&"panel_dark")
	var inner: float = StageParams.PODIUM_RING_INNER_RADIUS
	var outer: float = StageParams.PODIUM_RING_OUTER_RADIUS
	var half_angle: float = PI / float(StageParams.PODIUM_RING_SEATS)
	var top_y: float = StageParams.PODIUM_LEDGE_TOP_Y
	var top_bottom: float = top_y - StageParams.PODIUM_LEDGE_THICKNESS
	var base_y: float = StageParams.FOOT_Y
	var shell: SurfaceTool = _podium_surface()
	_append_podium_ring(shell, inner, outer, base_y + 0.10, top_bottom, -half_angle, half_angle)
	_commit_podium_mesh("PodiumShellPanels", panel, shell)
	# 基座、柜体、台面使用相同内外圆，侧视为落地的厚壁圆筒。
	var base: SurfaceTool = _podium_surface()
	_append_podium_ring(base, inner, outer, 0.0, base_y + 0.10, -half_angle, half_angle)
	_commit_podium_mesh("PodiumMetalModules", metal_mid, base)
	var top: SurfaceTool = _podium_surface()
	_append_recessed_podium_top(top, inner + 0.020, outer - 0.020, top_bottom, top_y, half_angle)
	_commit_podium_mesh("PodiumTop", Geometry.material(&"podium_top"), top)
	var trim: SurfaceTool = _podium_surface()
	for radius: float in [inner, outer - 0.020]:
		_append_recessed_podium_top(trim, radius, radius + 0.020, top_bottom, top_y, half_angle)
	_commit_podium_mesh("PodiumTrim", metal_light, trim, false)

	# 两端各负责半条凹槽、半枚卡榫；合成 3mm 宽、5mm 深的锯槽。
	# 槽底有完整实体背衬，不露地面；卡榫顶面仍与两侧台面齐平。
	var seams: SurfaceTool = _podium_surface()
	var tenons: SurfaceTool = _podium_surface()
	var seam_half: float = StageParams.PODIUM_RING_SEAM_WIDTH * 0.5
	var tenon_half: float = StageParams.PODIUM_RING_TENON_SIZE * 0.5
	for side: float in [-1.0, 1.0]:
		var boundary: float = side * half_angle
		var u0: float = 0.0 if side < 0.0 else -seam_half
		var u1: float = seam_half if side < 0.0 else 0.0
		_append_ring_patch(seams, boundary, u0, u1, inner, outer, top_y - StageParams.PODIUM_RING_SEAM_DEPTH + 0.0001)
		for radius: float in [inner + 0.11, outer - 0.11]:
			var t0: float = 0.0 if side < 0.0 else -tenon_half
			var t1: float = tenon_half if side < 0.0 else 0.0
			_append_ring_patch(seams, boundary, t0 - (0.001 if side > 0.0 else 0.0), t1 + (0.001 if side < 0.0 else 0.0), radius - tenon_half - 0.001, radius + tenon_half + 0.001, top_y + 0.00015)
			_append_ring_patch(tenons, boundary, t0, t1, radius - tenon_half, radius + tenon_half, top_y + 0.0002)
		for radius: float in [inner, outer]:
			var radial: float = -0.0002 if radius == inner else 0.0002
			var a: Vector3 = _podium_ring_point(radius + radial, boundary, base_y)
			var tangent: Vector3 = Vector3(cos(boundary), 0.0, sin(boundary))
			var n: Vector3 = Vector3(sin(boundary), 0.0, -cos(boundary))
			if radius == inner:
				n = -n
			_add_podium_quad(seams, a + tangent * u0, a + tangent * u1, a + tangent * u1 + Vector3.UP * (top_y - base_y), a + tangent * u0 + Vector3.UP * (top_y - base_y), n)
	var groove_mat: StandardMaterial3D = panel_dark.duplicate() as StandardMaterial3D
	groove_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	groove_mat.albedo_color = Color("080b12")
	_commit_podium_mesh("PodiumSeamLines", groove_mat, seams, false)
	_commit_podium_mesh("PodiumTenons", metal_light, tenons, false)

	# 匾额嵌入内圆立面：框与底板顺弧弯曲，中央文字朝桌心。
	var frame: SurfaceTool = _podium_surface()
	var plaque_half: float = 0.48 / inner
	var plaque_inner_half: float = 0.468 / inner
	var plaque_y: float = StageParams.PODIUM_DISC_Y
	for height: float in [plaque_y - 0.120, plaque_y + 0.108]:
		_append_podium_ring(frame, inner - 0.016, inner - 0.003, height, height + 0.012, -plaque_half, plaque_half)
	for side: float in [-1.0, 1.0]:
		var a0: float = -plaque_half if side < 0.0 else plaque_inner_half
		var a1: float = -plaque_inner_half if side < 0.0 else plaque_half
		_append_podium_ring(frame, inner - 0.016, inner - 0.003, plaque_y - 0.108, plaque_y + 0.108, a0, a1)
	_plaque_frame = _commit_podium_mesh("PlaqueFrame", metal_light, frame, false)
	var plate_back: SurfaceTool = _podium_surface()
	_append_podium_ring(plate_back, inner - 0.012, inner + 0.002, plaque_y - 0.108, plaque_y + 0.108, -plaque_inner_half, plaque_inner_half)
	_plaque_panel = _commit_podium_mesh("PlaquePanel", panel_dark, plate_back, false)
	_number_ring = _plaque_frame
	_number_disc = _plaque_panel
	var plate := Label3D.new()
	plate.name = "SeatNamePlate"
	plate.text = Catalog.display_name(_seat_index, true)
	var name_font: Font = load("res://assets/fonts/SourceHanSerifCN-Bold.otf") as Font
	plate.font = name_font
	plate.font_size = 64
	var measured: float = name_font.get_string_size(plate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	plate.pixel_size = minf(0.86 / measured, 0.0034) if measured > 0.0 else 0.0034
	plate.modulate = Color.WHITE
	plate.outline_modulate = Catalog.color(_seat_index)
	plate.outline_size = 12
	plate.shaded = false
	plate.double_sided = true
	var plaque_z: float = _podium_ring_point(inner, 0.0, 0.0).z
	# 平面字卡略高于弧面两端，避免长名字两侧被内圆遮住。
	plate.position = Vector3(0.0, plaque_y, plaque_z + 0.040)
	add_child(plate)
	_sheriff_light = OmniLight3D.new()
	_sheriff_light.name = "SheriffGlow"
	_sheriff_light.position = Vector3(0.0, plaque_y, plaque_z + 0.12)
	_sheriff_light.light_color = StageParams.COLOR_SHERIFF_GOLD
	_sheriff_light.omni_range = StageParams.PODIUM_SHERIFF_LIGHT_RANGE
	_sheriff_light.light_energy = 0.0
	_sheriff_light.shadow_enabled = false
	_sheriff_light.visible = false
	add_child(_sheriff_light)

# 局部 +Z 朝桌心，桌心位于 z=席位环半径，旋转后各席共享边界点。
func _podium_ring_point(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(radius * sin(angle), y, CameraParams.ring_radius(StageParams.PODIUM_RING_SEATS) - radius * cos(angle))

func _append_podium_ring(st: SurfaceTool, inner: float, outer: float, bottom: float, top: float, angle0: float, angle1: float) -> void:
	var steps: int = maxi(1, ceili(StageParams.PODIUM_RING_ARC_STEPS * absf(angle1 - angle0) / (TAU / float(StageParams.PODIUM_RING_SEATS))))
	for i in range(steps):
		var a0: float = lerpf(angle0, angle1, float(i) / float(steps))
		var a1: float = lerpf(angle0, angle1, float(i + 1) / float(steps))
		var ib0: Vector3 = _podium_ring_point(inner, a0, bottom)
		var ib1: Vector3 = _podium_ring_point(inner, a1, bottom)
		var ob0: Vector3 = _podium_ring_point(outer, a0, bottom)
		var ob1: Vector3 = _podium_ring_point(outer, a1, bottom)
		var it0: Vector3 = _podium_ring_point(inner, a0, top)
		var it1: Vector3 = _podium_ring_point(inner, a1, top)
		var ot0: Vector3 = _podium_ring_point(outer, a0, top)
		var ot1: Vector3 = _podium_ring_point(outer, a1, top)
		var radial: Vector3 = Vector3(sin((a0 + a1) * 0.5), 0.0, -cos((a0 + a1) * 0.5))
		_add_podium_quad(st, it0, it1, ot1, ot0, Vector3.UP)
		_add_podium_quad(st, ib0, ob0, ob1, ib1, Vector3.DOWN)
		_add_podium_quad(st, ib0, ib1, it1, it0, -radial)
		_add_podium_quad(st, ob0, ot0, ot1, ob1, radial)
		if i == 0:
			_add_podium_quad(st, ib0, it0, ot0, ob0, Vector3(-cos(a0), 0.0, -sin(a0)))
		if i == steps - 1:
			_add_podium_quad(st, ib1, ob1, ot1, it1, Vector3(cos(a1), 0.0, sin(a1)))

# 下层圆环填实槽底，上层板的两端内收半槽宽，槽壁垂直下切 5mm。
func _append_recessed_podium_top(st: SurfaceTool, inner: float, outer: float, bottom: float, top: float, half_angle: float) -> void:
	var floor_y: float = top - StageParams.PODIUM_RING_SEAM_DEPTH
	_append_podium_ring(st, inner, outer, bottom, floor_y, -half_angle, half_angle)
	var steps: int = StageParams.PODIUM_RING_ARC_STEPS
	var half_width: float = StageParams.PODIUM_RING_SEAM_WIDTH * 0.5
	var inner_edge: float = half_angle - asin(half_width / inner)
	var outer_edge: float = half_angle - asin(half_width / outer)
	for i in range(steps):
		var f0: float = float(i) / float(steps)
		var f1: float = float(i + 1) / float(steps)
		var ia0: float = lerpf(-inner_edge, inner_edge, f0)
		var ia1: float = lerpf(-inner_edge, inner_edge, f1)
		var oa0: float = lerpf(-outer_edge, outer_edge, f0)
		var oa1: float = lerpf(-outer_edge, outer_edge, f1)
		var it0: Vector3 = _podium_ring_point(inner, ia0, top)
		var it1: Vector3 = _podium_ring_point(inner, ia1, top)
		var ot0: Vector3 = _podium_ring_point(outer, oa0, top)
		var ot1: Vector3 = _podium_ring_point(outer, oa1, top)
		var down: Vector3 = Vector3.DOWN * StageParams.PODIUM_RING_SEAM_DEPTH
		var radial := Vector3(sin((ia0 + ia1) * 0.5), 0.0, -cos((ia0 + ia1) * 0.5))
		_add_podium_quad(st, it0, it1, ot1, ot0, Vector3.UP)
		_add_podium_quad(st, it0 + down, it1 + down, it1, it0, -radial)
		_add_podium_quad(st, ot0 + down, ot0, ot1, ot1 + down, radial)
		if i == 0:
			_add_podium_quad(st, it0 + down, it0, ot0, ot0 + down, Vector3(-cos(half_angle), 0.0, sin(half_angle)))
		if i == steps - 1:
			_add_podium_quad(st, it1 + down, ot1 + down, ot1, it1, Vector3(cos(half_angle), 0.0, sin(half_angle)))

func _append_ring_patch(st: SurfaceTool, angle: float, u0: float, u1: float, r0: float, r1: float, y: float) -> void:
	var tangent: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var a: Vector3 = _podium_ring_point(r0, angle, y)
	var b: Vector3 = _podium_ring_point(r1, angle, y)
	_add_podium_quad(st, a + tangent * u0, a + tangent * u1, b + tangent * u1, b + tangent * u0, Vector3.UP)

# 圆地台前固定弧与左右翻板共用圆轮廓，接合边没有方角。
func _pad_outline() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in range(128):
		var a: float = TAU * float(i) / 128.0
		points.append(Vector2(cos(a), sin(a)) * StageParams.FLOOR_PAD_RADIUS)
	return points

func _clip_pad_outline(points: Array[Vector2], axis: int, value: float, keep_greater: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var da: float = a[axis] - value
		var db: float = b[axis] - value
		var inside_a: bool = da >= -0.000001 if keep_greater else da <= 0.000001
		var inside_b: bool = db >= -0.000001 if keep_greater else db <= 0.000001
		if inside_a:
			result.append(a)
		if inside_a != inside_b:
			result.append(a.lerp(b, da / (da - db)))
	return result

func _build_round_hatch(root: Node3D, node_name: String, left: bool, mat: Material) -> void:
	var outline: Array[Vector2] = _clip_pad_outline(_pad_outline(), 1, StageParams.PODIUM_PAD_FIXED_FRONT, false)
	outline = _clip_pad_outline(outline, 0, 0.0, not left)
	for i in range(outline.size()):
		outline[i] -= Vector2(root.position.x, root.position.z)
	var st: SurfaceTool = _podium_surface()
	_append_pad_prism(st, outline, -StageParams.HATCH_THICKNESS * 0.5, StageParams.HATCH_THICKNESS * 0.5)
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = node_name
	part.mesh = st.commit()
	part.material_override = mat
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(part)

func _append_pad_prism(st: SurfaceTool, points: Array[Vector2], bottom: float, top: float) -> void:
	var center: Vector2 = Vector2.ZERO
	for p: Vector2 in points:
		center += p
	center /= float(points.size())
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var ab: Vector3 = Vector3(a.x, bottom, a.y)
		var bb: Vector3 = Vector3(b.x, bottom, b.y)
		var at: Vector3 = Vector3(a.x, top, a.y)
		var bt: Vector3 = Vector3(b.x, top, b.y)
		_add_podium_quad(st, Vector3(center.x, top, center.y), at, bt, bt, Vector3.UP)
		_add_podium_quad(st, Vector3(center.x, bottom, center.y), bb, ab, ab, Vector3.DOWN)
		_add_podium_quad(st, ab, bb, bt, at, Vector3(b.y - a.y, 0.0, a.x - b.x).normalized())

func _podium_surface() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _commit_podium_mesh(node_name: String, mat: Material, st: SurfaceTool, cast_shadow: bool = true) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = node_name
	part.mesh = st.commit()
	part.material_override = mat
	if not cast_shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part

# Godot 正面为顺时针绕序：先按给定轮廓算叉积，若法线朝外就反转，保证所有面从外侧可见。
func _add_podium_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	var face_normal: Vector3 = (b - a).cross(c - a)
	if face_normal.dot(outward) > 0.0:
		var swap: Vector3 = b
		b = d
		d = swap
	Geometry._add_quad(st, a, b, c, d, outward)

func _build_exit() -> void:
	_exit_spot = SpotLight3D.new()
	_exit_spot.name = "ExitSpot"
	_exit_spot.position = StageParams.EXIT_SPOT_LOCAL
	_exit_spot.light_color = StageParams.COLOR_EXIT_SPOT
	_exit_spot.light_energy = 0.0
	_exit_spot.spot_range = StageParams.EXIT_SPOT_RANGE
	_exit_spot.spot_angle = StageParams.EXIT_SPOT_ANGLE
	_exit_spot.spot_attenuation = 1.2
	_exit_spot.spot_angle_attenuation = 0.6
	_exit_spot.shadow_enabled = false
	_exit_spot.visible = false
	add_child(_exit_spot)
	_exit_spot.look_at(to_global(StageParams.EXIT_SPOT_TARGET), Vector3.UP)

	_confetti_root = Node3D.new()
	_confetti_root.name = "ExitConfetti"
	_confetti_root.visible = false
	add_child(_confetti_root)
	var ribbon_mesh: BoxMesh = BoxMesh.new()
	ribbon_mesh.size = StageParams.EXIT_CONFETTI_SIZE
	var mat_a: StandardMaterial3D = Geometry.make_emissive(StageParams.COLOR_PUBLIC, StageParams.EXIT_CONFETTI_ENERGY)
	var mat_b: StandardMaterial3D = Geometry.make_emissive(StageParams.COLOR_LOCK, StageParams.EXIT_CONFETTI_ENERGY)
	for i in range(StageParams.EXIT_CONFETTI_COUNT):
		var part: MeshInstance3D = MeshInstance3D.new()
		part.name = "Confetti%02d" % i
		part.mesh = ribbon_mesh
		part.material_override = mat_a if i % 2 == 0 else mat_b
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_confetti_root.add_child(part)
		_confetti_parts.append(part)

func _build_speaker_light() -> void:
	_spot = SpotLight3D.new()
	_spot.name = "SpeakerLight"
	_spot.position = StageParams.SPEAKER_LIGHT_POS
	_spot.light_color = StageParams.COLOR_PUBLIC
	_spot.light_energy = 0.0
	_spot.spot_range = StageParams.SPEAKER_LIGHT_RANGE
	_spot.spot_angle = StageParams.SPEAKER_LIGHT_ANGLE
	_spot.spot_attenuation = 1.0
	_spot.spot_angle_attenuation = 0.7
	_spot.shadow_enabled = false
	_spot.visible = false
	add_child(_spot)
	_spot.look_at(to_global(StageParams.SPEAKER_LIGHT_TARGET), Vector3.UP)
