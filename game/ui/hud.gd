extends CanvasLayer


const Paths = preload("res://config/game_paths.gd")
signal action_requested(action: String)
signal seek_requested(time: float)

const Catalog = preload("res://resources/character_catalog.gd")
const Timing = preload("res://config/timing_params.gd")
var status: Label
var info: Label
var shot_tag: Label
var speaker: Label
var dialogue: RichTextLabel
var channel: Label
var clock: Label
var subtitle_panel: PanelContainer
var subtitle_style: StyleBoxFlat
var play_button: Button
var mode_button: Button
var progress: HSlider
var history_panel: PanelContainer
var history_text: RichTextLabel
var terminal_panel: PanelContainer
var terminal_text: Label
var current_id: String = ""
var reveal_all: bool = false
var use_names: bool = true
var history_entries: Array[String] = []
var seen_ids: Dictionary = {}

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = Paths.font_ui()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("dbe5ff"))
	theme.set_font_size("font_size", "Button", 16)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.055, 0.08, 0.13, 0.92)
		box.border_color = Color("2b3f63") if state != "hover" else Color("4d6bfe")
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		theme.set_stylebox(state, "Button", box)
	theme.set_color("font_color", "Button", Color("c5d3ec"))
	theme.set_color("font_hover_color", "Button", Color("ffffff"))
	theme.set_color("font_pressed_color", "Button", Color("9db4ff"))
	root.theme = theme
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	status = Label.new()
	status.text = "圆桌审判 / 固定剧本演出"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(status)
	var demo := Label.new()
	demo.text = "上帝视角 · 无 API 请求"
	demo.modulate = Color("9eaecb")
	header.add_child(demo)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 15)
	info.modulate = Color("7f90ad")
	info.text = "—— FPS"
	header.add_child(info)
	# 当前机位单独一行，方便一眼确认走的是 DR2 原版还是旧机位。
	shot_tag = Label.new()
	shot_tag.add_theme_font_size_override("font_size", 16)
	shot_tag.modulate = Color("e0b45a")
	shot_tag.text = "机位：——"
	column.add_child(shot_tag)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	terminal_panel = _panel(Color("121d30"))
	terminal_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	terminal_panel.custom_minimum_size = Vector2(350, 120)
	column.add_child(terminal_panel)
	terminal_text = Label.new()
	terminal_text.add_theme_font_size_override("font_size", 20)
	terminal_panel.add_child(terminal_text)
	subtitle_panel = _panel(Color(0.018, 0.024, 0.036, 0.88))
	subtitle_style = subtitle_panel.get_theme_stylebox("panel").duplicate()
	subtitle_style.content_margin_left = 18
	subtitle_style.content_margin_right = 18
	subtitle_style.content_margin_top = 9
	subtitle_style.content_margin_bottom = 9
	subtitle_panel.add_theme_stylebox_override("panel", subtitle_style)
	column.add_child(subtitle_panel)
	var subtitle_column := VBoxContainer.new()
	subtitle_column.add_theme_constant_override("separation", 4)
	subtitle_panel.add_child(subtitle_column)
	var identity := HBoxContainer.new()
	subtitle_column.add_child(identity)
	speaker = Label.new()
	speaker.add_theme_font_size_override("font_size", 20)
	speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(speaker)
	channel = Label.new()
	channel.add_theme_font_size_override("font_size", 16)
	identity.add_child(channel)
	dialogue = RichTextLabel.new()
	dialogue.custom_minimum_size.y = 42
	dialogue.bbcode_enabled = false
	dialogue.fit_content = true
	dialogue.add_theme_font_size_override("normal_font_size", 21)
	dialogue.add_theme_constant_override("line_separation", 5)
	subtitle_column.add_child(dialogue)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	column.add_child(controls)
	_button(controls, "上一句", "previous")
	play_button = _button(controls, "暂停", "pause")
	_button(controls, "继续 ›", "next")
	mode_button = _button(controls, "自动播放", "mode")
	_button(controls, "速度 ×1", "speed")
	_button(controls, "发言记录", "history")
	_button(controls, "名字／位次", "names")
	progress = HSlider.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.step = 0.05
	progress.value_changed.connect(_on_seek)
	controls.add_child(progress)
	clock = Label.new()
	clock.custom_minimum_size.x = 178
	controls.add_child(clock)
	history_panel = _panel(Color("10192a"))
	history_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	history_panel.position = Vector2(300, 100)
	history_panel.size = Vector2(1000, 540)
	history_panel.visible = false
	root.add_child(history_panel)
	history_text = RichTextLabel.new()
	history_text.custom_minimum_size = Vector2(900, 440)
	history_panel.add_child(history_text)

func _panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("334c76")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _button(parent: Control, text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(_on_action.bind(action))
	parent.add_child(button)
	return button

func _on_action(action: String) -> void:
	if action == "history":
		history_panel.visible = not history_panel.visible
	elif action == "names":
		use_names = not use_names
	else:
		action_requested.emit(action)

func _on_seek(time: float) -> void:
	seek_requested.emit(time)

func show_state(state: Dictionary, time: float, total: float, paused: bool, manual: bool, speed: float, pacing: String = "", camera_mode: String = "dr2") -> void:
	var beat: Dictionary = state.beat
	var id: String = str(beat.id)
	if current_id != id:
		current_id = id
		reveal_all = false
	var private_channel: bool = str(beat.channel) != "public"
	var channel_name: String = {"public":"公共频道", "wolf":"狼队私人频道 · 上帝可见", "private":"神职私人终端 · 上帝可见"}.get(str(beat.channel), "公共频道")
	var accent: Color = Color("de6777") if str(beat.channel) == "wolf" else (Color("65c9a3") if private_channel else Color("8fa9ff"))
	var phase: String = "公开审判"
	if str(beat.kind) in ["closing", "sealed", "wolf", "oracle"]:
		phase = "夜间隔离"
	elif str(beat.kind).begins_with("sheriff_"):
		phase = "警长竞选"
	status.text = "圆桌审判 / " + phase
	speaker.text = Catalog.display_name(int(beat.speaker), use_names)
	if int(beat.speaker) >= 0:
		speaker.modulate = Catalog.color(int(beat.speaker)).lightened(0.18)
	else:
		speaker.modulate = Color("dbe5ff")
	channel.text = channel_name
	channel.modulate = accent
	var frame_size: Vector2i = get_viewport().get_visible_rect().size
	var dr2_shot: String = str(beat.get("dr2_shot", "")) if camera_mode == "dr2" else ""
	# 开场由多段原版镜头剪接：按当前段显示实际在用的镜头名。
	if camera_mode == "dr2" and beat.has("intro_cuts"):
		dr2_shot = _intro_shot_at(beat, float(state.get("elapsed", 0.0)))
	var shot_name: String = ("DR2 " + dr2_shot).to_upper() if not dr2_shot.is_empty() else str(beat.get("camera_preset", beat.get("shot", ""))).to_upper()
	if shot_tag != null:
		if not dr2_shot.is_empty():
			shot_tag.text = "机位：DR2 原版 · %s" % dr2_shot
		elif str(beat.get("shot", "")) == "orbit" or bool(beat.get("camera_orbit", false)):
			shot_tag.text = "机位：环绕 · 随机点位"
		elif str(beat.get("shot", "")) == "intro":
			shot_tag.text = "机位：开场 · 外圈 → 内圈"
		else:
			shot_tag.text = "机位：旧机位 · %s" % str(beat.get("camera_preset", beat.get("shot", ""))).to_upper()
	info.text = "· %d×%d · %d FPS · %s · %s" % [frame_size.x, frame_size.y, Engine.get_frames_per_second(), pacing, shot_name]
	subtitle_style.border_color = Catalog.color(int(beat.speaker)).lightened(0.15) if int(beat.speaker) >= 0 else accent
	dialogue.text = Catalog.render_references(str(beat.text), use_names)
	dialogue.visible_characters = -1 if reveal_all else int(float(state.elapsed) / Timing.TYPE_INTERVAL)
	play_button.text = "播放" if paused else "暂停"
	mode_button.text = "逐句阅读" if manual else "自动播放"
	progress.max_value = total
	progress.set_value_no_signal(time)
	clock.text = "%02d:%02d / %02d:%02d" % [int(time) / 60, int(time) % 60, int(total) / 60, int(total) % 60]
	terminal_panel.visible = private_channel
	terminal_text.modulate = accent
	var terminal_lines: Array[String] = ["私人终端 · 剧本演示"]
	if str(beat.channel) == "wolf":
		var mate_names: PackedStringArray = PackedStringArray()
		for mate: int in beat.get("wolves", []):
			mate_names.append(Catalog.display_name(int(mate), true))
		terminal_lines.append("● 队友 " + (" / ".join(mate_names) if not mate_names.is_empty() else "—") + " 已连接")
		terminal_lines.append("通讯加密 · 外部不可见")
	else:
		var check_target: int = int(beat.get("check_target", -1))
		terminal_lines.append("预言家 / 查验 " + (Catalog.display_name(check_target, false) if check_target >= 0 else "—"))
		terminal_lines.append("查验已确认 · 私人结果已存档")
	terminal_text.text = "\n".join(PackedStringArray(terminal_lines))
	if str(beat.channel) == "public" and not seen_ids.has(id):
		seen_ids[id] = true
		history_entries.append(Catalog.display_name(int(beat.speaker)) + "：" + Catalog.render_references(str(beat.text), true))
		history_text.text = "公共发言记录（仅已观看片段）\n\n" + "\n\n".join(history_entries)
	for child in mode_button.get_parent().get_children():
		if child is Button and str(child.text).begins_with("速度"):
			child.text = "速度 ×%d" % int(speed)

func _intro_shot_at(beat: Dictionary, elapsed: float) -> String:
	var cuts: Array = beat.get("intro_cuts", [])
	for i in range(cuts.size()):
		var cut: Dictionary = cuts[i]
		if elapsed < float(cut.get("until", beat.get("duration", 12.0))) or i == cuts.size() - 1:
			return str(cut.get("shot", ""))
	return ""

func continue_dialogue() -> void:
	if dialogue.visible_characters >= 0 and dialogue.visible_characters < dialogue.get_total_character_count():
		reveal_all = true
	else:
		action_requested.emit("next")
