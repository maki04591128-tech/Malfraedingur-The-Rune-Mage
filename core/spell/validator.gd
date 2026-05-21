extends RefCounted
class_name SpellValidator
## SpellValidator — 文法判定（格一致・語順・可用性）→ GrammarReport。
##
## 役割: 03 §5.4 の文法スコア G の元データを作る。
##       Validator は ruleset.scaffold_level に**不関与**（D3: 補助型／UI のみ）。
##       コア規則（case_agreement, word_order）は常時厳格判定。
## 出典: 03 §3.3・§5.4・§6.1 / 04 §4。
##
## INC-0: 空シェル。pass/fail 判定は INC-1 で。

## AST と Ruleset を受けて GrammarReport を返す。
##   ast: SpellParser.parse() の出力
##   ruleset: GrammarRuleset（可用性ゲート＋severity_weights を参照）
static func validate(_ast: Dictionary, _ruleset: Resource) -> GrammarReport:
	var report := GrammarReport.new()
	# INC-0: コア規則の判定は未実装。デフォルト pass:true で通す（spell_lab 起動を妨げない）。
	report.overall_pass = true
	report.g_score = 1.0
	report.findings = []
	return report
