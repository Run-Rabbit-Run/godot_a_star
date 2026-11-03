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

const RULES := {
	WET: {"name": "Влага", "description": "В конце своего хода теряет 1 уровень. Поглощает огненный урон: 1 урона за уровень, расходуя влагу. При наличии хотя бы 1 уровня усиливает электрический урон на 1 без расхода. Влага и горение взаимно снимаются 1:1. Плазма запрещает влагу."},
	BURNING: {"name": "Горение", "description": "В конце своего хода наносит 1 огненного урона независимо от числа уровней, затем теряет 1 уровень. Поглощает водный урон, расходуя 1 уровень за 1 урона. Взаимно снимается с влагой 1:1. При наличии масла вызывает взрыв."},
	ACID: {"name": "Кислота", "description": "В конце своего хода снимает 1 уровень брони и теряет 1 уровень кислоты. При 5 и более уровнях сразу снимает всю броню и кислоту."},
	ELECTRIFIED: {"name": "Наэлектризованность", "description": "В конце своего хода наносит 1 электрического урона независимо от числа уровней, затем теряет 1 уровень. Наложение, дающее 5 и более уровней, накладывает паралич."},
	PARALYSIS: {"name": "Паралич", "description": "Пропускает свой ход. Не накапливается выше 1 уровня и не накладывается при устойчивости к параличу. В конце пропущенного хода спадает и даёт 1 уровень устойчивости к параличу."},
	PARALYSIS_RESISTANCE: {"name": "Устойчивость к параличу", "description": "Пока есть, паралич не накладывается. Наложение снимает паралич. Появляется, когда спадает паралич. В конце своего хода теряет 1 уровень."},
	PLASMA: {"name": "Плазма", "description": "В конце своего хода наносит 2 огненного урона независимо от числа уровней, затем теряет 1 уровень. Даёт неуязвимость к водному урону, снимает всю влагу и запрещает её наложение. Наложение, дающее 5 и более уровней, накладывает паралич."},
	STICKY_OIL: {"name": "Тягучее масло", "description": "Снижает передвижение на 1; при 5 уровнях — на 2. В конце своего хода теряет 1 уровень. Огненный урон или наложение горения вызывает взрыв с уроном, равным сумме уровней масла и горения. Взрыв наносит физический урон только этому юниту, расходует всё масло и сохраняет горение."},
	ARMOR: {"name": "Броня", "description": "Каждый уровень блокирует 1 физического урона. Сама по себе не спадает. Кислота разрушает броню."},
}

static func has_status(id: StringName) -> bool:
	return RULES.has(id)

static func display_name(id: StringName) -> String:
	return String(RULES.get(id, {}).get("name", id))

static func description(id: StringName) -> String:
	return String(RULES.get(id, {}).get("description", ""))

static func movement_penalty(statuses: Dictionary) -> int:
	var oil := int(statuses.get(STICKY_OIL, 0))
	return 2 if oil >= 5 else (1 if oil > 0 else 0)
