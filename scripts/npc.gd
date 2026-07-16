class_name Npc
extends Node3D
## Мирный житель в лагере: стоит у костра, поворачивается к ближайшему
## игроку, иногда жестикулирует. Над головой — имя и маркер квеста.

var game: Node = null
var npc_name := ""
var model: Node3D = null
var anim_player: AnimationPlayer = null
var marker: Label3D = null
var facing := 0.0
var _gesture_timer := 5.0
var _marker_base_y := 2.75


func setup(g: Node, def: Dictionary, pos: Vector3, face_to: Vector3) -> void:
	game = g
	npc_name = def.name
	model = g.models[def.model].instantiate()
	add_child(model)
	anim_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim_player.playback_default_blend_time = 0.25
	if anim_player.has_animation("Idle"):
		anim_player.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		anim_player.play("Idle")
	# прячем оружие — жители безоружны
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		for p in ["Sword", "Axe", "Staff", "Wand", "Shield", "Knife", "Crossbow", "Throwable", "Mug", "Spellbook", "Offhand"]:
			if n.contains(p):
				mi.visible = false
				break
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# оттенок (вербовщик магов выделяется цветом мантии)
	var t: Color = def.get("tint", Color.WHITE)
	if t != Color.WHITE:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for i in mi.get_surface_override_material_count():
				var mat = mi.get_active_material(i)
				if mat != null:
					var m2 = mat.duplicate()
					m2.albedo_color = Color(m2.albedo_color.r * t.r, m2.albedo_color.g * t.g, m2.albedo_color.b * t.b, 1.0)
					mi.set_surface_override_material(i, m2)
	# призрак — полупрозрачный и светящийся
	if def.get("ghost", false):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for i in mi.get_surface_override_material_count():
				var mat = mi.get_active_material(i)
				if mat != null:
					var m2 = mat.duplicate()
					m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m2.albedo_color = Color(0.6, 0.8, 1.0, 0.55)
					m2.emission_enabled = true
					m2.emission = Color(0.4, 0.7, 1.0)
					m2.emission_energy_multiplier = 0.5
					mi.set_surface_override_material(i, m2)

	global_position = pos
	facing = atan2(face_to.x - pos.x, face_to.z - pos.z)
	model.rotation.y = facing

	# высота модели зависит от вида — у мага, например, ещё и шляпа сверху;
	# без запаса имя оказывается прямо в уборе, а не над головой
	var model_h: float = Gnome.MODEL_HEIGHTS.get(def.model, 1.8)

	var label := Label3D.new()
	label.text = tr(npc_name)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = model_h + 0.55
	label.pixel_size = 0.008
	label.outline_size = 8
	label.modulate = Color(0.7, 1.0, 0.8)
	add_child(label)

	_marker_base_y = model_h + 1.0
	marker = Label3D.new()
	marker.text = ""
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.position.y = _marker_base_y
	marker.pixel_size = 0.02
	marker.outline_size = 10
	marker.modulate = Color(1.0, 0.85, 0.3)
	add_child(marker)


func set_marker(text: String) -> void:
	marker.text = text


func _process(delta: float) -> void:
	# смотрим на ближайшего игрока
	var best: Node3D = null
	var best_d := 6.0
	for p in game.player_nodes.values():
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		var want := atan2(best.global_position.x - global_position.x, best.global_position.z - global_position.z)
		facing = rotate_toward(facing, want, 4.0 * delta)
		model.rotation.y = facing
	# маркер подпрыгивает
	marker.position.y = _marker_base_y + sin(Time.get_ticks_msec() / 300.0) * 0.08
	# иногда жестикулируем
	_gesture_timer -= delta
	if _gesture_timer <= 0:
		_gesture_timer = randf_range(6.0, 12.0)
		if best != null and anim_player.has_animation("Interact"):
			anim_player.play("Interact")
			await anim_player.animation_finished
			if anim_player.has_animation("Idle"):
				anim_player.play("Idle")
