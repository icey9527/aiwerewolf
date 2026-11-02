extends SceneTree

func _initialize() -> void:
	var path := "res://assets/characters/chatgpt/常态.png"
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	var error: Error = image.load_png_from_buffer(bytes)
	if error != OK or image.is_empty():
		push_error("无法解码 PNG：%s (%s)" % [path, error_string(error)])
		quit(1)
		return
	image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	print("PASS buffer=png size=%s mipmaps=%s texture=%s" % [image.get_size(), image.has_mipmaps(), texture != null])
	quit()
