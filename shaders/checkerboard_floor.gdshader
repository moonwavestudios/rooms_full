shader_type spatial;

uniform vec4 tile_color_a : source_color = vec4(0.0, 0.85, 0.90, 1.0);
uniform vec4 tile_color_b : source_color = vec4(0.02, 0.02, 0.04, 1.0);
uniform float tile_size : hint_range(0.1, 10.0) = 1.0;
uniform float emission_strength : hint_range(0.0, 5.0) = 1.8;
uniform float roughness_a : hint_range(0.0, 1.0) = 0.15;
uniform float roughness_b : hint_range(0.0, 1.0) = 0.9;
uniform float wetness : hint_range(0.0, 1.0) = 0.6;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.25;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.4;

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

float caustics(vec2 uv, float t) {
	float n1 = noise(uv * 2.0 + vec2(t * 0.5, t * 0.3));
	float n2 = noise(uv * 4.0 - vec2(t * 0.4, t * 0.6));
	float n3 = noise(uv * 8.0 + vec2(t * 0.2, t * 0.7));
	return n1 * 0.5 + n2 * 0.3 + n3 * 0.2;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_uv = world_pos.xz / tile_size;
	vec2 tile = floor(world_uv);
	float checker = mod(tile.x + tile.y, 2.0);

	float t = TIME * caustic_speed;
	float caustic_val = caustics(world_uv * 0.5, t);

	vec4 base_color = mix(tile_color_b, tile_color_a, checker);

	vec3 glow = tile_color_a.rgb * caustic_val * caustic_strength;
	base_color.rgb += glow;

	vec3 worn = vec3(noise(world_uv * 3.7 + 5.3)) * 0.08;
	base_color.rgb = clamp(base_color.rgb - worn * (1.0 - checker * 0.5), 0.0, 1.0);

	ALBEDO = base_color.rgb;

	float emit_mask = checker * (caustic_val * 0.4 + 0.6);
	EMISSION = tile_color_a.rgb * emit_mask * emission_strength;

	ROUGHNESS = mix(roughness_b, roughness_a, checker);
	METALLIC = mix(0.0, wetness, checker);
	SPECULAR = mix(0.1, 0.8, checker);
}
