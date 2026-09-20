shader_type canvas_item;

uniform vec4 rim_color : source_color = vec4(0.075, 0.082, 0.075, 0.74);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 radius = TEXTURE_PIXEL_SIZE * 15.0;
	float nearby_alpha = 0.0;
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(radius.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-radius.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(0.0, radius.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(0.0, -radius.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + radius).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - radius).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(radius.x, -radius.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-radius.x, radius.y)).a);

	float rim_alpha = max(nearby_alpha - source.a, 0.0) * rim_color.a;
	vec3 lit_color = clamp(source.rgb * 1.10 + vec3(0.018, 0.017, 0.014), 0.0, 1.0);
	COLOR = vec4(mix(rim_color.rgb, lit_color, source.a), max(source.a, rim_alpha));
}