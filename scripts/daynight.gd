class_name DayNight
extends Node
## Цикл дня и ночи: движение солнца и луны, закаты, звёзды, окна домиков.
## Время суток t ∈ [0..1): 0.25 — рассвет, 0.5 — полдень, 0.75 — закат.

const DAY_LENGTH := 480.0 # полный оборот суток, секунд
const NIGHT_FOG := Color(0.05, 0.07, 0.15)

var time := 0.3
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var biome: Dictionary
var night_lights: Array = []


func setup(refs: Dictionary, b: Dictionary, start_time: float) -> void:
	sun = refs.sun
	moon = refs.moon
	env = refs.env
	sky_mat = refs.sky_mat
	biome = b
	time = start_time
	night_lights = get_tree().get_nodes_in_group("night_light")
	sky_mat.set_shader_parameter("day_top", b.sky_top)
	sky_mat.set_shader_parameter("day_hor", b.sky_hor)
	sky_mat.set_shader_parameter("ground_color", (b.ground as Color).darkened(0.35))
	_apply()


## Сетевая коррекция времени (сервер рассылает своё).
func sync_time(t: float) -> void:
	var diff: float = absf(t - time)
	if diff > 0.5:
		diff = 1.0 - diff
	if diff > 0.01:
		time = t


func _physics_process(delta: float) -> void:
	time = fmod(time + delta / DAY_LENGTH, 1.0)
	_apply()


func _apply() -> void:
	var ang := (time - 0.25) * TAU
	# положение солнца на небосводе (слегка наклонённая дуга)
	var sun_v := Vector3(cos(ang) * 0.6, sin(ang), 0.42).normalized()
	var moon_v := -sun_v

	var day_k := clampf(sun_v.y * 3.5, 0.0, 1.0)
	var night_k := clampf(-sun_v.y * 3.5, 0.0, 1.0)
	var sunset_k := exp(-pow(sun_v.y * 5.0, 2.0)) # колокол у горизонта

	# солнце
	if sun_v.y > -0.15:
		sun.transform.basis = Basis.looking_at(-sun_v, Vector3.UP)
	sun.light_energy = biome.sun_e * day_k
	sun.light_color = (biome.sun as Color).lerp(Color(1.0, 0.5, 0.25), sunset_k * 0.85)
	sun.shadow_enabled = day_k > 0.05

	# луна
	if moon_v.y > -0.15:
		moon.transform.basis = Basis.looking_at(-moon_v, Vector3.UP)
	moon.light_energy = 0.42 * night_k
	moon.shadow_enabled = night_k > 0.5

	# туман и рассеянный свет
	var fog_c := (biome.fog as Color).lerp(NIGHT_FOG, night_k)
	env.fog_light_color = fog_c.lerp(Color(1.0, 0.55, 0.32), sunset_k * 0.5)
	env.fog_density = biome.fog_d * (1.0 + 0.35 * night_k)
	env.ambient_light_energy = biome.ambient * (1.0 - 0.25 * night_k)

	# небо
	sky_mat.set_shader_parameter("sun_dir", sun_v)
	sky_mat.set_shader_parameter("moon_dir", moon_v)
	sky_mat.set_shader_parameter("night_k", night_k)
	sky_mat.set_shader_parameter("sunset_k", sunset_k)

	# окна домиков загораются в сумерках
	var window_k := clampf(night_k + sunset_k * 0.5, 0.0, 1.0)
	for l in night_lights:
		if is_instance_valid(l):
			l.light_energy = window_k * 1.25
