extends RefCounted

const Params = preload("res://config/camera_params.gd")

static func solve(kind: String, seat_transform: Transform3D, radius: float, progress: float) -> Dictionary:
	var origin: Vector3 = seat_transform.origin
	var inward: Vector3 = seat_transform.basis.z.normalized()
	var tangent: Vector3 = seat_transform.basis.x.normalized()
	var target: Vector3 = origin + Vector3.UP * Params.INTRO_END_HEIGHT * 0.9
	var position := Vector3(0, Params.INTRO_END_HEIGHT, 0)
	var fov: float = Params.INTRO_END_FOV
	match kind:
		"intro":
			# 17 秒开场：外圈转满一整圈（保持 110°/秒，用时 3.27s）→ 硬切内圈一整圈
			# → 收束 2s 对准 0 号席位并持续缓推。全程绝对时间，可 seek。
			var elapsed: float = clampf(progress, 0.0, 1.0) * 17.0
			var seat_angle: float = atan2(origin.z, origin.x)
			# 外圈沿用立绘巡览里手调过的那套：15m → 7m、高 10m、整圈 360°。
			var outer_seconds: float = Params.INTRO_OUTER_SECONDS
			var inner_seconds: float = 15.0 - outer_seconds
			if elapsed < outer_seconds:
				var outer: Dictionary = preload("res://camera/shot_library.gd").preset("outer")
				# 方向从左往右，完整绕回 0 号席再切进内圈。
				var focus_angle: float = seat_angle - TAU * elapsed / outer_seconds
				var angle: float = focus_angle + float(outer.angle_offset)
				# 边转边线性拉近，同时按比例降低高度保持俯角，避免看起来在俯冲。
				var pull: float = clampf(elapsed / outer_seconds, 0.0, 1.0)
				var start_radius: float = Params.INTRO_OUTER_START_RADIUS
				var end_radius: float = Params.INTRO_OUTER_END_RADIUS
				var outer_radius: float = lerpf(start_radius, end_radius, pull)
				var start_height: float = Params.INTRO_OUTER_HEIGHT
				var end_height: float = float(outer.target) + (start_height - float(outer.target)) * end_radius / start_radius
				var outer_height: float = lerpf(start_height, end_height, pull)
				position = Vector3(cos(angle) * outer_radius, outer_height, sin(angle) * outer_radius)
				target = Vector3(0.0, float(outer.target), 0.0)
				fov = float(outer.fov)
			elif elapsed < 15.0:
				# 内圈：匀速一整圈，不在每个人面前停顿；最后 0.8 秒减速接收束。
				var local: float = elapsed - outer_seconds
				var brake: float = clampf((local - (inner_seconds - 0.8)) / 0.8, 0.0, 1.0)
				var fraction: float = (local - 0.4 * brake * brake) / (inner_seconds - 0.4)
				var angle: float = seat_angle - TAU * fraction
				var inner_radius: float = Params.INTRO_INNER_RADIUS + 0.05 * brake * brake
				position = Vector3(cos(angle) * inner_radius, Params.INTRO_INNER_HEIGHT, sin(angle) * inner_radius)
				target = Vector3(cos(angle) * radius, Params.INTRO_INNER_TARGET, sin(angle) * radius)
				fov = Params.INTRO_INNER_FOV
			else:
				# 承接 0.125m/s 的径向速度，2 秒内由 2.15m 推到 2.40m。
				var inner_radius: float = 2.15 + 0.125 * (elapsed - 15.0)
				position = Vector3(cos(seat_angle) * inner_radius, Params.INTRO_INNER_HEIGHT, sin(seat_angle) * inner_radius)
				target = origin + Vector3.UP * Params.INTRO_INNER_TARGET
				fov = Params.INTRO_INNER_FOV
		"orbit":
			# 真正沿桌心环轨移动，完整一圈通过连续角度采样，不走四元数最短路。
			var angle: float = -PI * 0.5 + TAU * progress
			position = Vector3(cos(angle) * Params.ORBIT_RADIUS, 2.25, sin(angle) * Params.ORBIT_RADIUS)
			target = Vector3(-cos(angle) * radius, 1.65, -sin(angle) * radius)
			fov = Params.WIDE_FOV
		"wide":
			fov = Params.WIDE_FOV
		"outside":
			# 封舱/开舱阶段从圈外看整圈，避免机位被关闭的舱壁包住。
			var out_angle: float = -PI * 0.5 + 0.28 * progress
			var out_radius: float = radius + 11.0
			position = Vector3(cos(out_angle) * out_radius, 8.8, sin(out_angle) * out_radius)
			target = Vector3(0, 0.85, 0)
			fov = 50.0
		"terminal":
			position = origin + inward * 1.30 + Vector3.UP * 2.20
			target = origin + Vector3.UP * 2.15
			fov = 82.0
		"execution":
			position = origin + inward * 4.0 + Vector3.UP * 1.9
			fov = 46.0
		"death_reveal":
			# 两个错位近景后切远景，画面始终展示牌位。
			var side: float = -1.0 if progress < 0.3 else 1.0
			var far_shot: bool = progress >= 0.6
			position = origin + inward * (4.2 if far_shot else 2.0) + tangent * (0.0 if far_shot else side * 0.3) + Vector3.UP * (1.95 if far_shot else 2.35)
			target = origin + Vector3.UP * (1.65 if far_shot else 2.45)
			var shake: float = sin(progress * 170.0) * Params.REVEAL_SHAKE * (1.0 - progress)
			target += tangent * shake
			fov = 42.0
		"hunter":
			position = origin + inward * 3.5 + tangent * 0.5 + Vector3.UP * 1.9
			target = origin + Vector3.UP * 1.9
			fov = 43.0
		"vote":
			# 接近正上方俯视，投票连线与全桌一览无余。
			# 机位拉高、视线略压向地面，让整圈席位落在字幕上方的空白区里；
			# 投票板直接使用这组机位投影出的席位坐标，因此不会和 3D 对不上。
			# 视线正对桌心偏南 2m 的垂直俯视：画面里的座位环居中偏上，
			# 屏幕上方对应世界 -Z（0 号席位在正上方），与投票板方向一致。
			position = Vector3(0.0, radius * 4.10, 2.02)
			target = Vector3(0.0, 0.40, 2.00)
			fov = 56.0
	return {"position": position, "target": target, "fov": fov}
