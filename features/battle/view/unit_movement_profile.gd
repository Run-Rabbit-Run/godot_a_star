class_name UnitMovementProfile
extends Resource

## Presentation-only gait, expressed in actor pixels and seconds at playback 1x.
@export_range(0.05, 1.0) var seconds_per_hex := 0.28
@export_range(0.0, 8.0) var lift := 2.4
@export_range(0.0, 8.0) var sway_degrees := 1.2
@export_range(0.0, 8.0) var lean_degrees := 2.0
@export_range(0.0, 0.1) var stride := 0.012
@export_range(0.0, 1.0) var leg_start := 0.65
@export_range(0.0, 1.0) var leg_split := 0.5
