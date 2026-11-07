class_name UnitBody
extends RefCounted
## What a unit's body is made of. A living body takes ordinary healing; a mechanical one is
## only repaired by abilities made for machines. The body is a rule of the battle, not a look.

const LIVING := &"living"
const MECHANICAL := &"mechanical"
const ALL: Array[StringName] = [LIVING, MECHANICAL]

const NAMES := {LIVING: "Живой", MECHANICAL: "Механический"}


static func is_known(body: StringName) -> bool:
	return ALL.has(body)


static func display_name(body: StringName) -> String:
	return String(NAMES.get(body, body))
