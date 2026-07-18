class_name WorldDungeon
extends RefCounted
## Генератор подземелий из модульного набора Dungeon Remastered (CC0, KayKit).
## Грид 4-метровых ячеек. Три темы по биому главы: crypt (кладка и факелы),
## cave (рваные пещеры, камни и светящиеся грибы), catacombs (плотный лабиринт
## маленьких комнат со знамёнами). Структура: цепочка комнат + петли, секретная
## комната за расшатанной кладкой, решётка перед залом босса (ключ у мини-босса),
## ниша наград у зала босса (выбор одного из двух трофеев).

const CELL := 4.0
const GRID := 15  # 15x15 ячеек = 60x60 метров

# Рецепты тем: количество/размер комнат, петли, свет, реквизит.
const THEMES := {
	"crypt": {
		"rooms_min": 5, "rooms_max": 7, "size_min": 2, "size_max": 4,
		"loops": 1, "torch_every": 4, "torch_max": 22, "blob": false,
		"floor": "dungeon/floor_tile_large.gltf.glb", "walls_visible": true,
		"props": ["dungeon/barrel_large.gltf.glb", "dungeon/crates_stacked.gltf.glb", "dungeon/table_medium.gltf.glb"],
		"mushrooms": 0, "ambient": Color(0.35, 0.36, 0.45),
	},
	"cave": {
		"rooms_min": 4, "rooms_max": 6, "size_min": 2, "size_max": 4,
		"loops": 1, "torch_every": 6, "torch_max": 12, "blob": true,
		"floor": "dungeon/floor_dirt_large.gltf.glb", "walls_visible": false,
		"props": ["dungeon/trunk_medium_A.gltf.glb", "dungeon/rubble_large.gltf.glb", "dungeon/trunk_small_B.gltf.glb"],
		"mushrooms": 3, "ambient": Color(0.3, 0.42, 0.38),
	},
	"catacombs": {
		"rooms_min": 7, "rooms_max": 9, "size_min": 2, "size_max": 3,
		"loops": 2, "torch_every": 3, "torch_max": 26, "blob": false,
		"floor": "dungeon/floor_tile_small.gltf.glb", "walls_visible": true,
		"props": ["dungeon/crates_stacked.gltf.glb", "dungeon/banner_thin_red.gltf.glb", "dungeon/trunk_small_A.gltf.glb"],
		"mushrooms": 0, "ambient": Color(0.4, 0.34, 0.3),
	},
}

# Тема — по биому главы: путешествие меняет и подземелья, не только поверхность.
const BIOME_THEMES := {"meadow": "crypt", "autumn": "cave", "winter": "catacombs", "night": "catacombs"}


static func _cell_pos(gx: int, gz: int) -> Vector3:
	return Vector3((gx - GRID / 2.0 + 0.5) * CELL, 0, (gz - GRID / 2.0 + 0.5) * CELL)


static func build(parent: Node3D, zone_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_seed
	var theme_id: String = BIOME_THEMES.get(Net.biome, "crypt")
	var t: Dictionary = THEMES[theme_id]
	var obstacles: Array = []

	# --- тёмное окружение: без неба и солнца, свет — факелы ---
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = t.ambient
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
	var n_rooms: int = rng.randi_range(t.rooms_min, t.rooms_max)
	for _try in 240:
		if rooms.size() >= n_rooms:
			break
		var w: int = rng.randi_range(t.size_min, t.size_max)
		var h: int = rng.randi_range(t.size_min, t.size_max)
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

	# вход — первая комната; босс — самая дальняя от входа, ПЕРЕНОСИТСЯ в конец
	# цепочки: тогда в зал босса ведёт ровно один коридор — его и запираем.
	var entry: Dictionary = rooms[0]
	var boss_i := 0
	var best_d := 0.0
	for i in rooms.size():
		var d: float = entry.center.distance_to(rooms[i].center)
		if d > best_d:
			best_d = d
			boss_i = i
	var boss_room: Dictionary = rooms[boss_i]
	rooms.remove_at(boss_i)
	rooms.append(boss_room)

	# мини-босс — комната посередине цепочки (не вход и не зал босса)
	var mini_room: Dictionary = rooms[maxi(1, rooms.size() / 2 - 1)]

	# --- коридоры: последовательное Г-образное соединение ---
	var corridor_cells: Array = []
	var carve := func(a: Dictionary, c: Dictionary) -> void:
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
	for i in range(rooms.size() - 1):
		carve.call(rooms[i], rooms[i + 1])
	# петли: пара дополнительных связей между НЕсоседними комнатами (без зала
	# босса — у него должен остаться единственный запираемый вход)
	for _l in int(t.loops):
		if rooms.size() < 4:
			break
		var ia := rng.randi_range(0, rooms.size() - 4)
		var ib := ia + 2
		carve.call(rooms[ia], rooms[ib])

	var dirs4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	# --- секретная комната: пристройка 2x2 за расшатанной кладкой.
	# Требование к месту честное, но не избыточное: своим ячейкам нельзя
	# ОРТОгонально касаться чужого пола (иначе второй открытый вход), а
	# диагональные соседи безвредны — стены ставятся только по ортогонали. ---
	var secret := {}
	var attach_list: Array = floor_cells.keys()
	for _try in 400:
		# сперва просторная пристройка 2x2; в тесноте — чулан 1x1. Цепляемся
		# к ЛЮБОЙ ячейке пола (комната или коридор): в плотных катакомбах
		# у стен комнат может просто не остаться свободного кармана.
		var sw := 2 if _try < 200 else 1
		var attach: Vector2i = attach_list[rng.randi_range(0, attach_list.size() - 1)]
		var d: Vector2i = dirs4[rng.randi_range(0, 3)]
		var neck: Vector2i = attach + d
		var perp := Vector2i(absi(d.y), absi(d.x))
		var shift: int = rng.randi_range(-(sw - 1), 0)
		var own: Dictionary = {neck: true}
		for i in sw:
			for j in sw:
				own[neck + d * (1 + i) + perp * (j + shift)] = true
		var ok := true
		for cc in own:
			if cc.x < 1 or cc.y < 1 or cc.x > GRID - 2 or cc.y > GRID - 2 or floor_cells.has(cc):
				ok = false
				break
			for nd in dirs4:
				var nb: Vector2i = cc + nd
				if own.has(nb):
					continue
				if cc == neck and nb == attach:
					continue # единственный разрешённый контакт: вход из пола
				if floor_cells.has(nb):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		for cc in own:
			floor_cells[cc] = true
		# сама кладка: между перешейком и полом-хозяином
		var np := _cell_pos(neck.x, neck.y)
		var wpos := Vector3(np.x - d.x * CELL * 0.5, 0, np.z - d.y * CELL * 0.5)
		var wrot := 0.0 if d.y != 0 else PI * 0.5
		var base: Vector2i = neck + d
		var s_center := _cell_pos(base.x, base.y) \
			+ Vector3(d.x + perp.x * shift, 0, d.y + perp.y * shift) * (CELL * 0.5 * (sw - 1))
		secret = {"x": wpos.x, "z": wpos.z, "rot": wrot, "center": s_center, "cells": own}
		break

	# пещеры: рваные края — комнаты обрастают случайными ячейками по периметру
	# (после тайника: блобам нельзя прилипать к нему — открылся бы второй вход)
	if t.blob:
		var scells: Dictionary = secret.get("cells", {})
		for r in rooms:
			for _b in r.w * r.h:
				var bside := rng.randi_range(0, 3)
				var bx: int = r.gx + (rng.randi_range(0, r.w - 1) if bside < 2 else (-1 if bside == 2 else r.w))
				var bz: int = r.gz + (rng.randi_range(0, r.h - 1) if bside >= 2 else (-1 if bside == 0 else r.h))
				if bx < 1 or bz < 1 or bx > GRID - 2 or bz > GRID - 2:
					continue
				var bc := Vector2i(bx, bz)
				var near_secret := scells.has(bc)
				for d in dirs4:
					if scells.has(bc + d):
						near_secret = true
						break
				if near_secret:
					continue
				floor_cells[bc] = true

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
		var tile := WorldGen.place_prop(parent, t.floor, Vector3(p.x, 0.0, p.z), 0.0, 1.0)
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
			if t.walls_visible:
				var wall_model := "dungeon/wall.gltf.glb" if wall_i % 4 != 0 else "dungeon/wall_cracked.gltf.glb"
				WorldGen.place_prop(parent, wall_model, wall_pos, rot, 1.0)
			else:
				# пещера: границы — груды камней, а не кладка
				var in_dir := Vector3(-d.x, 0, -d.y)
				for k in 2:
					var off: float = (float(k) - 0.5) * 2.0
					var rp := wall_pos + Vector3(-in_dir.z, 0, in_dir.x) * off + in_dir * 0.35
					WgLib._rock(parent, rng, rp.x, rp.z, rng.randf_range(0.8, 1.3), false)
			# коллайдер стены (в пещере невидимый — камни лишь декор)
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
			# факел с настоящим светом (частота — от темы)
			if wall_i % int(t.torch_every) == 1 and torch_lights < int(t.torch_max):
				torch_lights += 1
				var in_dir2 := Vector3(-d.x, 0, -d.y)
				var tpos := wall_pos + in_dir2 * 0.55
				var torch := WorldGen.place_prop(parent, "dungeon/torch_mounted.gltf.glb", Vector3(tpos.x, 1.8, tpos.z), rot, 1.0)
				var tl := OmniLight3D.new()
				tl.light_color = Color(1.0, 0.62, 0.25)
				tl.light_energy = 1.4
				tl.omni_range = 8.0
				tl.position.y = 0.9
				torch.add_child(tl)

	# пещера: светящиеся грибы дополняют редкие факелы
	if int(t.mushrooms) > 0:
		for r in rooms:
			for _m in rng.randi_range(1, int(t.mushrooms)):
				var mx: float = r.center.x + rng.randf_range(-r.w * CELL * 0.35, r.w * CELL * 0.35)
				var mz: float = r.center.z + rng.randf_range(-r.h * CELL * 0.35, r.h * CELL * 0.35)
				WgLib._mushroom(parent, rng, mx, mz, rng.randf_range(1.0, 1.6), true)

	# --- секретная кладка (после стен: она поверх дверного проёма) ---
	var secret_node: Node3D = null
	var secret_body: StaticBody3D = null
	if not secret.is_empty():
		secret_node = WorldGen.place_prop(parent, "dungeon/wall_cracked.gltf.glb", Vector3(secret.x, 0, secret.z), secret.rot, 1.0)
		secret_body = StaticBody3D.new()
		secret_body.collision_layer = 1
		secret_body.collision_mask = 0
		var sshape := CollisionShape3D.new()
		var sbox := BoxShape3D.new()
		sbox.size = Vector3(CELL, 4.0, 1.0)
		sshape.shape = sbox
		secret_body.add_child(sshape)
		parent.add_child(secret_body)
		secret_body.global_position = Vector3(secret.x, 2.0, secret.z)
		secret_body.rotation.y = secret.rot
		secret["node"] = secret_node
		secret["body"] = secret_body
		# внутри: сундук и горка монет
		WorldGen.place_prop(parent, "dungeon/coin_stack_medium.gltf.glb", secret.center + Vector3(0.9, 0, 0.6), rng.randf_range(0, TAU), 1.2)

	# --- решётка перед залом босса: единственный вход в последнюю комнату ---
	var door := {}
	for cell in floor_cells:
		if not door.is_empty():
			break
		# ячейка коридора, примыкающая к границе зала босса
		if cell.x >= boss_room.gx and cell.x < boss_room.gx + boss_room.w \
				and cell.y >= boss_room.gz and cell.y < boss_room.gz + boss_room.h:
			continue
		for d in dirs:
			var nb2: Vector2i = cell + d
			if nb2.x >= boss_room.gx and nb2.x < boss_room.gx + boss_room.w \
					and nb2.y >= boss_room.gz and nb2.y < boss_room.gz + boss_room.h \
					and floor_cells.has(nb2):
				var p2 := _cell_pos(cell.x, cell.y)
				var dpos := Vector3(p2.x + d.x * CELL * 0.5, 0, p2.z + d.y * CELL * 0.5)
				var drot := 0.0 if d.y != 0 else PI * 0.5
				var dnode := WorldGen.place_prop(parent, "dungeon/wall_doorway.glb", dpos, drot, 1.0)
				var dbody := StaticBody3D.new()
				dbody.collision_layer = 1
				dbody.collision_mask = 0
				var dshape := CollisionShape3D.new()
				var dbox := BoxShape3D.new()
				dbox.size = Vector3(CELL, 4.0, 1.0)
				dshape.shape = dbox
				dbody.add_child(dshape)
				parent.add_child(dbody)
				dbody.global_position = Vector3(dpos.x, 2.0, dpos.z)
				dbody.rotation.y = drot
				door = {"x": dpos.x, "z": dpos.z, "node": dnode, "body": dbody}
				break

	# --- реквизит в комнатах ---
	var chest_spots: Array = []
	if not secret.is_empty():
		chest_spots.append(secret.center) # тайник вознаграждает сундуком
	for ri in rooms.size():
		var r: Dictionary = rooms[ri]
		var is_entry: bool = r == entry
		var is_boss: bool = r == boss_room
		if not is_entry and not is_boss:
			# сундук в дальних комнатах — исследование вознаграждается
			if chest_spots.size() < 4 and rng.randf() < 0.7:
				var cpos: Vector3 = r.center + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
				chest_spots.append(cpos)
		for _p in rng.randi_range(0, 2):
			var px: float = r.center.x + rng.randf_range(-(r.w - 1) * CELL * 0.4, (r.w - 1) * CELL * 0.4)
			var pz: float = r.center.z + rng.randf_range(-(r.h - 1) * CELL * 0.4, (r.h - 1) * CELL * 0.4)
			if Vector2(px - r.center.x, pz - r.center.z).length() < 1.5:
				continue # центр комнаты держим свободным
			var props: Array = t.props
			WorldGen.place_prop(parent, props[rng.randi() % props.size()], Vector3(px, 0, pz), rng.randf_range(0, TAU), 1.0)
			WorldGen._static_cylinder(parent, px, pz, 0.7, 1.6)
			obstacles.append({"x": px, "z": pz, "r": 0.7})

	# --- зал босса: знамёна, золото и ниша наград (выбор одного из двух).
	# Центр зала держим пустым (r >= 3.2): там встаёт портал наружу — арка не
	# должна врастать в реквизит ---
	WorldGen.place_prop(parent, "dungeon/banner_patternA_red.gltf.glb", boss_room.center + Vector3(0, 0, -(boss_room.h * CELL * 0.5) + 0.8), 0.0, 1.0)
	WorldGen.place_prop(parent, "dungeon/coin_stack_medium.gltf.glb", boss_room.center + Vector3(3.4, 0, 2.2), rng.randf_range(0, TAU), 1.2)
	WorldGen.place_prop(parent, "dungeon/trunk_large_A.gltf.glb", boss_room.center + Vector3(-3.5, 0, 2.4), rng.randf_range(0, TAU), 1.1)
	var reward_spots: Array = [
		boss_room.center + Vector3(-1.6, 0, -(boss_room.h * CELL * 0.5) + 1.8),
		boss_room.center + Vector3(1.6, 0, -(boss_room.h * CELL * 0.5) + 1.8),
	]
	for spot in reward_spots:
		WorldGen.place_prop(parent, "dungeon/torch_lit.gltf.glb", spot + Vector3(0, 0, -0.7), 0.0, 1.0)

	# --- взрывные бочки (D1): пара в комнатах — рискованное подспорье в бою ---
	var barrels: Array = []
	for _b in 2:
		for _try in 20:
			var br: Dictionary = rooms[rng.randi_range(1, maxi(1, rooms.size() - 2))]
			var bx: float = br.center.x + rng.randf_range(-(br.w - 1) * CELL * 0.35, (br.w - 1) * CELL * 0.35)
			var bz: float = br.center.z + rng.randf_range(-(br.h - 1) * CELL * 0.35, (br.h - 1) * CELL * 0.35)
			if Vector2(bx - br.center.x, bz - br.center.z).length() < 1.5 or not WgGeom._clear_of(obstacles, bx, bz, 0.6, 0.5):
				continue
			barrels.append(WgCores.explosive_barrel(parent, rng, bx, bz))
			obstacles.append({"x": bx, "z": bz, "r": 0.6})
			break

	# --- ловушки: шипы в коридорах + жаровни (огонь жжётся сильнее) ---
	var traps: Array = []
	if corridor_cells.size() > 4:
		for _t2 in rng.randi_range(1, 2):
			var tc: Vector2i = corridor_cells[rng.randi_range(2, corridor_cells.size() - 1)]
			var tp := _cell_pos(tc.x, tc.y)
			WorldGen.place_prop(parent, "dungeon/floor_tile_big_spikes.glb", Vector3(tp.x, 0.05, tp.z), 0.0, 1.0)
			traps.append({"x": tp.x, "z": tp.z, "r": 1.8, "dmg": 6})
		# жаровня: открытый огонь посреди коридора — уважай или обходи
		var bc: Vector2i = corridor_cells[rng.randi_range(0, corridor_cells.size() - 1)]
		var bp := _cell_pos(bc.x, bc.y)
		var brazier := WorldGen.place_prop(parent, "dungeon/torch_lit.gltf.glb", Vector3(bp.x, 0, bp.z), 0.0, 1.3)
		var bl := OmniLight3D.new()
		bl.light_color = Color(1.0, 0.5, 0.15)
		bl.light_energy = 1.6
		bl.omni_range = 7.0
		bl.position.y = 1.4
		brazier.add_child(bl)
		traps.append({"x": bp.x, "z": bp.z, "r": 1.2, "dmg": 10})

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
		"chest_spots": chest_spots, "traps": traps, "theme": theme_id,
		"secret": secret, "door": door, "miniboss_spot": mini_room.center,
		"reward_spots": reward_spots, "barrels": barrels}
