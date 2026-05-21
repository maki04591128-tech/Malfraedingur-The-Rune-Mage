extends Node
## test_smoke.gd — INC-0 スモークテスト。
##
## 目的: 「土台が壊れていない」ことを高速に確認する 1 本。
##        Resource/Model クラスが construct でき、最小 .tres が読めて、
##        SpellEngine.cast() がエラーなく CastResult を返すこと。
##
## 実行: tests/test_smoke.tscn を main_scene にして F5 / F6 で実行。
## 期待: print に "ALL GREEN" が出る。push_error が出たら FAIL。
##
## INC-1 で T1〜T3（03 §5.5）の不変条件テストを追加して GUT 等への置換を検討。

func _ready() -> void:
	var r := TestRunner.new()

	# --- モデルが construct できる ---
	var report := GrammarReport.new()
	r.assert_not_null(report, "GrammarReport.new()")
	r.assert_false(report.overall_pass, "GrammarReport.overall_pass defaults false")

	var spec := EffectSpec.new()
	r.assert_not_null(spec, "EffectSpec.new()")
	r.assert_eq(spec.tier_sum, 0, "EffectSpec.tier_sum defaults 0")

	var resolved := ResolvedEffect.new()
	r.assert_not_null(resolved, "ResolvedEffect.new()")
	r.assert_false(resolved.misfired, "ResolvedEffect.misfired defaults false")

	var result := CastResult.new()
	r.assert_not_null(result, "CastResult.new()")
	r.assert_true(result.is_successful(), "Empty CastResult is_successful() = true (空シェル既定)")

	# --- 最小 .tres が読める ---
	var fjandi: WordResource = load("res://data/words/fjandi.tres") as WordResource
	r.assert_not_null(fjandi, "fjandi.tres loads as WordResource")
	if fjandi != null:
		r.assert_eq(fjandi.id, "fjandi", "fjandi.id")
		r.assert_eq(fjandi.word_class, "target", "fjandi.word_class")
		r.assert_eq(fjandi.gender, "masculine", "fjandi.gender")
		r.assert_eq(fjandi.get_inflected("sg", "nom"), "fjandi", "fjandi sg.nom = fjandi")
		r.assert_eq(fjandi.get_inflected("sg", "acc"), "fjanda", "fjandi sg.acc = fjanda")
		r.assert_eq(fjandi.get_gloss("ja"), "敵", "fjandi.gloss.ja = 敵")

	var ruleset: GrammarRuleset = load("res://data/grammar/phase_intro.tres") as GrammarRuleset
	r.assert_not_null(ruleset, "phase_intro.tres loads as GrammarRuleset")
	if ruleset != null:
		r.assert_eq(ruleset.id, "phase_intro", "ruleset.id")
		r.assert_eq(ruleset.scaffold_level, "max", "ruleset.scaffold_level")
		r.assert_true(ruleset.is_rule_enabled("case_agreement"), "case_agreement enabled")
		r.assert_true(ruleset.is_core_rule("case_agreement"), "case_agreement is core")
		r.assert_false(ruleset.is_rule_enabled("modifier"), "modifier disabled in phase_intro")

	# --- SpellEngine の縦の骨が通る ---
	var engine := get_node("/root/SpellEngine")
	r.assert_not_null(engine, "SpellEngine autoload exists")
	if engine != null:
		var tokens_in: Array = [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var cast_result: CastResult = engine.cast(tokens_in, ruleset)
		r.assert_not_null(cast_result, "cast() returns CastResult")
		if cast_result != null:
			r.assert_not_null(cast_result.grammar_report, "cast_result.grammar_report populated")
			r.assert_not_null(cast_result.effect_spec, "cast_result.effect_spec populated")
			r.assert_not_null(cast_result.resolved, "cast_result.resolved populated")
			r.assert_true(cast_result.debug.has("misfire_chance"), "debug has misfire_chance")

	# --- Resolver の数式（03 §5.2 確定式） ---
	r.assert_eq(SpellResolver.compute_misfire_chance(0.0), 0.10, "C=0 → 暴発10%")
	r.assert_eq(SpellResolver.compute_misfire_chance(50.0), 0.05, "C=50 → 暴発5%")
	r.assert_eq(SpellResolver.compute_misfire_chance(100.0), 0.0, "C=100 → 暴発0%")
	r.assert_eq(SpellResolver.band_for(30.0), "activation", "C=30 → activation band")
	r.assert_eq(SpellResolver.band_for(60.0), "execution", "C=60 → execution band")
	r.assert_eq(SpellResolver.band_for(99.0), "control", "C=99 → control band")
	r.assert_eq(SpellResolver.band_for(100.0), "none", "C=100 → no misfire band")

	r.print_summary()

	# 自動終了（CLI からの実行も想定）。エディタで F5 した場合は手動で閉じる。
	# get_tree().quit() を呼ぶとエディタ実行が即終了するので INC-0 は呼ばない。
