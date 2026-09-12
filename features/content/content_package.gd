class_name ContentPackage
extends Resource


@export var manifest: ContentPackageManifest
@export var battles: Array[BattleDefinition] = []
@export var maps: Array[BattleMapDefinition] = []
@export var units: Array[UnitDefinition] = []
@export var ai_profiles: Array[AIProfileDefinition] = []
@export var races: Array[RaceDefinition] = []
@export var abilities: Array[AbilityDefinition] = []
@export var scenarios: Array[ScenarioDefinition] = []
@export var campaigns: Array[CampaignDefinition] = []