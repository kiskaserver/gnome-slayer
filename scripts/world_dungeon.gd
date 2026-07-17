class_name WorldDungeon
extends RefCounted
## Генератор подземелий из модульного набора Dungeon Remastered (CC0, KayKit).
## Грид 4-метровых ячеек: комнаты + Г-образные коридоры, стены по границе пола,
## факелы, ловушки-шипы, сундучные места; финальная комната — арена босса.

const CELL := 4.0
const GRID := 15  # 15x15 ячеек = 60x60 метров


static func _cell_pos(gx: int, gz: int) -> Vector3:
	return Vector3((gx - GRID / 2.0 + 0.5) * CELL, 0, (gz - GRID / 2.0 + 0.5) * CELL)


static func build(parent: Node3D, zone_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_seed
	var obstacles: Array = []

	# --- тёмное окружение: без неба и солнца, свет — факелы ---
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.36, 0.45)
	e.ambient_light_energy = 0.35
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.05, 0.09)
	e.fog_density = 0.012
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = true
	e.ssao_intensity = 2.0
	env_node.environment = e
	parent.add_child(env_node)

	# тусклый "лунный" направленный свет, чтобы геометрия читалась и вне факелов
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.12
	sun.light_color = Color(0.5, 0.55, 0.8)
	sun.shadow_enabled = false
	parent.add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.0
	parent.add_child(moon)

	# --- планировка: комнаты ---
	var floor_cells: Dictionary = {}  # Vector2i -> true
	var rooms: Array = []             # {gx, gz, w, h, center: Vector3}
	var n_rooms := rng.randi_range(5, 7)
	for _try in 200:
		if rooms.size() >= n_rooms:
			break
		var w := rng.randi_range(2, 4)
		var h := rng.randi_range(2, 4)
		var gx := rng.randi_range(1, GRID - w - 1)
		var gz := rng.randi_range(1, GRID - h - 1)
		var clash := false
		for r in rooms:
			if gx < r.gx + r.w + 1 and gx + w + 1 > r.gx and gz < r.gz + r.h + 1 and gz + h + 1 > r.gz:
				clash = true
				break
		if clash:
			continue
		var center := _cell_pos(gx + w / 2, gz + h / 2)
		rooms.append({"gx": gx, "gz": gz, "w": w, "h": h, "center": center})
		for cx in range(gx, gx + w):
			for cz in range(gz, gz + h):
				floor_cells[Vector2i(cx, cz)] = true

	# вход — первая комната; босс — самая дальняя от входа
	var entry: Dictionary = rooms[0]
	var boss_room: Dictionary = rooms[0]
	var best_d := 0.0
	for r in rooms:
		var d: float = entry.center.distance_to(r.center)
		if d > best_d:
			best_d = d
			boss_room = r

	# --- коридоры: последовательное Г-образное соединение ---
	var corridor_cells: Array = []
	for i in range(rooms.size() - 1):
		var a: Dictionary = rooms[i]
		var c: Dictionary = rooms[i + 1]
		var ax: int = a.gx + a.w / 2
		var az: int = a.gz + a.h / 2
		var cx: int = c.gx + c.w / 2
		var cz: int = c.gz + c.h / 2
		var x := ax
		while x != cx:
			x += 1 if cx > x else -1
			if not floor_cells.has(Vector2i(x, az)):
				floor_cells[Vector2i(x, az)] = true
				corridor_cells.append(Vector2i(x, az))
		var z := az
		while z != cz:
			z += 1 if cz > z else -1
			if not floor_cells.has(Vector2i(cx, z)):
				floor_cells[Vector2i(cx, z)] = true
				corridor_cells.append(Vector2i(cx, z))

	# --- пол: общий коллайдер + тайлы ---
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(GRID * CELL + 8, 1, GRID * CELL + 8)
	fshape.shape = fbox
	fshape.position.y = -0.5
	floor_body.add_child(fshape)
	parent.add_child(floor_body)

	for cell in floor_cells:
		var p := _cell_pos(cell.x, cell.y)
		var tile := WorldGen.place_prop(parent, "dungeon/floor_tile_large.gltf.glb", Vector3(p.x, 0.0, p.z), 0.0, 1.0)
		for mi in tile.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- стены по границам пола ---
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var torch_lights := 0
	var wall_i := 0
	for cell in floor_cells:
		for d in dirs:
			var nb: Vector2i = cell + d
			if floor_cells.has(nb):
				continue
			wall_i += 1
			var p := _cell_pos(cell.x, cell.y)
			var wall_pos := Vector3(p.x + d.x * CELL * 0.5, 0, p.z + d.y * CELL * 0.5)
			var rot := 0.0 if d.y != 0 else PI * 0.5
			var wall_model := "dungeon/wall.gltf.glb" if wall_i % 4 != 0 else "dungeon/wall_cracked.gltf.glb"
			WorldGen.place_prop(parent, wall_model, wall_pos, rot, 1.0)
			# коллайдер стены
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(CELL, 4.0, 1.0)
			shape.shape = box
			body.add_child(shape)
			parent.add_child(body)
			body.global_position = Vector3(wall_pos.x, 2.0, wall_pos.z)
			body.rotation.y = rot
			# факел на каждой четвёртой стене (с настоящим светом)
			if wall_i % 4 == 1 and torch_lights < 22:
				torch_lights += 1
				var in_dir := Vector3(-d.x, 0, -d.y)
				var tpos := wall_pos + in_dir * 0.55
				var torch := WorldGen.place_prop(parent, "dungeon/torch_mounted.gltf.glb", Vector3(tpos.x, 1.8, tpos.z), rot, 1.0)
				var tl := OmniLight3D.new()
				tl.light_color = Color(1.0, 0.62, 0.25)
				tl.light_energy = 1.4
				tl.omni_range = 8.0
				tl.position.y = 0.9
				torch.add_child(tl)

	# --- реквизит в комнатах ---
	var props := ["dungeon/barrel_large.gltf.glb", "dungeon/crates_stacked.gltf.glb", "dungeon/table_medium.gltf.glb"]
	var chest_spots: Array = []
	for ri in rooms.size():
		var r: Dictionary = rooms[ri]
		var is_entry: bool = r == entry
		var is_boss: bool = r == boss_room
		if not is_entry and not is_boss:
			# сундук в дальних комнатах — исследование вознаграждается
			if chest_spots.size() < 3 and rng.randf() < 0.75:
				var cpos: Vector3 = r.center + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
				chest_spots.append(cpos)
		for _p in rng.randi_range(0, 2):
			var px: float = r.center.x + rng.randf_range(-(r.w - 1) * CELL * 0.4, (r.w - 1) * CELL * 0.4)
			var pz: float = r.center.z + rng.randf_range(-(r.h - 1) * CELL * 0.4, (r.h - 1) * CELL * 0.4)
			if Vector2(px - r.center.x, pz - r.center.z).length() < 1.5:
				continue # центр комнаты держим свободным
			WorldGen.place_prop(parent, props[rng.randi() % props.size()], Vector3(px, 0, pz), rng.randf_range(0, TAU), 1.0)
			WorldGen._static_cylinder(parent, px, pz, 0.7, 1.6)
			obstacles.append({"x": px, "z": pz, "r": 0.7})

	# --- зал босса: знамёна и золото ---
	WorldGen.place_prop(parent, "dungeon/banner_patternA_red.gltf.glb", boss_room.center + Vector3(0, 0, -(boss_room.h * CELL * 0.5) + 0.8), 0.0, 1.0)
	WorldGen.place_prop(parent, "dungeon/coin_stack_medium.gltf.glb", boss_room.center + Vector3(1.8, 0, 1.2), rng.randf_range(0, TAU), 1.2)
	WorldGen.place_prop(parent, "dungeon/trunk_large_A.gltf.glb", boss_room.center + Vector3(-2.0, 0, 1.5), rng.randf_range(0, TAU), 1.1)

	# --- ловушки-шипы в коридорах ---
	var traps: Array = []
	if corridor_cells.size() > 4:
		for _t in rng.randi_range(1, 2):
			var tc: Vector2i = corridor_cells[rng.randi_range(2, corridor_cells.size() - 1)]
			var tp := _cell_pos(tc.x, tc.y)
			WorldGen.place_prop(parent, "dungeon/floor_tile_big_spikes.glb", Vector3(tp.x, 0.05, tp.z), 0.0, 1.0)
			traps.append({"x": tp.x, "z": tp.z, "r": 1.8})

	# --- навигационная сетка (тот же рецепт, что и снаружи) ---
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

	return {"spawn_points": [entry.center], "houses": [], "nav_region": region,
		"sun": sun, "moon": moon, "env": e, "sky_mat": null,
		"biome": WorldGen.BIOMES["night"], "obstacles": obstacles, "pois": [],
		"rooms": rooms, "boss_spot": boss_room.center, "entry_spot": entry.center,
		"chest_spots": chest_spots, "traps": traps}
