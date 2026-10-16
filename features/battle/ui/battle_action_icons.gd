class_name BattleActionIcons
extends RefCounted
## Pictograms are presentation-only; unknown authored abilities get a neutral glyph.

const ICONS := {
	"move": preload("res://features/battle/ui/icons/classic/move.svg"),
	"attack": preload("res://features/battle/ui/icons/classic/attack.svg"),
	"defend": preload("res://features/battle/ui/icons/classic/defend.svg"),
	"laser": preload("res://features/battle/ui/icons/classic/laser.svg"),
	"grenade": preload("res://features/battle/ui/icons/classic/grenade.svg"),
	"electricity": preload("res://features/battle/ui/icons/classic/electricity.svg"),
	"turret": preload("res://features/battle/ui/icons/classic/turret.svg"),
	"spear": preload("res://features/battle/ui/icons/classic/spear.svg"),
	"ability": preload("res://features/battle/ui/icons/classic/ability.svg"),
}

static func ability(id: StringName) -> Texture2D:
	match id:
		&"core:laser": return ICONS.laser
		&"core:grenade", &"core:emp_grenade": return ICONS.grenade
		&"core:create_electricity": return ICONS.electricity
		&"core:electromagnetic_shot": return ICONS.attack
		&"core:electric_turret": return ICONS.turret
		&"core:spear_throw", &"core:spear_sweep", &"core:spear_pin": return ICONS.spear
	return ICONS.ability
