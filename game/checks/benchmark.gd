extends SceneTree

# 开发用帧时间采样：加载主场景，跳过预热帧后逐帧记录间隔，
# 输出平均值、p95、最差帧与渲染统计。只用于性能核对，不参与正式演出。
var frames_left: int = 600
var warmup: int = 90
var records: Array[float] = []
var last_us: int = 0
var main: Node
var unlimited: bool = false
var foreground: bool = false
var exclusive: bool = false
var vsync_name: String = ""
var max_override: int = -1
var pending_apply: bool = true

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bench-frames="):
			frames_left = int(argument.trim_prefix("--bench-frames="))
		if argument == "--bench-unlimited":
			unlimited = true
		if argument == "--bench-foreground":
			foreground = true
		if argument == "--bench-exclusive":
			exclusive = true
		if argument.begins_with("--bench-vsync="):
			vsync_name = argument.trim_prefix("--bench-vsync=")
		if argument.begins_with("--bench-max="):
			max_override = int(argument.trim_prefix("--bench-max="))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

# 主场景的 _ready 在加入场景树后才执行，所以覆盖要在第一帧里做。
func _apply_override() -> void:
	if exclusive:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	if max_override >= 0:
		Engine.max_fps = max_override
	if unlimited:
		Engine.max_fps = 0
	match vsync_name:
		"enabled":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		"mailbox":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
		"adaptive":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		"disabled":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if foreground:
		DisplayServer.window_move_to_foreground()

func _percentile(sorted_values: Array[float], ratio: float) -> float:
	var index: int = clampi(int(round(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]

func _report() -> void:
	records.sort()
	var total: float = 0.0
	for value in records:
		total += value
	var average: float = total / float(maxi(records.size(), 1))
	print("frames=%d  avg=%.2fms  p50=%.2f  p95=%.2f  p99=%.2f  max=%.2f" % [
		records.size(), average, _percentile(records, 0.5), _percentile(records, 0.95),
		_percentile(records, 0.99), records[records.size() - 1],
	])
	print("screen_refresh=%.1fHz  max_fps=%d  vsync=%d" % [
		DisplayServer.screen_get_refresh_rate(), Engine.max_fps, DisplayServer.window_get_vsync_mode(),
	])
	print("draw_calls=%d  primitives=%d  objects=%d  vram=%.1fMB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	])

func _process(_delta: float) -> bool:
	if pending_apply:
		pending_apply = false
		_apply_override()
		last_us = 0
		warmup = 90
		return false
	var now: int = Time.get_ticks_usec()
	if warmup > 0:
		warmup -= 1
		last_us = now
		return false
	if records.size() >= frames_left:
		_report()
		return true
	if last_us > 0:
		records.append(float(now - last_us) / 1000.0)
	last_us = now
	return false
