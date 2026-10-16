class_name BattleBackdrops
extends RefCounted

const TEXTURES := {
	&"plateau": preload("res://features/battle/art/classic/plateau.png"),
	&"mycelium": preload("res://features/battle/art/classic/mycelium.png"),
	&"roots": preload("res://features/battle/art/classic/roots.png"),
}
const NAMES := {&"plateau": "Аэр · парящее плато", &"mycelium": "Люмен · грибные сады", &"roots": "Умбра · корневой мир"}

static func texture(id: StringName) -> Texture2D:
	return TEXTURES.get(id, TEXTURES[&"plateau"])
