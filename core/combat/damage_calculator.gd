extends RefCounted
class_name DamageCalculator
## DamageCalculator — ResolvedEffect を戦闘ダメージに変換する純関数群。
##
## 役割: SpellResolver の出力 (`effect_power` / `self_damage` / 暴発カテゴリ)
##       と対象 Combatant の耐性から、敵への被ダメ・自分への被ダメを確定する。
## 出典: 08 §1.3 / 03 §5.3 / `core/spell/resolver.gd` の `_apply_misfire`。
##
## 不変条件:
##   - 副作用ゼロ。Combatant.take_damage() は呼び出し側 (CombatSystem) が叩く。
##   - effect_power が負（effect_reversal 等）の場合は「敵が回復する」と解釈し
##     戻り値の to_target に負値を返す。CombatSystem は abs を heal() に回す。
##   - target_word_id == "sjalfr" は self-target 判定で to_target=0, to_self に流す。
##   - 暴発の self_damage は to_self に加算。

## ダメージスケール定数（INC-2 v0.2 で追加）。
## 実機検証で「P_base ~ 2.3 のダメージ vs 敵 HP 30 / Player HP 100」が釣り合わず、
## 雑魚撃破まで 13+ ターン要する一方 Player は 12 ターンで死ぬ問題が判明。
## DAMAGE_SCALE で全戦闘ダメージを底上げし、3〜5 ターンで雑魚を倒せる強度に揃える。
## INC-3 で BalanceConfig.damage_scale として外出し予定（現状は const）。
const DAMAGE_SCALE: float = 3.0

## 1詠唱あたりの世界時間 Δ の暫定計算式。
## INC-3 で BalanceConfig.world_time_costs に外出し。
## 現状: 語数 × 1.0 + tier_sum × 0.5。
static func compute_world_time_delta(token_count: int, tier_sum: int) -> float:
	return float(token_count) * 1.0 + float(tier_sum) * 0.5


## 主要 API: 呪文結果から最終ダメージを計算する。
##   resolved: SpellResolver.resolve() の戻り値（ResolvedEffect）
##   target:   現在敵（自爆/自己対象時は player を渡しても可）
##   options:  { "dominant_element": String, "self_target_id": String } — INC-2 v0.1 では未使用
## 戻り値:
##   {
##     "to_target": float,           # 敵への与ダメ（負なら回復、CombatSystem 側で解釈）
##     "to_self": float,             # 自分への被ダメ
##     "is_self_target": bool,       # target_word_id == "sjalfr"
##     "log_summary": String,        # 1 行ログ
##   }
static func compute(resolved: ResolvedEffect, target: Combatant, options: Dictionary = {}) -> Dictionary:
	var out := {
		"to_target": 0.0,
		"to_self": 0.0,
		"is_self_target": false,
		"log_summary": "",
	}
	if resolved == null:
		out["log_summary"] = "(no result)"
		return out

	# 自己対象 (sjalfr): 効果を自分に流す。
	if resolved.target_word_id == "sjalfr":
		out["is_self_target"] = true
		# effect_power > 0 で「自分を傷つける」、< 0 で「自分を癒す」
		# INC-2 v0.1 は self-target は誤詠唱扱いとし、to_self に正値で渡す
		out["to_self"] = maxf(resolved.effect_power, 0.0) + resolved.self_damage
		out["log_summary"] = "(対象=自分) → 自身に %.1f" % out["to_self"]
		return out

	# 通常: target に effect_power を、self に self_damage を。
	var elem: String = String(options.get("dominant_element", ""))
	var resist: float = 1.0
	if target != null:
		resist = target.resist_mult_for(elem)

	# effect_power が負 → 反転 (effect_reversal)。CombatSystem 側で heal 解釈。
	# v0.2: DAMAGE_SCALE で全ダメージを底上げ（雑魚を 3〜5 ターンで倒せる強度に）。
	out["to_target"] = resolved.effect_power * resist * DAMAGE_SCALE
	out["to_self"] = resolved.self_damage * DAMAGE_SCALE

	if resolved.misfired:
		out["log_summary"] = "暴発(%s/%s) → 敵 %.1f / 自分 %.1f" % [
			resolved.misfire_category, resolved.misfire_outcome,
			out["to_target"], out["to_self"]
		]
	else:
		out["log_summary"] = "命中 → 敵 %.1f" % out["to_target"]
	return out
