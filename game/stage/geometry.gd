extends RefCounted

# 通用 3D 形状与材质工具。所有公共材质只创建一次并复用，
# 避免 set_night / set_pods_closed 每帧采样时反复 new 材质。

const StageParams = preload("res://config/stage_params.gd")

static var _materials: Dictionary = {}

static func material(key: StringName) -> StandardMaterial3D:
	var cached: Variant = _materials.get(key, null)
	if cached is StandardMaterial3D:
		return cached as StandardMaterial3D
	var created: StandardMaterial3D = _create_material(key)
	_materials[key] = created
	return created

static func make_metal(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	# Compatibility 无环境反射贴图时，过高金属度会使舱内近乎全黑。
	# 压低上限，让环境光更多地落成漫反射，白天更可读。
	mat.metallic = minf(metallic, 0.25)
	mat.roughness = roughness
	return mat

static func make_emissive(color: Color, energy: float) -> StandardMaterial3D:
	# 舞台不做材质自发光：亮度只来自真实灯光，避免桌面/灯带自己发亮。
	# 颜色仍写进 albedo，开灯时能正常被照亮；energy 参数仅为兼容旧调用保留。
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.55)
	mat.metallic = 0.10
	mat.roughness = 0.62
	mat.emission_enabled = false
	mat.emission = color
	mat.emission_energy_multiplier = 0.0
	return mat

static func _create_material(key: StringName) -> StandardMaterial3D:
	match key:
		&"metal_dark":
			return make_metal(StageParams.COLOR_METAL_DARK, 0.86, 0.36)
		&"metal_mid":
			return make_metal(StageParams.COLOR_METAL_MID, 0.80, 0.62)
		&"metal_light":
			return make_metal(StageParams.COLOR_METAL_LIGHT, 0.72, 0.62)
		# 讲台顶面单独用暗哑材质，避免被席位色灯照成一条发亮的光带。
		&"podium_top":
			return make_metal(StageParams.COLOR_METAL_MID, 0.20, 0.72)
		&"floor":
			return make_metal(StageParams.COLOR_FLOOR, 0.55, 0.72)
		&"table":
			return make_metal(StageParams.COLOR_TABLE, 0.78, 0.78)
		&"glass":
			return make_metal(StageParams.COLOR_GLASS, 0.15, 0.38)
		&"panel":
			return make_metal(StageParams.COLOR_PANEL, 0.06, 0.62)
		&"panel_dark":
			return make_metal(StageParams.COLOR_PANEL_DARK, 0.05, 0.68)
		&"trim":
			return make_metal(StageParams.COLOR_TRIM, 0.12, 0.34)
		&"canopy":
			var canopy_mat: StandardMaterial3D = make_metal(StageParams.COLOR_PANEL_DARK, 0.05, 0.68)
			canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			return canopy_mat
		&"glow_public":
			return make_emissive(StageParams.COLOR_PUBLIC, 0.90)
		&"glow_room":
			return make_emissive(StageParams.COLOR_PUBLIC, StageParams.ROOM_GLOW_DAY)
		&"glow_cold":
			return make_emissive(StageParams.COLOR_LOCK, 0.80)
	return make_metal(StageParams.COLOR_METAL_MID, 0.70, 0.50)

static func set_emission(mat: StandardMaterial3D, energy: float) -> void:
	if mat != null:
		mat.emission_energy_multiplier = energy

# 平面为梯形的挤出体：z0/z1 两端半宽 half0/half1，厚度 height（Y 向）。
# 用于闭合顶罩的前段收窄，避免方形罩体压到邻舱。
static func add_trapezoid(parent: Node3D, node_name: String, z0: float, z1: float, half0: float, half1: float, height: float, pos_y: float, mat: Material) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = height * 0.5
	var b00: Vector3 = Vector3(-half0, -h, z0)
	var b10: Vector3 = Vector3(half0, -h, z0)
	var b01: Vector3 = Vector3(-half1, -h, z1)
	var b11: Vector3 = Vector3(half1, -h, z1)
	var t00: Vector3 = Vector3(-half0, h, z0)
	var t10: Vector3 = Vector3(half0, h, z0)
	var t01: Vector3 = Vector3(-half1, h, z1)
	var t11: Vector3 = Vector3(half1, h, z1)
	var left_n: Vector3 = Vector3(-(z1 - z0), 0.0, half0 - half1).normalized()
	var right_n: Vector3 = Vector3(z1 - z0, 0.0, half1 - half0).normalized()
	_add_quad(st, b00, b10, b11, b01, Vector3.DOWN)
	_add_quad(st, t00, t10, t11, t01, Vector3.UP)
	_add_quad(st, b00, b01, t01, t00, left_n)
	_add_quad(st, b10, b11, t11, t10, right_n)
	_add_quad(st, b00, b10, t10, t00, Vector3.FORWARD)
	_add_quad(st, b01, b11, t11, t01, Vector3.BACK)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = st.commit()
	instance.material_override = mat
	instance.position = Vector3(0.0, pos_y, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(d)

static func add_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, cast_shadow: bool = true) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	instance.rotation_degrees = rot_deg
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func add_cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, pos: Vector3, mat: Material, radial_segments: int = 32, cast_shadow: bool = true, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	instance.rotation_degrees = rot_deg
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func add_torus(parent: Node3D, node_name: String, inner_radius: float, outer_radius: float, pos: Vector3, mat: Material, rings: int = 48, ring_segments: int = 10, cast_shadow: bool = false) -> MeshInstance3D:
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = rings
	mesh.ring_segments = ring_segments
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func add_sphere(parent: Node3D, node_name: String, radius: float, pos: Vector3, mat: Material, radial_segments: int = 16, rings: int = 8, cast_shadow: bool = false) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
