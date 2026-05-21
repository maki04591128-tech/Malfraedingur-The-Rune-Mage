extends RefCounted
class_name SpellResolver
## SpellResolver — 制御精度の適用＝最終効果の確定。
##
## 役割: 暴発確率 p = clamp(0.10 - 0.001*C, 0, 0.10) を引いて、
##       重篤度バンド（≤30 / 31..60 / 61..99 / =100）でカテゴリ決定。
##       variance/jitter を成功時に乗せる（03 §5.2/5.3）。
## 出典: 03 §5.2・§5.3 / 04 §4。
##
## INC-0: 空シェル。乱数 seed 固定・暴発判定は INC-1 で。

## EffectSpec と理解度 C・文法スコア G・seed を受けて、最終 ResolvedEffect を返す。
##   spec: SpellEvaluator.evaluate() の出力
##   c_weighted: 使用語の理解度加重平均（0..100）
##   g_score: 文法スコア G（0.0..1.0）
##   rng_seed: 再現性のための seed（テスト/ローグライク）
static func resolve(spec: EffectSpec, _c_weighted: float, _g_score: float, _rng_seed: int) -> ResolvedEffect:
	var out := ResolvedEffect.new()
	# INC-0: spec の値をそのまま素通し（暴発なし）。
	if spec != null:
		out.effect_power = spec.p_base
		out.target_word_id = spec.target_word_id
	out.misfired = false
	out.misfire_category = ""
	out.misfire_outcome = ""
	out.self_damage = 0.0
	out.variance_mult = 1.0
	return out


## 暴発確率の計算（03 §5.2 確定式）。C のみ依存。
##   c_weighted: 加重平均理解度（0..100）
## 返り値: 0.0..0.10
static func compute_misfire_chance(c_weighted: float) -> float:
	return clampf(0.10 - 0.001 * c_weighted, 0.0, 0.10)


## C に対応する重篤度バンドのカテゴリ名（03 §5.3）。
##   c_weighted: 加重平均理解度
## 返り値: "activation" | "execution" | "control" | "none"
static func band_for(c_weighted: float) -> String:
	if c_weighted >= 100.0:
		return "none"
	if c_weighted >= 61.0:
		return "control"
	if c_weighted >= 31.0:
		return "execution"
	return "activation"
