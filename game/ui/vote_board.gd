extends CanvasLayer

# 投票专用俯视板：12 个小头像直接贴在当前俯视机位投影出的真实席位坐标上，
# 板上的位置与桌边座位一一对应，不再另画一圈和 3D 对不上的示意椭圆。
const Catalog = preload("res://resources/character_catalog.gd")
var board: Control
var from_seat: int = -1
var to_seat: int = -1
var amount: float = 0.0
var votes: Array = []
var seat_points: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	layer = 4
	board = Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	board.draw.connect(_draw_board)
	visible = false

func show_vote(from_seat: int, to_seat: int, value: float, vote_list: Array = [], points: PackedVector2Array = PackedVector2Array()) -> void:
	var active: bool = value > 0.001
	if active != visible:
		visible = active
	self.from_seat = from_seat
	self.to_seat = to_seat
	self.amount = clampf(value, 0.0, 1.0)
	self.votes = vote_list
	self.seat_points = points
	board.queue_redraw()

func _fallback_point(index: int, center: Vector2, radius: Vector2) -> Vector2:
	# 没有相机投影时的兜底：等角椭圆排布。
	var angle: float = -PI * 0.5 + TAU * float(index) / float(maxi(Catalog.COUNT, 1))
	return center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)

func _point(index: int, center: Vector2, radius: Vector2) -> Vector2:
	if seat_points.size() == Catalog.COUNT:
		return seat_points[index]
	return _fallback_point(index, center, radius)

func _centre(center: Vector2) -> Vector2:
	if seat_points.size() != Catalog.COUNT:
		return center
	var sum: Vector2 = Vector2.ZERO
	for point in seat_points:
		sum += point
	return sum / float(seat_points.size())

func _format_weight(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return "%.1f" % value

func _draw_arrow(start: Vector2, end: Vector2, color: Color, width: float, trim: float, glow: float) -> void:
	# 参考 RTS 锁定箭头的做法：杆和平底三角头合成一整块多边形，沿弧长做透明度渐变，
	# 杆不会压进头里叠出更深的补丁；外面再罩一层很淡的宽描边当外发光。
	var control: Vector2 = (start + end) * 0.5 + (end - start).orthogonal() * 0.10
	var samples: PackedVector2Array = []
	for step in range(33):
		var t: float = float(step) / 32.0
		samples.append(start.lerp(control, t).lerp(control.lerp(end, t), t))
	if samples.size() < 3:
		return
	var tip_dir: Vector2 = (samples[samples.size() - 1] - samples[samples.size() - 2]).normalized()
	var tip: Vector2 = end - tip_dir * trim
	var side: Vector2 = tip_dir.orthogonal()
	# 箭头大小与线宽解耦：票权越高，箭头越长越宽。
	var head_len: float = 18.0 if width > 3.0 else 15.0
	var head_half: float = 9.0 if width > 3.0 else 7.5
	# 沿路径累计弧长，找到箭头底边所在的位置，杆只画到那里。
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	var running: float = 0.0
	for index in range(samples.size()):
		if index > 0:
			running += samples[index].distance_to(samples[index - 1])
		cumulative.append(running)
	var total: float = running
	var tail: Vector2 = samples[0]
	var base_index: int = samples.size() - 1
	for index in range(samples.size()):
		if tip.distance_to(samples[index]) <= head_len:
			base_index = index
			break
	# 从尾到头再折回来，形成一个闭合多边形；顶点色沿长度方向渐变。
	var outline: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	for index in range(base_index + 1):
		var point: Vector2 = samples[index]
		var tangent: Vector2 = (samples[mini(index + 1, samples.size() - 1)] - samples[maxi(index - 1, 0)]).normalized()
		var normal: Vector2 = tangent.orthogonal()
		var shade: Color = color
		shade.a *= _arrow_alpha(cumulative[index] / maxf(total, 0.001))
		outline.append(point + normal * (width * 0.5))
		colors.append(shade)
	var base: Vector2 = samples[base_index]
	var head_shade: Color = color
	head_shade.a *= _arrow_alpha(base.distance_to(tail) / maxf(total, 0.001))
	outline.append(base + side * head_half)
	colors.append(head_shade)
	outline.append(tip)
	colors.append(head_shade)
	outline.append(base - side * head_half)
	colors.append(head_shade)
	for index in range(base_index, -1, -1):
		var point: Vector2 = samples[index]
		var tangent: Vector2 = (samples[mini(index + 1, samples.size() - 1)] - samples[maxi(index - 1, 0)]).normalized()
		var normal: Vector2 = tangent.orthogonal()
		var shade: Color = color
		shade.a *= _arrow_alpha(cumulative[index] / maxf(total, 0.001))
		outline.append(point - normal * (width * 0.5))
		colors.append(shade)
	# 外发光：同一路径的宽描边，极低透明度，尾端本来就淡。
	var soft: Color = color
	soft.a *= glow * 0.16
	board.draw_polyline(samples, soft, width + 7.0, true)
	board.draw_polygon(outline, colors)

# 渐变曲线：尾端 0，到 42% 长度满亮度，中间走 smoothstep 再开 0.82 次方。
func _arrow_alpha(t: float) -> float:
	var x: float = clampf((t - 0.0) / 0.42, 0.0, 1.0)
	var eased: float = x * x * (3.0 - 2.0 * x)
	return pow(eased, 0.82)

func _draw_vote_list(origin: Vector2) -> void:
	if votes.is_empty():
		return
	# 票型合计：按目标席位合并权重，只显示得票最高的两行。
	var totals: Dictionary = {}
	for vote: Dictionary in votes:
		var target: int = int(vote.get("to", -1))
		if target < 0 or target >= Catalog.COUNT:
			continue
		totals[target] = float(totals.get(target, 0.0)) + float(vote.get("weight", 1.0))
	var ordered: Array = totals.keys()
	ordered.sort_custom(func(a: int, b: int) -> bool: return float(totals[a]) > float(totals[b]))
	var lines: Array[String] = []
	for i in range(mini(ordered.size(), 2)):
		var target: int = int(ordered[i])
		lines.append("%s %s 票" % [Catalog.display_name(target, true), _format_weight(float(totals[target]))])
	if lines.is_empty():
		return
	var text: String = "    ".join(lines)
	var color := Color(0.86, 0.90, 0.98, 0.55 + 0.45 * amount)
	board.draw_string(ThemeDB.fallback_font, origin + Vector2(-190, 34), text, HORIZONTAL_ALIGNMENT_CENTER, 380, 20, color)

func _draw_board() -> void:
	if Catalog.COUNT <= 0:
		return
	var size: Vector2 = board.size
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.45)
	var radius := Vector2(minf(size.x * 0.30, 430.0), minf(size.y * 0.245, 212.0))
	var avatar_size: float = clampf(minf(size.x, size.y) * 0.070, 54.0, 72.0)
	var origin: Vector2 = _centre(center)
	var has_projection: bool = seat_points.size() == Catalog.COUNT
	if not has_projection:
		var disc: float = minf(radius.x, radius.y) * 0.70
		board.draw_circle(center, disc, Color(0.04, 0.07, 0.12, 0.40))
	# 桌心垫一块暗底，保证“投票”和票型合计压在发光桌面上仍可读；
	# 先画垫底再画连线，箭头不会被盖断。
	board.draw_circle(origin + Vector2(0, 8), 104.0, Color(0.02, 0.03, 0.05, 0.62))
	var alpha: float = 0.25 + 0.75 * amount
	var arrow_list: Array = votes
	if arrow_list.is_empty() and from_seat >= 0 and to_seat >= 0 and from_seat != to_seat:
		arrow_list = [{"from": from_seat, "to": to_seat, "weight": 1.0}]
	# 先画线，再画头像，箭头会被头像遮住末端，看起来像真正指向这个人。
	# 每张票按索引错开点亮：只看当前 amount，seek 到同一进度结果一致。
	var lit: Dictionary = {}
	var count: int = maxi(arrow_list.size(), 1)
	for i in range(arrow_list.size()):
		var vote: Dictionary = arrow_list[i]
		var source: int = int(vote.get("from", -1))
		var target: int = int(vote.get("to", -1))
		if source < 0 or target < 0 or source >= Catalog.COUNT or target >= Catalog.COUNT or source == target:
			continue
		var delay: float = 0.65 * float(i) / float(maxi(count - 1, 1))
		var appear: float = smoothstep(delay, delay + 0.20, amount)
		if appear <= 0.001:
			continue
		var weight: float = float(vote.get("weight", 1.0))
		# 每张票用投票人自己的颜色，而不是全部统一一种颜色。
		var color: Color = Catalog.color(source).lightened(0.18)
		color.a = 0.92 * alpha * appear
		_draw_arrow(
			_point(source, center, radius), _point(target, center, radius),
			color, 3.8 if weight > 1.01 else 2.8,
			avatar_size * 0.62 + 4.0, 0.22 * appear
		)
		lit[target] = float(lit.get(target, 0.0)) + weight
	for index in range(Catalog.COUNT):
		var point: Vector2 = _point(index, center, radius)
		var color: Color = Catalog.color(index)
		var rect := Rect2(point - Vector2(avatar_size, avatar_size) * 0.5, Vector2(avatar_size, avatar_size))
		board.draw_rect(rect.grow(4), Color(0.06, 0.09, 0.14, 0.92))
		var texture: Texture2D = Catalog.texture(Catalog.character_id(index), 0)
		if texture != null:
			# 取原图头部区域；不按透明外接框重新裁切，保持同一比例。
			var side: float = texture.get_width() * 0.52
			var region := Rect2((texture.get_width() - side) * 0.5, texture.get_height() * 0.015, side, side)
			board.draw_texture_rect_region(texture, rect, region)
		var ring_color: Color = color.lightened(0.15)
		if index == from_seat:
			ring_color = Color("eef3ff")
		if index == to_seat:
			ring_color = Color("ff6b6b")
		board.draw_rect(rect.grow(4), ring_color, false, 3.0)
		# 名字单独一行，向外侧偏移；不再重复座位号，也不补零。
		var label: String = Catalog.display_name(index, true)
		var font_size: int = 15
		var text_width: float = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var box_width: float = text_width + 16.0
		var outward: Vector2 = (point - origin)
		if outward.length() < 1.0:
			outward = Vector2.DOWN
		outward = outward.normalized()
		var label_pos: Vector2 = point + outward * (avatar_size * 0.5 + 16.0) - Vector2(box_width * 0.5, 0.0)
		board.draw_rect(Rect2(label_pos + Vector2(0, -13), Vector2(box_width, 20)), Color(0.02, 0.03, 0.05, 0.72))
		board.draw_string(ThemeDB.fallback_font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, box_width, font_size, color.lightened(0.35))
	# 得票徽章：放在头像朝桌心的一侧，避开向外排布的名字。
	for target: int in lit.keys():
		var point: Vector2 = _point(target, center, radius)
		var inward: Vector2 = origin - point
		if inward.length() < 1.0:
			inward = Vector2.DOWN
		inward = inward.normalized()
		var badge: Vector2 = point + inward * (avatar_size * 0.5 + 15.0)
		board.draw_circle(badge, 14.0, Color(0.02, 0.03, 0.05, 0.88))
		board.draw_arc(badge, 14.0, 0.0, TAU, 24, Catalog.color(target).lightened(0.25), 2.0, true)
		var text: String = _format_weight(float(lit[target]))
		var text_size: Vector2 = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		board.draw_string(
			ThemeDB.fallback_font, badge - Vector2(text_size.x * 0.5, -5.5), text,
			HORIZONTAL_ALIGNMENT_CENTER, text_size.x, 16, Color("eef3ff")
		)
	var title_pos: Vector2 = origin + Vector2(-36, 2)
	board.draw_string(ThemeDB.fallback_font, title_pos, "投票", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("c8d5f0"))
	_draw_vote_list(origin)
