extends SceneTree

const ScriptPlayer = preload("res://scripted/script_player.gd")
const Director = preload("res://presentation/director.gd")
const Params = preload("res://config/camera_params.gd")
const Transition = preload("res://camera/transition.gd")
const Catalog = preload("res://resources/character_catalog.gd")
const Solver = preload("res://camera/shot_solver.gd")
const StateMap = preload("res://resources/state_map.gd")
const Election = preload("res://presentation/election.gd")

func _initialize() -> void:
	Catalog.prepare()
	assert(Catalog.COUNT == 12, "应接入十二名角色")
	assert(Catalog.character_id(0) == "chatgpt" and Catalog.character_id(11) == "豆包seed", "席位顺序应来自总表")
	assert(Catalog.entries["chatgpt"].has(Catalog.memorial_id(0)) and Catalog.entries["claude"].has(Catalog.memorial_id(1)), "两角色必须使用各自牌位")
	assert(Catalog.texture("chatgpt", 0) != null and Catalog.texture("gemini", 0) != null, "立绘应可直接解码")
	assert(Catalog.resolve_state("gemini", 13) == 0 and Catalog.resolve_state("chatgpt", 3) == 3, "缺失状态按角色回退0")
	var custom: Dictionary = StateMap.parse("name: 测试\ncolor: \"#ff8800\"\nmemorial: 11\nstates:\n  0: 常态.png\n  42: '特别动作.png'\n")
	assert(custom.error == "" and custom.states[42] == "特别动作.png", "新增非连续ID无需修改枚举")
	assert(custom.name == "测试" and custom.color == "#ff8800", "角色名与专属颜色应来自配置")
	assert(StateMap.parse("states:\n  0: 常态.png\n  0: 发言.png").error != "", "重复ID应被拒绝")
	assert(StateMap.parse("states:\n  0: ../常态.png").error != "", "状态文件不可越出角色目录")
	assert(StateMap.parse("states:\n  2: 发言.png").error != "", "必须配置默认ID0")
	assert(StateMap.parse("color: red\nstates:\n  0: 常态.png").error != "", "颜色必须为十六进制")
	var player := ScriptPlayer.new()
	assert(player.load_script("res://scripted/demos/first_trial.json"), player.error)
	player.paused = true
	player.advance(2.0)
	assert(player.time == 0.0, "暂停必须冻结时间")
	player.paused = false
	player.manual = true
	player.advance(100.0)
	assert(player.index_at(player.time) == 0 and player.paused, "逐句模式必须停在安全点")
	player.next()
	assert(player.index_at(player.time) == 1, "继续必须前往下一句")
	for index in range(player.beats.size()):
		player.seek(player.starts[index] + float(player.beats[index].duration) * 0.5)
		var first: Dictionary = player.state()
		var visual: Dictionary = Director.stage_state(first.beat, first.progress)
		player.seek(0.0)
		player.seek(player.starts[index] + float(player.beats[index].duration) * 0.5)
		var second: Dictionary = player.state()
		assert(visual == Director.stage_state(second.beat, second.progress), "任意跳转后演出采样应一致")
	var active := ScriptPlayer.new()
	assert(active.load_script("res://scripted/demos/first_trial_v3.json"), active.error)
	for index in range(active.beats.size()):
		active.seek(active.starts[index] + float(active.beats[index].duration) * 0.5)
		var probe: Dictionary = active.state()
		Director.stage_state(probe.beat, probe.progress)
		Director.character_states(active.beats, int(probe.index), float(probe.progress), Catalog.COUNT)
		Election.sample(active.beats, int(probe.index), float(probe.progress), Catalog.COUNT)
	for count in [8, 12, 16]:
		var radius: float = Params.ring_radius(count)
		var chord: float = 2.0 * radius * sin(PI / float(count))
		assert(chord >= Params.POD_WIDTH + Params.POD_GAP - 0.001, "席位布局不能重叠")
	var a: Dictionary = {"position": Vector3(4, 2, -0.01), "target": Vector3(8, 1.5, 0), "fov": 46.0}
	var b: Dictionary = {"position": Vector3(4, 2, 0.01), "target": Vector3(8, 1.5, 0), "fov": 52.0}
	assert((Transition.sample(a, b, 0.0).position as Vector3).is_equal_approx(a.position), "过渡起点必须一致")
	assert((Transition.sample(a, b, 1.0).position as Vector3).is_equal_approx(b.position), "过渡终点必须一致")
	var midpoint: Vector3 = Transition.sample(a, b, 0.5).position
	assert(midpoint.x > 3.99, "跨零角度不得绕整圈")
	assert(Transition.sample(a, b, 0.4) == Transition.sample(a, b, 0.4), "过渡采样不得依赖播放历史")
	var center_a: Dictionary = {"position": Vector3(0, 1.95, 0), "target": Vector3(0, 1.65, -8), "fov": 29.0}
	var center_b: Dictionary = {"position": Vector3(0, 1.95, 0), "target": Vector3(0, 1.65, 8), "fov": 29.0}
	for step in range(21):
		var frame: Dictionary = Transition.sample(center_a, center_b, float(step) / 20.0)
		assert((frame.position as Vector3).is_equal_approx(center_a.position), "中央转向不得平移相机")
		assert((frame.target as Vector3).distance_to(frame.position) > 0.9, "对侧交接的注视方向不得退化")
	var orbit_start: Dictionary = Solver.solve("orbit", Transform3D.IDENTITY, Params.ring_radius(12), 0.0)
	var orbit_quarter: Dictionary = Solver.solve("orbit", Transform3D.IDENTITY, Params.ring_radius(12), 0.25)
	var orbit_end: Dictionary = Solver.solve("orbit", Transform3D.IDENTITY, Params.ring_radius(12), 1.0)
	assert((orbit_start.position as Vector3).distance_to(orbit_quarter.position) > 1.0, "环绕必须真实移动相机")
	assert((orbit_start.position as Vector3).is_equal_approx(orbit_end.position), "完整环绕应回到起点")
	var seat_transform := Transform3D(Basis.IDENTITY, Vector3(0, 0, -Params.ring_radius(12)))
	# 开场三段：旧 OUTER 外圈转满 360°（沿用 110°/秒，3.27s）→ 硬切内圈一整圈
	# → 落到 0 号席位并缓推 2s。
	var intro_duration: float = float(active.beats[0].duration)
	assert(active.beats[0].id == "establish" and is_equal_approx(intro_duration, 17.0), "开场时长必须匹配镜头分段")
	var outer_end_time: float = 3.0 * 360.0 / 330.0
	var intro_radius: float = Params.ring_radius(12)
	var outer: Dictionary = preload("res://camera/shot_library.gd").preset("outer")
	var intro_start: Dictionary = Solver.solve("intro", seat_transform, intro_radius, 0.0)
	assert(is_equal_approx(Vector2(intro_start.position.x, intro_start.position.z).length(), Params.INTRO_OUTER_START_RADIUS), "外圈应从 15m 起镜（立绘巡览调好的那套）")
	assert(is_equal_approx(intro_start.position.y, Params.INTRO_OUTER_HEIGHT) and is_equal_approx(intro_start.fov, float(outer.fov)), "外圈高度 10m、FOV 来自旧 OUTER")
	assert((intro_start.target as Vector3).is_equal_approx(Vector3.UP * float(outer.target)), "外圈应匹配旧 OUTER 系统全景，注视桌心")
	var outer_angle: float = atan2(intro_start.position.z, intro_start.position.x)
	assert(absf(wrapf(outer_angle - atan2(seat_transform.origin.z, seat_transform.origin.x) - float(outer.angle_offset), -PI, PI)) < 0.0001, "外圈斜侧角应匹配旧 OUTER")
	# 累加短步角度，防止把起终点相同的静止镜头误判成完整一圈。
	var outer_sweep: float = 0.0
	for step in range(1, 101):
		var shot: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (outer_end_time - 0.0001) * float(step) / 100.0 / intro_duration)
		var angle: float = atan2(shot.position.z, shot.position.x)
		outer_sweep += wrapf(angle - outer_angle, -PI, PI)
		outer_angle = angle
		var outer_probe_radius: float = Vector2(shot.position.x, shot.position.z).length()
		assert(outer_probe_radius <= Params.INTRO_OUTER_START_RADIUS + 0.001 and outer_probe_radius >= Params.INTRO_OUTER_END_RADIUS - 0.001, "外圈半径应只从 15m 向 7m 缓慢拉近")
	assert(absf(absf(outer_sweep) - TAU) < 0.01, "外圈应完整转满 360° 再切内圈")
	var outer_end: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (outer_end_time - 0.0001) / intro_duration)
	assert(Vector2(outer_end.position.x, outer_end.position.z).length() < Params.INTRO_OUTER_END_RADIUS + 0.1, "外圈结束时已拉近到 7m")
	var intro_outer_end: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (outer_end_time - 0.0001) / intro_duration)
	var intro_inner_start: Dictionary = Solver.solve("intro", seat_transform, intro_radius, outer_end_time / intro_duration)
	assert((intro_inner_start.position as Vector3).distance_to(intro_outer_end.position) > 5.0, "内外圈应在边界硬切")
	assert(is_equal_approx(Vector2(intro_inner_start.position.x, intro_inner_start.position.z).length(), 2.10) and is_equal_approx(intro_inner_start.position.y, 2.40), "内圈应保留同侧上半身机位")
	var inner_angle: float = atan2(intro_inner_start.position.z, intro_inner_start.position.x)
	var inner_sweep: float = 0.0
	for step in range(1, 118):
		var shot: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (outer_end_time + 0.1 * float(step)) / intro_duration)
		var angle: float = atan2(shot.position.z, shot.position.x)
		var angle_step: float = wrapf(angle - inner_angle, -PI, PI)
		assert(angle_step <= 0.0001 and absf(angle_step) / 0.1 < deg_to_rad(40.0), "内圈应单向匀速移动，不在人物面前停顿")
		inner_sweep += angle_step
		inner_angle = angle
		assert(is_equal_approx(shot.fov, 40.0) and is_equal_approx(shot.target.y, 2.20), "内圈 FOV 与上半身注视高度应保持")
		assert(Vector2(shot.position.x, shot.position.z).dot(Vector2(shot.target.x, shot.target.z)) > 0.0, "内圈应朝外看同侧席位")
	assert(absf(absf(inner_sweep) - TAU) < 0.001, "内圈必须真实转满一整圈")
	var intro_inner_end: Dictionary = Solver.solve("intro", seat_transform, intro_radius, 15.0 / intro_duration)
	assert((intro_inner_end.target as Vector3).distance_to(seat_transform.origin + Vector3.UP * 2.20) < 0.001, "内圈转完应对准 0 号席位")
	# 接缝前后以毫秒采样，分别核对位置与速度，确保刹车接上推近时不顿住。
	for seam: float in [15.0]:
		var before: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (seam - 0.001) / intro_duration)
		var at_seam: Dictionary = Solver.solve("intro", seat_transform, intro_radius, seam / intro_duration)
		var after: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (seam + 0.001) / intro_duration)
		var velocity_before: Vector3 = (at_seam.position - before.position) / 0.001
		var velocity_after: Vector3 = (after.position - at_seam.position) / 0.001
		assert(velocity_before.distance_to(velocity_after) < 0.01, "内圈减速与收束接缝的移动速度应连续")
		assert((before.target as Vector3).distance_to(after.target) < 0.01, "内圈收束的注视点应连续")
	var hold_start: Dictionary = Solver.solve("intro", seat_transform, intro_radius, 15.0 / intro_duration)
	var hold_end: Dictionary = Solver.solve("intro", seat_transform, intro_radius, 1.0)
	assert(is_equal_approx((hold_start.position as Vector3).distance_to(hold_end.position), 0.25), "收束两秒应持续推进 0.25m")
	var hold_previous: Vector3 = hold_start.position
	for step in range(1, 21):
		var shot: Dictionary = Solver.solve("intro", seat_transform, intro_radius, (15.0 + 0.1 * float(step)) / intro_duration)
		assert((shot.position as Vector3).distance_to(hold_previous) > 0.01, "收束每一步必须继续推近，不能定格")
		hold_previous = shot.position
	var exile_index: int = -1
	var empty_index: int = -1
	var dawn_index: int = -1
	for i in range(player.beats.size()):
		match str(player.beats[i].id):
			"exile": exile_index = i
			"empty": empty_index = i
			"second_dawn": dawn_index = i
	assert(not Director.character_states(player.beats, exile_index, 0.9, 12)[0].visible, "放逐末尾人物应消失")
	assert(not Director.character_states(player.beats, empty_index, 0.5, 12)[0].visible, "放逐当天席位应留空")
	assert(Director.character_states(player.beats, dawn_index, 0.5, 12)[0].pose == Catalog.memorial_id(0), "次日应恢复为牌位")
	assert(Director.character_states(player.beats, exile_index, 0.0, 12)[0].visible, "回看放逐起点必须恢复人物")
	var election_beats: Array[Dictionary] = [{"kind": "sheriff_signup", "candidates": [0, 1, 2]}, {"kind": "sheriff_withdraw", "withdrawn": [1, 2]}, {"kind": "sheriff_elected", "elected": 0}]
	assert(Election.sample(election_beats, 0, 1.0, 12).heights[1] == 1.0, "上警者应升起")
	assert(Election.sample(election_beats, 1, 1.0, 12).heights[1] == 0.0, "退水者应落回")
	var elected: Dictionary = Election.sample(election_beats, 2, 1.0, 12)
	assert(elected.sheriff == 0 and elected.heights[0] == 0.0, "当选后保留警长灯并回落")
	print("PASS: 剧本、回放、镜头、退场、上警升降与警长状态")
	quit()
