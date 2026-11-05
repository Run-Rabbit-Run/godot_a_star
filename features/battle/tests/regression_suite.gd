extends "res://features/battle/tests/check_suite.gd"
## Registry of the game regressions: each group lives in its own `<topic>_regressions.gd`.
## They never load tools/: tool checks live in tools/tests/tool_regression_suite.gd.
## Groups run in this order; `--only=<group>` runs one of them.


func _run() -> void:
	if runs("skill_library"):
		preload("res://features/battle/tests/skill_library_regressions.gd").new().run(self)
	if runs("authored_validation"):
		preload("res://features/battle/tests/authored_validation_regressions.gd").new().run(self)
	if runs("spear"):
		preload("res://features/battle/tests/spear_regressions.gd").new().run(self)
		await preload("res://features/battle/tests/spear_regressions.gd").new().run_presentation(self)
	if runs("objectives"):
		preload("res://features/battle/tests/objective_regressions.gd").new().run(self)
	if runs("action_preview"):
		preload("res://features/battle/tests/action_preview_regressions.gd").new().run(self)
	if runs("side_phases"):
		preload("res://features/battle/tests/side_phase_regressions.gd").new().run(self)
	if runs("basic_attack"):
		preload("res://features/battle/tests/basic_attack_regressions.gd").new().run(self)
	if runs("obstacles"):
		preload("res://features/battle/tests/obstacle_regressions.gd").new().run_obstacles(self)
	if runs("obstacle_view"):
		await preload("res://features/battle/tests/obstacle_regressions.gd").new().run_obstacle_view(self)
	if runs("flasks"):
		preload("res://features/battle/tests/flask_regressions.gd").new().run(self)
	if runs("flask_view"):
		await preload("res://features/battle/tests/flask_regressions.gd").new().run_presentation(self)
	if runs("geometry"):
		preload("res://features/battle/tests/hex_rule_regressions.gd").new().run_geometry(self)
	if runs("terrain_reactions"):
		preload("res://features/battle/tests/hex_rule_regressions.gd").new().run_terrain_reactions(self)
	if runs("properties"):
		preload("res://features/battle/tests/hex_rule_regressions.gd").new().run_properties(self)
	if runs("hex_lifetime"):
		preload("res://features/battle/tests/hex_rule_regressions.gd").new().run_hex_lifetime(self)
	if runs("statuses"):
		preload("res://features/battle/tests/status_regressions.gd").new().run_statuses(self)
	if runs("paralysis"):
		preload("res://features/battle/tests/paralysis_regressions.gd").new().run(self)
	if runs("shield"):
		preload("res://features/battle/tests/shield_regressions.gd").new().run(self)
	if runs("push"):
		preload("res://features/battle/tests/push_regressions.gd").new().run(self)
	if runs("push_view"):
		await preload("res://features/battle/tests/push_regressions.gd").new().run_presentation(self)
	if runs("passives"):
		preload("res://features/battle/tests/passive_regressions.gd").new().run(self)
	if runs("passive_view"):
		await preload("res://features/battle/tests/passive_regressions.gd").new().run_presentation(self)
	if runs("damage_log"):
		preload("res://features/battle/tests/status_regressions.gd").new().run_damage_log(self)
	if runs("file_logging"):
		preload("res://features/battle/tests/file_logging_regressions.gd").new().run_file_logging(self)
	if runs("file_logging_ui"):
		await preload("res://features/battle/tests/file_logging_regressions.gd").new().run_file_logging_ui(self)
	if runs("file_logging_flag"):
		preload("res://features/battle/tests/file_logging_regressions.gd").new().run_file_logging_flag(self)
	if runs("turn_effect_order"):
		preload("res://features/battle/tests/status_regressions.gd").new().run_turn_effect_order(self)
	if runs("commands"):
		preload("res://features/battle/tests/session_regressions.gd").new().run_commands(self)
	if runs("content"):
		preload("res://features/battle/tests/content_regressions.gd").new().run_content(self)
	if runs("documents"):
		preload("res://features/battle/tests/content_regressions.gd").new().run_documents(self)
	if runs("ai_and_forecast"):
		preload("res://features/battle/tests/ai_regressions.gd").new().run_ai_and_forecast(self)
	if runs("tactical_ai"):
		preload("res://features/battle/tests/tactical_ai_regressions.gd").new().run(self)
	if runs("doomed_ai"):
		preload("res://features/battle/tests/ai_regressions.gd").new().run_doomed_ai(self)
	if runs("doomed_ai_search"):
		preload("res://features/battle/tests/doomed_ai_regressions.gd").new().run(self)
	if runs("ability_transactions"):
		preload("res://features/battle/tests/ability_transaction_regressions.gd").new().run(self)
	if runs("hex_propagation"):
		preload("res://features/battle/tests/hex_propagation_regressions.gd").new().run(self)
	if runs("player_selection"):
		await preload("res://features/battle/tests/player_selection_regressions.gd").new().run(self)
	if runs("hud_layout"):
		await preload("res://features/battle/tests/hud_layout_regressions.gd").new().run(self)
	if runs("atomic_files"):
		preload("res://features/battle/tests/atomic_file_regressions.gd").new().run(self)
	if runs("rule_boundaries"):
		await preload("res://features/battle/tests/rule_boundary_regressions.gd").new().run(self)
	if runs("summon_control"):
		preload("res://features/battle/tests/session_regressions.gd").new().run_summon_control(self)
	if runs("summon_references"):
		preload("res://features/battle/tests/summon_reference_regressions.gd").new().run(self)
	if runs("strategist"):
		preload("res://features/battle/tests/strategist_regressions.gd").new().run(self)
	if runs("strategist_view"):
		await preload("res://features/battle/tests/strategist_regressions.gd").new().run_presentation(self)
	if runs("simulation"):
		preload("res://features/battle/tests/session_regressions.gd").new().run_simulation(self)
	if runs("presentation"):
		await preload("res://features/battle/tests/presentation_regressions.gd").new().run_presentation(self)
	if runs("presentation_recovery"):
		await preload("res://features/battle/tests/presentation_recovery_regressions.gd").new().run(self)
	if runs("automatic_run"):
		await preload("res://features/battle/tests/automatic_run_regressions.gd").new().run(self)
	if runs("ai_threads"):
		await preload("res://features/battle/tests/ai_thread_regressions.gd").new().run(self)
	if runs("game_flow"):
		await preload("res://features/battle/tests/game_flow_regressions.gd").new().run(self)
	if runs("review_fixes"):
		preload("res://features/battle/tests/review_fix_regressions.gd").new().run_review_fixes(self)
	await _report("A_star regressions")
