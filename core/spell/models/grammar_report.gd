extends Resource
class_name GrammarReport
## GrammarReport — 文法判定結果（規則ごとの pass/fail と理由・推奨修正）。
##
## 役割: UI フィードバックの源（spell_lab 表示用、`06_INC1検証仕様.md` §2.2）。
## 出典: 04 §4 / 03 §3.3・§5.4・§7
##
## INC-0: 空シェル。findings の中身は INC-1 で Validator が詰める。

## 規則ごとの判定結果。形（例）:
##   {
##     "rule": "case_agreement",
##     "pass": false,
##     "severity": "moderate",
##     "reason": "対格ではありません",
##     "recommended": "fjandi → fjanda?"
##   }
@export var findings: Array[Dictionary] = []

## 全体として pass か（コア規則が全て pass のとき true）。
@export var overall_pass: bool = false

## 文法スコア G（03 §5.4）。0.0..1.0 を想定。INC-1 で Evaluator が計算。
@export var g_score: float = 0.0


## 失敗 finding だけを抽出（UI フィードバック用）。
func failures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in findings:
		if not f.get("pass", true):
			out.append(f)
	return out


## コア規則 (case_agreement / word_order) で失敗があるか。
## コア規則 fail は INC-1/2 の戦闘で命中精度を落とすことに使う。
func has_core_failure() -> bool:
	for f in findings:
		var rule_name: String = f.get("rule", "")
		var passed: bool = f.get("pass", true)
		if not passed and rule_name in ["case_agreement", "word_order"]:
			return true
	return false
