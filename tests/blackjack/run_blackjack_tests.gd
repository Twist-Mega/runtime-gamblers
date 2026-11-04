extends Node
## Open blackjack_tests.tscn and Run Current Scene (F6) to run all blackjack suites.
## Reuse the running Godot executable, so no PATH or machine-specific setup is needed.

const SUITES = [
	{"script": "res://tests/blackjack/test_blackjack_engine.gd", "log": "blackjack-tests.log"},
	{"script": "res://tests/blackjack/test_blackjack_session_controller.gd", "log": "blackjack-session-tests.log"},
	{"script": "res://tests/blackjack/test_blackjack_debug.gd", "log": "blackjack-debug-tests.log"},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed: bool = false
	for suite in SUITES:
		print("Running %s" % suite.script)
		var output: Array = []
		var arguments := PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", ProjectSettings.globalize_path("res://.godot/" + suite.log),
			"--script", suite.script,
		])
		var exit_code := OS.execute(OS.get_executable_path(), arguments, output, true, false)
		for chunk in output:
			print(String(chunk).strip_edges())
		if exit_code != 0:
			failed = true
			push_error("Suite failed: %s (exit code %d)." % [suite.script, exit_code])
	if failed:
		push_error("Blackjack tests: FAILED. Look above for FAIL or SCRIPT ERROR and the test name.")
	else:
		print("Blackjack tests: ALL SUITES PASSED.")
	get_tree().quit(1 if failed else 0)
