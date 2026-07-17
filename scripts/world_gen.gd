class_name WorldGen
extends RefCounted
## Процедурная арена: биомы, детализация (трава, цветы, брёвна, атмосферные
## частицы), домики гномов с дверями, отдельная ПвП-арена с руинами,
## навигационная сетка. Детерминирована сидом.

const WORLD_RADIUS := 58.0
const OVERWORLD_RADIUS := 120.0  # сюжетный мир-путешествие (арена волн/ПвП остаётся 58)

const BIOME_LIST := ["meadow", "winter", "autumn", "night"]

const BIOMES := {
	"meadow": {
		"title": "Поляна",
		"ground": Color(0.36, 0.54, 0.27),
		"leaves": [Color(0.25, 0.44, 0.2), Color(0.29, 0.49, 0.22), Color(0.21, 0.4, 0.17)],
		"sky_top": Color(0.35, 0.55, 0.78), "sky_hor": Color(0.7, 0.8, 0.88),
		"fog": Color(0.62, 0.72, 0.82), "fog_d": 0.006,
		"sun": Color(1.0, 0.95, 0.85), "sun_e": 1.35, "sun_rot": Vector3(-48, 35, 0),
		"ambient": 1.0, "mushrooms": 40,
		"grass": 550, "grass_color": Color(0.3, 0.5, 0.22),
		"particles": "pollen", "start_time": 0.3,
	},
	"winter": {
		"title": "Зимний лес",
		"ground": Color(0.82, 0.86, 0.9),
		"leaves": [Color(0.2, 0.35, 0.28), Color(0.75, 0.82, 0.86), Color(0.26, 0.42, 0.34)],
		"sky_top": Color(0.5, 0.62, 0.75), "sky_hor": Color(0.82, 0.86, 0.9),
		"fog": Color(0.8, 0.85, 0.9), "fog_d": 0.011,
		"sun": Color(0.9, 0.95, 1.0), "sun_e": 1.1, "sun_rot": Vector3(-30, 50, 0),
		"ambient": 1.1, "mushrooms": 10,
		"grass": 90, "grass_color": Color(0.55, 0.5, 0.35),
		"particles": "snow", "start_time": 0.33,
	},
	"autumn": {
		"title": "Осенний лес",
		"ground": Color(0.5, 0.42, 0.2),
		"leaves": [Color(0.75, 0.4, 0.12), Color(0.72, 0.55, 0.15), Color(0.6, 0.25, 0.1)],
		"sky_top": Color(0.45, 0.5, 0.65), "sky_hor": Color(0.9, 0.75, 0.55),
		"fog": Color(0.85, 0.72, 0.55), "fog_d": 0.009,
		"sun": Color(1.0, 0.85, 0.6), "sun_e": 1.2, "sun_rot": Vector3(-25, 20, 0),
		"ambient": 0.9, "mushrooms": 55,
		"grass": 380, "grass_color": Color(0.55, 0.45, 0.18),
		"particles": "leaves", "start_time": 0.68,
		"tree_models": ["halloween/tree_pine_orange_large.gltf", "halloween/tree_pine_orange_medium.gltf", "halloween/tree_pine_yellow_large.gltf"],
	},
	"night": {
		"title": "Ночь",
		"ground": Color(0.16, 0.24, 0.14),
		"leaves": [Color(0.1, 0.2, 0.12), Color(0.13, 0.24, 0.14), Color(0.08, 0.17, 0.1)],
		"sky_top": Color(0.26, 0.34, 0.52), "sky_hor": Color(0.48, 0.52, 0.62),
		"fog": Color(0.3, 0.36, 0.46), "fog_d": 0.011,
		"sun": Color(0.8, 0.85, 1.0), "sun_e": 0.9, "sun_rot": Vector3(-55, -20, 0),
		"ambient": 1.4, "mushrooms": 45,
		"grass": 260, "grass_color": Color(0.12, 0.22, 0.13),
		"particles": "fireflies", "start_time": 0.86,
		"tree_models": ["halloween/tree_dead_large.gltf", "halloween/tree_dead_medium.gltf"],
	},
}


static var _prop_cache: Dictionary = {}


static func prop_scene(path: String) -> PackedScene:
	if not _prop_cache.has(path):
		_prop_cache[path] = load("res://models/%s" % path)
	return _prop_cache[path]


static func place_prop(parent: Node3D, path: String, pos: Vector3, rot_y: float, s: float, coll_r := 0.0, coll_h := 3.0) -> Node3D:
	var node: Node3D = prop_scene(path).instantiate()
	parent.add_child(node)
	node.global_position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * s
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if coll_r > 0.0:
		_static_cylinder(parent, pos.x, pos.z, coll_r, coll_h)
	return node


## Лист (фигурный меш с изломом по центру, а не квадрат)
static var _leaf_meshes: Dictionary = {}


static func leaf_mesh(color: Color) -> ArrayMesh:
	if _leaf_meshes.has(color):
		return _leaf_meshes[color]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# контур листа: остриё, две боковые дуги, черешок; лёгкий сгиб по жилке
	var pts := [
		Vector3(0, 0, 0.16),           # остриё
		Vector3(0.055, 0.012, 0.06),
		Vector3(0.07, 0.016, -0.03),
		Vector3(0.035, 0.01, -0.11),
		Vector3(0, 0, -0.15),          # черешок
		Vector3(-0.035, 0.01, -0.11),
		Vector3(-0.07, 0.016, -0.03),
		Vector3(-0.055, 0.012, 0.06),
	]
	var mid := Vector3(0, 0.022, 0.0)  # жилка приподнята — лист «сложен»
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		st.add_vertex(mid)
		st.add_vertex(a)
		st.add_vertex(b)
	st.generate_normals()
	var mesh := st.commit()
	var m := _mat(color)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	_leaf_meshes[color] = mesh
	return mesh


## Огранённый кристалл (шестигранная бипирамида), а не примитив
static var _crystal_mesh: ArrayMesh = null


static func crystal_mesh() -> ArrayMesh:
	if _crystal_mesh != null:
		return _crystal_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 0.62, 0)
	var bottom := Vector3(0, -0.1, 0)
	var ring_hi: Array = []
	var ring_lo: Array = []
	for i in 6:
		var a := float(i) / 6.0 * TAU
		ring_hi.append(Vector3(cos(a) * 0.16, 0.34, sin(a) * 0.16))
		ring_lo.append(Vector3(cos(a + 0.26) * 0.2, 0.08, sin(a + 0.26) * 0.2))
	for i in 6:
		var j := (i + 1) % 6
		# вершинные грани
		st.add_vertex(top); st.add_vertex(ring_hi[j]); st.add_vertex(ring_hi[i])
		# пояс (две грани)
		st.add_vertex(ring_hi[i]); st.add_vertex(ring_hi[j]); st.add_vertex(ring_lo[j])
		st.add_vertex(ring_hi[i]); st.add_vertex(ring_lo[j]); st.add_vertex(ring_lo[i])
		# нижние грани
		st.add_vertex(ring_lo[i]); st.add_vertex(ring_lo[j]); st.add_vertex(bottom)
	st.generate_normals()
	_crystal_mesh = st.commit()
	return _crystal_mesh


static func _mat(color: Color, flat := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if flat:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m


static func _static_cylinder(parent: Node, x: float, z: float, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	shape.shape = cyl
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = Vector3(x, h * 0.5, z)


## Дальность прорисовки декоративной растительности: на большом оверворлде
## сотни деревьев за пределами этого радиуса не рисуются вовсе.
const DETAIL_VIS_RANGE := 95.0


static func _tree(parent: Node, rng: RandomNumberGenerator, b: Dictionary, x: float, z: float, s: float, with_collision: bool) -> void:
	# полноценные glb-деревья, если у биома они назначены
	if b.has("tree_models"):
		var prop := place_prop(parent, b.tree_models[rng.randi() % b.tree_models.size()],
			Vector3(x, 0, z), rng.randf_range(0, TAU), s * 1.55)
		for mi in prop.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_end = DETAIL_VIS_RANGE
			mi.visibility_range_end_margin = 8.0
		if with_collision:
			_static_cylinder(parent, x, z, 0.55 * s, 3.0)
		return
	var g := Node3D.new()
	parent.add_child(g)
	g.global_position = Vector3(x, 0, z)
	g.rotation.y = rng.randf_range(0, TAU)

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.22 * s
	tm.bottom_radius = 0.32 * s
	tm.height = 1.6 * s
	tm.radial_segments = 8
	trunk.mesh = tm
	trunk.material_override = _mat(Color(0.42, 0.29, 0.18))
	trunk.position.y = 0.8 * s
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	trunk.visibility_range_end = DETAIL_VIS_RANGE
	trunk.visibility_range_end_margin = 8.0
	g.add_child(trunk)

	var leaves: Array = b.leaves
	var y := 1.5 * s
	var r := 1.5 * s
	for i in 3:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = r
		cm.height = 1.7 * s
		cm.radial_segments = 8
		cone.mesh = cm
		var base_c: Color = leaves[rng.randi() % leaves.size()]
		cone.material_override = _mat(base_c.lightened(rng.randf_range(0.0, 0.08)))
		cone.position.y = y + 0.85 * s
		cone.rotation.y = rng.randf_range(0, TAU)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		cone.visibility_range_end = DETAIL_VIS_RANGE
		cone.visibility_range_end_margin = 8.0
		g.add_child(cone)
		y += 1.0 * s
		r *= 0.72

	if with_collision:
		_static_cylinder(parent, x, z, 0.55 * s, 3.0)


static func _rock(parent: Node, rng: RandomNumberGenerator, x: float, z: float, s: float, with_collision: bool) -> void:
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = s
	sm.height = s * 1.5
	sm.radial_segments = 7
	sm.rings = 4
	rock.mesh = sm
	var grays := [Color(0.54, 0.55, 0.56), Color(0.48, 0.49, 0.5), Color(0.58, 0.57, 0.54)]
	rock.material_override = _mat(grays[rng.randi() % grays.size()], true)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rock.visibility_range_end = DETAIL_VIS_RANGE
	rock.visibility_range_end_margin = 8.0
	parent.add_child(rock)
	rock.global_position = Vector3(x, s * 0.4, z)
	rock.rotation = Vector3(rng.randf_range(0, 0.5), rng.randf_range(0, TAU), rng.randf_range(0, 0.5))
	rock.scale = Vector3(1.0, rng.randf_range(0.6, 0.85), rng.randf_range(0.8, 1.1))
	if with_collision:
		_static_cylinder(parent, x, z, s * 0.85, s * 1.4)


static func _mushroom(parent: Node, rng: RandomNumberGenerator, x: float, z: float, s: float, glowing := false) -> Node3D:
	var g := Node3D.new()
	parent.add_child(g)
	g.global_position = Vector3(x, 0, z)

	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.08 * s
	sm.bottom_radius = 0.11 * s
	sm.height = 0.3 * s
	stem.mesh = sm
	stem.material_override = _mat(Color(0.91, 0.87, 0.78))
	stem.position.y = 0.15 * s
	g.add_child(stem)

	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.2 * s
	cm.height = 0.22 * s
	cap.mesh = cm
	if glowing:
		var m := _mat(Color(0.3, 0.9, 0.85))
		m.emission_enabled = true
		m.emission = Color(0.2, 0.9, 0.8)
		m.emission_energy_multiplier = 1.6
		cap.material_override = m
	else:
		var reds := [Color(0.75, 0.22, 0.17), Color(0.83, 0.33, 0.0), Color(0.66, 0.2, 0.15)]
		cap.material_override = _mat(reds[rng.randi() % reds.size()])
	cap.position.y = 0.32 * s
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(cap)
	return g


## Светящийся кристалл-баф: гранёный кластер (центральный + два малых).
static func crystal(parent: Node, color: Color) -> Node3D:
	var g := Node3D.new()
	parent.add_child(g)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.1
	m.roughness = 0.25
	m.metallic = 0.15
	for cfg in [[Vector3.ZERO, Vector3.ZERO, 1.0], [Vector3(0.16, 0, 0.06), Vector3(0.05, 0.6, -0.35), 0.55], [Vector3(-0.14, 0, -0.08), Vector3(-0.3, 1.9, 0.28), 0.45]]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = crystal_mesh()
		mesh.material_override = m
		mesh.position = cfg[0] + Vector3(0, 0.12, 0)
		mesh.rotation = cfg[1]
		mesh.scale = Vector3.ONE * cfg[2]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(mesh)
	return g


static func _house(parent: Node, x: float, z: float) -> Dictionary:
	var g := Node3D.new()
	parent.add_child(g)
	g.global_position = Vector3(x, 0, z)
	g.rotation.y = atan2(-x, -z)

	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.5
	bm.bottom_radius = 1.7
	bm.height = 1.6
	bm.radial_segments = 12
	base.mesh = bm
	base.material_override = _mat(Color(0.48, 0.33, 0.21))
	base.position.y = 0.8
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(base)

	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 2.1
	rm.height = 1.8
	rm.radial_segments = 12
	roof.mesh = rm
	roof.material_override = _mat(Color(0.7, 0.25, 0.18))
	roof.position.y = 2.5
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.add_child(roof)

	# труба с дымком
	var chimney := MeshInstance3D.new()
	var chm := CylinderMesh.new()
	chm.top_radius = 0.14
	chm.bottom_radius = 0.16
	chm.height = 0.7
	chimney.mesh = chm
	chimney.material_override = _mat(Color(0.4, 0.38, 0.36))
	chimney.position = Vector3(0.8, 2.9, 0)
	g.add_child(chimney)
	var smoke := GPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 3.0
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 10.0
	spm.initial_velocity_min = 0.4
	spm.initial_velocity_max = 0.7
	spm.gravity = Vector3(0.15, 0.1, 0)
	spm.scale_min = 0.5
	spm.scale_max = 1.4
	spm.color = Color(0.85, 0.85, 0.85, 0.35)
	smoke.process_material = spm
	var sdm := SphereMesh.new()
	sdm.radius = 0.14
	sdm.height = 0.28
	sdm.radial_segments = 6
	sdm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sdm.material = smat
	smoke.draw_pass_1 = sdm
	smoke.position = Vector3(0.8, 3.3, 0)
	g.add_child(smoke)

	# окошко (ночью светится и подсвечивает двор)
	var window := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.22
	wm.bottom_radius = 0.22
	wm.height = 0.05
	window.mesh = wm
	var wmat := _mat(Color(1.0, 0.85, 0.45))
	wmat.emission_enabled = true
	wmat.emission = Color(1.0, 0.75, 0.35)
	wmat.emission_energy_multiplier = 1.2
	window.material_override = wmat
	window.rotation_degrees = Vector3(0, 0, 90)
	window.position = Vector3(1.55, 1.0, 0.5)
	window.rotation.y = 0.35
	g.add_child(window)
	var wl := OmniLight3D.new()
	wl.light_color = Color(1.0, 0.75, 0.4)
	wl.light_energy = 0.0 # включается с наступлением темноты (группа night_light)
	wl.omni_range = 5.0
	wl.position = Vector3(1.9, 1.2, 0.6)
	wl.add_to_group("night_light")
	g.add_child(wl)

	# дверь на петле
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.35, 0, 1.58)
	g.add_child(hinge)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.7, 1.0, 0.08)
	door.mesh = dm
	door.material_override = _mat(Color(0.29, 0.2, 0.12))
	door.position = Vector3(0.35, 0.5, 0)
	hinge.add_child(door)

	_static_cylinder(parent, x, z, 2.0, 4.0)

	var dir := Vector2(sin(g.rotation.y), cos(g.rotation.y))
	return {"x": x, "z": z, "dirx": dir.x, "dirz": dir.y, "door": hinge}


## Рассыпает N экземпляров меша по кольцу арены (MultiMesh — дёшево).
## Если coll_r > 0, на каждый инстанс ставится коллизия (например сугробы,
## которые визуально читаются как камни — иначе враги и игрок проходят сквозь).
static func _scatter(parent: Node3D, rng: RandomNumberGenerator, mesh: Mesh, count: int,
		r_min: float, r_max: float, s_min: float, s_max: float, y := 0.0,
		coll_r := 0.0, obstacles: Array = []) -> void:
	if count <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(r_min, r_max)
		var s := rng.randf_range(s_min, s_max)
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s, s))
		var x := cos(a) * r
		var z := sin(a) * r
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		if coll_r > 0.0:
			_static_cylinder(parent, x, z, coll_r * s, 1.0)
			obstacles.append({"x": x, "z": z, "r": coll_r * s})
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)


## Точки интереса: заметные рукотворные ориентиры, а не только случайный лес.
## Каждая — со своей коллизией (попадает в obstacles) и записью в pois
## (игра потом даёт с ней взаимодействовать: осмотреть лор, получить благословение).
static func _build_pois(parent: Node3D, rng: RandomNumberGenerator, biome_id: String, obstacles: Array, pois: Array) -> void:
	var kinds := ["ruins", "standing_stones", "shrine", "campfire", "well", "bounty_board", "crypt", "battlefield"]
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var count := 4
	for i in count:
		var pos := Vector3.INF
		for _try in 40:
			var a := rng.randf_range(0, TAU)
			var r := rng.randf_range(16.0, WORLD_RADIUS - 8.0)
			var x := cos(a) * r
			var z := sin(a) * r
			if Vector2(x - 6.0, z - 6.0).length() > 12.0 and _far_from(obstacles, x, z, 9.0):
				pos = Vector3(x, 0, z)
				break
		if pos == Vector3.INF:
			continue
		var kind: String = kinds[i]
		match kind:
			"ruins":
				_poi_ruins(parent, rng, pos, obstacles)
			"standing_stones":
				_poi_standing_stones(parent, rng, pos, obstacles)
			"shrine":
				_poi_shrine(parent, rng, pos, obstacles)
			"campfire":
				_poi_campfire(parent, rng, pos, obstacles)
			"well":
				_poi_well(parent, rng, pos, obstacles)
			"bounty_board":
				_poi_bounty_board(parent, rng, pos, obstacles)
			"crypt":
				_poi_crypt(parent, rng, pos, obstacles)
			"battlefield":
				_poi_battlefield(parent, rng, pos, obstacles)
		pois.append({"kind": kind, "x": pos.x, "z": pos.z})


## Обрушенная сторожевая башня — три просевших каменных яруса и завал у подножья.
## Обрушенная сторожевая башня — настоящие обломки колонн вокруг завала
## щебня, а не аккуратно составленные друг на друга цилиндры.
static func _poi_ruins(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	place_prop(parent, "dungeon/rubble_large.gltf.glb", pos, rng.randf_range(0, TAU), 0.55)
	var n := 4
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(1.6, 2.4)
		var cpos := Vector3(pos.x + cos(a) * r, 0, pos.z + sin(a) * r)
		var col := place_prop(parent, "dungeon/pillar_decorated.gltf.glb", cpos, rng.randf_range(0, TAU), rng.randf_range(0.5, 0.85))
		# часть колонн обрушена набок, часть ещё стоит — читается как настоящие руины
		if rng.randf() < 0.5:
			col.rotation.x = rng.randf_range(1.0, 1.5)
			col.position.y = 0.3
	_rock(parent, rng, pos.x + 1.8, pos.z + 1.2, 1.1, false)
	_rock(parent, rng, pos.x - 1.6, pos.z - 1.4, 0.9, false)
	_static_cylinder(parent, pos.x, pos.z, 2.3, 2.0)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 2.3})


## Кольцо древних менгиров со слабым рунным свечением — привет "Осколкам Сердца Горы".
static func _poi_standing_stones(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var n := 6
	var ring_r := 2.6
	for i in n:
		var a := TAU * float(i) / n
		var sx := pos.x + cos(a) * ring_r
		var sz := pos.z + sin(a) * ring_r
		var stone := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, rng.randf_range(2.0, 2.8), 0.32)
		stone.mesh = bm
		var mat := _mat(Color(0.4, 0.42, 0.46), true)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.75, 1.0)
		mat.emission_energy_multiplier = 0.5
		stone.material_override = mat
		stone.position = Vector3(sx, bm.size.y * 0.5, sz)
		stone.rotation.y = a + PI * 0.5 + rng.randf_range(-0.08, 0.08)
		stone.rotation.z = rng.randf_range(-0.05, 0.05)
		parent.add_child(stone)
		_static_cylinder(parent, sx, sz, 0.3, bm.size.y)
		obstacles.append({"x": sx, "z": sz, "r": 0.3})
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.45, 0.75, 1.0)
	glow.light_energy = 0.7
	glow.omni_range = ring_r + 3.0
	glow.position = Vector3(pos.x, 1.2, pos.z)
	parent.add_child(glow)


## Каменное святилище с жаровней — путникам есть где передохнуть у огня.
static func _poi_shrine(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var dais := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.8
	dm.bottom_radius = 2.0
	dm.height = 0.3
	dm.radial_segments = 12
	dais.mesh = dm
	dais.material_override = _mat(Color(0.55, 0.53, 0.5), true)
	dais.position = Vector3(pos.x, 0.15, pos.z)
	parent.add_child(dais)

	var brazier := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.4
	bm.bottom_radius = 0.25
	bm.height = 0.9
	brazier.mesh = bm
	brazier.material_override = _mat(Color(0.3, 0.28, 0.26), true)
	brazier.position = Vector3(pos.x, 0.75, pos.z)
	parent.add_child(brazier)

	var fire := GPUParticles3D.new()
	fire.amount = 18
	fire.lifetime = 0.75
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 14.0
	fm.initial_velocity_min = 0.8
	fm.initial_velocity_max = 1.8
	fm.gravity = Vector3(0, 1.4, 0)
	fm.scale_min = 0.4
	fm.scale_max = 1.1
	fm.color = Color(1.0, 0.55, 0.15)
	fire.process_material = fm
	var fdm := SphereMesh.new()
	fdm.radius = 0.08
	fdm.height = 0.16
	fdm.radial_segments = 6
	fdm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fdm.material = fmat
	fire.draw_pass_1 = fdm
	fire.position = Vector3(pos.x, 1.2, pos.z)
	parent.add_child(fire)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 1.3
	light.omni_range = 7.0
	light.position = Vector3(pos.x, 1.3, pos.z)
	parent.add_child(light)

	for side in [-1.0, 1.0]:
		place_prop(parent, "dungeon/torch_lit.gltf.glb", pos + Vector3(side * 1.4, 0, 1.1), rng.randf_range(0, TAU), 1.1)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		_rock(parent, rng, pos.x + cos(a) * 2.4, pos.z + sin(a) * 2.4, rng.randf_range(0.5, 0.7), false)
	_static_cylinder(parent, pos.x, pos.z, 1.9, 0.6)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.9})


## Походный костёр — настоящие поленья под огнём и брёвна-сиденья вокруг.
static func _poi_campfire(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var logs := ["dungeon/trunk_small_A.gltf.glb", "dungeon/trunk_small_B.gltf.glb", "dungeon/trunk_small_C.gltf.glb"]
	for i in 5:
		var a := TAU * float(i) / 5.0
		var lpos := Vector3(pos.x + cos(a) * 0.4, 0.05, pos.z + sin(a) * 0.4)
		var log_ := place_prop(parent, logs[i % logs.size()], lpos, rng.randf_range(0, TAU), 1.3)
		log_.rotation.x = PI * 0.5  # поленья лежат под огнём, а не стоят пеньками

	var fire := GPUParticles3D.new()
	fire.amount = 22
	fire.lifetime = 0.7
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 16.0
	fm.initial_velocity_min = 0.7
	fm.initial_velocity_max = 1.6
	fm.gravity = Vector3(0, 1.3, 0)
	fm.scale_min = 0.35
	fm.scale_max = 0.95
	fm.color = Color(1.0, 0.5, 0.12)
	fire.process_material = fm
	var fdm := SphereMesh.new()
	fdm.radius = 0.07
	fdm.height = 0.14
	fdm.radial_segments = 6
	fdm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fdm.material = fmat
	fire.draw_pass_1 = fdm
	fire.position = Vector3(pos.x, 0.4, pos.z)
	parent.add_child(fire)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 1.1
	light.omni_range = 6.0
	light.position = Vector3(pos.x, 0.6, pos.z)
	parent.add_child(light)

	for i in 3:
		var seat := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.25
		sm.bottom_radius = 0.28
		sm.height = 0.4
		seat.mesh = sm
		seat.material_override = _mat(Color(0.3, 0.24, 0.16), true)
		var a2 := rng.randf_range(0, TAU)
		seat.position = Vector3(pos.x + cos(a2) * 1.5, 0.2, pos.z + sin(a2) * 1.5)
		parent.add_child(seat)
	_static_cylinder(parent, pos.x, pos.z, 1.3, 0.6)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.3})


## Старый колодец с навесом — можно испить воды и подлечиться в дороге.
static func _poi_well(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.05
	rm.height = 0.8
	ring.mesh = rm
	ring.material_override = _mat(Color(0.5, 0.48, 0.44), true)
	ring.position = Vector3(pos.x, 0.4, pos.z)
	parent.add_child(ring)

	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.85
	wm.bottom_radius = 0.85
	wm.height = 0.05
	water.mesh = wm
	var watmat := _mat(Color(0.15, 0.35, 0.5), true)
	watmat.metallic = 0.3
	watmat.roughness = 0.1
	water.material_override = watmat
	water.position = Vector3(pos.x, 0.78, pos.z)
	parent.add_child(water)

	var roof_mat := _mat(Color(0.35, 0.22, 0.12), true)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.07
		pm.bottom_radius = 0.09
		pm.height = 2.0
		post.mesh = pm
		post.material_override = roof_mat
		post.position = Vector3(pos.x, 1.0, pos.z + side * 0.9)
		parent.add_child(post)
	var roof := MeshInstance3D.new()
	var rfm := CylinderMesh.new()
	rfm.top_radius = 0.05
	rfm.bottom_radius = 1.15
	rfm.height = 0.55
	rfm.radial_segments = 4
	roof.mesh = rfm
	roof.material_override = roof_mat
	roof.position = Vector3(pos.x, 2.05, pos.z)
	roof.rotation.y = PI * 0.25
	parent.add_child(roof)

	_static_cylinder(parent, pos.x, pos.z, 1.1, 0.8)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.1})


## Доска объявлений — заказ на элитного гнома за особую награду.
static func _poi_bounty_board(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.18, 2.0, 0.18)
	post.mesh = pm
	post.material_override = _mat(Color(0.34, 0.24, 0.15), true)
	post.position = Vector3(pos.x, 1.0, pos.z)
	parent.add_child(post)

	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.9, 0.08)
	board.mesh = bm
	board.material_override = _mat(Color(0.42, 0.32, 0.2), true)
	board.position = Vector3(pos.x, 1.75, pos.z)
	board.rotation.y = rng.randf_range(0, TAU)
	parent.add_child(board)

	for i in 3:
		var pin := MeshInstance3D.new()
		var pnm := BoxMesh.new()
		pnm.size = Vector3(0.35, 0.22, 0.02)
		pin.mesh = pnm
		pin.material_override = _mat(Color(0.85, 0.8, 0.7), true)
		pin.position = board.position + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.25, 0.25), 0.06)
		pin.rotation.y = board.rotation.y
		parent.add_child(pin)

	place_prop(parent, "dungeon/torch_lit.gltf.glb", pos + Vector3(0.9, 0, 0.3), rng.randf_range(0, TAU), 1.0)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.75, 0.3)
	glow.light_energy = 0.55
	glow.omni_range = 3.5
	glow.position = Vector3(pos.x, 1.75, pos.z)
	parent.add_child(glow)

	# коллизия и резерв места под точку совпадают (было 0.6 против 0.9) —
	# столб доски перекрывает свою же зону, без «сквозного» края
	_static_cylinder(parent, pos.x, pos.z, 0.9, 2.0)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 0.9})


## Полуразрушенная гробница — настоящая каменная арка входа с обрушенными
## стенами и заваленным нутром, а не примитивная коробка.
static func _poi_crypt(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var facing := rng.randf_range(0, TAU)
	var fwd := Vector2(sin(facing), cos(facing))
	place_prop(parent, "dungeon/wall_arched.gltf.glb", pos, facing, 1.0)
	for side in [-1.0, 1.0]:
		var side_pos := pos + Vector3(fwd.y * side * 1.05, 0, -fwd.x * side * 1.05)
		place_prop(parent, "dungeon/wall_broken.gltf.glb", side_pos, facing + PI * 0.5, 0.85)
	place_prop(parent, "dungeon/rubble_large.gltf.glb", pos - Vector3(fwd.x, 0, fwd.y) * 1.6, rng.randf_range(0, TAU), 0.4)
	for i in 2:
		var col_pos := pos + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
		var col := place_prop(parent, "dungeon/column.gltf.glb", col_pos, rng.randf_range(0, TAU), 1.0)
		col.rotation.x = rng.randf_range(0.15, 0.4)  # завалившаяся колонна, не идеально ровная

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.35, 0.5, 0.4)
	glow.light_energy = 0.4
	glow.omni_range = 4.5
	glow.position = Vector3(pos.x, 0.6, pos.z)
	parent.add_child(glow)

	for i in 3:
		_rock(parent, rng, pos.x + rng.randf_range(-2.6, 2.6), pos.z + rng.randf_range(-2.6, 2.6), rng.randf_range(0.4, 0.6), false)
	_static_cylinder(parent, pos.x, pos.z, 2.3, 2.5)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 2.3})


## Старое поле боя — покосившееся знамя и обломки клинков среди щебня.
static func _poi_battlefield(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var banner := place_prop(parent, "dungeon/banner_thin_red.gltf.glb", pos, rng.randf_range(0, TAU), 1.0)
	banner.rotation.z = rng.randf_range(-0.15, 0.15)  # клонится набок, не стоит по стойке смирно

	for i in 4:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(1.0, 2.6)
		var wpos := Vector3(pos.x + cos(a) * r, 0, pos.z + sin(a) * r)
		var sword := place_prop(parent, "dungeon/sword_shield_broken.gltf.glb", wpos, rng.randf_range(0, TAU), 0.85)
		sword.rotation.x = rng.randf_range(0.9, 1.5)  # большинство лежит поваленными, не воткнуто
	place_prop(parent, "dungeon/rubble_large.gltf.glb", pos + Vector3(1.6, 0, -1.2), rng.randf_range(0, TAU), 0.35)
	_static_cylinder(parent, pos.x, pos.z, 1.6, 1.0)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.6})


## Трава, цветы, кусты, брёвна, пни — детализация арены.
static func _build_details(parent: Node3D, rng: RandomNumberGenerator, b: Dictionary, biome_id: String, obstacles: Array, radius := WORLD_RADIUS) -> void:
	# травинки (конусы)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.045
	blade.height = 0.34
	blade.radial_segments = 4
	blade.rings = 1
	blade.material = _mat(b.grass_color)
	_scatter(parent, rng, blade, int(b.grass), 3.0, radius - 1.5, 0.7, 1.5, 0.15)

	# кусты
	var bush := SphereMesh.new()
	bush.radius = 0.55
	bush.height = 0.7
	bush.radial_segments = 8
	bush.rings = 4
	bush.material = _mat((b.leaves[0] as Color).lightened(0.05))
	_scatter(parent, rng, bush, 22, 6.0, radius - 2.0, 0.6, 1.4, 0.1)

	match biome_id:
		"meadow":
			for fc in [Color(1, 1, 0.85), Color(1.0, 0.8, 0.3), Color(0.95, 0.5, 0.6), Color(0.7, 0.6, 1.0)]:
				var flower := SphereMesh.new()
				flower.radius = 0.06
				flower.height = 0.12
				flower.radial_segments = 6
				flower.rings = 3
				var fm := _mat(fc)
				fm.emission_enabled = true
				fm.emission = fc
				fm.emission_energy_multiplier = 0.25
				flower.material = fm
				_scatter(parent, rng, flower, 26, 3.0, radius - 2.0, 0.8, 1.4, 0.28)
		"autumn":
			# опавшие листья — фигурные, с центральной жилкой
			_scatter(parent, rng, leaf_mesh(Color(0.8, 0.45, 0.12)), 260, 3.0, radius - 1.0, 1.0, 2.2, 0.01)
			_scatter(parent, rng, leaf_mesh(Color(0.62, 0.25, 0.1)), 200, 3.0, radius - 1.0, 1.0, 2.0, 0.01)
			_scatter(parent, rng, leaf_mesh(Color(0.72, 0.55, 0.15)), 150, 3.0, radius - 1.0, 1.0, 2.0, 0.01)
		"winter":
			# сугробы
			var mound := SphereMesh.new()
			mound.radius = 0.7
			mound.height = 0.5
			mound.radial_segments = 8
			mound.rings = 4
			mound.material = _mat(Color(0.92, 0.95, 1.0))
			_scatter(parent, rng, mound, 40, 4.0, radius - 1.5, 0.6, 1.8, 0.0, 0.6, obstacles)
		"night":
			# светящиеся грибочки
			for i in 40:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(4.0, radius - 2.0)
				_mushroom(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.5, 1.0), true)
			# старый погост: надгробия и черепа
			var graves := ["halloween/grave_A.gltf", "halloween/grave_B.gltf", "halloween/gravemarker_A.gltf"]
			for i in 12:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(9.0, radius - 4.0)
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				if Vector2(p.x - 6.0, p.z - 6.0).length() > 7.0:
					place_prop(parent, graves[rng.randi() % graves.size()], p, rng.randf_range(0, TAU), rng.randf_range(0.9, 1.3), 0.45, 1.4)
					obstacles.append({"x": p.x, "z": p.z, "r": 0.45})
			for i in 9:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(5.0, radius - 3.0)
				place_prop(parent, "halloween/skull.gltf", Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0, TAU), rng.randf_range(0.7, 1.1))
			# тыквы-светильники подсвечивают тропы
			for i in 8:
				var a := rng.randf_range(0, TAU)
				var r := rng.randf_range(7.0, radius - 4.0)
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				var pumpkin := place_prop(parent, "halloween/pumpkin_orange_jackolantern.gltf", p, rng.randf_range(0, TAU), rng.randf_range(1.0, 1.5), 0.35, 1.2)
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
		log_mesh.material_override = _mat(Color(0.38, 0.27, 0.17))
		parent.add_child(log_mesh)
		log_mesh.global_position = Vector3(x, 0.3, z)
		log_mesh.rotation = Vector3(PI * 0.5, rng.randf_range(0, TAU), 0)
		log_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_static_cylinder(parent, x, z, 0.8, 0.6)
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
		stump.material_override = _mat(Color(0.45, 0.32, 0.2))
		parent.add_child(stump)
		stump.global_position = Vector3(x, 0.25, z)
		stump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_static_cylinder(parent, x, z, 0.45, 0.6)


## Атмосферные частицы биома: пыльца/снег/листопад/светлячки.
static func _ambient_particles(parent: Node3D, kind: String, radius := WORLD_RADIUS) -> void:
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
			p.draw_pass_1 = leaf_mesh(Color(0.85, 0.5, 0.15))
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
		pillar.material_override = _mat(stone, true)
		parent.add_child(pillar)
		pillar.global_position = Vector3(x, pm.height * 0.5, z)
		pillar.rotation.y = rng.randf_range(0, TAU)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_static_cylinder(parent, x, z, 0.6, pm.height)
	# четыре обломка стен по диагоналям
	for i in 4:
		var a := float(i) / 4.0 * TAU + PI / 4.0
		var x := cos(a) * 14.0
		var z := sin(a) * 14.0
		var wall := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(4.0, rng.randf_range(1.2, 2.0), 0.8)
		wall.mesh = wm
		wall.material_override = _mat(stone.darkened(0.1), true)
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
	sun.directional_shadow_max_distance = 90.0
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


static func build(parent: Node3D, world_seed: int, biome_id: String, pvp := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var b: Dictionary = BIOMES.get(biome_id, BIOMES["meadow"])
	var obstacles: Array = []
	var pois: Array = []
	var spawn_points: Array = []
	var houses: Array = []

	var envd := _setup_environment(parent, b)
	var e: Environment = envd.env
	var sun: DirectionalLight3D = envd.sun
	var moon: DirectionalLight3D = envd.moon
	var sky_mat: ShaderMaterial = envd.sky_mat
	_setup_ground(parent, world_seed, b, WORLD_RADIUS)

	# --- лес за границей ---
	for i in 78:
		var a := float(i) / 78.0 * TAU + rng.randf_range(-0.05, 0.05)
		var r := WORLD_RADIUS + rng.randf_range(2.5, 14.0)
		_tree(parent, rng, b, cos(a) * r, sin(a) * r, rng.randf_range(1.1, 1.9), false)

	# --- камни по периметру ---
	for i in 40:
		var a := float(i) / 40.0 * TAU + rng.randf_range(-0.06, 0.06)
		var r := WORLD_RADIUS + rng.randf_range(0.0, 1.5)
		_rock(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.8, 1.5), false)

	if pvp:
		# --- ПвП-арена: руины в центре, симметричные укрытия, без домиков ---
		_build_pvp_ruins(parent, rng)
		for i in 4:
			var a := float(i) / 4.0 * TAU
			var r := 24.0
			_rock(parent, rng, cos(a) * r + rng.randf_range(-2, 2), sin(a) * r + rng.randf_range(-2, 2), rng.randf_range(1.0, 1.6), true)
			_tree(parent, rng, b, cos(a) * r + rng.randf_range(-4, 4), sin(a) * r + rng.randf_range(-4, 4), rng.randf_range(1.0, 1.4), true)
		for i in 4:
			var a := float(i) / 4.0 * TAU + PI / 4.0
			spawn_points.append(Vector3(cos(a) * (WORLD_RADIUS - 8.0), 0, sin(a) * (WORLD_RADIUS - 8.0)))
	else:
		# --- домики гномов ---
		for i in 5:
			var a := float(i) / 5.0 * TAU + 0.4
			var r := WORLD_RADIUS - 7.0
			var x := cos(a) * r
			var z := sin(a) * r
			var house := _house(parent, x, z)
			houses.append(house)
			obstacles.append({"x": x, "z": z, "r": 2.0})
			spawn_points.append(Vector3(x + house.dirx * 2.2, 0, z + house.dirz * 2.2))

		# --- деревья и камни внутри арены ---
		for i in 22:
			var x := 0.0
			var z := 0.0
			var ok := false
			for _try in 30:
				x = rng.randf_range(-WORLD_RADIUS + 6, WORLD_RADIUS - 6)
				z = rng.randf_range(-WORLD_RADIUS + 6, WORLD_RADIUS - 6)
				if Vector2(x, z).length() > 10.0 and Vector2(x - 6.0, z - 6.0).length() > 7.0 and _far_from(obstacles, x, z, 5.0):
					ok = true
					break
			if ok:
				_tree(parent, rng, b, x, z, rng.randf_range(0.9, 1.5), true)
				obstacles.append({"x": x, "z": z, "r": 0.7})

		for i in 16:
			var x := 0.0
			var z := 0.0
			var ok := false
			for _try in 30:
				x = rng.randf_range(-WORLD_RADIUS + 5, WORLD_RADIUS - 5)
				z = rng.randf_range(-WORLD_RADIUS + 5, WORLD_RADIUS - 5)
				if Vector2(x, z).length() > 8.0 and Vector2(x - 6.0, z - 6.0).length() > 7.0 and _far_from(obstacles, x, z, 4.0):
					ok = true
					break
			if ok:
				var s := rng.randf_range(0.6, 1.2)
				_rock(parent, rng, x, z, s, true)
				obstacles.append({"x": x, "z": z, "r": s * 0.9})

		# --- точки интереса: заметные ориентиры, не только случайный лес ---
		if not pvp:
			_build_pois(parent, rng, biome_id, obstacles, pois)

	# --- грибы (декор) ---
	for i in int(b.mushrooms):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(4.0, WORLD_RADIUS - 2.0)
		_mushroom(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.7, 1.6))

	# --- детализация и атмосфера ---
	_build_details(parent, rng, b, biome_id, obstacles)
	_ambient_particles(parent, b.particles)

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


static func _far_from(obstacles: Array, x: float, z: float, min_d: float) -> bool:
	for o in obstacles:
		if Vector2(x - o.x, z - o.z).length() < min_d:
			return false
	return true


# ===========================================================================
# ОВЕРВОРЛД: мир-путешествие для сюжета — лагерь, дорога через области,
# поселение/поле боя/роща, вход в подземелье на дальнем краю.
# ===========================================================================

## Внутри ли точка хоть одной области.
static func _in_area(areas: Array, x: float, z: float, pad := 0.0) -> bool:
	for a in areas:
		if Vector2(x - a.center.x, z - a.center.z).length() < a.radius + pad:
			return true
	return false


## Расстояние до ближайшей точки дороги (для «просек» в лесу).
static func _road_dist(road: Array, x: float, z: float) -> float:
	var best := 1e9
	for w in road:
		best = minf(best, Vector2(x - w.x, z - w.z).length())
	return best


## Дорога из тайлов path_A-D вдоль ломаной (плавная кривая через вейпоинты).
static func _lay_road(parent: Node3D, rng: RandomNumberGenerator, pts: Array) -> Array:
	var tiles := ["halloween/path_A.gltf", "halloween/path_B.gltf", "halloween/path_C.gltf", "halloween/path_D.gltf"]
	var samples: Array = []
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var seg_len: float = Vector2(c.x - a.x, c.z - a.z).length()
		var steps := maxi(1, int(seg_len / 1.7))
		for s in steps:
			var t := float(s) / steps
			samples.append(a.lerp(c, t))
	samples.append(pts[pts.size() - 1])
	for i in samples.size():
		var p: Vector3 = samples[i]
		var tile := place_prop(parent, tiles[rng.randi() % tiles.size()], Vector3(p.x, 0.02, p.z), rng.randf_range(0, TAU), rng.randf_range(0.95, 1.15))
		# дорога — плоский декор: тени и коллизия не нужны
		for mi in tile.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return samples


## Линия забора поперёк дороги с воротами arch_gate над самой дорогой.
static func _fence_gate_line(parent: Node3D, rng: RandomNumberGenerator, gate_pos: Vector3, dir_angle: float, half_len: float, obstacles: Array) -> void:
	var across := dir_angle + PI * 0.5
	var gate := place_prop(parent, "halloween/arch_gate.gltf", gate_pos, across, 1.35)
	for mi in gate.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# сами ворота — проходные (без коллизии), забор по бокам — с коллизией
	var fences := ["halloween/fence.gltf", "halloween/fence.gltf", "halloween/fence_broken.gltf"]
	var seg := 4.0 * 1.1
	for side in [-1.0, 1.0]:
		var n := int(half_len / seg)
		for i in range(1, n + 1):
			var off: float = (3.2 + (i - 0.5) * seg) * side
			var fx: float = gate_pos.x + cos(across) * off
			var fz: float = gate_pos.z + sin(across) * off
			place_prop(parent, fences[rng.randi() % fences.size()], Vector3(fx, 0, fz), across, 1.1)
			_static_box(parent, fx, fz, across, seg, 2.0, 0.4)
			obstacles.append({"x": fx, "z": fz, "r": 1.6})


## Тонкий коллайдер-бокс (для заборов) — прямоугольный, повёрнутый.
static func _static_box(parent: Node3D, x: float, z: float, rot_y: float, len_: float, h: float, thick: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(len_, h, thick)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = Vector3(x, h * 0.5, z)
	body.rotation.y = rot_y


## Лесной пояс: плотные деревья в кольцевой полосе, с просветом вдоль дороги.
static func _forest_belt(parent: Node3D, rng: RandomNumberGenerator, b: Dictionary, r_min: float, r_max: float, count: int, road: Array, areas: Array, obstacles: Array) -> void:
	for i in count:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(r_min, r_max)
		var x := cos(a) * r
		var z := sin(a) * r
		if _road_dist(road, x, z) < 5.0:
			continue # просека вдоль дороги
		if _in_area(areas, x, z, 2.0):
			continue # внутри областей лес не сеем
		var with_coll := (i % 2 == 0) # коллизия через одно дерево: навмеш легче, лес всё равно труднопроходим
		_tree(parent, rng, b, x, z, rng.randf_range(1.0, 1.7), with_coll)
		if with_coll:
			obstacles.append({"x": x, "z": z, "r": 0.7})


## Сюжетный оверворлд. Возвращает тот же словарь, что и build(), плюс
## "areas" (список областей) и "road" (вейпоинты дороги).
static func build_overworld(parent: Node3D, world_seed: int, biome_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var b: Dictionary = BIOMES.get(biome_id, BIOMES["meadow"])
	var obstacles: Array = []
	var pois: Array = []
	var spawn_points: Array = []
	var houses: Array = []
	var R := OVERWORLD_RADIUS

	var envd := _setup_environment(parent, b)
	_setup_ground(parent, world_seed, b, R)

	# --- планировка: главное направление дороги и области вдоль неё ---
	var road_a := rng.randf_range(0, TAU)
	var dirv := Vector3(cos(road_a), 0, sin(road_a))
	var sidev := Vector3(-dirv.z, 0, dirv.x)

	var areas: Array = []
	areas.append({"id": "camp", "kind": "camp", "center": Vector3(6, 0, 6), "radius": 22.0})
	var settle_c: Vector3 = dirv * 52.0 + sidev * rng.randf_range(-8.0, 8.0)
	areas.append({"id": "settlement", "kind": "settlement", "center": settle_c, "radius": 20.0})
	var side_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var battle_c: Vector3 = dirv * 78.0 + sidev * (30.0 * side_sign)
	areas.append({"id": "battlefield", "kind": "battlefield", "center": battle_c, "radius": 21.0})
	var grove_c: Vector3 = dirv * 74.0 - sidev * (32.0 * side_sign)
	areas.append({"id": "grove", "kind": "grove", "center": grove_c, "radius": 19.0})
	var approach_c: Vector3 = dirv * 100.0
	areas.append({"id": "approach", "kind": "approach", "center": approach_c, "radius": 17.0})

	# --- дорога: лагерь -> поселение -> развилка -> подход к подземелью ---
	var fork: Vector3 = dirv * 72.0
	var road_pts := [Vector3(6, 0, 6), dirv * 26.0, settle_c, fork, approach_c]
	var road := _lay_road(parent, rng, road_pts)
	# боковые тропы к полю боя и роще
	road += _lay_road(parent, rng, [fork, battle_c])
	road += _lay_road(parent, rng, [fork, grove_c])

	# --- ворота на дороге: границы поясов ---
	_fence_gate_line(parent, rng, dirv * 33.0, road_a, 14.0, obstacles)
	_fence_gate_line(parent, rng, dirv * 88.0, road_a, 12.0, obstacles)

	# --- вход в подземелье: крипта с аркой на дальнем краю ---
	var crypt_pos: Vector3 = approach_c + dirv * 8.0
	var crypt := place_prop(parent, "halloween/crypt.gltf", crypt_pos, road_a + PI, 1.25)
	for mi in crypt.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_static_cylinder(parent, crypt_pos.x, crypt_pos.z, 4.5, 6.0)
	obstacles.append({"x": crypt_pos.x, "z": crypt_pos.z, "r": 4.5})
	var dungeon_entrance: Vector3 = crypt_pos - dirv * 5.5
	place_prop(parent, "halloween/lantern_standing.gltf", dungeon_entrance + sidev * 2.0, rng.randf_range(0, TAU), 1.2)
	place_prop(parent, "halloween/lantern_standing.gltf", dungeon_entrance - sidev * 2.0, rng.randf_range(0, TAU), 1.2)

	# --- домики гномов по областям (спавны врагов) ---
	for area in areas:
		if area.kind in ["camp"]:
			continue
		var n_houses := 3 if area.kind != "approach" else 2
		for i in n_houses:
			var ha := rng.randf_range(0, TAU)
			var hr: float = area.radius * rng.randf_range(0.45, 0.8)
			var hx: float = area.center.x + cos(ha) * hr
			var hz: float = area.center.z + sin(ha) * hr
			if not _far_from(obstacles, hx, hz, 6.0) or _road_dist(road, hx, hz) < 4.0:
				continue
			var house := _house(parent, hx, hz)
			house["area"] = area.id
			houses.append(house)
			obstacles.append({"x": hx, "z": hz, "r": 2.0})
			spawn_points.append(Vector3(hx + house.dirx * 2.2, 0, hz + house.dirz * 2.2))

	# --- фонари вдоль дороги (ориентиры в сумерках) ---
	for i in range(6, road.size(), 24):
		var p: Vector3 = road[i]
		var lp := place_prop(parent, "halloween/post_lantern.gltf", Vector3(p.x, 0, p.z) + sidev * 1.8, road_a + PI * 0.5, 1.1)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.75, 0.4)
		ll.light_energy = 0.0
		ll.omni_range = 6.0
		ll.position.y = 2.2
		ll.add_to_group("night_light")
		lp.add_child(ll)

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
			for _try in 40:
				var pa := rng.randf_range(0, TAU)
				var pr: float = area.radius * rng.randf_range(0.3, 0.85)
				var px: float = area.center.x + cos(pa) * pr
				var pz: float = area.center.z + sin(pa) * pr
				if Vector2(px - 6.0, pz - 6.0).length() > 12.0 and _far_from(obstacles, px, pz, 9.0) and _road_dist(road, px, pz) > 4.0:
					pos = Vector3(px, 0, pz)
					break
			if pos == Vector3.INF:
				continue
			match kind:
				"ruins": _poi_ruins(parent, rng, pos, obstacles)
				"standing_stones": _poi_standing_stones(parent, rng, pos, obstacles)
				"shrine": _poi_shrine(parent, rng, pos, obstacles)
				"campfire": _poi_campfire(parent, rng, pos, obstacles)
				"well": _poi_well(parent, rng, pos, obstacles)
				"bounty_board": _poi_bounty_board(parent, rng, pos, obstacles)
				"crypt": _poi_crypt(parent, rng, pos, obstacles)
				"battlefield": _poi_battlefield(parent, rng, pos, obstacles)
			pois.append({"kind": kind, "x": pos.x, "z": pos.z})

	# --- лесные пояса: между лагерем и серединой, между серединой и краем ---
	_forest_belt(parent, rng, b, 26.0, 40.0, 90, road, areas, obstacles)
	_forest_belt(parent, rng, b, 58.0, 92.0, 150, road, areas, obstacles)
	# лес за границей мира
	for i in 70:
		var a := float(i) / 70.0 * TAU + rng.randf_range(-0.05, 0.05)
		var r := R + rng.randf_range(2.5, 14.0)
		_tree(parent, rng, b, cos(a) * r, sin(a) * r, rng.randf_range(1.2, 2.0), false)

	# --- редкие деревья/камни внутри областей ---
	for area in areas:
		if area.kind == "camp":
			continue
		for i in 4:
			var ta := rng.randf_range(0, TAU)
			var tr: float = area.radius * rng.randf_range(0.4, 0.9)
			var tx: float = area.center.x + cos(ta) * tr
			var tz: float = area.center.z + sin(ta) * tr
			if _far_from(obstacles, tx, tz, 5.0) and _road_dist(road, tx, tz) > 4.0:
				_tree(parent, rng, b, tx, tz, rng.randf_range(0.9, 1.4), true)
				obstacles.append({"x": tx, "z": tz, "r": 0.7})
		for i in 3:
			var ra := rng.randf_range(0, TAU)
			var rr: float = area.radius * rng.randf_range(0.4, 0.9)
			var rx: float = area.center.x + cos(ra) * rr
			var rz: float = area.center.z + sin(ra) * rr
			if _far_from(obstacles, rx, rz, 4.0) and _road_dist(road, rx, rz) > 3.0:
				var s := rng.randf_range(0.6, 1.2)
				_rock(parent, rng, rx, rz, s, true)
				obstacles.append({"x": rx, "z": rz, "r": s * 0.9})

	# --- грибы, детализация, атмосфера (по большому радиусу) ---
	for i in int(b.mushrooms * 1.6):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(4.0, R - 2.0)
		_mushroom(parent, rng, cos(a) * r, sin(a) * r, rng.randf_range(0.7, 1.6))
	_build_details(parent, rng, b, biome_id, obstacles, R)
	_ambient_particles(parent, b.particles, R)

	# --- навигационная сетка (как в build) ---
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
		"areas": areas, "road": road_pts, "dungeon_entrance": dungeon_entrance}
