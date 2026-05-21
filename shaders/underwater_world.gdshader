shader_type sky;

uniform vec4 sky_top_color : source_color = vec4(0.01, 0.08, 0.10, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.02, 0.18, 0.20, 1.0);
uniform float fog_density : hint_range(0.0, 1.0) = 0.85;
uniform float time_scale : hint_range(0.0, 2.0) = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	float horizon = clamp(1.0 - abs(EYEDIR.y) * 2.5, 0.0, 1.0);
	vec4 base = mix(sky_top_color, sky_horizon_color, horizon);

	vec2 uv = EYEDIR.xz / (abs(EYEDIR.y) + 0.1);
	float t = TIME * time_scale;

	float n1 = noise(uv * 1.5 + vec2(t * 0.4, t * 0.2));
	float n2 = noise(uv * 3.0 - vec2(t * 0.3, t * 0.5));
	float n3 = noise(uv * 6.0 + vec2(t * 0.1, t * 0.6));
	float caustic = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2);

	vec3 caustic_color = vec3(0.0, 0.5, 0.55) * caustic * 0.15 * (1.0 - fog_density);
	vec3 final_color = base.rgb + caustic_color;
	final_color = mix(final_color, sky_horizon_color.rgb, horizon * fog_density);

	COLOR = final_color;
}
