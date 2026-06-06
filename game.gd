extends Node

@export var time_of_day: float = 0.0
@export var auto_advance_time: bool = false
@export var time_speed: float = 1.0

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $SunLight
@onready var sky_light: DirectionalLight3D = $SkyLight

const SUN_COLORS := [
	Color(0.05, 0.07, 0.15),
	Color(1.0, 0.6, 0.3),
	Color(1.0, 0.85, 0.7),
	Color(1.0, 0.98, 0.95),
	Color(1.0, 0.65, 0.25),
	Color(0.6, 0.3, 0.15),
	Color(0.05, 0.07, 0.15),
]

const SKY_COLORS := [
	Color(0.02, 0.03, 0.08),
	Color(0.5, 0.35, 0.55),
	Color(0.45, 0.65, 0.9),
	Color(0.25, 0.55, 0.95),
	Color(0.55, 0.35, 0.5),
	Color(0.2, 0.15, 0.35),
	Color(0.02, 0.03, 0.08),
]

const PHASE_HOURS := [0.0, 5.0, 7.0, 10.0, 17.0, 19.5, 24.0]


func _ready() -> void:
	_setup_environment()


func _process(delta: float) -> void:
	if auto_advance_time:
		time_of_day = fmod(time_of_day + delta * time_speed / 60.0, 24.0)
	_update_sun()


func _setup_environment() -> void:
	var sky := Sky.new()
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.0
	sky_mat.mie_coefficient = 0.005
	sky_mat.mie_eccentricity = 0.8
	sky_mat.turbidity = 4.0
	sky_mat.sun_disk_scale = 6.0
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.0

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_energy = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 7.0

	env.ssao_enabled = true
	env.ssao_radius = 1.3
	env.ssao_intensity = 2.2
	env.ssao_power = 1.5
	env.ssao_sharpness = 0.98

	env.ssil_enabled = true
	env.ssil_radius = 5.0
	env.ssil_intensity = 1.0
	env.ssil_sharpness = 0.9

	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.5
	env.sdfgi_energy = 1.0
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1

	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.08)
	env.fog_light_energy = 0.5
	env.fog_density = 0.04
	env.fog_sky_affect = 0.3

	world_env.environment = env

	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_max_distance = 150.0
	sun_light.shadow_bias = 0.03
	sky_light.shadow_enabled = false


func _update_sun() -> void:
	var phase_idx := 0
	for i in range(PHASE_HOURS.size() - 1):
		if time_of_day >= PHASE_HOURS[i] and time_of_day < PHASE_HOURS[i + 1]:
			phase_idx = i
			break

	var t = (time_of_day - PHASE_HOURS[phase_idx]) / (PHASE_HOURS[phase_idx + 1] - PHASE_HOURS[phase_idx])
	var next_idx := mini(phase_idx + 1, SUN_COLORS.size() - 1)

	sun_light.light_color = SUN_COLORS[phase_idx].lerp(SUN_COLORS[next_idx], t)
	sky_light.light_color = SKY_COLORS[phase_idx].lerp(SKY_COLORS[next_idx], t)

	var sun_angle := (time_of_day / 24.0) * TAU - PI * 0.5
	var elevation := sin(sun_angle)

	sun_light.rotation_degrees = Vector3(-rad_to_deg(sun_angle) * 0.75, 45.0, 0.0)
	sky_light.rotation_degrees = Vector3(30.0, rad_to_deg(sun_angle) * 0.3 + 180.0, 0.0)

	sun_light.light_energy = clamp(elevation * 2.5, 0.0, 2.5)
	sky_light.light_energy = clamp(elevation * 0.6 + 0.15, 0.05, 0.75)
	sun_light.visible = sun_light.light_energy > 0.05

	var night_factor = clamp(1.0 - abs(elevation) * 3.0, 0.0, 1.0)
	world_env.environment.ambient_light_energy = lerp(0.08, 0.0, night_factor)
	world_env.environment.ambient_light_color = Color(0.04, 0.04, 0.06).lerp(Color(0.95, 0.85, 0.7), 1.0 - night_factor)
	world_env.environment.fog_density = lerp(0.002, 0.04, night_factor)
	world_env.environment.fog_light_color = Color(0.8, 0.9, 1.0).lerp(Color(0.02, 0.02, 0.05), night_factor)
