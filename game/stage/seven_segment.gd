extends RefCounted

# 七段数码管面板：一个 QuadMesh + 一个 shader，改 value/颜色即可复用。
const SegShader = preload("res://stage/seven_seg.gdshader")

static func make_material(value: int, color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SegShader
	material.set_shader_parameter("value", value)
	material.set_shader_parameter("lit_color", color)
	return material

static func make_panel(material: ShaderMaterial, size: Vector2) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var panel := MeshInstance3D.new()
	panel.mesh = quad
	panel.material_override = material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return panel
