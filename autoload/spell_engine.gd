extends Node
## SpellEngine — 呪文パイプライン Facade（Autoload）。
## API: cast(tokens_in: Array, ruleset: Resource, options: Dictionary = {}) -> CastResult
## パイプライン: Tokenizer → Parser → Validator → Evaluator → Resolver（04 §4）。
## 物語固定詠唱 `öld renna aptr`（巻き戻し）は本 API を通さない（04 §4 末尾）。
##
## INC-1: 各段に実装が入った。spell_lab が `cast()` を直接叩いて S1 を可視化する。
##
## 不変条件:
##   - この autoload は他の autoload を **class スコープで参照しない**
##     （Godot 4 の autoload parse 順序問題を避けるため）。
##     他 autoload が必要なときは関数ローカルで get_node("/root/Name") で取る。
##   - 巻き戻し詠唱 `öld renna aptr` は本 API を通さない（GameState 直叩きの固定イベント）。


## 呪文1詠唱を解決して CastResult を返す。
##   tokens_in: SpellComposer が出した {word_id, case} 列、または無辞書経路の正規化済み列
##   ruleset: GrammarRuleset（可用性ゲート＋scaffold_level＋severity_weights）
##   options: 任意の上書き。
##            {
##              "c_override":     float (0..100) — 指定すれば C を上書き（spell_lab スライダ用）
##              "rng_seed":       int            — Resolver の seed 固定。0 はランダム
##              "spatial_context": SpatialContext or null — INC-3 v0.9 新規。位置あり詠唱の元データ
##            }
## 戻り値: 4子モデル全てが populated な CastResult。
func cast(tokens_in: Array, ruleset: Resource, options: Dictionary = {}) -> CastResult:
	# 他 autoload は関数ローカルで参照（class スコープ参照禁止の不変条件）。
	var lexicon := get_node_or_null("/root/Lexicon")
	var word_lookup := Callable()
	if lexicon != null and lexicon.has_method("get_word"):
		word_lookup = Callable(lexicon, "get_word")

	# Tokenizer → Parser
	var tokens: Array = SpellTokenizer.tokenize(tokens_in, ruleset, word_lookup)
	var ast: Dictionary = SpellParser.parse(tokens)

	# Validator → GrammarReport / G
	var grammar_report: GrammarReport = SpellValidator.validate(ast, ruleset)

	# Evaluator → EffectSpec / P_base
	var effect_spec: EffectSpec = SpellEvaluator.evaluate(ast, word_lookup, ruleset)

	# SpatialResolver → TargetSet (INC-3 v0.9 新規、09 §7.4)
	# spatial_context が null なら null を返し後方互換維持
	var spatial_context = options.get("spatial_context", null)
	var target_set: TargetSet = SpatialResolver.resolve(ast, spatial_context, ruleset)

	# INC-3.5 v0.9.5: SpatialResolver の core_findings を grammar_report.findings にマージし、
	# overall_pass / g_score を再計算（range_required は座標が要るのでここで合流）。
	if target_set != null and grammar_report != null and target_set.core_findings.size() > 0:
		for f in target_set.core_findings:
			grammar_report.findings.append(f)
		SpellValidator.recompute_after_merge(grammar_report, ruleset)

	# C: options.c_override > 使用語の comprehension 加重平均（Lexicon 経由）
	var c_weighted: float = 0.0
	if options.has("c_override"):
		c_weighted = clampf(float(options["c_override"]), 0.0, 100.0)
	else:
		c_weighted = _average_comprehension(tokens, lexicon)

	var g_score: float = grammar_report.g_score if grammar_report != null else 0.0
	var rng_seed: int = int(options.get("rng_seed", 0))

	# Resolver → ResolvedEffect（v0.11: report を渡して暴発確率に文法を合流）
	var resolved: ResolvedEffect = SpellResolver.resolve(effect_spec, c_weighted, g_score, rng_seed, grammar_report)

	# CastResult 組み立て
	var result := CastResult.new()
	result.grammar_report = grammar_report
	result.effect_spec = effect_spec
	result.resolved = resolved
	result.target_set = target_set
	result.debug = {
		"C": c_weighted,
		"G": g_score,
		"control": clampf(0.6 * (c_weighted / 100.0) + 0.4 * g_score, 0.0, 1.0),
		"p_base": effect_spec.p_base if effect_spec != null else 0.0,
		"tier_sum": effect_spec.tier_sum if effect_spec != null else 0,
		# v0.11: misfire_chance は文法込みの実値。base のみは misfire_base に別途。
		"misfire_chance": SpellResolver.compute_misfire_chance(c_weighted, grammar_report),
		"misfire_base": SpellResolver.compute_misfire_chance(c_weighted),
		# v0.12: 成功時威力ペナルティ g_mult = G（spell_lab 表示用）
		"g_mult": clampf(g_score, 0.0, 1.0),
		"band": SpellResolver.band_for(c_weighted),
		"seed": rng_seed,
	}
	return result


## 物語固定詠唱の入口。コア API を通さないので別関数。
## 実装は INC-3（巻き戻し導入）で GameState.reset() を呼ぶ形に。
func incant_rewind() -> void:
	# INC-3 で実装。ここを通る詠唱はパイプラインを完全にバイパスする。
	pass


## 使用語の理解度加重平均（03 §5.1 weakest-link tunable は INC-1 では単純平均で代用）。
##   tokens: Tokenizer の出力
##   lexicon: /root/Lexicon ノード（null 可）
## 返り値: 0..100。語が無ければ 0。
func _average_comprehension(tokens: Array, lexicon) -> float:
	if lexicon == null or not lexicon.has_method("get_comprehension"):
		return 0.0
	var total: int = 0
	var count: int = 0
	for tok in tokens:
		var word_id: String = String(tok.get("word_id", ""))
		if word_id.is_empty():
			continue
		total += int(lexicon.get_comprehension(word_id))
		count += 1
	if count == 0:
		return 0.0
	return float(total) / float(count)
