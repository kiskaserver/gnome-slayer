class_name WgLib
extends RefCounted
## Примитивы мира: пропы (кэш сцен), деревья/камни/грибы/кристаллы,
## домики гномов, меши листвы, материалы, статик-коллайдеры, скаттер.


static var _prop_cache: Dictionary = {}


static func prop_scene(path: String) -> PackedScene:
	if not _prop_cache.has(path):
		_prop_cache[path] = load("res://models/%s" % path)
	return _prop_cache[path]


static func place_prop(parent: Node3D, path: String, pos: Vector3, rot_y: float, s: float, coll_r := 0.0, coll_h := 3.0, vis_range := 0.0) -> Node3D:
	var node: Node3D = prop_scene(path).instantiate()
	parent.add_child(node)
	node.global_position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * s
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if vis_range > 0.0:
			mi.visibility_range_end = vis_range
			mi.visibility_range_end_margin = 8.0
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


static func _tree(parent: Node, rng: RandomNumberGenerator, b: Dictionary, x: float, z: float, s: float, with_collision: bool, shadows := true) -> void:
	# полноценные glb-деревья, если у биома они назначены
	if b.has("tree_models"):
		var prop := place_prop(parent, b.tree_models[rng.randi() % b.tree_models.size()],
			Vector3(x, 0, z), rng.randf_range(0, TAU), s * 1.55, 0.0, 3.0, WorldGen.DETAIL_VIS_RANGE)
		if not shadows:
			for mi in prop.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trunk.visibility_range_end = WorldGen.DETAIL_VIS_RANGE
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
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.visibility_range_end = WorldGen.DETAIL_VIS_RANGE
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
	rock.visibility_range_end = WorldGen.DETAIL_VIS_RANGE
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
