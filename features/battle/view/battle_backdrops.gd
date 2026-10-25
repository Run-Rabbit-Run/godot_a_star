class_name BattleBackdrops
extends RefCounted

const TEXTURES := {
	&"plateau": preload("res://features/battle/art/classic/plateau.png"),
	&"mycelium": preload("res://features/battle/art/classic/mycelium.png"),
	&"roots": preload("res://features/battle/art/classic/roots.png"),
	&"alien_arena": preload("res://features/battle/art/generated/alien_arena_2026_10_17/alien_arena_2560x1440.png"),
	&"alien_crystal_arena": preload("res://features/battle/art/generated/alien_arena_2026_10_17/alien_crystal_arena_2560x1440.png"),
}
const NAMES := {
	&"plateau": "Аэр · парящее плато",
	&"mycelium": "Люмен · грибные сады",
	&"roots": "Умбра · корневой мир",
	&"alien_arena": "Инопланетная арена · открытое поле",
	&"alien_crystal_arena": "Инопланетная арена · кристаллы по краям",
}

static func texture(id: StringName) -> Texture2D:
	return TEXTURES.get(id, TEXTURES[&"plateau"])
