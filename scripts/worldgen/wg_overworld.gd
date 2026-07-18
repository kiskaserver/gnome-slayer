class_name WgOverworld
extends RefCounted
## Сюжетный оверворлд-путешествие: области, дорога, поселение, подход
## к склепу (радиус WorldGen.OVERWORLD_RADIUS).


## Сюжетный оверворлд. Возвращает тот же словарь, что и WgArena.build(), плюс
## "areas" (список областей) и "road" (вейпоинты дороги).
static func build_overworld(parent: Node3D, world_seed: int, biome_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var b: Dictionary = WorldGen.BIOMES.get(biome_id, WorldGen.BIOMES["meadow"])
	var obstacles: Array = []
	var pois: Array = []
	var spawn_points: Array = []
	var houses: Array = []
	var R := WorldGen.OVERWORLD_RADIUS

	var envd := WgEnv._setup_environment(parent, b)
	WgEnv._setup_ground(parent, world_seed, b, R)

	# --- планировка: главное направление дороги и области вдоль неё ---
	var road_a := rng.randf_range(0, TAU)
	var dirv := Vector3(cos(road_a), 0, sin(road_a))
	var sidev := Vector3(-dirv.z, 0, dirv.x)

	# Стянутая карта-путешествие (C0): области ближе, перегоны короче —
	# насыщенность вместо пустых полян между ориентирами.
	# Пара средних областей зависит от биома (C1): главы отличаются
	# компоновкой, а не только палитрой.
	var mid_kinds: Array = {
		"meadow": ["battlefield", "grove"],
		"autumn": ["enemy_camp", "grove"],
		"winter": ["outpost", "battlefield"],
		"night": ["cemetery", "enemy_camp"],
	}.get(biome_id, ["battlefield", "grove"])
	var areas: Array = []
	areas.append({"id": "camp", "kind": "camp", "center": Vector3(6, 0, 6), "radius": 20.0})
	var settle_c: Vector3 = dirv * 38.0 + sidev * rng.randf_range(-6.0, 6.0)
	areas.append({"id": "settlement", "kind": "settlement", "center": settle_c, "radius": 18.0})
	var side_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var battle_c: Vector3 = dirv * 55.0 + sidev * (22.0 * side_sign)
	areas.append({"id": mid_kinds[0], "kind": mid_kinds[0], "center": battle_c, "radius": 17.0})
	var grove_c: Vector3 = dirv * 52.0 - sidev * (23.0 * side_sign)
	areas.append({"id": mid_kinds[1], "kind": mid_kinds[1], "center": grove_c, "radius": 16.0})
	var approach_c: Vector3 = dirv * 66.0
	areas.append({"id": "approach", "kind": "approach", "center": approach_c, "radius": 14.0})

	# --- дорога: лагерь -> поселение -> развилка -> подход к подземелью ---
	# main_samples — только магистраль (для ворот и фонарей вдоль неё)
	var fork: Vector3 = dirv * 50.0
	var road_pts := [Vector3(6, 0, 6), dirv * 19.0, settle_c, fork, approach_c]
	var main_samples := WgGeom._lay_road(parent, rng, road_pts)
	var road := main_samples.duplicate()
	# боковые тропы к полю боя и роще
	road += WgGeom._lay_road(parent, rng, [fork, battle_c])
	road += WgGeom._lay_road(parent, rng, [fork, grove_c])

	# --- вход в подземелье: крипта с аркой на дальнем краю (ставим первой,
	# как ориентир, и регистрируем в obstacles — всё прочее её обходит) ---
	var crypt_pos: Vector3 = approach_c + dirv * 7.0
	var crypt_yaw := atan2(-dirv.x, -dirv.z) # фасад к дороге
	var crypt := WgLib.place_prop(parent, "halloween/crypt.gltf", crypt_pos, crypt_yaw, 1.25)
	for mi in crypt.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	WgLib._static_cylinder(parent, crypt_pos.x, crypt_pos.z, 4.5, 6.0)
	obstacles.append({"x": crypt_pos.x, "z": crypt_pos.z, "r": 4.5})
	var dungeon_entrance: Vector3 = crypt_pos - dirv * 5.5
	WgLib.place_prop(parent, "halloween/lantern_standing.gltf", dungeon_entrance + sidev * 2.4, atan2(-sidev.x, -sidev.z), 1.2)
	WgLib.place_prop(parent, "halloween/lantern_standing.gltf", dungeon_entrance - sidev * 2.4, atan2(sidev.x, sidev.z), 1.2)
	obstacles.append({"x": dungeon_entrance.x + sidev.x * 2.4, "z": dungeon_entrance.z + sidev.z * 2.4, "r": 0.6})
	obstacles.append({"x": dungeon_entrance.x - sidev.x * 2.4, "z": dungeon_entrance.z - sidev.z * 2.4, "r": 0.6})

	# --- застройка поселения (кольцом, с проверкой пересечений) ---
	WgGeom._place_settlement(parent, rng, settle_c, road, obstacles)

	# --- ядра областей (C1): сгруппированные композиции вместо пустоты ---
	WgCores._core_settlement(parent, rng, settle_c, road, obstacles)
	for pair in [[mid_kinds[0], battle_c, fork], [mid_kinds[1], grove_c, fork]]:
		var kind: String = pair[0]
		var c: Vector3 = pair[1]
		match kind:
			"battlefield": WgCores._core_battlefield(parent, rng, c, obstacles)
			"grove": WgCores._core_grove(parent, rng, b, c, obstacles)
			"enemy_camp": WgCores._core_enemy_camp(parent, rng, c, obstacles)
			"cemetery": WgCores._core_cemetery(parent, rng, c, obstacles)
			"outpost":
				# ворота заставы поперёк тропы от развилки к области
				var fk: Vector3 = pair[2]
				WgCores._core_outpost(parent, rng, c, atan2(c.z - fk.z, c.x - fk.x), obstacles)
	WgCores._core_approach(parent, rng, approach_c, dirv, sidev, obstacles)

	# --- ворота в открытых промежутках дороги (открытые створки) ---
	WgGeom._place_gates(parent, rng, main_samples, areas, obstacles)

	# --- домики гномов по областям (спавны врагов) — обходят всё вышестоящее ---
	for area in areas:
		if area.kind in ["camp"]:
			continue
		# табір ворога — гнездо спавнеров: домиков больше, чем в обычной области
		var n_houses := 2 if area.kind == "approach" else (4 if area.kind == "enemy_camp" else 3)
		for i in n_houses:
			var placed := false
			for _t in 60:
				var ha := rng.randf_range(0, TAU)
				# в тесном поселении (застройка + ятки) домики выносим на внешнее кольцо
				var hr: float = area.radius * (rng.randf_range(0.6, 0.98) if area.kind == "settlement" else rng.randf_range(0.5, 0.85))
				var hx: float = area.center.x + cos(ha) * hr
				var hz: float = area.center.z + sin(ha) * hr
				if not WgGeom._clear_of(obstacles, hx, hz, 2.6, 1.2) or WgGeom._road_dist(road, hx, hz) < 4.0:
					continue
				var house := WgLib._house(parent, hx, hz)
				house["area"] = area.id
				houses.append(house)
				obstacles.append({"x": hx, "z": hz, "r": 2.6})
				spawn_points.append(Vector3(hx + house.dirx * 2.2, 0, hz + house.dirz * 2.2))
				placed = true
				break

	# --- фонари вдоль магистрали (сбоку, по локальному перпендикуляру) ---
	WgGeom._place_lanterns(parent, rng, main_samples, obstacles)

	# --- тупички-кеши от дороги: тайник с отблеском, сундук поставит сервер ---
	var caches := WgCores._road_caches(parent, rng, main_samples, areas, obstacles)

	# --- взрывные бочки (D1): удар по бочке — взрыв, цепная детонация ---
	var barrels := WgCores.scatter_barrels(parent, rng, areas, road, obstacles)

	# --- точки интереса: по одной на область (кроме лагеря и подхода) ---
	var poi_kinds := ["ruins", "standing_stones", "shrine", "campfire", "well", "bounty_board", "crypt", "battlefield"]
	for i in range(poi_kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = poi_kinds[i]
		poi_kinds[i] = poi_kinds[j]
		poi_kinds[j] = tmp
	var pk := 0
	for area in areas:
		if area.kind == "approach":
			continue
		var per_area := 1 if area.kind == "camp" else 2
		for _n in per_area:
			if pk >= poi_kinds.size():
				break
			var kind: String = poi_kinds[pk]
			pk += 1
			var pos := Vector3.INF
			for _try in 80:
				var pa := rng.randf_range(0, TAU)
				var pr: float = area.radius * rng.randf_range(0.3, 0.9)
				var px: float = area.center.x + cos(pa) * pr
				var pz: float = area.center.z + sin(pa) * pr
				if Vector2(px - 6.0, pz - 6.0).length() > 12.0 and WgGeom._clear_of(obstacles, px, pz, 3.0, 2.5) and WgGeom._road_dist(road, px, pz) > 4.5:
					pos = Vector3(px, 0, pz)
					break
			if pos == Vector3.INF:
				continue
			match kind:
				"ruins": WgPois._poi_ruins(parent, rng, pos, obstacles)
				"standing_stones": WgPois._poi_standing_stones(parent, rng, pos, obstacles)
				"shrine": WgPois._poi_shrine(parent, rng, pos, obstacles)
				"campfire": WgPois._poi_campfire(parent, rng, pos, obstacles)
				"well": WgPois._poi_well(parent, rng, pos, obstacles)
				"bounty_board": WgPois._poi_bounty_board(parent, rng, pos, obstacles)
				"crypt": WgPois._poi_crypt(parent, rng, pos, obstacles)
				"battlefield": WgPois._poi_battlefield(parent, rng, pos, obstacles)
			pois.append({"kind": kind, "x": pos.x, "z": pos.z})

	# --- лесные пояса: резко прорежены (C0) — лес формирует пространство,
	# а не заполняет его; плотные «рощи» остаются только между областями ---
	WgGeom._forest_belt(parent, rng, b, 22.0, 32.0, 46, road, areas, obstacles)
	WgGeom._forest_belt(parent, rng, b, 42.0, 62.0, 74, road, areas, obstacles)
	# лес за границей мира (декорация — без теней)
	for i in 70:
		var a := float(i) / 70.0 * TAU + rng.randf_range(-0.05, 0.05)
		var r := R + rng.randf_range(2.5, 14.0)
		WgLib._tree(parent, rng, b, cos(a) * r, sin(a) * r, rng.randf_range(1.2, 2.0), false, false)

	# --- редкие деревья/камни внутри областей ---
	for area in areas:
		if area.kind == "camp":
			continue
		for i in 4:
			var ta := rng.randf_range(0, TAU)
			var tr: float = area.radius * rng.randf_range(0.4, 0.9)
			var tx: float = area.center.x + cos(ta) * tr
			var tz: float = area.center.z + sin(ta) * tr
			if WgGeom._clear_of(obstacles, tx, tz, 0.7, 1.0) and WgGeom._road_dist(road, tx, tz) > 4.0:
				WgLib._tree(parent, rng, b, tx, tz, rng.randf_range(0.9, 1.4), true)
				obstacles.append({"x": tx, "z": tz, "r": 0.7})
		for i in 3:
			var ra := rng.randf_range(0, TAU)
			var rr: float = area.radius * rng.randf_range(0.4, 0.9)
			var rx: float = area.center.x + cos(ra) * rr
			var rz: float = area.center.z + sin(ra) * rr
			if WgGeom._clear_of(obstacles, rx, rz, 1.1, 0.8) and WgGeom._road_dist(road, rx, rz) > 3.0:
				var s := rng.randf_range(0.6, 1.2)
				WgLib._rock(parent, rng, rx, rz, s, true)
				obstacles.append({"x": rx, "z": rz, "r": s * 0.9})

	# --- грибы, детализация, атмосфера (по большому радиусу) ---
	for i in int(b.mushrooms * 1.6):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(4.0, R - 2.0)
		WgLib._mushroom(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.7, 1.6))
	WgEnv._build_details(parent, rng, b, biome_id, obstacles, R)
	WgEnv._ambient_particles(parent, b.particles, R)

	# --- навигационная сетка (как в WgArena.build) ---
	var region := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = "nav_src"
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.5
	navmesh.agent_max_climb = 0.25
	region.navigation_mesh = navmesh
	parent.add_to_group("nav_src")
	parent.add_child(region)

	return {"spawn_points": spawn_points, "houses": houses, "nav_region": region,
		"sun": envd.sun, "moon": envd.moon, "env": envd.env, "sky_mat": envd.sky_mat,
		"biome": b, "obstacles": obstacles, "pois": pois,
		"areas": areas, "road": road_pts, "dungeon_entrance": dungeon_entrance,
		"caches": caches, "barrels": barrels}
