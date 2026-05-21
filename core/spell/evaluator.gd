extends RefCounted
class_name SpellEvaluator
## SpellEvaluator — 評価フェーズ。AST → EffectSpec（制御精度適用前）。
##
## 役割: 期待威力 P_base（=Σtier ＋ 語順ボーナス）と効果種別を出す（03 §5.1）。
## 出典: 03 §5.1 / 04 §4。
##
## INC-0: 空シェル。tier 合算・語順ボーナスは INC-1 で。

## AST と語辞書アクセサから EffectSpec を返す。
##   ast: SpellParser.parse() の出力
##   word_lookup: Callable または Object — INC-1 で型を確定（id → WordResource を引く I/F）
##   ruleset: GrammarRuleset（word_order_bonus 等の係数取得）
static func evaluate(_ast: Dictionary, _word_lookup = null, _ruleset: Resource = null) -> EffectSpec:
	var spec := EffectSpec.new()
	# INC-0: 全フィールド既定値のまま返す。
	return spec
