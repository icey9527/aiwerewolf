shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// 七段数码管：暗底面板 + 未点亮的暗段 + 点亮的数字段。
uniform vec4 lit_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform vec4 dim_color : source_color = vec4(0.022, 0.032, 0.048, 1.0);
uniform vec4 panel_color : source_color = vec4(0.006, 0.010, 0.016, 1.0);
uniform vec4 edge_color : source_color = vec4(0.06, 0.11, 0.19, 1.0);
uniform int value = 1;
uniform float intensity = 1.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float box_mask(vec2 p, vec2 half_size) {
	float r = min(half_size.x, half_size.y) * 0.9;
	float d = sd_round_box(p, half_size, r);
	return 1.0 - smoothstep(-0.0025, 0.0025, d);
}

int digit_mask(int d) {
	if (d == 0) { return 63; }
	if (d == 1) { return 6; }
	if (d == 2) { return 91; }
	if (d == 3) { return 93; }
	if (d == 4) { return 102; }
	if (d == 5) { return 109; }
	if (d == 6) { return 125; }
	if (d == 7) { return 7; }
	if (d == 8) { return 127; }
	if (d == 9) { return 111; }
	return 0;
}

float segment(vec2 p, vec2 center, vec2 half_size, int mask, int bit) {
	float shape = box_mask(p - center, half_size);
	float on = float((mask & bit) != 0 ? 1.0 : 0.0);
	return shape * on;
}

float digit_lit(vec2 uv, int d) {
	int m = digit_mask(d);
	float v = 0.0;
	v = max(v, segment(uv, vec2(0.50, 0.94), vec2(0.34, 0.045), m, 1));
	v = max(v, segment(uv, vec2(0.94, 0.72), vec2(0.045, 0.19), m, 2));
	v = max(v, segment(uv, vec2(0.94, 0.28), vec2(0.045, 0.19), m, 4));
	v = max(v, segment(uv, vec2(0.50, 0.06), vec2(0.34, 0.045), m, 8));
	v = max(v, segment(uv, vec2(0.06, 0.28), vec2(0.045, 0.19), m, 16));
	v = max(v, segment(uv, vec2(0.06, 0.72), vec2(0.045, 0.19), m, 32));
	v = max(v, segment(uv, vec2(0.50, 0.50), vec2(0.34, 0.045), m, 64));
	return v;
}

float digit_ghost(vec2 uv) {
	float v = 0.0;
	v = max(v, box_mask(uv - vec2(0.50, 0.94), vec2(0.34, 0.045)));
	v = max(v, box_mask(uv - vec2(0.94, 0.72), vec2(0.045, 0.19)));
	v = max(v, box_mask(uv - vec2(0.94, 0.28), vec2(0.045, 0.19)));
	v = max(v, box_mask(uv - vec2(0.50, 0.06), vec2(0.34, 0.045)));
	v = max(v, box_mask(uv - vec2(0.06, 0.28), vec2(0.045, 0.19)));
	v = max(v, box_mask(uv - vec2(0.06, 0.72), vec2(0.045, 0.19)));
	v = max(v, box_mask(uv - vec2(0.50, 0.50), vec2(0.34, 0.045)));
	return v;
}

void fragment() {
	// 从背面看时水平镜像 UV，保证任何一侧读到的数字都不是反的。
	vec2 uv = FRONT_FACING ? UV : vec2(1.0 - UV.x, UV.y);
	vec2 p = uv - vec2(0.5);
	float panel = 1.0 - smoothstep(-0.0025, 0.0025, sd_round_box(p, vec2(0.5, 0.5), 0.07));
	if (panel < 0.5) {
		discard;
	}
	// 数码管固定两位，个位补零（01、02…），和文字里的「1号」区分开。
	bool left = uv.x < 0.5;
	int digit = left ? value / 10 : value % 10;
	vec2 cell = vec2((uv.x - (left ? 0.02 : 0.52)) / 0.46, (uv.y - 0.08) / 0.84);
	float lit = digit_lit(cell, digit);
	float ghost = digit_ghost(cell);
	vec3 color = mix(panel_color.rgb, dim_color.rgb, ghost * 0.55);
	color = mix(color, lit_color.rgb * 1.8 * intensity, lit);
	float border = 1.0 - smoothstep(0.0, 0.012, sd_round_box(p, vec2(0.485, 0.485), 0.065));
	color = mix(color, edge_color.rgb, border * 0.85);
	ALBEDO = color;
}
