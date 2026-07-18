class_name GnomeAi
extends RefCounted
## Серверный ИИ гнома: машина состояний (_sim), восприятие (зрение/слух),
## выбор цели, спецприёмы боссов, движение (прямое и по навсетке), урон.

# Босс-спецприёмы: telegraph -> execute -> recover.
const SPECIAL_TELEGRAPH_TIME := 1.3
const SPECIAL_RECOVER_TIME := 0.6

## Насколько далеко от нанимателя наёмник ещё готов гоняться за врагом —
## иначе он убегал через полкарты за первым замеченным гномом.
const ALLY_LEASH := 11.0
const ALLY_RECALL := 15.0

var gn # Gnome-владелец

var _charge_target := Vector2.ZERO
var _nav_repath := 0.0


func _init(gn_) -> void:
	gn = gn_


func sim(delta: float) -> void:
	if gn.state == "spawn":
		if gn.age >= 0.35:
			set_state("emerge")
		return

	if gn.shout_lock > 0:
		gn.shout_lock -= delta
		stop_move(delta)
		apply_motion(delta)
		return

	pick_target(delta)

	# фирменный спецприём босса — вне обычной машины состояний, приоритет над всем
	if gn.cfg.has("special"):
		if gn.is_special:
			_run_special(delta)
			return
		if gn.target != null and gn.alerted and gn.state != "emerge":
			gn.special_timer -= delta
			if gn.special_timer <= 0.0 and dist_to_target() < gn.cfg.get("special_range", 14.0):
				_start_special()
				return

	# наёмник: врага нет — держимся рядом с нанимателем
	if gn.friendly:
		if gn.target != null and (gn.state == "patrol" or gn.state == "idle_wait" or gn.state == "investigate"):
			set_state("chase")
		elif gn.target == null and gn.state != "attack" and gn.state != "emerge":
			var boss_p = gn.game.player_nodes.get(gn.owner_id)
			if boss_p != null and is_instance_valid(boss_p):
				var d_own: float = gn.global_position.distance_to(boss_p.global_position)
				if d_own > 3.2:
					nav_move_towards(boss_p.global_position.x, boss_p.global_position.z,
						gn.cfg.speed * gn.speed_mul * (1.4 if d_own > 8.0 else 1.0), delta)
					loco(d_own > 8.0, true)
				else:
					stop_move(delta)
					loco(false, false)
			else:
				stop_move(delta)
				loco(false, false)
			apply_motion(delta)
			return

	# из сейф-зоны лагеря уходим, не задерживаясь
	if gn.friendly == false and gn.game.in_safe_zone(gn.global_position) and gn.state != "emerge":
		var away := Vector2(gn.global_position.x - Game.CAMP_POS.x, gn.global_position.z - Game.CAMP_POS.z)
		if away.length() < 0.1:
			away = Vector2(1, 0)
		var out := Vector2(Game.CAMP_POS.x, Game.CAMP_POS.z) + away.normalized() * (Game.SAFE_RADIUS + 2.0)
		move_towards(out.x, out.y, gn.cfg.speed * gn.speed_mul, delta)
		loco(false, true)
		apply_motion(delta)
		return

	# восприятие (не во время выхода из домика)
	if not gn.alerted and gn.target != null and gn.state != "emerge":
		if can_see_target():
			become_alerted(true)
		elif can_hear_target():
			gn.investigate_pos = Vector2(gn.target.global_position.x, gn.target.global_position.z)
			gn.investigating = true
			if gn.state != "investigate":
				set_state("investigate")

	gn.attack_timer = maxf(0, gn.attack_timer - delta)
	gn.sidestep_cd = maxf(0, gn.sidestep_cd - delta)
	gn.heal_cd = maxf(0, gn.heal_cd - delta)
	var speed: float = gn.cfg.speed * gn.speed_mul
	var one_shot_busy: bool = gn.age < gn.one_shot_until

	match gn.state:
		"emerge":
			# выходим из домика через дверь
			var d := move_towards(gn.emerge_target.x, gn.emerge_target.y, speed * 0.6, delta)
			loco(false, true)
			if d < 0.5 or gn.state_time > 3.0:
				set_state("patrol")
				gn.has_waypoint = false
		"patrol":
			if not gn.has_waypoint:
				gn.waypoint = _random_waypoint()
				gn.has_waypoint = true
			var d := nav_move_towards(gn.waypoint.x, gn.waypoint.y, speed * 0.45, delta)
			loco(false, true)
			if d < 0.9:
				set_state("idle_wait")
				gn.idle_for = randf_range(1.0, 2.5)
		"idle_wait":
			loco(false, false)
			stop_move(delta)
			if gn.state_time > gn.idle_for:
				gn.has_waypoint = false
				set_state("patrol")
		"investigate":
			if not gn.investigating:
				set_state("patrol")
			else:
				var d := nav_move_towards(gn.investigate_pos.x, gn.investigate_pos.y, speed * 0.7, delta)
				loco(false, true)
				if can_see_target():
					become_alerted(true)
				elif d < 1.2 or gn.state_time > 6.0:
					gn.investigating = false
					set_state("patrol")
		"chase":
			if gn.target == null:
				gn.alerted = false
				set_state("patrol")
			else:
				var d := dist_to_target()
				if d < gn.cfg.ring + 1.5:
					set_state("circle")
				else:
					nav_move_towards(gn.target.global_position.x, gn.target.global_position.z, speed, delta)
					loco(true, true)
		"circle":
			if gn.target == null:
				gn.alerted = false
				set_state("patrol")
			else:
				var d := dist_to_target()
				if d > gn.cfg.ring + 6.0:
					set_state("chase")
				else:
					var tx: float = gn.target.global_position.x + sin(gn.slot_angle) * gn.cfg.ring
					var tz: float = gn.target.global_position.z + cos(gn.slot_angle) * gn.cfg.ring
					var dslot := move_towards(tx, tz, speed * 0.8, delta, angle_to_target())
					if not one_shot_busy:
						loco(false, dslot > 0.5)

					# разведчик уворачивается от замаха игрока
					if gn.cfg.get("dodges", false) and gn.sidestep_cd <= 0 and d < 3.8 \
							and gn.target is PlayerChar and gn.target.state == "attack" and gn.target.state_time < 0.12 \
							and randf() < float(gn.game.diff().dodge):
						_start_sidestep()
					elif gn.cfg.ranged and d < 5.5:
						set_state("flee")
					elif gn.cfg.get("heals", false) and gn.heal_cd <= 0 and _try_start_heal():
						pass
					else:
						var in_range: bool = (d < gn.cfg.attack_range) if gn.cfg.ranged else true
						if gn.attack_timer <= 0 and in_range and _request_token():
							_start_attack()
		"sidestep":
			gn.velocity.x = gn.sidestep_dir.x * 7.0
			gn.velocity.z = gn.sidestep_dir.z * 7.0
			if gn.state_time > 0.35:
				set_state("circle")
		"heal_cast":
			stop_move(delta)
			if gn.heal_target != null and is_instance_valid(gn.heal_target) and gn.heal_target.alive:
				gn.facing = rotate_toward(gn.facing,
					atan2(gn.heal_target.global_position.x - gn.global_position.x, gn.heal_target.global_position.z - gn.global_position.z),
					gn.cfg.turn * delta)
				if gn.state_time >= 1.0 and gn.heal_target != null:
					var ally = gn.heal_target
					gn.heal_target = null
					ally.hp = mini(ally.max_hp, ally.hp + 18)
					gn.game.bcast_gnome_event(ally.gid, "healed", [18])
					gn.heal_cd = float(gn.game.diff().heal_cd)
			if gn.state_time >= 1.2:
				set_state("circle")
		"attack":
			if gn.target == null:
				_finish_attack()
				set_state("patrol")
			elif gn.cfg.ranged:
				stop_move(delta)
				gn.facing = rotate_toward(gn.facing, angle_to_target(), gn.cfg.turn * delta)
				if not gn.attack_did_hit and gn.state_time >= gn.attack_dur * 0.55:
					gn.attack_did_hit = true
					gn.game.server_spawn_fireball(gn)
				if gn.state_time >= gn.attack_dur:
					_finish_attack()
			elif not gn.attack_swinging:
				var d := move_towards(gn.target.global_position.x, gn.target.global_position.z, speed * 1.25, delta)
				loco(true, true)
				if d < gn.cfg.attack_range * 0.85:
					gn.attack_swinging = true
					gn.state_time = 0.0
					var anim: String = gn.cfg.attack_anims[randi() % gn.cfg.attack_anims.size()]
					gn.attack_dur = gn.anim_player.get_animation(anim).length / gn.cfg.attack_ts if gn.anim_player.has_animation(anim) else 0.8
					gn.game.bcast_gnome_event(gn.gid, "attack", [anim])
				elif gn.state_time > 3.5:
					_finish_attack()
			else:
				stop_move(delta)
				gn.facing = rotate_toward(gn.facing, angle_to_target(), gn.cfg.turn * 0.5 * delta)
				if not gn.attack_did_hit and gn.state_time >= gn.attack_dur * 0.45:
					gn.attack_did_hit = true
					if dist_to_target() < gn.cfg.attack_range + 0.6:
						var out_dmg := maxi(1, roundi(gn.cfg.attack_dmg * gn.dmg_mul * gn.level_dmg_mult * float(gn.game.diff().dmg)))
						if gn.target is Gnome:
							gn.target.last_attacker = 0
							gn.target.last_attacker_gid = gn.gid
							gn.target.server_take_damage(out_dmg, gn.global_position, false)
						else:
							gn.game.server_damage_player(target_id(), out_dmg, gn.global_position)
				if gn.state_time >= gn.attack_dur:
					_finish_attack()
					if gn.cfg.retreats:
						set_state("retreat")
		"retreat":
			if gn.target != null:
				var away := atan2(gn.global_position.x - gn.target.global_position.x, gn.global_position.z - gn.target.global_position.z)
				move_towards(gn.global_position.x + sin(away + 0.5) * 3, gn.global_position.z + cos(away + 0.5) * 3, speed, delta, angle_to_target())
				loco(true, true)
			if gn.state_time > 0.7:
				set_state("circle")
		"flee":
			if gn.target != null:
				var away := atan2(gn.global_position.x - gn.target.global_position.x, gn.global_position.z - gn.target.global_position.z)
				nav_move_towards(gn.global_position.x + sin(away) * 5, gn.global_position.z + cos(away) * 5, speed * 1.25, delta)
				loco(true, true)
				if dist_to_target() > gn.cfg.ring + 1.0 or gn.state_time > 4.0:
					set_state("circle")
			else:
				set_state("patrol")
		"stagger":
			stop_move(delta)
			if gn.state_time > 0.45:
				set_state("circle" if gn.alerted else "patrol")

	apply_motion(delta)


## Гравитация, отбрасывание и физика — через move_and_slide (сквозь стены нельзя).
func apply_motion(delta: float) -> void:
	if gn.knockback.length_squared() > 0.01:
		gn.velocity.x += gn.knockback.x
		gn.velocity.z += gn.knockback.z
		gn.knockback = gn.knockback.move_toward(Vector3.ZERO, gn.knockback.length() * 8 * delta + 0.2)
	gn.velocity.y -= gn.GRAVITY * delta
	gn.move_and_slide()
	if gn.is_on_floor():
		gn.velocity.y = 0


func _start_special() -> void:
	gn.is_special = true
	gn.special_phase = "telegraph"
	gn.special_time = 0.0
	var telegraph_anim := "Spellcast_Summon" if gn.cfg.special == "summon" else "Taunt_Longer"
	if not gn.anim_player.has_animation(telegraph_anim):
		telegraph_anim = "Taunt" if gn.anim_player.has_animation("Taunt") else gn.cfg.idle_anim
	gn.one_shot_until = gn.age + gn._play(telegraph_anim, 1.0, true)
	gn.game.bcast_gnome_event(gn.gid, "special_telegraph", [gn.cfg.special])


func _run_special(delta: float) -> void:
	gn.special_time += delta
	match gn.special_phase:
		"telegraph":
			stop_move(delta)
			apply_motion(delta)
			if gn.target != null:
				gn.facing = rotate_toward(gn.facing, angle_to_target(), gn.cfg.turn * 0.4 * delta)
			if gn.special_time >= SPECIAL_TELEGRAPH_TIME:
				gn.special_phase = "execute"
				gn.special_time = 0.0
				_execute_special()
		"execute":
			if gn.cfg.special == "charge":
				if gn.special_time < 0.55:
					# рывок к точке, выбранной в момент начала броска (см. _execute_special)
					var d := move_towards(_charge_target.x, _charge_target.y, gn.cfg.speed * 3.4, delta)
					loco(true, true)
					apply_motion(delta)
					if d >= 0.6:
						return
				# долетели (или вышло время) — удар по приземлению
				_on_charge_land()
				stop_move(delta)
				apply_motion(delta)
				gn.special_phase = "recover"
				gn.special_time = 0.0
			else:
				stop_move(delta)
				apply_motion(delta)
				gn.special_phase = "recover"
				gn.special_time = 0.0
		"recover":
			stop_move(delta)
			apply_motion(delta)
			if gn.special_time >= SPECIAL_RECOVER_TIME:
				gn.is_special = false
				gn.special_timer = gn.cfg.get("special_cd", 9.0)
				set_state("circle" if gn.alerted else "patrol")


func _execute_special() -> void:
	match gn.cfg.special:
		"slam":
			gn.game.bcast_gnome_event(gn.gid, "special_fx", ["slam", gn.global_position.x, gn.global_position.z])
			var r: float = gn.cfg.get("special_radius", 5.0)
			var dmg: int = roundi(gn.cfg.get("special_dmg", 20) * gn.level_dmg_mult * float(gn.game.diff().dmg))
			for id in gn.game.player_nodes:
				var p = gn.game.player_nodes[id]
				if gn.game.server_hp.get(id, 0) <= 0:
					continue
				if gn.global_position.distance_to(p.global_position) < r:
					gn.game.server_damage_player(id, dmg, gn.global_position)
		"charge":
			if gn.target != null:
				_charge_target = Vector2(gn.target.global_position.x, gn.target.global_position.z)
			else:
				_charge_target = Vector2(gn.global_position.x, gn.global_position.z)
			gn.special_time = 0.0 # длительность броска отмеряется в _run_special
		"summon":
			var n: int = gn.cfg.get("special_count", 2)
			for i in n:
				var a := randf_range(0, TAU)
				var px: float = gn.global_position.x + cos(a) * 2.5
				var pz: float = gn.global_position.z + sin(a) * 2.5
				gn.game.server_spawn_gnome_at("skeleton_minion", Vector3(px, 0, pz), gn.level)
			gn.game.bcast_gnome_event(gn.gid, "special_fx", ["summon", gn.global_position.x, gn.global_position.z])


func _on_charge_land() -> void:
	var r: float = gn.cfg.get("special_radius", 3.0)
	var dmg: int = roundi(gn.cfg.get("special_dmg", 18) * gn.level_dmg_mult * float(gn.game.diff().dmg))
	gn.game.bcast_gnome_event(gn.gid, "special_fx", ["charge_land", gn.global_position.x, gn.global_position.z])
	for id in gn.game.player_nodes:
		var p = gn.game.player_nodes[id]
		if gn.game.server_hp.get(id, 0) <= 0:
			continue
		if gn.global_position.distance_to(p.global_position) < r:
			gn.game.server_damage_player(id, dmg, gn.global_position)


func _start_sidestep() -> void:
	gn.sidestep_cd = 1.6
	var to_t := angle_to_target()
	var side := 1.0 if randf() < 0.5 else -1.0
	gn.sidestep_dir = Vector3(sin(to_t + PI * 0.5 * side), 0, cos(to_t + PI * 0.5 * side))
	set_state("sidestep")
	gn.one_shot_until = gn.age + 0.4
	gn._play("Dodge_Right" if side > 0 else "Dodge_Left", 1.4, true)


func _try_start_heal() -> bool:
	var best: Gnome = null
	var best_hp := 0.65
	for g in gn.game.gnomes.values():
		if g == gn or not g.alive or g.friendly != gn.friendly:
			continue
		var frac: float = float(g.hp) / g.max_hp
		if frac < best_hp and gn.global_position.distance_to(g.global_position) < 12.0:
			best_hp = frac
			best = g
	if best == null:
		return false
	gn.heal_target = best
	set_state("heal_cast")
	gn.game.bcast_gnome_event(gn.gid, "heal_cast", [])
	return true


func pick_target(delta: float) -> void:
	gn.retarget_timer -= delta
	var owner_p = gn.game.player_nodes.get(gn.owner_id) if gn.friendly else null
	# якорь привязи: наниматель, если он на месте; иначе — сам наёмник, чтобы
	# осиротевший (наниматель вышел) маг держался рядом, а не убегал через полкарты
	var anchor: Vector3 = gn.global_position
	if owner_p != null and is_instance_valid(owner_p):
		anchor = owner_p.global_position
	if gn.retarget_timer > 0 and gn.target != null and is_instance_valid(gn.target) \
			and gn.target.state != "dead" and gn.target.state != "downed" \
			and not gn.game.in_safe_zone(gn.target.global_position) \
			and (not gn.friendly or anchor.distance_to(gn.target.global_position) < ALLY_RECALL):
		return
	gn.retarget_timer = 0.5
	gn.target = null
	var best := 1e9
	if gn.friendly:
		# наёмник целится в ближайшего врага-гнома, но только рядом с якорем —
		# иначе он срывается через полкарты за первым замеченным противником
		for g in gn.game.gnomes.values():
			if g == gn or not g.alive or g.friendly:
				continue
			if anchor.distance_to(g.global_position) > ALLY_LEASH:
				continue
			var dg: float = gn.global_position.distance_to(g.global_position)
			if dg < best:
				best = dg
				gn.target = g
		return
	for p in gn.game.player_nodes.values():
		if p.state == "dead" or p.state == "downed":
			continue
		if gn.game.in_safe_zone(p.global_position):
			continue # в лагере игрок недосягаем
		# поводок: не гонимся за игроком, который увёл бы нас слишком далеко от дома
		if gn.home_pos != Vector3.INF \
				and Vector2(p.global_position.x - gn.home_pos.x, p.global_position.z - gn.home_pos.z).length() > gn.HOME_LEASH:
			continue
		var d: float = gn.global_position.distance_to(p.global_position)
		if d < best:
			best = d
			gn.target = p
	# наёмники игроков — тоже цели (и ближе костяшкам, чем рыцари)
	for g in gn.game.gnomes.values():
		if not g.friendly or not g.alive:
			continue
		var d2: float = gn.global_position.distance_to(g.global_position)
		if d2 < best:
			best = d2
			gn.target = g


func target_id() -> int:
	return gn.target.peer_id if gn.target != null else 0


func dist_to_target() -> float:
	return Vector2(gn.target.global_position.x - gn.global_position.x, gn.target.global_position.z - gn.global_position.z).length()


func angle_to_target() -> float:
	return atan2(gn.target.global_position.x - gn.global_position.x, gn.target.global_position.z - gn.global_position.z)


func can_see_target() -> bool:
	if gn.target == null:
		return false
	var d := dist_to_target()
	if d < 3.0:
		return true
	if d > float(gn.game.diff().sight):
		return false
	return absf(angle_difference(angle_to_target(), gn.facing)) < gn.SIGHT_ANGLE


func can_hear_target() -> bool:
	if gn.target == null:
		return false
	if gn.target is Gnome:
		return dist_to_target() < 12.0
	return dist_to_target() < gn.game.get_player_noise(gn.target)


func become_alerted(shout: bool) -> void:
	if gn.alerted or not gn.alive or gn.state == "emerge" or gn.state == "spawn":
		return
	gn.alerted = true
	if is_instance_valid(gn.target):
		gn.slot_angle = atan2(gn.global_position.x - gn.target.global_position.x, gn.global_position.z - gn.target.global_position.z)
	set_state("chase")
	if shout:
		gn.shout_lock = 0.5
		gn.game.bcast_gnome_event(gn.gid, "cry", [])
		gn.game.server_alert_nearby(gn.global_position, 15.0, gn)


## Урон (только на сервере). Добивание оглушённого (state == "stagger")
## гнома — импровизированный "финишер": больше урона и своя ачивка.
func take_damage(dmg: int, from_pos: Vector3, crit: bool) -> void:
	if not gn.alive:
		return
	var finisher: bool = gn.state == "stagger" and not gn.friendly
	if finisher:
		dmg = roundi(dmg * 1.4)
	gn.hp -= dmg
	var dx: float = gn.global_position.x - from_pos.x
	var dz: float = gn.global_position.z - from_pos.z
	var d := maxf(0.1, Vector2(dx, dz).length())
	var kb := (5.0 if crit else 3.0) * (0.25 if gn.type == "king" else 1.0)
	gn.knockback += Vector3(dx / d * kb, 0, dz / d * kb)

	if gn.state == "emerge":
		set_state("patrol") # выманили из домика ударом
	become_alerted(false)
	gn.game.server_alert_nearby(gn.global_position, 10.0, gn)

	if gn.hp <= 0:
		_release_token()
		gn.game.server_gnome_died(gn, from_pos, crit, finisher)
		return

	if gn.cfg.enrage_at > 0.0 and not gn.enraged and gn.hp < gn.max_hp * gn.cfg.enrage_at:
		gn.speed_mul = 1.55
		gn.dmg_mul = 1.5
		gn.game.bcast_gnome_event(gn.gid, "enrage", [])

	var staggered: bool = gn.state != "attack" or randf() < gn.cfg.stagger
	gn.game.bcast_gnome_event(gn.gid, "hit", [dmg, crit, staggered, finisher, gn.last_attacker])
	if staggered:
		_release_token()
		gn.attack_swinging = false
		set_state("stagger")

	if gn.type == "shaman" and gn.hp < gn.max_hp * 0.5 and is_instance_valid(gn.target) and dist_to_target() < 6.0:
		set_state("flee")


func set_state(s: String) -> void:
	gn.state = s
	gn.state_time = 0.0


func _request_token() -> bool:
	if gn.has_token:
		return true
	if gn.game.server_request_token(gn.gid):
		gn.has_token = true
		return true
	return false


func _release_token() -> void:
	if gn.has_token:
		gn.game.server_release_token(gn.gid)
		gn.has_token = false


func _start_attack() -> void:
	set_state("attack")
	gn.attack_did_hit = false
	gn.attack_swinging = false
	if gn.cfg.ranged:
		gn.attack_swinging = true
		var anim: String = gn.cfg.attack_anims[0]
		gn.attack_dur = gn.anim_player.get_animation(anim).length / gn.cfg.attack_ts if gn.anim_player.has_animation(anim) else 0.9
		gn.game.bcast_gnome_event(gn.gid, "attack", [anim])
		Sfx.play_at("fireball", gn.global_position)


func _finish_attack() -> void:
	_release_token()
	gn.attack_timer = randf_range(gn.cfg.cd_min, gn.cfg.cd_max) * (0.55 if gn.enraged else 1.0) * float(gn.game.diff().cd)
	gn.attack_swinging = false
	if gn.state == "attack":
		set_state("circle")


## Прямое движение (короткие манёвры вокруг цели).
func move_towards(tx: float, tz: float, speed: float, delta: float, face_target: float = INF) -> float:
	var dx: float = tx - gn.global_position.x
	var dz: float = tz - gn.global_position.z
	var d := Vector2(dx, dz).length()
	if d > 0.05:
		gn.velocity.x = dx / d * speed
		gn.velocity.z = dz / d * speed
		var face := face_target if face_target != INF else atan2(dx, dz)
		gn.facing = rotate_toward(gn.facing, face, gn.cfg.turn * delta)
	else:
		gn.velocity.x = 0
		gn.velocity.z = 0
		if face_target != INF:
			gn.facing = rotate_toward(gn.facing, face_target, gn.cfg.turn * delta)
	return d


## Движение по навигационной сетке (дальние переходы — обходит препятствия).
func nav_move_towards(tx: float, tz: float, speed: float, delta: float) -> float:
	var final_d := Vector2(tx - gn.global_position.x, tz - gn.global_position.z).length()
	if gn.nav == null or not gn.game.nav_ready or final_d < 2.0:
		move_towards(tx, tz, speed, delta)
		return final_d
	_nav_repath -= delta
	var t := Vector3(tx, 0, tz)
	if _nav_repath <= 0 or gn.nav.target_position.distance_to(t) > 1.5:
		_nav_repath = 0.4
		gn.nav.target_position = t
	if gn.nav.is_navigation_finished():
		stop_move(delta)
		return final_d
	var next: Vector3 = gn.nav.get_next_path_position()
	move_towards(next.x, next.z, speed, delta)
	return final_d


func stop_move(delta: float) -> void:
	gn.velocity.x = move_toward(gn.velocity.x, 0, 20 * delta)
	gn.velocity.z = move_toward(gn.velocity.z, 0, 20 * delta)


func loco(fast: bool, moving: bool) -> void:
	if gn.age < gn.one_shot_until:
		return
	if fast:
		gn._play("Running_A")
	elif moving:
		gn._play("Walking_A")
	else:
		gn._play(gn.cfg.idle_anim)


func _random_waypoint() -> Vector2:
	# на оверворлде гном патрулирует свою округу, а не весь огромный мир
	if gn.home_pos != Vector3.INF:
		for _try in 8:
			var ha := randf_range(0, TAU)
			var hr := randf_range(3.0, gn.HOME_ROAM)
			var hwp := Vector2(gn.home_pos.x + cos(ha) * hr, gn.home_pos.z + sin(ha) * hr)
			if not gn.game.in_safe_zone(Vector3(hwp.x, 0, hwp.y)):
				return hwp
	for _try in 8:
		var a := randf_range(0, TAU)
		var r := randf_range(5.0, WorldGen.WORLD_RADIUS - 5.0)
		var wp := Vector2(cos(a) * r, sin(a) * r)
		if not gn.game.in_safe_zone(Vector3(wp.x, 0, wp.y)):
			return wp
	return Vector2(0, -WorldGen.WORLD_RADIUS * 0.5)
