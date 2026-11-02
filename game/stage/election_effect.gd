extends Node3D

const RING_RADIUS := 1.15
const PILLAR_RADIUS := 0.92

var _seat_count := 0
var _groups: Array[Node3D] = []
var _rings: Array = []
var _pillars: Array = []
var _gold: StandardMaterial3D
var _cold: StandardMaterial3D
var _ring_mesh: TorusMesh
var _pillar_mesh: CylinderMesh

func _ready() -> void:
	top_level = true
	transform = Transform3D.IDENTITY
	_ensure_resources()
	visible = false

func build(count: int) -> void:
	count = maxi(count, 0)
	if count == _seat_count and _groups.size() == count:
		return
	_ensure_resources()
	for group in _groups:
		remove_child(group)
		group.queue_free()
	_groups.clear()
	_rings.clear()
	_pillars.clear()
	_seat_count = count
	for i in range(count):
		var group := Node3D.new()
		group.name = "Seat%d" % i
		group.visible = false
		add_child(group)
		_groups.append(group)

		var rings: Array[MeshInstance3D] = []
		for r in range(2):
			var ring := MeshInstance3D.new()
			ring.mesh = _ring_mesh
			ring.material_override = _gold if r == 0 else _cold
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.visible = false
			group.add_child(ring)
			rings.append(ring)
		_rings.append(rings)

		var pillars: Array[MeshInstance3D] = []
		for p in range(4):
			var pillar := MeshInstance3D.new()
			pillar.mesh = _pillar_mesh
			pillar.material_override = _gold
			pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pillar.visible = false
			var angle := PI * 0.25 + float(p) * PI * 0.5
			pillar.position = Vector3(cos(angle) * PILLAR_RADIUS, 0.0, sin(angle) * PILLAR_RADIUS)
			group.add_child(pillar)
			pillars.append(pillar)
		_pillars.append(pillars)
	visible = false

func sample(transforms: Array[Transform3D], heights: Array, active: bool, progress: float, withdrawing: bool) -> void:
	if not active:
		visible = false
		return
	visible = true
	var t := clampf(progress, 0.0, 1.0)
	var travel: float = (0.36 * t) if not withdrawing else (0.36 * (1.0 - t))
	
	for i in range(_groups.size()):
		var group: Node3D = _groups[i]
		if i >= transforms.size() or i >= heights.size() or float(heights[i]) <= 0.0:
			group.visible = false
			continue
		group.visible = true
		group.transform = transforms[i]

		var rings: Array = _rings[i]
		var grow: float = 1.0 + sin(t * PI) * 0.04
		grow = maxf(grow, 0.5)
		for r in range(rings.size()):
			var ring: MeshInstance3D = rings[r]
			ring.visible = true
			ring.scale = Vector3(grow, grow, grow)
			# 光环约束在升降地台附近，像机构的能量密封圈。
			ring.position = Vector3(0.0, -0.12 + float(r) * 0.12 + travel * 0.15, 0.0)

		var pillars: Array = _pillars[i]
		for p in range(pillars.size()):
			var pillar: MeshInstance3D = pillars[p]
			# 用垂直能量导轨连接升起地台与地面，替代悬空烟花式光柱。
			var ph: float = maxf(float(heights[i]) * 1.6, 0.02)
			pillar.visible = ph > 0.03
			pillar.scale = Vector3(1.0, ph, 1.0)
			pillar.position.y = -ph * 0.5

func _ensure_resources() -> void:
	if _gold == null:
		_gold = _make_material(Color("e8b455"))
		_cold = _make_material(Color("dbe9ff"))
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = RING_RADIUS - 0.02
		_ring_mesh.outer_radius = RING_RADIUS + 0.02
		_ring_mesh.rings = 12
		_ring_mesh.ring_segments = 64
	if _pillar_mesh == null:
		_pillar_mesh = CylinderMesh.new()
		_pillar_mesh.top_radius = 0.014
		_pillar_mesh.bottom_radius = 0.014
		_pillar_mesh.height = 1.0
		_pillar_mesh.radial_segments = 8
		_pillar_mesh.rings = 1

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.darkened(0.22)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.15
	material.metallic = 0.0
	material.roughness = 1.0
	return material
