class_name CampBuilder
extends RefCounted
## Лагерь отряда (сюжет): костёр, походный шатёр, сюжетные НПС и огонь-партиклы.

var game # Game-владелец: узлы добавляются его детьми

const POLE_H := 3.9


func _init(game_) -> void:
	game = game_


func build_camp() -> void:
	# костёр
	var fire_root := Node3D.new()
	game.add_child(fire_root)
	fire_root.global_position = game.CAMP_POS
	for i in 4:
		var log_m := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.09
		lm.bottom_radius = 0.11
		lm.height = 1.0
		log_m.mesh = lm
		log_m.material_override = WorldGen._mat(Color(0.35, 0.24, 0.15))
		log_m.rotation = Vector3(PI * 0.42, i * PI * 0.5, 0)
		log_m.position.y = 0.22
		fire_root.add_child(log_m)
	fire_root.add_child(make_fire())
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.25)
	fl.light_energy = 1.6
	fl.omni_range = 9.0
	fl.position.y = 1.0
	fire_root.add_child(fl)

	# шатёр — дом сюжетных персонажей; костёр стоит внутри, у входа
	_build_tent(game.CAMP_POS + Vector3(0, 0, -1.0))

	# НПС под шатром, лицом к костру
	var cfg: Dictionary = game.chapter_cfg()
	var npc_main := Npc.new()
	game.add_child(npc_main)
	npc_main.setup(game, cfg.npc_main, game.CAMP_POS + Vector3(-1.5, 0, -2.4), game.CAMP_POS)
	var npc_side := Npc.new()
	game.add_child(npc_side)
	npc_side.setup(game, cfg.npc_side, game.CAMP_POS + Vector3(1.5, 0, -2.6), game.CAMP_POS)
	# вербовщик вольных магов — сбоку, у края навеса
	var npc_hire := Npc.new()
	game.add_child(npc_hire)
	npc_hire.setup(game, game.HIRE_NPC, game.CAMP_POS + Vector3(2.8, 0, -0.6), game.CAMP_POS + Vector3(0, 0, 4))
	# торговец: скупает трофеи и продаёт снаряжение (ассортимент — на главу)
	var npc_shop := Npc.new()
	game.add_child(npc_shop)
	npc_shop.setup(game, game.MERCHANT_NPC, game.CAMP_POS + Vector3(-2.8, 0, -0.4), game.CAMP_POS + Vector3(0, 0, 4))
	game.npcs = [npc_main, npc_side, npc_hire, npc_shop]
	game._update_npc_markers()


## Походный шатёр: конусная крыша на шестах, открыт к костру.
func _build_tent(pos: Vector3) -> void:
	var tent := Node3D.new()
	game.add_child(tent)
	tent.global_position = pos

	# крыша-конус (ещё выше — с запасом даже для голов в шапках и капюшонах)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.02
	rm.bottom_radius = 3.6
	rm.height = 2.3
	rm.radial_segments = 10
	roof.mesh = rm
	roof.material_override = WorldGen._mat(Color(0.62, 0.2, 0.16))
	roof.position.y = 4.75
	tent.add_child(roof)
	# светлая оторочка по краю крыши
	var rim := MeshInstance3D.new()
	var rmm := CylinderMesh.new()
	rmm.top_radius = 3.52
	rmm.bottom_radius = 3.62
	rmm.height = 0.22
	rmm.radial_segments = 10
	rim.mesh = rmm
	rim.material_override = WorldGen._mat(Color(0.9, 0.82, 0.66))
	rim.position.y = 3.68
	tent.add_child(rim)

	# шесты по кругу (спереди — шире, вход к костру)
	for i in 5:
		var ang := PI * 0.28 + TAU * float(i) / 5.0
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.06
		pm.bottom_radius = 0.08
		pm.height = POLE_H
		pole.mesh = pm
		pole.material_override = WorldGen._mat(Color(0.4, 0.28, 0.18))
		pole.position = Vector3(sin(ang) * 3.0, POLE_H * 0.5, cos(ang) * 3.0)
		tent.add_child(pole)

	# вымпел на макушке
	var flag := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.55, 0.3, 0.04)
	flag.mesh = fm
	flag.material_override = WorldGen._mat(Color(0.95, 0.8, 0.3))
	flag.position = Vector3(0.28, 6.0, 0)
	flag.rotation.z = -PI * 0.5
	tent.add_child(flag)

	# тёплый фонарик под крышей
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 0.9
	lamp.omni_range = 6.5
	lamp.position.y = 3.9
	tent.add_child(lamp)

	# половик под ногами у НПС — читается как обжитое место, а не голый каркас
	var rug := MeshInstance3D.new()
	var rugm := CylinderMesh.new()
	rugm.top_radius = 2.6
	rugm.bottom_radius = 2.6
	rugm.height = 0.03
	rugm.radial_segments = 10
	rug.mesh = rugm
	rug.material_override = WorldGen._mat(Color(0.5, 0.16, 0.14))
	rug.position.y = 0.02
	tent.add_child(rug)

	# растяжки от шестов к земле — придают шатру вес и объём настоящей палатки
	for i in 5:
		var ang := PI * 0.28 + TAU * float(i) / 5.0
		var top := Vector3(sin(ang) * 3.0, POLE_H - 0.35, cos(ang) * 3.0)
		var out := Vector3(sin(ang) * 4.1, 0.0, cos(ang) * 4.1)
		var dir := out - top
		var rope := MeshInstance3D.new()
		var rm2 := CylinderMesh.new()
		rm2.top_radius = 0.025
		rm2.bottom_radius = 0.025
		rm2.height = dir.length()
		rope.mesh = rm2
		rope.material_override = WorldGen._mat(Color(0.55, 0.5, 0.42))
		# по умолчанию цилиндр вытянут вдоль Y — совмещаем эту ось с направлением растяжки
		var y_axis := dir.normalized()
		var x_axis := y_axis.cross(Vector3.FORWARD).normalized()
		if x_axis.length() < 0.01:
			x_axis = y_axis.cross(Vector3.RIGHT).normalized()
		var z_axis := x_axis.cross(y_axis).normalized()
		rope.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (top + out) * 0.5)
		tent.add_child(rope)
		var peg := MeshInstance3D.new()
		var pegm := CylinderMesh.new()
		pegm.top_radius = 0.03
		pegm.bottom_radius = 0.05
		pegm.height = 0.3
		peg.mesh = pegm
		peg.material_override = WorldGen._mat(Color(0.35, 0.3, 0.24))
		peg.position = Vector3(out.x, 0.12, out.z)
		tent.add_child(peg)


func make_fire() -> GPUParticles3D:
	var fire := GPUParticles3D.new()
	fire.amount = 22
	fire.lifetime = 0.8
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 12.0
	fm.initial_velocity_min = 1.0
	fm.initial_velocity_max = 2.0
	fm.gravity = Vector3(0, 1.5, 0)
	fm.scale_min = 0.5
	fm.scale_max = 1.4
	fm.color = Color(1.0, 0.55, 0.15)
	fire.process_material = fm
	var fdm := SphereMesh.new()
	fdm.radius = 0.09
	fdm.height = 0.18
	fdm.radial_segments = 6
	fdm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fdm.material = fmat
	fire.draw_pass_1 = fdm
	fire.position.y = 0.35
	return fire
