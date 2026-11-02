extends SceneTree

# 立绘巡览：先以每席序列首张完成旧 OUTER 外圈，再硬切开场同侧内圈。
# 每席按项目主给定的固定序列逐圈换表情，首次内圈使用首张，安全离场后准备下一圈。
# 全部由绝对时间推导，可 seek、可循环，不使用 Tween。

const Arena = preload("res://stage/arena.gd")
const Portrait = preload("res://stage/portrait.gd")
const Catalog = preload("res://resources/character_catalog.gd")
const Params = preload("res://config/camera_params.gd")
const ShotLibrary = preload("res://camera/shot_library.gd")

const ORBIT_RADIUS: float = 2.10
const ORBIT_HEIGHT: float = 2.40
const TARGET_HEIGHT: float = 2.20
const ORBIT_FOV: float = 40.0
const OUTER_SWEEP_DEG: float = 360.0
# 名称下标就是状态 id；常态也参加洗牌，牌位固定放在末尾。
const STATE_NAMES: Array[String] = ["常态", "从容", "发言", "沉思", "观望", "质疑", "被质疑", "反驳", "愤怒", "失落", "无奈", "牌位"]
const NORMAL_STATE_COUNT: int = 11
const MEMORIAL_STATE: int = 11
# 每席的固定展示序列，按角色目录名索引，最后一项固定是「牌位」。
# 状态 id：0 常态 / 1 从容 / 2 发言 / 3 沉思 / 4 观望 / 5 质疑 / 6 被质疑 /
#          7 反驳 / 8 愤怒 / 9 失落 / 10 无奈 / 11 牌位
const FIXED_ORDERS: Dictionary = {
	"chatgpt": [1, 2, 6, 7, 8, 3, 5, 10, 4, 9, 0, 11],
	"豆包": [0, 4, 2, 6, 7, 3, 8, 5, 9, 10, 1, 11],
	# 角色名是「豆包Seed」，运行目录是「豆包seed」，两个键都认，改名不影响。
	"豆包seed": [0, 4, 2, 6, 7, 3, 8, 5, 9, 10, 1, 11],
	"文心一言": [10, 0, 2, 4, 6, 7, 3, 9, 5, 8, 1, 11],
	"grok": [5, 1, 2, 8, 3, 10, 4, 6, 7, 0, 9, 11],
	"qwen": [1, 4, 5, 3, 2, 0, 10, 8, 6, 7, 9, 11],
	"minimax": [2, 1, 0, 4, 6, 7, 8, 5, 9, 10, 3, 11],
	"mimo": [8, 0, 2, 1, 4, 6, 7, 5, 10, 9, 3, 11],
	"kimi": [3, 1, 4, 2, 5, 8, 10, 6, 7, 9, 0, 11],
	"glm": [4, 1, 5, 2, 8, 3, 10, 0, 9, 6, 7, 11],
	"gemini": [8, 2, 1, 5, 3, 0, 4, 10, 6, 7, 9, 11],
	"deepseek": [10, 4, 2, 0, 1, 3, 6, 7, 5, 8, 9, 11],
	"claude": [1, 3, 0, 4, 2, 5, 10, 9, 8, 6, 7, 11],
}
# 保留 90° 离场下限，再以完整立绘四角与实际侧裁剪平面求安全角；
# 命令行机位覆盖和窗口比例变化均使用实际内圈参数重算。
const EXIT_MARGIN_DEG: float = 90.0
const EXIT_PADDING_DEG: float = 2.0
# 后台只处理 CPU 图片；队列最多保留四张，主线程每帧最多预上传一张。
const DECODE_QUEUE_LIMIT: int = 4
const TEXTURES_PER_FRAME: int = 1

class GalleryPortrait:
	extends Portrait
	var first_pose: int = 0

	func set_pose(pose: int) -> void:
		# Portrait.build() 默认调用常态；巡览直接用序列首张，避免额外同步解码。
		super.set_pose(first_pose if current_pose < 0 else pose)

var arena: Node3D
var camera: Camera3D
var portraits: Array[Node3D] = []
var seat_angles: PackedFloat32Array = PackedFloat32Array()
var current_states: Array[int] = []
var state_orders: Array[PackedInt32Array] = []

var render_size: Vector2i = Vector2i.ZERO
var lap_seconds: float = 10.0
var outer_lap_seconds: float = 3.2727
var outer_height: float = 5.6
# 角色目录准备好后再按席位总数求默认绝对半径，命令行可直接覆盖。
var outer_radius: float = 0.0
# 外圈转一整圈的过程中缓慢向席位圈拉近，但不进入内圈机位，最后硬切。
var outer_end_radius: float = 0.0
var orbit_radius: float = ORBIT_RADIUS
var orbit_height: float = ORBIT_HEIGHT
var target_height: float = TARGET_HEIGHT
var orbit_fov: float = ORBIT_FOV
var portrait_half_widths: Array[float] = []
var exit_radians: Array[float] = []
var exit_times: Array[float] = []
var exit_aspect: float = 0.0
var time: float = 0.0
var capture_path: String = ""
var frames: int = 0
var built: bool = false
# 录屏时可以限帧并开垂直同步，让游戏帧率和录制帧率对齐；0 表示保持默认。
var fps_cap: int = 0
# --fps=0 时也能单独开垂直同步；--fullscreen 使用独占全屏，默认仍是窗口模式。
var vsync_enabled: bool = false
var fullscreen: bool = false
var no_msaa: bool = false
var decode_thread := Thread.new()
var decode_mutex := Mutex.new()
var decode_slots := Semaphore.new()
var decoded_images: Array[Dictionary] = []
var decode_stopping: bool = false
var decode_finished: bool = false
var decode_started: bool = false
var decode_reported: bool = false
var async_uploaded: int = 0
var sync_fallbacks: int = 0

func _initialize() -> void:
	_parse_args()
	# 录屏可以按 --size=1920x1080 提高渲染分辨率；窗口与根视口一起改，
	# MovieWriter 会按新的视口尺寸写帧。
	if render_size != Vector2i.ZERO:
		DisplayServer.window_set_size(render_size)
		root.size = render_size
	if not Catalog.prepare():
		quit(1)
		return
	if outer_radius <= 0.0:
		outer_radius = Params.ring_radius(Catalog.COUNT) + 3.2
	if outer_end_radius <= 0.0:
		outer_end_radius = Params.ring_radius(Catalog.COUNT) + 1.2
	_build_orders()
	_preload_states()

func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lap="):
			lap_seconds = maxf(float(argument.trim_prefix("--lap=")), 4.0)
		if argument.begins_with("--outer-lap="):
			outer_lap_seconds = maxf(float(argument.trim_prefix("--outer-lap=")), 0.1)
		if argument.begins_with("--outer-height="):
			outer_height = float(argument.trim_prefix("--outer-height="))
		if argument.begins_with("--outer-radius="):
			outer_radius = maxf(float(argument.trim_prefix("--outer-radius=")), 0.25)
		if argument.begins_with("--outer-end-radius="):
			outer_end_radius = maxf(float(argument.trim_prefix("--outer-end-radius=")), 0.25)
		if argument.begins_with("--radius="):
			orbit_radius = maxf(float(argument.trim_prefix("--radius=")), 0.25)
		if argument.begins_with("--height="):
			orbit_height = float(argument.trim_prefix("--height="))
		if argument.begins_with("--target="):
			target_height = float(argument.trim_prefix("--target="))
		if argument.begins_with("--fov="):
			orbit_fov = clampf(float(argument.trim_prefix("--fov=")), 5.0, 120.0)
		if argument.begins_with("--at="):
			time = maxf(float(argument.trim_prefix("--at=")), 0.0)
		# --no-ui 作为兼容参数接收；巡览始终不创建屏幕 UI。
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--fps="):
			fps_cap = maxi(int(argument.trim_prefix("--fps=")), 0)
		if argument == "--vsync":
			vsync_enabled = true
		if argument == "--fullscreen":
			fullscreen = true
		if argument == "--no-msaa":
			no_msaa = true
		if argument.begins_with("--size="):
			var parts: PackedStringArray = argument.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				render_size = Vector2i(int(parts[0]), int(parts[1]))

func _build_orders() -> void:
	# 每席按 FIXED_ORDERS 的固定序列逐圈换表情；序列只在这里生成一次，
	# seek 与切换都不会重排。未配置的角色按 0..10 + 牌位 的顺序兜底。
	state_orders.clear()
	for seat in range(Catalog.COUNT):
		var key: String = Catalog.character_id(seat)
		var order := PackedInt32Array()
		if FIXED_ORDERS.has(key):
			for state: int in FIXED_ORDERS[key]:
				order.append(state)
		else:
			for state in range(NORMAL_STATE_COUNT):
				order.append(state)
			order.append(MEMORIAL_STATE)
		assert(order.size() == NORMAL_STATE_COUNT + 1, "%s 的展示序列必须是 12 项" % key)
		assert(order[order.size() - 1] == MEMORIAL_STATE, "%s 的最后一项必须是牌位" % key)
		state_orders.append(order)
		var report := PackedStringArray()
		for state in order:
			report.append("%d %s" % [state, STATE_NAMES[state]])
		print("%d号（%s）表情顺序：%s" % [seat + 1, Catalog.display_name(seat), " → ".join(report)])

func _preload_states() -> void:
	# 启动只同步解码十二席的首张；其余图片只读 PNG 的 IHDR 尺寸。
	for seat in range(Catalog.COUNT):
		var key: String = Catalog.character_id(seat)
		var texture: Texture2D = Catalog.texture(key, state_orders[seat][0])
		var half_width: float = 0.0
		if texture != null:
			half_width = Params.PORTRAIT_HEIGHT * float(texture.get_width()) / float(texture.get_height()) * 0.5 * 1.15
		for path: String in Catalog.entries[key].values():
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() < 24:
				continue
			file.big_endian = true
			if file.get_32() != 0x89504e47 or file.get_32() != 0x0d0a1a0a:
				continue
			file.seek(16)
			var width: int = file.get_32()
			var height: int = file.get_32()
			if width > 0 and height > 0:
				half_width = maxf(half_width, Params.PORTRAIT_HEIGHT * float(width) / float(height) * 0.5)
		portrait_half_widths.append(half_width)
	print("首屏预解码：%d 张；其余立绘后台加载。" % Catalog.cache.size())

func _start_decoder() -> void:
	decode_started = true
	if exit_times.is_empty():
		var viewport_size: Vector2 = root.get_visible_rect().size
		_rebuild_exit_angles(viewport_size.x / maxf(viewport_size.y, 1.0))
	var jobs: Array[Dictionary] = []
	var queued: Dictionary = {}
	for seat in range(Catalog.COUNT):
		if is_inf(exit_times[seat]):
			continue
		var key: String = Catalog.character_id(seat)
		var order: PackedInt32Array = state_orders[seat]
		var round_index: int = maxi(int(floor((time - outer_lap_seconds - exit_times[seat]) / lap_seconds)) + 1, 0)
		for offset in range(1, order.size() + 1):
			var next_round: int = round_index + offset
			var state: int = Catalog.resolve_state(key, order[next_round % order.size()])
			var cache_key: String = key + "/" + str(state)
			if Catalog.cache.has(cache_key) or queued.has(cache_key):
				continue
			queued[cache_key] = true
			jobs.append({"key": cache_key, "path": str(Catalog.entries[key][state]), "needed_at": outer_lap_seconds + exit_times[seat] + float(next_round - 1) * lap_seconds})
	# 按下一次实际换图的时刻排序，同一轮各席的下一张先于更后面的表情。
	jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.needed_at) < float(b.needed_at))
	for slot in range(DECODE_QUEUE_LIMIT):
		decode_slots.post()
	var result: Error = decode_thread.start(_decode_states.bind(jobs))
	if result != OK:
		decode_finished = true
		push_warning("后台解码线程启动失败，按需同步加载：%s" % error_string(result))

func _decode_states(jobs: Array[Dictionary]) -> void:
	# 工作线程不读写 Catalog 缓存，不触碰 SceneTree 或 ImageTexture。
	for job in jobs:
		decode_slots.wait()
		decode_mutex.lock()
		var stopping: bool = decode_stopping
		decode_mutex.unlock()
		if stopping:
			break
		var image := Image.new()
		var result: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(str(job.path)))
		if result == OK:
			image.generate_mipmaps()
		decode_mutex.lock()
		decoded_images.append({"key": job.key, "image": image, "error": result, "path": job.path})
		decode_mutex.unlock()
	decode_mutex.lock()
	decode_finished = true
	decode_mutex.unlock()

func _upload_decoded_images() -> void:
	for upload in range(TEXTURES_PER_FRAME):
		decode_mutex.lock()
		var ready: Dictionary = {} if decoded_images.is_empty() else decoded_images.pop_front()
		decode_mutex.unlock()
		if ready.is_empty():
			break
		decode_slots.post()
		if int(ready.error) != OK:
			push_warning("后台立绘解码失败，使用时重试：%s" % str(ready.path))
		elif not Catalog.cache.has(ready.key):
			# 所有纹理及缓存操作都留在主线程，Mutex 只保护 Image 的交接队列。
			Catalog.cache[ready.key] = ImageTexture.create_from_image(ready.image as Image)
			async_uploaded += 1
	decode_mutex.lock()
	var complete: bool = decode_finished and decoded_images.is_empty()
	decode_mutex.unlock()
	if complete and not decode_reported:
		decode_reported = true
		print("后台立绘就绪：预上传 %d 张，按需同步回退 %d 张，缓存共 %d 张。" % [async_uploaded, sync_fallbacks, Catalog.cache.size()])

func _finalize() -> void:
	# 提前关闭窗口或截图退出时唤醒阻塞线程，并等待当前一张 CPU 解码完成。
	decode_mutex.lock()
	decode_stopping = true
	decode_mutex.unlock()
	decode_slots.post()
	if decode_thread.is_started():
		decode_thread.wait_to_finish()
	decoded_images.clear()

func _build() -> void:
	arena = Arena.new()
	root.add_child(arena)
	var colors: Array[Color] = []
	for index in range(Catalog.COUNT):
		colors.append(Catalog.color(index))
	arena.build(Catalog.COUNT, Params.ring_radius(Catalog.COUNT), colors)
	arena.set_glow(false)
	for index in range(Catalog.COUNT):
		var portrait := GalleryPortrait.new()
		portrait.first_pose = state_orders[index][0]
		root.add_child(portrait)
		portrait.global_transform = arena.seat_transform(index)
		portrait.build(index)
		portraits.append(portrait)
		var origin: Vector3 = arena.seat_transform(index).origin
		seat_angles.append(atan2(origin.z, origin.x))
		current_states.append(-1)
	camera = Camera3D.new()
	camera.near = 0.15
	camera.far = 60.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	root.add_child(camera)
	camera.current = true
	_solve()
	print("巡览参数：外圈 %.2f 秒转 %.1f°（%.2f°/秒）；内圈每圈 %.2f 秒（%.2f°/秒），半径 %.2f，高度 %.2f，统一注视 %.2f，垂直 FOV %.2f" % [outer_lap_seconds, OUTER_SWEEP_DEG, OUTER_SWEEP_DEG / outer_lap_seconds, lap_seconds, 360.0 / lap_seconds, orbit_radius, orbit_height, target_height, orbit_fov])
	print("外圈机位：半径 %.4f → %.4f（缓慢拉近），高度 %.2f；注视桌心、垂直 FOV %.2f" % [outer_radius, outer_end_radius, outer_height, float(ShotLibrary.preset("outer").fov)])
	print("内圈使用各角色独立顺序，每轮 12 张；牌位固定为第 12 张，安全离场后循环到首张。")
	# 诊断用：打印实际驱动与呈现状态，确认 --rendering-driver opengl3_angle 是否真的生效。
	var window_name: String = "窗口"
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			window_name = "独占全屏"
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			window_name = "无边框全屏"
	var vsync_name: String = "关闭"
	match DisplayServer.window_get_vsync_mode():
		DisplayServer.VSYNC_ENABLED:
			vsync_name = "开启"
		DisplayServer.VSYNC_ADAPTIVE:
			vsync_name = "自适应"
		DisplayServer.VSYNC_MAILBOX:
			vsync_name = "邮箱"
	print("渲染诊断：驱动 %s（%s）；适配器 %s；窗口 %s；VSync %s；max_fps %d" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), window_name, vsync_name, Engine.max_fps])

func _process(delta: float) -> bool:
	if not built:
		built = true
		# 先切换窗口模式，再设置垂直同步，避免全屏切换重置呈现状态。
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if fps_cap > 0:
			Engine.max_fps = fps_cap
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		elif vsync_enabled:
			# 不限帧 + 垂直同步：由显示器刷新率节流，不额外限帧。
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			# 0 = 不限帧（用户偏好），与主演出高刷屏策略一致。
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if no_msaa:
			root.msaa_3d = Viewport.MSAA_DISABLED
		_build()
		return false
	# 首帧先显示，再启动后台工作和逐帧纹理上传。
	if not decode_started:
		_start_decoder()
	_upload_decoded_images()
	# 截图固定采样 --at 指定的绝对时刻，预热帧和解码耗时不推进镜头。
	if capture_path.is_empty():
		time += delta
	_solve()
	frames += 1
	if not capture_path.is_empty() and frames == 10:
		_capture()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(capture_path)
	if result != OK:
		push_error("截图失败：%s" % error_string(result))
	else:
		var segment: String = "外圈" if time < outer_lap_seconds else "内圈第 %d 圈" % (int(floor((time - outer_lap_seconds) / lap_seconds)) + 1)
		print("截图已保存：%s；绝对时刻 %.3f 秒；%s；各席表情 %s；相机 %s" % [capture_path, time, segment, str(current_states), str(camera.global_position)])
	quit(0 if result == OK else 1)

func _solve() -> void:
	var start_angle: float = seat_angles[0]
	var inner_time: float = time - outer_lap_seconds
	if inner_time < 0.0:
		# 旧 OUTER 全景匀速转满 360°，边界直接切换机位，不插值。
		var outer: Dictionary = ShotLibrary.preset("outer")
		var angle: float = start_angle + float(outer.angle_offset) - deg_to_rad(OUTER_SWEEP_DEG) * time / outer_lap_seconds
		# 边转边线性拉近，同时按比例降低高度，保持俯角不变，避免越拉越像俯视。
		var pull: float = clampf(time / outer_lap_seconds, 0.0, 1.0)
		var radius: float = lerpf(outer_radius, outer_end_radius, pull)
		var outer_target: float = float(outer.target)
		var end_height: float = outer_target + (outer_height - outer_target) * outer_end_radius / maxf(outer_radius, 0.01)
		var height: float = lerpf(outer_height, end_height, pull)
		camera.global_position = Vector3(cos(angle) * radius, height, sin(angle) * radius)
		camera.look_at(Vector3(0.0, float(outer.target), 0.0), Vector3.UP)
		camera.fov = float(outer.fov)
		for seat in range(portraits.size()):
			_set_state(seat, state_orders[seat][0])
	else:
		# 内圈持续匀速转动，经过人物时也不减速或停顿。
		var camera_angle: float = start_angle - TAU * inner_time / lap_seconds
		camera.global_position = Vector3(cos(camera_angle) * orbit_radius, orbit_height, sin(camera_angle) * orbit_radius)
		var radius: float = Params.ring_radius(Catalog.COUNT)
		# 与开场内圈相同：朝外看同侧席位，所有角色统一注视高度。
		camera.look_at(Vector3(cos(camera_angle) * radius, target_height, sin(camera_angle) * radius), Vector3.UP)
		camera.fov = orbit_fov
		var viewport_size: Vector2 = root.get_visible_rect().size
		var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
		if not is_equal_approx(aspect, exit_aspect):
			_rebuild_exit_angles(aspect)
		for seat in range(portraits.size()):
			if is_inf(exit_radians[seat]):
				# 极端机位若始终不能安全离场，就保持首张，绝不在画内换图。
				_set_state(seat, state_orders[seat][0])
				continue
			# 首次正对席位之后再加安全离场角，不能把离场时间取模到首次出场之前。
			# 首次经过即为该席洗牌后的首张；仅在完整立绘离场后准备下一张。
			var round_index: int = maxi(int(floor((inner_time - exit_times[seat]) / lap_seconds)) + 1, 0)
			var order: PackedInt32Array = state_orders[seat]
			_set_state(seat, order[round_index % order.size()])
	_check_visibility()

func _set_state(seat: int, state: int) -> void:
	if state != current_states[seat]:
		var key: String = Catalog.character_id(seat)
		var resolved: int = Catalog.resolve_state(key, state)
		if not Catalog.cache.has(key + "/" + str(resolved)):
			# seek 或后台未赶上时只补当前必需的一张，保持按绝对时间采样的正确性。
			sync_fallbacks += 1
		current_states[seat] = state
		portraits[seat].call(&"set_pose", state)

func _rebuild_exit_angles(aspect: float) -> void:
	exit_aspect = aspect
	exit_radians.clear()
	exit_times.clear()
	var horizontal_tangent: float = tan(deg_to_rad(orbit_fov) * 0.5) * aspect
	var radial_distance: float = Params.ring_radius(Catalog.COUNT) - orbit_radius
	var look_direction: float = 1.0 if radial_distance >= 0.0 else -1.0
	var pitch: float = absf(atan2(target_height - orbit_height, absf(radial_distance)))
	# 俯仰使立牌顶部/底部深度不同；用统一注视点下的最大深度包住四个角。
	var vertical_depth: float = maxf(absf(Params.FOOT_HEIGHT - orbit_height), absf(Params.FOOT_HEIGHT + Params.PORTRAIT_HEIGHT - orbit_height)) * sin(pitch)
	var report: PackedStringArray = PackedStringArray()
	for seat in range(portraits.size()):
		var radius: float = Vector2(portraits[seat].position.x, portraits[seat].position.z).length()
		var half_width: float = portrait_half_widths[seat]
		var safe_angle: float = INF
		for step in range(int(EXIT_MARGIN_DEG * 4.0), 720):
			var angle: float = deg_to_rad(float(step) * 0.25)
			if angle + deg_to_rad(EXIT_PADDING_DEG) >= PI:
				break
			# 同侧朝外：右边界 x ≤ -R sinδ + w|cosδ|，
			# 深度 z ≤ R cosδ - r + w|sinδ|。四角均越过侧裁剪平面
			# 才算整张立绘离场；包含透明画布并另留 2° 安全量。
			var edge: float = -radius * sin(angle) + half_width * absf(cos(angle))
			# 半径覆盖到席位圈外时看向内侧，深度方向也必须随实际视线翻转。
			var depth: float = look_direction * (radius * cos(angle) - orbit_radius) + half_width * absf(sin(angle))
			if edge + horizontal_tangent * (maxf(depth, 0.0) + vertical_depth) < 0.0:
				safe_angle = angle + deg_to_rad(EXIT_PADDING_DEG)
				break
		exit_radians.append(safe_angle)
		var first_pass_angle: float = fposmod(seat_angles[0] - seat_angles[seat], TAU)
		exit_times.append(INF if is_inf(safe_angle) else (first_pass_angle + safe_angle) / TAU * lap_seconds)
		report.append("%d号 %.2f°" % [seat + 1, rad_to_deg(safe_angle)])
	print("安全离场角：%s" % "，".join(report))

func _check_visibility() -> void:
	# 相机贴到立牌身前时临时隐藏，避免整块贴图糊住画面。
	for index in range(portraits.size()):
		var flat: Vector2 = Vector2(
			portraits[index].global_position.x - camera.global_position.x,
			portraits[index].global_position.z - camera.global_position.z
		)
		portraits[index].visible = flat.length() > 1.15
