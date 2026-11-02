extends RefCounted

var beats: Array[Dictionary] = []
var starts: Array[float] = []
var total: float = 0.0
var time: float = 0.0
var paused: bool = false
var manual: bool = false
var speed: float = 1.0
var error: String = ""

func load_script(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("beats") is Array:
		error = "剧本格式无效"
		return false
	beats.clear()
	starts.clear()
	total = 0.0
	var ids: Dictionary = {}
	for item: Variant in parsed.beats:
		if not item is Dictionary:
			error = "演出段必须为对象"
			return false
		var beat: Dictionary = item
		var id: String = str(beat.get("id", ""))
		if id.is_empty() or ids.has(id) or float(beat.get("duration", 0)) <= 0.0:
			error = "演出段 ID 重复或时长无效"
			return false
		if not str(beat.get("channel", "")) in ["public", "wolf", "private"]:
			error = "频道无效"
			return false
		if beat.has("pose"):
			var pose: Variant = beat.pose
			if not (pose is int or pose is float):
				error = "姿态必须使用数字 ID：" + id
				return false
			if float(pose) < 0.0 or float(pose) != floor(float(pose)):
				error = "姿态 ID 必须为非负整数：" + id
				return false
			beat.pose = int(pose)
		ids[id] = true
		starts.append(total)
		beats.append(beat)
		total += float(beat.duration)
	return not beats.is_empty()

func index_at(t: float) -> int:
	for i in range(beats.size() - 1, -1, -1):
		if t >= starts[i]:
			return i
	return 0

func advance(delta: float) -> void:
	if paused:
		return
	var index: int = index_at(time)
	var next_time: float = minf(total - 0.001, time + delta * speed)
	var boundary: float = starts[index] + float(beats[index].duration)
	if manual and next_time >= boundary:
		time = boundary - 0.001
		paused = true
	else:
		time = next_time
	if time >= total - 0.001:
		paused = true

func seek(t: float) -> void:
	time = clampf(t, 0.0, total - 0.001)

func next() -> void:
	var index: int = index_at(time)
	if index + 1 < beats.size():
		time = starts[index + 1]
		paused = false

func previous() -> void:
	var index: int = index_at(time)
	seek(starts[maxi(0, index - 1)])

func state() -> Dictionary:
	var index: int = index_at(time)
	var beat: Dictionary = beats[index]
	var elapsed: float = time - starts[index]
	return {"beat": beat, "index": index, "elapsed": elapsed, "progress": elapsed / float(beat.duration)}
