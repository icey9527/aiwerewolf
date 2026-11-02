extends Node3D


const Paths = preload("res://config/game_paths.gd")
const Arena = preload("res://stage/arena.gd")
const Portrait = preload("res://stage/portrait.gd")
const Rig = preload("res://camera/camera_rig.gd")
const Player = preload("res://scripted/script_player.gd")
const Director = preload("res://presentation/director.gd")
const Hud = preload("res://ui/hud.gd")
const Params = preload("res://config/camera_params.gd")
const Catalog = preload("res://resources/character_catalog.gd")
const Timing = preload("res://config/timing_params.gd")
const SkillEffect = preload("res://stage/skill_effect.gd")
const Election = preload("res://presentation/election.gd")
const ElectionEffect = preload("res://stage/election_effect.gd")
const VoteBoard = preload("res://ui/vote_board.gd")
var vote_board: CanvasLayer
var election_effect: Node3D
var skill_effect: Node3D
var arena: Node3D
var camera: Camera3D
var hud: CanvasLayer
var player: RefCounted
var portraits: Array[Node3D] = []
var speed_index: int = 0
var capture_path: String = ""
var capture_frames: int = 0
var fps_mode: int = 0
var refresh_rate: float = 60.0
var camera_mode: String = Params.CAMERA_MODE
# 录屏用：隐藏 HUD 与投票板，只留 3D 画面；H 键随时切换。
var hide_ui: bool = false

func _ready() -> void:
	var script_path: String = Paths.DEFAULT_SCRIPT_PATH
	var seek_to: float = -1.0
	var start_paused: bool = false
	var forced_fps: int = 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--script="):
			var wanted: String = argument.trim_prefix("--script=")
			if not wanted.ends_with(".json"):
				wanted += ".json"
			script_path = wanted if wanted.begins_with("res://") else Paths.SCRIPT_DIR + wanted
		if argument.begins_with("--at="):
			seek_to = float(argument.trim_prefix("--at="))
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
			start_paused = true
		if argument.begins_with("--fps="):
			forced_fps = int(argument.trim_prefix("--fps="))
		if argument.begins_with("--camera="):
			camera_mode = argument.trim_prefix("--camera=")
		if argument == "--hide-ui":
			hide_ui = true
	refresh_rate = DisplayServer.screen_get_refresh_rate()
	if refresh_rate <= 0.0:
		refresh_rate = 60.0
	# 120Hz 以上的屏幕默认不限帧率：锁在刷新率附近会被软件限速与扫描错相拖住，
	# 渲染得比刷新率快，每次扫描才能拿到最新帧。60Hz 屏仍按跟随屏幕处理。
	fps_mode = 2 if forced_fps > 0 else (3 if refresh_rate >= 100.0 else 0)
	if forced_fps > 0:
		refresh_rate = float(forced_fps)
	_apply_fps_mode()
	if not Catalog.prepare():
		get_tree().quit(1)
		return
	player = Player.new()
	if not player.load_script(script_path):
		push_error(player.error)
		get_tree().quit(1)
		return
	# 开场前把全剧会用到的表情和牌位一次性解码，播放中不再有换图卡顿。
	Catalog.preload_script_states(player.beats)
	# 开场环绕会展示全员，补齐剧本未点名的状态 0，建场前完成解码。
	for seat in range(Catalog.COUNT):
		Catalog.texture(Catalog.character_id(seat), 0)
	arena = Arena.new()
	add_child(arena)
	var radius: float = Params.ring_radius(Catalog.COUNT)
	var seat_colors: Array[Color] = []
	for seat in range(Catalog.COUNT):
		seat_colors.append(Catalog.color(seat))
	arena.build(Catalog.COUNT, radius, seat_colors)
	for seat in range(Catalog.COUNT):
		var portrait: Node3D = Portrait.new()
		add_child(portrait)
		portrait.global_transform = arena.seat_transform(seat)
		portrait.build(seat)
		portraits.append(portrait)
	election_effect = ElectionEffect.new()
	add_child(election_effect)
	election_effect.build(Catalog.COUNT)
	skill_effect = SkillEffect.new()
	add_child(skill_effect)
	camera = Rig.new()
	add_child(camera)
	camera.configure(arena, radius)
	camera.configure_beats(player.beats)
	camera.set_mode(camera_mode)
	vote_board = VoteBoard.new()
	add_child(vote_board)
	hud = Hud.new()
	add_child(hud)
	hud.action_requested.connect(_on_action)
	hud.seek_requested.connect(_on_seek)
	hud.visible = not hide_ui
	if seek_to >= 0.0:
		player.seek(seek_to)
	if start_paused:
		player.paused = true
	_sample()

func _apply_fps_mode() -> void:
	match fps_mode:
		0:
			# 跟随屏幕：60Hz 屏锁刷新率并开垂直同步。
			# ≥100Hz 时改为渲染到刷新率的 2 倍并关垂直同步：锁在刷新率附近时，
			# 软件限速和显示器扫描会缓慢错相，偶尔复用上一帧，转圈就会顿一下；
			# 2 倍采样保证每次扫描都拿到 3ms 内的新帧，同时比“不限”省一半显卡负载。
			var high_refresh: bool = refresh_rate >= 100.0
			Engine.max_fps = clampi(int(round(refresh_rate * (2.0 if high_refresh else 1.0))), 30, 480)
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_DISABLED if high_refresh else DisplayServer.VSYNC_ENABLED
			)
		1:
			Engine.max_fps = 60
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		2:
			Engine.max_fps = 120
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_:
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _pacing_label() -> String:
	match fps_mode:
		0:
			return "跟随屏幕 ×2" if refresh_rate >= 100.0 else "跟随屏幕"
		1:
			return "60档"
		2:
			return "120档"
		_:
			return "不限"

func _process(delta: float) -> void:
	if player == null or player.beats.is_empty():
		return
	player.advance(delta)
	_sample()
	if not capture_path.is_empty():
		capture_frames += 1
		if capture_frames == 12:
			_capture()

func _sample() -> void:
	var state: Dictionary = player.state()
	var beat: Dictionary = state.beat
	var visual: Dictionary = Director.stage_state(beat, float(state.progress))
	var election: Dictionary = Election.sample(player.beats, int(state.index), float(state.progress), Catalog.COUNT)
	arena.set_election(election.heights, int(election.sheriff), Params.ELECTION_LIFT)
	var seat_transforms: Array[Transform3D] = []
	for seat in range(Catalog.COUNT):
		seat_transforms.append(arena.seat_transform(seat))
	election_effect.sample(seat_transforms, election.heights, str(beat.kind).begins_with("sheriff_"), float(state.progress), str(beat.kind) != "sheriff_signup")
	arena.set_night(float(visual.night))
	arena.set_pods_closed(float(visual.closed))
	arena.set_speaker(int(beat.speaker))
	arena.set_vote(-1, -1, 0.0)
	var voting: bool = str(beat.kind) == "vote"
	if arena.has_method("set_exit"):
		arena.set_exit(int(visual.exit_seat), float(visual.fall), float(visual.spotlight), float(visual.confetti))
	camera.set_lifts(election.heights)
	camera.sample(beat, float(state.progress), player.time)
	# 投票板按当前俯视机位投影真实的席位坐标，板上的头像与桌边座位一一对齐。
	var vote_points: PackedVector2Array = PackedVector2Array()
	if voting:
		for seat in range(Catalog.COUNT):
			vote_points.append(camera.unproject_position(arena.seat_transform(seat).origin + Vector3.UP * 1.30))
	vote_board.show_vote(int(beat.get("vote_from", 0)), int(beat.get("vote_to", 1)), float(visual.vote), beat.get("votes", []), vote_points)
	if hide_ui:
		vote_board.visible = false
	var characters: Array[Dictionary] = Director.character_states(player.beats, int(state.index), float(state.progress), Catalog.COUNT)
	for seat in range(portraits.size()):
		var character: Dictionary = characters[seat]
		# 镜头穿行时贴近立牌就临时隐藏，避免整块板子糊在画面上。
		var flat := Vector2(portraits[seat].global_position.x - camera.global_position.x, portraits[seat].global_position.z - camera.global_position.z)
		var too_close: bool = flat.length() < 1.1 and absf(camera.global_position.y - 1.6) < 2.2
		portraits[seat].visible = bool(character.visible) and not voting and not too_close
		portraits[seat].global_transform = arena.seat_transform(seat)
		portraits[seat].position.y -= float(character.drop)
		portraits[seat].set_pose(character.pose)
		var is_execution: bool = str(beat.kind) == "execution"
		var brightness: float = 1.0 if not is_execution or seat == int(visual.exit_seat) else 0.42
		portraits[seat].set_lighting(brightness, is_execution and seat == int(visual.exit_seat))
	var hunter_active: bool = str(beat.kind) == "hunter"
	var shooter_seat: int = clampi(int(beat.get("camera_seat", beat.get("speaker", 3))), 0, Catalog.COUNT - 1)
	var target_seat: int = clampi(int(beat.get("skill_target", 1)), 0, Catalog.COUNT - 1)
	var shooter: Transform3D = arena.seat_transform(shooter_seat)
	var target: Transform3D = arena.seat_transform(target_seat)
	var hand: Vector3 = shooter.origin + shooter.basis.z * 0.55 + shooter.basis.x * 0.38 + Vector3.UP * 2.15
	skill_effect.sample(hunter_active, float(state.progress), hand, target.origin + Vector3.UP * 1.85)
	hud.show_state(state, player.time, player.total, player.paused, player.manual, player.speed, _pacing_label(), camera_mode)

func _on_seek(time: float) -> void:
	player.seek(time)

func _on_action(action: String) -> void:
	match action:
		"pause": player.paused = not player.paused
		"next": player.next()
		"previous": player.previous()
		"mode": player.manual = not player.manual
		"speed":
			speed_index = (speed_index + 1) % Timing.SPEEDS.size()
			player.speed = Timing.SPEEDS[speed_index]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE: _on_action("pause")
		KEY_ENTER, KEY_RIGHT: hud.continue_dialogue()
		KEY_LEFT: _on_action("previous")
		KEY_F:
			var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_F5:
			# 跟随屏幕 → 60 → 120 → 不限，循环切换。
			fps_mode = (fps_mode + 1) % 4
			_apply_fps_mode()
		KEY_H:
			# 录屏用：隐藏/恢复全部 2D UI，3D 演出不受影响。
			hide_ui = not hide_ui
			hud.visible = not hide_ui
			vote_board.visible = not hide_ui

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var result: Error = image.save_png(capture_path)
	if result != OK:
		push_error("截图失败：%s" % error_string(result))
	get_tree().quit(0 if result == OK else 1)
