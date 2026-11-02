extends RefCounted

const BenchFocus = preload("res://camera/bench_focus.gd")

# 中央转向复用上游聚焦机制；移动镜头在极坐标中走最短弧。
static func sample(from: Dictionary, to: Dictionary, progress: float) -> Dictionary:
	var t: float = clampf(progress, 0.0, 1.0)
	var ease: float = BenchFocus.cubic_in_out(t)
	var a: Vector3 = from.position
	var b: Vector3 = to.position
	if a.is_equal_approx(b):
		# 同一中央机位插值朝向，避免对侧目标线性插值经过相机而翻转。
		var rotation_a: Quaternion = BenchFocus.target_rotation(a, from.target)
		var rotation_b: Quaternion = BenchFocus.target_rotation(b, to.target)
		var direction: Vector3 = -(Basis(BenchFocus.sample_rotation(rotation_a, rotation_b, t)).z)
		return {"position": a, "target": a + direction, "fov": lerpf(float(from.fov), float(to.fov), ease)}
	var angle_a: float = atan2(a.z, a.x)
	var angle_b: float = atan2(b.z, b.x)
	var angle: float = angle_a + wrapf(angle_b - angle_a, -PI, PI) * ease
	var distance: float = lerpf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length(), ease)
	var position := Vector3(cos(angle) * distance, lerpf(a.y, b.y, ease), sin(angle) * distance)
	return {
		"position": position,
		"target": (from.target as Vector3).lerp(to.target, ease),
		"fov": lerpf(float(from.fov), float(to.fov), ease),
	}
