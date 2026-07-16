class_name Gnome
extends CharacterBody3D
## Гном. На сервере — полный ИИ: машина состояний, зрение/слух, групповая
## тревога, окружение по слотам, токены атак, обход препятствий по навсетке,
## уклонения (разведчик), лечение союзников (шаман). На клиентах — марионетка.

const GRAVITY := 20.0
const SIGHT_DIST := 17.0
const SIGHT_ANGLE := 1.25
const LOCO := ["Idle", "Walking_A", "Running_A", "2H_Melee_Idle", "Idle_Combat", "Unarmed_Idle"]

# высота модели в юнитах до масштабирования — для лейблов над головой
const MODEL_HEIGHTS := {
	"Barbarian": 1.85, "Rogue_Hooded": 1.8, "Rogue": 1.8, "Mage": 2.25,
	"Skeleton_Warrior": 1.9, "Skeleton_Minion": 1.55,
	"Skeleton_Mage": 2.2, "Skeleton_Rogue": 1.8,
}

const TYPES := {
	"berserker": {
		"model": "Barbarian", "scale": 0.62, "hp": 55, "speed": 3.3, "turn": 7.0,
		"attack_range": 1.8, "attack_dmg": 15, "cd_min": 1.6, "cd_max": 2.6,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin"],
		"attack_ts": 1.15, "ring": 3.0, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"stagger": 0.45, "ranged": false, "retreats": false, "enrage_at": 0.4,
	},
	"scout": {
		"model": "Rogue_Hooded", "scale": 0.55, "hp": 26, "speed": 5.0, "turn": 10.0,
		"attack_range": 1.5, "attack_dmg": 8, "cd_min": 1.2, "cd_max": 2.0,
		"attack_anims": ["Dualwield_Melee_Attack_Stab", "Dualwield_Melee_Attack_Slice"],
		"attack_ts": 1.5, "ring": 4.4, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["Crossbow", "Throwable"],
		"stagger": 0.85, "ranged": false, "retreats": true, "enrage_at": 0.0, "dodges": true,
	},
	"shaman": {
		"model": "Mage", "scale": 0.58, "hp": 30, "speed": 2.9, "turn": 8.0,
		"attack_range": 14.0, "attack_dmg": 12, "cd_min": 2.6, "cd_max": 3.8,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 9.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["1H_Wand", "Spellbook"],
		"stagger": 0.9, "ranged": true, "retreats": false, "enrage_at": 0.0, "heals": true,
	},
	# босс финальной волны — «Вождь», земельной ярости: раз в цикл вбивает
	# оружие в землю и бьёт волной по всем, кто рядом (сигнал — долгий рёв).
	"king": {
		"model": "Barbarian", "scale": 1.05, "hp": 380, "speed": 2.6, "turn": 5.0,
		"attack_range": 2.6, "attack_dmg": 28, "cd_min": 1.8, "cd_max": 2.8,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Slice"],
		"attack_ts": 0.95, "ring": 3.4, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"special": "slam", "special_cd": 9.0, "special_range": 20.0, "special_radius": 5.5, "special_dmg": 24,
		"stagger": 0.06, "ranged": false, "retreats": false, "enrage_at": 0.5,
	},
	# --- зимний лес: морозные гномы ---
	"frost_berserker": {
		"model": "Barbarian", "scale": 0.66, "hp": 72, "speed": 2.9, "turn": 6.0,
		"attack_range": 1.9, "attack_dmg": 18, "cd_min": 1.7, "cd_max": 2.7,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin"],
		"attack_ts": 1.05, "ring": 3.0, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"stagger": 0.35, "ranged": false, "retreats": false, "enrage_at": 0.4,
		"tint": Color(0.6, 0.8, 1.3),
	},
	"frost_shaman": {
		"model": "Mage", "scale": 0.58, "hp": 34, "speed": 2.9, "turn": 8.0,
		"attack_range": 14.0, "attack_dmg": 14, "cd_min": 2.4, "cd_max": 3.6,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 9.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["1H_Wand", "Spellbook"],
		"stagger": 0.9, "ranged": true, "retreats": false, "enrage_at": 0.0, "heals": true,
		"tint": Color(0.6, 0.8, 1.3), "projectile_color": Color(0.45, 0.8, 1.0),
	},
	# «Ледяной король» — вместо статичной ярости раз в цикл делает стремительный
	# рывок к самой дальней цели и бьёт ледяной волной по приземлению.
	"frost_king": {
		"model": "Barbarian", "scale": 1.1, "hp": 440, "speed": 2.5, "turn": 5.0,
		"attack_range": 2.7, "attack_dmg": 32, "cd_min": 1.8, "cd_max": 2.8,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Slice"],
		"attack_ts": 0.92, "ring": 3.4, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"special": "charge", "special_cd": 7.5, "special_range": 22.0, "special_radius": 3.5, "special_dmg": 22,
		"stagger": 0.05, "ranged": false, "retreats": false, "enrage_at": 0.5,
		"tint": Color(0.55, 0.78, 1.35),
	},
	# --- скелеты (ночь и осень), пак KayKit Skeletons ---
	"skeleton_warrior": {
		"model": "Skeleton_Warrior", "scale": 0.85, "hp": 60, "speed": 3.1, "turn": 7.0,
		"attack_range": 1.9, "attack_dmg": 16, "cd_min": 1.5, "cd_max": 2.5,
		"attack_anims": ["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab"],
		"attack_ts": 1.2, "ring": 3.0, "idle_anim": "Idle_Combat",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": [],
		"stagger": 0.4, "ranged": false, "retreats": false, "enrage_at": 0.0,
		"weapon_r": "Skeleton_Blade", "weapon_l": "Skeleton_Shield_Small_A",
	},
	"skeleton_minion": {
		"model": "Skeleton_Minion", "scale": 0.6, "hp": 18, "speed": 5.4, "turn": 10.0,
		"attack_range": 1.3, "attack_dmg": 6, "cd_min": 0.9, "cd_max": 1.7,
		"attack_anims": ["Unarmed_Melee_Attack_Punch_A", "Unarmed_Melee_Attack_Punch_B", "Unarmed_Melee_Attack_Kick"],
		"attack_ts": 1.5, "ring": 3.6, "idle_anim": "Unarmed_Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": [],
		"stagger": 0.9, "ranged": false, "retreats": false, "enrage_at": 0.0,
	},
	"skeleton_mage": {
		"model": "Skeleton_Mage", "scale": 0.8, "hp": 32, "speed": 2.8, "turn": 8.0,
		"attack_range": 14.0, "attack_dmg": 13, "cd_min": 2.5, "cd_max": 3.7,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 9.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": [],
		"stagger": 0.9, "ranged": true, "retreats": false, "enrage_at": 0.0, "heals": true,
		"weapon_r": "Skeleton_Staff", "projectile_color": Color(0.5, 1.0, 0.4),
	},
	"skeleton_rogue": {
		"model": "Skeleton_Rogue", "scale": 0.75, "hp": 28, "speed": 4.8, "turn": 10.0,
		"attack_range": 1.5, "attack_dmg": 9, "cd_min": 1.2, "cd_max": 2.0,
		"attack_anims": ["1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Diagonal"],
		"attack_ts": 1.45, "ring": 4.4, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": [],
		"stagger": 0.85, "ranged": false, "retreats": true, "enrage_at": 0.0, "dodges": true,
		"weapon_r": "Skeleton_Blade",
	},
	# «Костяной король» — не бьёт сам сильнее прочих, а раз в цикл поднимает
	# из земли подкрепление: свежих скелетов-миньонов.
	"skeleton_king": {
		"model": "Skeleton_Warrior", "scale": 1.35, "hp": 400, "speed": 2.5, "turn": 5.0,
		"attack_range": 2.7, "attack_dmg": 30, "cd_min": 1.7, "cd_max": 2.7,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Slice"],
		"attack_ts": 0.92, "ring": 3.4, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": [],
		"special": "summon", "special_cd": 12.0, "special_range": 30.0, "special_count": 2,
		"stagger": 0.05, "ranged": false, "retreats": false, "enrage_at": 0.5,
		"weapon_r": "Skeleton_Axe", "tint": Color(0.75, 1.0, 0.85),
	},
	# --- наёмник игроков: вольный гном-маг (вербуется в лагере за золото) ---
	"ally_mage": {
		"model": "Mage", "scale": 0.58, "hp": 65, "speed": 3.8, "turn": 9.0,
		"attack_range": 15.0, "attack_dmg": 13, "cd_min": 2.0, "cd_max": 3.0,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 8.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["Spellbook"],
		"stagger": 0.8, "ranged": true, "retreats": false, "enrage_at": 0.0,
		# не просто перекрашенный вражеский маг: приглушённый бронзовый убор и
		# плащ отдельно от мантии (вместо ровного оттенка на всей модели) —
		# но без блеска и свечения, чтобы не выбиваться из общей стилистики
		"friendly": true,
		"tint_map": {
			"Hat": Color(1.05, 0.82, 0.48), "Cape": Color(1.05, 0.82, 0.48),
			"Body": Color(1.02, 1.0, 0.9), "Arm": Color(1.02, 1.0, 0.9), "Leg": Color(1.02, 1.0, 0.9),
		},
		"projectile_color": Color(0.35, 0.75, 1.0),
	},
}

var game: Node = null
var gid := 0
var type := ""
var cfg: Dictionary = {}
var is_sim := false

var model: Node3D = null
var anim_player: AnimationPlayer = null
var materials: Array = []
var _materials_full := false  # true, когда собраны уникальные материалы ВСЕХ поверхностей
var current_anim := ""
var one_shot_until := 0.0

var hp := 1
var max_hp := 1
var facing := 0.0
var speed_mul := 1.0
var dmg_mul := 1.0
var enraged := false
var alive := true

var state := "spawn"
var state_time := 0.0
var age := 0.0
var alerted := false
var has_token := false
var attack_timer := 0.0
var attack_dur := 0.0
var attack_did_hit := false
var attack_swinging := false
var slot_angle := 0.0
var waypoint := Vector2.ZERO
var has_waypoint := false
var idle_for := 1.0
var investigate_pos := Vector2.ZERO
var investigating := false
var shout_lock := 0.0
var dead_time := 0.0
var target: Node3D = null
var retarget_timer := 0.0
var knockback := Vector3.ZERO
var last_attacker := 0
var last_attacker_gid := 0  # какой гном нанёс смертельный удар (для прокачки наёмника)
var friendly := false  # наёмник игроков: бьёт гномов, а не рыцарей
var elite := false  # редкий "золотой" гном: больше хп/урона, гарантированный жирный лут
var owner_id := 0      # кто нанял (для следования и зачёта убийств)
var ally_kills := 0    # счётчик убийств наёмника — для его собственной прокачки
var _hire_level := 0   # уровень и hp на момент найма — база для прокачки (ленивая фиксация)
var _hire_max_hp := 0
const ALLY_KILLS_PER_LEVEL := 3
const ALLY_MAX_LEVEL := 5

# --- босс-паттерны: у каждого босса свой фирменный спецприём (cfg.special) ---
var special_timer := 0.0
var is_special := false
var special_phase := ""
var special_time := 0.0

# выход из домика
var emerge_target := Vector2.ZERO

# уклонение разведчика
var sidestep_cd := 0.0
var sidestep_dir := Vector3.ZERO

# лечение шамана
var heal_cd := 3.0
var heal_target: Node3D = null

# навигация
var nav: NavigationAgent3D = null
var _nav_repath := 0.0

# марионетка
var net_pos := Vector3.ZERO
var net_rot := 0.0
var net_loco := 0


var level := 1
var level_dmg_mult := 1.0
var lvl_label: Label3D = null
var net_sent_pos := Vector3(1e9, 0, 1e9)
var net_sent_rot := 1e9
var net_sent_loco := -1
var net_sent_hp := -1


func setup(g: Node, id: int, gtype: String, pos: Vector3, emerge_to := Vector2.ZERO, lvl := 1, is_elite := false) -> void:
	level = maxi(1, lvl)
	level_dmg_mult = Quests.enemy_dmg_mult(level)
	game = g
	gid = id
	type = gtype
	cfg = TYPES[gtype]
	is_sim = Net.is_server
	name = "G%d" % id
	friendly = cfg.get("friendly", false)
	if friendly:
		alerted = true # наёмник всегда начеку
	elite = is_elite and not friendly

	hp = cfg.hp
	max_hp = cfg.hp
	if elite:
		max_hp = roundi(max_hp * 1.8)
		hp = max_hp
		dmg_mul = maxf(dmg_mul, 1.35)
	attack_timer = randf_range(cfg.cd_min, cfg.cd_max)
	if cfg.has("special"):
		special_timer = cfg.get("special_cd", 9.0) * 0.6 # первый спецприём раньше — бой сразу заявляет характер босса

	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * (cfg.scale / 0.6)
	cap.height = 1.1 * (cfg.scale / 0.6)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)

	model = game.models[cfg.model].instantiate()
	model.scale = Vector3.ONE * 0.01
	add_child(model)
	anim_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim_player.playback_default_blend_time = 0.15
	for a in LOCO:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_prepare_model()
	if cfg.has("weapon_r"):
		_attach_weapon(cfg.weapon_r, "r")
	if cfg.has("weapon_l"):
		_attach_weapon(cfg.weapon_l, "l")
	if cfg.has("tint"):
		_ensure_unique_materials()
		for m in materials:
			if m is StandardMaterial3D:
				var t: Color = cfg.tint
				m.albedo_color = Color(m.albedo_color.r * t.r, m.albedo_color.g * t.g, m.albedo_color.b * t.b, 1.0)
				if cfg.get("glow", false):
					m.emission_enabled = true
					m.emission = t
					m.emission_energy_multiplier = 0.4
	elif cfg.has("tint_map"):
		# разные части модели красим по-разному (убор/плащ отдельно от мантии) —
		# читается как свой наряд, а не перекрашенная вражеская модель
		var tmap: Dictionary = cfg.tint_map
		for mesh_inst in model.find_children("*", "MeshInstance3D", true, false):
			if not mesh_inst.visible:
				continue
			var t: Color = Color.WHITE
			var matched := false
			for key in tmap:
				if String(mesh_inst.name).contains(key):
					t = tmap[key]
					matched = true
					break
			if not matched:
				continue
			for i in mesh_inst.get_surface_override_material_count():
				var mat = mesh_inst.get_active_material(i)
				if mat == null or not (mat is StandardMaterial3D):
					continue
				var m2: StandardMaterial3D = mat.duplicate()
				m2.albedo_color = Color(m2.albedo_color.r * t.r, m2.albedo_color.g * t.g, m2.albedo_color.b * t.b, 1.0)
				if cfg.get("glow", false):
					m2.emission_enabled = true
					m2.emission = t
					m2.emission_energy_multiplier = 0.35
				mesh_inst.set_surface_override_material(i, m2)
				materials.append(m2)
	if elite:
		_apply_elite_glow()
	global_position = pos

	if emerge_to != Vector2.ZERO:
		emerge_target = emerge_to
		facing = atan2(emerge_to.x - pos.x, emerge_to.y - pos.z)
	else:
		facing = randf_range(0, TAU)
		emerge_target = Vector2(pos.x, pos.z)

	if level >= 2 or elite:
		_refresh_level_label()

	if is_sim:
		nav = NavigationAgent3D.new()
		nav.path_desired_distance = 0.7
		nav.target_desired_distance = 0.5
		nav.radius = 0.4
		add_child(nav)

	_play("Idle")


func _refresh_level_label() -> void:
	if lvl_label == null:
		lvl_label = Label3D.new()
		lvl_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# высота модели зависит от вида (шляпа мага выше лысины миньона)
		lvl_label.position.y = MODEL_HEIGHTS.get(cfg.model, 1.8) * cfg.scale + 0.45
		lvl_label.pixel_size = 0.007
		lvl_label.outline_size = 7
		add_child(lvl_label)
	if elite:
		lvl_label.text = tr("★ ЭЛИТА ур. %d") % level
		lvl_label.modulate = Color(1.0, 0.83, 0.2)
	elif friendly:
		lvl_label.text = tr("подмастерье ур. %d") % level
		lvl_label.modulate = Color(1.0, 0.85, 0.4)
	else:
		lvl_label.text = tr("ур. %d") % level
		lvl_label.modulate = Color(1.0, 0.75, 0.5) if level >= 4 else Color(0.9, 0.9, 0.85)


## Золотое сияние редкого гнома — мягкий свет и медленные искры, видно издалека.
func _apply_elite_glow() -> void:
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.82, 0.25)
	glow.light_energy = 1.0
	glow.omni_range = 4.5
	glow.position.y = MODEL_HEIGHTS.get(cfg.model, 1.8) * cfg.scale * 0.5
	add_child(glow)

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
	add_child(sparkle)


## Прокачка наёмного мага: за N убитых им гномов — новый уровень (сильнее и живучее).
## Вызывается только на сервере (там же, где решается судьба гнома-жертвы).
func grant_ally_kill() -> void:
	# фиксируем базу найма при первом убийстве: max_hp здесь уже с учётом
	# множителя за размер отряда (см. Game.on_gnome_spawn), а level — уровень главы
	if _hire_level == 0:
		_hire_level = level
		_hire_max_hp = max_hp
	ally_kills += 1
	# уровни считаем ОТ уровня найма, а не от 1 — иначе наёмник высокого уровня
	# первые убийства «в никуда», а max_hp не проседает ниже базового
	var new_level: int = mini(_hire_level + ALLY_MAX_LEVEL - 1, _hire_level + ally_kills / ALLY_KILLS_PER_LEVEL)
	if new_level <= level:
		return
	var steps := new_level - _hire_level
	level = new_level
	max_hp = roundi(_hire_max_hp * (1.0 + 0.18 * steps))
	hp = max_hp
	dmg_mul = 1.0 + 0.2 * steps
	var maxed: bool = steps >= ALLY_MAX_LEVEL - 1
	game.bcast_gnome_event(gid, "levelup", [level, maxed, owner_id])


func _prepare_model() -> void:
	for mesh_inst in model.find_children("*", "MeshInstance3D", true, false):
		var hide := false
		for p in cfg.hide:
			if String(mesh_inst.name).contains(p):
				hide = true
				break
		mesh_inst.visible = not hide
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Подвешивает оружие из пака скелетов в слот руки.
func _attach_weapon(weapon_name: String, side: String) -> void:
	var scene = game.weapon_scene(weapon_name)
	if scene == null:
		return
	for slot in model.find_children("*handslot*", "", true, false):
		var n := String(slot.name).to_lower()
		if n.ends_with(side) or n.ends_with(side + "_"):
			var w: Node3D = scene.instantiate()
			slot.add_child(w)
			for mi in w.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			return


## Свои копии материалов нужны только для ярости/затухания — дублируем лениво.
func _ensure_unique_materials() -> void:
	if _materials_full:
		return
	_materials_full = true
	# идемпотентно по поверхностям: уже уникальные (например перекрашенные из
	# tint_map) не дублируем повторно, но добираем все остальные — иначе труп
	# с tint_map (маг) растворяется лишь частично
	for mesh_inst in model.find_children("*", "MeshInstance3D", true, false):
		if not mesh_inst.visible:
			continue
		for i in mesh_inst.get_surface_override_material_count():
			var mat = mesh_inst.get_active_material(i)
			if mat != null and not materials.has(mat):
				var m2 = mat.duplicate()
				mesh_inst.set_surface_override_material(i, m2)
				materials.append(m2)


func _play(anim: String, custom_speed: float = 1.0, force := false) -> float:
	if anim_player == null or not anim_player.has_animation(anim):
		return 0.0
	if current_anim == anim and not force:
		return anim_player.get_animation(anim).length / absf(custom_speed)
	current_anim = anim
	anim_player.play(anim, -1, custom_speed)
	if custom_speed != 1.0 or force:
		anim_player.seek(0.0)
	return anim_player.get_animation(anim).length / absf(custom_speed)


func loco_index() -> int:
	var i := LOCO.find(current_anim)
	return maxi(i, 0)


# ---------------------------------------------------------------------------
# События (приходят на все машины, включая сервер — call_local)
# ---------------------------------------------------------------------------
func on_event(ev: String, data: Array) -> void:
	match ev:
		"hit":
			var dmg: int = data[0]
			var crit: bool = data[1]
			game.fx_burst(global_position + Vector3(0, 0.7, 0), Color(0.6, 0.07, 0.07), 10)
			game.fx_number(global_position, str(dmg), Color(1, 0.85, 0.4) if not crit else Color(1, 0.55, 0.15))
			if alive and data[2]:
				one_shot_until = age + 0.45
				_play(cfg.hit_anim, 1.5, true)
			# достижение — только тому, кто реально добил (не всем зрителям)
			if data.size() >= 5 and data[3] and data[4] == Net.my_id:
				Achievements.unlock("finisher")
		"attack":
			var anim: String = data[0]
			one_shot_until = age + _play(anim, cfg.attack_ts, true)
			if not cfg.ranged:
				Sfx.play_at("swing", global_position, 0.0, 1.3)
		"heal_cast":
			one_shot_until = age + _play("Spellcast_Long", 1.2, true)
		"healed":
			game.fx_burst(global_position + Vector3(0, 0.8, 0), Color(0.4, 0.9, 0.4), 10)
			game.fx_number(global_position, "+%d" % data[0], Color(0.5, 0.9, 0.4))
			Sfx.play_at("pickup", global_position, -6.0, 0.8)
		"cry":
			one_shot_until = age + 0.6
			_play("Cheer", 1.8, true)
			Sfx.play_at("war_cry", global_position)
		"special_telegraph":
			var kind: String = data[0]
			var label: String = {"slam": "ГОТОВИТ УДАР!", "charge": "ГОТОВИТ РЫВОК!", "summon": "ПРИЗЫВАЕТ ПОДКРЕПЛЕНИЕ!"}.get(kind, "!")
			game.fx_number(global_position, tr(label), Color(1.0, 0.25, 0.15))
			game.fx_burst(global_position + Vector3(0, 0.3, 0), Color(1.0, 0.3, 0.15), 8)
			Sfx.play_at("war_cry", global_position, 2.0, 0.75)
		"special_fx":
			var kind: String = data[0]
			var fx_pos := Vector3(data[1], 0.3, data[2])
			match kind:
				"slam":
					game.fx_burst(fx_pos, Color(1.0, 0.4, 0.1), 26)
					Sfx.play_at("explode", fx_pos, 4.0, 0.85)
				"charge_land":
					game.fx_burst(fx_pos, Color(0.55, 0.78, 1.35), 22)
					Sfx.play_at("explode", fx_pos, 2.0, 1.15)
				"summon":
					game.fx_burst(fx_pos, Color(0.6, 0.9, 0.6), 20)
					Sfx.play_at("gnome_death", fx_pos, -2.0, 0.6)
		"levelup":
			level = data[0]
			_refresh_level_label()
			game.fx_burst(global_position + Vector3(0, 1.3, 0), Color(1.0, 0.85, 0.4), 16)
			game.fx_number(global_position, tr("УРОВЕНЬ %d") % level, Color(1.0, 0.85, 0.4))
			Sfx.play_at("pickup", global_position, 2.0, 1.1)
			if friendly and data.size() >= 3 and data[1] and data[2] == Net.my_id:
				Achievements.unlock("ally_veteran")
		"enrage":
			enraged = true
			_ensure_unique_materials()
			for m in materials:
				if m is StandardMaterial3D:
					m.emission_enabled = true
					m.emission = Color(1.0, 0.13, 0.0)
					m.emission_energy_multiplier = 0.4
			game.fx_number(global_position, tr("ЯРОСТЬ!"), Color(1, 0.4, 0.1))
			Sfx.play_at("war_cry", global_position, 3.0, 0.8)
		"die":
			alive = false
			state = "dead"
			dead_time = 0.0
			_ensure_unique_materials()
			Sfx.play_at("gnome_death", global_position, 3.0, 0.7 if type == "king" else 1.0)
			game.fx_burst(global_position + Vector3(0, 0.5, 0), Color(0.7, 0.12, 0.07), 18)
			collision_layer = 0
			collision_mask = 1
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
			_spawn_ragdoll(kdir, kcrit)


# ---------------------------------------------------------------------------
# Труп-регдолл
# ---------------------------------------------------------------------------
var corpse: RigidBody3D = null
var _thud_played := false


func _spawn_ragdoll(dir: Vector3, crit: bool) -> void:
	anim_player.pause()

	corpse = RigidBody3D.new()
	corpse.top_level = true
	corpse.collision_layer = 0
	corpse.collision_mask = 1
	corpse.mass = 2.5 * cfg.scale
	corpse.continuous_cd = true # быстрый кувырок иначе может проскочить сквозь тонкий пол/камень
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	pmat.friction = 0.9
	corpse.physics_material_override = pmat
	# коробка на весь силуэт модели (а не только туловище) — иначе голова/ноги
	# торчат за её пределы и на кувырке проваливаются сквозь текстуры пола/камней
	var full_h: float = MODEL_HEIGHTS.get(cfg.model, 1.8) * cfg.scale
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9 * cfg.scale, full_h, 1.1 * cfg.scale)
	cs.shape = box
	cs.position.y = full_h * 0.5 - 0.55 * cfg.scale
	corpse.add_child(cs)
	corpse.contact_monitor = true
	corpse.max_contacts_reported = 1
	corpse.body_entered.connect(_on_corpse_contact)
	add_child(corpse)
	corpse.global_position = global_position + Vector3(0, 0.55 * cfg.scale, 0)
	model.reparent(corpse)

	var heavy: float = 0.55 if type == "king" else 1.0 # короля так просто не подбросишь
	var speed: float = (8.5 if crit else 5.0) * heavy
	corpse.linear_velocity = dir.normalized() * speed + Vector3(0, (5.5 if crit else 3.5) * heavy, 0)
	corpse.angular_velocity = Vector3(
		randf_range(-7, 7), randf_range(-4, 4), randf_range(-7, 7)) * heavy


func _on_corpse_contact(_body: Node) -> void:
	if not _thud_played and corpse != null:
		_thud_played = true
		Sfx.play_at("hit", corpse.global_position, -8.0, 0.65)
		game.fx_burst(corpse.global_position, Color(0.5, 0.4, 0.25), 6)


# ---------------------------------------------------------------------------
# Симуляция
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	age += delta
	state_time += delta

	if age < 0.35:
		model.scale = Vector3.ONE * lerpf(0.01, cfg.scale, age / 0.35)
	elif model.scale.x != cfg.scale:
		model.scale = Vector3.ONE * cfg.scale

	if state == "dead":
		dead_time += delta
		if dead_time > 2.4:
			var k := clampf((dead_time - 2.4) / 1.0, 0, 1)
			for m in materials:
				if m is StandardMaterial3D:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color.a = 1.0 - k
			if k >= 1.0:
				game.free_gnome_local(gid)
		return

	if is_sim:
		_sim(delta)
	else:
		_puppet(delta)
	model.rotation.y = facing


func _puppet(delta: float) -> void:
	global_position = global_position.lerp(Vector3(net_pos.x, 0, net_pos.z), minf(1.0, 12 * delta))
	facing = lerp_angle(facing, net_rot, minf(1.0, 10 * delta))
	if age > one_shot_until:
		_play(LOCO[net_loco])


func apply_net_state(x: float, z: float, rot: float, loco: int, new_hp: int) -> void:
	net_pos = Vector3(x, 0, z)
	net_rot = rot
	net_loco = loco
	hp = new_hp


# --- серверный ИИ ---------------------------------------------------------
func _sim(delta: float) -> void:
	if state == "spawn":
		if age >= 0.35:
			_set_state("emerge")
		return

	if shout_lock > 0:
		shout_lock -= delta
		_stop_move(delta)
		_apply_motion(delta)
		return

	_pick_target(delta)

	# фирменный спецприём босса — вне обычной машины состояний, приоритет над всем
	if cfg.has("special"):
		if is_special:
			_run_special(delta)
			return
		if target != null and alerted and state != "emerge":
			special_timer -= delta
			if special_timer <= 0.0 and _dist_to_target() < cfg.get("special_range", 14.0):
				_start_special()
				return

	# наёмник: врага нет — держимся рядом с нанимателем
	if friendly:
		if target != null and (state == "patrol" or state == "idle_wait" or state == "investigate"):
			_set_state("chase")
		elif target == null and state != "attack" and state != "emerge":
			var boss_p = game.player_nodes.get(owner_id)
			if boss_p != null and is_instance_valid(boss_p):
				var d_own: float = global_position.distance_to(boss_p.global_position)
				if d_own > 3.2:
					_nav_move_towards(boss_p.global_position.x, boss_p.global_position.z,
						cfg.speed * speed_mul * (1.4 if d_own > 8.0 else 1.0), delta)
					_loco(d_own > 8.0, true)
				else:
					_stop_move(delta)
					_loco(false, false)
			else:
				_stop_move(delta)
				_loco(false, false)
			_apply_motion(delta)
			return

	# из сейф-зоны лагеря уходим, не задерживаясь
	if friendly == false and game.in_safe_zone(global_position) and state != "emerge":
		var away := Vector2(global_position.x - Game.CAMP_POS.x, global_position.z - Game.CAMP_POS.z)
		if away.length() < 0.1:
			away = Vector2(1, 0)
		var out := Vector2(Game.CAMP_POS.x, Game.CAMP_POS.z) + away.normalized() * (Game.SAFE_RADIUS + 2.0)
		_move_towards(out.x, out.y, cfg.speed * speed_mul, delta)
		_loco(false, true)
		_apply_motion(delta)
		return

	# восприятие (не во время выхода из домика)
	if not alerted and target != null and state != "emerge":
		if _can_see_target():
			become_alerted(true)
		elif _can_hear_target():
			investigate_pos = Vector2(target.global_position.x, target.global_position.z)
			investigating = true
			if state != "investigate":
				_set_state("investigate")

	attack_timer = maxf(0, attack_timer - delta)
	sidestep_cd = maxf(0, sidestep_cd - delta)
	heal_cd = maxf(0, heal_cd - delta)
	var speed: float = cfg.speed * speed_mul
	var one_shot_busy := age < one_shot_until

	match state:
		"emerge":
			# выходим из домика через дверь
			var d := _move_towards(emerge_target.x, emerge_target.y, speed * 0.6, delta)
			_loco(false, true)
			if d < 0.5 or state_time > 3.0:
				_set_state("patrol")
				has_waypoint = false
		"patrol":
			if not has_waypoint:
				waypoint = _random_waypoint()
				has_waypoint = true
			var d := _nav_move_towards(waypoint.x, waypoint.y, speed * 0.45, delta)
			_loco(false, true)
			if d < 0.9:
				_set_state("idle_wait")
				idle_for = randf_range(1.0, 2.5)
		"idle_wait":
			_loco(false, false)
			_stop_move(delta)
			if state_time > idle_for:
				has_waypoint = false
				_set_state("patrol")
		"investigate":
			if not investigating:
				_set_state("patrol")
			else:
				var d := _nav_move_towards(investigate_pos.x, investigate_pos.y, speed * 0.7, delta)
				_loco(false, true)
				if _can_see_target():
					become_alerted(true)
				elif d < 1.2 or state_time > 6.0:
					investigating = false
					_set_state("patrol")
		"chase":
			if target == null:
				alerted = false
				_set_state("patrol")
			else:
				var d := _dist_to_target()
				if d < cfg.ring + 1.5:
					_set_state("circle")
				else:
					_nav_move_towards(target.global_position.x, target.global_position.z, speed, delta)
					_loco(true, true)
		"circle":
			if target == null:
				alerted = false
				_set_state("patrol")
			else:
				var d := _dist_to_target()
				if d > cfg.ring + 6.0:
					_set_state("chase")
				else:
					var tx: float = target.global_position.x + sin(slot_angle) * cfg.ring
					var tz: float = target.global_position.z + cos(slot_angle) * cfg.ring
					var dslot := _move_towards(tx, tz, speed * 0.8, delta, _angle_to_target())
					if not one_shot_busy:
						_loco(false, dslot > 0.5)

					# разведчик уворачивается от замаха игрока
					if cfg.get("dodges", false) and sidestep_cd <= 0 and d < 3.8 \
							and target is PlayerChar and target.state == "attack" and target.state_time < 0.12 \
							and randf() < float(game.diff().dodge):
						_start_sidestep()
					elif cfg.ranged and d < 5.5:
						_set_state("flee")
					elif cfg.get("heals", false) and heal_cd <= 0 and _try_start_heal():
						pass
					else:
						var in_range: bool = (d < cfg.attack_range) if cfg.ranged else true
						if attack_timer <= 0 and in_range and _request_token():
							_start_attack()
		"sidestep":
			velocity.x = sidestep_dir.x * 7.0
			velocity.z = sidestep_dir.z * 7.0
			if state_time > 0.35:
				_set_state("circle")
		"heal_cast":
			_stop_move(delta)
			if heal_target != null and is_instance_valid(heal_target) and heal_target.alive:
				facing = rotate_toward(facing,
					atan2(heal_target.global_position.x - global_position.x, heal_target.global_position.z - global_position.z),
					cfg.turn * delta)
				if state_time >= 1.0 and heal_target != null:
					var ally = heal_target
					heal_target = null
					ally.hp = mini(ally.max_hp, ally.hp + 18)
					game.bcast_gnome_event(ally.gid, "healed", [18])
					heal_cd = float(game.diff().heal_cd)
			if state_time >= 1.2:
				_set_state("circle")
		"attack":
			if target == null:
				_finish_attack()
				_set_state("patrol")
			elif cfg.ranged:
				_stop_move(delta)
				facing = rotate_toward(facing, _angle_to_target(), cfg.turn * delta)
				if not attack_did_hit and state_time >= attack_dur * 0.55:
					attack_did_hit = true
					game.server_spawn_fireball(self)
				if state_time >= attack_dur:
					_finish_attack()
			elif not attack_swinging:
				var d := _move_towards(target.global_position.x, target.global_position.z, speed * 1.25, delta)
				_loco(true, true)
				if d < cfg.attack_range * 0.85:
					attack_swinging = true
					state_time = 0.0
					var anim: String = cfg.attack_anims[randi() % cfg.attack_anims.size()]
					attack_dur = anim_player.get_animation(anim).length / cfg.attack_ts if anim_player.has_animation(anim) else 0.8
					game.bcast_gnome_event(gid, "attack", [anim])
				elif state_time > 3.5:
					_finish_attack()
			else:
				_stop_move(delta)
				facing = rotate_toward(facing, _angle_to_target(), cfg.turn * 0.5 * delta)
				if not attack_did_hit and state_time >= attack_dur * 0.45:
					attack_did_hit = true
					if _dist_to_target() < cfg.attack_range + 0.6:
						var out_dmg := maxi(1, roundi(cfg.attack_dmg * dmg_mul * level_dmg_mult * float(game.diff().dmg)))
						if target is Gnome:
							target.last_attacker = 0
							target.last_attacker_gid = gid
							target.server_take_damage(out_dmg, global_position, false)
						else:
							game.server_damage_player(_target_id(), out_dmg, global_position)
				if state_time >= attack_dur:
					_finish_attack()
					if cfg.retreats:
						_set_state("retreat")
		"retreat":
			if target != null:
				var away := atan2(global_position.x - target.global_position.x, global_position.z - target.global_position.z)
				_move_towards(global_position.x + sin(away + 0.5) * 3, global_position.z + cos(away + 0.5) * 3, speed, delta, _angle_to_target())
				_loco(true, true)
			if state_time > 0.7:
				_set_state("circle")
		"flee":
			if target != null:
				var away := atan2(global_position.x - target.global_position.x, global_position.z - target.global_position.z)
				_nav_move_towards(global_position.x + sin(away) * 5, global_position.z + cos(away) * 5, speed * 1.25, delta)
				_loco(true, true)
				if _dist_to_target() > cfg.ring + 1.0 or state_time > 4.0:
					_set_state("circle")
			else:
				_set_state("patrol")
		"stagger":
			_stop_move(delta)
			if state_time > 0.45:
				_set_state("circle" if alerted else "patrol")

	_apply_motion(delta)


## Гравитация, отбрасывание и физика — через move_and_slide (сквозь стены нельзя).
func _apply_motion(delta: float) -> void:
	if knockback.length_squared() > 0.01:
		velocity.x += knockback.x
		velocity.z += knockback.z
		knockback = knockback.move_toward(Vector3.ZERO, knockback.length() * 8 * delta + 0.2)
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0


# ---------------------------------------------------------------------------
# Босс-спецприёмы: у каждого босса свой фирменный паттерн (cfg.special),
# отдельная мини-машина состояний поверх обычного ИИ — telegraph -> execute -> recover.
# ---------------------------------------------------------------------------
const SPECIAL_TELEGRAPH_TIME := 1.3
const SPECIAL_RECOVER_TIME := 0.6

func _start_special() -> void:
	is_special = true
	special_phase = "telegraph"
	special_time = 0.0
	var telegraph_anim := "Spellcast_Summon" if cfg.special == "summon" else "Taunt_Longer"
	if not anim_player.has_animation(telegraph_anim):
		telegraph_anim = "Taunt" if anim_player.has_animation("Taunt") else cfg.idle_anim
	one_shot_until = age + _play(telegraph_anim, 1.0, true)
	game.bcast_gnome_event(gid, "special_telegraph", [cfg.special])


func _run_special(delta: float) -> void:
	special_time += delta
	match special_phase:
		"telegraph":
			_stop_move(delta)
			_apply_motion(delta)
			if target != null:
				facing = rotate_toward(facing, _angle_to_target(), cfg.turn * 0.4 * delta)
			if special_time >= SPECIAL_TELEGRAPH_TIME:
				special_phase = "execute"
				special_time = 0.0
				_execute_special()
		"execute":
			if cfg.special == "charge":
				if special_time < 0.55:
					# рывок к точке, выбранной в момент начала броска (см. _execute_special)
					var d := _move_towards(_charge_target.x, _charge_target.y, cfg.speed * 3.4, delta)
					_loco(true, true)
					_apply_motion(delta)
					if d >= 0.6:
						return
				# долетели (или вышло время) — удар по приземлению
				_on_charge_land()
				_stop_move(delta)
				_apply_motion(delta)
				special_phase = "recover"
				special_time = 0.0
			else:
				_stop_move(delta)
				_apply_motion(delta)
				special_phase = "recover"
				special_time = 0.0
		"recover":
			_stop_move(delta)
			_apply_motion(delta)
			if special_time >= SPECIAL_RECOVER_TIME:
				is_special = false
				special_timer = cfg.get("special_cd", 9.0)
				_set_state("circle" if alerted else "patrol")


var _charge_target := Vector2.ZERO


func _execute_special() -> void:
	match cfg.special:
		"slam":
			game.bcast_gnome_event(gid, "special_fx", ["slam", global_position.x, global_position.z])
			var r: float = cfg.get("special_radius", 5.0)
			var dmg: int = roundi(cfg.get("special_dmg", 20) * level_dmg_mult * float(game.diff().dmg))
			for id in game.player_nodes:
				var p = game.player_nodes[id]
				if game.server_hp.get(id, 0) <= 0:
					continue
				if global_position.distance_to(p.global_position) < r:
					game.server_damage_player(id, dmg, global_position)
		"charge":
			if target != null:
				_charge_target = Vector2(target.global_position.x, target.global_position.z)
			else:
				_charge_target = Vector2(global_position.x, global_position.z)
			special_time = 0.0 # длительность броска отмеряется в _run_special
		"summon":
			var n: int = cfg.get("special_count", 2)
			for i in n:
				var a := randf_range(0, TAU)
				var px := global_position.x + cos(a) * 2.5
				var pz := global_position.z + sin(a) * 2.5
				game.server_spawn_gnome_at("skeleton_minion", Vector3(px, 0, pz), level)
			game.bcast_gnome_event(gid, "special_fx", ["summon", global_position.x, global_position.z])


func _on_charge_land() -> void:
	var r: float = cfg.get("special_radius", 3.0)
	var dmg: int = roundi(cfg.get("special_dmg", 18) * level_dmg_mult * float(game.diff().dmg))
	game.bcast_gnome_event(gid, "special_fx", ["charge_land", global_position.x, global_position.z])
	for id in game.player_nodes:
		var p = game.player_nodes[id]
		if game.server_hp.get(id, 0) <= 0:
			continue
		if global_position.distance_to(p.global_position) < r:
			game.server_damage_player(id, dmg, global_position)


func _start_sidestep() -> void:
	sidestep_cd = 1.6
	var to_t := _angle_to_target()
	var side := 1.0 if randf() < 0.5 else -1.0
	sidestep_dir = Vector3(sin(to_t + PI * 0.5 * side), 0, cos(to_t + PI * 0.5 * side))
	_set_state("sidestep")
	one_shot_until = age + 0.4
	_play("Dodge_Right" if side > 0 else "Dodge_Left", 1.4, true)


func _try_start_heal() -> bool:
	var best: Gnome = null
	var best_hp := 0.65
	for g in game.gnomes.values():
		if g == self or not g.alive or g.friendly != friendly:
			continue
		var frac: float = float(g.hp) / g.max_hp
		if frac < best_hp and global_position.distance_to(g.global_position) < 12.0:
			best_hp = frac
			best = g
	if best == null:
		return false
	heal_target = best
	_set_state("heal_cast")
	game.bcast_gnome_event(gid, "heal_cast", [])
	return true


## Насколько далеко от нанимателя наёмник ещё готов гоняться за врагом —
## иначе он убегал через полкарты за первым замеченным гномом.
const ALLY_LEASH := 11.0
const ALLY_RECALL := 15.0


func _pick_target(delta: float) -> void:
	retarget_timer -= delta
	var owner_p = game.player_nodes.get(owner_id) if friendly else null
	# якорь привязи: наниматель, если он на месте; иначе — сам наёмник, чтобы
	# осиротевший (наниматель вышел) маг держался рядом, а не убегал через полкарты
	var anchor: Vector3 = global_position
	if owner_p != null and is_instance_valid(owner_p):
		anchor = owner_p.global_position
	if retarget_timer > 0 and target != null and is_instance_valid(target) \
			and target.state != "dead" and target.state != "downed" \
			and not game.in_safe_zone(target.global_position) \
			and (not friendly or anchor.distance_to(target.global_position) < ALLY_RECALL):
		return
	retarget_timer = 0.5
	target = null
	var best := 1e9
	if friendly:
		# наёмник целится в ближайшего врага-гнома, но только рядом с якорем —
		# иначе он срывается через полкарты за первым замеченным противником
		for g in game.gnomes.values():
			if g == self or not g.alive or g.friendly:
				continue
			if anchor.distance_to(g.global_position) > ALLY_LEASH:
				continue
			var dg: float = global_position.distance_to(g.global_position)
			if dg < best:
				best = dg
				target = g
		return
	for p in game.player_nodes.values():
		if p.state == "dead" or p.state == "downed":
			continue
		if game.in_safe_zone(p.global_position):
			continue # в лагере игрок недосягаем
		var d: float = global_position.distance_to(p.global_position)
		if d < best:
			best = d
			target = p
	# наёмники игроков — тоже цели (и ближе костяшкам, чем рыцари)
	for g in game.gnomes.values():
		if not g.friendly or not g.alive:
			continue
		var d2: float = global_position.distance_to(g.global_position)
		if d2 < best:
			best = d2
			target = g


func _target_id() -> int:
	return target.peer_id if target != null else 0


func _dist_to_target() -> float:
	return Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()


func _angle_to_target() -> float:
	return atan2(target.global_position.x - global_position.x, target.global_position.z - global_position.z)


func _can_see_target() -> bool:
	if target == null:
		return false
	var d := _dist_to_target()
	if d < 3.0:
		return true
	if d > float(game.diff().sight):
		return false
	return absf(angle_difference(_angle_to_target(), facing)) < SIGHT_ANGLE


func _can_hear_target() -> bool:
	if target == null:
		return false
	if target is Gnome:
		return _dist_to_target() < 12.0
	return _dist_to_target() < game.get_player_noise(target)


func become_alerted(shout: bool) -> void:
	if alerted or not alive or state == "emerge" or state == "spawn":
		return
	alerted = true
	if is_instance_valid(target):
		slot_angle = atan2(global_position.x - target.global_position.x, global_position.z - target.global_position.z)
	_set_state("chase")
	if shout:
		shout_lock = 0.5
		game.bcast_gnome_event(gid, "cry", [])
		game.server_alert_nearby(global_position, 15.0, self)


## Урон (только на сервере). Добивание оглушённого (state == "stagger")
## гнома — импровизированный "финишер": больше урона и своя ачивка.
func server_take_damage(dmg: int, from_pos: Vector3, crit: bool) -> void:
	if not alive:
		return
	var finisher: bool = state == "stagger" and not friendly
	if finisher:
		dmg = roundi(dmg * 1.4)
	hp -= dmg
	var dx := global_position.x - from_pos.x
	var dz := global_position.z - from_pos.z
	var d := maxf(0.1, Vector2(dx, dz).length())
	var kb := (5.0 if crit else 3.0) * (0.25 if type == "king" else 1.0)
	knockback += Vector3(dx / d * kb, 0, dz / d * kb)

	if state == "emerge":
		_set_state("patrol") # выманили из домика ударом
	become_alerted(false)
	game.server_alert_nearby(global_position, 10.0, self)

	if hp <= 0:
		_release_token()
		game.server_gnome_died(self, from_pos, crit, finisher)
		return

	if cfg.enrage_at > 0.0 and not enraged and hp < max_hp * cfg.enrage_at:
		speed_mul = 1.55
		dmg_mul = 1.5
		game.bcast_gnome_event(gid, "enrage", [])

	var staggered: bool = state != "attack" or randf() < cfg.stagger
	game.bcast_gnome_event(gid, "hit", [dmg, crit, staggered, finisher, last_attacker])
	if staggered:
		_release_token()
		attack_swinging = false
		_set_state("stagger")

	if type == "shaman" and hp < max_hp * 0.5 and is_instance_valid(target) and _dist_to_target() < 6.0:
		_set_state("flee")


func _set_state(s: String) -> void:
	state = s
	state_time = 0.0


func _request_token() -> bool:
	if has_token:
		return true
	if game.server_request_token(gid):
		has_token = true
		return true
	return false


func _release_token() -> void:
	if has_token:
		game.server_release_token(gid)
		has_token = false


func _start_attack() -> void:
	_set_state("attack")
	attack_did_hit = false
	attack_swinging = false
	if cfg.ranged:
		attack_swinging = true
		var anim: String = cfg.attack_anims[0]
		attack_dur = anim_player.get_animation(anim).length / cfg.attack_ts if anim_player.has_animation(anim) else 0.9
		game.bcast_gnome_event(gid, "attack", [anim])
		Sfx.play_at("fireball", global_position)


func _finish_attack() -> void:
	_release_token()
	attack_timer = randf_range(cfg.cd_min, cfg.cd_max) * (0.55 if enraged else 1.0) * float(game.diff().cd)
	attack_swinging = false
	if state == "attack":
		_set_state("circle")


## Прямое движение (короткие манёвры вокруг цели).
func _move_towards(tx: float, tz: float, speed: float, delta: float, face_target: float = INF) -> float:
	var dx := tx - global_position.x
	var dz := tz - global_position.z
	var d := Vector2(dx, dz).length()
	if d > 0.05:
		velocity.x = dx / d * speed
		velocity.z = dz / d * speed
		var face := face_target if face_target != INF else atan2(dx, dz)
		facing = rotate_toward(facing, face, cfg.turn * delta)
	else:
		velocity.x = 0
		velocity.z = 0
		if face_target != INF:
			facing = rotate_toward(facing, face_target, cfg.turn * delta)
	return d


## Движение по навигационной сетке (дальние переходы — обходит препятствия).
func _nav_move_towards(tx: float, tz: float, speed: float, delta: float) -> float:
	var final_d := Vector2(tx - global_position.x, tz - global_position.z).length()
	if nav == null or not game.nav_ready or final_d < 2.0:
		_move_towards(tx, tz, speed, delta)
		return final_d
	_nav_repath -= delta
	var t := Vector3(tx, 0, tz)
	if _nav_repath <= 0 or nav.target_position.distance_to(t) > 1.5:
		_nav_repath = 0.4
		nav.target_position = t
	if nav.is_navigation_finished():
		_stop_move(delta)
		return final_d
	var next := nav.get_next_path_position()
	_move_towards(next.x, next.z, speed, delta)
	return final_d


func _stop_move(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 20 * delta)
	velocity.z = move_toward(velocity.z, 0, 20 * delta)


func _loco(fast: bool, moving: bool) -> void:
	if age < one_shot_until:
		return
	if fast:
		_play("Running_A")
	elif moving:
		_play("Walking_A")
	else:
		_play(cfg.idle_anim)


func _random_waypoint() -> Vector2:
	for _try in 8:
		var a := randf_range(0, TAU)
		var r := randf_range(5.0, WorldGen.WORLD_RADIUS - 5.0)
		var wp := Vector2(cos(a) * r, sin(a) * r)
		if not game.in_safe_zone(Vector3(wp.x, 0, wp.y)):
			return wp
	return Vector2(0, -WorldGen.WORLD_RADIUS * 0.5)
