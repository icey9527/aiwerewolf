extends Camera3D

const Solver = preload("res://camera/shot_solver.gd")
const Library = preload("res://camera/shot_library.gd")
const Params = preload("res://config/camera_params.gd")
const Dr2 = preload("res://camera/dr2_camera.gd")
const Catalog = preload("res://resources/character_catalog.gd")
var arena: Node3D
var radius: float
var beats: Array[Dictionary] = []
var seat_lifts: Array[float] = []
var _orbit_cache: Dictionary = {}
var _dr2_rejected: Dictionary = {}
# "dr2"：剧本写了 dr2_shot 的发言/侧拍镜头走 DR2 原始机位；"legacy"：全部走旧的 shot_solver。
var mode: String = "dr2"

func configure(stage: Node3D, ring: float) -> void:
	arena = stage
	radius = ring
	near = 0.15
	far = 60.0
	current = true

func configure_beats(script_beats: Array[Dictionary]) -> void:
	beats = script_beats

func set_mode(value: String) -> void:
	mode = value

func set_lifts(lifts: Array[float]) -> void:
	seat_lifts = lifts

func _index_of(beat: Dictionary) -> int:
	for i in range(beats.size()):
		if beats[i].id == beat.id:
			return i
	return -1

func _desired(beat: Dictionary, library_name: String, time: float) -> Dictionary:
	var preset: Dictionary = Library.preset(library_name)
	var mode: String = str(preset.mode)
	var speaker: int = int(beat.get("speaker", -1))
	# 系统播报也可用 camera_seat 指定要看向的席位（例如当选警长）。
	var focus: int = int(beat.get("camera_seat", speaker))
	var seat_origin := Vector3.ZERO
	var seat_angle: float = 0.0
	if focus >= 0:
		var transform_at_seat: Transform3D = arena.base_seat_transform(focus)
		seat_origin = transform_at_seat.origin
		seat_angle = atan2(seat_origin.z, seat_origin.x)
	var drift: float = sin(time * float(preset.get("drift_speed", 0.35))) * float(preset.drift)
	var lift: float = 0.0
	if focus >= 0 and focus < seat_lifts.size():
		# 竞选升降时镜头跟着人走，避免只拍到讲台或把头顶切掉。
		lift = float(seat_lifts[focus]) * Params.ELECTION_LIFT
	var angle: float = seat_angle + drift + float(preset.get("yaw", 0.0))
	var camera_radius: float = float(preset.radius)
	if mode == "outer":
		# 席位圈外侧的斜侧机位：不站到对面，避免最近的立牌挡住画面。
		angle += float(preset.get("angle_offset", PI))
		camera_radius = radius + float(preset.get("ring_offset", 3.0))
	elif mode == "overhead":
		angle = time * 0.05
	# 剧本可用 camera_target 覆盖看向高度（例如空席要看桌面而不是人胸口）。
	var target_height: float = float(beat.get("camera_target", preset.target))
	# 俯视机位始终看桌心，只有发言/侧拍才跟着席位走。
	var target: Vector3 = Vector3(0, target_height + lift, 0)
	if focus >= 0 and mode != "overhead":
		target = seat_origin + Vector3.UP * (target_height + lift)
	return {
		"angle": angle,
		"radius": camera_radius,
		"height": float(preset.height) + lift * 0.5,
		"fov": float(preset.fov),
		"target": target,
		"mode": mode,
	}

func sample(beat: Dictionary, progress: float, time: float) -> void:
	var index: int = _index_of(beat)
	var shot_name: String = str(beat.get("shot", "wide"))
	# 环绕镜头：在房间内取 3–4 个由 beat id 决定的外圈点，缓慢插值绕桌，
	# 不再永远从同一个固定机位转。结果是确定性的，seek 可复现。
	if shot_name == "orbit" or (shot_name == "wide" and bool(beat.get("camera_orbit", false))):
		_sample_orbit(beat, progress)
		return
	# 开场由若干原版镜头剪接而成（外圈高位全景 → 切进内圈近景），
	# 不再自己写一条连续旋转路径；剪接表写在剧本的 intro_cuts 里。
	if shot_name == "intro" and mode == "dr2" and beat.has("intro_cuts"):
		if _sample_intro(beat, progress, time):
			return
	# DR2 原始机位：剧本显式写了 dr2_shot 的发言/侧拍/全景/环绕都接管；
	# 处决、投票、终端、牌位揭示等特殊演出仍走旧机位。
	if mode == "dr2" and shot_name in ["speaker", "side", "wide", "orbit"] and not _dr2_rejected.has(str(beat.get("id", ""))):
		var dr2_name: String = str(beat.get("dr2_shot", ""))
		if not dr2_name.is_empty():
			var elapsed: float = progress * float(beat.get("duration", 6.0))
			var anchor_mode: String = str(beat.get("dr2_anchor", "speaker"))
			var position_scale: float = float(beat.get("dr2_scale", Dr2.POSITION_SCALE))
			var anchor_height: float = Dr2.ANCHOR_HEIGHT
			var focus_height: float = Dr2.FOCUS_HEIGHT
			if anchor_mode == "center":
				# 房间中心锚点：适合 LOOKOUT / *_OVER 这类绕着整桌转的镜头。
				position_scale = float(beat.get("dr2_scale", 0.10))
				anchor_height = 1.2
				focus_height = 1.2
			if _apply_dr2(
				beat, dr2_name, elapsed, anchor_mode, position_scale,
				anchor_height, focus_height, Dr2.PITCH_SCALE,
				float(beat.get("dr2_fov", 0.0)), time, progress
			):
				return
			# 这一镜会钻地或飞出房间：整段放弃，避免在地下和正常机位之间来回跳。
			_dr2_rejected[str(beat.get("id", ""))] = true
	if shot_name in ["speaker", "side", "wide", "orbit"]:
		var preset_name: String = str(beat.get("camera_preset", "medium"))
		var current: Dictionary = _desired(beat, preset_name, time)
		if index > 0:
			var previous_beat: Dictionary = beats[index - 1]
			var previous: Dictionary = _desired(previous_beat, str(previous_beat.get("camera_preset", "medium")), time)
			var previous_focus: int = int(previous_beat.get("camera_seat", previous_beat.get("speaker", -1)))
			var current_focus: int = int(beat.get("camera_seat", beat.get("speaker", -1)))
			if str(previous.mode) == str(current.mode) and previous_focus == current_focus and str(beat.get("camera_transition", "")) != "cut":
				# 同一位角色连续发言才平滑过渡；换角色直接切到新角色，不横穿桌面。
				var elapsed: float = progress * float(beat.duration)
				var blend: float = smoothstep(0.0, 1.0, clampf(elapsed / 0.6, 0.0, 1.0))
				current.angle = lerp_angle(float(previous.angle), float(current.angle), blend)
				current.radius = lerpf(float(previous.radius), float(current.radius), blend)
				current.height = lerpf(float(previous.height), float(current.height), blend)
				current.fov = lerpf(float(previous.fov), float(current.fov), blend)
				current.target = (previous.target as Vector3).lerp(current.target, blend)
		var orbit_angle: float = float(current.angle)
		var orbit_radius: float = float(current.radius)
		global_position = Vector3(cos(orbit_angle) * orbit_radius, float(current.height), sin(orbit_angle) * orbit_radius)
		look_at(current.target, Vector3.UP)
		fov = float(current.fov)
		_apply_shake(beat, time, progress)
		return
	var shot: Dictionary = Solver.solve(shot_name, arena.base_seat_transform(maxi(0, int(beat.get("camera_seat", beat.get("speaker", 0))))), radius, progress)
	global_position = shot.position
	look_at(shot.target, Vector3.UP)
	fov = float(shot.fov)
	_apply_shake(beat, time, progress)


# 采样一镜 DR2 数据并直接应用到本相机。返回 false 表示这一镜出界，调用方可回退。
func _apply_dr2(
	beat: Dictionary, shot_name: String, elapsed: float, anchor_mode: String,
	position_scale: float, anchor_height: float, focus_height: float,
	pitch_scale: float, fov_lock: float, time: float, progress: float
) -> bool:
	var focus_seat: int = clampi(int(beat.get("camera_seat", beat.get("speaker", 0))), 0, Catalog.COUNT - 1)
	var anchor_transform: Transform3D
	if anchor_mode == "center":
		anchor_transform = Transform3D.IDENTITY
	else:
		anchor_transform = arena.seat_transform(focus_seat)
		# 每个角色按自己立绘的脸部位置取锚点；坐姿、半身像也不会偏低。
		focus_height = Catalog.focus_height(focus_seat)
		anchor_height = focus_height + 0.05
	var sampled: Dictionary = Dr2.sample(
		shot_name, anchor_transform, elapsed, 0.0,
		position_scale, anchor_height, focus_height, pitch_scale, fov_lock
	)
	if sampled.is_empty():
		return false
	var tf: Transform3D = sampled.transform as Transform3D
	var eye: Vector3 = tf.origin
	# 镜头穿过地面或飞出房间时放弃这一镜，避免穿模后拉到屏幕外。
	if eye.y <= 0.35 or Vector2(eye.x, eye.z).length() >= 15.2:
		return false
	# 原版镜头播完后不立刻定死：绕注视点做极慢的漂移，让长台词段保持“活”的。
	var extra: float = elapsed - float(sampled.get("duration", 0.0))
	if extra > 0.0:
		var focus: Vector3 = sampled.get("focus", anchor_transform.origin + Vector3.UP * focus_height)
		var yaw: float = minf(extra, 4.0) * 0.010
		var turn := Basis(Vector3.UP, yaw)
		tf = Transform3D(turn * tf.basis, focus + turn * (tf.origin - focus))
	global_transform = tf
	fov = fov_lock if fov_lock > 0.0 else float(sampled.fov)
	_apply_shake(beat, time, progress)
	return true

# 开场剪接：按 intro_cuts 的 until 时间分段，每段从自己的 0 秒开始采样原版镜头。
func _sample_intro(beat: Dictionary, progress: float, time: float) -> bool:
	var cuts: Array = beat.get("intro_cuts", [])
	if cuts.is_empty():
		return false
	var duration: float = maxf(float(beat.get("duration", 12.0)), 0.01)
	var elapsed: float = clampf(progress, 0.0, 1.0) * duration
	var start: float = 0.0
	for i in range(cuts.size()):
		var cut: Dictionary = cuts[i]
		var until: float = float(cut.get("until", duration))
		if elapsed < until or i == cuts.size() - 1:
			var local: float = clampf(elapsed - start, 0.0, maxf(until - start, 0.01))
			return _apply_dr2(
				beat, str(cut.get("shot", "")), local, str(cut.get("anchor", "center")),
				float(cut.get("scale", Dr2.POSITION_SCALE)),
				float(cut.get("anchor_height", Dr2.ANCHOR_HEIGHT)),
				float(cut.get("focus_height", Dr2.FOCUS_HEIGHT)),
				0.0 if bool(cut.get("zero_pitch", false)) else Dr2.PITCH_SCALE,
				float(cut.get("fov", 0.0)), time, progress
			)
		start = until
	return false

func _orbit_points(beat: Dictionary) -> Array:
	var key: String = str(beat.get("id", "orbit"))
	if _orbit_cache.has(key):
		return _orbit_cache[key]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = absi(hash(key))
	var orbit_seat: int = clampi(int(beat.get("orbit_seat", -1)), -1, Catalog.COUNT - 1)
	var base: float = rng.randf_range(0.0, TAU)
	var sweep: float = deg_to_rad(rng.randf_range(150.0, 250.0))
	if orbit_seat >= 0:
		# 竞选镜头对着升起的那个人：立牌只朝桌心，所以机位必须放在圈内侧、
		# 并且靠近该席位的法线方向，才能看到正脸而不是黑色背面；
		# 半径留在 3.6–4.8m、机位降到 2.6–3.4m，避免从正上方俯拍。
		var seat_origin: Vector3 = arena.seat_transform(orbit_seat).origin
		var seat_angle: float = atan2(seat_origin.z, seat_origin.x)
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		base = seat_angle + side * deg_to_rad(rng.randf_range(5.0, 14.0))
		sweep = side * deg_to_rad(rng.randf_range(8.0, 16.0))
	else:
		# 整圈环绕落在两个席位之间，尽量少把邻座立绘的黑色背面塞进前景。
		var seat_angle0: float = atan2(arena.seat_transform(0).origin.z, arena.seat_transform(0).origin.x)
		base = seat_angle0 + deg_to_rad(15.0 + 30.0 * float(rng.randi_range(0, Catalog.COUNT - 1)))
		sweep = deg_to_rad(rng.randf_range(150.0, 250.0))
	var points: Array[Vector3] = []
	for i in range(4):
		var angle: float = base + sweep * float(i) / 3.0
		var point_radius: float
		var height: float
		if orbit_seat >= 0:
			point_radius = rng.randf_range(3.6, 4.8)
			height = rng.randf_range(2.6, 3.4)
		else:
			point_radius = rng.randf_range(8.6, 9.8)
			height = rng.randf_range(4.4, 5.2)
		points.append(Vector3(cos(angle) * point_radius, height, sin(angle) * point_radius))
	_orbit_cache[key] = points
	return points

func _sample_orbit(beat: Dictionary, progress: float) -> void:
	var points: Array = _orbit_points(beat)
	var t: float = clampf(progress, 0.0, 1.0) * float(points.size() - 1)
	var index: int = clampi(int(t), 0, points.size() - 2)
	var blend: float = smoothstep(0.0, 1.0, t - float(index))
	var position: Vector3 = (points[index] as Vector3).lerp(points[index + 1], blend)
	global_position = position
	# 竞选镜头可以围绕正在升起的那个人，锚点随升降一起动，而不是永远看桌心。
	var target := Vector3(0.0, 1.25, 0.0)
	var orbit_seat: int = int(beat.get("orbit_seat", -1))
	if orbit_seat >= 0 and orbit_seat < Catalog.COUNT:
		var seat_transform: Transform3D = arena.seat_transform(orbit_seat)
		target = seat_transform.origin + Vector3.UP * Catalog.focus_height(orbit_seat)
	look_at(target, Vector3.UP)
	fov = 44.0 if orbit_seat >= 0 else 50.0


# 判定类的短促震屏：剧本写 camera_shake（米），叠加确定性的正弦抖动，seek 可复现。
func _apply_shake(beat: Dictionary, time: float, progress: float) -> void:
	# 旋转抖动（度），在段首约 0.6 秒内指数衰减；只转镜头，不推位置。
	var amount: float = float(beat.get("camera_shake", 0.0))
	if amount <= 0.0:
		return
	var elapsed: float = progress * float(beat.get("duration", 1.0))
	var decay: float = clampf(1.0 - elapsed / 0.6, 0.0, 1.0)
	if decay <= 0.0:
		return
	var angle: float = amount * decay
	rotate_object_local(Vector3.RIGHT, deg_to_rad(sin(time * 47.0) * angle))
	rotate_object_local(Vector3.UP, deg_to_rad(sin(time * 53.0 + 1.1) * angle * 0.6))
	rotate_object_local(Vector3.BACK, deg_to_rad(sin(time * 41.0 + 2.2) * angle * 0.4))
