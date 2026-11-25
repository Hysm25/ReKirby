extends SceneTree
## Headless automated test runner executed via: godot --headless -s tests/test_runner.gd

const TEST_SUITES: Array[String] = [
	"res://tests/test_importer.gd",
	"res://tests/test_physics.gd",
	"res://tests/test_audio.gd",
]


func _initialize() -> void:
	var total_passed: int = 0
	var total_failed: int = 0

	print("========================================")
	print("ReKirby Headless Verification Suite")
	print("========================================")

	for suite_path: String in TEST_SUITES:
		var script_res: Resource = load(suite_path)
		if script_res == null or not (script_res is GDScript):
			printerr("[FAIL] Unable to load test suite: %s" % suite_path)
			total_failed += 1
			continue

		var suite_script: GDScript = script_res as GDScript
		var suite_instance: Variant = suite_script.new()
		if suite_instance == null or not suite_instance.has_method("run_tests"):
			printerr("[FAIL] Test suite missing run_tests(): %s" % suite_path)
			total_failed += 1
			continue

		var t0: int = Time.get_ticks_msec()
		var report_variant: Variant = suite_instance.call("run_tests")
		var elapsed_ms: int = Time.get_ticks_msec() - t0
		if not (report_variant is Dictionary):
			printerr("[FAIL] Invalid report returned from %s" % suite_path)
			total_failed += 1
			continue

		var report: Dictionary = report_variant as Dictionary
		var passed: int = int(report.get("passed", 0))
		var failed: int = int(report.get("failed", 0))
		total_passed += passed
		total_failed += failed
		print("[SUITE] %s -> passed=%d failed=%d (%d ms)" % [suite_path, passed, failed, elapsed_ms])

	print("----------------------------------------")
	print("TOTAL: passed=%d failed=%d" % [total_passed, total_failed])
	print("========================================")

	if total_failed > 0:
		quit(1)
	else:
		quit(0)
