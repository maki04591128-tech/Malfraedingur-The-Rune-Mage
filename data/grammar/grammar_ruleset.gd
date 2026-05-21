extends Resource
class_name GrammarRuleset
## GrammarRuleset — 構文の可用性集合（Resource, .tres で永続化）。
##
## スキーマ出典: docs/05_データ定義テンプレート.md §2、確定モデル 03 §6。
##
## 重要な意味づけ:
##   - `rules[name].enabled` は「その構文が使用可能（導入済み）か」＝**可用性ゲート**。
##     enabled:false は寛容に無視するのではなく、その構文・語をプレイヤーに登場させない。
##   - **コア規則**（case_agreement, word_order）は全フェーズで `core:true` かつ `enabled:true`。
##     段階に依らず厳格判定（寛容化はしない＝D3 補助型）。
##   - `scaffold_level` は UI 補助段階（SpellComposer のみが解釈）。
##     Validator の合否・G には一切影響しない（D3）。
##   - `severity_weights` は文法スコア G の減点幅・フィードバック強調度に寄与。
##     **暴発確率には不関与**（v0.7 で確定。03 §5.2/5.3、05 v0.5）。

## 一意キー（例: "phase_intro" | "phase_beginner" | "phase_intermediate" | "phase_advanced"）。
@export var id: String = ""

## 表示ラベル（例: "入門" / "初級"）。i18n 対応はラベル側でなく UI 側で行う（INC-0 では文字列直書きで可）。
@export var label: String = ""

## ルール辞書。形:
##   { "case_agreement": { "enabled": true, "severity": "moderate", "core": true },
##     "word_order":     { "enabled": true, "severity": "minor",    "core": true },
##     "word_order_bonus": { "enabled": true, "weight": 0.15 },
##     "elements":       { "enabled": true, "severity": "minor" },
##     "modifier":       { "enabled": false, "severity": "minor" },
##     ... }
##
## 既知のルール名（03 §6 のフェーズ表に対応）:
##   case_agreement / word_order / word_order_bonus /
##   elements / modifier / range / number_agreement /
##   condition_clause / negation_scope
@export var rules: Dictionary = {}

## UI 補助段階。"max" | "mid" | "low" | "none"
##   max:  正格自動提示・不正語順グレーアウト・ライブプレビュー
##   mid:  要求時ヒント＋詠唱前警告
##   low:  詠唱後 GrammarReport のみ
##   none: 補助なし（無辞書モードは強制 none）
@export_enum("max", "mid", "low", "none") var scaffold_level: String = "max"

## severity→重み。文法スコア G の減点幅とフィードバック強調度に使う（暴発率には不関与）。
## デフォは 05 §2 の例: minor=1.1 / moderate=1.3 / severe=1.8
@export var severity_weights: Dictionary = {
	"minor": 1.1,
	"moderate": 1.3,
	"severe": 1.8,
}


## 簡易バリデーション。失敗理由の配列を返す（空 = OK）。
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()

	if id.is_empty():
		errors.append("id is required")
	if label.is_empty():
		errors.append("label is required")
	if not _is_valid_scaffold(scaffold_level):
		errors.append("scaffold_level must be one of max|mid|low|none (got '%s')" % scaffold_level)

	# severity_weights の必須キー
	for key in ["minor", "moderate", "severe"]:
		if not severity_weights.has(key):
			errors.append("severity_weights['%s'] is required" % key)

	# コア規則は enabled:true 必須（寛容化禁止＝D3）。
	# 定義されていなくてもエラーにはしない（後で追加できる）が、定義済みなら enabled:true を要求。
	for core_rule in ["case_agreement", "word_order"]:
		if rules.has(core_rule):
			var rule = rules[core_rule]
			if typeof(rule) == TYPE_DICTIONARY:
				if rule.get("enabled", true) == false:
					errors.append("core rule '%s' must be enabled (no lenient phase)" % core_rule)
				# core フラグの一貫性は警告レベル（必須にしない）。

	return errors


## ルールが現在のフェーズで利用可能か。未定義は false 扱い（出さない）。
func is_rule_enabled(rule_name: String) -> bool:
	if not rules.has(rule_name):
		return false
	var rule = rules[rule_name]
	if typeof(rule) != TYPE_DICTIONARY:
		return false
	return rule.get("enabled", false)


## ルールがコア規則か（段階に依らず厳格適用）。
func is_core_rule(rule_name: String) -> bool:
	if not rules.has(rule_name):
		return false
	var rule = rules[rule_name]
	if typeof(rule) != TYPE_DICTIONARY:
		return false
	return rule.get("core", false)


## severity に対応する重みを返す。未定義は 1.0。
func get_severity_weight(severity: String) -> float:
	return float(severity_weights.get(severity, 1.0))


## word_order_bonus のウェイト（成功時威力ボーナス）。
## 未定義/無効化なら 0.0（ボーナスなし）。
func get_word_order_bonus_weight() -> float:
	if not is_rule_enabled("word_order_bonus"):
		return 0.0
	var rule = rules["word_order_bonus"]
	return float(rule.get("weight", 0.0))


static func _is_valid_scaffold(level: String) -> bool:
	return level in ["max", "mid", "low", "none"]
