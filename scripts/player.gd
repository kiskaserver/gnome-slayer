class_name PlayerChar
extends CharacterBody3D
## Рыцарь. Локальный игрок обрабатывает ввод и рассылает своё состояние,
## чужие игроки — марионетки, интерполируемые по сети.

const WALK_SPEED := 3.2
const RUN_SPEED := 6.2
const TURN_SPEED := 12.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0026

# Анимации кодируются индексом в сетевых пакетах (не строками).
const ANIM_TABLE := [
	"Idle", "Walking_A", "Running_A", "Blocking", "Block_Hit", "Hit_A",
	"Death_A", "Dodge_Forward", "Cheer", "Lie_StandUp",
	"1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Chop",
	"2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Chop",
	"PickUp",
]

const COMBO_1H := [
	{"anim": "1H_Melee_Attack_Slice_Horizontal", "dmg": 14, "range": 2.6, "arc": 1.25, "ts": 1.45},
	{"anim": "1H_Melee_Attack_Slice_Diagonal", "dmg": 14, "range": 2.6, "arc": 1.25, "ts": 1.45},
	{"anim": "1H_Melee_Attack_Chop", "dmg": 26, "range": 2.9, "arc": 1.5, "ts": 1.25},
]
# Великий меч: медленнее, больнее, шире дуга
const COMBO_2H := [
	{"anim": "2H_Melee_Attack_Slice", "dmg": 21, "range": 3.0, "arc": 1.6, "ts": 1.3},
	{"anim": "2H_Melee_Attack_Spin", "dmg": 21, "range": 3.2, "arc": 2.7, "ts": 1.25},
	{"anim": "2H_Melee_Attack_Chop", "dmg": 36, "range": 3.2, "arc": 1.7, "ts": 1.1},
]

const HIDE_1H := ["2H_Sword", "Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield"]
const LOOP_ANIMS := ["Idle", "Walking_A", "Running_A", "Blocking", "Walking_Backwards", "PickUp"]

var game: Node = null
var peer_id: int = 1
var player_name: String = ""
var is_local: bool = false

var model: Node3D = null
var anim_player: AnimationPlayer = null
var current_anim: String = ""

var max_hp := 100
var hp := 100
var facing := 0.0
var state := "idle" # idle | attack | dodge | block | block_hit | hit | downed | revive_up | dead
var state_time := 0.0
var noise_radius := 3.0

# атака
var combo_step := 0
var combo_queued := false
var attack_dur := 0.0
var hit_done := false
var combo_reset := 0.0

# кувырок / блок
var dodge_dir := Vector3.ZERO
var dodge_cooldown := 0.0
var iframes := 0.0
var blocking := false

# бафы: тип -> оставшееся время
var buffs: Dictionary = {}

# камера (только локальный)
var cam_yaw: Node3D = null
var cam_pitch: Node3D = null
var camera: Camera3D = null
var shake := 0.0

# сеть
var net_pos := Vector3.ZERO
var net_rot := 0.0
var net_anim := ""
var send_timer := 0.0
var _last_sent_anim := -1
var _last_sent_pos := Vector3.ZERO
var _revive_send_timer := 0.0
var _revive_target_id := 0
var _hint_timer := 0.0

var name_label: Label3D = null
var _move_dir := Vector3.ZERO


func setup(g: Node, id: int, pname: String, color: Color) -> void:
	game = g
	peer_id = id
	player_name = pname
	is_local = (id == Net.my_id)
	name = "P%d" % id

	collision_layer = 2
	collision_mask = 1 | 2 | 4

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)

	model = game.models["Knight"].instantiate()
	add_child(model)
	anim_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim_player.playback_default_blend_time = 0.18
	for a in LOOP_ANIMS:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_prepare_model(color)
	_update_weapon()
	facing = PI # спиной к камере
	model.rotation.y = facing
	_play("Idle")

	if is_local:
		_build_camera()
	else:
		name_label = Label3D.new()
		name_label.text = pname
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.position.y = 2.45
		name_label.pixel_size = 0.008
		name_label.outline_size = 8
		name_label.modulate = Color(1, 0.95, 0.7)
		add_child(name_label)


func _prepare_model(color: Color) -> void:
	for mesh_inst in model.find_children("*", "MeshInstance3D", true, false):
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if color != Color.WHITE:
			for i in mesh_inst.get_surface_override_material_count():
				var mat = mesh_inst.get_active_material(i)
				if mat != null:
					var m2 = mat.duplicate()
					m2.albedo_color = color
					mesh_inst.set_surface_override_material(i, m2)


var weapon_id := "sword1h"       # класс оружия в руках (реплицируется)
var _attached_weapon: Node3D = null


## Показывает нужное оружие: запечённые меши Knight для мечей/щита,
## рантайм-модель из пака Adventurers для топоров/кинжала. Кристалл
## «великий меч» временно переключает на sword2h.
func _update_weapon() -> void:
	var wid := "sword2h" if has_buff("greatsword") else weapon_id
	var cls: Dictionary = Items.WEAPONS.get(wid, Items.WEAPONS["sword1h"])
	var baked: String = cls.baked
	var want_shield: bool = cls.shield
	for mesh_inst in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(mesh_inst.name)
		if n.contains("2H_Sword"):
			mesh_inst.visible = baked == "2H_Sword"
		elif n.contains("1H_Sword") and not n.contains("Offhand"):
			mesh_inst.visible = baked == "1H_Sword"
		elif n.contains("Round_Shield"):
			mesh_inst.visible = want_shield
		else:
			for p in HIDE_1H:
				if n.contains(p):
					mesh_inst.visible = false
					break
	# рантайм-модель в правую руку (топор/кинжал)
	if _attached_weapon != null:
		_attached_weapon.queue_free()
		_attached_weapon = null
	if cls.model != "":
		var slot := model.find_children("handslot.r", "", true, false)
		if not slot.is_empty():
			var wnode: Node3D = game.weapon_scene(cls.model).instantiate()
			slot[0].add_child(wnode)
			_attached_weapon = wnode
			for mi in wnode.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Реплика: чем машет этот игрок (для всех клиентов).
func set_weapon_visual(wid: String) -> void:
	if not Items.WEAPONS.has(wid):
		wid = "sword1h"
	weapon_id = wid
	combo_step = 0
	_update_weapon()


## Локально: сервер подтвердил новую экипировку.
func on_equip_changed(eq: Dictionary) -> void:
	var w: Dictionary = eq.get("weapon", {})
	set_weapon_visual(w.get("id", "sword1h"))


func active_combo() -> Array:
	if has_buff("greatsword"):
		return Items.WEAPONS["sword2h"].combo
	if is_local:
		return Items.combo_for(game.my_equip)
	return Items.WEAPONS.get(weapon_id, Items.WEAPONS["sword1h"]).combo


func has_buff(type: String) -> bool:
	return buffs.get(type, 0.0) > 0.0


func apply_buff(type: String, dur: float) -> void:
	if type == "shield_end":
		buffs.erase("shield")
		if is_local:
			game.hud.set_buffs(buffs) # иначе иконка барьера зависает на экране
		return
	var had_gs := has_buff("greatsword")
	buffs[type] = dur
	if type == "greatsword" and not had_gs:
		combo_step = 0
		_update_weapon()
	if is_local:
		game.hud.set_buffs(buffs)


func _tick_buffs(delta: float) -> void:
	var changed := false
	for type in buffs.keys():
		if buffs[type] >= 900.0:
			continue # «вечные» (барьер) — снимаются событием
		buffs[type] -= delta
		if buffs[type] <= 0.0:
			buffs.erase(type)
			changed = true
			if type == "greatsword":
				combo_step = 0
				_update_weapon()
	if is_local and (changed or not buffs.is_empty()):
		game.hud.set_buffs(buffs) # обновляем каждый кадр — тикают секунды


func _build_camera() -> void:
	cam_yaw = Node3D.new()
	cam_yaw.top_level = true
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation.x = -0.35
	cam_yaw.add_child(cam_pitch)
	var spring := SpringArm3D.new()
	spring.spring_length = 5.4
	spring.margin = 0.3
	spring.collision_mask = 1
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 60
	spring.add_child(camera)
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or state == "dead" or state == "downed" or game.ui_blocked:
		return
	if event is InputEventMouseMotion:
		var sens: float = MOUSE_SENS * Settings.mouse_sens
		var dy: float = event.relative.y * (-1.0 if Settings.invert_y else 1.0)
		cam_yaw.rotation.y -= event.relative.x * sens
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - dy * sens * 0.85, -1.15, 0.35)
	if event.is_action_pressed("attack"):
		try_attack()
	elif event.is_action_pressed("dodge"):
		try_dodge()
	elif event.is_action_pressed("interact"):
		# приоритет: поднять друга (удержание) > НПС > квест-объект > сундук
		if game.find_downed_near(global_position, 3.4, peer_id) == 0:
			var npc_idx: int = game.find_npc_near(global_position, 2.6)
			var qid: int = game.find_qnode_near(global_position, 2.6)
			var cid: int = game.find_chest_near(global_position, 2.4)
			var poi_idx: int = game.find_poi_near(global_position, 3.2)
			if npc_idx >= 0:
				game.start_dialog(npc_idx)
			elif qid != 0:
				Net.req_qnode(qid)
			elif cid != 0:
				Net.req_open_chest(cid)
			elif poi_idx >= 0:
				var poi_kind: String = game.world_pois[poi_idx].kind
				match poi_kind:
					"shrine":
						Net.req_shrine(poi_idx)
						Achievements.unlock("blessed")
					"campfire":
						Net.req_poi(poi_idx)
						Achievements.unlock("campfire_rest")
					"well":
						Net.req_poi(poi_idx)
						Achievements.unlock("well_wisher")
					"bounty_board":
						Net.req_poi(poi_idx)
						Achievements.unlock("bounty_board")
					_:
						game.start_lore(poi_idx)
	elif event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.physical_keycode:
			KEY_1: slot = 0
			KEY_2: slot = 1
			KEY_3: slot = 2
			KEY_4: slot = 3
			KEY_5: slot = 4
		if slot >= 0:
			game.use_item_slot(slot)


func _play(anim: String, custom_speed: float = 1.0) -> float:
	if anim_player == null or not anim_player.has_animation(anim):
		return 0.0
	if current_anim == anim and custom_speed == 1.0 and anim in LOOP_ANIMS:
		return anim_player.get_animation(anim).length
	current_anim = anim
	anim_player.play(anim, -1, custom_speed)
	if custom_speed != 1.0:
		anim_player.seek(0.0)
	return anim_player.get_animation(anim).length / absf(custom_speed)


# ---------------------------------------------------------------------------
# Бой
# ---------------------------------------------------------------------------
func try_attack() -> void:
	if state == "dead" or state == "downed":
		return
	if state == "attack":
		if state_time > attack_dur * 0.3:
			combo_queued = true
		return
	if state in ["dodge", "hit", "revive_up"]:
		return
	_start_attack()


func _start_attack() -> void:
	var step: Dictionary = active_combo()[combo_step]
	state = "attack"
	state_time = 0.0
	hit_done = false
	combo_queued = false
	attack_dur = _play(step.anim, step.ts)
	Sfx.play_at("swing", global_position)
	_face_nearest_enemy()


func _face_nearest_enemy() -> void:
	var best = null
	var best_d := 5.5
	for g in game.gnomes.values():
		if not g.alive or g.friendly:
			continue # не доворачиваемся к своему наёмнику
		var d: float = g.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = g
	if game.is_pvp():
		for p in game.player_nodes.values():
			if p == self or p.state == "dead":
				continue
			var d: float = p.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = p
	if best != null:
		var dx: float = best.global_position.x - global_position.x
		var dz: float = best.global_position.z - global_position.z
		facing = atan2(dx, dz)


func try_dodge() -> void:
	if state in ["dead", "downed", "dodge", "revive_up", "reviving"] or dodge_cooldown > 0:
		return
	if state == "attack" and state_time < attack_dur * 0.5:
		return
	state = "dodge"
	state_time = 0.0
	iframes = 0.45
	var me: Dictionary = Net.players.get(Net.my_id, {})
	dodge_cooldown = 0.9 * (1.0 - 0.05 * me.get("agi", 0)) * Skills.dodge_cd_mult(me) if is_local else 0.9
	var dir := _move_dir if _move_dir.length_squared() > 0.01 else Vector3(sin(facing), 0, cos(facing))
	dodge_dir = dir.normalized()
	facing = atan2(dodge_dir.x, dodge_dir.z)
	_play("Dodge_Forward", 1.5)
	Sfx.play_at("roll", global_position)


func _deal_damage(step: Dictionary) -> void:
	var targets: Array = []
	for id in game.gnomes:
		var g = game.gnomes[id]
		if not g.alive or g.friendly:
			continue # свой наёмник не получает урона от игрока
		if _in_arc(g.global_position, step.range + 0.45, step.arc):
			targets.append(["g", id])
	if game.is_pvp():
		for id in game.player_nodes:
			if id == peer_id:
				continue
			var p = game.player_nodes[id]
			if p.state == "dead" or p.state == "downed":
				continue
			if _in_arc(p.global_position, step.range + 0.45, step.arc):
				targets.append(["p", id])
	if targets.is_empty():
		return
	var me: Dictionary = Net.players.get(Net.my_id, {})
	var crit := randf() < Quests.crit_chance_for(me) + Items.equip_crit_bonus(game.my_equip)
	var dmg_f: float = step.dmg * (1.5 if has_buff("rage") else 1.0) * Quests.dmg_mult_for(me) \
		* Items.equip_dmg_mult(game.my_equip)
	var dmg: int = roundi(dmg_f * (1.8 * Quests.crit_dmg_mult_for(me) if crit else 1.0))
	Net.req_melee(targets, dmg, crit)
	Sfx.play_at("hit", global_position)
	add_shake(0.12)
	if is_local:
		game.hud.combo_flash(combo_step + 1)


func _in_arc(target: Vector3, dist: float, arc: float) -> bool:
	var dx := target.x - global_position.x
	var dz := target.z - global_position.z
	if Vector2(dx, dz).length() > dist:
		return false
	return absf(angle_difference(atan2(dx, dz), facing)) < arc


## Визуальная реакция на изменение HP (сервер уже применил урон).
## flag: hit | block | dodge | heal | shield
func on_hp_event(new_hp: int, flag: String, from_pos: Vector3) -> void:
	var old_hp := hp
	hp = new_hp
	if state == "dead" or state == "downed":
		if is_local:
			game.hud.set_hp(hp, max_hp)
		return
	match flag:
		"dodge":
			game.fx_number(global_position, tr("уворот!"), Color(0.5, 0.9, 0.4))
		"shield":
			game.fx_number(global_position, tr("барьер!"), Color(0.4, 0.75, 1.0))
			game.fx_burst(global_position + Vector3(0, 1.2, 0), Color(0.4, 0.75, 1.0), 8)
			Sfx.play_at("block", global_position)
		"block":
			_play("Block_Hit", 1.3)
			state = "block_hit"
			state_time = 0.0
			Sfx.play_at("block", global_position)
			game.fx_burst(global_position + Vector3(0, 1.2, 0), Color(1, 0.95, 0.7), 8)
			game.fx_number(global_position, str(new_hp - old_hp), Color(1, 0.6, 0.5))
		"heal":
			game.fx_number(global_position, "+%d" % (new_hp - old_hp), Color(0.5, 0.9, 0.4))
			Sfx.play_at("pickup", global_position)
		_:
			game.fx_number(global_position, str(new_hp - old_hp), Color(1, 0.45, 0.4))
			game.fx_burst(global_position + Vector3(0, 1.2, 0), Color(0.75, 0.1, 0.1), 10)
			Sfx.play_at("player_hurt", global_position)
			if is_local:
				add_shake(0.25)
				game.hud.hurt_flash()
			if state != "attack" and state != "dodge":
				state = "hit"
				state_time = 0.0
				_play("Hit_A", 1.4)
	if is_local:
		game.hud.set_hp(hp, max_hp)


func die() -> void:
	state = "dead"
	state_time = 0.0
	blocking = false
	iframes = 0.0
	_play("Death_A")
	Sfx.play_at("player_death", global_position)
	if is_local:
		game.hud.set_hp(0, max_hp)


## Нокдаун (ПвЕ-кооп): лежит, ждёт поднятия.
func go_downed() -> void:
	state = "downed"
	state_time = 0.0
	hp = 0
	blocking = false
	iframes = 0.0
	_play("Death_A")
	Sfx.play_at("player_death", global_position, 0.0, 1.2)
	if name_label != null:
		name_label.modulate = Color(1, 0.4, 0.35)
		name_label.text = player_name + tr(" (пал)")
	if is_local:
		game.hud.set_hp(0, max_hp)


func on_revived(new_hp: int) -> void:
	hp = new_hp
	state = "revive_up"
	state_time = 0.0
	var dur := _play("Lie_StandUp", 1.4)
	if dur <= 0:
		state = "idle"
	elif not is_local:
		# марионетка сама не выйдет из revive_up — вернём в idle по таймеру-ребёнку
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = dur + 0.2
		add_child(t)
		t.timeout.connect(func():
			if state == "revive_up":
				state = "idle"
			t.queue_free())
		t.start()
	if name_label != null:
		name_label.modulate = Color(1, 0.95, 0.7)
		name_label.text = player_name
	game.fx_burst(global_position + Vector3(0, 1, 0), Color(0.5, 0.9, 0.4), 14)
	Sfx.play_at("pickup", global_position)
	if is_local:
		game.hud.set_hp(hp, max_hp)
		game.hud.center_msg("")


func respawn(x: float, z: float) -> void:
	global_position = Vector3(x, 0.1, z)
	hp = max_hp
	state = "idle"
	state_time = 0.0
	buffs.clear()
	_update_weapon()
	_play("Idle")
	if name_label != null:
		name_label.modulate = Color(1, 0.95, 0.7)
		name_label.text = player_name
	if is_local:
		game.hud.set_hp(hp, max_hp)
		game.hud.set_buffs(buffs)
		game.hud.center_msg("")


func play_victory() -> void:
	if state != "dead" and state != "downed":
		state = "idle"
		_play("Cheer")


func add_shake(v: float) -> void:
	if is_local:
		shake = minf(shake + v, 0.5)


# ---------------------------------------------------------------------------
# Симуляция
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_tick_buffs(delta)
	if is_local:
		_local_sim(delta)
	else:
		_puppet_sim(delta)


func _local_sim(delta: float) -> void:
	state_time += delta
	dodge_cooldown = maxf(0, dodge_cooldown - delta)
	iframes = maxf(0, iframes - delta)
	combo_reset = maxf(0, combo_reset - delta)
	if combo_reset == 0 and state != "attack":
		combo_step = 0
	shake = maxf(0, shake - delta * 1.8)
	_update_camera(delta)

	if state == "dead" or state == "downed":
		velocity.x = 0
		velocity.z = 0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		_send_state(delta)
		return

	var input_captured: bool = not game.ui_blocked
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_captured else Vector2.ZERO
	var cam_basis := cam_yaw.global_transform.basis
	_move_dir = cam_basis * Vector3(iv.x, 0, iv.y)
	var moving := _move_dir.length_squared() > 0.01
	if moving:
		_move_dir = _move_dir.normalized()
	var running: bool = Input.is_action_pressed("run") and input_captured
	var want_block: bool = Input.is_action_pressed("block") and input_captured

	var speed_mul := 1.0
	blocking = false

	match state:
		"attack":
			speed_mul = 0.12
			var step: Dictionary = active_combo()[combo_step]
			if not hit_done and state_time >= attack_dur * 0.38:
				hit_done = true
				_deal_damage(step)
			if state_time >= attack_dur * 0.72 and combo_queued:
				combo_step = (combo_step + 1) % active_combo().size()
				_start_attack()
			elif state_time >= attack_dur:
				state = "idle"
				combo_step = (combo_step + 1) % active_combo().size()
				combo_reset = 1.2
		"dodge":
			var t := state_time / 0.45
			if t >= 1.0:
				state = "idle"
			else:
				var sp := 10.0 * (1.0 - t * 0.6)
				velocity.x = dodge_dir.x * sp
				velocity.z = dodge_dir.z * sp
				speed_mul = 0.0
		"hit":
			speed_mul = 0.25
			if state_time > 0.4:
				state = "idle"
		"revive_up":
			speed_mul = 0.0
			if state_time > 1.0:
				state = "idle"
		"reviving":
			# наклон над упавшим товарищем, пока держим [E] — раньше тут не менялось вообще ничего
			speed_mul = 0.0
			var dn = game.player_nodes.get(_revive_target_id)
			if dn != null:
				facing = rotate_toward(facing, atan2(dn.global_position.x - global_position.x, dn.global_position.z - global_position.z), TURN_SPEED * delta)
		"block_hit":
			speed_mul = 0.2
			blocking = true
			if state_time > 0.3:
				state = "block" if want_block else "idle"
				if state == "block":
					_play("Blocking")
		"block":
			speed_mul = 0.35
			blocking = true
			if not want_block:
				state = "idle"
			facing = rotate_toward(facing, cam_yaw.rotation.y + PI, TURN_SPEED * delta)
		_:
			if want_block:
				state = "block"
				_play("Blocking")

	# поднятие павшего друга (E рядом с упавшим) — наклоняемся и тянем, а не стоим истуканом
	_revive_send_timer -= delta
	var reviving_now := false
	if input_captured and Input.is_action_pressed("interact") and state in ["idle", "block", "reviving"]:
		var target_id: int = game.find_downed_near(global_position, 3.4, peer_id)
		if target_id != 0:
			reviving_now = true
			_revive_target_id = target_id
			if state != "reviving":
				state = "reviving"
				state_time = 0.0
				_play("PickUp", 1.0)
			if _revive_send_timer <= 0:
				_revive_send_timer = 0.15
				Net.req_revive(target_id)
	if state == "reviving" and not reviving_now:
		state = "idle"

	# подсказка взаимодействия (сундук / павший друг)
	_hint_timer -= delta
	if _hint_timer <= 0:
		_hint_timer = 0.2
		var key: String = game.main.key_name("interact")
		var downed_id: int = game.find_downed_near(global_position, 3.4, peer_id)
		var npc_i: int = game.find_npc_near(global_position, 2.6)
		var qn_id: int = game.find_qnode_near(global_position, 2.6)
		if downed_id != 0:
			var dname: String = Net.players[downed_id].name if Net.players.has(downed_id) else tr("союзника")
			game.hud.set_hint(tr("Держи [%s] — поднять %s") % [key, dname])
		elif npc_i == 2:
			game.hud.set_hint(tr("[%s] — нанять мага (%d золота)") % [key, Game.HIRE_COST])
		elif npc_i == 3:
			game.hud.set_hint(tr("[%s] — торговать") % key)
		elif npc_i >= 0:
			game.hud.set_hint(tr("[%s] — говорить") % key)
		elif qn_id != 0:
			game.hud.set_hint(tr("[%s] — взять / разжечь") % key)
		elif game.find_chest_near(global_position, 2.4) != 0:
			game.hud.set_hint(tr("[%s] — открыть сундук") % key)
		else:
			var poi_hint_idx: int = game.find_poi_near(global_position, 3.2)
			if poi_hint_idx >= 0:
				match game.world_pois[poi_hint_idx].kind:
					"shrine":
						game.hud.set_hint(tr("[%s] — попросить благословения") % key)
					"campfire":
						game.hud.set_hint(tr("[%s] — согреться у костра") % key)
					"well":
						game.hud.set_hint(tr("[%s] — испить воды") % key)
					"bounty_board":
						game.hud.set_hint(tr("[%s] — принять заказ") % key)
					_:
						game.hud.set_hint(tr("[%s] — осмотреть") % key)
			else:
				game.hud.set_hint("")

	# перемещение
	if state != "dodge":
		if moving and speed_mul > 0:
			var buff_speed := 1.35 if has_buff("speed") else 1.0
			var stat_speed: float = Quests.speed_mult_for(Net.players.get(Net.my_id, {})) \
				* Items.equip_speed_mult(game.my_equip) if is_local else 1.0
			var speed := (RUN_SPEED if running else WALK_SPEED) * speed_mul * buff_speed * stat_speed
			velocity.x = _move_dir.x * speed
			velocity.z = _move_dir.z * speed
			if state != "block" and state != "attack":
				facing = rotate_toward(facing, atan2(_move_dir.x, _move_dir.z), TURN_SPEED * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, 30 * delta)
			velocity.z = move_toward(velocity.z, 0, 30 * delta)
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0
	model.rotation.y = facing

	# локомоция
	if state == "idle":
		if moving:
			_play("Running_A" if running else "Walking_A")
		else:
			_play("Idle")

	noise_radius = 22.0 if state == "attack" else (14.0 if (moving and running) else (7.0 if moving else 3.0))

	_send_state(delta)


## Адаптивная отправка состояния: 20 Гц в движении, 5 Гц в покое.
func _send_state(delta: float) -> void:
	send_timer -= delta
	if send_timer > 0:
		return
	var anim_idx := ANIM_TABLE.find(current_anim)
	var moved: bool = global_position.distance_squared_to(_last_sent_pos) > 0.0004
	var anim_changed := anim_idx != _last_sent_anim
	if not moved and not anim_changed and send_timer > -0.2:
		return # покой: шлём раз в 0.2 c
	send_timer = 0.05
	_last_sent_anim = anim_idx
	_last_sent_pos = global_position
	var flags := 0
	if blocking:
		flags |= 1
	if iframes > 0:
		flags |= 2
	var pkt := PackedFloat32Array([global_position.x, global_position.z, facing, float(anim_idx), float(flags)])
	Net.send_player_state(pkt)


func _puppet_sim(delta: float) -> void:
	# павшие и мёртвые не перетираются сетевой локомоцией
	if state == "dead" or state == "downed":
		return
	var target := Vector3(net_pos.x, 0, net_pos.z)
	global_position = global_position.lerp(target, minf(1.0, 14 * delta))
	global_position.y = 0
	facing = lerp_angle(facing, net_rot, minf(1.0, 14 * delta))
	model.rotation.y = facing
	if net_anim != "" and net_anim != current_anim:
		var speed := 1.0
		if net_anim.contains("Melee_Attack"):
			speed = 1.3
			Sfx.play_at("swing", global_position)
		_play(net_anim, speed)


func apply_net_state(pkt: PackedFloat32Array) -> void:
	if pkt.size() < 5:
		return
	net_pos = Vector3(pkt[0], 0, pkt[1])
	net_rot = pkt[2]
	var idx := int(pkt[3])
	net_anim = ANIM_TABLE[idx] if idx >= 0 and idx < ANIM_TABLE.size() else ""
	var flags := int(pkt[4])
	blocking = (flags & 1) != 0
	iframes = 0.3 if (flags & 2) != 0 else 0.0


func _update_camera(delta: float) -> void:
	var target := global_position + Vector3(0, 1.5, 0)
	cam_yaw.global_position = cam_yaw.global_position.lerp(target, minf(1.0, 12 * delta))
	if shake > 0.001:
		cam_yaw.global_position += Vector3(
			randf_range(-shake, shake) * 0.35,
			randf_range(-shake, shake) * 0.35,
			randf_range(-shake, shake) * 0.35
		)


func get_camera_yaw() -> float:
	return cam_yaw.rotation.y if cam_yaw != null else 0.0
