class_name WgArena
extends RefCounted
## Арена волн/ПвП (радиус WorldGen.WORLD_RADIUS) и руины ПвП.


## Центральные руины ПвП-арены: кольцо колонн и обломки стен.
static func _build_pvp_ruins(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var stone := Color(0.6, 0.58, 0.54)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var x := cos(a) * 6.0
		var z := sin(a) * 6.0
		var pillar := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.45
		pm.bottom_radius = 0.55
		pm.height = rng.randf_range(1.8, 3.6)
		pm.radial_segments = 9
		pillar.mesh = pm
		pillar.material_override = WgLib._mat(stone, true)
		parent.add_child(pillar)
		pillar.global_position = Vector3(x, pm.height * 0.5, z)
		pillar.rotation.y = rng.randf_range(0, TAU)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		WgLib._static_cylinder(parent, x, z, 0.6, pm.height)
	# четыре обломка стен по диагоналям
	for i in 4:
		var a := float(i) / 4.0 * TAU + PI / 4.0
		var x := cos(a) * 14.0
		var z := sin(a) * 14.0
		var wall := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(4.0, rng.randf_range(1.2, 2.0), 0.8)
		wall.mesh = wm
		wall.material_override = WgLib._mat(stone.darkened(0.1), true)
		parent.add_child(wall)
		wall.global_position = Vector3(x, wm.size.y * 0.5, z)
		wall.rotation.y = -a + PI * 0.5
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wm.size
		shape.shape = box
		body.add_child(shape)
		parent.add_child(body)
		body.global_position = wall.global_position
		body.rotation.y = wall.rotation.y


static func build(parent: Node3D, world_seed: int, biome_id: String, pvp := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var b: Dictionary = WorldGen.BIOMES.get(biome_id, WorldGen.BIOMES["meadow"])
	var obstacles: Array = []
	var pois: Array = []
	var spawn_points: Array = []
	var houses: Array = []

	var envd := WgEnv._setup_environment(parent, b)
	var e: Environment = envd.env
	var sun: DirectionalLight3D = envd.sun
	var moon: DirectionalLight3D = envd.moon
	var sky_mat: ShaderMaterial = envd.sky_mat
	WgEnv._setup_ground(parent, world_seed, b, WorldGen.WORLD_RADIUS)

	# --- лес за границей ---
	for i in 78:
		var a := float(i) / 78.0 * TAU + rng.randf_range(-0.05, 0.05)
		var r := WorldGen.WORLD_RADIUS + rng.randf_range(2.5, 14.0)
		WgLib._tree(parent, rng, b, cos(a) * r, sin(a) * r, rng.randf_range(1.1, 1.9), false)

	# --- камни по периметру ---
	for i in 40:
		var a := float(i) / 40.0 * TAU + rng.randf_range(-0.06, 0.06)
		var r := WorldGen.WORLD_RADIUS + rng.randf_range(0.0, 1.5)
		WgLib._rock(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.8, 1.5), false)

	if pvp:
		# --- ПвП-арена: руины в центре, симметричные укрытия, без домиков ---
		_build_pvp_ruins(parent, rng)
		for i in 4:
			var a := float(i) / 4.0 * TAU
			var r := 24.0
			WgLib._rock(parent, rng, cos(a) * r + rng.randf_range(-2, 2), sin(a) * r + rng.randf_range(-2, 2), rng.randf_range(1.0, 1.6), true)
			WgLib._tree(parent, rng, b, cos(a) * r + rng.randf_range(-4, 4), sin(a) * r + rng.randf_range(-4, 4), rng.randf_range(1.0, 1.4), true)
		for i in 4:
			var a := float(i) / 4.0 * TAU + PI / 4.0
			spawn_points.append(Vector3(cos(a) * (WorldGen.WORLD_RADIUS - 8.0), 0, sin(a) * (WorldGen.WORLD_RADIUS - 8.0)))
	else:
		# --- домики гномов ---
		for i in 5:
			var a := float(i) / 5.0 * TAU + 0.4
			var r := WorldGen.WORLD_RADIUS - 7.0
			var x := cos(a) * r
			var z := sin(a) * r
			var house := WgLib._house(parent, x, z)
			houses.append(house)
			obstacles.append({"x": x, "z": z, "r": 2.0})
			spawn_points.append(Vector3(x + house.dirx * 2.2, 0, z + house.dirz * 2.2))

		# --- деревья и камни внутри арены ---
		for i in 22:
			var x := 0.0
			var z := 0.0
			var ok := false
			for _try in 30:
				x = rng.randf_range(-WorldGen.WORLD_RADIUS + 6, WorldGen.WORLD_RADIUS - 6)
				z = rng.randf_range(-WorldGen.WORLD_RADIUS + 6, WorldGen.WORLD_RADIUS - 6)
				if Vector2(x, z).length() > 10.0 and Vector2(x - 6.0, z - 6.0).length() > 7.0 and WgGeom._far_from(obstacles, x, z, 5.0):
					ok = true
					break
			if ok:
				WgLib._tree(parent, rng, b, x, z, rng.randf_range(0.9, 1.5), true)
				obstacles.append({"x": x, "z": z, "r": 0.7})

		for i in 16:
			var x := 0.0
			var z := 0.0
			var ok := false
			for _try in 30:
				x = rng.randf_range(-WorldGen.WORLD_RADIUS + 5, WorldGen.WORLD_RADIUS - 5)
				z = rng.randf_range(-WorldGen.WORLD_RADIUS + 5, WorldGen.WORLD_RADIUS - 5)
				if Vector2(x, z).length() > 8.0 and Vector2(x - 6.0, z - 6.0).length() > 7.0 and WgGeom._far_from(obstacles, x, z, 4.0):
					ok = true
					break
			if ok:
				var s := rng.randf_range(0.6, 1.2)
				WgLib._rock(parent, rng, x, z, s, true)
				obstacles.append({"x": x, "z": z, "r": s * 0.9})

		# --- точки интереса: заметные ориентиры, не только случайный лес ---
		if not pvp:
			WgPois._build_pois(parent, rng, biome_id, obstacles, pois)

	# --- грибы (декор) ---
	for i in int(b.mushrooms):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(4.0, WorldGen.WORLD_RADIUS - 2.0)
		WgLib._mushroom(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.7, 1.6))

	# --- детализация и атмосфера ---
	WgEnv._build_details(parent, rng, b, biome_id, obstacles)
	WgEnv._ambient_particles(parent, b.particles)

	# --- навигационная сетка ---
	var region := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = "nav_src"
	navmesh.agent_radius = 0.5
	# кратно cell_height (0.25), иначе движок сыплет ворнинги о потере точности
	navmesh.agent_height = 1.5
	navmesh.agent_max_climb = 0.25
	region.navigation_mesh = navmesh
	parent.add_to_group("nav_src")
	parent.add_child(region)

	return {"spawn_points": spawn_points, "houses": houses, "nav_region": region,
		"sun": sun, "moon": moon, "env": e, "sky_mat": sky_mat, "biome": b, "obstacles": obstacles, "pois": pois}
