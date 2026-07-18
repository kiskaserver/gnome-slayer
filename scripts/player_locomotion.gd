class_name PlayerLocomotion
extends RefCounted
## Симуляция игрока: локальный тик (движение/состояния/подсказки), камера,
## адаптивная отправка состояния и интерполяция чужих марионеток.

var p # PlayerChar-владелец

# сеть: отправка своего состояния
var send_timer := 0.0
var _last_sent_anim := -1
var _last_sent_pos := Vector3.ZERO
# поднятие павшего и подсказки взаимодействия
var _revive_send_timer := 0.0
var _revive_target_id := 0
var _hint_timer := 0.0


func _init(p_) -> void:
	p = p_


func build_camera() -> void:
	p.cam_yaw = Node3D.new()
	p.cam_yaw.top_level = true
	p.add_child(p.cam_yaw)
	p.cam_pitch = Node3D.new()
	p.cam_pitch.rotation.x = -0.35
	p.cam_yaw.add_child(p.cam_pitch)
	var spring := SpringArm3D.new()
	spring.spring_length = 5.4
	spring.margin = 0.3
	spring.collision_mask = 1
	p.cam_pitch.add_child(spring)
	p.camera = Camera3D.new()
	p.camera.fov = 60
	spring.add_child(p.camera)
	p.camera.current = true


func local_sim(delta: float) -> void:
	p.state_time += delta
	p.dodge_cooldown = maxf(0, p.dodge_cooldown - delta)
	p.iframes = maxf(0, p.iframes - delta)
	p.combo_reset = maxf(0, p.combo_reset - delta)
	if p.combo_reset == 0 and p.state != "attack":
		p.combo_step = 0
	p.shake = maxf(0, p.shake - delta * 1.8)
	update_camera(delta)

	if p.state == "dead" or p.state == "downed":
		p.velocity.x = 0
		p.velocity.z = 0
		p.velocity.y -= p.GRAVITY * delta
		p.move_and_slide()
		send_state(delta)
		return

	var input_captured: bool = not p.game.ui_blocked
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_captured else Vector2.ZERO
	var cam_basis: Basis = p.cam_yaw.global_transform.basis
	p._move_dir = cam_basis * Vector3(iv.x, 0, iv.y)
	var moving: bool = p._move_dir.length_squared() > 0.01
	if moving:
		p._move_dir = p._move_dir.normalized()
	var running: bool = Input.is_action_pressed("run") and input_captured
	var want_block: bool = Input.is_action_pressed("block") and input_captured

	var speed_mul := 1.0
	p.blocking = false

	match p.state:
		"attack":
			speed_mul = 0.12
			var step: Dictionary = p.active_combo()[p.combo_step]
			if not p.hit_done and p.state_time >= p.attack_dur * 0.38:
				p.hit_done = true
				p.combat.deal_damage(step)
			if p.state_time >= p.attack_dur * 0.72 and p.combo_queued:
				p.combo_step = (p.combo_step + 1) % p.active_combo().size()
				p.combat.start_attack()
			elif p.state_time >= p.attack_dur:
				p.state = "idle"
				p.combo_step = (p.combo_step + 1) % p.active_combo().size()
				p.combo_reset = 1.2
		"dodge":
			var t: float = p.state_time / 0.45
			if t >= 1.0:
				p.state = "idle"
			else:
				var sp := 10.0 * (1.0 - t * 0.6)
				p.velocity.x = p.dodge_dir.x * sp
				p.velocity.z = p.dodge_dir.z * sp
				speed_mul = 0.0
		"hit":
			speed_mul = 0.25
			if p.state_time > 0.4:
				p.state = "idle"
		"revive_up":
			speed_mul = 0.0
			if p.state_time > 1.0:
				p.state = "idle"
		"reviving":
			# наклон над упавшим товарищем, пока держим [E] — раньше тут не менялось вообще ничего
			speed_mul = 0.0
			var dn = p.game.player_nodes.get(_revive_target_id)
			if dn != null:
				p.facing = rotate_toward(p.facing, atan2(dn.global_position.x - p.global_position.x, dn.global_position.z - p.global_position.z), p.TURN_SPEED * delta)
		"block_hit":
			speed_mul = 0.2
			p.blocking = true
			if p.state_time > 0.3:
				p.state = "block" if want_block else "idle"
				if p.state == "block":
					p._play("Blocking")
		"block":
			speed_mul = 0.35
			p.blocking = true
			if not want_block:
				p.state = "idle"
			p.facing = rotate_toward(p.facing, p.cam_yaw.rotation.y + PI, p.TURN_SPEED * delta)
		_:
			if want_block:
				p.state = "block"
				p._play("Blocking")

	# поднятие павшего друга (E рядом с упавшим) — наклоняемся и тянем, а не стоим истуканом
	_revive_send_timer -= delta
	var reviving_now := false
	if input_captured and Input.is_action_pressed("interact") and p.state in ["idle", "block", "reviving"]:
		var target_id: int = p.game.find_downed_near(p.global_position, 3.4, p.peer_id)
		if target_id != 0:
			reviving_now = true
			_revive_target_id = target_id
			if p.state != "reviving":
				p.state = "reviving"
				p.state_time = 0.0
				p._play("PickUp", 1.0)
			if _revive_send_timer <= 0:
				_revive_send_timer = 0.15
				Net.req_revive(target_id)
	if p.state == "reviving" and not reviving_now:
		p.state = "idle"

	# подсказка взаимодействия (сундук / павший друг)
	_hint_timer -= delta
	if _hint_timer <= 0:
		_hint_timer = 0.2
		var key: String = p.game.main.key_name("interact")
		var downed_id: int = p.game.find_downed_near(p.global_position, 3.4, p.peer_id)
		var npc_i: int = p.game.find_npc_near(p.global_position, 2.6)
		var qn_id: int = p.game.find_qnode_near(p.global_position, 2.6)
		if downed_id != 0:
			var dname: String = Net.players[downed_id].name if Net.players.has(downed_id) else tr("союзника")
			p.game.hud.set_hint(tr("Держи [%s] — поднять %s") % [key, dname])
		elif npc_i == 2:
			p.game.hud.set_hint(tr("[%s] — нанять мага (%d золота)") % [key, Game.HIRE_COST])
		elif npc_i == 3:
			p.game.hud.set_hint(tr("[%s] — торговать") % key)
		elif npc_i >= 0:
			p.game.hud.set_hint(tr("[%s] — говорить") % key)
		elif qn_id != 0:
			p.game.hud.set_hint(tr("[%s] — взять / разжечь") % key)
		elif p.game.find_chest_near(p.global_position, 2.4) != 0:
			p.game.hud.set_hint(tr("[%s] — открыть сундук") % key)
		elif p.game.secret_near(p.global_position, 3.0):
			p.game.hud.set_hint(tr("[%s] — расшатать кладку") % key)
		else:
			var poi_hint_idx: int = p.game.find_poi_near(p.global_position, 3.2)
			if poi_hint_idx >= 0:
				match p.game.world_pois[poi_hint_idx].kind:
					"shrine":
						p.game.hud.set_hint(tr("[%s] — попросить благословения") % key)
					"campfire":
						p.game.hud.set_hint(tr("[%s] — согреться у костра") % key)
					"well":
						p.game.hud.set_hint(tr("[%s] — испить воды") % key)
					"bounty_board":
						p.game.hud.set_hint(tr("[%s] — принять заказ") % key)
					_:
						p.game.hud.set_hint(tr("[%s] — осмотреть") % key)
			else:
				p.game.hud.set_hint("")

	# перемещение
	if p.state != "dodge":
		if moving and speed_mul > 0:
			var buff_speed := 1.35 if p.has_buff("speed") else 1.0
			var stat_speed: float = Quests.speed_mult_for(Net.players.get(Net.my_id, {})) \
				* Items.equip_speed_mult(p.game.my_equip) if p.is_local else 1.0
			var speed: float = (p.RUN_SPEED if running else p.WALK_SPEED) * speed_mul * buff_speed * stat_speed
			p.velocity.x = p._move_dir.x * speed
			p.velocity.z = p._move_dir.z * speed
			if p.state != "block" and p.state != "attack":
				p.facing = rotate_toward(p.facing, atan2(p._move_dir.x, p._move_dir.z), p.TURN_SPEED * delta)
		else:
			p.velocity.x = move_toward(p.velocity.x, 0, 30 * delta)
			p.velocity.z = move_toward(p.velocity.z, 0, 30 * delta)
	p.velocity.y -= p.GRAVITY * delta
	p.move_and_slide()
	if p.is_on_floor():
		p.velocity.y = 0
	p.model.rotation.y = p.facing

	# локомоция
	if p.state == "idle":
		if moving:
			p._play("Running_A" if running else "Walking_A")
		else:
			p._play("Idle")

	p.noise_radius = 22.0 if p.state == "attack" else (14.0 if (moving and running) else (7.0 if moving else 3.0))

	send_state(delta)


## Адаптивная отправка состояния: 20 Гц в движении, 5 Гц в покое.
func send_state(delta: float) -> void:
	send_timer -= delta
	if send_timer > 0:
		return
	var anim_idx: int = p.ANIM_TABLE.find(p.current_anim)
	var moved: bool = p.global_position.distance_squared_to(_last_sent_pos) > 0.0004
	var anim_changed := anim_idx != _last_sent_anim
	if not moved and not anim_changed and send_timer > -0.2:
		return # покой: шлём раз в 0.2 c
	send_timer = 0.05
	_last_sent_anim = anim_idx
	_last_sent_pos = p.global_position
	var flags := 0
	if p.blocking:
		flags |= 1
	if p.iframes > 0:
		flags |= 2
	var pkt := PackedFloat32Array([p.global_position.x, p.global_position.z, p.facing, float(anim_idx), float(flags)])
	Net.send_player_state(pkt)


func puppet_sim(delta: float) -> void:
	# павшие и мёртвые не перетираются сетевой локомоцией
	if p.state == "dead" or p.state == "downed":
		return
	var target := Vector3(p.net_pos.x, 0, p.net_pos.z)
	p.global_position = p.global_position.lerp(target, minf(1.0, 14 * delta))
	p.global_position.y = 0
	p.facing = lerp_angle(p.facing, p.net_rot, minf(1.0, 14 * delta))
	p.model.rotation.y = p.facing
	if p.net_anim != "" and p.net_anim != p.current_anim:
		var speed := 1.0
		if p.net_anim.contains("Melee_Attack"):
			speed = 1.3
			Sfx.play_at("swing", p.global_position)
		p._play(p.net_anim, speed)


func update_camera(delta: float) -> void:
	var target: Vector3 = p.global_position + Vector3(0, 1.5, 0)
	p.cam_yaw.global_position = p.cam_yaw.global_position.lerp(target, minf(1.0, 12 * delta))
	if p.shake > 0.001:
		p.cam_yaw.global_position += Vector3(
			randf_range(-p.shake, p.shake) * 0.35,
			randf_range(-p.shake, p.shake) * 0.35,
			randf_range(-p.shake, p.shake) * 0.35
		)
