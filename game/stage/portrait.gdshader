shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, alpha_to_coverage;

uniform sampler2D portrait_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float brightness = 1.0;
uniform bool clip_floor = false;
varying float world_height;

void vertex() {
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (clip_floor && world_height < 0.12) {
		discard;
	}
	vec4 image = texture(portrait_texture, UV);
	// 立牌背面是纯黑剪影，不放正面的图案。
	ALBEDO = FRONT_FACING ? image.rgb * tint.rgb * brightness : vec3(0.004, 0.006, 0.010);
	ALPHA = image.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
