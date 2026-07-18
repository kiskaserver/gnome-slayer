class_name WgEnv
extends RefCounted
## Окружение: свет/туман/небо, земля, атмосферные частицы, детализация
## (трава, цветы, брёвна и пр.).


## Трава, цветы, кусты, брёвна, пни — детализация арены.
static func _build_details(parent: Node3D, rng: RandomNumberGenerator, b: Dictionary, biome_id: String, obstacles: Array, radius := WorldGen.WORLD_RADIUS) -> void:
	# травинки (конусы)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.045
	blade.height = 0.34
	blade.radial_segments = 4
	blade.rings = 1
	blade.material = WgLib._mat(b.grass_color)
	WgLib._scatter(parent, rng, blade, int(b.grass), 3.0, radius - 1.5, 0.7, 1.5, 0.15)

	# кусты
	var bush := SphereMesh.new()
	bush.radius = 0.55
	bush.height = 0.7
	bush.radial_segments = 8
	bush.rings = 4
	bush.material = WgLib._mat((b.leaves[0] as Color).lightened(0.05))
	WgLib._scatter(parent, rng, bush, 22, 6.0, radius - 2.0, 0.6, 1.4, 0.1)

	match biome_id:
		"meadow":
			for fc in [Color(1, 1, 0.85), Color(1.0, 0.8, 0.3), Color(0.95, 0.5, 0.6), Color(0.7, 0.6, 1.0)]:
				var flower := SphereMesh.new()
				flower.radius = 0.06
				flower.height = 0.12
				flower.radial_segments = 6
				flower.rings = 3
				var fm := WgLib._mat(fc)
				fm.emission_enabled = true
				fm.emission = fc
				fm.emission_energy_multiplier = 0.25
				flower.material = fm
				WgLib._scatter(parent, rng, flower, 26, 3.0, radius - 2.0, 0.8, 1.4, 0.28)
		"autumn":
			# опавшие листья — фигурные, с центральной жилкой
			WgLib._scatter(parent, rng, WgLib.leaf_mesh(Color(0.8, 0.45, 0.12)), 260, 3.0, radius - 1.0, 1.0, 2.2, 0.01)
			WgLib._scatter(parent, rng, WgLib.leaf_mesh(Color(0.62, 0.25, 0.1)), 200, 3.0, radius - 1.0, 1.0, 2.0, 0.01)
			WgLib._scatter(parent, rng, WgLib.leaf_mesh(Color(0.72, 0.55, 0.15)), 150, 3.0, radius - 1.0, 1.0, 2.0, 0.01)
		"winter":
			# сугробы
			var mound := SphereMesh.new()
			mound.radius = 0.7
			mound.height = 0.5
			mound.radial_segments = 8
			mound.rings = 4
			mound.material = WgLib._mat(Color(0.92, 0.95, 1.0))
			WgLib._scatter(parent, rng, mound, 40, 4.0, radius - 1.5, 0.6, 1.8, 0.0, 0.6, obstacles)
		"night":
			# светящиеся грибочки
			for i in 40:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(4.0, radius - 2.0)
				WgLib._mushroom(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.5, 1.0), true)
			# старый погост: надгробия и черепа
			var graves := ["halloween/grave_A.gltf", "halloween/grave_B.gltf", "halloween/gravemarker_A.gltf"]
			for i in 12:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(9.0, radius - 4.0)
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				if Vector2(p.x - 6.0, p.z - 6.0).length() > 7.0:
					WgLib.place_prop(parent, graves[rng.randi() % graves.size()], p, rng.randf_range(0, TAU), rng.randf_range(0.9, 1.3), 0.45, 1.4)
					obstacles.append({"x": p.x, "z": p.z, "r": 0.45})
			for i in 9:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(5.0, radius - 3.0)
				WgLib.place_prop(parent, "halloween/skull.gltf", Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0, TAU), rng.randf_range(0.7, 1.1))
			# тыквы-светильники подсвечивают тропы
			for i in 8:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(7.0, radius - 4.0)
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				var pumpkin := WgLib.place_prop(parent, "halloween/pumpkin_orange_jackolantern.gltf", p, rng.randf_range(0, TAU), rng.randf_range(1.0, 1.5), 0.35, 1.2)
				obstacles.append({"x": p.x, "z": p.z, "r": 0.35})
				var pl := OmniLight3D.new()
				pl.light_color = Color(1.0, 0.55, 0.15)
				pl.light_energy = 0.0
				pl.omni_range = 4.5
				pl.position.y = 0.5
				pl.add_to_group("night_light")
				pumpkin.add_child(pl)

	# брёвна и пни (с коллизией)
	for i in 6:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(10.0, radius - 6.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var log_mesh := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.28
		lm.bottom_radius = 0.32
		lm.height = rng.randf_range(2.0, 3.2)
		lm.radial_segments = 8
		log_mesh.mesh = lm
		log_mesh.material_override = WgLib._mat(Color(0.38, 0.27, 0.17))
		parent.add_child(log_mesh)
		log_mesh.global_position = Vector3(x, 0.3, z)
		log_mesh.rotation = Vector3(PI * 0.5, rng.randf_range(0, TAU), 0)
		log_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		WgLib._static_cylinder(parent, x, z, 0.8, 0.6)
	for i in 5:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(8.0, radius - 5.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var stump := MeshInstance3D.new()
		var stm := CylinderMesh.new()
		stm.top_radius = 0.35
		stm.bottom_radius = 0.45
		stm.height = 0.5
		stm.radial_segments = 9
		stump.mesh = stm
		stump.material_override = WgLib._mat(Color(0.45, 0.32, 0.2))
		parent.add_child(stump)
		stump.global_position = Vector3(x, 0.25, z)
		stump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		WgLib._static_cylinder(parent, x, z, 0.45, 0.6)


## Атмосферные частицы биома: пыльца/снег/листопад/светлячки.
static func _ambient_particles(parent: Node3D, kind: String, radius := WorldGen.WORLD_RADIUS) -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(radius, 7, radius)
	var dm := SphereMesh.new()
	dm.radial_segments = 5
	dm.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.vertex_color_use_as_albedo = true
	dm.material = dmat
	match kind:
		"snow":
			p.amount = 400
			p.lifetime = 9.0
			mat.gravity = Vector3(0.3, -1.4, 0)
			mat.color = Color(1, 1, 1, 0.85)
			dm.radius = 0.035
			dm.height = 0.07
		"leaves":
			p.amount = 160
			p.lifetime = 8.0
			mat.gravity = Vector3(0.5, -1.1, 0.2)
			mat.angular_velocity_min = 90.0
			mat.angular_velocity_max = 360.0
			mat.color = Color(1, 1, 1, 0.95)
			p.draw_pass_1 = WgLib.leaf_mesh(Color(0.85, 0.5, 0.15))
			p.process_material = mat
			p.visibility_aabb = AABB(Vector3(-radius - 5, -2, -radius - 5), Vector3(radius * 2 + 10, 16, radius * 2 + 10))
			p.position.y = 4.0
			p.preprocess = 6.0
			parent.add_child(p)
			return
		"fireflies":
			p.amount = 130
			p.lifetime = 12.0
			mat.gravity = Vector3.ZERO
			mat.initial_velocity_min = 0.2
			mat.initial_velocity_max = 0.6
			mat.spread = 180.0
			mat.direction = Vector3(1, 0.2, 0)
			mat.color = Color(1.6, 1.5, 0.5, 1.0) # ярче единицы — расцветает в bloom
			dm.radius = 0.04
			dm.height = 0.08
			mat.emission_box_extents = Vector3(radius, 2.5, radius)
		_: # pollen
			p.amount = 150
			p.lifetime = 10.0
			mat.gravity = Vector3(0.2, -0.15, 0.1)
			mat.color = Color(1, 1, 0.9, 0.5)
			dm.radius = 0.03
			dm.height = 0.06
	p.process_material = mat
	p.draw_pass_1 = dm
	p.visibility_aabb = AABB(Vector3(-radius - 5, -2, -radius - 5), Vector3(radius * 2 + 10, 16, radius * 2 + 10))
	p.position.y = 4.0
	p.preprocess = 6.0 # частицы уже в воздухе на старте
	parent.add_child(p)


## Строит мир. Возвращает {"spawn_points", "houses", "nav_region"}.
## Окружение (env/sky/солнце/луна) — общее для арены и оверворлда.
static func _setup_environment(parent: Node3D, b: Dictionary) -> Dictionary:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME # небо динамическое — рассеянный свет обновляется
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = b.ambient
	e.fog_enabled = true
	e.fog_light_color = b.fog
	e.fog_density = b.fog_d
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# мягкое свечение и глубина: сцена перестаёт выглядеть «плоской»
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = true
	e.ssao_intensity = 1.6
	env.environment = e
	parent.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = b.sun_rot
	sun.light_energy = b.sun_e
	sun.light_color = b.sun
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	parent.add_child(sun)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.directional_shadow_max_distance = 90.0
	parent.add_child(moon)
	return {"env": e, "sun": sun, "moon": moon, "sky_mat": sky_mat}


## Земля + коллайдер пола + невидимая стена по границе, радиус задаётся.
static func _setup_ground(parent: Node3D, world_seed: int, b: Dictionary, radius: float) -> void:
	var ground := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = radius + 40.0
	gm.bottom_radius = radius + 40.0
	gm.height = 0.1
	gm.radial_segments = 64
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.roughness = 1.0
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = 0.012
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.seamless = true
	var grad := Gradient.new()
	grad.set_color(0, b.ground.darkened(0.16))
	grad.set_color(1, b.ground.lightened(0.08))
	ntex.color_ramp = grad
	gmat.albedo_texture = ntex
	gmat.uv1_triplanar = true
	gmat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	ground.material_override = gmat
	ground.position.y = -0.05
	parent.add_child(ground)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(radius * 2.0 + 64.0, 1, radius * 2.0 + 64.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	parent.add_child(floor_body)

	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	parent.add_child(wall_body)
	var wall_count := 24
	for i in wall_count:
		var a := float(i) / wall_count * TAU
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var seg := TAU * (radius + 1.0) / wall_count
		box.size = Vector3(seg * 1.2, 6.0, 1.0)
		shape.shape = box
		wall_body.add_child(shape)
		shape.global_position = Vector3(cos(a) * (radius + 1.5), 3.0, sin(a) * (radius + 1.5))
		shape.rotation.y = -a + PI * 0.5
