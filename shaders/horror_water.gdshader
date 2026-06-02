shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_map_a : hint_normal, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, repeat_enable;
uniform sampler2D foam_texture : hint_default_white, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform vec4 deep_color : source_color = vec4(0.01, 0.03, 0.04, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.04, 0.07, 0.06, 1.0);
uniform vec4 foam_color : source_color = vec4(0.55, 0.58, 0.55, 1.0);
uniform vec4 subsurface_color : source_color = vec4(0.02, 0.06, 0.05, 1.0);

uniform float wave_speed : hint_range(0.0, 2.0) = 0.18;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.38;
uniform float wave_scale_a : hint_range(0.1, 10.0) = 1.6;
uniform float wave_scale_b : hint_range(0.1, 10.0) = 3.2;

uniform float depth_fade_distance : hint_range(0.1, 10.0) = 2.8;
uniform float refraction_strength : hint_range(0.0, 0.5) = 0.055;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.72;

uniform float foam_threshold : hint_range(0.0, 1.0) = 0.18;
uniform float foam_softness : hint_range(0.01, 1.0) = 0.12;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.08;

uniform float blood_tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 blood_color : source_color = vec4(0.18, 0.01, 0.01, 1.0);
uniform float oil_slick_strength : hint_range(0.0, 1.0) = 0.22;
uniform float darkness_vignette : hint_range(0.0, 1.0) = 0.65;

uniform float gust_frequency : hint_range(0.0, 5.0) = 0.55;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.28;

varying vec3 world_pos;
varying float wave_height;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.13;
	}
	return value;
}

vec3 oil_slick_iridescence(vec3 view_dir, vec3 normal, float time) {
	float fresnel = pow(1.0 - clamp(dot(view_dir, normal), 0.0, 1.0), 3.0);
	float phase = fbm(view_dir.xz * 3.0 + time * 0.05) * 6.283;
	vec3 irid;
	irid.r = 0.5 + 0.5 * sin(phase);
	irid.g = 0.5 + 0.5 * sin(phase + 2.094);
	irid.b = 0.5 + 0.5 * sin(phase + 4.189);
	irid = mix(vec3(0.0), irid * vec3(0.3, 0.5, 0.4), fresnel * oil_slick_strength);
	return irid;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float t = TIME * wave_speed;
	vec2 wp = world_pos.xz;

	float gust = sin(TIME * gust_frequency) * 0.5 + 0.5;
	float disturb = fbm(wp * 0.3 + t * 0.5) * gust * gust_strength;

	float w1 = sin(wp.x * 1.1 + t * 1.3) * cos(wp.y * 0.9 + t * 0.8);
	float w2 = sin(wp.x * 2.3 - t * 0.7) * sin(wp.y * 1.8 + t * 1.1);
	float w3 = fbm(wp * 0.6 + t * 0.4);

	wave_height = (w1 * 0.4 + w2 * 0.35 + w3 * 0.25 + disturb) * wave_strength;
	VERTEX.y += wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 uv_a = world_pos.xz * wave_scale_a * 0.1;
	vec2 uv_b = world_pos.xz * wave_scale_b * 0.1;

	float gust = sin(TIME * gust_frequency * 0.7) * 0.5 + 0.5;
	vec2 flow_a = vec2(t * 0.8 + gust * 0.15, t * 0.5);
	vec2 flow_b = vec2(-t * 0.6 + gust * 0.1, t * 0.9);

	vec3 n_a = texture(normal_map_a, uv_a + flow_a).xyz * 2.0 - 1.0;
	vec3 n_b = texture(normal_map_b, uv_b + flow_b).xyz * 2.0 - 1.0;
	vec3 blended_normal = normalize(n_a + n_b);
	blended_normal.xy *= wave_strength * 1.4;

	vec2 screen_uv = SCREEN_UV;
	screen_uv += blended_normal.xy * refraction_strength;
	screen_uv = clamp(screen_uv, vec2(0.001), vec2(0.999));

	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_coords = INV_PROJECTION_MATRIX * ndc;
	view_coords.xyz /= view_coords.w;
	float scene_depth = -view_coords.z;

	float frag_depth = -VERTEX.z;
	float depth_diff = clamp((scene_depth - frag_depth) / depth_fade_distance, 0.0, 1.0);

	vec3 deep = mix(deep_color.rgb, blood_color.rgb, blood_tint_strength * 0.6);
	vec3 shallow = mix(shallow_color.rgb, blood_color.rgb, blood_tint_strength * 0.3);
	vec3 water_color = mix(shallow, deep, depth_diff);

	float noise_val = fbm(world_pos.xz * 2.0 + TIME * 0.12);
	water_color -= noise_val * 0.015;
	water_color = clamp(water_color, vec3(0.0), vec3(1.0));

	float foam_depth = clamp(1.0 - (depth_diff / foam_threshold), 0.0, 1.0);
	float foam_noise = fbm(world_pos.xz * 4.0 + TIME * foam_speed);
	float foam_mask = smoothstep(0.0, foam_softness, foam_depth - foam_noise * 0.4);
	foam_mask *= smoothstep(foam_threshold, 0.0, depth_diff);

	float view_fresnel_raw = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - view_fresnel_raw, 4.0);

	vec3 refracted = texture(screen_texture, screen_uv).rgb;
	vec3 base_color = mix(refracted * water_color * 0.85, water_color, depth_diff * 0.7);

	vec3 oil = oil_slick_iridescence(VIEW, blended_normal, TIME);
	base_color += oil;

	float subsurface = pow(clamp(1.0 - depth_diff, 0.0, 1.0), 2.0) * 0.4;
	base_color += subsurface_color.rgb * subsurface;

	float dark_patch = fbm(world_pos.xz * 0.5 - TIME * 0.04);
	base_color = mix(base_color, base_color * 0.3, dark_patch * darkness_vignette * 0.5);

	base_color = mix(base_color, foam_color.rgb, foam_mask * 0.7);

	ALBEDO = base_color;
	ROUGHNESS = mix(roughness + 0.15, roughness, fresnel);
	METALLIC = metallic;
	SPECULAR = specular;
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.5;
	ALPHA = mix(deep_color.a, 1.0, depth_diff * 0.9 + fresnel * 0.1);
	ALPHA = clamp(ALPHA + foam_mask * 0.4, 0.0, 1.0);
}
