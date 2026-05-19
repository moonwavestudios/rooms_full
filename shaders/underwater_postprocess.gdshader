shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform vec4 fog_color : source_color = vec4(0.01, 0.12, 0.14, 1.0);
uniform float fog_near : hint_range(0.0, 50.0) = 2.0;
uniform float fog_far : hint_range(0.0, 500.0) = 60.0;
uniform float fog_density : hint_range(0.0, 1.0) = 0.92;
uniform float teal_shift : hint_range(0.0, 1.0) = 0.7;
uniform float aberration : hint_range(0.0, 0.02) = 0.004;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	vec3 col_r = texture(SCREEN_TEXTURE, uv + vec2(aberration, 0.0)).rgb;
	vec3 col_g = texture(SCREEN_TEXTURE, uv).rgb;
	vec3 col_b = texture(SCREEN_TEXTURE, uv - vec2(aberration, 0.0)).rgb;
	vec3 scene = vec3(col_r.r, col_g.g, col_b.b);

	float depth_raw = texture(DEPTH_TEXTURE, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth_raw);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords /= view_coords.w;
	float linear_depth = -view_coords.z;

	float fog_amount = clamp((linear_depth - fog_near) / (fog_far - fog_near), 0.0, 1.0);
	fog_amount = pow(fog_amount, 0.7) * fog_density;

	float luminance = dot(scene, vec3(0.299, 0.587, 0.114));
	vec3 teal_tinted = mix(scene, vec3(luminance) * vec3(0.6, 1.3, 1.4), teal_shift * 0.3);
	teal_tinted = clamp(teal_tinted, 0.0, 1.0);

	vec3 final = mix(teal_tinted, fog_color.rgb, fog_amount);

	float vignette = length(uv - 0.5) * 1.6;
	vignette = clamp(vignette * vignette * 0.5, 0.0, 1.0);
	final = mix(final, fog_color.rgb * 0.3, vignette);

	ALBEDO = final;
}
