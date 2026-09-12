class_name ScenarioTransitionDefinition
extends Resource


enum Outcome {
	VICTORY,
	DEFEAT,
	CANCELLED,
}


@export var outcome: Outcome = Outcome.VICTORY
@export var target_scenario_id: StringName
@export var ends_campaign := false