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

	# --- INC-1 S1: 格一致の手応え（06_INC1検証仕様.md §3 S1） ---
	# Lexicon が WordResource を返せる（getRegistry 経路の sanity）。
	var lex := get_node("/root/Lexicon")
	r.assert_not_null(lex, "Lexicon autoload exists")
	if lex != null:
		var fj: WordResource = lex.get_word("fjandi")
		r.assert_not_null(fj, "Lexicon.get_word('fjandi') returns WordResource")
		r.assert_eq(lex.get_word("doesnotexist"), null, "Lexicon.get_word(unknown) returns null")

	if engine != null and ruleset != null:
		# S1a: meiða fjanda (対格・正) — 文法 OK / G=1.0 / 推奨修正なし
		var tokens_correct: Array = [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var c_ok: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 100.0, "rng_seed": 1})
		r.assert_not_null(c_ok, "S1a cast returns CastResult")
		if c_ok != null and c_ok.grammar_report != null:
			r.assert_true(c_ok.grammar_report.overall_pass, "S1a: 対格・正 は overall_pass=true")
			r.assert_eq(c_ok.grammar_report.g_score, 1.0, "S1a: G=1.0")
			r.assert_eq(c_ok.grammar_report.failures().size(), 0, "S1a: failures=0")

		# S1b: meiða fjandi (主格・誤) — 文法 NG / G<1 / 推奨に "fjanda" を含む
		var tokens_wrong: Array = [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "nom"},
		]
		var c_ng: CastResult = engine.cast(tokens_wrong, ruleset, {"c_override": 100.0, "rng_seed": 1})
		r.assert_not_null(c_ng, "S1b cast returns CastResult")
		if c_ng != null and c_ng.grammar_report != null:
			r.assert_false(c_ng.grammar_report.overall_pass, "S1b: 主格・誤 は overall_pass=false")
			r.assert_true(c_ng.grammar_report.g_score < 1.0, "S1b: G<1.0")
			var fails := c_ng.grammar_report.failures()
			r.assert_true(fails.size() > 0, "S1b: failures>=1")
			var found_case_finding := false
			var has_fjanda_suggestion := false
			for f in fails:
				if String(f.get("rule", "")) == "case_agreement":
					found_case_finding = true
					if String(f.get("recommended", "")).contains("fjanda"):
						has_fjanda_suggestion = true
			r.assert_true(found_case_finding, "S1b: case_agreement finding が出る")
			r.assert_true(has_fjanda_suggestion, "S1b: 推奨修正に 'fjanda' を含む")

		# T1（03 §5.5）: P_base は理解度に不依存（同じ tokens で C 違いの p_base 一致）
		var c_low: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 0.0, "rng_seed": 1})
		var c_hi: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 100.0, "rng_seed": 1})
		if c_low != null and c_hi != null:
			r.assert_eq(c_low.effect_spec.p_base, c_hi.effect_spec.p_base, "T1: P_base は C に不依存")
			# tier_sum = meida(1) + fjandi(1) = 2
			r.assert_eq(c_low.effect_spec.tier_sum, 2, "S1: tier_sum = 2 (meida+fjandi)")

		# T5（03 §5.5 v0.11 反転）: p_misfire は理解度と文法の合算
		# C=100 では base=0 なので文法違反があっても p=0（達人不変条件）
		var p_correct_100: float = c_ok.debug.get("misfire_chance", -1.0) if c_ok != null else -1.0
		var p_wrong_100: float = c_ng.debug.get("misfire_chance", -2.0) if c_ng != null else -2.0
		r.assert_eq(p_correct_100, 0.0, "T5(C=100, 違反なし): p_misfire = 0")
		r.assert_eq(p_wrong_100, 0.0, "T5(C=100, 格違反): p_misfire = 0（達人不変条件）")

		# C=50 で base=0.05。違反ゼロ → 0.05、格違反のみ → 0.10、語順違反のみ → 0.30、両方 → 0.40
		var c50_ok: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 50.0, "rng_seed": 7})
		var c50_case_only: CastResult = engine.cast(tokens_wrong, ruleset, {"c_override": 50.0, "rng_seed": 7})
		if c50_ok != null and c50_case_only != null:
			r.assert_eq(c50_ok.debug.get("misfire_chance", -1.0), 0.05, "T5(C=50, 違反なし): p_misfire = base = 0.05")
			r.assert_eq(c50_case_only.debug.get("misfire_chance", -1.0), 0.10, "T5(C=50, 格違反のみ): p_misfire = 2×base = 0.10")
			# base はどちらも 0.05
			r.assert_eq(c50_ok.debug.get("misfire_base", -1.0), 0.05, "T5: misfire_base は C のみ依存（違反なし）")
			r.assert_eq(c50_case_only.debug.get("misfire_base", -1.0), 0.05, "T5: misfire_base は C のみ依存（違反あり）")

		# compute_misfire_chance 直叩きでの境界確認
		r.assert_eq(SpellResolver.compute_misfire_chance(50.0, null), 0.05, "compute(C=50, null) = 0.05")
		r.assert_eq(SpellResolver.compute_misfire_chance(100.0, null), 0.0, "compute(C=100, null) = 0.0")
		# モックレポートを作って倍率合算を確認
		var mock_report := GrammarReport.new()
		mock_report.findings = [
			{"rule": "case_agreement", "pass": false, "severity": "moderate", "reason": "x", "recommended": ""},
			{"rule": "word_order", "pass": false, "severity": "minor", "reason": "x", "recommended": ""},
		]
		r.assert_eq(SpellResolver.compute_misfire_chance(50.0, mock_report), 0.40, "compute(C=50, case+word_order) = (2+6)×0.05 = 0.40")
		# C=100 でも違反ありで 0（達人不変条件、base=0 が支配）
		r.assert_eq(SpellResolver.compute_misfire_chance(100.0, mock_report), 0.0, "compute(C=100, case+word_order) = 0（達人不変条件）")

		# Resolver の seed 決定性: 同じ入力・同じ seed → 同じ effect_power
		var c_a: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 50.0, "rng_seed": 42})
		var c_b: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 50.0, "rng_seed": 42})
		if c_a != null and c_b != null:
			r.assert_eq(c_a.resolved.effect_power, c_b.resolved.effect_power, "Resolver seed 決定性")

		# T6（03 §5.5 v0.12 新規）: effect_power = P_base × G × randNormal(1.0, variance)
		# C=100 では variance=0 になる（Control=1.0×G + 0.6 で、G=1 → Control=1.0、G=0.5 → Control=0.8 で variance>0 だが小さい）
		# 正側: C=100, G=1.0 → variance=0 → effect_power = P_base 確定（2.3）
		var c100_ok: CastResult = engine.cast(tokens_correct, ruleset, {"c_override": 100.0, "rng_seed": 1})
		if c100_ok != null and c100_ok.resolved != null:
			r.assert_eq(c100_ok.resolved.effect_power, c100_ok.effect_spec.p_base, "T6(C=100, 正): effect_power = P_base 確定")
			r.assert_false(c100_ok.resolved.misfired, "T6(C=100, 正): 暴発しない（達人不変）")
			r.assert_eq(c100_ok.debug.get("g_mult", -1.0), 1.0, "T6(C=100, 正): g_mult = 1.0")

		# 誤側: C=100, G=0.5 → 暴発なし（達人不変）、effect_power 平均 = P_base × 0.5 = 1.15
		# variance はあるので決定的ではないが、複数 seed で平均を取れば 0.5 倍前後
		var c100_ng_single: CastResult = engine.cast(tokens_wrong, ruleset, {"c_override": 100.0, "rng_seed": 100})
		if c100_ng_single != null and c100_ng_single.resolved != null:
			r.assert_false(c100_ng_single.resolved.misfired, "T6(C=100, 誤): 暴発しない（達人不変）")
			r.assert_eq(c100_ng_single.debug.get("g_mult", -1.0), 0.5, "T6(C=100, 誤): g_mult = 0.5")

		# N=20 サンプリングで統計確認（平均 ≈ P_base × 0.5, max < P_base）
		var samples: Array[float] = []
		for s in 20:
			var c100_ng: CastResult = engine.cast(tokens_wrong, ruleset, {"c_override": 100.0, "rng_seed": 100 + s})
			if c100_ng != null and c100_ng.resolved != null:
				samples.append(c100_ng.resolved.effect_power)
		if samples.size() > 0 and c100_ok != null:
			var sum: float = 0.0
			var max_v: float = samples[0]
			for v in samples:
				sum += v
				if v > max_v: max_v = v
			var avg: float = sum / float(samples.size())
			var expected: float = c100_ok.effect_spec.p_base * 0.5
			r.assert_true(absf(avg - expected) < expected * 0.10, "T6(C=100, 誤 N=20): 平均 effect_power ≈ P_base × 0.5（got %.3f, expected %.3f）" % [avg, expected])
			# 重要不変条件: C=100 誤側の max は絶対に P_base 正側威力を超えない
			r.assert_true(max_v < c100_ok.effect_spec.p_base, "T6(C=100, 誤): max effect_power < P_base（上振れで正を超えない・got max=%.3f, P_base=%.3f）" % [max_v, c100_ok.effect_spec.p_base])

		# --- S6（語順違反のみ）と S1+S6（複合）の検証 ---
		# S6: fjanda meiða — 対格は保持・語順崩し（target が前 / effect が後）
		var tokens_s6_only: Array = [
			{"word_id": "fjandi", "case": "acc"},
			{"word_id": "meida", "case": ""},
		]
		var c50_s6: CastResult = engine.cast(tokens_s6_only, ruleset, {"c_override": 50.0, "rng_seed": 8})
		r.assert_not_null(c50_s6, "S6 cast returns CastResult")
		if c50_s6 != null and c50_s6.grammar_report != null:
			r.assert_false(c50_s6.grammar_report.overall_pass, "S6: 語順違反は overall_pass=false")
			r.assert_eq(c50_s6.grammar_report.g_score, 0.5, "S6: G=0.5（1 fail out of 2 core rules）")
			# word_order finding が出る
			var has_word_order_finding := false
			var has_case_finding := false
			for f in c50_s6.grammar_report.failures():
				var rule_name: String = String(f.get("rule", ""))
				if rule_name == "word_order":
					has_word_order_finding = true
				if rule_name == "case_agreement":
					has_case_finding = true
			r.assert_true(has_word_order_finding, "S6: word_order finding が出る")
			r.assert_false(has_case_finding, "S6: case_agreement finding は出ない（対格は保持）")
			# p_misfire = base × 6 = 0.30 at C=50
			r.assert_eq(c50_s6.debug.get("misfire_chance", -1.0), 0.30, "S6(C=50): p_misfire = 6×base = 0.30")

		# S1+S6: fjandi meiða — 格も語順も違反（最悪パターン）
		var tokens_both: Array = [
			{"word_id": "fjandi", "case": "nom"},
			{"word_id": "meida", "case": ""},
		]
		var c50_both: CastResult = engine.cast(tokens_both, ruleset, {"c_override": 50.0, "rng_seed": 9})
		r.assert_not_null(c50_both, "S1+S6 cast returns CastResult")
		if c50_both != null and c50_both.grammar_report != null:
			r.assert_false(c50_both.grammar_report.overall_pass, "S1+S6: overall_pass=false")
			r.assert_eq(c50_both.grammar_report.g_score, 0.0, "S1+S6: G=0.0（2 fails out of 2 core rules）")
			r.assert_eq(c50_both.grammar_report.failures().size(), 2, "S1+S6: failures=2 (格＋語順)")
			# p_misfire = (2+6)×base = 8×0.05 = 0.40 at C=50
			r.assert_eq(c50_both.debug.get("misfire_chance", -1.0), 0.40, "S1+S6(C=50): p_misfire = (2+6)×base = 0.40")

		# C=100, S1+S6: 達人不変条件で暴発ゼロ、G=0 で effect_power 確定 0
		var c100_both: CastResult = engine.cast(tokens_both, ruleset, {"c_override": 100.0, "rng_seed": 11})
		if c100_both != null and c100_both.resolved != null:
			r.assert_false(c100_both.resolved.misfired, "S1+S6(C=100): 暴発しない（達人不変）")
			r.assert_eq(c100_both.resolved.effect_power, 0.0, "S1+S6(C=100): effect_power = P_base × 0 = 0（成功してもゼロ）")
			r.assert_eq(c100_both.debug.get("misfire_chance", -1.0), 0.0, "S1+S6(C=100): p_misfire = 0（base=0 が支配）")

		# compute_misfire_chance での個別倍率確認
		var rep_s6_only := GrammarReport.new()
		rep_s6_only.findings = [
			{"rule": "word_order", "pass": false, "severity": "minor", "reason": "x", "recommended": ""},
		]
		r.assert_eq(SpellResolver.compute_misfire_chance(50.0, rep_s6_only), 0.30, "compute(C=50, word_order only) = 6×0.05 = 0.30")

		var rep_unknown := GrammarReport.new()
		rep_unknown.findings = [
			{"rule": "unknown_word", "pass": false, "severity": "moderate", "reason": "x", "recommended": ""},
		]
		r.assert_eq(SpellResolver.compute_misfire_chance(50.0, rep_unknown), 0.20, "compute(C=50, unknown_word only) = 4×0.05 = 0.20")

		# 三重違反（無辞書経路を想定）
		var rep_triple := GrammarReport.new()
		rep_triple.findings = [
			{"rule": "case_agreement", "pass": false, "severity": "moderate", "reason": "x", "recommended": ""},
			{"rule": "unknown_word", "pass": false, "severity": "moderate", "reason": "x", "recommended": ""},
			{"rule": "word_order", "pass": false, "severity": "minor", "reason": "x", "recommended": ""},
		]
		r.assert_eq(SpellResolver.compute_misfire_chance(50.0, rep_triple), 0.60, "compute(C=50, 全違反) = (2+4+6)×0.05 = 0.60")

	# --- Ruleset 3 段階（phase_intro / phase_beginner / phase_intermediate） ---
	var rs_intro: GrammarRuleset = load("res://data/grammar/phase_intro.tres") as GrammarRuleset
	var rs_beginner: GrammarRuleset = load("res://data/grammar/phase_beginner.tres") as GrammarRuleset
	var rs_inter: GrammarRuleset = load("res://data/grammar/phase_intermediate.tres") as GrammarRuleset
	r.assert_not_null(rs_intro, "phase_intro.tres loads")
	r.assert_not_null(rs_beginner, "phase_beginner.tres loads")
	r.assert_not_null(rs_inter, "phase_intermediate.tres loads")

	if rs_beginner != null:
		r.assert_eq(rs_beginner.id, "phase_beginner", "phase_beginner.id")
		r.assert_eq(rs_beginner.scaffold_level, "mid", "phase_beginner: scaffold=mid")
		r.assert_true(rs_beginner.is_rule_enabled("case_agreement"), "phase_beginner: case_agreement enabled")
		r.assert_true(rs_beginner.is_rule_enabled("word_order"), "phase_beginner: word_order enabled")
		r.assert_true(rs_beginner.is_rule_enabled("elements"), "phase_beginner: elements enabled")
		r.assert_false(rs_beginner.is_rule_enabled("modifier"), "phase_beginner: modifier disabled")
		r.assert_false(rs_beginner.is_rule_enabled("range"), "phase_beginner: range disabled")
		r.assert_true(rs_beginner.is_core_rule("case_agreement"), "phase_beginner: case_agreement is core")

	if rs_inter != null:
		r.assert_eq(rs_inter.id, "phase_intermediate", "phase_intermediate.id")
		r.assert_eq(rs_inter.scaffold_level, "low", "phase_intermediate: scaffold=low")
		r.assert_true(rs_inter.is_rule_enabled("case_agreement"), "phase_intermediate: case_agreement enabled")
		r.assert_true(rs_inter.is_rule_enabled("word_order"), "phase_intermediate: word_order enabled")
		r.assert_true(rs_inter.is_rule_enabled("modifier"), "phase_intermediate: modifier enabled")
		r.assert_true(rs_inter.is_rule_enabled("range"), "phase_intermediate: range enabled")
		r.assert_false(rs_inter.is_rule_enabled("condition_clause"), "phase_intermediate: condition disabled")

	# --- 修飾語 mikill / litill のロード（phase_intermediate で解禁される語） ---
	var mikill: WordResource = load("res://data/words/mikill.tres") as WordResource
	var litill: WordResource = load("res://data/words/litill.tres") as WordResource
	r.assert_not_null(mikill, "mikill.tres loads")
	r.assert_not_null(litill, "litill.tres loads")
	if mikill != null:
		r.assert_eq(mikill.word_class, "modifier", "mikill.word_class = modifier")
		r.assert_eq(mikill.get_gloss("ja"), "大いに", "mikill.gloss.ja = 大いに")
	if litill != null:
		r.assert_eq(litill.word_class, "modifier", "litill.word_class = modifier")

	# Lexicon が新規語も引ける
	if lex != null:
		r.assert_eq(lex.get_known_word_ids().size(), 9, "Lexicon: 9 語に拡張 (修飾語 +2)")
		r.assert_not_null(lex.get_word("mikill"), "Lexicon.get_word('mikill') returns WordResource")

	# --- T7（03 §5.5 v0.13）: elements / modifier 判定 ---
	var engine2 := get_node("/root/SpellEngine")
	if engine2 != null and rs_intro != null and rs_inter != null:
		# elements: 1 元素 OK (phase_intro で elements enabled)
		var tokens_1el: Array = [
			{"word_id": "eldr", "case": ""},
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_1el: CastResult = engine2.cast(tokens_1el, rs_intro, {"c_override": 100.0, "rng_seed": 1})
		if r_1el != null and r_1el.grammar_report != null:
			var fails_1el := r_1el.grammar_report.failures()
			var has_el_finding := false
			for f in fails_1el:
				if String(f.get("rule", "")) == "elements":
					has_el_finding = true
			r.assert_false(has_el_finding, "T7(1 元素): elements finding なし")

		# elements: 2 元素 NG (半端な属性合成)
		var tokens_2el: Array = [
			{"word_id": "eldr", "case": ""},
			{"word_id": "vatn", "case": ""},
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_2el: CastResult = engine2.cast(tokens_2el, rs_intro, {"c_override": 100.0, "rng_seed": 1})
		if r_2el != null and r_2el.grammar_report != null:
			r.assert_false(r_2el.grammar_report.overall_pass, "T7(2 元素): overall_pass=false")
			var has_el_finding2 := false
			var reason_str := ""
			for f in r_2el.grammar_report.failures():
				if String(f.get("rule", "")) == "elements":
					has_el_finding2 = true
					reason_str = String(f.get("reason", ""))
			r.assert_true(has_el_finding2, "T7(2 元素): elements finding が出る")
			r.assert_true(reason_str.contains("不発"), "T7(2 元素): reason に「不発」を含む")

		# elements: 4 元素全部 OK + chaos マーク
		var tokens_4el: Array = [
			{"word_id": "eldr", "case": ""},
			{"word_id": "vatn", "case": ""},
			{"word_id": "vindr", "case": ""},
			{"word_id": "jorth", "case": ""},
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_4el: CastResult = engine2.cast(tokens_4el, rs_intro, {"c_override": 100.0, "rng_seed": 1})
		if r_4el != null and r_4el.grammar_report != null and r_4el.effect_spec != null:
			r.assert_true(r_4el.grammar_report.overall_pass, "T7(4 元素): overall_pass=true（混沌属性）")
			r.assert_true(r_4el.effect_spec.modifiers.get("chaos", false), "T7(4 元素): effect_spec.modifiers.chaos = true")

		# modifier: 修飾語あり＋効果語あり OK (phase_intermediate で modifier enabled)
		# v0.14: modifier も case="acc" にして agreement OK にする。
		# v0.15: modifier は target に隣接（修飾-名詞）させる。
		var tokens_mod_ok: Array = [
			{"word_id": "meida", "case": ""},
			{"word_id": "mikill", "case": "acc"},  # v0.14: target.case と一致／v0.15: target 直前
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_mod_ok: CastResult = engine2.cast(tokens_mod_ok, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_mod_ok != null and r_mod_ok.grammar_report != null and r_mod_ok.effect_spec != null:
			r.assert_true(r_mod_ok.grammar_report.overall_pass, "T7(mod OK): overall_pass=true")
			# P_base = (tier_sum + bonus) × modifier_factor
			# tier_sum = effect(1)+target(1) = 2 ※ modifier は tier_sum に含まれない（v0.13）
			# bonus = 2×0.15 = 0.30
			# P_base = (2 + 0.30) × 1.5 = 3.45
			r.assert_true(r_mod_ok.effect_spec.p_base > 3.4, "T7(mikill): P_base ×1.5 適用 (got %.3f)" % r_mod_ok.effect_spec.p_base)
			r.assert_true(r_mod_ok.effect_spec.p_base < 3.5, "T7(mikill): P_base 約 3.45")

		# modifier: 修飾語ありかつ効果語なし NG（phase_intermediate）
		var tokens_mod_alone: Array = [
			{"word_id": "mikill", "case": ""},
		]
		var r_mod_alone: CastResult = engine2.cast(tokens_mod_alone, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_mod_alone != null and r_mod_alone.grammar_report != null:
			r.assert_false(r_mod_alone.grammar_report.overall_pass, "T7(mod alone): overall_pass=false")
			var has_mod_finding := false
			for f in r_mod_alone.grammar_report.failures():
				if String(f.get("rule", "")) == "modifier":
					has_mod_finding = true
			r.assert_true(has_mod_finding, "T7(mod alone): modifier finding が出る")
			# 効果語なしなら P_base = 0（v0.13 ガード）
			if r_mod_alone.effect_spec != null:
				r.assert_eq(r_mod_alone.effect_spec.p_base, 0.0, "T7(mod alone): P_base = 0（効果語なし）")

		# modifier: phase_intro では modifier disabled なので、mikill 含めても modifier finding は出ない
		var tokens_mod_intro: Array = [
			{"word_id": "mikill", "case": ""},
		]
		var r_mod_intro: CastResult = engine2.cast(tokens_mod_intro, rs_intro, {"c_override": 100.0, "rng_seed": 1})
		if r_mod_intro != null and r_mod_intro.grammar_report != null:
			var has_mod_finding_intro := false
			for f in r_mod_intro.grammar_report.failures():
				if String(f.get("rule", "")) == "modifier":
					has_mod_finding_intro = true
			r.assert_false(has_mod_finding_intro, "T7(phase_intro): modifier disabled なので finding 出ない")

		# litill ×0.7 確認（v0.14: agreement のため case="acc" 一致／v0.15: target 隣接）
		var tokens_litill: Array = [
			{"word_id": "meida", "case": ""},
			{"word_id": "litill", "case": "acc"},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_litill: CastResult = engine2.cast(tokens_litill, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_litill != null and r_litill.effect_spec != null:
			# P_base = (2 + 0.30) × 0.7 = 1.61
			r.assert_true(r_litill.effect_spec.p_base > 1.55, "T7(litill): P_base ×0.7 (got %.3f)" % r_litill.effect_spec.p_base)
			r.assert_true(r_litill.effect_spec.p_base < 1.65, "T7(litill): P_base 約 1.61")

	# elements / modifier の倍率テーブル直叩き確認
	var rep_el := GrammarReport.new()
	rep_el.findings = [{"rule": "elements", "pass": false, "severity": "minor", "reason": "x", "recommended": ""}]
	r.assert_eq(SpellResolver.compute_misfire_chance(50.0, rep_el), 0.075, "compute(C=50, elements only) = 1.5×0.05 = 0.075")

	var rep_mod := GrammarReport.new()
	rep_mod.findings = [{"rule": "modifier", "pass": false, "severity": "minor", "reason": "x", "recommended": ""}]
	r.assert_eq(SpellResolver.compute_misfire_chance(50.0, rep_mod), 0.075, "compute(C=50, modifier only) = 1.5×0.05 = 0.075")

	# --- T8（03 §5.5 v0.14）: 4 格データと修飾一致 ---
	# 4 格データの存在確認
	var fj_v14: WordResource = load("res://data/words/fjandi.tres") as WordResource
	if fj_v14 != null:
		r.assert_eq(fj_v14.get_inflected("sg", "dat"), "fjanda", "fjandi sg.dat = fjanda (n-stem 弱変化)")
		r.assert_eq(fj_v14.get_inflected("sg", "gen"), "fjanda", "fjandi sg.gen = fjanda")
	var sj_v14: WordResource = load("res://data/words/sjalfr.tres") as WordResource
	if sj_v14 != null:
		r.assert_eq(sj_v14.get_inflected("sg", "dat"), "sjalfum", "sjalfr sg.dat = sjalfum")
		r.assert_eq(sj_v14.get_inflected("sg", "gen"), "sjalfs", "sjalfr sg.gen = sjalfs")
	var jorth_v14: WordResource = load("res://data/words/jorth.tres") as WordResource
	if jorth_v14 != null:
		r.assert_eq(jorth_v14.get_inflected("sg", "dat"), "jörðu", "jörð sg.dat = jörðu (i-stem 化女性)")
		r.assert_eq(jorth_v14.get_inflected("sg", "gen"), "jarðar", "jörð sg.gen = jarðar")

	# mikill 形容詞活用表（12 形）
	var mik_v14: WordResource = load("res://data/words/mikill.tres") as WordResource
	if mik_v14 != null:
		r.assert_true(mik_v14.has_gendered_inflection(), "mikill: 形容詞活用 (gender 別) を持つ")
		# 男性
		r.assert_eq(mik_v14.get_inflected("sg", "nom", "masculine"), "mikill", "mikill sg.masc.nom = mikill")
		r.assert_eq(mik_v14.get_inflected("sg", "acc", "masculine"), "mikinn", "mikill sg.masc.acc = mikinn")
		r.assert_eq(mik_v14.get_inflected("sg", "dat", "masculine"), "miklum", "mikill sg.masc.dat = miklum")
		r.assert_eq(mik_v14.get_inflected("sg", "gen", "masculine"), "mikils", "mikill sg.masc.gen = mikils")
		# 女性
		r.assert_eq(mik_v14.get_inflected("sg", "acc", "feminine"), "mikla", "mikill sg.fem.acc = mikla")
		# 中性
		r.assert_eq(mik_v14.get_inflected("sg", "acc", "neuter"), "mikit", "mikill sg.neut.acc = mikit")

	# litill 同様（要点のみ）
	var lit_v14: WordResource = load("res://data/words/litill.tres") as WordResource
	if lit_v14 != null:
		r.assert_true(lit_v14.has_gendered_inflection(), "litill: 形容詞活用を持つ")
		r.assert_eq(lit_v14.get_inflected("sg", "acc", "masculine"), "lítinn", "litill sg.masc.acc = lítinn")

	# 修飾一致判定（modifier_agreement、phase_intermediate で modifier enabled）
	if engine != null and rs_inter != null:
		# OK: mikinn (masc.acc) + meiða + fjanda (masc.acc)
		# v0.15: 正準語順は meiða mikinn fjanda（V + 修飾-名詞）。
		var tokens_mod_ok: Array = [
			{"word_id": "meida",  "case": ""},
			{"word_id": "mikill", "case": "acc"},  # masc.acc = mikinn を期待
			{"word_id": "fjandi", "case": "acc"},  # masc.acc = fjanda
		]
		var r_ok: CastResult = engine.cast(tokens_mod_ok, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_ok != null and r_ok.grammar_report != null:
			r.assert_true(r_ok.grammar_report.overall_pass, "T8: mikill(acc) + fjandi(acc) は文法 OK")
			var has_agreement_finding := false
			for f in r_ok.grammar_report.failures():
				if String(f.get("rule", "")) == "modifier_agreement":
					has_agreement_finding = true
			r.assert_false(has_agreement_finding, "T8(一致): modifier_agreement finding なし")

		# NG: mikill (masc.nom) + meiða + fjanda (masc.acc) → 格不一致
		# v0.15: modifier は target に隣接させる（語順は OK、格だけ不一致にする）。
		var tokens_mod_ng: Array = [
			{"word_id": "meida",  "case": ""},
			{"word_id": "mikill", "case": "nom"},  # 主格 → modifier_agreement 違反
			{"word_id": "fjandi", "case": "acc"},  # 対格
		]
		var r_ng: CastResult = engine.cast(tokens_mod_ng, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_ng != null and r_ng.grammar_report != null:
			r.assert_false(r_ng.grammar_report.overall_pass, "T8: mikill(nom) + fjandi(acc) は文法 NG")
			var has_finding := false
			var has_mikinn_suggestion := false
			for f in r_ng.grammar_report.failures():
				if String(f.get("rule", "")) == "modifier_agreement":
					has_finding = true
					if String(f.get("recommended", "")).contains("mikinn"):
						has_mikinn_suggestion = true
			r.assert_true(has_finding, "T8(不一致): modifier_agreement finding が出る")
			r.assert_true(has_mikinn_suggestion, "T8(不一致): 推奨修正に 'mikinn' を含む")

		# 中性名詞との一致: もし vatn を対象として使えるなら mikit を期待
		# （vatn の word_class は element だが gender=neuter なので、ここでは fjandi (masc) のみ確認）

		# 倍率テーブル: modifier_agreement = ×2.0
		var rep_agr := GrammarReport.new()
		rep_agr.findings = [{"rule": "modifier_agreement", "pass": false, "severity": "moderate", "reason": "x", "recommended": ""}]
		r.assert_eq(SpellResolver.compute_misfire_chance(50.0, rep_agr), 0.10, "compute(C=50, modifier_agreement) = 2.0×0.05 = 0.10")

	# --- T9（03 §5.5 v0.15）: アイスランド語準拠の正準語順 ---
	if engine != null and rs_inter != null:
		# ◯ meiða mikinn fjanda（V + 修飾-名詞）
		var t_vmn: Array = [
			{"word_id": "meida",  "case": ""},
			{"word_id": "mikill", "case": "acc"},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_vmn: CastResult = engine.cast(t_vmn, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_vmn != null and r_vmn.grammar_report != null:
			var has_wo := false
			for f in r_vmn.grammar_report.failures():
				if String(f.get("rule", "")) == "word_order":
					has_wo = true
			r.assert_false(has_wo, "T9(V 修 名): word_order finding なし")

		# ◯ eldr meiða mikinn fjanda（属性前置）
		var t_emvn: Array = [
			{"word_id": "eldr",   "case": ""},
			{"word_id": "meida",  "case": ""},
			{"word_id": "mikill", "case": "acc"},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_emvn: CastResult = engine.cast(t_emvn, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_emvn != null and r_emvn.grammar_report != null:
			var has_wo2 := false
			for f in r_emvn.grammar_report.failures():
				if String(f.get("rule", "")) == "word_order":
					has_wo2 = true
			r.assert_false(has_wo2, "T9(属 V 修 名): word_order finding なし")

		# ◯ meiða mikinn fjanda eldr（属性後置 道具的）
		var t_vmne: Array = [
			{"word_id": "meida",  "case": ""},
			{"word_id": "mikill", "case": "acc"},
			{"word_id": "fjandi", "case": "acc"},
			{"word_id": "eldr",   "case": ""},
		]
		var r_vmne: CastResult = engine.cast(t_vmne, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_vmne != null and r_vmne.grammar_report != null:
			var has_wo3 := false
			for f in r_vmne.grammar_report.failures():
				if String(f.get("rule", "")) == "word_order":
					has_wo3 = true
			r.assert_false(has_wo3, "T9(V 修 名 属): word_order finding なし")

		# ✗ meiða eldr mikinn fjanda（属性が effect-target 間）
		var t_vemn: Array = [
			{"word_id": "meida",  "case": ""},
			{"word_id": "eldr",   "case": ""},
			{"word_id": "mikill", "case": "acc"},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_vemn: CastResult = engine.cast(t_vemn, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_vemn != null and r_vemn.grammar_report != null:
			var has_wo4 := false
			var reason_str: String = ""
			for f in r_vemn.grammar_report.failures():
				if String(f.get("rule", "")) == "word_order":
					has_wo4 = true
					reason_str = String(f.get("reason", ""))
			r.assert_true(has_wo4, "T9(V 属 修 名): word_order finding が出る（属性が間に挟まれた）")
			r.assert_true(reason_str.contains("属性"), "T9: 属性配置エラーメッセージを含む")

		# ✗ mikinn meiða fjanda（修飾が動詞越しに離れる）
		var t_mvn: Array = [
			{"word_id": "mikill", "case": "acc"},
			{"word_id": "meida",  "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var r_mvn: CastResult = engine.cast(t_mvn, rs_inter, {"c_override": 100.0, "rng_seed": 1})
		if r_mvn != null and r_mvn.grammar_report != null:
			var has_wo5 := false
			var reason5: String = ""
			for f in r_mvn.grammar_report.failures():
				if String(f.get("rule", "")) == "word_order":
					has_wo5 = true
					reason5 = String(f.get("reason", ""))
			r.assert_true(has_wo5, "T9(修 V 名): word_order finding が出る（修飾が離れた）")
			r.assert_true(reason5.contains("形容詞") or reason5.contains("修飾"), "T9: 修飾語隣接エラーメッセージを含む")

	# --- v0.17: シナリオ JSON のロード確認 ---
	var idx_file := FileAccess.open("res://tests/scenarios/index.json", FileAccess.READ)
	r.assert_not_null(idx_file, "scenarios/index.json が存在する")
	if idx_file != null:
		var idx_data: Variant = JSON.parse_string(idx_file.get_as_text())
		idx_file.close()
		r.assert_true(typeof(idx_data) == TYPE_DICTIONARY, "index.json が辞書として parse できる")
		if typeof(idx_data) == TYPE_DICTIONARY:
			var scn_list: Array = idx_data.get("scenarios", [])
			r.assert_eq(scn_list.size(), 7, "シナリオ 7 個（S1正/S1誤/S2/S3/S4/S5/S6）")
			# 各シナリオを実際に読めるか
			for fname in scn_list:
				var f := FileAccess.open("res://tests/scenarios/" + String(fname), FileAccess.READ)
				r.assert_not_null(f, "scenarios/%s が存在する" % fname)
				if f != null:
					var scn: Variant = JSON.parse_string(f.get_as_text())
					f.close()
					r.assert_true(typeof(scn) == TYPE_DICTIONARY, "%s が辞書として parse できる" % fname)
					if typeof(scn) == TYPE_DICTIONARY:
						r.assert_true((scn as Dictionary).has("id"), "%s に id" % fname)
						r.assert_true((scn as Dictionary).has("name"), "%s に name" % fname)
						r.assert_true((scn as Dictionary).has("tokens"), "%s に tokens" % fname)

	# --- v0.17: i18n 文言キーがロードできる ---
	# TranslationServer.translate() は ja.po / en.po 経由で文言を返す。
	# キーが未登録だとキー文字列がそのまま返るので、明示的に翻訳が効いていることを確認。
	# 現在のロケールは ja (project.godot の locale/fallback="ja")。
	var ja_keys: PackedStringArray = PackedStringArray([
		"grammar.case_agreement.reason",
		"grammar.case_agreement.recommended",
		"grammar.word_order.modifier_adjacency",
		"grammar.word_order.element_inserted",
		"grammar.elements.partial_combo",
		"grammar.modifier.standalone",
		"grammar.modifier_agreement.case_mismatch",
		"grammar.case.nom",
		"grammar.case.acc",
		"grammar.case.dat",
		"grammar.case.gen",
	])
	for key in ja_keys:
		var translated: String = TranslationServer.translate(key)
		r.assert_true(not translated.is_empty() and translated != key, "i18n: %s 翻訳済み (got '%s')" % [key, translated])

	# 4 ruleset 揃っている確認 (v0.16 で phase_advanced 追加)
	var rs_advanced: GrammarRuleset = load("res://data/grammar/phase_advanced.tres") as GrammarRuleset
	r.assert_not_null(rs_advanced, "phase_advanced.tres loads")
	if rs_advanced != null:
		r.assert_eq(rs_advanced.scaffold_level, "none", "phase_advanced: scaffold=none")
		r.assert_true(rs_advanced.is_rule_enabled("modifier"), "phase_advanced: modifier enabled")
		r.assert_true(rs_advanced.is_rule_enabled("condition_clause"), "phase_advanced: condition enabled")

	r.print_summary()

	# 自動終了（CLI からの実行も想定）。エディタで F5 した場合は手動で閉じる。
	# get_tree().quit() を呼ぶとエディタ実行が即終了するので INC-0 は呼ばない。
