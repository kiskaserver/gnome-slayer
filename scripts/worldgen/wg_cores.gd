class_name WgCores
extends RefCounted
## «Ядра» областей (C1): каждая область получает сгруппированную композицию
## из 3-6 объектов с узнаваемым силуэтом — вместо одного POI среди пустоты.
## Плюс тупички-кеши от дороги: короткая тропа к тайнику со сундуком.


## Поселение: рыночные ятки и бочки у площади — жилое место, а не декорации
## по кругу. Здания уже стоят кольцом (WgGeom._place_settlement).
static func _core_settlement(parent: Node3D, rng: RandomNumberGenerator, c: Vector3, road: Array, obstacles: Array) -> void:
	var base := rng.randf_range(0, TAU)
	# две ятки: стол, за ним ящики — читается как прилавок
	for i in 2:
		for _try in 20:
			var a := base + PI * float(i) + rng.randf_range(-0.5, 0.5)
			var r := rng.randf_range(5.5, 8.0)
			var sx := c.x + cos(a) * r
			var sz := c.z + sin(a) * r
			if not WgGeom._clear_of(obstacles, sx, sz, 1.2, 0.8) or WgGeom._road_dist(road, sx, sz) < 2.6:
				continue
			var yaw := atan2(c.x - sx, c.z - sz) # прилавком к площади
			WgLib.place_prop(parent, "dungeon/table_medium.gltf.glb", Vector3(sx, 0, sz), yaw, 1.1)
			var back := Vector2(sx - c.x, sz - c.z).normalized() * 1.3
			WgLib.place_prop(parent, "dungeon/crates_stacked.gltf.glb", Vector3(sx + back.x, 0, sz + back.y), yaw + rng.randf_range(-0.3, 0.3), 0.9)
			WgLib._static_cylinder(parent, sx, sz, 1.1, 1.2)
			obstacles.append({"x": sx, "z": sz, "r": 1.1})
			break
	# бочки у обочины
	for i in 2:
		for _try in 15:
			var a2 := rng.randf_range(0, TAU)
			var r2 := rng.randf_range(6.0, 10.0)
			var bx := c.x + cos(a2) * r2
			var bz := c.z + sin(a2) * r2
			if not WgGeom._clear_of(obstacles, bx, bz, 0.7, 0.6) or WgGeom._road_dist(road, bx, bz) < 2.2:
				continue
			WgLib.place_prop(parent, "dungeon/barrel_large.gltf.glb", Vector3(bx, 0, bz), rng.randf_range(0, TAU), 1.0)
			WgLib._static_cylinder(parent, bx, bz, 0.6, 1.2)
			obstacles.append({"x": bx, "z": bz, "r": 0.6})
			break
	# знамя площади
	for _try in 15:
		var a3 := rng.randf_range(0, TAU)
		var fx := c.x + cos(a3) * 4.0
		var fz := c.z + sin(a3) * 4.0
		if WgGeom._clear_of(obstacles, fx, fz, 0.5, 0.8) and WgGeom._road_dist(road, fx, fz) > 2.0:
			WgLib.place_prop(parent, "dungeon/banner_patternA_red.gltf.glb", Vector3(fx, 0, fz), rng.randf_range(0, TAU), 1.1)
			obstacles.append({"x": fx, "z": fz, "r": 0.5})
			break


## Поле боя: линия сломанных заборов, воткнутые и поваленные клинки, черепа —
## место недавней стычки, а не пустое поле с одним знаменем.
static func _core_battlefield(parent: Node3D, rng: RandomNumberGenerator, c: Vector3, obstacles: Array) -> void:
	var line_a := rng.randf_range(0, TAU)
	var across := Vector2(cos(line_a), sin(line_a))
	# рваная линия обороны из сломанных заборов
	for i in 4:
		var off := (float(i) - 1.5) * 4.2
		var fx := c.x + across.x * off + rng.randf_range(-0.8, 0.8)
		var fz := c.z + across.y * off + rng.randf_range(-0.8, 0.8)
		if not WgGeom._clear_of(obstacles, fx, fz, 1.4, 0.6):
			continue
		var yaw := WgGeom._yaw_along(line_a) + rng.randf_range(-0.2, 0.2)
		WgLib.place_prop(parent, "halloween/fence_broken.gltf", Vector3(fx, 0, fz), yaw, 1.1)
		WgLib._static_box(parent, fx, fz, yaw, 3.6, 1.2, 0.4)
		obstacles.append({"x": fx, "z": fz, "r": 1.4})
	# клинки: часть воткнута (стоит), часть повалена
	for i in 5:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(2.0, 7.5)
		var wx := c.x + cos(a) * r
		var wz := c.z + sin(a) * r
		if not WgGeom._clear_of(obstacles, wx, wz, 0.4, 0.3):
			continue
		var sword := WgLib.place_prop(parent, "dungeon/sword_shield_broken.gltf.glb", Vector3(wx, 0, wz), rng.randf_range(0, TAU), 0.9)
		sword.rotation.x = rng.randf_range(0.05, 0.25) if i % 2 == 0 else rng.randf_range(0.9, 1.5)
	# черепа павших
	for i in 3:
		var a2 := rng.randf_range(0, TAU)
		var r2 := rng.randf_range(1.5, 6.5)
		WgLib.place_prop(parent, "halloween/skull.gltf", Vector3(c.x + cos(a2) * r2, 0.02, c.z + sin(a2) * r2), rng.randf_range(0, TAU), rng.randf_range(0.8, 1.2))


## Роща: плотное кольцо деревьев вокруг поляны со светящимися грибами и
## поваленным стволом — укрытие и ориентир, а не случайный рассев.
static func _core_grove(parent: Node3D, rng: RandomNumberGenerator, b: Dictionary, c: Vector3, obstacles: Array) -> void:
	var n := 7
	var ring := rng.randf_range(5.0, 6.5)
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.18, 0.18)
		var tx := c.x + cos(a) * (ring + rng.randf_range(-0.8, 0.8))
		var tz := c.z + sin(a) * (ring + rng.randf_range(-0.8, 0.8))
		if not WgGeom._clear_of(obstacles, tx, tz, 0.7, 0.5):
			continue
		WgLib._tree(parent, rng, b, tx, tz, rng.randf_range(1.1, 1.5), true)
		obstacles.append({"x": tx, "z": tz, "r": 0.7})
	# поваленный ствол поперёк поляны
	var trunk := WgLib.place_prop(parent, "dungeon/trunk_large_A.gltf.glb", c, rng.randf_range(0, TAU), 1.4)
	trunk.rotation.x = PI * 0.5
	WgLib._static_cylinder(parent, c.x, c.z, 1.2, 0.8)
	obstacles.append({"x": c.x, "z": c.z, "r": 1.2})
	# светящиеся грибы — подсказка, что поляна не пустая
	for i in 6:
		var a2 := rng.randf_range(0, TAU)
		var r2 := rng.randf_range(1.8, 4.5)
		WgLib._mushroom(parent, rng, c.x + cos(a2) * r2, c.z + sin(a2) * r2, rng.randf_range(0.9, 1.5), true)


## Подход к склепу: погост — могилы и надгробья вдоль последнего перегона,
## мёртвые деревья и черепа. Настроение меняется до входа в подземелье.
static func _core_approach(parent: Node3D, rng: RandomNumberGenerator, c: Vector3, dirv: Vector3, sidev: Vector3, obstacles: Array) -> void:
	var graves := ["halloween/grave_A.gltf", "halloween/grave_B.gltf", "halloween/gravemarker_A.gltf"]
	for i in 7:
		var along := rng.randf_range(-9.0, 3.0)
		var side := (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(3.2, 8.0)
		var gx := c.x + dirv.x * along + sidev.x * side
		var gz := c.z + dirv.z * along + sidev.z * side
		if not WgGeom._clear_of(obstacles, gx, gz, 0.6, 0.5):
			continue
		# лицом к дороге
		var yaw := atan2(-sidev.x * signf(side), -sidev.z * signf(side)) + rng.randf_range(-0.15, 0.15)
		WgLib.place_prop(parent, graves[rng.randi() % graves.size()], Vector3(gx, 0, gz), yaw, rng.randf_range(0.95, 1.2))
		WgLib._static_cylinder(parent, gx, gz, 0.45, 1.0)
		obstacles.append({"x": gx, "z": gz, "r": 0.45})
	for i in 2:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(6.0, 11.0)
		var tx := c.x + cos(a) * r
		var tz := c.z + sin(a) * r
		if WgGeom._clear_of(obstacles, tx, tz, 0.8, 0.6):
			WgLib.place_prop(parent, "halloween/tree_dead_medium.gltf", Vector3(tx, 0, tz), rng.randf_range(0, TAU), rng.randf_range(1.1, 1.5), 0.55, 3.0)
			obstacles.append({"x": tx, "z": tz, "r": 0.8})
	for i in 2:
		WgLib.place_prop(parent, "halloween/skull.gltf", Vector3(c.x + rng.randf_range(-6, 6), 0.02, c.z + rng.randf_range(-6, 6)), rng.randf_range(0, TAU), 1.0)


## Тупички-кеши: от магистрали ответвляется короткая тропа к тайнику —
## монеты, бочка и тёплый отблеск. Позицию возвращаем: сервер поставит сундук.
static func _road_caches(parent: Node3D, rng: RandomNumberGenerator, main_samples: Array, areas: Array, obstacles: Array) -> Array:
	var caches: Array = []
	var tries := 0
	var i := 10
	while i < main_samples.size() - 8 and caches.size() < 2 and tries < 40:
		tries += 1
		var p: Vector3 = main_samples[i]
		if WgGeom._in_area(areas, p.x, p.z, 2.0):
			i += 6
			continue
		var tan: Vector3 = main_samples[i + 1] - main_samples[i - 1]
		tan.y = 0
		if tan.length() < 0.01:
			i += 6
			continue
		tan = tan.normalized()
		var perp := Vector3(-tan.z, 0, tan.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var endp: Vector3 = p + perp * rng.randf_range(7.0, 10.0)
		if not WgGeom._clear_of(obstacles, endp.x, endp.z, 1.6, 1.0):
			i += 6
			continue
		# тропа-ответвление и сам тайник
		WgGeom._lay_road(parent, rng, [p, endp])
		WgLib.place_prop(parent, "dungeon/coin_stack_medium.gltf.glb", endp + perp.normalized() * 0.9, rng.randf_range(0, TAU), 1.0)
		WgLib.place_prop(parent, "dungeon/barrel_large.gltf.glb", endp + Vector3(perp.z, 0, -perp.x).normalized() * 1.1, rng.randf_range(0, TAU), 0.95)
		var glint := OmniLight3D.new()
		glint.light_color = Color(1.0, 0.85, 0.4)
		glint.light_energy = 0.5
		glint.omni_range = 3.5
		glint.position = endp + Vector3(0, 0.8, 0)
		parent.add_child(glint)
		obstacles.append({"x": endp.x, "z": endp.z, "r": 1.4})
		caches.append(endp)
		i += 14
	return caches
