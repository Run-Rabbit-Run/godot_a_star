shader_type canvas_item;
render_mode unshaded;
varying vec4 instance_tint;

void vertex() {
	instance_tint = COLOR;
}

// Keep bodies readable without competing with living units or tactical highlights.
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float value = dot(texel.rgb, vec3(0.299, 0.587, 0.114));
	vec3 muted = mix(texel.rgb, vec3(value), 0.70);
	muted = (muted - vec3(0.38)) * 0.72 + vec3(0.32);
	COLOR = instance_tint * vec4(muted * vec3(1.0, 0.96, 0.89), texel.a * 0.88);
}
