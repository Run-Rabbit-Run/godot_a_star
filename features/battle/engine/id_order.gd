class_name IdOrder
extends RefCounted
## The order of IDs wherever it can reach a rule, the AI, a log or the screen: by their text,
## code point by code point. `Array.sort()` and `<` compare StringName by its interned pointer,
## which depends on when each name was first created, so they never order IDs.


## True when `left` comes before `right`.
static func is_before(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


## A copy of `ids` in this order; every element is a StringName.
static func sorted(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(ids)
	result.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	return result
