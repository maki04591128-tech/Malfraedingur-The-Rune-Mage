extends RefCounted
class_name SpellResolver
## SpellResolver — 制御精度の適用＝最終効果の確定。
##
## 役割: 暴発確率 p = clamp(Σ(mult_i × base), 0, 1) を引いて、
##       重篤度バンド（≤30 / 31..60 / 61..99 / =100）でカテゴリ決定。
##       variance/jitter を成功時に乗せる（03 §5.2/5.3/5.4・v0.11）。
## 出典: 03 §5.2・§5.3・§5.4 (v0.11) / 04 §4。
##
## INC-1: 暴発判定＋成功時 variance（randNormal）まで実装。
##        対象ズレ（target_jitter）の戦闘適用は INC-2 で。
##        暴発確率の合算は v0.11 で文法込みに（base × Σmult）。重篤度カテゴリは依然 C のみ。


## 文法違反ごとの暴発確率倍率（03 §5.2 v0.11 / v0.13 拡張 / v0.17 でチューニング可能化）。
## INC-2 で BalanceConfig.misfire.mult_by_rule へ外出し予定。
## v0.17: spell_builder のチューニングパネルから書き換え可能にするため static var に。
static var MISFIRE_MULT_BY_RULE: Dictionary = {
	"case_agreement":      2.0,
	"unknown_word":        4.0,   # 無辞書経路のみ。タイル経路では発生しない
	"word_order":          6.0,
	"elements":            1.5,   # v0.13: 半端な属性合成は不発
	"modifier":            1.5,   # v0.13: 修飾語単独詠唱の構文エラー（最小）
	"modifier_agreement":  2.0,   # v0.14: 修飾語の性・数・格不一致（古ノルド語の正確な活用）
	# === INC-3.5 v0.9.5 新規（03 §3.3 v0.18 / 09 §7.3）===
	"range_required":      2.0,   # 射程外 — SpatialResolver が finding を立てる
	"range_conflict":      3.0,   # 範囲語が複数（nær×fjarri など） — Validator が立てる
	"direction_required":  2.0,   # 形状系範囲語に方向指定なし — Validator が立てる
}

## tier 別の variance 上限（暫定値・INC-2 で BalanceConfig 化、v0.17 でチューニング可能化）。
## V_max が大きいほど成功時のゆらぎが大きい（不安定）。
static var V_MAX_BY_TIER: Dictionary = {
	1: 0.15,
	2: 0.20,
	3: 0.30,
}

## tier 別の target_jitter 上限（INC-1 は数値計算だけ、戦闘適用は INC-2）。
const J_MAX_BY_TIER := {
	1: 0.10,
	2: 0.15,
	3: 0.25,
}


## EffectSpec と理解度 C・文法スコア G・seed を受けて、最終 ResolvedEffect を返す。
##   spec: SpellEvaluator.evaluate() の出力
##   c_weighted: 使用語の理解度加重平均（0..100）
##   g_score: 文法スコア G（0.0..1.0）。variance/Control 用。
##   rng_seed: 再現性のための seed（0 は「ランダム＝現在時刻ベース」）
##   report: GrammarReport（暴発確率の合算用、v0.11）。null なら違反ゼロ扱い。
static func resolve(spec: EffectSpec, c_weighted: float, g_score: float, rng_seed: int, report: GrammarReport = null) -> ResolvedEffect:
	var out := ResolvedEffect.new()
	if spec == null:
		return out

	out.target_word_id = spec.target_word_id

	# RNG セットアップ。seed=0 はランダム。
	var rng := RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed

	# 暴発判定（理解度＋文法の合算・03 §5.2 v0.11）。
	var p_misfire: float = compute_misfire_chance(c_weighted, report)
	var rolled: float = rng.randf()
	var misfired: bool = rolled < p_misfire

	if misfired:
		out.misfired = true
		out.misfire_category = band_for(c_weighted)
		out.misfire_outcome = _pick_misfire_outcome(out.misfire_category, rng)
		_apply_misfire(out, spec, out.misfire_category, out.misfire_outcome, rng)
		return out

	# 成功時: Control から variance を出して effect_power に乗算（03 §5.4 v0.12）。
	# v0.12 改訂: effect_power = P_base × g_mult(G) × randNormal(1.0, variance)
	# g_mult は文法スコアの線形乗算（C 不問で文法違反は決定的に威力を下げる）。
	var control: float = clampf(0.6 * (c_weighted / 100.0) + 0.4 * g_score, 0.0, 1.0)
	var v_max: float = _v_max_for_tier(_dominant_tier(spec))
	var variance: float = (1.0 - control) * v_max
	var multiplier: float = rng.randfn(1.0, variance) if variance > 0.0 else 1.0
	multiplier = maxf(multiplier, 0.0)  # 負方向にぶれて 0 未満になるのを防ぐ
	var g_mult: float = clampf(g_score, 0.0, 1.0)  # v0.12: 文法スコア線形乗算

	out.effect_power = spec.p_base * g_mult * multiplier
	out.variance_mult = multiplier
	out.misfired = false
	out.misfire_category = ""
	out.misfire_outcome = ""
	out.self_damage = 0.0
	return out


## 暴発確率の計算（03 §5.2 v0.11）。理解度＋文法の合算。
##   c_weighted: 加重平均理解度（0..100）
##   report: GrammarReport（null/失敗ゼロなら base のみ）
## 返り値:
##   違反ゼロ → base = clamp(0.10 - 0.001*C, 0, 0.10)
##   違反あり → clamp(Σ(mult_i * base), 0, 1)
##   C=100 → base=0 のため、文法違反があっても 0（達人不変条件）
static func compute_misfire_chance(c_weighted: float, report: GrammarReport = null) -> float:
	var base: float = clampf(0.10 - 0.001 * c_weighted, 0.0, 0.10)
	if report == null:
		return base
	var fails := report.failures()
	if fails.is_empty():
		return base
	var total_mult: float = 0.0
	for f in fails:
		var rule: String = String(f.get("rule", ""))
		total_mult += float(MISFIRE_MULT_BY_RULE.get(rule, 0.0))
	if total_mult <= 0.0:
		# 既知ルール外の違反は確率に乗らない（仕様: テーブル外は寄与 0）。
		return base
	return clampf(total_mult * base, 0.0, 1.0)


## 旧 API 互換のオーバーロード相当: report を null で呼んだのと同じ。
## test_smoke 等の既存呼び出し（c のみ）を壊さないため、引数 1 つの呼び出しも当然動作する
## （GDScript ではデフォルト引数で対応済み、本コメントは説明用）。


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


# --- 暴発内訳の決定 ---

## バンドごとの代表的アウトカム（03 §5.3 表）。INC-2 で BalanceConfig.misfire.catalog 化。
static func _pick_misfire_outcome(category: String, rng: RandomNumberGenerator) -> String:
	match category:
		"activation":
			return "fizzle" if rng.randf() < 0.5 else "collapse"
		"execution":
			var r := rng.randf()
			if r < 0.34:
				return "target_shift"
			elif r < 0.67:
				return "power_drop"
			else:
				return "halve_or_misrange"
		"control":
			var r2 := rng.randf()
			if r2 < 0.5:
				return "self_damage"
			elif r2 < 0.8:
				return "effect_reversal"
			else:
				return "recoil"
		_:
			return ""


## 暴発カテゴリ別の数値適用。effect_power / self_damage / target_word_id を書き換える。
static func _apply_misfire(
	out: ResolvedEffect,
	spec: EffectSpec,
	category: String,
	outcome: String,
	rng: RandomNumberGenerator
) -> void:
	match category:
		"activation":
			# 不発: 効果ゼロ、軽い体勢崩しのみ（戦闘適用は INC-2）。
			out.effect_power = 0.0
		"execution":
			# 実行失敗: 威力 30〜70%、または対象ズレ。
			match outcome:
				"power_drop":
					out.effect_power = spec.p_base * rng.randf_range(0.3, 0.7)
				"target_shift":
					out.effect_power = spec.p_base * rng.randf_range(0.6, 0.9)
					out.target_word_id = ""  # 別対象/無方向（戦闘層が解釈）
				"halve_or_misrange":
					out.effect_power = spec.p_base * 0.5
				_:
					out.effect_power = spec.p_base * 0.5
		"control":
			# 制御失敗: 自爆 or 反転。
			match outcome:
				"self_damage":
					out.effect_power = 0.0
					out.self_damage = float(spec.tier_sum) * 1.0
				"effect_reversal":
					out.effect_power = -spec.p_base  # 反転（戦闘層が符号解釈）
				"recoil":
					out.effect_power = spec.p_base * 0.6
					out.self_damage = float(spec.tier_sum) * 0.4
				_:
					out.self_damage = float(spec.tier_sum) * 0.5
		_:
			pass


# --- variance テーブル ---

static func _dominant_tier(spec: EffectSpec) -> int:
	# 単純化: tier_sum を tier 数（仮に2語）で割って平均にする雑な代理。
	# 厳密には effect/target の tier 平均だが、INC-1 では tier_sum 自体が小さい範囲なので近似で十分。
	if spec == null or spec.tier_sum <= 1:
		return 1
	if spec.tier_sum <= 3:
		return 1
	if spec.tier_sum <= 5:
		return 2
	return 3


static func _v_max_for_tier(tier: int) -> float:
	return float(V_MAX_BY_TIER.get(tier, 0.20))


static func _j_max_for_tier(tier: int) -> float:
	return float(J_MAX_BY_TIER.get(tier, 0.15))
