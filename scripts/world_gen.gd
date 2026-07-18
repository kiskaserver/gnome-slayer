class_name WorldGen
extends RefCounted
## Процедурная арена: биомы, детализация (трава, цветы, брёвна, атмосферные
## частицы), домики гномов с дверями, отдельная ПвП-арена с руинами,
## навигационная сетка. Детерминирована сидом.

const WORLD_RADIUS := 58.0
const OVERWORLD_RADIUS := 80.0  # сюжетный мир-путешествие (арена волн/ПвП остаётся 58);
	# 4.3: стянут со 120 — «меньше площади, больше содержания» (мастер-план C0)

const BIOME_LIST := ["meadow", "winter", "autumn", "night"]

const BIOMES := {
	"meadow": {
		"title": "Поляна",
		"ground": Color(0.36, 0.54, 0.27),
		"leaves": [Color(0.25, 0.44, 0.2), Color(0.29, 0.49, 0.22), Color(0.21, 0.4, 0.17)],
		"sky_top": Color(0.35, 0.55, 0.78), "sky_hor": Color(0.7, 0.8, 0.88),
		"fog": Color(0.62, 0.72, 0.82), "fog_d": 0.006,
		"sun": Color(1.0, 0.95, 0.85), "sun_e": 1.35, "sun_rot": Vector3(-48, 35, 0),
		"ambient": 1.0, "mushrooms": 40,
		"grass": 550, "grass_color": Color(0.3, 0.5, 0.22),
		"particles": "pollen", "start_time": 0.3,
	},
	"winter": {
		"title": "Зимний лес",
		"ground": Color(0.82, 0.86, 0.9),
		"leaves": [Color(0.2, 0.35, 0.28), Color(0.75, 0.82, 0.86), Color(0.26, 0.42, 0.34)],
		"sky_top": Color(0.5, 0.62, 0.75), "sky_hor": Color(0.82, 0.86, 0.9),
		"fog": Color(0.8, 0.85, 0.9), "fog_d": 0.011,
		"sun": Color(0.9, 0.95, 1.0), "sun_e": 1.1, "sun_rot": Vector3(-30, 50, 0),
		"ambient": 1.1, "mushrooms": 10,
		"grass": 90, "grass_color": Color(0.55, 0.5, 0.35),
		"particles": "snow", "start_time": 0.33,
	},
	"autumn": {
		"title": "Осенний лес",
		"ground": Color(0.5, 0.42, 0.2),
		"leaves": [Color(0.75, 0.4, 0.12), Color(0.72, 0.55, 0.15), Color(0.6, 0.25, 0.1)],
		"sky_top": Color(0.45, 0.5, 0.65), "sky_hor": Color(0.9, 0.75, 0.55),
		"fog": Color(0.85, 0.72, 0.55), "fog_d": 0.009,
		"sun": Color(1.0, 0.85, 0.6), "sun_e": 1.2, "sun_rot": Vector3(-25, 20, 0),
		"ambient": 0.9, "mushrooms": 55,
		"grass": 380, "grass_color": Color(0.55, 0.45, 0.18),
		"particles": "leaves", "start_time": 0.68,
		"tree_models": ["halloween/tree_pine_orange_large.gltf", "halloween/tree_pine_orange_medium.gltf", "halloween/tree_pine_yellow_large.gltf"],
	},
	"night": {
		"title": "Ночь",
		"ground": Color(0.16, 0.24, 0.14),
		"leaves": [Color(0.1, 0.2, 0.12), Color(0.13, 0.24, 0.14), Color(0.08, 0.17, 0.1)],
		"sky_top": Color(0.26, 0.34, 0.52), "sky_hor": Color(0.48, 0.52, 0.62),
		"fog": Color(0.3, 0.36, 0.46), "fog_d": 0.011,
		"sun": Color(0.8, 0.85, 1.0), "sun_e": 0.9, "sun_rot": Vector3(-55, -20, 0),
		"ambient": 1.4, "mushrooms": 45,
		"grass": 260, "grass_color": Color(0.12, 0.22, 0.13),
		"particles": "fireflies", "start_time": 0.86,
		"tree_models": ["halloween/tree_dead_large.gltf", "halloween/tree_dead_medium.gltf"],
	},
}


## Дальность прорисовки декоративной растительности: на большом оверворлде
## сотни деревьев за пределами этого радиуса не рисуются вовсе.
const DETAIL_VIS_RANGE := 95.0


# Файл — тонкий фасад: реализация разнесена по scripts/worldgen/* (WgLib,
# WgPois, WgEnv, WgGeom, WgArena, WgOverworld). Здесь живут общие константы
# и делегаты внешнего API — внешние вызовы WorldGen.* работают как раньше.


static func build(parent: Node3D, world_seed: int, biome_id: String, pvp := false) -> Dictionary:
	return WgArena.build(parent, world_seed, biome_id, pvp)


static func build_overworld(parent: Node3D, world_seed: int, biome_id: String) -> Dictionary:
	return WgOverworld.build_overworld(parent, world_seed, biome_id)


static func prop_scene(path: String) -> PackedScene:
	return WgLib.prop_scene(path)


static func place_prop(parent: Node3D, path: String, pos: Vector3, rot_y: float, s: float, coll_r := 0.0, coll_h := 3.0, vis_range := 0.0) -> Node3D:
	return WgLib.place_prop(parent, path, pos, rot_y, s, coll_r, coll_h, vis_range)


static func crystal(parent: Node, color: Color) -> Node3D:
	return WgLib.crystal(parent, color)


static func _mushroom(parent: Node, rng: RandomNumberGenerator, x: float, z: float, s: float, glowing := false) -> Node3D:
	return WgLib._mushroom(parent, rng, x, z, s, glowing)


static func _mat(color: Color, flat := false) -> StandardMaterial3D:
	return WgLib._mat(color, flat)


static func _static_cylinder(parent: Node, x: float, z: float, r: float, h: float) -> void:
	WgLib._static_cylinder(parent, x, z, r, h)
