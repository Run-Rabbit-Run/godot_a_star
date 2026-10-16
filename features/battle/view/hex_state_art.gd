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
	&"core:electricity": Rect2(0.0, 37.0, 362.0, 276.0),
	&"core:water": Rect2(0.0, 90.0, 362.0, 203.0),
	&"core:fire": Rect2(0.0, 66.0, 354.0, 239.0),
	&"core:oil": Rect2(98.0, 142.0, 1397.0, 704.0),
	&"core:acid": Rect2(0.0, 54.0, 362.0, 222.0),
	&"core:electrified_water": Rect2(0.0, 42.0, 362.0, 232.0),
	&"core:plasma": Rect2(0.0, 18.0, 362.0, 275.0),
	&"core:electrified_acid": Rect2(0.0, 36.0, 348.0, 245.0),
	&"core:steam": Rect2(0.0, 24.0, 362.0, 321.0),
	&"core:boiling_acid": Rect2(1.0, 69.0, 361.0, 285.0),
	&"core:burning_oil": Rect2(0.0, 59.0, 362.0, 308.0),
	&"core:acid_vapour": Rect2(0.0, 42.0, 347.0, 317.0),
}


static func texture(state_id: StringName) -> AtlasTexture:
	if not TEXTURES.has(state_id):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = TEXTURES[state_id]
	atlas.region = REGIONS[state_id]
	return atlas
