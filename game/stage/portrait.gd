extends Node3D

const Params = preload("res://config/camera_params.gd")
const Catalog = preload("res://resources/character_catalog.gd")
const PortraitShader = preload("res://stage/portrait.gdshader")
var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var current_pose: int = -1
var character: String

func build(seat: int) -> void:
	Catalog.prepare()
	character = Catalog.character_id(seat)
	mesh_instance = MeshInstance3D.new()
	material = ShaderMaterial.new()
	material.shader = PortraitShader
	mesh_instance.material_override = material
	add_child(mesh_instance)
	set_pose(0)

func set_lighting(brightness: float, clip_floor: bool) -> void:
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("clip_floor", clip_floor)

func set_pose(pose: int) -> void:
	var key: int = Catalog.resolve_state(character, pose)
	if key == current_pose:
		return
	current_pose = key
	var texture: Texture2D = Catalog.texture(character, key)
	if texture == null:
		push_error("立绘资源未加载：%s / %d" % [character, key])
		return
	# 复用同一个 QuadMesh，只改尺寸，避免每次换表情都新建网格资源造成瞬时卡顿。
	var quad: QuadMesh
	if mesh_instance.mesh is QuadMesh:
		quad = mesh_instance.mesh as QuadMesh
	else:
		quad = QuadMesh.new()
		mesh_instance.mesh = quad
	quad.size = Vector2(Params.PORTRAIT_HEIGHT * float(texture.get_width()) / float(texture.get_height()), Params.PORTRAIT_HEIGHT)
	mesh_instance.position.y = Params.FOOT_HEIGHT + Params.PORTRAIT_HEIGHT * 0.5
	material.set_shader_parameter("portrait_texture", texture)
