extends "res://features/battle/tests/check_suite.gd"
## Regressions of the development tools, run by tools/tests/run_tests.py through
## features/battle/tests/run_regressions.gd with --suite. The game regressions never load tools/.


func _run() -> void:
	if runs("battle_editor"):
		await preload("res://tools/battles/tests/battle_editor_regressions.gd").new().run(self)
	if runs("unit_editor"):
		await preload("res://tools/units/tests/unit_editor_regressions.gd").new().run(self)
	if runs("skill_editor"):
		await preload("res://tools/skills/tests/skill_editor_regressions.gd").new().run(self)
	if runs("previews"):
		preload("res://tools/previews/tests/preview_regressions.gd").new().run(self)
	await _report("A_star tool regressions")
