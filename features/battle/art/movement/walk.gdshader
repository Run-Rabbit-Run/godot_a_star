shader_type canvas_item;
render_mode unshaded;

uniform float phase = 0.0;
uniform float strength = 0.0;
uniform float stride = 0.012;
uniform float leg_start = 0.65;
uniform float leg_split = 0.5;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// A restrained cutout gait; phase comes from travelled distance, never wall time.
void fragment() {
	vec2 uv = UV;
	float legs = smoothstep(leg_start, 0.96, uv.y);
	float side = mix(-1.0, 1.0, smoothstep(leg_split - 0.04, leg_split + 0.04, uv.x));
	uv.x -= sin(phase) * side * legs * stride * strength;
	uv.y += max(0.0, sin(phase) * side) * legs * stride * strength;
	vec4 painted = texture(TEXTURE, uv);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	COLOR = painted * tint;
	COLOR.a *= inside;
}
