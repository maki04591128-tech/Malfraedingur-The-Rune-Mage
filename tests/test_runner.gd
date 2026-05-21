extends RefCounted
class_name TestRunner
## TestRunner — 最小アサーション API＋実行ログ。
##
## INC-0 はこの自前ランナーで足りる（テストは smoke 1本）。
## INC-1 で T1〜T3 不変条件テスト（03 §5.5）の本数が増えたら GUT 等への置換を検討する。
##
## 使い方:
##   var r := TestRunner.new()
##   r.assert_eq(SpellResolver.compute_misfire_chance(100.0), 0.0, "C=100 で暴発0")
##   r.print_summary()

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func assert_true(cond: bool, label: String = "") -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append("[FAIL] %s — expected true" % label)


func assert_false(cond: bool, label: String = "") -> void:
	assert_true(not cond, label)


func assert_eq(actual: Variant, expected: Variant, label: String = "") -> void:
	if typeof(actual) == TYPE_FLOAT and typeof(expected) == TYPE_FLOAT:
		# 浮動小数は近似比較。
		if is_equal_approx(actual, expected):
			_passed += 1
			return
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func assert_not_null(value: Variant, label: String = "") -> void:
	assert_true(value != null, label)


func passed() -> int:
	return _passed


func failed() -> int:
	return _failed


func is_green() -> bool:
	return _failed == 0


func print_summary() -> void:
	var total: int = _passed + _failed
	print("=== TestRunner Summary ===")
	print("  passed: %d / %d" % [_passed, total])
	if _failed > 0:
		for f in _failures:
			print("  ", f)
		push_error("TEST FAILED: %d/%d" % [_failed, total])
	else:
		print("  ALL GREEN")
