class_name WgGeom
extends RefCounted
## Геометрия размещения: дороги, ворота, заборы, фонари, поселение,
## лесной пояс, проверки удалённости/пересечений.


static func _far_from(obstacles: Array, x: float, z: float, min_d: float) -> bool:
	for o in obstacles:
		if Vector2(x - o.x, z - o.z).length() < min_d:
			return false
	return true


## Клиренс по СУММЕ радиусов: объект радиуса r не пересекает ни один obstacle
## (учитывает радиус каждого препятствия + зазор). Именно это не даёт зданиям
## налезать друг на друга и на дома/крипту.
static func _clear_of(obstacles: Array, x: float, z: float, r: float, gap := 1.0) -> bool:
	for o in obstacles:
		if Vector2(x - o.x, z - o.z).length() < float(o.get("r", 0.0)) + r + gap:
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
		var tile := WgLib.place_prop(parent, tiles[rng.randi() % tiles.size()], Vector3(p.x, 0.02, p.z),
			rng.randf_range(0, TAU), rng.randf_range(0.95, 1.15), 0.0, 3.0, WorldGen.DETAIL_VIS_RANGE)
		# дорога — плоский декор: тени и коллизия не нужны
		for mi in tile.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return samples


## Поворот, при котором ЛОКАЛЬНАЯ ось X модели ложится вдоль мирового
## направления (dx, dz). rotation.y = θ маппит X в (cos θ, -sin θ), поэтому
## для направления (cos a, sin a) нужен θ = -a — иначе модели «ёлочкой».
static func _yaw_along(dir_angle: float) -> float:
	return -dir_angle


## Ворота arch_gate: прячем створки (arch_gate_left/right), оставляя открытый
## каменный проём — иначе дорога визуально перегорожена закрытыми дверьми.
static func _open_gate(gate: Node3D) -> void:
	for leaf in ["arch_gate_left", "arch_gate_right", "fence_gate_left", "fence_gate_right"]:
		for n in gate.find_children(leaf, "", true, false):
			n.visible = false


## Линия забора поперёк дороги с открытыми воротами над самой дорогой.
## dir_angle — направление движения по дороге; забор ставится перпендикулярно,
## оставляя в центре проём под ширину дороги.
static func _fence_gate_line(parent: Node3D, rng: RandomNumberGenerator, gate_pos: Vector3, dir_angle: float, half_len: float, obstacles: Array) -> void:
	var across := dir_angle + PI * 0.5
	var yaw := _yaw_along(across)
	var gate := WgLib.place_prop(parent, "halloween/arch_gate.gltf", gate_pos, yaw, 1.35)
	_open_gate(gate)
	for mi in gate.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# проём под дорогу; забор по бокам — с коллизией. Секции слегка внахлёст.
	var fences := ["halloween/fence.gltf", "halloween/fence.gltf", "halloween/fence_broken.gltf"]
	var flen := 4.0 * 1.1
	var seg := flen * 0.96
	var gap := 3.4 # половина ширины проёма
	for side in [-1.0, 1.0]:
		var n := int(half_len / seg)
		for i in range(1, n + 1):
			var off: float = (gap + (i - 0.5) * seg) * side
			var fx: float = gate_pos.x + cos(across) * off
			var fz: float = gate_pos.z + sin(across) * off
			WgLib.place_prop(parent, fences[rng.randi() % fences.size()], Vector3(fx, 0, fz), yaw, 1.1)
			WgLib._static_box(parent, fx, fz, yaw, flen, 2.0, 0.4)
			obstacles.append({"x": fx, "z": fz, "r": 1.6})


## Ворота вдоль дороги в открытых промежутках между областями (макс. 2).
static func _place_gates(parent: Node3D, rng: RandomNumberGenerator, samples: Array, areas: Array, obstacles: Array) -> void:
	var placed := 0
	var last_i := -100
	var i := 8
	while i < samples.size() - 4 and placed < 2:
		var p: Vector3 = samples[i]
		if _in_area(areas, p.x, p.z, 4.0) or (i - last_i) < 16:
			i += 1
			continue
		var tan: Vector3 = samples[i + 1] - samples[i - 1]
		tan.y = 0
		if tan.length() < 0.01:
			i += 1
			continue
		_fence_gate_line(parent, rng, Vector3(p.x, 0, p.z), atan2(tan.z, tan.x), 11.0, obstacles)
		placed += 1
		last_i = i
		i += 1


## Застройка поселения кольцом вокруг площади с гарантированным клиренсом:
## здания не налезают друг на друга, на дорогу и на уже расставленное.
static func _place_settlement(parent: Node3D, rng: RandomNumberGenerator, center: Vector3, road: Array, obstacles: Array) -> void:
	var defs := [
		{"m": "medieval/building_tavern_green.gltf", "r": 3.6},
		{"m": "medieval/building_market_green.gltf", "r": 3.8},
		{"m": "medieval/building_blacksmith_green.gltf", "r": 3.2},
		{"m": "medieval/building_home_A_green.gltf", "r": 2.4},
		{"m": "medieval/building_home_A_green.gltf", "r": 2.4},
	]
	var n := defs.size()
	var base_ang := rng.randf_range(0, TAU)
	for i in n:
		var d: Dictionary = defs[i]
		for attempt in 40:
			var ang: float = base_ang + TAU * float(i) / n + rng.randf_range(-0.25, 0.25)
			var rad: float = 12.0 + attempt * 1.0
			var bx: float = center.x + cos(ang) * rad
			var bz: float = center.z + sin(ang) * rad
			if not _clear_of(obstacles, bx, bz, d.r, 2.0):
				continue
			if _road_dist(road, bx, bz) < d.r + 2.0:
				continue
			# фасад — к центру площади (локальная +Z смотрит на центр)
			var yaw: float = atan2(center.x - bx, center.z - bz)
			WgLib.place_prop(parent, d.m, Vector3(bx, 0, bz), yaw, 4.0)
			WgLib._static_cylinder(parent, bx, bz, d.r, 5.0)
			obstacles.append({"x": bx, "z": bz, "r": d.r})
			break


## Фонари ВДОЛЬ дороги: смещение по ЛОКАЛЬНОМУ перпендикуляру (а не глобальному),
## поэтому на поворотах и боковых ветках фонарь стоит сбоку, а не на тропе.
static func _place_lanterns(parent: Node3D, rng: RandomNumberGenerator, samples: Array, obstacles: Array) -> void:
	var step := 13
	var i := step
	while i < samples.size() - 1:
		var p: Vector3 = samples[i]
		var tan: Vector3 = samples[mini(samples.size() - 1, i + 1)] - samples[maxi(0, i - 1)]
		tan.y = 0
		if tan.length() < 0.01:
			i += step
			continue
		tan = tan.normalized()
		var perp := Vector3(-tan.z, 0, tan.x)
		# выбираем сторону, где чище (нет здания/POI впритык)
		var side := 1.0
		var ca: Vector3 = p + perp * 2.7
		var cb: Vector3 = p - perp * 2.7
		if not _far_from(obstacles, ca.x, ca.z, 1.6) and _far_from(obstacles, cb.x, cb.z, 1.6):
			side = -1.0
		var pos: Vector3 = p + perp * (2.7 * side)
		if not _far_from(obstacles, pos.x, pos.z, 1.2):
			i += step
			continue
		# фонарь развёрнут «лицом» к дороге (локальная +Z в сторону -perp*side)
		var yaw: float = atan2(-perp.x * side, -perp.z * side)
		var lp := WgLib.place_prop(parent, "halloween/post_lantern.gltf", Vector3(pos.x, 0, pos.z), yaw, 1.1)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.75, 0.4)
		ll.light_energy = 0.0
		ll.omni_range = 6.0
		ll.position.y = 2.2
		ll.add_to_group("night_light")
		lp.add_child(ll)
		obstacles.append({"x": pos.x, "z": pos.z, "r": 0.5})
		i += step


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
		WgLib._tree(parent, rng, b, x, z, rng.randf_range(1.0, 1.7), with_coll, false)
		if with_coll:
			obstacles.append({"x": x, "z": z, "r": 0.7})
