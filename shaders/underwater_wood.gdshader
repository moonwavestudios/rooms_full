shader_type spatial;

uniform vec4 wood_base_color : source_color = vec4(0.04, 0.10, 0.12, 1.0);
uniform vec4 wood_grain_color : source_color = vec4(0.02, 0.06, 0.08, 1.0);
uniform vec4 teal_tint : source_color = vec4(0.08, 0.35, 0.38, 1.0);
uniform float tile_size : hint_range(0.1, 10.0) = 1.0;
uniform float plank_width : hint_range(0.1, 4.0) = 0.5;
uniform float grain_scale : hint_range(1.0, 20.0) = 8.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float wetness : hint_range(0.0, 1.0) = 0.7;
uniform float teal_strength : hint_range(0.0, 1.0) = 0.45;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.08;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.35;
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

float caustics(vec2 uv, float t) {
	float n1 = noise(uv * 2.0 + vec2(t * 0.5, t * 0.3));
	float n2 = noise(uv * 4.0 - vec2(t * 0.4, t * 0.6));
	float n3 = noise(uv * 8.0 + vec2(t * 0.2, t * 0.7));
	return n1 * 0.5 + n2 * 0.3 + n3 * 0.2;
}

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 blend = abs(world_normal);
	blend = pow(blend, vec3(4.0));
	blend /= blend.x + blend.y + blend.z + 0.001;

	float plank_xz = floor(world_pos.x / (plank_width * tile_size));
	float plank_zy = floor(world_pos.z / (plank_width * tile_size));
	float plank_xy = floor(world_pos.x / (plank_width * tile_size));

	float rand_xz = hash1(plank_xz * 7.3 + 2.1);
	float rand_zy = hash1(plank_zy * 5.7 + 8.4);
	float rand_xy = hash1(plank_xy * 3.9 + 6.2);

	vec2 grain_uv_xz = vec2(world_pos.x / tile_size * grain_scale + rand_xz * 10.0, world_pos.z / tile_size);
	vec2 grain_uv_zy = vec2(world_pos.z / tile_size * grain_scale + rand_zy * 10.0, world_pos.y / tile_size);
	vec2 grain_uv_xy = vec2(world_pos.x / tile_size * grain_scale + rand_xy * 10.0, world_pos.y / tile_size);

	float grain_xz = fbm(grain_uv_xz);
	float grain_zy = fbm(grain_uv_zy);
	float grain_xy = fbm(grain_uv_xy);
	float grain = grain_xz * blend.y + grain_zy * blend.x + grain_xy * blend.z;

	float local_x_xz = fract(world_pos.x / (plank_width * tile_size));
	float local_x_zy = fract(world_pos.z / (plank_width * tile_size));
	float edge_xz = smoothstep(0.0, 0.08, local_x_xz) * smoothstep(1.0, 0.92, local_x_xz);
	float edge_zy = smoothstep(0.0, 0.08, local_x_zy) * smoothstep(1.0, 0.92, local_x_zy);
	float edge_mask = edge_xz * blend.y + edge_zy * blend.x;

	float knot_xz = smoothstep(0.08, 0.0, length(fract(vec2(world_pos.x, world_pos.z) / (tile_size * 3.0) + rand_xz) - 0.5));
	float knot_zy = smoothstep(0.08, 0.0, length(fract(vec2(world_pos.z, world_pos.y) / (tile_size * 3.0) + rand_zy) - 0.5));
	float knots = clamp(knot_xz * blend.y + knot_zy * blend.x, 0.0, 1.0);

	vec3 base = mix(wood_grain_color.rgb, wood_base_color.rgb, grain);
	base = mix(base, base * (1.0 - edge_darkness * 0.5), 1.0 - edge_mask);
	base = mix(base, wood_grain_color.rgb * 0.3, knots);

	float t = TIME * caustic_speed;
	float caustic_val = caustics(world_pos.xz / tile_size * 0.4, t);
	base += teal_tint.rgb * caustic_val * caustic_strength;

	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 teal = teal_tint.rgb;
	base = mix(base, teal * (lum * 1.5 + 0.05), teal_strength);

	float wet_mask = edge_mask * (1.0 - knots);

	ALBEDO = clamp(base, 0.0, 1.0);
	ROUGHNESS = mix(roughness_base, roughness_base * 0.25, wetness * wet_mask);
	METALLIC = 0.0;
	SPECULAR = mix(0.05, 0.6, wetness * wet_mask);
}
