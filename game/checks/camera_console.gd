extends SceneTree


const Paths = preload("res://config/game_paths.gd")
# 镜头预览控制台：左侧面板可选 DR2 原版镜头或旧机位预设，
# 支持家族筛选、搜索、座位、竞选升起与进度拖动。
const Arena = preload("res://stage/arena.gd")
const Portrait = preload("res://stage/portrait.gd")
const Catalog = preload("res://resources/character_catalog.gd")
const Params = preload("res://config/camera_params.gd")
const Library = preload("res://camera/shot_library.gd")
const Rig = preload("res://camera/camera_rig.gd")
const Dr2 = preload("res://camera/dr2_camera.gd")

var arena: Node3D
var camera: Camera3D
var portraits: Array[Node3D] = []
var built: bool = false
var capture_path: String = ""
var frames: int = 0
var hide_ui: bool = false
var ui_layer: CanvasLayer

var dr2_mode: bool = true
var dr2_shot: String = "PAN_L_00"
var dr2_family: String = "全部"
var dr2_search: String = ""
var dr2_progress: float = 0.0
var dr2_scale: float = 0.30
var dr2_duration: float = 3.0
# 构图锚点高度；-1 表示自动使用角色 chara.yaml 的 focus。
var focus_override: float = -1.0
# 房间中心锚点（LOOKOUT / *_OVER 全景用）；anchor_height / focus_height 可单独覆盖。
var center_anchor: bool = false
var anchor_height_override: float = -1.0
var fov_override: float = -1.0
var zero_pitch: bool = false
var playing: bool = true
var preset_index: int = 1
var seat: int = 0
var lifted: bool = false
var time: float = 0.0

var panel: PanelContainer
var mode_option: OptionButton
var seat_option: OptionButton
var lift_check: CheckButton
var dr2_box: VBoxContainer
var legacy_box: VBoxContainer
var family_option: OptionButton
var search_edit: LineEdit
var shot_option: OptionButton
var progress_slider: HSlider
var progress_label: Label
var scale_slider: HSlider
var scale_label: Label
var focus_slider: HSlider
var focus_label: Label
var play_check: CheckButton
var preset_option: OptionButton
var info_label: Label

var families: PackedStringArray = PackedStringArray()
var family_shots: Array[String] = []
var _family_regex: RegEx

func _initialize() -> void:
	Catalog.prepare()
	_family_regex = RegEx.new()
	_family_regex.compile("_\\d+(?:_END|_N\\d+)?$")
	var wanted_progress: float = -1.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--seat="):
			seat = clampi(int(argument.trim_prefix("--seat=")) - 1, 0, Catalog.COUNT - 1)
		if argument == "--lift":
			lifted = true
		if argument.begins_with("--dr2="):
			dr2_shot = argument.trim_prefix("--dr2=")
		if argument.begins_with("--preset="):
			var wanted: String = argument.trim_prefix("--preset=")
			dr2_mode = false
			var presets: Array[String] = ["close", "medium", "outer", "high"]
			if presets.has(wanted):
				preset_index = presets.find(wanted)
		if argument == "--legacy":
			dr2_mode = false
		if argument == "--no-ui":
			hide_ui = true
		if argument.begins_with("--progress="):
			wanted_progress = float(argument.trim_prefix("--progress="))
		if argument.begins_with("--focus="):
			focus_override = float(argument.trim_prefix("--focus="))
		if argument.begins_with("--anchor="):
			anchor_height_override = float(argument.trim_prefix("--anchor="))
		if argument.begins_with("--fov="):
			fov_override = float(argument.trim_prefix("--fov="))
		if argument.begins_with("--scale="):
			dr2_scale = float(argument.trim_prefix("--scale="))
		if argument == "--center":
			center_anchor = true
		if argument == "--nopitch":
			zero_pitch = true
	if wanted_progress >= 0.0:
		dr2_progress = clampf(wanted_progress, 0.0, 1.0)
		playing = false
	if not dr2_shot.is_empty():
		dr2_family = _family_of(dr2_shot)

func _family_of(shot_name: String) -> String:
	var result: RegExMatch = _family_regex.search(shot_name)
	if result != null:
		return shot_name.substr(0, result.get_start())
	return shot_name

func _process(delta: float) -> bool:
	if not built:
		built = true
		_build()
	if dr2_mode and playing:
		dr2_progress = minf(1.0, dr2_progress + delta / maxf(dr2_duration, 0.01))
	else:
		time += delta
	_solve()
	_update_ui()
	frames += 1
	if not capture_path.is_empty() and frames == 10:
		_capture()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_path)
	quit(0)

func _build() -> void:
	arena = Arena.new()
	root.add_child(arena)
	var colors: Array[Color] = []
	for index in range(Catalog.COUNT):
		colors.append(Catalog.color(index))
	arena.build(Catalog.COUNT, Params.ring_radius(Catalog.COUNT), colors)
	for index in range(Catalog.COUNT):
		var portrait: Node3D = Portrait.new()
		root.add_child(portrait)
		portrait.global_transform = arena.seat_transform(index)
		portrait.build(index)
		portraits.append(portrait)
	camera = Rig.new()
	root.add_child(camera)
	camera.configure(arena, Params.ring_radius(Catalog.COUNT))
	var empty: Array[Dictionary] = []
	camera.configure_beats(empty)
	_build_ui()
	if hide_ui and ui_layer != null:
		ui_layer.visible = false

func _build_ui() -> void:
	var font: Font = Paths.font_ui()
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", Color("dbe5ff"))

	var layer := CanvasLayer.new()
	ui_layer = layer
	root.add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(380, 0)
	panel.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.09, 0.94)
	style.border_color = Color("2b3f63")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "镜头预览"
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color("e0b45a")
	column.add_child(title)

	mode_option = OptionButton.new()
	mode_option.add_item("DR2 原版镜头")
	mode_option.add_item("旧机位预设")
	mode_option.selected = 0 if dr2_mode else 1
	mode_option.item_selected.connect(_on_mode_selected)
	column.add_child(mode_option)

	var seat_row := HBoxContainer.new()
	seat_row.add_theme_constant_override("separation", 8)
	column.add_child(seat_row)
	seat_row.add_child(_label("座位"))
	seat_option = OptionButton.new()
	for index in range(Catalog.COUNT):
		seat_option.add_item("%d号 · %s" % [index + 1, Catalog.display_name(index)], index)
	seat_option.selected = seat
	seat_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_option.item_selected.connect(_on_seat_selected)
	seat_row.add_child(seat_option)
	lift_check = CheckButton.new()
	lift_check.text = "升起"
	lift_check.button_pressed = lifted
	lift_check.toggled.connect(_on_lift_toggled)
	seat_row.add_child(lift_check)

	# 锚点高度：默认取该角色 chara.yaml 的 focus（脸部位置），拖动可现场校准取景。
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 8)
	column.add_child(focus_row)
	focus_row.add_child(_label("锚点"))
	focus_slider = HSlider.new()
	focus_slider.min_value = 0.4
	focus_slider.max_value = 3.2
	focus_slider.step = 0.01
	focus_slider.value = focus_override if focus_override > 0.0 else Catalog.focus_height(seat)
	focus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_slider.value_changed.connect(_on_focus_changed)
	focus_row.add_child(focus_slider)
	focus_label = Label.new()
	focus_label.custom_minimum_size = Vector2(86, 0)
	focus_label.add_theme_font_size_override("font_size", 13)
	focus_row.add_child(focus_label)

	dr2_box = VBoxContainer.new()
	dr2_box.add_theme_constant_override("separation", 6)
	column.add_child(dr2_box)
	var family_row := HBoxContainer.new()
	family_row.add_theme_constant_override("separation", 8)
	dr2_box.add_child(family_row)
	family_row.add_child(_label("家族"))
	family_option = OptionButton.new()
	family_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	family_option.item_selected.connect(_on_family_selected)
	family_row.add_child(family_option)
	_fill_families()
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	dr2_box.add_child(search_row)
	search_row.add_child(_label("搜索"))
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "镜头名关键字"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_changed.connect(_on_search_changed)
	search_row.add_child(search_edit)
	shot_option = OptionButton.new()
	shot_option.item_selected.connect(_on_shot_selected)
	dr2_box.add_child(shot_option)
	_rebuild_shots()

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	dr2_box.add_child(progress_row)
	progress_row.add_child(_label("进度"))
	progress_slider = HSlider.new()
	progress_slider.min_value = 0.0
	progress_slider.max_value = 1.0
	progress_slider.step = 0.001
	progress_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_slider.value_changed.connect(_on_progress_changed)
	progress_row.add_child(progress_slider)
	progress_label = Label.new()
	progress_label.custom_minimum_size = Vector2(86, 0)
	progress_label.add_theme_font_size_override("font_size", 13)
	progress_row.add_child(progress_label)
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	dr2_box.add_child(scale_row)
	scale_row.add_child(_label("距离"))
	scale_slider = HSlider.new()
	scale_slider.min_value = 0.10
	scale_slider.max_value = 0.50
	scale_slider.step = 0.01
	scale_slider.value = dr2_scale
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value_changed.connect(_on_scale_changed)
	scale_row.add_child(scale_slider)
	scale_label = Label.new()
	scale_label.custom_minimum_size = Vector2(52, 0)
	scale_label.add_theme_font_size_override("font_size", 13)
	scale_row.add_child(scale_label)
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 10)
	dr2_box.add_child(play_row)
	play_check = CheckButton.new()
	play_check.text = "自动播放"
	play_check.button_pressed = playing
	play_check.toggled.connect(_on_play_toggled)
	play_row.add_child(play_check)
	var replay := Button.new()
	replay.text = "重播"
	replay.pressed.connect(_on_replay)
	play_row.add_child(replay)

	legacy_box = VBoxContainer.new()
	legacy_box.add_theme_constant_override("separation", 6)
	column.add_child(legacy_box)
	preset_option = OptionButton.new()
	for index in range(4):
		var name: String = ["close", "medium", "outer", "high"][index]
		var preset: Dictionary = Library.preset(name)
		preset_option.add_item("%s · 半径 %.2f / 高 %.2f" % [name.to_upper(), float(preset.radius), float(preset.height)], index)
	preset_option.selected = preset_index
	preset_option.item_selected.connect(_on_preset_selected)
	legacy_box.add_child(preset_option)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.modulate = Color("9eaecb")
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info_label)

	_apply_mode_visibility()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(40, 0)
	return label

func _fill_families() -> void:
	family_option.clear()
	family_option.add_item("全部", 0)
	families = PackedStringArray()
	var seen: Dictionary = {}
	for name in Dr2.shot_names():
		var family: String = _family_of(name)
		if not seen.has(family):
			seen[family] = true
			families.append(family)
	families.sort()
	for family in families:
		family_option.add_item(family, family_option.item_count)
	var wanted: int = 0
	if dr2_family != "全部":
		for index in range(families.size()):
			if families[index] == dr2_family:
				wanted = index + 1
				break
	family_option.selected = wanted

func _on_family_selected(index: int) -> void:
	dr2_family = "全部" if index <= 0 else families[index - 1]
	_rebuild_shots()
	_reset_progress()

func _on_search_changed(text: String) -> void:
	dr2_search = text.strip_edges()
	_rebuild_shots()
	_reset_progress()

func _rebuild_shots() -> void:
	family_shots.clear()
	var keyword: String = dr2_search.to_upper()
	for name in Dr2.shot_names():
		if dr2_family != "全部" and _family_of(name) != dr2_family:
			continue
		if not keyword.is_empty() and not name.to_upper().contains(keyword):
			continue
		family_shots.append(name)
	shot_option.clear()
	var selected_index: int = 0
	for index in range(family_shots.size()):
		shot_option.add_item(family_shots[index], index)
		if family_shots[index] == dr2_shot:
			selected_index = index
	if not family_shots.is_empty():
		if not family_shots.has(dr2_shot):
			dr2_shot = family_shots[0]
		shot_option.selected = family_shots.find(dr2_shot)
	shot_option.disabled = family_shots.is_empty()

func _on_shot_selected(index: int) -> void:
	if index < 0 or index >= family_shots.size():
		return
	dr2_shot = family_shots[index]
	_reset_progress()

func _on_progress_changed(value: float) -> void:
	if playing:
		playing = false
		play_check.set_pressed_no_signal(false)
	dr2_progress = value

func _on_play_toggled(pressed: bool) -> void:
	playing = pressed
	if pressed and dr2_progress >= 0.999:
		dr2_progress = 0.0

func _on_replay() -> void:
	dr2_progress = 0.0
	playing = true
	play_check.set_pressed_no_signal(true)

func _reset_progress() -> void:
	dr2_progress = 0.0
	playing = true
	if play_check != null:
		play_check.set_pressed_no_signal(true)

func _on_mode_selected(index: int) -> void:
	dr2_mode = index == 0
	_apply_mode_visibility()

func _on_seat_selected(index: int) -> void:
	seat = index
	# 换角色时锚点回到该角色自动值。
	focus_override = -1.0
	if focus_slider != null:
		focus_slider.set_value_no_signal(Catalog.focus_height(seat))

func _on_focus_changed(value: float) -> void:
	focus_override = value

func _on_lift_toggled(pressed: bool) -> void:
	lifted = pressed

func _on_preset_selected(index: int) -> void:
	preset_index = index
	time = 0.0

func _apply_mode_visibility() -> void:
	if dr2_box != null:
		dr2_box.visible = dr2_mode
	if legacy_box != null:
		legacy_box.visible = not dr2_mode

func _on_scale_changed(value: float) -> void:
	dr2_scale = value

func _solve() -> void:
	var lifts: Array[float] = []
	lifts.resize(Catalog.COUNT)
	lifts.fill(0.0)
	lifts[seat] = 1.0 if lifted else 0.0
	arena.set_election(lifts, -1, Params.ELECTION_LIFT)
	for index in range(portraits.size()):
		portraits[index].global_transform = arena.seat_transform(index)
	if dr2_mode:
		var elapsed: float = dr2_progress * dr2_duration
		var anchor_focus: float = focus_override if focus_override > 0.0 else Catalog.focus_height(seat)
		var anchor_transform: Transform3D = arena.seat_transform(seat)
		var anchor_height: float = anchor_focus + 0.05
		var focus_height: float = anchor_focus
		if center_anchor:
			# 全景镜头：锚点放在房间中心，高度/注视高度可单独覆盖。
			anchor_transform = Transform3D.IDENTITY
			anchor_height = anchor_height_override if anchor_height_override > 0.0 else 6.0
			focus_height = focus_override if focus_override > 0.0 else 3.0
		var sampled: Dictionary = Dr2.sample(
			dr2_shot, anchor_transform, elapsed, 0.0,
			dr2_scale, anchor_height, focus_height,
			0.0 if zero_pitch else Dr2.PITCH_SCALE, fov_override
		)
		if not sampled.is_empty():
			camera.global_transform = sampled.transform as Transform3D
			camera.fov = float(sampled.fov)
			dr2_duration = float(sampled.duration)
		camera.set_lifts(lifts)
	else:
		var presets: Array[String] = ["close", "medium", "outer", "high"]
		camera.set_lifts(lifts)
		camera.sample({
			"id": "preview",
			"shot": "speaker",
			"camera_preset": presets[preset_index],
			"camera_seat": seat,
			"speaker": seat,
		}, 0.5, time)

func _update_ui() -> void:
	if progress_slider != null:
		progress_slider.set_value_no_signal(dr2_progress)
	if progress_label != null:
		progress_label.text = "%.2f / %.1fs" % [dr2_progress, dr2_duration]
	if scale_label != null:
		scale_label.text = "×%.2f" % dr2_scale
	if focus_label != null:
		var auto_focus: float = Catalog.focus_height(seat)
		var shown_focus: float = focus_override if focus_override > 0.0 else auto_focus
		focus_label.text = "%.2fm%s" % [shown_focus, "" if focus_override > 0.0 else " 自动"]
	if info_label == null:
		return
	if dr2_mode:
		var count: int = maxi(Dr2.shot_names().size(), 1)
		var info: Dictionary = Dr2.info(dr2_shot)
		var motion: String = "固定机位（不会动）" if bool(info.get("static", true)) else "移动 %.2fm / %.1f°" % [float(info.get("position_delta", 0.0)), float(info.get("rotation_delta", 0.0))]
		if int(info.get("next", 0)) == 1:
			motion += " · 原版有连段"
		info_label.text = "当前：%s\n%s   时长 %.1fs\n家族：%s   家族内 %d / 全部 %d\n锚点：%d号 %s   升起：%s" % [
			dr2_shot, motion, float(info.get("duration", 3.0)), dr2_family, family_shots.size(), count, seat + 1,
			Catalog.display_name(seat), "开" if lifted else "关",
		]
	else:
		var presets: Array[String] = ["close", "medium", "outer", "high"]
		info_label.text = "当前：旧机位 %s\n座位：%d号 %s   升起：%s" % [
			presets[preset_index].to_upper(), seat + 1, Catalog.display_name(seat), "开" if lifted else "关",
		]
