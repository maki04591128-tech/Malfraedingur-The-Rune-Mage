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

	# --- INC-2 v0.1: 戦闘層スケルトン ---

	# Combatant の基本動作
	var c1 := Combatant.new("Dummy", 100.0, {"fire": 0.5})
	r.assert_not_null(c1, "Combatant.new() ok")
	r.assert_eq(c1.hp, 100.0, "Combatant: 初期 HP = max_hp")
	r.assert_true(c1.is_alive(), "Combatant: 初期は alive")
	r.assert_eq(c1.take_damage(30.0), 30.0, "Combatant: 30 ダメ適用 = 30 戻り")
	r.assert_eq(c1.hp, 70.0, "Combatant: HP 100→70")
	r.assert_eq(c1.heal(10.0), 10.0, "Combatant: 10 回復 = 10 戻り")
	r.assert_eq(c1.hp, 80.0, "Combatant: HP 70→80")
	r.assert_eq(c1.heal(1000.0), 20.0, "Combatant: overheal は max_hp で頭打ち")
	r.assert_eq(c1.hp, 100.0, "Combatant: 上限 100 clamp")
	r.assert_eq(c1.take_damage(0.0), 0.0, "Combatant: 0 ダメ NOP")
	r.assert_eq(c1.take_damage(-5.0), 0.0, "Combatant: 負ダメ NOP")
	r.assert_eq(c1.take_damage(150.0), 100.0, "Combatant: 過剰ダメは max_hp で頭打ち")
	r.assert_eq(c1.hp, 0.0, "Combatant: HP 0 になる")
	r.assert_false(c1.is_alive(), "Combatant: HP 0 で死亡")
	r.assert_eq(c1.resist_mult_for("fire"), 0.5, "Combatant: fire 耐性 0.5")
	r.assert_eq(c1.resist_mult_for("water"), 1.0, "Combatant: 未定義属性は 1.0")
	r.assert_eq(c1.resist_mult_for(""), 1.0, "Combatant: 空属性は 1.0")

	# DamageCalculator: 通常命中
	var fake_resolved := ResolvedEffect.new()
	fake_resolved.effect_power = 12.0
	fake_resolved.target_word_id = "fjandi"
	fake_resolved.misfired = false
	var target_c := Combatant.new("Enemy", 50.0, {})
	var calc := DamageCalculator.compute(fake_resolved, target_c, {})
	# v0.2: DAMAGE_SCALE=3.0 を全ダメに掛ける。12.0 × 3.0 = 36.0
	r.assert_eq(calc["to_target"], 36.0, "DC: 命中 → to_target=36.0 (=12.0×DAMAGE_SCALE 3.0)")
	r.assert_eq(calc["to_self"], 0.0, "DC: 命中 → to_self=0")
	r.assert_false(calc["is_self_target"], "DC: 通常は is_self_target=false")

	# DamageCalculator: 自爆 (control band)
	var fake_misfired := ResolvedEffect.new()
	fake_misfired.effect_power = 0.0
	fake_misfired.self_damage = 5.0
	fake_misfired.misfired = true
	fake_misfired.misfire_category = "control"
	fake_misfired.misfire_outcome = "self_damage"
	fake_misfired.target_word_id = "fjandi"
	var calc2 := DamageCalculator.compute(fake_misfired, target_c, {})
	r.assert_eq(calc2["to_target"], 0.0, "DC: 自爆 → to_target=0")
	# v0.2: self_damage 5.0 × DAMAGE_SCALE 3.0 = 15.0
	r.assert_eq(calc2["to_self"], 15.0, "DC: 自爆 → to_self=15.0 (=5.0×3.0)")

	# DamageCalculator: 自己対象 (sjalfr)
	var fake_self := ResolvedEffect.new()
	fake_self.effect_power = 8.0
	fake_self.target_word_id = "sjalfr"
	var calc3 := DamageCalculator.compute(fake_self, target_c, {})
	r.assert_true(calc3["is_self_target"], "DC: sjalfr → is_self_target=true")
	r.assert_eq(calc3["to_target"], 0.0, "DC: sjalfr → to_target=0")
	r.assert_eq(calc3["to_self"], 8.0, "DC: sjalfr → to_self=8.0（自分に流れる）")

	# DamageCalculator: 元素耐性
	var fake_fire := ResolvedEffect.new()
	fake_fire.effect_power = 10.0
	fake_fire.target_word_id = "fjandi"
	var fire_resistant := Combatant.new("FireResist", 50.0, {"fire": 0.5})
	var calc4 := DamageCalculator.compute(fake_fire, fire_resistant, {"dominant_element": "fire"})
	# v0.2: 10.0 × 0.5 (耐性) × 3.0 (DAMAGE_SCALE) = 15.0
	r.assert_eq(calc4["to_target"], 15.0, "DC: fire 耐性 0.5 → 15.0 (=10×0.5×3.0)")

	# DamageCalculator: 世界時間 Δ
	r.assert_eq(DamageCalculator.compute_world_time_delta(2, 2), 3.0, "DC: Δ(2 語, tier_sum=2) = 2 + 1.0 = 3.0")
	r.assert_eq(DamageCalculator.compute_world_time_delta(3, 4), 5.0, "DC: Δ(3 語, tier_sum=4) = 3 + 2.0 = 5.0")

	# CombatSystem: 雑魚→ボス→FLOOR_CLEAR
	var cs := CombatSystem.new()
	var p_c := Combatant.new("Player", 100.0, {})
	var zako := Combatant.new("Zako", 10.0, {})
	var boss := Combatant.new("Boss", 20.0, {})
	cs.start_floor(p_c, [zako, boss], [3.0, 5.0])
	r.assert_eq(cs.state, CombatSystem.State.PLAYER_TURN, "CS: start で PLAYER_TURN")
	r.assert_eq(cs.turn_count, 1, "CS: start で T=1")
	r.assert_eq(cs.current_enemy_index, 0, "CS: start で current=0 (雑魚)")
	r.assert_false(cs.is_over(), "CS: start で is_over=false")

	var kill_cast := CastResult.new()
	kill_cast.grammar_report = GrammarReport.new()
	kill_cast.grammar_report.overall_pass = true
	kill_cast.effect_spec = EffectSpec.new()
	kill_cast.effect_spec.tier_sum = 2
	kill_cast.resolved = ResolvedEffect.new()
	kill_cast.resolved.effect_power = 15.0
	kill_cast.resolved.target_word_id = "fjandi"

	var info1 := cs.apply_cast(kill_cast, 2, 2)
	r.assert_true(info1["enemy_killed"], "CS: 雑魚撃破")
	r.assert_eq(cs.current_enemy_index, 1, "CS: 次の敵に進む (current=1=Boss)")
	r.assert_eq(cs.state, CombatSystem.State.ENEMY_TURN, "CS: 雑魚撃破後は ENEMY_TURN")
	r.assert_false(info1["floor_cleared"], "CS: ボスがまだ残ってる")
	r.assert_eq(zako.hp, 0.0, "CS: 雑魚 HP=0")
	r.assert_eq(info1["delta"], 3.0, "CS: Δ=3.0")
	r.assert_eq(cs.world_time_delta_total, 3.0, "CS: Δ累積=3.0")

	var einfo := cs.enemy_turn()
	r.assert_eq(einfo["damage"], 5.0, "CS: Boss 攻撃力=5.0")
	r.assert_eq(p_c.hp, 95.0, "CS: Player HP 100→95")
	r.assert_eq(cs.state, CombatSystem.State.PLAYER_TURN, "CS: 敵ターン後は PLAYER_TURN")
	r.assert_eq(cs.turn_count, 2, "CS: turn=2 にインクリメント")

	var boss_kill := CastResult.new()
	boss_kill.grammar_report = GrammarReport.new()
	boss_kill.grammar_report.overall_pass = true
	boss_kill.effect_spec = EffectSpec.new()
	boss_kill.effect_spec.tier_sum = 2
	boss_kill.resolved = ResolvedEffect.new()
	boss_kill.resolved.effect_power = 25.0
	boss_kill.resolved.target_word_id = "fjandi"

	var info2 := cs.apply_cast(boss_kill, 2, 2)
	r.assert_true(info2["floor_cleared"], "CS: ボス撃破 → floor_cleared=true")
	r.assert_eq(cs.state, CombatSystem.State.FLOOR_CLEAR, "CS: FLOOR_CLEAR")
	r.assert_true(cs.is_over(), "CS: is_over=true")
	r.assert_eq(boss.hp, 0.0, "CS: ボス HP=0")

	var dead_cast_info := cs.apply_cast(kill_cast, 2, 2)
	r.assert_eq(dead_cast_info["to_target"], 0.0, "CS: 終了後 apply_cast は NOP")
	var dead_enemy_info := cs.enemy_turn()
	r.assert_eq(dead_enemy_info["damage"], 0.0, "CS: 終了後 enemy_turn は NOP")

	# 敗北フロー
	var cs2 := CombatSystem.new()
	var p2 := Combatant.new("P2", 5.0, {})
	var tough := Combatant.new("Tough", 1000.0, {})
	cs2.start_floor(p2, [tough], [10.0])
	var weak_cast := CastResult.new()
	weak_cast.grammar_report = GrammarReport.new()
	weak_cast.effect_spec = EffectSpec.new()
	weak_cast.resolved = ResolvedEffect.new()
	weak_cast.resolved.effect_power = 1.0
	weak_cast.resolved.target_word_id = "fjandi"
	cs2.apply_cast(weak_cast, 2, 2)
	cs2.enemy_turn()
	r.assert_eq(p2.hp, 0.0, "CS: Player HP=0")
	r.assert_eq(cs2.state, CombatSystem.State.DEFEAT, "CS: 敗北")
	r.assert_true(cs2.is_over(), "CS: 敗北で is_over=true")

	# snapshot
	var snap := cs.snapshot()
	r.assert_eq(snap["state"], CombatSystem.State.FLOOR_CLEAR, "snapshot: state")
	r.assert_eq(snap["enemies"].size(), 2, "snapshot: 敵 2 体")
	r.assert_eq(int(snap["enemies"][0]["hp"]), 0, "snapshot: 雑魚 HP=0")
	r.assert_eq(int(snap["enemies"][1]["hp"]), 0, "snapshot: ボス HP=0")

	# ============================================================================
	# INC-3 v0.9 新規: マス目移動・シームレス戦闘の最小縦切り検証
	# ============================================================================
	print("--- INC-3 v0.9: マス目移動・シームレス戦闘 ---")

	# INC-3.1: 範囲語・方向語 WordResource が読めて spatial フィールドが揃う
	var naer: WordResource = load("res://data/words/naer.tres") as WordResource
	r.assert_not_null(naer, "INC-3: naer.tres loads")
	if naer != null:
		r.assert_eq(naer.word_class, "range", "naer.word_class = range")
		r.assert_true(naer.spatial.has("kind"), "naer.spatial.kind exists")
		r.assert_eq(String(naer.spatial.get("kind", "")), "distance", "naer.spatial.kind = distance")

	var fram: WordResource = load("res://data/words/fram.tres") as WordResource
	r.assert_not_null(fram, "INC-3: fram.tres loads")
	if fram != null:
		r.assert_eq(fram.word_class, "direction", "fram.word_class = direction")
		var fp = fram.spatial.get("params", {})
		r.assert_eq(String(fp.get("axis", "")), "forward", "fram.spatial.params.axis = forward")

	var i_gegnum: WordResource = load("res://data/words/i_gegnum.tres") as WordResource
	r.assert_not_null(i_gegnum, "INC-3: i_gegnum.tres loads (line_pierce)")
	if i_gegnum != null:
		var ip = i_gegnum.spatial.get("params", {})
		r.assert_eq(String(ip.get("shape", "")), "line_pierce", "i_gegnum.spatial.params.shape = line_pierce")

	# range/direction バリデーション
	var bad := WordResource.new()
	bad.id = "bad_range"
	bad.word_class = "range"
	bad.gloss = {"ja": "x"}
	bad.tier = 1
	# spatial を空のまま validate → エラーが出るはず
	var errs := bad.validate()
	r.assert_true(errs.size() > 0, "range word without spatial → validation error")

	# INC-3.2: TileKind が読めて wall/floor/stairs_down/player_start が揃う
	var t_floor: TileKind = load("res://data/tiles/floor.tres") as TileKind
	var t_wall: TileKind = load("res://data/tiles/wall.tres") as TileKind
	var t_stairs: TileKind = load("res://data/tiles/stairs_down.tres") as TileKind
	var t_start: TileKind = load("res://data/tiles/player_start.tres") as TileKind
	r.assert_not_null(t_floor, "INC-3: floor.tres loads as TileKind")
	r.assert_not_null(t_wall, "INC-3: wall.tres loads")
	r.assert_not_null(t_stairs, "INC-3: stairs_down.tres loads")
	r.assert_not_null(t_start, "INC-3: player_start.tres loads")
	if t_wall != null:
		r.assert_false(t_wall.passable, "wall not passable")
		r.assert_true(t_wall.blocks_sight, "wall blocks sight")
	if t_stairs != null:
		r.assert_true(t_stairs.passable, "stairs_down passable")

	# INC-3.3: FloorTemplate と EnemyResource が読める
	var ft1: FloorTemplate = load("res://data/floors/helgrind_1.tres") as FloorTemplate
	r.assert_not_null(ft1, "INC-3: helgrind_1.tres loads")
	if ft1 != null:
		r.assert_eq(ft1.depth, 1, "helgrind_1.depth = 1")
		r.assert_eq(ft1.generation_method, "rooms_and_corridors", "helgrind_1.generation_method")
		r.assert_true(ft1.fixed_start_room, "helgrind_1.fixed_start_room = true (09 §2.5)")
		var ft1_errs := ft1.validate()
		r.assert_eq(ft1_errs.size(), 0, "helgrind_1 validates")

	var er_lesser: EnemyResource = load("res://data/enemies/draugr_lesser.tres") as EnemyResource
	r.assert_not_null(er_lesser, "INC-3: draugr_lesser.tres loads")
	if er_lesser != null:
		r.assert_eq(er_lesser.id, "draugr_lesser", "draugr_lesser.id")
		r.assert_eq(er_lesser.hp, 18, "draugr_lesser.hp = 18")
		r.assert_eq(er_lesser.sight_radius, 4, "draugr_lesser.sight_radius = 4 (09 §5.2)")

	# INC-3.4: DungeonGenerator がシード駆動で同一マップ生成（決定論性）
	var DSEED = preload("res://core/map/models/dungeon_seed.gd")
	var seed1 = DSEED.new(42, 0, 1)
	var seed2 = DSEED.new(42, 0, 1)
	var map_a = DungeonGenerator.generate(ft1, seed1)
	var map_b = DungeonGenerator.generate(ft1, seed2)
	r.assert_not_null(map_a, "INC-3: DungeonGenerator.generate() returns MapData")
	if map_a != null and map_b != null:
		r.assert_eq(map_a.size, map_b.size, "DungeonGenerator: 同seed → 同 size")
		r.assert_eq(map_a.rooms.size(), map_b.rooms.size(), "DungeonGenerator: 同seed → 同 room 数")
		# player_start_pos も決定論
		r.assert_eq(map_a.player_start_pos, map_b.player_start_pos, "DungeonGenerator: 同seed → 同 player_start_pos")
		# 起点部屋が左上 (2, 2) 付近（fixed_start_room=true）
		r.assert_true(map_a.player_start_pos.x >= 2 and map_a.player_start_pos.x < 15,
			"helgrind_1 起点部屋 x ∈ [2,15) (fixed_start_room)")
		# 階段配置済み
		r.assert_true(map_a.stairs_down_pos.x >= 0, "stairs_down_pos が配置されている")
		# 床が部屋数 × 部屋寸法分くらい存在する
		var floor_count := 0
		for y in range(map_a.size.y):
			for x in range(map_a.size.x):
				if map_a.get_tile(Vector2i(x, y)) == "floor":
					floor_count += 1
		r.assert_true(floor_count > 50, "DungeonGenerator: 床タイルが 50 個以上 (got %d)" % floor_count)

	# INC-3.5: 異なる seed なら異なるマップ
	var seed3 = DSEED.new(999, 0, 1)
	var map_c = DungeonGenerator.generate(ft1, seed3)
	if map_a != null and map_c != null:
		# 起点部屋は固定だが、他の部屋数や配置が異なるはず
		# (note: unused var was removed to avoid type infer issue)
		var all_same: bool = true
		if map_a.rooms.size() == map_c.rooms.size():
			for i in range(map_a.rooms.size()):
				var ra = map_a.rooms[i]
				var rc = map_c.rooms[i]
				if ra.x != rc.x or ra.y != rc.y:
					all_same = false
					break
		else:
			all_same = false
		r.assert_false(all_same, "DungeonGenerator: 異seed → 異マップ")

	# INC-3.6: Pathfinder が経路を返す（map_a で player_start から stairs まで）
	if map_a != null:
		var path = Pathfinder.find_path(map_a, map_a.player_start_pos, map_a.stairs_down_pos)
		r.assert_true(path.size() > 0, "Pathfinder: start → stairs に経路あり")
		if path.size() > 0:
			r.assert_eq(path[0], map_a.player_start_pos, "path[0] = start")
			r.assert_eq(path[path.size() - 1], map_a.stairs_down_pos, "path[-1] = stairs")
		var next = Pathfinder.next_step_towards(map_a, map_a.player_start_pos, map_a.stairs_down_pos)
		r.assert_true(next != map_a.player_start_pos, "next_step_towards: start から動く")

	# INC-3.7: MapState が load_floor で初期化される
	var ms := get_node("/root/MapState")
	r.assert_not_null(ms, "MapState autoload exists")
	if ms != null and ft1 != null:
		var seed_x = DSEED.new(123, 0, 1)
		ms.load_floor(ft1, seed_x)
		r.assert_not_null(ms.map_data, "MapState.map_data populated after load_floor")
		r.assert_true(ms.player_pos.x >= 0, "MapState.player_pos initialized")
		r.assert_eq(ms.player_facing, ms.FACING_NORTH, "MapState.player_facing = NORTH on load")
		r.assert_true(ms.fov_cache.size() > 0, "MapState.fov_cache populated")
		# 起点部屋付近は視界内
		r.assert_true(ms.is_visible(ms.player_pos), "player_pos is visible to self")

	# INC-3.8: MapState.reset() が状態をクリア
	if ms != null:
		ms.reset()
		r.assert_true(ms.map_data == null, "MapState.reset() clears map_data")
		r.assert_eq(ms.player_pos, Vector2i(-1, -1), "MapState.reset() clears player_pos")
		r.assert_eq(ms.fov_cache.size(), 0, "MapState.reset() clears fov_cache")

	# INC-3.9: 巻き戻しでマップ再生成（同じ seed_x で同じマップになる = 決定論）
	if ms != null and ft1 != null:
		var seed_y1 = DSEED.new(456, 0, 1)
		var seed_y2 = DSEED.new(456, 0, 1)
		ms.load_floor(ft1, seed_y1)
		var pos_a = ms.player_pos
		ms.reset()
		ms.load_floor(ft1, seed_y2)
		var pos_b = ms.player_pos
		r.assert_eq(pos_a, pos_b, "巻き戻し: 同 seed なら player_pos 同じ")

	# INC-3.10: 方向語の相対方向計算（プレイヤー向き基準）
	if ms != null and ft1 != null:
		ms.load_floor(ft1, DSEED.new(789, 0, 1))
		ms.player_facing = ms.FACING_NORTH
		r.assert_eq(ms.get_relative_direction_vector("forward"), Vector2i(0, -1), "fram (forward) when N = (0,-1)")
		r.assert_eq(ms.get_relative_direction_vector("right"),   Vector2i(1, 0),  "hoegri (right) when N = (1,0)")
		r.assert_eq(ms.get_relative_direction_vector("backward"),Vector2i(0, 1),  "aptr (backward) when N = (0,1)")
		r.assert_eq(ms.get_relative_direction_vector("left"),    Vector2i(-1, 0), "vinstri (left) when N = (-1,0)")
		ms.player_facing = ms.FACING_EAST
		r.assert_eq(ms.get_relative_direction_vector("forward"), Vector2i(1, 0),  "fram when E = (1,0)")
		r.assert_eq(ms.get_relative_direction_vector("left"),    Vector2i(0, -1), "vinstri when E = (0,-1) = N")

	# INC-3.11: SpatialContext.from_map_state() と nearest_enemy_in_sight
	if ms != null and ft1 != null:
		ms.load_floor(ft1, DSEED.new(2026, 0, 1))
		var ctx = SpatialContext.from_map_state(ms)
		r.assert_not_null(ctx, "SpatialContext.from_map_state() returns ctx")
		if ctx != null:
			r.assert_eq(ctx.player_pos, ms.player_pos, "ctx.player_pos = ms.player_pos")
			# 視界内に敵がいなければ nearest_enemy_in_sight は空
			# (helgrind_1 は敵が部屋内なので、起点部屋に居る限り視界内に敵がいる確率は低い)
			var ne = ctx.nearest_enemy_in_sight()
			r.assert_true(typeof(ne) == TYPE_DICTIONARY, "nearest_enemy_in_sight returns Dictionary")

	# INC-3.12: SpatialResolver の後方互換 (spatial_context=null → null を返す)
	var ts_null = SpatialResolver.resolve({"tokens": []}, null, null)
	r.assert_true(ts_null == null, "SpatialResolver: spatial_context=null → null (後方互換)")

	# INC-3.13: SpellEngine.cast() に spatial_context を渡せる (CastResult.target_set が populated)
	if ms != null and ft1 != null and ruleset != null:
		ms.load_floor(ft1, DSEED.new(2027, 0, 1))
		# 起点部屋付近に敵がいない可能性が高いので、ダミー敵を直挿入
		ms.map_data.enemies.append({
			"id": "draugr_lesser",
			"pos": ms.player_pos + Vector2i(1, 0),  # 隣接
			"hp": 18, "atk": 6, "max_hp": 18,
		})
		ms._recompute_fov()
		var ctx2 = SpatialContext.from_map_state(ms)
		var tokens_pos = [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var cast_pos: CastResult = engine.cast(tokens_pos, ruleset, {"spatial_context": ctx2})
		r.assert_not_null(cast_pos, "INC-3: cast with spatial_context returns CastResult")
		if cast_pos != null:
			r.assert_not_null(cast_pos.target_set, "CastResult.target_set populated when spatial_context given")
			if cast_pos.target_set != null:
				r.assert_true(cast_pos.target_set.reachable, "target_set.reachable = true (隣接敵あり)")
				r.assert_eq(cast_pos.target_set.target_tiles.size(), 1, "target_set.target_tiles 1 個 (最隣接敵)")

	# INC-3.14: GameState ループ管理
	GameState.reset()
	r.assert_eq(GameState.hp, GameState.PLAYER_MAX_HP, "GameState.reset() → HP MAX")
	r.assert_eq(GameState.floor_index, 1, "GameState.reset() → floor 1")
	r.assert_eq(GameState.world_time_remaining, GameState.LOOP_WORLD_TIME_BUDGET, "GameState.reset() → time MAX")
	var rewind_due := GameState.advance_world_time(50.0)
	r.assert_false(rewind_due, "GameState: 50 消費しても巻き戻しなし")
	r.assert_eq(GameState.world_time_remaining, 118.0, "GameState: 168-50 = 118")
	var rewind_now := GameState.advance_world_time(200.0)
	r.assert_true(rewind_now, "GameState: 大量消費で巻き戻し条件成立")
	r.assert_eq(GameState.world_time_remaining, 0.0, "GameState: 残量 0 でクランプ")

	GameState.reset()
	r.assert_eq(GameState.floor_index, 1, "GameState: reset 後 floor=1")
	GameState.descend_floor()
	GameState.descend_floor()
	r.assert_eq(GameState.floor_index, 3, "GameState: descend x2 → floor 3")

	# INC-3.15: 範囲語・方向語が minor finding にとどまる（02 v0.9 §3 INC-3 / 09 §8.1）
	# 仕様: INC-3 ではデータには載せるが Validator はコア違反扱いしない、SpatialResolver の
	#       advisory_findings に入る、grammar_report.overall_pass は維持される
	if ms != null and ft1 != null and ruleset != null:
		ms.load_floor(ft1, DSEED.new(3838, 0, 1))
		# 起点部屋付近に敵を直挿入
		ms.map_data.enemies.append({
			"id": "draugr_lesser",
			"pos": ms.player_pos + Vector2i(1, 0),
			"hp": 18, "atk": 6, "max_hp": 18,
		})
		ms._recompute_fov()
		var ctx3 = SpatialContext.from_map_state(ms)
		var tokens_dir = [
			{"word_id": "fram", "case": ""},      # 方向語
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var cast_dir: CastResult = engine.cast(tokens_dir, ruleset, {"spatial_context": ctx3})
		r.assert_not_null(cast_dir, "INC-3.15: fram + meiða fjanda 詠唱が結果を返す")
		if cast_dir != null:
			# Validator は方向語をコア違反扱いしない → overall_pass は格・語順だけで決まる
			r.assert_not_null(cast_dir.grammar_report, "INC-3.15: grammar_report populated")
			# fjandi の格は acc で OK、meiða(動詞)+fjanda(対格) で文法 OK のはず
			# 方向語の存在自体は Validator のコア違反にならない
			r.assert_true(cast_dir.grammar_report.overall_pass, "INC-3.15: 方向語付きでも overall_pass=true (minor finding にとどまる)")
			# SpatialResolver が方向語を認識して TargetSet に記録
			r.assert_not_null(cast_dir.target_set, "INC-3.15: target_set populated")
			if cast_dir.target_set != null:
				r.assert_eq(cast_dir.target_set.used_direction_word, "fram", "INC-3.15: target_set.used_direction_word = fram")

		# 範囲語 + 方向語の組み合わせ
		var tokens_range = [
			{"word_id": "naer", "case": ""},      # 範囲語
			{"word_id": "fram", "case": ""},      # 方向語
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var cast_range: CastResult = engine.cast(tokens_range, ruleset, {"spatial_context": ctx3})
		if cast_range != null and cast_range.target_set != null:
			r.assert_eq(cast_range.target_set.used_range_word, "naer", "INC-3.15: target_set.used_range_word = naer")
			r.assert_eq(cast_range.target_set.used_direction_word, "fram", "INC-3.15: target_set.used_direction_word = fram (組み合わせ)")
		if cast_range != null and cast_range.grammar_report != null:
			r.assert_true(cast_range.grammar_report.overall_pass, "INC-3.15: 範囲語+方向語でも overall_pass=true (INC-3 minor finding 暫定)")

		# 範囲語が複数（INC-3 では advisory_findings に range_conflict が入るが minor）
		var tokens_conflict = [
			{"word_id": "naer", "case": ""},
			{"word_id": "fjarri", "case": ""},
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var cast_conflict: CastResult = engine.cast(tokens_conflict, ruleset, {"spatial_context": ctx3})
		if cast_conflict != null and cast_conflict.target_set != null:
			r.assert_true(cast_conflict.target_set.advisory_findings.has("range_conflict"), "INC-3.15: nær+fjarri で range_conflict が advisory_findings に入る (minor)")
		if cast_conflict != null and cast_conflict.grammar_report != null:
			# range_conflict は advisory（INC-3 では Validator にも Resolver にも反映されない、minor）
			r.assert_true(cast_conflict.grammar_report.overall_pass, "INC-3.15: range_conflict があっても overall_pass=true (INC-3 暫定、INC-3.5 で重篤化予定)")

	# Cleanup
	if ms != null:
		ms.reset()
	GameState.reset()

	# --- INC-2 v0.4: SpellEngine → CombatSystem 統合 E2E テスト ---
	# Resolver の確率挙動・GrammarReport・Evaluator が戦闘層と正しく繋がっていることを
	# 固定 seed の連続詠唱で確認。phase_intermediate + C=100 + DAMAGE_SCALE=3.0 で
	# `meiða mikinn fjanda` を最大 10 ターン撃って雑魚 30 HP を倒せる、暴発ゼロ、を見る。
	# DAMAGE_SCALE を念のためデフォルト 3.0 にリセットしてから走らせる（前のテストで触られていないが防御）。
	var saved_scale: float = DamageCalculator.DAMAGE_SCALE
	DamageCalculator.DAMAGE_SCALE = 3.0

	var engine_e2e := get_node("/root/SpellEngine")
	var rs_inter_e2e: GrammarRuleset = load("res://data/grammar/phase_intermediate.tres") as GrammarRuleset
	r.assert_not_null(engine_e2e, "E2E: SpellEngine autoload")
	r.assert_not_null(rs_inter_e2e, "E2E: phase_intermediate ruleset")

	if engine_e2e != null and rs_inter_e2e != null:
		var cs_e2e := CombatSystem.new()
		var player_e2e := Combatant.new("Player", 100.0, {})
		var zako_e2e := Combatant.new("Zako", 30.0, {})
		cs_e2e.start_floor(player_e2e, [zako_e2e], [8.0])

		# `meiða mikinn fjanda` (V 修飾 名詞・正準語順)
		var tokens_e2e: Array = [
			{"word_id": "meida",  "case": ""},
			{"word_id": "mikill", "case": "acc"},
			{"word_id": "fjandi", "case": "acc"},
		]

		var max_turns: int = 10
		var actual_turns: int = 0
		var misfire_count_e2e: int = 0
		var cast_seed: int = 1000
		for t in max_turns:
			if cs_e2e.is_over():
				break
			var cr: CastResult = engine_e2e.cast(tokens_e2e, rs_inter_e2e, {"c_override": 100.0, "rng_seed": cast_seed + t})
			if cr == null:
				break
			if cr.resolved != null and cr.resolved.misfired:
				misfire_count_e2e += 1
			cs_e2e.apply_cast(cr, tokens_e2e.size(), cr.effect_spec.tier_sum)
			actual_turns += 1
			if cs_e2e.is_over():
				break
			cs_e2e.enemy_turn()

		# 雑魚は 5 ターン以内に死ぬはず（DAMAGE_SCALE=3.0, mikill 修飾語 ×1.5 で P_base ~ 3.45、
		# C=100 + G=1.0 で variance=0 → 確定 3.45 × 3.0 = 10.35 ダメージ/ターン → 3 ターンで 31 ダメ）
		r.assert_eq(zako_e2e.hp, 0.0, "E2E: 雑魚撃破")
		r.assert_true(cs_e2e.is_over(), "E2E: 戦闘終了")
		r.assert_true(actual_turns <= 5, "E2E: 5 ターン以内に撃破 (実測 %d)" % actual_turns)
		# C=100 達人不変条件 (T6) は戦闘層でも保たれる: 暴発ゼロ
		r.assert_eq(misfire_count_e2e, 0, "E2E: C=100 で暴発ゼロ (達人不変・戦闘層版)")
		# Player は雑魚反撃を 4 回受けても HP > 60 で生存しているはず
		r.assert_true(player_e2e.hp > 60.0, "E2E: Player HP > 60 残し (got %.1f)" % player_e2e.hp)

		# DAMAGE_SCALE を直接書き換えた場合の反映確認
		DamageCalculator.DAMAGE_SCALE = 1.0
		var weak_resolved := ResolvedEffect.new()
		weak_resolved.effect_power = 10.0
		weak_resolved.target_word_id = "fjandi"
		var weak_target := Combatant.new("T", 100.0, {})
		var calc_scale1 := DamageCalculator.compute(weak_resolved, weak_target, {})
		r.assert_eq(calc_scale1["to_target"], 10.0, "E2E: DAMAGE_SCALE=1.0 で素通し")
		DamageCalculator.DAMAGE_SCALE = 5.0
		var calc_scale5 := DamageCalculator.compute(weak_resolved, weak_target, {})
		r.assert_eq(calc_scale5["to_target"], 50.0, "E2E: DAMAGE_SCALE=5.0 で 10 → 50")

	# 後片付け
	DamageCalculator.DAMAGE_SCALE = saved_scale

	r.print_summary()

	# 自動終了（CLI からの実行も想定）。エディタで F5 した場合は手動で閉じる。
	# get_tree().quit() を呼ぶとエディタ実行が即終了するので INC-0 は呼ばない。
