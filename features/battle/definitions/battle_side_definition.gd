class_name BattleSideDefinition
extends Resource


@export var side_id: StringName
@export var faction: BattleFaction.Value = BattleFaction.Value.PLAYER
@export var control_source: BattleControlSource.Value = BattleControlSource.Value.PLAYER
@export var ai_profile_id: StringName
