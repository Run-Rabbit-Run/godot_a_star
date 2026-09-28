class_name HexStateArt
extends RefCounted


const TEXTURES := {
	&"core:electricity": preload("res://features/battle/art/hex_states/01-electricity.png"),
	&"core:water": preload("res://features/battle/art/hex_states/02-water.png"),
	&"core:fire": preload("res://features/battle/art/hex_states/03-fire.png"),
	&"core:oil": preload("res://features/battle/art/hex_states/04-oil.png"),
	&"core:acid": preload("res://features/battle/art/hex_states/05-acid.png"),
	&"core:electrified_water": preload("res://features/battle/art/hex_states/06-electrified-water.png"),
	&"core:plasma": preload("res://features/battle/art/hex_states/07-plasma.png"),
	&"core:electrified_acid": preload("res://features/battle/art/hex_states/08-electrified-acid.png"),
	&"core:steam": preload("res://features/battle/art/hex_states/09-steam.png"),
	&"core:boiling_acid": preload("res://features/battle/art/hex_states/10-boiling-acid.png"),
	&"core:burning_oil": preload("res://features/battle/art/hex_states/11-burning-oil.png"),
	&"core:acid_vapour": preload("res://features/battle/art/hex_states/12-acid-vapour.png"),
}
const REGIONS := {
	&"core:electricity": Rect2(22, 75, 331, 263),
	&"core:water": Rect2(17, 109, 329, 221),
	&"core:fire": Rect2(14, 69, 328, 264),
	&"core:oil": Rect2(126, 191, 1343, 635),
	&"core:acid": Rect2(22, 54, 334, 229),
	&"core:electrified_water": Rect2(16, 24, 336, 268),
	&"core:plasma": Rect2(15, 28, 330, 261),
	&"core:electrified_acid": Rect2(7, 40, 333, 258),
	&"core:steam": Rect2(20, 42, 334, 292),
	&"core:boiling_acid": Rect2(14, 42, 337, 293),
	&"core:burning_oil": Rect2(8, 30, 342, 303),
	&"core:acid_vapour": Rect2(15, 33, 325, 298),
}


static func texture(state_id: StringName) -> AtlasTexture:
	if not TEXTURES.has(state_id):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = TEXTURES[state_id]
	atlas.region = REGIONS[state_id]
	return atlas
