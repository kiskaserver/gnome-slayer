class_name PlayerCombat
extends RefCounted
## Бой игрока: атака/комбо, доворот к цели, кувырок, расчёт и отправка урона.
## Состояние (state, combo_step, iframes...) живёт на PlayerChar.

var p # PlayerChar-владелец


func _init(p_) -> void:
	p = p_


func try_attack() -> void:
	if p.state == "dead" or p.state == "downed":
		return
	if p.state == "attack":
		if p.state_time > p.attack_dur * 0.3:
			p.combo_queued = true
		return
	if p.state in ["dodge", "hit", "revive_up"]:
		return
	start_attack()


func start_attack() -> void:
	p.heavy_step = {}
	var step: Dictionary = p.active_combo()[p.combo_step]
	p.state = "attack"
	p.state_time = 0.0
	p.hit_done = false
	p.combo_queued = false
	p.attack_dur = p._play(step.anim, step.ts)
	Sfx.play_at("swing", p.global_position)
	if p.is_local and p.game.tutorial != null:
		p.game.tutorial.notify("attack")
	if p.is_ranged_weapon():
		p.facing = p.cam_yaw.rotation.y + PI # арбалет целится по камере, не по ближайшему врагу
	else:
		_face_nearest_enemy()


## Тяжёлый удар с замаха: больнее и шире последнего шага комбо, жрёт стамину.
func release_heavy() -> void:
	p.drain_stamina(p.STAM_HEAVY)
	var base: Dictionary = p.active_combo()[p.active_combo().size() - 1]
	p.heavy_step = {"anim": base.anim, "dmg": roundi(base.dmg * 1.7),
		"range": base.range + 0.3, "arc": minf(base.arc * 1.7, 2.9), "ts": base.ts * 0.9}
	p.state = "attack"
	p.state_time = 0.0
	p.hit_done = false
	p.combo_queued = false
	p.attack_held = 0.0
	p.attack_dur = p._play(p.heavy_step.anim, p.heavy_step.ts)
	Sfx.play_at("swing", p.global_position, 2.0, 0.8)
	p.add_shake(0.1)
	_face_nearest_enemy()


func _face_nearest_enemy() -> void:
	var best = null
	var best_d := 5.5
	for g in p.game.gnomes.values():
		if not g.alive or g.friendly:
			continue # не доворачиваемся к своему наёмнику
		var d: float = g.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = g
	if p.game.is_pvp():
		for pl in p.game.player_nodes.values():
			if pl == p or pl.state == "dead":
				continue
			var d: float = pl.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = pl
	if best != null:
		var dx: float = best.global_position.x - p.global_position.x
		var dz: float = best.global_position.z - p.global_position.z
		p.facing = atan2(dx, dz)


func try_dodge() -> void:
	if p.state in ["dead", "downed", "dodge", "revive_up", "reviving"] or p.dodge_cooldown > 0:
		return
	if p.state == "attack" and p.state_time < p.attack_dur * 0.5:
		return
	if p.is_local and p.stamina < p.STAM_DODGE:
		return # выдохся — на кувырок не хватает
	if p.is_local:
		p.drain_stamina(p.STAM_DODGE)
	p.state = "dodge"
	p.state_time = 0.0
	p.iframes = 0.45
	if p.is_local and p.game.tutorial != null:
		p.game.tutorial.notify("dodge")
	var me: Dictionary = Net.players.get(Net.my_id, {})
	p.dodge_cooldown = 0.9 * (1.0 - 0.05 * me.get("agi", 0)) * Skills.dodge_cd_mult(me) if p.is_local else 0.9
	var dir: Vector3 = p._move_dir if p._move_dir.length_squared() > 0.01 else Vector3(sin(p.facing), 0, cos(p.facing))
	p.dodge_dir = dir.normalized()
	p.facing = atan2(p.dodge_dir.x, p.dodge_dir.z)
	p._play("Dodge_Forward", 1.5)
	Sfx.play_at("roll", p.global_position)


func deal_damage(step: Dictionary) -> void:
	# арбалет: клиент шлёт только направление — урон и попадание решает сервер
	if p.is_ranged_weapon():
		p.facing = p.cam_yaw.rotation.y + PI # стреляем туда, куда смотрит камера
		Net.req_shoot(sin(p.facing), cos(p.facing))
		Sfx.play_at("swing", p.global_position, -2.0, 1.6)
		p.add_shake(0.08)
		return
	var targets: Array = []
	for id in p.game.gnomes:
		var g = p.game.gnomes[id]
		if not g.alive or g.friendly:
			continue # свой наёмник не получает урона от игрока
		if _in_arc(g.global_position, step.range + 0.45, step.arc):
			targets.append(["g", id])
	if p.game.is_pvp():
		for id in p.game.player_nodes:
			if id == p.peer_id:
				continue
			var pl = p.game.player_nodes[id]
			if pl.state == "dead" or pl.state == "downed":
				continue
			if _in_arc(pl.global_position, step.range + 0.45, step.arc):
				targets.append(["p", id])
	# взрывные бочки — тоже цель замаха
	for bid in p.game.barrels:
		var b = p.game.barrels[bid]
		if b.alive and _in_arc(Vector3(b.x, 0, b.z), step.range + 0.45, step.arc):
			targets.append(["b", bid])
	if targets.is_empty():
		return
	var me: Dictionary = Net.players.get(Net.my_id, {})
	var crit := randf() < Quests.crit_chance_for(me) + Items.equip_crit_bonus(p.game.my_equip)
	var dmg_f: float = step.dmg * (1.5 if p.has_buff("rage") else 1.0) * Quests.dmg_mult_for(me) \
		* Items.equip_dmg_mult(p.game.my_equip)
	var dmg: int = roundi(dmg_f * (1.8 * Quests.crit_dmg_mult_for(me) if crit else 1.0))
	Net.req_melee(targets, dmg, crit)
	Sfx.play_at("hit", p.global_position)
	p.add_shake(0.12)
	if p.is_local:
		p.game.hud.combo_flash(p.combo_step + 1)


func _in_arc(target: Vector3, dist: float, arc: float) -> bool:
	var dx: float = target.x - p.global_position.x
	var dz: float = target.z - p.global_position.z
	if Vector2(dx, dz).length() > dist:
		return false
	return absf(angle_difference(atan2(dx, dz), p.facing)) < arc
