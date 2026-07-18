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

# сеть (отправка/интерполяция — в PlayerLocomotion)
var net_pos := Vector3.ZERO
var net_rot := 0.0
var net_anim := ""

var name_label: Label3D = null
var _move_dir := Vector3.ZERO

var combat: PlayerCombat
var loco: PlayerLocomotion


func setup(g: Node, id: int, pname: String, color: Color) -> void:
	game = g
	combat = PlayerCombat.new(self)
	loco = PlayerLocomotion.new(self)
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


## Стрелковый ли класс сейчас в руках (великий меч-бафф перебивает).
func is_ranged_weapon() -> bool:
	if has_buff("greatsword"):
		return false
	var wid := weapon_id
	if is_local:
		wid = game.my_equip.get("weapon", {}).get("id", "sword1h")
	return Items.WEAPONS.get(wid, {}).get("ranged", false)


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
	loco.build_camera()


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
			elif game.secret_near(global_position, 3.0):
				Net.req_secret()
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
# Бой — логика в PlayerCombat (player_combat.gd)
# ---------------------------------------------------------------------------
func try_attack() -> void:
	combat.try_attack()


func try_dodge() -> void:
	combat.try_dodge()


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
		loco.local_sim(delta)
	else:
		loco.puppet_sim(delta)


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
