extends RefCounted
class_name SpellEvaluator
## SpellEvaluator — 評価フェーズ。AST → EffectSpec（制御精度適用前）。
##
## 役割: 期待威力 P_base（=Σtier ＋ 語順ボーナス）と効果種別を出す（03 §5.1）。
##       理解度は P_base に**寄与しない**（§1-1, T1）。理解度の作用は Resolver 側。
## 出典: 03 §5.1, §1, 附録A / 04 §4。
##
## INC-1: tier 合算・効果種別・対象語の確定まで。
##        修飾語効果の P_base 乗算 (v0.13, mikill=1.5/litill=0.7)。
##        属性合成の混沌判定 (v0.13, 4 元素全部で modifiers["chaos"]=true)。

## 修飾語ごとの効果倍率（v0.13）。INC-2 で BalanceConfig.modifier.power_factor へ。
const MODIFIER_FACTOR_BY_ID: Dictionary = {
	"mikill": 1.5,  # 大いに → 威力＋
	"litill": 0.7,  # 小さく → 威力−
}

## 四大元素の ID（混沌判定用）。
const FOUR_ELEMENTS: Array = ["eldr", "vatn", "vindr", "jorth"]

## AST と Ruleset から EffectSpec を返す。
##   ast: SpellParser.parse() の出力
##   _word_lookup: 未使用（AST 内の token.resource を直接参照する）
##   ruleset: GrammarRuleset（word_order_bonus_weight 等の係数取得）
static func evaluate(ast: Dictionary, _word_lookup = null, ruleset: Resource = null) -> EffectSpec:
	var spec := EffectSpec.new()

	var effect = ast.get("effect", null)
	var target = ast.get("target", null)
	var elements: Array = ast.get("elements", [])

	# tier_sum: 効果語＋対象語＋属性語の tier 合算。03 §5.1。
	var tier_sum: int = 0
	if effect != null:
		var e_res: WordResource = effect.get("resource", null)
		if e_res != null:
			tier_sum += e_res.tier
	if target != null:
		var t_res: WordResource = target.get("resource", null)
		if t_res != null:
			tier_sum += t_res.tier
	for el in elements:
		var el_res: WordResource = el.get("resource", null)
		if el_res != null:
			tier_sum += el_res.tier
	spec.tier_sum = tier_sum

	# 語順ボーナス（正準語順なら +、§3.2/§5.4）。
	# 判定: 効果語と対象語が両方 AST にあり、word_order で effect が target より前 → ボーナス適用。
	var bonus_weight: float = 0.0
	if ruleset != null and ruleset.has_method("get_word_order_bonus_weight"):
		bonus_weight = ruleset.get_word_order_bonus_weight()
	var canonical: bool = _is_canonical_order(ast)
	var bonus: float = float(tier_sum) * bonus_weight if canonical else 0.0

	# 効果語がない場合は P_base = 0（増幅対象がない、v0.13）。
	# tier_sum や bonus は計算上保持するが、最終的な P_base は 0 で確定。
	var modifiers: Array = ast.get("modifiers", [])
	if effect == null:
		spec.p_base = 0.0
	else:
		# 修飾語の倍率を P_base に乗算（v0.13, mikill=1.5/litill=0.7）。
		var modifier_factor: float = 1.0
		for m in modifiers:
			var m_res: WordResource = m.get("resource", null)
			if m_res != null:
				modifier_factor *= float(MODIFIER_FACTOR_BY_ID.get(m_res.id, 1.0))
		spec.p_base = (float(tier_sum) + bonus) * modifier_factor

	# 効果種別: 効果語の governs_case と意味で簡易マッピング。INC-2 で附録A 効果語クラスから取得へ。
	spec.kind = _infer_kind(effect)

	# 対象語 ID（acc 等で参照された語）。
	if target != null:
		spec.target_word_id = String(target.get("word_id", ""))

	# 元素属性 ID（先頭の element を採用）。
	if elements.size() > 0:
		var first_el: WordResource = elements[0].get("resource", null)
		if first_el != null:
			spec.element_word_id = first_el.id

	# modifiers 辞書: 混沌判定など Evaluator 側のメタ情報を載せる。
	spec.modifiers = {}
	# 四大元素 4 つ全部なら chaos=true（v0.13、戦闘層が解釈）。
	var four_used: Array = []
	for el in elements:
		var el_res: WordResource = el.get("resource", null)
		if el_res != null and (el_res.id in FOUR_ELEMENTS) and not (el_res.id in four_used):
			four_used.append(el_res.id)
	if four_used.size() == FOUR_ELEMENTS.size():
		spec.modifiers["chaos"] = true

	return spec


## 正準語順か（effect が target より前にあるか）。
static func _is_canonical_order(ast: Dictionary) -> bool:
	var order: Array = ast.get("word_order", [])
	var e_idx := order.find("effect")
	var t_idx := order.find("target")
	if e_idx == -1 or t_idx == -1:
		return false
	return e_idx < t_idx


## 効果種別の簡易推論。INC-2 で word_id ベースのテーブルに差し替え予定。
static func _infer_kind(effect) -> String:
	if effect == null:
		return "none"
	var res: WordResource = effect.get("resource", null)
	if res == null:
		return "none"
	# INC-1 範囲の効果語（meida/verja/lakna/thverra）を最低限マップ。
	match res.id:
		"meida": return "damage"
		"verja": return "buff"
		"lakna": return "heal"
		"thverra": return "debuff"
		_:
			# governs_case=acc は概ね対象に作用する系 → damage 既定（暫定）。
			if res.governs_case == "acc":
				return "damage"
			return "none"
