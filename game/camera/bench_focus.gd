extends RefCounted

# 改编自 Saupernova13/customronpa-trial-engine 的 bench_focus_camera.gd。
# 上游版本：79e057c7a29239c5ee69e58252e11dc407663b0e，focus_on_bench 第 239–255 行。
# Copyright (c) 2026 Saupernova13，MIT；完整许可见仓库 third_party/。
# 保留 looking_at → 四元数 → cubic in-out，Tween 改为绝对时间采样以支持回放。
static func target_rotation(camera_position: Vector3, marker_position: Vector3, pitch_offset: float = 0.0, yaw_offset: float = 0.0) -> Quaternion:
	var look_transform: Transform3D = Transform3D(Basis.IDENTITY, camera_position).looking_at(marker_position, Vector3.UP)
	var rotation: Quaternion = look_transform.basis.get_rotation_quaternion()
	var euler: Vector3 = rotation.get_euler()
	euler.x += deg_to_rad(pitch_offset)
	euler.y += deg_to_rad(yaw_offset)
	return Quaternion.from_euler(euler)

static func cubic_in_out(progress: float) -> float:
	var t: float = clampf(progress, 0.0, 1.0)
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5

static func sample_rotation(from: Quaternion, to: Quaternion, progress: float) -> Quaternion:
	return from.slerp(to, cubic_in_out(progress))
