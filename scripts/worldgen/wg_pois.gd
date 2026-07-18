class_name WgPois
extends RefCounted
## Точки интереса: руины, менгиры, алтарь, костёр, колодец, доска
## объявлений, склеп, поле боя. Детерминированы сидом.


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
			var r := rng.randf_range(16.0, WorldGen.WORLD_RADIUS - 8.0)
			var x := cos(a) * r
			var z := sin(a) * r
			if Vector2(x - 6.0, z - 6.0).length() > 12.0 and WgGeom._far_from(obstacles, x, z, 9.0):
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
	WgLib.place_prop(parent, "dungeon/rubble_large.gltf.glb", pos, rng.randf_range(0, TAU), 0.55)
	var n := 4
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(1.6, 2.4)
		var cpos := Vector3(pos.x + cos(a) * r, 0, pos.z + sin(a) * r)
		var col := WgLib.place_prop(parent, "dungeon/pillar_decorated.gltf.glb", cpos, rng.randf_range(0, TAU), rng.randf_range(0.5, 0.85))
		# часть колонн обрушена набок, часть ещё стоит — читается как настоящие руины
		if rng.randf() < 0.5:
			col.rotation.x = rng.randf_range(1.0, 1.5)
			col.position.y = 0.3
	WgLib._rock(parent, rng, pos.x + 1.8, pos.z + 1.2, 1.1, false)
	WgLib._rock(parent, rng, pos.x - 1.6, pos.z - 1.4, 0.9, false)
	WgLib._static_cylinder(parent, pos.x, pos.z, 2.3, 2.0)
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
		var mat := WgLib._mat(Color(0.4, 0.42, 0.46), true)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.75, 1.0)
		mat.emission_energy_multiplier = 0.5
		stone.material_override = mat
		stone.position = Vector3(sx, bm.size.y * 0.5, sz)
		stone.rotation.y = a + PI * 0.5 + rng.randf_range(-0.08, 0.08)
		stone.rotation.z = rng.randf_range(-0.05, 0.05)
		parent.add_child(stone)
		WgLib._static_cylinder(parent, sx, sz, 0.3, bm.size.y)
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
	dais.material_override = WgLib._mat(Color(0.55, 0.53, 0.5), true)
	dais.position = Vector3(pos.x, 0.15, pos.z)
	parent.add_child(dais)

	var brazier := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.4
	bm.bottom_radius = 0.25
	bm.height = 0.9
	brazier.mesh = bm
	brazier.material_override = WgLib._mat(Color(0.3, 0.28, 0.26), true)
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
		WgLib.place_prop(parent, "dungeon/torch_lit.gltf.glb", pos + Vector3(side * 1.4, 0, 1.1), rng.randf_range(0, TAU), 1.1)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		WgLib._rock(parent, rng, pos.x + cos(a) * 2.4, pos.z + sin(a) * 2.4, rng.randf_range(0.5, 0.7), false)
	WgLib._static_cylinder(parent, pos.x, pos.z, 1.9, 0.6)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.9})


## Походный костёр — настоящие поленья под огнём и брёвна-сиденья вокруг.
static func _poi_campfire(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var logs := ["dungeon/trunk_small_A.gltf.glb", "dungeon/trunk_small_B.gltf.glb", "dungeon/trunk_small_C.gltf.glb"]
	for i in 5:
		var a := TAU * float(i) / 5.0
		var lpos := Vector3(pos.x + cos(a) * 0.4, 0.05, pos.z + sin(a) * 0.4)
		var log_ := WgLib.place_prop(parent, logs[i % logs.size()], lpos, rng.randf_range(0, TAU), 1.3)
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
		seat.material_override = WgLib._mat(Color(0.3, 0.24, 0.16), true)
		var a2 := rng.randf_range(0, TAU)
		seat.position = Vector3(pos.x + cos(a2) * 1.5, 0.2, pos.z + sin(a2) * 1.5)
		parent.add_child(seat)
	WgLib._static_cylinder(parent, pos.x, pos.z, 1.3, 0.6)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.3})


## Старый колодец с навесом — можно испить воды и подлечиться в дороге.
static func _poi_well(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.05
	rm.height = 0.8
	ring.mesh = rm
	ring.material_override = WgLib._mat(Color(0.5, 0.48, 0.44), true)
	ring.position = Vector3(pos.x, 0.4, pos.z)
	parent.add_child(ring)

	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.85
	wm.bottom_radius = 0.85
	wm.height = 0.05
	water.mesh = wm
	var watmat := WgLib._mat(Color(0.15, 0.35, 0.5), true)
	watmat.metallic = 0.3
	watmat.roughness = 0.1
	water.material_override = watmat
	water.position = Vector3(pos.x, 0.78, pos.z)
	parent.add_child(water)

	var roof_mat := WgLib._mat(Color(0.35, 0.22, 0.12), true)
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

	WgLib._static_cylinder(parent, pos.x, pos.z, 1.1, 0.8)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.1})


## Доска объявлений — заказ на элитного гнома за особую награду.
static func _poi_bounty_board(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.18, 2.0, 0.18)
	post.mesh = pm
	post.material_override = WgLib._mat(Color(0.34, 0.24, 0.15), true)
	post.position = Vector3(pos.x, 1.0, pos.z)
	parent.add_child(post)

	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.9, 0.08)
	board.mesh = bm
	board.material_override = WgLib._mat(Color(0.42, 0.32, 0.2), true)
	board.position = Vector3(pos.x, 1.75, pos.z)
	board.rotation.y = rng.randf_range(0, TAU)
	parent.add_child(board)

	for i in 3:
		var pin := MeshInstance3D.new()
		var pnm := BoxMesh.new()
		pnm.size = Vector3(0.35, 0.22, 0.02)
		pin.mesh = pnm
		pin.material_override = WgLib._mat(Color(0.85, 0.8, 0.7), true)
		pin.position = board.position + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.25, 0.25), 0.06)
		pin.rotation.y = board.rotation.y
		parent.add_child(pin)

	WgLib.place_prop(parent, "dungeon/torch_lit.gltf.glb", pos + Vector3(0.9, 0, 0.3), rng.randf_range(0, TAU), 1.0)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.75, 0.3)
	glow.light_energy = 0.55
	glow.omni_range = 3.5
	glow.position = Vector3(pos.x, 1.75, pos.z)
	parent.add_child(glow)

	# коллизия и резерв места под точку совпадают (было 0.6 против 0.9) —
	# столб доски перекрывает свою же зону, без «сквозного» края
	WgLib._static_cylinder(parent, pos.x, pos.z, 0.9, 2.0)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 0.9})


## Полуразрушенная гробница — настоящая каменная арка входа с обрушенными
## стенами и заваленным нутром, а не примитивная коробка.
static func _poi_crypt(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var facing := rng.randf_range(0, TAU)
	var fwd := Vector2(sin(facing), cos(facing))
	WgLib.place_prop(parent, "dungeon/wall_arched.gltf.glb", pos, facing, 1.0)
	for side in [-1.0, 1.0]:
		var side_pos := pos + Vector3(fwd.y * side * 1.05, 0, -fwd.x * side * 1.05)
		WgLib.place_prop(parent, "dungeon/wall_broken.gltf.glb", side_pos, facing + PI * 0.5, 0.85)
	WgLib.place_prop(parent, "dungeon/rubble_large.gltf.glb", pos - Vector3(fwd.x, 0, fwd.y) * 1.6, rng.randf_range(0, TAU), 0.4)
	for i in 2:
		var col_pos := pos + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8))
		var col := WgLib.place_prop(parent, "dungeon/column.gltf.glb", col_pos, rng.randf_range(0, TAU), 1.0)
		col.rotation.x = rng.randf_range(0.15, 0.4)  # завалившаяся колонна, не идеально ровная

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.35, 0.5, 0.4)
	glow.light_energy = 0.4
	glow.omni_range = 4.5
	glow.position = Vector3(pos.x, 0.6, pos.z)
	parent.add_child(glow)

	for i in 3:
		WgLib._rock(parent, rng, pos.x + rng.randf_range(-2.6, 2.6), pos.z + rng.randf_range(-2.6, 2.6), rng.randf_range(0.4, 0.6), false)
	WgLib._static_cylinder(parent, pos.x, pos.z, 2.3, 2.5)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 2.3})


## Старое поле боя — покосившееся знамя и обломки клинков среди щебня.
static func _poi_battlefield(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3, obstacles: Array) -> void:
	var banner := WgLib.place_prop(parent, "dungeon/banner_thin_red.gltf.glb", pos, rng.randf_range(0, TAU), 1.0)
	banner.rotation.z = rng.randf_range(-0.15, 0.15)  # клонится набок, не стоит по стойке смирно

	for i in 4:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(1.0, 2.6)
		var wpos := Vector3(pos.x + cos(a) * r, 0, pos.z + sin(a) * r)
		var sword := WgLib.place_prop(parent, "dungeon/sword_shield_broken.gltf.glb", wpos, rng.randf_range(0, TAU), 0.85)
		sword.rotation.x = rng.randf_range(0.9, 1.5)  # большинство лежит поваленными, не воткнуто
	WgLib.place_prop(parent, "dungeon/rubble_large.gltf.glb", pos + Vector3(1.6, 0, -1.2), rng.randf_range(0, TAU), 0.35)
	WgLib._static_cylinder(parent, pos.x, pos.z, 1.6, 1.0)
	obstacles.append({"x": pos.x, "z": pos.z, "r": 1.6})
