class_name DamageTypeColors
extends RefCounted

const COLORS := {
	&"physical": Color("eee6d3"),
	&"electric": Color("75b8d5"),
	&"water": Color("699fa8"),
	&"fire": Color("e6a15a"),
	&"acid": Color("b2bd64"),
	&"plasma": Color("d68ba9"),
}

static func get_color(type: StringName) -> Color:
	return COLORS.get(type, COLORS[&"physical"])
