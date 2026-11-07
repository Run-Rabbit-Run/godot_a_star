class_name UnitStatusCatalog
extends RefCounted

## Status IDs the rules refer to by name.
const WET := &"core:wet"
const BURNING := &"core:burning"
const ACID := &"core:acid"
const ELECTRIFIED := &"core:electrified"
const PARALYSIS := &"core:paralysis"
const PARALYSIS_RESISTANCE := &"core:paralysis_resistance"
const PLASMA := &"core:plasma"
const STICKY_OIL := &"core:sticky_oil"
const ARMOR := &"core:armor"
const SHIELD := &"core:shield"
const ATTACK_CHARGE := &"core:attack_charge"
const TARGETING_GLITCH := &"core:targeting_glitch"

## When a status acts and when it loses levels: HEX_AND_UNIT_STATES.md «Категории статусов».
enum Category {
	## Acts by itself at the start of its side's phase, then loses one level right there.
	PERIODIC,
	## Changes what the unit can do in its own phase; loses one level when that phase ends.
	TURN,
	## Changes how other things act on the unit; loses one level at the start of its side's phase.
	PROPERTY,
	## Its level is an amount, not a duration: it never wears off by itself.
	RESERVE,
}

const CATEGORY_NAMES := {
	Category.PERIODIC: "периодический",
	Category.TURN: "состояние хода",
	Category.PROPERTY: "свойство",
	Category.RESERVE: "запас",
}

## `drops_at_phase_start`: a reserve that falls whole at the start of its side's phase;
## `drops_at_phase_end`: one that falls whole at the end of its side's phase.
const RULES := {
	WET: {"name": "Влага", "category": Category.PROPERTY, "description": "Пока есть, поглощает огненный урон: 1 урона за уровень, расходуя влагу. При наличии хотя бы 1 уровня усиливает электрический урон на 1 без расхода. Влага и горение взаимно снимаются 1:1. Плазма запрещает влагу. В начале фазы своей стороны теряет 1 уровень."},
	BURNING: {"name": "Горение", "category": Category.PERIODIC, "description": "В начале фазы своей стороны наносит 1 огненного урона независимо от числа уровней, затем теряет 1 уровень. Пока есть, поглощает водный урон, расходуя 1 уровень за 1 урона. Взаимно снимается с влагой 1:1. При наличии масла вызывает взрыв."},
	ACID: {"name": "Кислота", "category": Category.PERIODIC, "description": "В начале фазы своей стороны снимает 1 уровень брони, затем теряет 1 уровень. При 5 и более уровнях сразу снимает всю броню и кислоту."},
	ELECTRIFIED: {"name": "Наэлектризованность", "category": Category.PERIODIC, "description": "В начале фазы своей стороны наносит 1 электрического урона независимо от числа уровней, затем теряет 1 уровень. Наложение, дающее 5 и более уровней, накладывает паралич."},
	PARALYSIS: {"name": "Паралич", "category": Category.TURN, "description": "Пока есть, юнит не действует. Отнимает ровно один ход: спадает в конце фазы своей стороны, в которой юнит из-за него не сходил или не доходил, и даёт 1 уровень устойчивости к параличу. Паралич, полученный уже после хода, отнимает следующую фазу. Не накапливается выше 1 уровня."},
	PARALYSIS_RESISTANCE: {"name": "Устойчивость к параличу", "category": Category.PROPERTY, "description": "Пока есть, паралич не накладывается. Наложение снимает паралич. Появляется, когда спадает паралич. В начале фазы своей стороны теряет 1 уровень."},
	PLASMA: {"name": "Плазма", "category": Category.PERIODIC, "description": "В начале фазы своей стороны наносит 2 огненного урона независимо от числа уровней, затем теряет 1 уровень. Пока есть, даёт неуязвимость к водному урону и запрещает влагу; наложение снимает всю влагу. Наложение, дающее 5 и более уровней, накладывает паралич."},
	STICKY_OIL: {"name": "Тягучее масло", "category": Category.TURN, "description": "Снижает передвижение на 1; при 5 уровнях — на 2. В конце фазы своей стороны теряет 1 уровень. Огненный урон или наложение горения вызывает взрыв с уроном, равным сумме уровней масла и горения. Взрыв наносит физический урон только этому юниту, расходует всё масло и сохраняет горение."},
	ARMOR: {"name": "Броня", "category": Category.RESERVE, "description": "Каждый уровень блокирует 1 физического урона. Сама по себе не спадает. Кислота разрушает броню."},
	SHIELD: {"name": "Щит", "category": Category.RESERVE, "drops_at_phase_start": true, "description": "Предотвращает урон любого типа: 1 урона за уровень, после брони и других статусов. Предотвратив хотя бы 1 урона, снимается целиком. В начале фазы своей стороны снимаются все уровни. «Защита» даёт 1 уровень."},
	ATTACK_CHARGE: {"name": "Заряд", "category": Category.RESERVE, "description": "Следующая обычная атака юнита — по противнику или препятствию — наносит на 1 урона больше за каждый уровень и расходует весь заряд. Сам не спадает. Ответный удар и умения заряд не тратят. Пассив «Я здесь» даёт 1 уровень, если юнит начал ход рядом с противником."},
	TARGETING_GLITCH: {"name": "Сбой наведения", "category": Category.RESERVE, "drops_at_phase_end": true, "description": "Следующая обычная атака юнита — по противнику, препятствию или ответный удар — наносит на 1 урона меньше за каждый уровень, но не меньше 0, и снимает сбой целиком. Умения его не тратят. Если юнит не атаковал, сбой снимается в конце фазы своей стороны."},
}

static func has_status(id: StringName) -> bool:
	return RULES.has(id)

static func display_name(id: StringName) -> String:
	return String(RULES.get(id, {}).get("name", id))

static func description(id: StringName) -> String:
	return String(RULES.get(id, {}).get("description", ""))

## Only for a known status (`has_status`).
static func category(id: StringName) -> Category:
	return RULES[id]["category"]

static func category_name(id: StringName) -> String:
	return String(CATEGORY_NAMES[category(id)]) if RULES.has(id) else ""

static func drops_at_phase_start(id: StringName) -> bool:
	return bool(RULES.get(id, {}).get("drops_at_phase_start", false))

static func drops_at_phase_end(id: StringName) -> bool:
	return bool(RULES.get(id, {}).get("drops_at_phase_end", false))

static func movement_penalty(statuses: Dictionary) -> int:
	var oil := int(statuses.get(STICKY_OIL, 0))
	return 2 if oil >= 5 else (1 if oil > 0 else 0)
