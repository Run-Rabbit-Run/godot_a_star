class_name BattleBackdrops
extends RefCounted

const TEXTURES := {
	&"plateau": preload("res://features/battle/art/plateau.png"),
	&"mycelium": preload("res://features/battle/art/mycelium.png"),
	&"roots": preload("res://features/battle/art/roots.png"),
}
const NAMES := {&"plateau": "Аэр · парящее плато", &"mycelium": "Люмен · грибные сады", &"roots": "Умбра · корневой мир"}

static func texture(id: StringName) -> Texture2D:
	return TEXTURES.get(id, TEXTURES[&"plateau"])
