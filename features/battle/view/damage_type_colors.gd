class_name DamageTypeColors
extends RefCounted

const COLORS := {
	&"physical": Color("eee6d3"),
	&"electric": Color("377cff"),
	&"water": Color("55ddff"),
	&"fire": Color("ff4747"),
	&"acid": Color("6deb55"),
	&"plasma": Color("ff8ba8"),
}

static func get_color(type: StringName) -> Color:
	return COLORS.get(type, COLORS[&"physical"])
