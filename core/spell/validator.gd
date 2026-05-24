extends RefCounted
class_name SpellValidator
## SpellValidator — 文法判定（格一致・語順・可用性）→ GrammarReport。
##
## 役割: 03 §5.4 の文法スコア G の元データを作る。
##       Validator は ruleset.scaffold_level に**不関与**（D3: 補助型／UI のみ）。
##       コア規則（case_agreement, word_order）は常時厳格判定。
## 出典: 03 §3.3・§5.4・§6.1, §7, 附録B.1 / 04 §4。
##
## INC-1: case_agreement, word_order, elements, modifier(最小) を実装。
##        elements: 四大元素の組み合わせ判定（半端=NG, 4全部=混沌, §A.3）。
##        modifier(最小): 修飾語あり＋効果語なしを NG（性・数・格一致は INC-5）。
##        range/condition_clause/number_agreement は ruleset が enabled でも INC-2 以降。
##
## INC-3.5 v0.9.5: ruleset で "range" が enabled のとき、`range_conflict` と
##        `direction_required` をコア違反として判定（03 §3.3 v0.18 / 09 §7.3）。
##        `range_required`（射程外）は座標が要るため SpatialResolver 側で finding を生成し、
##        SpellEngine がパイプラインで grammar_report.findings にマージする。

## 四大元素の ID 集合（§A.3）。
const FOUR_ELEMENTS: Array = ["eldr", "vatn", "vindr", "jorth"]

## INC-3.5 v0.9.5: 形状系の範囲 word_id（vítt / í gegnum）。
##   `direction_required` 判定で「方向語かタイル指定がないとダメ」の対象になる。
const SHAPE_RANGE_WORDS: Array = ["vitt", "i_gegnum"]

## AST と Ruleset を受けて GrammarReport を返す。
##   ast: SpellParser.parse() の出力
##   ruleset: GrammarRuleset（可用性ゲート＋severity_weights を参照）
static func validate(ast: Dictionary, ruleset: Resource) -> GrammarReport:
	var report := GrammarReport.new()
	report.findings = []

	# === コア規則: 格一致 ===
	# 効果語の governs_case が "acc"/"dat"/"gen" のとき、対象語の case が一致するかを検査。
	if _is_rule_active(ruleset, "case_agreement"):
		var finding := _check_case_agreement(ast, ruleset)
		if finding.size() > 0:
			report.findings.append(finding)

	# === コア規則: 語順（v0.15 アイスランド語準拠）===
	if _is_rule_active(ruleset, "word_order"):
		var wo_findings: Array = _check_word_order(ast, ruleset)
		for wf in wo_findings:
			report.findings.append(wf)

	# === コア補助: elements（属性合成、v0.13）===
	if _is_rule_active(ruleset, "elements"):
		var el_finding := _check_elements(ast, ruleset)
		if el_finding.size() > 0:
			report.findings.append(el_finding)

	# === ストレッチ最小: modifier（修飾語単独使用、v0.13）===
	if _is_rule_active(ruleset, "modifier"):
		var mod_finding := _check_modifier(ast, ruleset)
		if mod_finding.size() > 0:
			report.findings.append(mod_finding)
		# v0.14: 修飾一致（性・数・格）
		var agreement_findings: Array = _check_modifier_agreement(ast, ruleset)
		for af in agreement_findings:
			report.findings.append(af)

	# === INC-3.5 コア: 範囲語・方向語の構造的検査（03 §3.3 v0.18 / 09 §7.3）===
	# range_required（射程外）は座標を要するため SpatialResolver 側で生成し、
	# SpellEngine がパイプラインで grammar_report.findings にマージする。
	if _is_rule_active(ruleset, "range"):
		var rc_finding := _check_range_conflict(ast, ruleset)
		if rc_finding.size() > 0:
			report.findings.append(rc_finding)
		var dr_finding := _check_direction_required(ast, ruleset)
		if dr_finding.size() > 0:
			report.findings.append(dr_finding)

	# 全体 pass/fail と G スコア計算。
	report.overall_pass = report.failures().size() == 0
	report.g_score = _compute_g_score(report, ruleset)

	return report


# --- 個別ルール ---

## case_agreement: 効果語の要求格と対象語の指定格を比較。
## 返り値: 失敗なら finding 辞書、pass なら空辞書を返す（pass の finding は出さない方針）。
static func _check_case_agreement(ast: Dictionary, ruleset: Resource) -> Dictionary:
	var effect = ast.get("effect", null)
	var target = ast.get("target", null)

	# 効果語なし → このルールは判定対象外（パース未完。AST 段で別エラー）。
	if effect == null:
		return {}

	var effect_res: WordResource = effect.get("resource", null)
	if effect_res == null:
		return {}

	var required_case: String = effect_res.governs_case
	# governs_case が "" / "none" → 目的語を取らない動詞。判定不要。
	if required_case.is_empty() or required_case == "none":
		return {}

	# 目的語を取る効果語なのに target がない → 失敗（S1 範囲外だが将来のため）。
	if target == null:
		return _build_finding(
			"case_agreement",
			false,
			_get_rule_severity(ruleset, "case_agreement", "moderate"),
			_t("grammar.case_agreement.missing_target") % required_case,
			""
		)

	var target_case: String = String(target.get("case", ""))
	if target_case == required_case:
		return {}  # pass — finding は出さない

	# 不一致。推奨修正を組み立てる（附録B.1: `{word} は対格ではありません（{suggest}？）`）。
	var target_res: WordResource = target.get("resource", null)
	var word_form: String = String(target.get("word_id", ""))
	var suggested_form: String = ""
	if target_res != null:
		# 表示用に「指定された格の語形」を出す（語幹ではなく実際の形）。
		var actual := target_res.get_inflected("sg", target_case)
		if not actual.is_empty():
			word_form = actual
		suggested_form = target_res.get_inflected("sg", required_case)

	var case_label := _case_label(required_case)
	var reason := _t("grammar.case_agreement.reason") % [word_form, case_label]
	var recommended := ""
	if not suggested_form.is_empty():
		recommended = _t("grammar.case_agreement.recommended") % [word_form, suggested_form]

	return _build_finding(
		"case_agreement",
		false,
		_get_rule_severity(ruleset, "case_agreement", "moderate"),
		reason,
		recommended
	)


## elements: 四大元素の組み合わせ判定（§A.3 / v0.13）。
##   - 0 個: 判定対象外（無属性詠唱）
##   - 1 個: pass
##   - 2-3 個（四大の一部）: fail / reason「半端な属性合成は不発します」
##   - 4 個全部: pass（混沌属性、finding は出さない＝情報的に Evaluator が拾う）
##   - ljos/myrkr 混在は許容（混沌に参加しないだけ）
static func _check_elements(ast: Dictionary, ruleset: Resource) -> Dictionary:
	var elements: Array = ast.get("elements", [])
	if elements.is_empty():
		return {}

	# 四大元素の使用集合を作る。
	var four_used: Array = []
	var has_non_four: bool = false
	for el in elements:
		var res: WordResource = el.get("resource", null)
		if res == null:
			continue
		if res.id in FOUR_ELEMENTS:
			if not (res.id in four_used):
				four_used.append(res.id)
		else:
			has_non_four = true  # ljos / myrkr 等

	# 四大の半端な組み合わせ（2-3 個）→ NG
	if four_used.size() >= 2 and four_used.size() <= 3:
		var missing: Array = []
		for e in FOUR_ELEMENTS:
			if not (e in four_used):
				missing.append(e)
		return _build_finding(
			"elements",
			false,
			_get_rule_severity(ruleset, "elements", "minor"),
			_t("grammar.elements.partial_combo") % ", ".join(four_used),
			_t("grammar.elements.partial_combo_recommended") % ", ".join(FOUR_ELEMENTS)
		)

	# 0 個 / 1 個 / 4 個全部 はすべて pass（findings なし）
	# 4 個全部の場合は混沌属性発動（Evaluator が effect_spec.modifiers["chaos"]=true をマークする想定）
	return {}


## modifier_agreement（v0.14）: 修飾語が target と性・数・格一致するか。
##   - 修飾語が複数あれば各々判定（複数 findings を返す）。
##   - target がない／修飾語が形容詞活用を持たないものはスキップ。
##   - 格不一致 → finding（推奨修正に target に合わせた語形を提示）。
##   - 格一致だが活用形が辞書にない → 警告（データ不足）。
## 返り値: finding 辞書の配列（空なら全 pass）。
static func _check_modifier_agreement(ast: Dictionary, ruleset: Resource) -> Array:
	var findings: Array = []
	var modifiers: Array = ast.get("modifiers", [])
	if modifiers.is_empty():
		return findings
	var target = ast.get("target", null)
	if target == null:
		return findings  # 修飾対象なし → このルールは判定対象外（modifier 単独 NG は別 finding）
	var target_res: WordResource = target.get("resource", null)
	if target_res == null:
		return findings
	var target_case: String = String(target.get("case", ""))
	var target_gender: String = target_res.gender

	for mod in modifiers:
		var mod_res: WordResource = mod.get("resource", null)
		if mod_res == null:
			continue
		# 形容詞活用を持たない修飾語（INC-1 範囲外の語）はスキップ。
		if not mod_res.has_gendered_inflection():
			continue
		var mod_case: String = String(mod.get("case", ""))

		# 格不一致
		if mod_case != target_case:
			var given_form: String = mod_res.get_inflected("sg", mod_case, target_gender)
			if given_form.is_empty():
				given_form = mod_res.id
			var expected_form: String = mod_res.get_inflected("sg", target_case, target_gender)
			var target_form: String = target_res.get_inflected("sg", target_case)
			if target_form.is_empty():
				target_form = target_res.id
			var reason := _t("grammar.modifier_agreement.case_mismatch") % [
				given_form, _case_label(mod_case),
				target_form, _case_label(target_case)
			]
			var recommended := ""
			if not expected_form.is_empty():
				recommended = _t("grammar.modifier_agreement.recommended") % [given_form, expected_form]
			findings.append(_build_finding(
				"modifier_agreement",
				false,
				_get_rule_severity(ruleset, "modifier", "moderate"),
				reason,
				recommended
			))
			continue

		# 格一致しているが、活用形が無い（データ不足）
		var expected_form: String = mod_res.get_inflected("sg", target_case, target_gender)
		if expected_form.is_empty():
			findings.append(_build_finding(
				"modifier_agreement",
				false,
				"minor",
				_t("grammar.modifier_agreement.no_form") % [mod_res.id, target_gender, _case_label(target_case)],
				""
			))

	return findings


## modifier 最小判定: 修飾語ありかつ効果語なし → 構文エラー（v0.13）。
## 性・数・格一致は v0.14 で _check_modifier_agreement に分離。
static func _check_modifier(ast: Dictionary, ruleset: Resource) -> Dictionary:
	var modifiers: Array = ast.get("modifiers", [])
	if modifiers.is_empty():
		return {}

	var effect = ast.get("effect", null)
	if effect != null:
		return {}  # 効果語があれば pass（INC-1 では性・数・格は判定しない）

	# 修飾語あり＋効果語なし
	var mod_names: PackedStringArray = PackedStringArray()
	for m in modifiers:
		var res: WordResource = m.get("resource", null)
		if res != null:
			mod_names.append(res.id)
	return _build_finding(
		"modifier",
		false,
		_get_rule_severity(ruleset, "modifier", "minor"),
		_t("grammar.modifier.standalone") % ", ".join(mod_names),
		_t("grammar.modifier.standalone_recommended")
	)


## range_conflict（INC-3.5 v0.9.5 新規、03 §3.3 v0.18 / 09 §7.3）:
##   範囲語が複数指定されていれば矛盾。特に nær (近) + fjarri (遠) は明示的に NG。
##   形状系 (vítt / í gegnum) と距離系 (nær / fjarri) の混在も矛盾扱い（一の呪文に一の範囲）。
##   返り値: fail finding or 空辞書（pass）。
static func _check_range_conflict(ast: Dictionary, ruleset: Resource) -> Dictionary:
	var ranges: Array = ast.get("ranges", [])
	if ranges.size() <= 1:
		return {}  # 0 or 1 個なら矛盾なし
	# 複数指定 → 矛盾
	var ids: PackedStringArray = PackedStringArray()
	for r in ranges:
		var res: WordResource = r.get("resource", null)
		ids.append(res.id if res != null else String(r.get("word_id", "?")))
	return _build_finding(
		"range_conflict",
		false,
		_get_rule_severity(ruleset, "range_conflict", "moderate"),
		_t("grammar.range_conflict.reason") % ", ".join(ids),
		_t("grammar.range_conflict.recommended")
	)


## direction_required（INC-3.5 v0.9.5 新規、03 §3.3 v0.18 / 09 §7.3）:
##   形状系の範囲語 (vítt / í gegnum) は中心方向の指定が必須。
##   方向語 (fram/aptr/vinstri/hœgri) が呪文に無ければ NG。
##   タイル直接指定は呪文側からは見えないため、呪文 AST に方向語が無ければ fail を立て、
##   呼び側（UI）が「タイル指定があるならこの finding を抑制する」運用にする想定。
##   INC-3.5 では呪文タイル指定 UI を実装しないため、本判定は方向語のみで OK。
##   返り値: fail finding or 空辞書（pass）。
static func _check_direction_required(ast: Dictionary, ruleset: Resource) -> Dictionary:
	var ranges: Array = ast.get("ranges", [])
	if ranges.is_empty():
		return {}  # 範囲語なし → 暗黙隣接、direction 不要（最隣接敵自動）
	var has_shape: bool = false
	var shape_id: String = ""
	for r in ranges:
		var res: WordResource = r.get("resource", null)
		var rid: String = res.id if res != null else String(r.get("word_id", ""))
		if rid in SHAPE_RANGE_WORDS:
			has_shape = true
			shape_id = rid
			break
	if not has_shape:
		return {}  # 形状系がなければ direction 不要（距離系は最隣接扇 fallback）
	# 形状系あり → directions が空なら NG
	var directions: Array = ast.get("directions", [])
	if directions.size() > 0:
		return {}
	return _build_finding(
		"direction_required",
		false,
		_get_rule_severity(ruleset, "direction_required", "moderate"),
		_t("grammar.direction_required.reason") % shape_id,
		_t("grammar.direction_required.recommended")
	)


## word_order（v0.15 アイスランド語準拠）: 正準 `[属性] 効果語 [修飾] 対象語` からの逸脱を検査。
## 判定:
##   (a) effect が target より前にあるか（VO 命令文）
##   (b) modifier は target に隣接（直前または直後）
##   (c) element は effect の前 または target の後（effect-target 間に挟まない）
## 複数違反が同時に出ることもあるので Array を返す。
static func _check_word_order(ast: Dictionary, ruleset: Resource) -> Array:
	var findings: Array = []
	var order: Array = ast.get("word_order", [])
	var effect_idx := order.find("effect")
	var target_idx := order.find("target")
	if effect_idx == -1 or target_idx == -1:
		return findings  # effect/target いずれかが無ければ判定対象外（別 finding が別経路で出る）

	# (a) VO 順序
	if effect_idx > target_idx:
		findings.append(_build_finding(
			"word_order",
			false,
			_get_rule_severity(ruleset, "word_order", "minor"),
			_t("grammar.word_order.vo_violation"),
			_t("grammar.word_order.vo_recommended") % _show_token_role_jp("effect")
		))
		return findings  # 基本順序が崩れているので隣接チェックはスキップ（混乱回避）

	# (b) modifier の隣接性
	for i in order.size():
		if String(order[i]) == "modifier":
			# target に隣接（直前 i==target_idx-1 or 直後 i==target_idx+1）であること
			var adjacent: bool = (i == target_idx - 1) or (i == target_idx + 1)
			if not adjacent:
				findings.append(_build_finding(
					"word_order",
					false,
					_get_rule_severity(ruleset, "word_order", "minor"),
					_t("grammar.word_order.modifier_adjacency"),
					_t("grammar.word_order.modifier_adjacency_recommended")
				))
				break  # 1 finding で十分

	# (c) element の位置: effect の前 or target の後
	for i in order.size():
		if String(order[i]) == "element":
			var in_between: bool = i > effect_idx and i < target_idx
			if in_between:
				findings.append(_build_finding(
					"word_order",
					false,
					_get_rule_severity(ruleset, "word_order", "minor"),
					_t("grammar.word_order.element_inserted"),
					_t("grammar.word_order.element_inserted_recommended")
				))
				break

	return findings


## v0.17: static 文脈から翻訳を引くヘルパー（Object.tr() は static 不可のため TranslationServer 経由）。
static func _t(key: String) -> String:
	return TranslationServer.translate(key)


## 役割名の日本語表示（推奨修正用、補助）。
static func _show_token_role_jp(role: String) -> String:
	match role:
		"effect": return "効果語"
		"target": return "対象語"
		"modifier": return "修飾語"
		"element": return "属性語"
		_: return role


# --- スコアリング ---

## INC-3.5 v0.9.5: SpellEngine がパイプライン途中で SpatialResolver の core_findings を
## merge した後、G スコアと overall_pass を再計算するための公開ヘルパ。
static func recompute_after_merge(report: GrammarReport, ruleset: Resource) -> void:
	if report == null:
		return
	report.overall_pass = report.failures().size() == 0
	report.g_score = _compute_g_score(report, ruleset)


## G スコア（0..1）。03 §5.4「GrammarReport の pass 比率＋語順ボーナス補正」。
## INC-1 暫定モデル:
##   G = (active コア規則のうち pass した数) / (active コア規則の総数)
##   コア規則ゼロなら G=1.0（判定不能 = ペナルティなし）
## severity_weights はフィードバック強調用に温存し、G への寄与は INC-2 のチューニングで再検討。
## ※暴発確率には不関与（T5、§5.2）。
##
## INC-3.5 v0.9.5: ruleset で "range" 解禁時のみ range_conflict / direction_required /
##   range_required（SpatialResolver マージ）を G の分母に加算する。
static func _compute_g_score(report: GrammarReport, ruleset: Resource) -> float:
	var core_rules: PackedStringArray = PackedStringArray(["case_agreement", "word_order"])
	# INC-3.5: range が解禁されていれば、その下位 3 ルールも core 扱い。
	if _is_rule_active(ruleset, "range"):
		core_rules.append("range_conflict")
		core_rules.append("direction_required")
		core_rules.append("range_required")
	var active: int = core_rules.size()
	if active == 0:
		return 1.0

	var failed_core: int = 0
	var seen_failed: Dictionary = {}
	for f in report.failures():
		var rname: String = String(f.get("rule", ""))
		if rname in core_rules and not seen_failed.has(rname):
			seen_failed[rname] = true
			failed_core += 1

	var passed: int = max(0, active - failed_core)
	return clampf(float(passed) / float(active), 0.0, 1.0)


# --- 補助 ---

## ルールが ruleset で有効か（is_rule_enabled 経由）。ruleset null は「コア規則は常時 ON」。
static func _is_rule_active(ruleset: Resource, rule_name: String) -> bool:
	if ruleset == null:
		# ruleset 未指定でもコア規則は判定する（D3: コア常時厳格）。
		# elements / modifier は ruleset がない場合は判定しない（可用性ゲートを尊重）。
		return rule_name in ["case_agreement", "word_order"]
	if ruleset.has_method("is_rule_enabled"):
		return ruleset.is_rule_enabled(rule_name)
	return false


## ルールに記述された severity を取る（無ければ既定値）。
static func _get_rule_severity(ruleset: Resource, rule_name: String, default: String) -> String:
	if ruleset == null:
		return default
	var rules = ruleset.get("rules")
	if typeof(rules) != TYPE_DICTIONARY:
		return default
	if not rules.has(rule_name):
		return default
	var rule = rules[rule_name]
	if typeof(rule) != TYPE_DICTIONARY:
		return default
	return String(rule.get("severity", default))


static func _build_finding(rule: String, passed: bool, severity: String, reason: String, recommended: String) -> Dictionary:
	return {
		"rule": rule,
		"pass": passed,
		"severity": severity,
		"reason": reason,
		"recommended": recommended,
	}


## 格 ID → ロケール別ラベル（v0.17 i18n 化）。_t("grammar.case.nom") 等を使う。
## 旧名 _case_label_ja は v0.17 で _case_label にリネーム（多言語対応）。
static func _case_label(grammatical_case: String) -> String:
	match grammatical_case:
		"nom": return _t("grammar.case.nom")
		"acc": return _t("grammar.case.acc")
		"dat": return _t("grammar.case.dat")
		"gen": return _t("grammar.case.gen")
		_: return grammatical_case
