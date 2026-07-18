class_name GnomeVisual
extends RefCounted
## Презентация гнома: подготовка модели и оружия, уникальные материалы,
## бейдж уровня, свечение элиты, событийные эффекты и труп-регдолл.

var gn # Gnome-владелец

var _thud_played := false


func _init(gn_) -> void:
	gn = gn_


func prepare_model() -> void:
	for mesh_inst in gn.model.find_children("*", "MeshInstance3D", true, false):
		var hide := false
		for p in gn.cfg.hide:
			if String(mesh_inst.name).contains(p):
				hide = true
				break
		mesh_inst.visible = not hide
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Подвешивает оружие из пака скелетов в слот руки.
func attach_weapon(weapon_name: String, side: String) -> void:
	var scene = gn.game.weapon_scene(weapon_name)
	if scene == null:
		return
	for slot in gn.model.find_children("*handslot*", "", true, false):
		var n := String(slot.name).to_lower()
		if n.ends_with(side) or n.ends_with(side + "_"):
			var w: Node3D = scene.instantiate()
			slot.add_child(w)
			for mi in w.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			return


## Свои копии материалов нужны только для ярости/затухания — дублируем лениво.
func ensure_unique_materials() -> void:
	if gn._materials_full:
		return
	gn._materials_full = true
	# идемпотентно по поверхностям: уже уникальные (например перекрашенные из
	# tint_map) не дублируем повторно, но добираем все остальные — иначе труп
	# с tint_map (маг) растворяется лишь частично
	for mesh_inst in gn.model.find_children("*", "MeshInstance3D", true, false):
		if not mesh_inst.visible:
			continue
		for i in mesh_inst.get_surface_override_material_count():
			var mat = mesh_inst.get_active_material(i)
			if mat != null and not gn.materials.has(mat):
				var m2 = mat.duplicate()
				mesh_inst.set_surface_override_material(i, m2)
				gn.materials.append(m2)


func refresh_level_label() -> void:
	if gn.lvl_label == null:
		gn.lvl_label = Label3D.new()
		gn.lvl_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# высота модели зависит от вида (шляпа мага выше лысины миньона)
		gn.lvl_label.position.y = gn.MODEL_HEIGHTS.get(gn.cfg.model, 1.8) * gn.cfg.scale + 0.45
		gn.lvl_label.pixel_size = 0.007
		gn.lvl_label.outline_size = 7
		gn.add_child(gn.lvl_label)
	if gn.elite:
		gn.lvl_label.text = tr("★ ЭЛИТА ур. %d") % gn.level
		gn.lvl_label.modulate = Color(1.0, 0.83, 0.2)
	elif gn.friendly:
		gn.lvl_label.text = tr("подмастерье ур. %d") % gn.level
		gn.lvl_label.modulate = Color(1.0, 0.85, 0.4)
	else:
		gn.lvl_label.text = tr("ур. %d") % gn.level
		gn.lvl_label.modulate = Color(1.0, 0.75, 0.5) if gn.level >= 4 else Color(0.9, 0.9, 0.85)


## Золотое сияние редкого гнома — мягкий свет и медленные искры, видно издалека.
func apply_elite_glow() -> void:
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.82, 0.25)
	glow.light_energy = 1.0
	glow.omni_range = 4.5
	glow.position.y = gn.MODEL_HEIGHTS.get(gn.cfg.model, 1.8) * gn.cfg.scale * 0.5
	gn.add_child(glow)

	var sparkle := GPUParticles3D.new()
	sparkle.amount = 12
	sparkle.lifetime = 1.6
	sparkle.position.y = 0.15
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.gravity = Vector3(0, 0.25, 0)
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.55
	pm.scale_min = 0.05
	pm.scale_max = 0.1
	pm.color = Color(1.0, 0.85, 0.3)
	sparkle.process_material = pm
	var pdm := BoxMesh.new()
	pdm.size = Vector3(0.08, 0.08, 0.08)
	var pmat := StandardMaterial3D.new()
	pmat.vertex_color_use_as_albedo = true
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pdm.material = pmat
	sparkle.draw_pass_1 = pdm
	gn.add_child(sparkle)


## События (приходят на все машины, включая сервер — call_local).
func on_event(ev: String, data: Array) -> void:
	match ev:
		"hit":
			var dmg: int = data[0]
			var crit: bool = data[1]
			gn.game.fx_burst(gn.global_position + Vector3(0, 0.7, 0), Color(0.6, 0.07, 0.07), 10)
			gn.game.fx_number(gn.global_position, str(dmg), Color(1, 0.85, 0.4) if not crit else Color(1, 0.55, 0.15))
			if gn.alive and data[2]:
				gn.one_shot_until = gn.age + 0.45
				gn._play(gn.cfg.hit_anim, 1.5, true)
			# достижение — только тому, кто реально добил (не всем зрителям)
			if data.size() >= 5 and data[3] and data[4] == Net.my_id:
				Achievements.unlock("finisher")
		"attack":
			var anim: String = data[0]
			gn.one_shot_until = gn.age + gn._play(anim, gn.cfg.attack_ts, true)
			if not gn.cfg.ranged:
				Sfx.play_at("swing", gn.global_position, 0.0, 1.3)
		"heal_cast":
			gn.one_shot_until = gn.age + gn._play("Spellcast_Long", 1.2, true)
		"healed":
			gn.game.fx_burst(gn.global_position + Vector3(0, 0.8, 0), Color(0.4, 0.9, 0.4), 10)
			gn.game.fx_number(gn.global_position, "+%d" % data[0], Color(0.5, 0.9, 0.4))
			Sfx.play_at("pickup", gn.global_position, -6.0, 0.8)
		"cry":
			gn.one_shot_until = gn.age + 0.6
			gn._play("Cheer", 1.8, true)
			Sfx.play_at("war_cry", gn.global_position)
		"parried":
			# удар отбит парированием: гном отшатнулся и раскрылся
			gn.one_shot_until = gn.age + 0.9
			gn._play(gn.cfg.hit_anim, 1.1, true)
			Sfx.play_at("block", gn.global_position, 3.0, 1.25)
			gn.game.fx_burst(gn.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.95, 0.6), 12)
			gn.game.fx_number(gn.global_position, tr("ПАРИРОВАНО!"), Color(1.0, 0.95, 0.5))
		"special_telegraph":
			var kind: String = data[0]
			var label: String = {"slam": "ГОТОВИТ УДАР!", "charge": "ГОТОВИТ РЫВОК!", "summon": "ПРИЗЫВАЕТ ПОДКРЕПЛЕНИЕ!"}.get(kind, "!")
			gn.game.fx_number(gn.global_position, tr(label), Color(1.0, 0.25, 0.15))
			gn.game.fx_burst(gn.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.3, 0.15), 8)
			Sfx.play_at("war_cry", gn.global_position, 2.0, 0.75)
		"special_fx":
			var kind: String = data[0]
			var fx_pos := Vector3(data[1], 0.3, data[2])
			match kind:
				"slam":
					gn.game.fx_burst(fx_pos, Color(1.0, 0.4, 0.1), 26)
					Sfx.play_at("explode", fx_pos, 4.0, 0.85)
				"charge_land":
					gn.game.fx_burst(fx_pos, Color(0.55, 0.78, 1.35), 22)
					Sfx.play_at("explode", fx_pos, 2.0, 1.15)
				"summon":
					gn.game.fx_burst(fx_pos, Color(0.6, 0.9, 0.6), 20)
					Sfx.play_at("gnome_death", fx_pos, -2.0, 0.6)
		"levelup":
			gn.level = data[0]
			refresh_level_label()
			gn.game.fx_burst(gn.global_position + Vector3(0, 1.3, 0), Color(1.0, 0.85, 0.4), 16)
			gn.game.fx_number(gn.global_position, tr("УРОВЕНЬ %d") % gn.level, Color(1.0, 0.85, 0.4))
			Sfx.play_at("pickup", gn.global_position, 2.0, 1.1)
			if gn.friendly and data.size() >= 3 and data[1] and data[2] == Net.my_id:
				Achievements.unlock("ally_veteran")
		"enrage":
			gn.enraged = true
			ensure_unique_materials()
			for m in gn.materials:
				if m is StandardMaterial3D:
					m.emission_enabled = true
					m.emission = Color(1.0, 0.13, 0.0)
					m.emission_energy_multiplier = 0.4
			gn.game.fx_number(gn.global_position, tr("ЯРОСТЬ!"), Color(1, 0.4, 0.1))
			Sfx.play_at("war_cry", gn.global_position, 3.0, 0.8)
		"die":
			gn.alive = false
			gn.state = "dead"
			gn.dead_time = 0.0
			ensure_unique_materials()
			Sfx.play_at("gnome_death", gn.global_position, 3.0, 0.7 if gn.type == "king" else 1.0)
			gn.game.fx_burst(gn.global_position + Vector3(0, 0.5, 0), Color(0.7, 0.12, 0.07), 18)
			gn.collision_layer = 0
			gn.collision_mask = 1
			var kdir := Vector3.FORWARD
			var kcrit := false
			if data.size() >= 3:
				kdir = Vector3(data[0], 0, data[1])
				kcrit = data[2]
			# достижения за убийство — только реальному убийце (data[5] = его id)
			var killer_id: int = data[5] if data.size() >= 6 else 0
			if killer_id == Net.my_id:
				if data.size() >= 4 and data[3]:
					Achievements.unlock("elite_hunter")
				if data.size() >= 5 and data[4]:
					Achievements.unlock("finisher")
			spawn_ragdoll(kdir, kcrit)


func spawn_ragdoll(dir: Vector3, crit: bool) -> void:
	gn.anim_player.pause()

	var corpse := RigidBody3D.new()
	gn.corpse = corpse
	corpse.top_level = true
	corpse.collision_layer = 0
	corpse.collision_mask = 1
	corpse.mass = 2.5 * gn.cfg.scale
	corpse.continuous_cd = true # быстрый кувырок иначе может проскочить сквозь тонкий пол/камень
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	pmat.friction = 0.9
	corpse.physics_material_override = pmat
	# коробка на весь силуэт модели (а не только туловище) — иначе голова/ноги
	# торчат за её пределы и на кувырке проваливаются сквозь текстуры пола/камней
	var full_h: float = gn.MODEL_HEIGHTS.get(gn.cfg.model, 1.8) * gn.cfg.scale
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9 * gn.cfg.scale, full_h, 1.1 * gn.cfg.scale)
	cs.shape = box
	cs.position.y = full_h * 0.5 - 0.55 * gn.cfg.scale
	corpse.add_child(cs)
	corpse.contact_monitor = true
	corpse.max_contacts_reported = 1
	corpse.body_entered.connect(_on_corpse_contact)
	gn.add_child(corpse)
	corpse.global_position = gn.global_position + Vector3(0, 0.55 * gn.cfg.scale, 0)
	gn.model.reparent(corpse)

	var heavy: float = 0.55 if gn.type == "king" else 1.0 # короля так просто не подбросишь
	var speed: float = (8.5 if crit else 5.0) * heavy
	corpse.linear_velocity = dir.normalized() * speed + Vector3(0, (5.5 if crit else 3.5) * heavy, 0)
	corpse.angular_velocity = Vector3(
		randf_range(-7, 7), randf_range(-4, 4), randf_range(-7, 7)) * heavy


func _on_corpse_contact(_body: Node) -> void:
	if not _thud_played and gn.corpse != null:
		_thud_played = true
		Sfx.play_at("hit", gn.corpse.global_position, -8.0, 0.65)
		gn.game.fx_burst(gn.corpse.global_position, Color(0.5, 0.4, 0.25), 6)
