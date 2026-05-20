shader_type spatial;

uniform vec4 stone_light : source_color = vec4(0.35, 0.75, 0.72, 1.0);
uniform vec4 stone_dark : source_color = vec4(0.04, 0.14, 0.16, 1.0);
uniform vec4 grout_color : source_color = vec4(0.02, 0.08, 0.10, 1.0);
uniform float tile_size : hint_range(0.1, 10.0) = 1.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.7;
uniform float wetness : hint_range(0.0, 1.0) = 0.55;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.18;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.35;
uniform float grout_width : hint_range(0.0, 0.5) = 0.07;
uniform float teal_shift : hint_range(0.0, 1.0) = 0.6;

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
	for (int i = 0; i < 4; i++) {
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

vec2 brick_uv(vec2 world_xz, float bw, float bh, float offset) {
	float row = floor(world_xz.y / bh);
	float shift = mod(row, 2.0) * offset;
	float col = floor((world_xz.x + shift) / bw);
	vec2 local = vec2(
		fract((world_xz.x + shift) / bw),
		fract(world_xz.y / bh)
	);
	return local;
}

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float bw = tile_size * 2.0;
	float bh = tile_size;

	vec2 xz = world_pos.xz;
	vec2 xy = world_pos.xy;
	vec2 zy = world_pos.zy;

	vec3 blend = abs(world_normal);
	blend = pow(blend, vec3(4.0));
	blend /= blend.x + blend.y + blend.z + 0.001;

	vec2 local_xz = brick_uv(xz / tile_size, 2.0, 1.0, 0.5);
	vec2 local_xy = brick_uv(xy / tile_size, 2.0, 1.0, 0.5);
	vec2 local_zy = brick_uv(zy / tile_size, 2.0, 1.0, 0.5);

	float grout_xz = step(1.0 - grout_width, local_xz.x) + step(1.0 - grout_width, local_xz.y);
	float grout_xy = step(1.0 - grout_width, local_xy.x) + step(1.0 - grout_width, local_xy.y);
	float grout_zy = step(1.0 - grout_width, local_zy.x) + step(1.0 - grout_width, local_zy.y);
	float grout = clamp(
		grout_xz * blend.y + grout_xy * blend.z + grout_zy * blend.x,
		0.0, 1.0
	);

	float stone_xz = fbm(xz / tile_size * 3.5 + 7.3);
	float stone_xy = fbm(xy / tile_size * 3.5 + 2.1);
	float stone_zy = fbm(zy / tile_size * 3.5 + 4.7);
	float stone_detail = stone_xz * blend.y + stone_xy * blend.z + stone_zy * blend.x;

	vec3 base = mix(stone_dark.rgb, stone_light.rgb, stone_detail);
	base = mix(base, grout_color.rgb, grout);

	float t = TIME * caustic_speed;
	float caustic_val = caustics(xz / tile_size * 0.5, t);
	vec3 teal = vec3(0.1, 0.9, 0.85);
	base += teal * caustic_val * caustic_strength * (1.0 - grout);

	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(base, mix(vec3(lum), teal, 0.5) * (lum + 0.1), teal_shift * 0.4);

	ALBEDO = clamp(base, 0.0, 1.0);
	ROUGHNESS = mix(roughness_base, roughness_base * 0.3, wetness * (1.0 - grout));
	METALLIC = 0.0;
	SPECULAR = mix(0.1, 0.7, wetness * (1.0 - grout));
}
