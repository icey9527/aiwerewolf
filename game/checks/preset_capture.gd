extends SceneTree

# 机位预设截图：把 close / medium / outer / high 和竞选升降各拍一张，
# 用来在不动主流程的情况下核对构图。输出到 captures/。
const Arena = preload("res://stage/arena.gd")
const Portrait = preload("res://stage/portrait.gd")
const Catalog = preload("res://resources/character_catalog.gd")
const Params = preload("res://config/camera_params.gd")
const Rig = preload("res://camera/camera_rig.gd")

const JOBS: Array[Dictionary] = [
	{"name": "close", "lift": 0.0},
	{"name": "medium", "lift": 0.0},
	{"name": "outer", "lift": 0.0},
	{"name": "high", "lift": 0.0},
	{"name": "medium-elevated", "lift": 1.0, "file": "medium-lift"},
]

var arena: Node3D
var camera: Camera3D
var portraits: Array[Node3D] = []
var built: bool = false
var index: int = -1
var busy: bool = false

func _initialize() -> void:
	Catalog.prepare()

func _process(_delta: float) -> bool:
	if not built:
		built = true
		_build()
		_next()
	return false

func _build() -> void:
	arena = Arena.new()
	root.add_child(arena)
	var seat_colors: Array[Color] = []
	for index in range(Catalog.COUNT):
		seat_colors.append(Catalog.color(index))
	arena.build(Catalog.COUNT, Params.ring_radius(Catalog.COUNT), seat_colors)
	for seat in range(Catalog.COUNT):
		var portrait: Node3D = Portrait.new()
		root.add_child(portrait)
		portrait.global_transform = arena.seat_transform(seat)
		portrait.build(seat)
		portraits.append(portrait)
	camera = Rig.new()
	root.add_child(camera)
	camera.configure(arena, Params.ring_radius(Catalog.COUNT))
	var empty: Array[Dictionary] = []
	camera.configure_beats(empty)
	arena.set_speaker(0)

func _apply(job: Dictionary) -> void:
	var lifts: Array[float] = []
	lifts.resize(Catalog.COUNT)
	lifts.fill(0.0)
	lifts[0] = float(job.get("lift", 0.0))
	arena.set_election(lifts, -1, Params.ELECTION_LIFT)
	for seat in range(Catalog.COUNT):
		portraits[seat].global_transform = arena.seat_transform(seat)
	camera.set_lifts(lifts)
	camera.sample({
		"id": "preview",
		"shot": "speaker",
		"camera_preset": str(job.name),
		"camera_seat": 0,
		"speaker": 0,
	}, 0.5, 0.0)

func _next() -> void:
	if busy:
		return
	index += 1
	if index >= JOBS.size():
		quit(0)
		return
	busy = true
	var job: Dictionary = JOBS[index]
	_apply(job)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var folder: String = ProjectSettings.globalize_path("res://")
	var file: String = folder.path_join("../captures/preset-%s.png" % str(job.get("file", job.name))).simplify_path()
	image.save_png(file)
	busy = false
	_next()
