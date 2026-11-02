extends Node3D

# 猎人开枪：细核心光柱 + 外层辉光 + 枪口/命中火花 + 命中闪光。
# 全部由绝对进度驱动，只在开枪窗口内出现，seek 可重复得到同一画面。
var beam: MeshInstance3D
var glow: MeshInstance3D
var muzzle: MeshInstance3D
var flash: MeshInstance3D
var light: OmniLight3D
var muzzle_sparks: CPUParticles3D
var hit_sparks: CPUParticles3D
var was_firing: bool = false

func _ready() -> void:
	var core := _additive(Color(1.0, 0.86, 0.56, 0.9), 1.1)
	beam = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = 1.0
	beam.mesh = cylinder
	beam.material_override = core
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	glow = MeshInstance3D.new()
	var wide := CylinderMesh.new()
	wide.top_radius = 0.045
	wide.bottom_radius = 0.045
	wide.height = 1.0
	glow.mesh = wide
	glow.material_override = _additive(Color(1.0, 0.70, 0.30, 0.10), 0.8)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	var ball := SphereMesh.new()
	ball.radius = 0.055
	ball.height = 0.11
	muzzle = MeshInstance3D.new()
	muzzle.mesh = ball
	muzzle.material_override = core
	add_child(muzzle)
	flash = MeshInstance3D.new()
	var burst := SphereMesh.new()
	burst.radius = 0.18
	burst.height = 0.36
	flash.mesh = burst
	flash.material_override = _additive(Color(1.0, 0.88, 0.62, 0.25), 1.2)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	light = OmniLight3D.new()
	light.light_color = Color("ffce80")
	light.omni_range = 5.0
	add_child(light)
	muzzle_sparks = _make_sparks(28, Color("ffe7b0"))
	add_child(muzzle_sparks)
	hit_sparks = _make_sparks(46, Color("ffc06a"))
	add_child(hit_sparks)
	for node in [beam, glow, muzzle, flash, light]:
		node.visible = false

func _additive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	return material

func _make_sparks(amount: int, color: Color) -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = amount
	sparks.lifetime = 0.45
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.spread = 42.0
	sparks.initial_velocity_min = 2.2
	sparks.initial_velocity_max = 5.6
	sparks.gravity = Vector3(0, -6.0, 0)
	sparks.scale_amount_min = 0.015
	sparks.scale_amount_max = 0.045
	sparks.color = color
	sparks.emitting = false
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sparks

func _orient(node: Node3D, from: Vector3, to: Vector3) -> void:
	var direction: Vector3 = to - from
	var up_axis: Vector3 = direction.normalized()
	var right_axis: Vector3 = up_axis.cross(Vector3.UP).normalized()
	if right_axis.length_squared() < 0.1:
		right_axis = Vector3.RIGHT
	node.basis = Basis(right_axis, up_axis, right_axis.cross(up_axis).normalized())
	node.position = (from + to) * 0.5
	node.scale = Vector3(1, direction.length(), 1)

func sample(active: bool, progress: float, from: Vector3, to: Vector3) -> void:
	var pulse: float = clampf(1.0 - absf(progress - 0.45) / 0.055, 0.0, 1.0)
	var firing: bool = active and pulse > 0.0
	for node in [beam, glow, muzzle, flash, light]:
		node.visible = firing
	if firing:
		_orient(beam, from, to)
		_orient(glow, from, to)
		glow.scale = beam.scale * Vector3(1.0 + pulse * 0.4, 1.0, 1.0 + pulse * 0.4)
		muzzle.position = from
		muzzle.scale = Vector3.ONE * (0.6 + pulse * 0.6)
		flash.position = to
		flash.scale = Vector3.ONE * (0.4 + pulse * 1.0)
		light.position = from
		light.light_energy = pulse * 4.5
		muzzle_sparks.position = from
		muzzle_sparks.direction = (to - from).normalized()
		hit_sparks.position = to
		hit_sparks.direction = (from - to).normalized()
		if not was_firing:
			muzzle_sparks.restart()
			hit_sparks.restart()
			muzzle_sparks.emitting = true
			hit_sparks.emitting = true
	was_firing = firing
