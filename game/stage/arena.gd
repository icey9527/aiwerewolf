extends Node3D

# 真 3D 舞台装配。不声明 class_name，由入口 preload 后 new()。
# 只负责房间、中央圆桌、隔离舱、全局昼夜光与单条投票反馈；
# 不创建人物、相机或屏幕 UI，不读取剧本/身份/规则状态。
# 所有开合与灯光均为绝对采样，不使用 Tween/await。

const StageParams = preload("res://config/stage_params.gd")
const Geometry = preload("res://stage/geometry.gd")
const IsolationPod = preload("res://stage/isolation_pod.gd")

var _built: bool = false
var _count: int = 0
var _radius: float = 0.0
var _seat_transforms: Array[Transform3D] = []
var _seat_colors: Array[Color] = []
var _pods: Array[Node3D] = []

var _environment: Environment
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _top_light: OmniLight3D
var _table_light: OmniLight3D
var _fill_lights: Array[OmniLight3D] = []

var _vote_root: Node3D
var _vote_segments: Array[MeshInstance3D] = []
var _vote_material: StandardMaterial3D
var _vote_marker: MeshInstance3D
var _vote_from: int = -1
var _vote_to: int = -1
var _vote_path_dirty: bool = true

var _speaker: int = -1
var _closed: float = 0.0
var _night: float = 0.0

func build(count: int, radius: float, seat_colors: Array = []) -> void:
	if _built:
		push_warning("Arena.build() 只允许调用一次")
		return
	if count < 1 or radius <= 0.1:
		push_error("Arena.build() 参数无效：count=%d radius=%.3f" % [count, radius])
		return
	_built = true
	_count = count
	_radius = radius
	_seat_colors.clear()
	for color: Color in seat_colors:
		_seat_colors.append(color)
	_warn_layout()
	_build_environment()
	_build_fill_lights()
	_build_room()
	_build_perch()
	_build_table()
	_build_seats()
	if not seat_colors.is_empty():
		for index in range(mini(_pods.size(), seat_colors.size())):
			_pods[index].call(&"set_accent_color", seat_colors[index])
	_build_vote_feedback()
	set_night(0.0)
	set_pods_closed(0.0)
	set_speaker(-1)
	set_vote(-1, -1, 0.0)
	set_exit(-1, 0.0, 0.0, 0.0)

func seat_transform(seat_id: int) -> Transform3D:
	if seat_id < 0 or seat_id >= _seat_transforms.size():
		push_error("seat_transform(%d) 越界，count=%d" % [seat_id, _count])
		return Transform3D.IDENTITY
	return _pods[seat_id].global_transform

# 镜头只使用不随竞选升降变化的基础席位坐标，避免讲台升起时相机跟着抬。
func base_seat_transform(seat_id: int) -> Transform3D:
	if seat_id < 0 or seat_id >= _seat_transforms.size():
		return Transform3D.IDENTITY
	return global_transform * _seat_transforms[seat_id]

func set_election(heights: Array, sheriff: int, lift: float) -> void:
	for seat in range(_pods.size()):
		var base: Transform3D = _seat_transforms[seat]
		base.origin.y += float(heights[seat]) * lift
		_pods[seat].transform = base
		_pods[seat].call(&"set_sheriff", seat == sheriff)

func set_speaker(seat_id: int) -> void:
	if not _built:
		return
	var target: int = seat_id
	if target < -1 or target >= _count:
		push_warning("set_speaker(%d) 越界，按 -1 处理" % seat_id)
		target = -1
	_speaker = target
	for i in range(_pods.size()):
		var pod: Node3D = _pods[i]
		pod.call(&"set_speaker", i == target)

func set_night(amount: float) -> void:
	if not _built:
		return
	var t: float = clampf(amount, 0.0, 1.0)
	_night = t
	if _environment != null:
		_environment.ambient_light_color = StageParams.COLOR_DAY_AMBIENT.lerp(StageParams.COLOR_NIGHT_AMBIENT, t)
		_environment.ambient_light_energy = lerpf(StageParams.DAY_AMBIENT_ENERGY, StageParams.NIGHT_AMBIENT_ENERGY, t)
		_environment.background_color = StageParams.COLOR_DAY_BG.lerp(StageParams.COLOR_NIGHT_BG, t)
		_environment.glow_intensity = lerpf(StageParams.GLOW_DAY, StageParams.GLOW_NIGHT, t)
	if _sun != null:
		_sun.light_color = StageParams.COLOR_DAY_SUN.lerp(StageParams.COLOR_NIGHT_SUN, t)
		_sun.light_energy = lerpf(StageParams.DAY_SUN_ENERGY, StageParams.NIGHT_SUN_ENERGY, t)
	if _top_light != null:
		_top_light.light_color = StageParams.COLOR_DAY_SUN.lerp(StageParams.COLOR_NIGHT_SUN, t)
		_top_light.light_energy = lerpf(StageParams.DAY_TOP_ENERGY, StageParams.NIGHT_TOP_ENERGY, t)
	if _table_light != null:
		_table_light.light_color = StageParams.COLOR_TABLE_LIGHT_DAY.lerp(StageParams.COLOR_TABLE_LIGHT_NIGHT, t)
		_table_light.light_energy = lerpf(StageParams.DAY_TABLE_LIGHT_ENERGY, StageParams.NIGHT_TABLE_LIGHT_ENERGY, t)
	for fill in _fill_lights:
		fill.light_color = StageParams.COLOR_DAY_FILL.lerp(StageParams.COLOR_NIGHT_FILL, t)
		fill.light_energy = lerpf(StageParams.DAY_FILL_ENERGY, StageParams.NIGHT_FILL_ENERGY, t)
	var room_glow: StandardMaterial3D = Geometry.material(&"glow_room")
	Geometry.set_emission(room_glow, lerpf(StageParams.ROOM_GLOW_DAY, StageParams.ROOM_GLOW_NIGHT, t))

# 录屏/巡览可以单独关掉辉光，避免白衣角色和大面积亮面产生泛光。
func set_glow(enabled: bool) -> void:
	if _environment != null:
		_environment.glow_enabled = enabled

func set_pods_closed(amount: float) -> void:
	if not _built:
		return
	var t: float = clampf(amount, 0.0, 1.0)
	_closed = t
	for pod in _pods:
		pod.call(&"set_closed", t)

func set_vote(from_seat: int, to_seat: int, amount: float) -> void:
	if not _built or _vote_root == null:
		return
	var t: float = clampf(amount, 0.0, 1.0)
	if t <= 0.001 or from_seat < 0 or to_seat < 0 or from_seat >= _count or to_seat >= _count or from_seat == to_seat:
		_vote_root.visible = false
		_vote_from = -1
		_vote_to = -1
		_vote_path_dirty = true
		return
	if from_seat != _vote_from or to_seat != _vote_to or _vote_path_dirty:
		_rebuild_vote_path(from_seat, to_seat)
		_vote_from = from_seat
		_vote_to = to_seat
		_vote_path_dirty = false
	_vote_material.emission_energy_multiplier = StageParams.VOTE_GLOW_MAX * t
	_vote_root.visible = true

# 绝对采样退场：先清空其他舱，再只给目标舱设置翻板/聚光/彩带。
# seat_id=-1 表示重置；越界按 -1 处理。fall/spotlight/confetti 均为 0..1。
func set_exit(seat_id: int, fall: float, spotlight: float, confetti: float) -> void:
	if not _built:
		return
	var target: int = seat_id
	if target < -1 or target >= _count:
		push_warning("set_exit(%d) 越界，按 -1 处理" % seat_id)
		target = -1
	for i in range(_pods.size()):
		if i != target:
			_pods[i].call(&"set_exit", false, 0.0, 0.0, 0.0)
	if target >= 0:
		_pods[target].call(&"set_exit", true, clampf(fall, 0.0, 1.0), clampf(spotlight, 0.0, 1.0), clampf(confetti, 0.0, 1.0))

func _warn_layout() -> void:
	var spacing: float = TAU * _radius / float(_count)
	var required: float = StageParams.POD_WIDTH + StageParams.POD_GAP
	if spacing + 0.001 < required:
		push_warning("席位弧距 %.3f m 小于舱宽+间隔 %.3f m；舱体可能重叠。保持固定舱宽，不缩窄人物空间。" % [spacing, required])
	var front_distance: float = _radius - StageParams.POD_FRONT_Z
	if front_distance < StageParams.TABLE_MIN_RADIUS + 0.25:
		push_warning("radius %.3f m 过小：舱前壁距桌心 %.3f m，圆桌可能与舱体相交。" % [_radius, front_distance])

func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = StageParams.COLOR_DAY_BG
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = StageParams.COLOR_DAY_AMBIENT
	_environment.ambient_light_energy = StageParams.DAY_AMBIENT_ENERGY
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.glow_enabled = true
	# 只保留中段三档辉光：完整七档在高刷下会多出数次全屏模糊，
	# 低档位几乎看不出差别，却能让 120Hz 的帧预算留出余量。
	for glow_index in range(0, 7):
		_environment.set_glow_level(glow_index, glow_index >= 2 and glow_index <= 4)
	_environment.glow_intensity = StageParams.GLOW_DAY
	_environment.glow_strength = 0.90
	_environment.glow_bloom = 0.05
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = _environment
	add_child(_world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-58.0, -38.0, 0.0)
	_sun.light_color = StageParams.COLOR_DAY_SUN
	_sun.light_energy = StageParams.DAY_SUN_ENERGY
	# 侧向阳光只作柔和的形体补光，主光改到桌心正上方，影子自然落向每个人身后。
	_sun.shadow_enabled = false
	_sun.directional_shadow_max_distance = 45.0
	add_child(_sun)

	_top_light = OmniLight3D.new()
	_top_light.name = "TopKey"
	_top_light.position = StageParams.TOP_LIGHT_POS
	_top_light.light_color = StageParams.COLOR_DAY_SUN
	_top_light.light_energy = StageParams.DAY_TOP_ENERGY
	_top_light.omni_range = StageParams.TOP_LIGHT_RANGE
	_top_light.omni_attenuation = 0.85
	_top_light.shadow_enabled = true
	add_child(_top_light)

	_table_light = OmniLight3D.new()
	_table_light.name = "TableLight"
	_table_light.position = StageParams.TABLE_LIGHT_POS
	_table_light.light_color = StageParams.COLOR_TABLE_LIGHT_DAY
	_table_light.light_energy = StageParams.DAY_TABLE_LIGHT_ENERGY
	_table_light.omni_range = StageParams.TABLE_LIGHT_RANGE
	_table_light.omni_attenuation = StageParams.TABLE_LIGHT_ATTENUATION
	# 桌面只吃漫反射，不产生高光斑/彩色反光。
	_table_light.light_specular = 0.0
	_table_light.shadow_enabled = false
	add_child(_table_light)

func _build_fill_lights() -> void:
	_fill_lights.clear()
	for i in range(StageParams.FILL_LIGHT_COUNT):
		var a: float = TAU * float(i) / float(StageParams.FILL_LIGHT_COUNT) + PI * 0.25
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "RingFill%d" % i
		light.position = Vector3(cos(a) * _radius * StageParams.FILL_LIGHT_RADIUS_SCALE, StageParams.FILL_LIGHT_HEIGHT, sin(a) * _radius * StageParams.FILL_LIGHT_RADIUS_SCALE)
		light.light_color = StageParams.COLOR_DAY_FILL
		light.light_energy = StageParams.DAY_FILL_ENERGY
		light.omni_range = StageParams.FILL_LIGHT_RANGE
		light.omni_attenuation = StageParams.FILL_LIGHT_ATTENUATION
		light.shadow_enabled = false
		add_child(light)
		_fill_lights.append(light)

func _build_room() -> void:
	var room_radius: float = _radius + StageParams.ROOM_RADIUS_PAD
	var floor_radius: float = room_radius + StageParams.ROOM_FLOOR_EXTRA
	var wall_inner: float = room_radius - StageParams.ROOM_WALL_THICKNESS * 0.5
	var segments: int = StageParams.ROOM_WALL_SEGMENTS
	var seg_width: float = 2.0 * room_radius * tan(PI / float(segments)) * 1.04
	var shell_mat: StandardMaterial3D = _make_server_material(StageParams.COLOR_SERVER_SHELL, 0.05, 0.94)
	var body_mat: StandardMaterial3D = _make_server_material(StageParams.COLOR_SERVER_BODY, 0.12, 0.88)
	var metal_mat: StandardMaterial3D = Geometry.material(&"metal_light")
	# 柜面贴图只生成一次：256×512、固定种子；所有机柜共用一个 unshaded 材质。
	var face_tex: ImageTexture = _make_server_texture()
	var face_mat: StandardMaterial3D = _make_server_face_material(face_tex)
	var seam_mat: StandardMaterial3D = _make_server_glow_material(StageParams.COLOR_SERVER_SEAM, StageParams.SERVER_SEAM_EMISSION)
	var inlay_mat: StandardMaterial3D = _make_server_glow_material(StageParams.COLOR_SERVER_FLOOR_INLAY, StageParams.SERVER_INLAY_EMISSION)

	Geometry.add_cylinder(self, "RoomFloor", floor_radius, floor_radius, 0.20, Vector3(0.0, -0.10, 0.0), Geometry.material(&"floor"), 96, false)

	# 1) 闭壳：沿用旧墙尺寸的 24 段互相搭接，360° 不会露出墙外。
	var shell_st: SurfaceTool = _begin_surface()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		_append_surface_box(shell_st, Vector3(seg_width, StageParams.ROOM_WALL_HEIGHT, StageParams.ROOM_WALL_THICKNESS),
			Vector3(cos(a) * room_radius, StageParams.ROOM_WALL_HEIGHT * 0.5, sin(a) * room_radius),
			PI * 0.5 - a)
	_commit_surface("ServerShell", shell_st, shell_mat)

	# 2) 环形服务器阵列：48 个 7.5° 单元，柜面再分成两列 0.96m 柜位。
	var cab_count: int = StageParams.SERVER_CABINET_COUNT
	var step: float = TAU / float(cab_count)
	var cab_height: float = StageParams.SERVER_CABINET_HEIGHT
	var cab_depth: float = StageParams.SERVER_CABINET_DEPTH
	var cab_base: float = StageParams.SERVER_CABINET_BASE_Y
	var cab_back: float = wall_inner - StageParams.SERVER_CABINET_WALL_GAP
	var cab_center: float = cab_back - cab_depth * 0.5
	var cab_front: float = cab_back - cab_depth
	var front_pitch: float = 2.0 * cab_front * sin(step * 0.5)
	var cab_width: float = front_pitch - StageParams.SERVER_CABINET_GAP
	var body_st: SurfaceTool = _begin_surface()
	var face_st: SurfaceTool = _begin_surface()
	var metal_st: SurfaceTool = _begin_surface()
	var seam_st: SurfaceTool = _begin_surface()
	for i in range(cab_count):
		var a: float = TAU * float(i) / float(cab_count)
		var yaw: float = PI * 0.5 - a
		var basis: Basis = Basis(Vector3.UP, yaw)
		var outward: Vector3 = Vector3(cos(a), 0.0, sin(a))
		_append_surface_box(body_st, Vector3(cab_width, cab_height, cab_depth),
			outward * cab_center + Vector3.UP * (cab_base + cab_height * 0.5), yaw)
		# 落地踢脚与柜顶压条，让柜体在暗场里仍有清晰的上下轮廓。
		_append_surface_box(body_st, Vector3(cab_width + 0.02, 0.10, cab_depth + 0.02),
			outward * cab_center + Vector3.UP * 0.05, yaw)
		_append_surface_box(body_st, Vector3(cab_width + 0.03, 0.05, cab_depth + 0.03),
			outward * cab_center + Vector3.UP * (cab_base + cab_height + 0.015), yaw)
		# 柜面细节全部交给贴图：一整块带 UV 的四边形，含两列柜位、10 排槽缝和指示灯。
		_append_textured_face(face_st,
			Transform3D(basis, outward * cab_center + Vector3.UP * (cab_base + cab_height * 0.5)),
			cab_width - 0.03, cab_height - 0.06, -cab_depth * 0.5 - 0.003)
		# 细金属边框遮住贴图四边，柜体看起来有 27mm 的正面厚度。
		var rail_radius: float = cab_front - 0.015
		_append_surface_box(metal_st, Vector3(cab_width, 0.030, 0.030),
			outward * rail_radius + Vector3.UP * (cab_base + cab_height - 0.015), yaw)
		_append_surface_box(metal_st, Vector3(cab_width, 0.030, 0.030),
			outward * rail_radius + Vector3.UP * (cab_base + 0.015), yaw)
		for side: float in [-1.0, 1.0]:
			var side_pos: Vector3 = outward * rail_radius + basis * Vector3(side * (cab_width * 0.5 - 0.015), cab_base + cab_height * 0.5, 0.0)
			_append_surface_box(metal_st, Vector3(0.030, cab_height - 0.06, 0.030), side_pos, yaw)
		# 单元之间的 70mm 缝里放一条竖向冷光，只作空间分隔，不做霓虹。
		var seam_a: float = a + step * 0.5
		var seam_outward: Vector3 = Vector3(cos(seam_a), 0.0, sin(seam_a))
		_append_surface_box(seam_st, Vector3(0.022, cab_height - 0.14, 0.012),
			seam_outward * (cab_front - 0.010) + Vector3.UP * (cab_base + cab_height * 0.5),
			PI * 0.5 - seam_a)
	_commit_surface("ServerArray", body_st, body_mat)
	_commit_surface("ServerFaces", face_st, face_mat)

	# 3) 机柜上方：退进暗墙带、检修走道、径向横梁与竖肋。
	var upper_radius: float = StageParams.SERVER_UPPER_BAND_RADIUS
	var band_bottom: float = StageParams.SERVER_UPPER_BAND_BOTTOM
	var band_top: float = StageParams.SERVER_UPPER_BAND_TOP
	var band_height: float = band_top - band_bottom
	var upper_width: float = 2.0 * upper_radius * tan(PI / float(cab_count)) * 1.04
	var upper_st: SurfaceTool = _begin_surface()
	for i in range(cab_count):
		var a: float = TAU * float(i) / float(cab_count)
		_append_surface_box(upper_st, Vector3(upper_width, band_height, StageParams.SERVER_UPPER_BAND_DEPTH),
			Vector3(cos(a), 0.0, sin(a)) * upper_radius + Vector3.UP * (band_bottom + band_height * 0.5),
			PI * 0.5 - a)
	_commit_surface("ServerUpperBand", upper_st, body_mat)

	# 4) 走道与横梁共用金属材质。圆环用独立 SurfaceTool 单独提交：
	# 原始 add_vertex 与 append_from(BoxMesh) 的顶点格式不同，混用会静默丢面。
	var walkway_st: SurfaceTool = _begin_surface()
	_append_ring_slab(walkway_st, StageParams.SERVER_WALKWAY_INNER, StageParams.SERVER_WALKWAY_OUTER,
		StageParams.SERVER_WALKWAY_BOTTOM, StageParams.SERVER_WALKWAY_TOP, 96)
	var walkway_mid: float = (StageParams.SERVER_WALKWAY_INNER + StageParams.SERVER_WALKWAY_OUTER) * 0.5
	for i in range(StageParams.SERVER_UPPER_RIB_COUNT):
		var a: float = TAU * float(i) / float(StageParams.SERVER_UPPER_RIB_COUNT)
		var yaw: float = PI * 0.5 - a
		var outward: Vector3 = Vector3(cos(a), 0.0, sin(a))
		_append_surface_box(metal_st, Vector3(0.15, 0.10, StageParams.SERVER_WALKWAY_OUTER - StageParams.SERVER_WALKWAY_INNER),
			outward * walkway_mid + Vector3.UP * (StageParams.SERVER_WALKWAY_BOTTOM - 0.05), yaw)
		_append_surface_box(metal_st, Vector3(0.14, band_height - 0.04, 0.24),
			outward * (upper_radius - 0.08) + Vector3.UP * (band_bottom + band_height * 0.5), yaw)
	# 顶部灯带上缘的窄金属压条。
	_append_ring_slab(walkway_st, StageParams.SERVER_TOP_LIGHT_INNER - 0.04, StageParams.SERVER_TOP_LIGHT_OUTER + 0.05,
		StageParams.SERVER_TOP_LIGHT_Y + 0.055, StageParams.SERVER_TOP_LIGHT_Y + 0.105, 96)
	# 圆环面是原始三角形，和 BoxMesh 的顶点格式不同；分开提交，避免 append_from 静默丢面。
	_commit_mesh("ServerWalkway", walkway_st.commit(), metal_mat)
	_commit_surface("ServerMetal", metal_st, metal_mat)

	# 5) 顶部环形灯带：朝向房间内壁的竖向细带，比水平环更容易在宽景里读出来。
	var top_light_st: SurfaceTool = _begin_surface()
	_append_cylinder_band(top_light_st,
		(StageParams.SERVER_TOP_LIGHT_INNER + StageParams.SERVER_TOP_LIGHT_OUTER) * 0.5,
		StageParams.SERVER_TOP_LIGHT_Y, StageParams.SERVER_TOP_LIGHT_Y + 0.06, 128)
	_commit_mesh("ServerTopLight", top_light_st.commit(), seam_mat)
	_commit_surface("ServerSeams", seam_st, seam_mat)

	# 6) 地面三圈同心细线与 30° 径向细线，把纵深从桌心延伸到机柜脚下。
	# 全部是同一材质的原始三角形，合并成一个 MeshInstance。
	var floor_ring_st: SurfaceTool = _begin_surface()
	for radius: float in [StageParams.SERVER_FLOOR_RING_RADIUS_A, StageParams.SERVER_FLOOR_RING_RADIUS_B, StageParams.SERVER_FLOOR_RING_RADIUS_C]:
		_append_flat_ring(floor_ring_st, radius - 0.014, radius + 0.014, 0.009, 128)
	for i in range(StageParams.SERVER_FLOOR_RADIAL_COUNT):
		var a: float = TAU * float(i) / float(StageParams.SERVER_FLOOR_RADIAL_COUNT)
		_append_flat_radial(floor_ring_st, StageParams.SERVER_FLOOR_RADIAL_INNER,
			StageParams.SERVER_FLOOR_RADIAL_OUTER, 0.009, 0.010, a)
	_commit_mesh("ServerFloorInlay", floor_ring_st.commit(), inlay_mat)

func _begin_surface() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _append_surface_box(st: SurfaceTool, size: Vector3, center: Vector3, yaw: float) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	st.append_from(box, 0, Transform3D(Basis(Vector3.UP, yaw), center))

# 柜面四边形：局部 -Z 朝向房间中心，UV 纵向 0 在上、1 在下。
func _append_textured_face(st: SurfaceTool, xform: Transform3D, width: float, height: float, z: float) -> void:
	var half_width: float = width * 0.5
	var half_height: float = height * 0.5
	var normal: Vector3 = (xform.basis * Vector3.FORWARD).normalized()
	var top_left: Vector3 = xform * Vector3(-half_width, half_height, z)
	var top_right: Vector3 = xform * Vector3(half_width, half_height, z)
	var bottom_right: Vector3 = xform * Vector3(half_width, -half_height, z)
	var bottom_left: Vector3 = xform * Vector3(-half_width, -half_height, z)
	st.set_normal(normal)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(top_left)
	st.set_normal(normal)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(top_right)
	st.set_normal(normal)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(bottom_right)
	st.set_normal(normal)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(top_left)
	st.set_normal(normal)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(bottom_right)
	st.set_normal(normal)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(bottom_left)

func _append_ring_slab(st: SurfaceTool, inner: float, outer: float, bottom: float, top: float, segments: int) -> void:
	for step in range(segments):
		var a0: float = TAU * float(step) / float(segments)
		var a1: float = TAU * float(step + 1) / float(segments)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var it0: Vector3 = d0 * inner + Vector3.UP * top
		var it1: Vector3 = d1 * inner + Vector3.UP * top
		var ot0: Vector3 = d0 * outer + Vector3.UP * top
		var ot1: Vector3 = d1 * outer + Vector3.UP * top
		var offset: Vector3 = Vector3.DOWN * (top - bottom)
		_ring_quad(st, it0, ot0, ot1, it1, Vector3.UP)
		_ring_quad(st, it0 + offset, it1 + offset, ot1 + offset, ot0 + offset, Vector3.DOWN)
		_ring_quad(st, it0 + offset, it0, it1, it1 + offset, -(d0 + d1).normalized())
		_ring_quad(st, ot0 + offset, ot1 + offset, ot1, ot0, (d0 + d1).normalized())

func _append_flat_ring(st: SurfaceTool, inner: float, outer: float, y: float, segments: int) -> void:
	for step in range(segments):
		var a0: float = TAU * float(step) / float(segments)
		var a1: float = TAU * float(step + 1) / float(segments)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		_ring_quad(st, d0 * inner + Vector3.UP * y, d0 * outer + Vector3.UP * y,
			d1 * outer + Vector3.UP * y, d1 * inner + Vector3.UP * y, Vector3.UP)

# 地面径向细线：一条贴地的窄四边形，和同心环共用同一个 SurfaceTool。
func _append_flat_radial(st: SurfaceTool, inner: float, outer: float, half_width: float, y: float, angle: float) -> void:
	var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var side: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * half_width
	_ring_quad(st,
		direction * inner + side + Vector3.UP * y,
		direction * outer + side + Vector3.UP * y,
		direction * outer - side + Vector3.UP * y,
		direction * inner - side + Vector3.UP * y,
		Vector3.UP)

# 圆柱面细带：只保留朝向房间中心的一面，用于顶部环形灯带。
func _append_cylinder_band(st: SurfaceTool, radius: float, bottom: float, top: float, segments: int) -> void:
	for step in range(segments):
		var a0: float = TAU * float(step) / float(segments)
		var a1: float = TAU * float(step + 1) / float(segments)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var p0: Vector3 = d0 * radius + Vector3.UP * bottom
		var p1: Vector3 = d0 * radius + Vector3.UP * top
		var q0: Vector3 = d1 * radius + Vector3.UP * bottom
		var q1: Vector3 = d1 * radius + Vector3.UP * top
		_ring_quad(st, p0, p1, q1, q0, -(d0 + d1).normalized())

func _commit_surface(node_name: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	return _commit_mesh(node_name, st.commit(), mat)

func _commit_mesh(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _make_server_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	# Compatibility 下高金属度会吃掉环境光；机柜保持低金属度、高粗糙度。
	mat.metallic = minf(metallic, 0.25)
	mat.roughness = roughness
	return mat

func _make_server_glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.55)
	mat.metallic = 0.0
	mat.roughness = 0.75
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _make_server_face_material(texture: ImageTexture) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	# Compatibility 下 emission_texture 会被当成常量自发光整面提亮，
	# 因此按任务允许的退路改用 unshaded：贴图本身保持近黑，只有槽线与灯点可见。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.metallic = 0.0
	mat.roughness = 1.0
	mat.emission_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

# 固定种子、一次性生成柜面 2D 贴图：两列柜位、10 排横向槽缝、少量蓝紫指示灯。
func _make_server_texture() -> ImageTexture:
	var width: int = StageParams.SERVER_TEXTURE_WIDTH
	var height: int = StageParams.SERVER_TEXTURE_HEIGHT
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = StageParams.SERVER_TEXTURE_SEED
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(StageParams.COLOR_SERVER_FACE_BASE)
	var edge: Color = Color(0.018, 0.023, 0.032, 1.0)
	image.fill_rect(Rect2i(0, 0, width, 5), edge)
	image.fill_rect(Rect2i(0, height - 5, width, 5), edge)
	image.fill_rect(Rect2i(0, 0, 5, height), edge)
	image.fill_rect(Rect2i(width - 5, 0, 5, height), edge)
	var half_width: int = width / 2
	image.fill_rect(Rect2i(half_width - 2, 0, 4, height), edge)
	var rows: int = StageParams.SERVER_SLOT_ROWS
	var top_pad: int = 46
	var bottom_pad: int = 42
	var row_height: int = (height - top_pad - bottom_pad) / rows
	for column in range(2):
		var x0: int = column * half_width + 8
		var x1: int = (column + 1) * half_width - 8
		# 栏头 / 栏脚：给每列柜位一个清楚的上下框。
		image.fill_rect(Rect2i(x0, 10, x1 - x0, 26), Color(0.055, 0.065, 0.082, 1.0))
		image.fill_rect(Rect2i(x0, 36, x1 - x0, 2), Color(0.12, 0.15, 0.19, 1.0))
		image.fill_rect(Rect2i(x0, height - 32, x1 - x0, 20), Color(0.030, 0.036, 0.048, 1.0))
		for row in range(rows):
			var y0: int = top_pad + row * row_height
			var slot_y: int = y0 + 6
			var slot_h: int = row_height - 12
			image.fill_rect(Rect2i(x0, slot_y, x1 - x0, slot_h), Color(0.017, 0.021, 0.030, 1.0))
			image.fill_rect(Rect2i(x0, slot_y, x1 - x0, 1), Color(0.140, 0.165, 0.205, 1.0))
			image.fill_rect(Rect2i(x0, slot_y + 2, x1 - x0, 1), Color(0.060, 0.074, 0.094, 1.0))
			image.fill_rect(Rect2i(x0, slot_y + slot_h - 1, x1 - x0, 1), Color(0.042, 0.050, 0.066, 1.0))
			var vent_x: int = x0 + 6
			while vent_x < x1 - 12:
				image.fill_rect(Rect2i(vent_x, slot_y + 3, 1, maxi(2, slot_h - 6)), Color(0.050, 0.060, 0.078, 1.0))
				vent_x += 7
			var led_count: int = rng.randi_range(1, 2)
			for led in range(led_count):
				var lx: int = rng.randi_range(x1 - 20, x1 - 5)
				var ly: int = rng.randi_range(slot_y + 3, slot_y + maxi(3, slot_h - 4))
				var led_color: Color = StageParams.COLOR_SERVER_LED_BLUE if rng.randf() < 0.72 else StageParams.COLOR_SERVER_LED_VIOLET
				var bright: float = rng.randf_range(0.45, 1.0)
				image.fill_rect(Rect2i(lx - 2, ly - 2, 7, 7),
					Color(led_color.r * bright * 0.20, led_color.g * bright * 0.20, led_color.b * bright * 0.20, 1.0))
				image.fill_rect(Rect2i(lx, ly, 3, 3),
					Color(led_color.r * bright, led_color.g * bright, led_color.b * bright, 1.0))
			if row % 3 == 0:
				image.fill_rect(Rect2i(x0, y0 + row_height - 2, x1 - x0, 1), Color(0.055, 0.066, 0.084, 1.0))
	# 极轻的面板噪声，避免大块纯色在近景里显得像塑料。
	var noise_count: int = int(float(width * height) / 96.0)
	for i in range(noise_count):
		var nx: int = rng.randi_range(0, width - 1)
		var ny: int = rng.randi_range(0, height - 1)
		var color: Color = image.get_pixel(nx, ny)
		var delta: float = rng.randf_range(-0.008, 0.008)
		color.r = clampf(color.r + delta, 0.0, 1.0)
		color.g = clampf(color.g + delta, 0.0, 1.0)
		color.b = clampf(color.b + delta, 0.0, 1.0)
		image.set_pixel(nx, ny, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _build_perch() -> void:
	# 低矮环形栏台：位于席位环后约 3 m（由固定舱宽推导，不新增全局参数）。
	# 分段低墙 + 圆角基座 + 顶轨构成竖向三层，填住桌区外侧的空筒地面。
	var perch_radius: float = _radius + StageParams.POD_WIDTH * 0.84
	var perch_height: float = StageParams.PODIUM_BASE_HEIGHT * 2.4
	var perch_thickness: float = StageParams.ROOM_WALL_THICKNESS * 0.60
	var perch_segments: int = int(StageParams.ROOM_WALL_SEGMENTS * 0.5)
	var perch_width: float = 2.0 * perch_radius * tan(PI / float(perch_segments)) * 1.04
	var panel_dark: StandardMaterial3D = Geometry.material(&"panel_dark")
	var metal_mid: StandardMaterial3D = Geometry.material(&"metal_mid")
	var metal_light: StandardMaterial3D = Geometry.material(&"metal_light")
	for i in range(perch_segments):
		var a: float = TAU * float(i) / float(perch_segments)
		var rot_deg: Vector3 = Vector3(0.0, rad_to_deg(PI * 0.5 - a), 0.0)
		var wall_pos: Vector3 = Vector3(cos(a) * perch_radius, perch_height * 0.5, sin(a) * perch_radius)
		Geometry.add_box(self, "PerchWall%02d" % i, Vector3(perch_width, perch_height, perch_thickness), wall_pos, panel_dark, rot_deg, true)
	Geometry.add_torus(self, "PerchCurb", perch_radius - perch_thickness * 0.62, perch_radius + perch_thickness * 0.62, Vector3(0.0, perch_height * 0.10, 0.0), metal_mid, 96, 8, false)
	Geometry.add_torus(self, "PerchRail", perch_radius - perch_thickness * 0.30, perch_radius + perch_thickness * 0.30, Vector3(0.0, perch_height, 0.0), metal_light, 96, 8, false)

func _table_radius() -> float:
	var raw: float = _radius - StageParams.POD_FRONT_Z - StageParams.TABLE_CLEARANCE
	if raw < StageParams.TABLE_MIN_RADIUS:
		push_warning("圆桌半径受限于席位环：raw=%.3f m，使用最小值 %.3f m。" % [raw, StageParams.TABLE_MIN_RADIUS])
	return clampf(raw, StageParams.TABLE_MIN_RADIUS, StageParams.TABLE_MAX_RADIUS)

func _build_table() -> void:
	# 沿用旧桌半径给桌心显示环与既有投票尺度；台面扩至原席位固定环外缘。
	var display_radius: float = _table_radius()
	var table_radius: float = _radius - StageParams.POD_FRONT_Z - 0.12
	var metal_dark: StandardMaterial3D = Geometry.material(&"metal_dark")
	var metal_mid: StandardMaterial3D = Geometry.material(&"metal_mid")
	var metal_light: StandardMaterial3D = Geometry.material(&"metal_light")
	var glow_public: StandardMaterial3D = Geometry.material(&"glow_public")
	var glass: StandardMaterial3D = Geometry.material(&"glass")
	# 中心底座承托实心拼装圆盘及既有显示装饰。
	Geometry.add_cylinder(self, "TableBase", display_radius * 0.26, display_radius * 0.26, 0.14, Vector3(0.0, 0.07, 0.0), metal_dark, 48, true)
	Geometry.add_cylinder(self, "TableColumn", display_radius * 0.20, display_radius * 0.20, 0.56, Vector3(0.0, 0.35, 0.0), metal_mid, 32, true)
	Geometry.add_torus(self, "TableUnderGlow", display_radius * 0.55 - 0.03, display_radius * 0.55 + 0.03, Vector3(0.0, 0.64, 0.0), glow_public, 64, 8, false)
	# 每个席位对应一块平齐扇形板；席间拼接面零间隙，顶面仅有深色细线。
	var inner_radius: float = minf(StageParams.TABLE_INNER_RADIUS, table_radius * 0.65)
	_build_table_modules(inner_radius, table_radius, metal_light)
	_build_center_display(metal_light)
	for i in range(_count):
		var a: float = -PI * 0.5 + TAU * float(i) / float(_count)
		var mark_pos: Vector3 = Vector3(cos(a) * (table_radius - 0.20), 0.792, sin(a) * (table_radius - 0.20))
		var rot_deg: Vector3 = Vector3(0.0, rad_to_deg(PI * 0.5 - a), 0.0)
		Geometry.add_box(self, "TableMark%02d" % i, Vector3(0.045, 0.012, 0.20), mark_pos, glow_public, rot_deg, false)
	_build_clock_face(table_radius)
	var ring_a: float = table_radius + 0.90
	Geometry.add_torus(self, "FloorRingA", ring_a - 0.035, ring_a + 0.035, Vector3(0.0, 0.012, 0.0), Geometry.material(&"glow_room"), 96, 8, false)
	var ring_b: float = minf(_radius - StageParams.POD_FRONT_Z - 0.35, table_radius + 2.00)
	if ring_b > ring_a + 0.20:
		Geometry.add_torus(self, "FloorRingB", ring_b - 0.035, ring_b + 0.035, Vector3(0.0, 0.012, 0.0), Geometry.material(&"glow_room"), 96, 8, false)

# 桌心显示盘：照参考图做——抛光黑盘 + 冷白金属薄边 + 边上的蓝色刻线 + 中心蓝光环。
func _build_center_display(metal_light: StandardMaterial3D) -> void:
	const CENTER_RADIUS: float = 1.45
	const CORE_RADIUS: float = 0.55
	var disc := StandardMaterial3D.new()
	disc.albedo_color = Color("0b1018")
	disc.metallic = 0.18
	disc.metallic_specular = 0.25
	disc.roughness = 0.58
	Geometry.add_cylinder(self, "TableDisplay", CENTER_RADIUS, CENTER_RADIUS, 0.014, Vector3(0.0, 0.785, 0.0), disc, 96, false)
	# 冷白金属薄边，微微高出盘面。
	Geometry.add_torus(self, "TableDisplayRim", CENTER_RADIUS - 0.012, CENTER_RADIUS + 0.012, Vector3(0.0, 0.7925, 0.0), metal_light, 96, 8, false)
	# 中心孔：近黑圆盘 + 细蓝光环。
	var core := StandardMaterial3D.new()
	core.albedo_color = Color("010205")
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Geometry.add_cylinder(self, "TableDisplayCore", CORE_RADIUS, CORE_RADIUS, 0.004, Vector3(0.0, 0.7915, 0.0), core, 96, false)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color("3d72ef")
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blue.emission_enabled = true
	blue.emission = Color("457eff")
	blue.emission_energy_multiplier = 0.55
	Geometry.add_torus(self, "TableDisplayCoreRing", CORE_RADIUS + 0.002, CORE_RADIUS + 0.026, Vector3(0.0, 0.7922, 0.0), blue, 96, 8, false)
	# 盘沿 12 根蓝色刻线，径向压在最外圈的金属边上。
	for step in range(12):
		var a: float = -PI * 0.5 + TAU * float(step) / 12.0
		var tick_pos := Vector3(cos(a) * (CENTER_RADIUS - 0.006), 0.7946, sin(a) * (CENTER_RADIUS - 0.006))
		var rot_deg := Vector3(0.0, rad_to_deg(PI * 0.5 - a), 0.0)
		Geometry.add_box(self, "CenterTick%02d" % step, Vector3(0.030, 0.003, 0.160), tick_pos, blue, rot_deg, false)

func _build_clock_face(table_radius: float) -> void:
	var numerals: Array[String] = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
	var font: Font = load("res://assets/fonts/SourceHanSerifCN-Bold.otf") as Font
	var face := Node3D.new()
	face.name = "ClockFace"
	add_child(face)
	var label_radius: float = table_radius - 0.58
	for i in range(_count):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(_count)
		var label := Label3D.new()
		label.name = "Hour%02d" % (i + 1)
		label.text = numerals[i % numerals.size()]
		label.font = font
		label.font_size = 56
		label.pixel_size = 0.0072
		label.modulate = Color(0.62, 0.68, 0.78, 0.92)
		label.shaded = false
		label.double_sided = true
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.outline_size = 0
		var position := Vector3(cos(angle) * label_radius, 0.792, sin(angle) * label_radius)
		# 平铺在桌面，所有数字统一朝上（世界 -Z），不再径向旋转，避免底部数字倒置。
		label.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), position)
		face.add_child(label)
		# 每小时之间 4 根小刻度，用该席位在 chara.yaml 里的专属颜色。
		var seat_color: Color = _seat_colors[i] if i < _seat_colors.size() else Color("dbe5ff")
		var tick_mat := StandardMaterial3D.new()
		tick_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tick_mat.albedo_color = seat_color.lightened(0.10)
		for k in range(1, 5):
			var tick_angle: float = angle + TAU * float(k) / (float(_count) * 5.0)
			var tick_pos := Vector3(cos(tick_angle) * (table_radius - 0.16), 0.7925, sin(tick_angle) * (table_radius - 0.16))
			var tick_rot: float = PI * 0.5 - tick_angle
			var tick := Geometry.add_box(face, "Minute%02d_%d" % [i, k], Vector3(0.012, 0.006, 0.10), tick_pos, tick_mat, Vector3(0.0, rad_to_deg(tick_rot), 0.0), false)
			tick.position = tick_pos

func _build_seats() -> void:
	_seat_transforms.clear()
	_pods.clear()
	for i in range(_count):
		var a: float = -PI * 0.5 + TAU * float(i) / float(_count)
		var origin: Vector3 = Vector3(cos(a) * _radius, 0.0, sin(a) * _radius)
		var x_axis: Vector3 = Vector3(-sin(a), 0.0, cos(a))
		var z_axis: Vector3 = Vector3(-cos(a), 0.0, -sin(a))
		var seat_tf: Transform3D = Transform3D(Basis(x_axis, Vector3.UP, z_axis), origin)
		_seat_transforms.append(seat_tf)
		var pod: Node3D = IsolationPod.new() as Node3D
		pod.name = "Pod%02d" % i
		add_child(pod)
		pod.transform = seat_tf
		pod.call(&"setup", i)
		_pods.append(pod)

func _build_table_modules(inner: float, outer: float, frame_mat: StandardMaterial3D) -> void:
	var modules: Node3D = Node3D.new()
	modules.name = "TableModules"
	add_child(modules)
	var joints: Node3D = Node3D.new()
	joints.name = "TableJoints"
	add_child(joints)
	var seal_mat: StandardMaterial3D = Geometry.material(&"table").duplicate() as StandardMaterial3D
	seal_mat.albedo_color = StageParams.COLOR_TABLE.darkened(0.82)
	seal_mat.metallic = 0.0
	seal_mat.roughness = 1.0
	seal_mat.emission_enabled = false
	var top: float = StageParams.TABLE_HEIGHT + StageParams.TABLE_TOP_THICKNESS * 0.5
	var bottom: float = StageParams.TABLE_HEIGHT - StageParams.TABLE_TOP_THICKNESS * 0.5
	var span: float = TAU / float(_count)
	for seat in range(_count):
		var center: float = -PI * 0.5 + span * float(seat)
		_add_table_module(modules, seat, inner, outer, center - span * 0.5, center + span * 0.5)
		# 接缝根节点的局部 X 沿切向、Z 沿径向，托梁与插接片共用这一坐标。
		var joint: Node3D = Node3D.new()
		joint.name = "Joint%02d" % seat
		joint.rotation.y = PI * 0.5 - (center + span * 0.5)
		joints.add_child(joint)
		# 拼缝仅为高出表面 0.5mm 的深色细线；下方板面与侧壁完全贴合。
		var line: MeshInstance3D = MeshInstance3D.new()
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(StageParams.TABLE_SEAM_LINE_WIDTH, outer - 0.01 - inner)
		line.name = "SurfaceSeam"
		line.mesh = plane
		line.material_override = seal_mat
		line.position = Vector3(0.0, top + 0.0005, (outer - 0.01 + inner) * 0.5)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		joint.add_child(line)
		# 每条接缝共用一套落地承托；径向梁保留原长度，不在圆心堆叠。
		var beam_inner: float = 1.16
		Geometry.add_box(joint, "SpliceBeam", Vector3(0.14, 0.08, outer - 0.06 - beam_inner), Vector3(0.0, bottom - 0.04, (beam_inner + outer - 0.06) * 0.5), Geometry.material(&"metal_mid"))
		var post_radius: float = outer - 0.60
		var post_height: float = bottom - 0.13
		Geometry.add_box(joint, "SupportPost", Vector3(0.16, post_height, 0.28), Vector3(0.0, 0.05 + post_height * 0.5, post_radius), Geometry.material(&"metal_dark"))
		Geometry.add_box(joint, "SupportFoot", Vector3(0.32, 0.05, 0.42), Vector3(0.0, 0.025, post_radius), frame_mat)
		# 连接片全部藏在桌底，在托梁两侧跨接，不在台面叠第二层边框。
		for connector_radius: float in [outer * 0.52, outer - 0.12]:
			Geometry.add_box(joint, "ConnectorMiddle" if connector_radius < outer * 0.75 else "ConnectorOuter", Vector3(0.13, 0.018, 0.09), Vector3(0.0, bottom - 0.009, connector_radius), frame_mat, Vector3.ZERO, false)

# 相邻模块复用同一圆周采样编号，边界顶点完全一致，零物理空隙。
func _add_table_module(parent: Node3D, seat: int, inner: float, outer: float, a0: float, a1: float) -> void:
	var steps: int = maxi(16, int(ceil(float(StageParams.TABLE_TOP_SEGMENTS) / float(_count))))
	var top: float = StageParams.TABLE_HEIGHT + StageParams.TABLE_TOP_THICKNESS * 0.5
	var bottom: float = StageParams.TABLE_HEIGHT - StageParams.TABLE_TOP_THICKNESS * 0.5
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(Geometry.material(&"table"))
	for step in range(steps):
		var angle0: float = -PI * 0.5 - PI / float(_count) + TAU * float((seat * steps + step) % (_count * steps)) / float(_count * steps)
		var angle1: float = -PI * 0.5 - PI / float(_count) + TAU * float((seat * steps + step + 1) % (_count * steps)) / float(_count * steps)
		var d0: Vector3 = Vector3(cos(angle0), 0.0, sin(angle0))
		var d1: Vector3 = Vector3(cos(angle1), 0.0, sin(angle1))
		var i0: Vector3 = d0 * inner
		var i1: Vector3 = d1 * inner
		var o0: Vector3 = d0 * outer
		var o1: Vector3 = d1 * outer
		_ring_quad(st, i0 + Vector3.UP * top, o0 + Vector3.UP * top, o1 + Vector3.UP * top, i1 + Vector3.UP * top, Vector3.UP)
		_ring_quad(st, i0 + Vector3.UP * bottom, i1 + Vector3.UP * bottom, o1 + Vector3.UP * bottom, o0 + Vector3.UP * bottom, Vector3.DOWN)
		_ring_quad(st, o0 + Vector3.UP * bottom, o1 + Vector3.UP * bottom, o1 + Vector3.UP * top, o0 + Vector3.UP * top, (d0 + d1).normalized())
	# 相邻的封闭端面共用边界，不内收、不倒角，也不制造可见深槽。
	for end: int in range(2):
		var angle: float = a0 if end == 0 else a1
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var normal: Vector3 = Vector3(sin(angle), 0.0, -cos(angle)) * (1.0 if end == 0 else -1.0)
		var bi: Vector3 = direction * inner + Vector3.UP * bottom
		var bo: Vector3 = direction * outer + Vector3.UP * bottom
		var ti: Vector3 = direction * inner + Vector3.UP * top
		var to: Vector3 = direction * outer + Vector3.UP * top
		if end == 0:
			_ring_quad(st, bi, bo, to, ti, normal)
		else:
			_ring_quad(st, bo, bi, ti, to, normal)
	var plate: MeshInstance3D = MeshInstance3D.new()
	plate.name = "Module%02d" % seat
	plate.mesh = st.commit()
	parent.add_child(plate)

func _ring_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	# 圆心扇面用退化四边形表达；只提交有效三角形，避免零面积面。
	if (b - a).cross(c - a).length_squared() > 0.00000000000001:
		for vertex: Vector3 in [a, b, c]:
			st.add_vertex(vertex)
	if (c - a).cross(d - a).length_squared() > 0.00000000000001:
		for vertex: Vector3 in [a, c, d]:
			st.add_vertex(vertex)

func _build_vote_feedback() -> void:
	_vote_root = Node3D.new()
	_vote_root.name = "VoteFeedback"
	_vote_root.visible = false
	add_child(_vote_root)
	_vote_material = Geometry.make_emissive(StageParams.COLOR_PUBLIC, 0.0)
	var tube_mesh: CylinderMesh = CylinderMesh.new()
	tube_mesh.top_radius = StageParams.VOTE_TUBE_RADIUS
	tube_mesh.bottom_radius = StageParams.VOTE_TUBE_RADIUS
	tube_mesh.height = 1.0
	tube_mesh.radial_segments = 8
	tube_mesh.rings = 1
	for i in range(StageParams.VOTE_SEGMENTS):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "VoteSegment%02d" % i
		segment.mesh = tube_mesh
		segment.material_override = _vote_material
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.visible = false
		_vote_root.add_child(segment)
		_vote_segments.append(segment)
	_vote_marker = Geometry.add_sphere(_vote_root, "VoteTargetMarker", StageParams.VOTE_MARKER_RADIUS, Vector3.ZERO, _vote_material, 16, 8, false)
	_vote_marker.visible = false
	_vote_path_dirty = true

func _rebuild_vote_path(from_seat: int, to_seat: int) -> void:
	var from_tf: Transform3D = _seat_transforms[from_seat]
	var to_tf: Transform3D = _seat_transforms[to_seat]
	var from_pos: Vector3 = from_tf.origin + Vector3.UP * StageParams.VOTE_ENDPOINT_Y
	var to_pos: Vector3 = to_tf.origin + Vector3.UP * StageParams.VOTE_ENDPOINT_Y
	var control: Vector3 = (from_pos + to_pos) * 0.5 + Vector3.UP * StageParams.VOTE_ARC_LIFT
	var segment_count: int = _vote_segments.size()
	for i in range(segment_count):
		var t0: float = float(i) / float(segment_count)
		var t1: float = float(i + 1) / float(segment_count)
		var p0: Vector3 = _quadratic_bezier(from_pos, control, to_pos, t0)
		var p1: Vector3 = _quadratic_bezier(from_pos, control, to_pos, t1)
		var segment: MeshInstance3D = _vote_segments[i]
		segment.transform = _tube_transform(p0, p1)
		segment.visible = true
	_vote_marker.position = to_pos + to_tf.basis.z.normalized() * 0.30 + Vector3.UP * 0.10
	_vote_marker.visible = true

func _quadratic_bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return a * (u * u) + b * (2.0 * u * t) + c * (t * t)

func _tube_transform(p0: Vector3, p1: Vector3) -> Transform3D:
	var delta: Vector3 = p1 - p0
	var length: float = delta.length()
	if length < 0.0001:
		return Transform3D(Basis.IDENTITY, p0)
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis * length, z_axis), (p0 + p1) * 0.5)
