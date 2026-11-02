extends RefCounted


const Paths = preload("res://config/game_paths.gd")
const StateMap = preload("res://resources/state_map.gd")
const StageParams = preload("res://config/stage_params.gd")
const ROOT: String = Paths.CHARACTER_ROOT
static var COUNT: int = 0
static var entries: Dictionary = {}
static var cache: Dictionary = {}
static var definitions: Dictionary = {}
static var seats: Array[String] = []

static func character_id(seat: int) -> String:
	return seats[posmod(seat, seats.size())]

static func prepare() -> bool:
	if not entries.is_empty():
		return true
	var dir: DirAccess = DirAccess.open(ROOT)
	if dir == null:
		push_error("角色目录不存在：" + ROOT)
		return false
	var records: Array[Dictionary] = []
	for folder: String in dir.get_directories():
		var path: String = ROOT.path_join(folder).path_join(Paths.CHARACTER_CONFIG)
		if not FileAccess.file_exists(path):
			continue
		var parsed: Dictionary = StateMap.parse(FileAccess.get_file_as_string(path))
		if not str(parsed.error).is_empty():
			push_error(path + "：" + str(parsed.error))
			return false
		var poses: Dictionary = {}
		for id: int in parsed.states:
			var image_path: String = path.get_base_dir().path_join(parsed.states[id])
			if not FileAccess.file_exists(image_path):
				push_error("状态图片不存在：" + image_path)
				return false
			poses[id] = image_path
		if not poses.has(0):
			push_error("角色缺少默认状态 0：" + folder)
			return false
		var memorial: int = int(parsed.memorial)
		if memorial < 0 or not poses.has(memorial):
			memorial = 0
		var display_name: String = str(parsed.name)
		if display_name.is_empty():
			display_name = folder
		records.append({
			"key": folder,
			"seat": int(parsed.seat),
			"name": display_name,
			"color": str(parsed.color),
			"memorial_id": memorial,
			"focus": float(parsed.focus),
			"poses": poses,
		})
	if records.is_empty():
		push_error("没有找到任何角色配置：" + ROOT)
		return false
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.seat) == int(b.seat):
			return str(a.key) < str(b.key)
		if int(a.seat) < 1:
			return false
		if int(b.seat) < 1:
			return true
		return int(a.seat) < int(b.seat)
	)
	var used_seats: Dictionary = {}
	for record: Dictionary in records:
		var seat: int = int(record.seat)
		if seat >= 1:
			if used_seats.has(seat):
				push_error("席位号重复：%d（%s）" % [seat, record.key])
				return false
			used_seats[seat] = true
		entries[record.key] = record.poses
		definitions[record.key] = {
			"name": record.name,
			"color": Color(record.color) if not str(record.color).is_empty() else Color("dbe5ff"),
			"memorial_id": record.memorial_id,
			"focus": float(record.focus),
		}
		seats.append(record.key)
	COUNT = seats.size()
	var missing: Array[String] = []
	for record: Dictionary in records:
		if int(record.memorial_id) == 0 and not record.poses.has(11):
			missing.append(record.key)
	if not missing.is_empty():
		push_warning("以下角色尚无牌位，暂用常态替代：%s" % ", ".join(missing))
	return true

static func resolve_state(character: String, state: int) -> int:
	return state if entries[character].has(state) else 0

static func texture(character: String, state: int) -> Texture2D:
	var id: int = resolve_state(character, state)
	var key: String = character + "/" + str(id)
	if cache.has(key):
		return cache[key] as Texture2D
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entries[character][id]))
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_error("立绘解码失败：" + str(entries[character][id]))
		return null
	image.generate_mipmaps()
	var created: ImageTexture = ImageTexture.create_from_image(image)
	cache[key] = created
	return created

# 把剧本里会用到的表情/牌位提前解码到显存，避免播放中第一次换表情时
# 在主线程解 1024x1536 PNG + 生成 mipmap，造成一次几十毫秒的卡顿。
static func preload_script_states(beats: Array[Dictionary]) -> void:
	for beat: Dictionary in beats:
		var speaker: int = int(beat.get("speaker", -1))
		if speaker >= 0 and speaker < seats.size():
			var key: String = character_id(speaker)
			texture(key, resolve_state(key, int(beat.get("pose", 0))))
			for change: Dictionary in beat.get("pose_changes", []):
				texture(key, resolve_state(key, int(change.get("pose", 0))))
		for reaction: Dictionary in beat.get("reactions", []):
			var seat: int = int(reaction.get("seat", -1))
			if seat >= 0 and seat < seats.size():
				var reaction_key: String = character_id(seat)
				texture(reaction_key, resolve_state(reaction_key, int(reaction.get("pose", 0))))
		for seat: int in beat.get("empty_seats", []):
			if seat >= 0 and seat < seats.size():
				texture(character_id(int(seat)), memorial_id(int(seat)))

# 构图锚点：用 chara.yaml 的 focus 字段（脸部/眼睛在画布中的高度比例），
# 锚点落在脸下方 FOCUS_BELOW_FACE 米，让人物处于画面中上部而不是被顶到边上。
# 坐姿、半身、带大发型或帽子的立绘都能按各自画面单独标定；未配置时
# 退回到 alpha 顶部 + 约 10% 画布高度估算脸的位置。
const FOCUS_BELOW_FACE: float = 0.25
const DEFAULT_FACE_RATIO: float = 0.11
static var _focus_cache: Dictionary = {}
static func focus_height(seat: int) -> float:
	var key: String = character_id(seat)
	if _focus_cache.has(key):
		return float(_focus_cache[key])
	var face_ratio: float = float(definitions[key].get("focus", -1.0))
	if face_ratio < 0.0:
		face_ratio = DEFAULT_FACE_RATIO
		var texture2d: Texture2D = texture(key, 0)
		if texture2d != null:
			var image: Image = texture2d.get_image()
			if image != null and image.get_height() > 0:
				var used: Rect2i = image.get_used_rect()
				if used.size.y > 0:
					face_ratio = float(used.position.y) / float(image.get_height()) + 0.10
	var value: float = StageParams.FOOT_Y + (1.0 - face_ratio) * StageParams.PORTRAIT_HEIGHT - FOCUS_BELOW_FACE
	_focus_cache[key] = value
	return value

static func memorial_id(seat: int) -> int:
	return int(definitions[character_id(seat)].memorial_id)

static func color(seat: int) -> Color:
	var value: Color = definitions[character_id(seat)].color
	return value

static func display_name(seat: int, use_names: bool = true) -> String:
	if seat < 0:
		return "系统广播"
	if use_names:
		return str(definitions[character_id(seat)].name)
	return "%d号" % (seat + 1)

static func render_references(text: String, use_names: bool) -> String:
	var rendered: String = text
	for seat in range(COUNT):
		rendered = rendered.replace("{seat:%d}" % seat, display_name(seat, use_names))
	return rendered
