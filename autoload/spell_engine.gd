extends Node
## SpellEngine — 呪文パイプライン Facade（Autoload）。
## API: cast(tokens_in: Array, ruleset: Resource) -> CastResult
## パイプライン: Tokenizer → Parser → Validator → Evaluator → Resolver（04 §4）。
## 物語固定詠唱 `öld renna aptr`（巻き戻し）は本 API を通さない（04 §4 末尾）。
##
## INC-0: 縦の骨だけ通す。各段はシェルで空回りし、CastResult を返すだけ。
##         実ロジックは INC-1 で順次充足。
##
## 不変条件:
##   - この autoload は他の autoload を **class スコープで参照しない**
##     （Godot 4 の autoload parse 順序問題を避けるため）。
##     他 autoload が必要なときは関数ローカルで get_node("/root/Name") で取る。
##   - 巻き戻し詠唱 `öld renna aptr` は本 API を通さない（GameState 直叩きの固定イベント）。


## 呪文1詠唱を解決して CastResult を返す。
##   tokens_in: SpellComposer が出した {word_id, case} 列、または無辞書経路の正規化済み列
##   ruleset: GrammarRuleset（可用性ゲート＋scaffold_level＋severity_weights）
## 戻り値: 4子モデル全てが populated な CastResult（INC-0 は空シェル相当の値）。
func cast(tokens_in: Array, ruleset: Resource) -> CastResult:
	# 縦の骨を順に呼ぶ。各段の出力が次段の入力。
	var tokens: Array = SpellTokenizer.tokenize(tokens_in, ruleset)
	var ast: Dictionary = SpellParser.parse(tokens)
	var grammar_report: GrammarReport = SpellValidator.validate(ast, ruleset)
	var effect_spec: EffectSpec = SpellEvaluator.evaluate(ast, null, ruleset)

	# 制御精度の入力（INC-1 で Lexicon から実値を取って計算）。
	var c_weighted: float = 0.0
	var g_score: float = 0.0
	if grammar_report != null:
		g_score = grammar_report.g_score
	var rng_seed: int = 0

	var resolved: ResolvedEffect = SpellResolver.resolve(effect_spec, c_weighted, g_score, rng_seed)

	var result := CastResult.new()
	result.grammar_report = grammar_report
	result.effect_spec = effect_spec
	result.resolved = resolved
	result.debug = {
		"C": c_weighted,
		"G": g_score,
		"misfire_chance": SpellResolver.compute_misfire_chance(c_weighted),
		"band": SpellResolver.band_for(c_weighted),
		"seed": rng_seed,
	}
	return result


## 物語固定詠唱の入口。コア API を通さないので別関数。
## 実装は INC-3（巻き戻し導入）で GameState.reset() を呼ぶ形に。
func incant_rewind() -> void:
	# INC-3 で実装。ここを通る詠唱はパイプラインを完全にバイパスする。
	pass
