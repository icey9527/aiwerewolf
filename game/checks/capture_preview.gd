extends SceneTree

# 仅用于本机视觉验收，不加入游戏入口。
var scene: Node3D
var output: String
var frame: int = 0
const FPS: int = 15
const SECONDS: int = 15

func _initialize() -> void:
	output = ProjectSettings.globalize_path("res://../captures/motion-frames")
	DirAccess.make_dir_recursive_absolute(output)
	_start.call_deferred()

func _start() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.player.paused = true
	root.size = Vector2i(1280, 720)
	_capture_frame()

func _capture_frame() -> void:
	scene.player.seek(float(frame) / float(FPS))
	scene._sample()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_jpg(output.path_join("%04d.jpg" % frame), 0.88)
	frame += 1
	if frame >= FPS * SECONDS:
		quit()
	else:
		_capture_frame.call_deferred()
