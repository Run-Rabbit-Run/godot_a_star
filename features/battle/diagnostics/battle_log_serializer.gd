class_name BattleLogSerializer
extends RefCounted


## JSON-safe gameplay values. Never serializes Nodes, textures or private runtime services.
static func encode(value: Variant, depth := 0) -> Variant:
	if depth > 32:
		return {"serialization_error": "maximum_depth"}
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return String(value)
		TYPE_VECTOR2I, TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(encode(item, depth + 1))
			return items
		TYPE_DICTIONARY:
			var fields: Dictionary = {}
			for key: Variant in value:
				fields[str(key)] = encode(value[key], depth + 1)
			return fields
		TYPE_OBJECT:
			if value is HexGrid:
				var cells: Array = []
				for cell: Vector2i in value.get_cells():
					cells.append({"hex": encode(cell), "terrain_id": String(value.get_terrain_id(cell)), "state_id": String(value.get_hex_state_id(cell)), "state_turns": value.get_hex_state_turns(cell), "traversable": value.is_traversable(cell), "movement_cost": value.get_configured_movement_cost(cell)})
				return {"type": "HexGrid", "cells": cells}
			if value is Node or value is Texture2D or value is Script:
				return {"type": value.get_class()}
			var script: Script = value.get_script()
			var fields: Dictionary = {"type": String(script.get_global_name()) if script != null else value.get_class()}
			if script != null:
				for property: Dictionary in value.get_property_list():
					var name := String(property.name)
					if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not name.begins_with("_"):
						fields[name] = encode(value.get(name), depth + 1)
			return fields
		_:
			return {"variant_type": type_string(typeof(value)), "value": str(value)}
