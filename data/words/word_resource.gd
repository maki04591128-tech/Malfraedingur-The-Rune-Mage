extends Resource
class_name WordResource
## WordResource — 語彙の正典データ（Resource, .tres で永続化）。
##
## スキーマ出典: docs/05_データ定義テンプレート.md §1。
## 不変条件:
##   - word_class=target → gender と inflection 必須（格一致のため）。
##   - word_class=effect → governs_case 必須（自動詞/移動効果は "none"）。
##   - tier ∈ {1,2,3}、comprehension_default ∈ [0,100]。
##   - gloss.ja 必須（gloss.en は INC-5/6 のリリースゲート, DL1）。
##   - reading_kana/ipa は表示・教育用のみ。判定/威力に一切関与しない（DP2）。
## 設計方針:
##   - コードにゲーム内容（語形）をハードコードしない＝全て本 Resource。
##   - INC-0 では @export と簡易バリデータのみ。詳細チェックは INC-1 で SpellEngine 側に。

## 一意キー（基本形・通常は主格 sg）。
@export var id: String = ""

## 語クラス。03 附録A の語クラス分類に準拠。
## effect | target | element | modifier | range | conditional | cond_detail | numeral | time_unit | suffix
@export var word_class: String = ""

## 学習用の意味（伏せ表示の対象）。ロケール別マップ（DL1）。
## 例: { "ja": "敵", "en": "enemy" }
@export var gloss: Dictionary = {}

## カナ読み（表示補助・無辞書モードでは非表示）。
@export var reading_kana: String = ""

## IPA（詳細ビュー用・任意）。
@export var ipa: String = ""

## 名詞/形容詞のみ: masculine | feminine | neuter
@export var gender: String = ""

## 固有威力ティア 1|2|3。理解度と独立（03 附録A の暫定tier）。
@export_range(1, 3) var tier: int = 1

## 新規発見時の理解度（通常 0）。
@export_range(0, 100) var comprehension_default: int = 0

## 格変化表（対象語は必須）。
## 形式 1（名詞・性別固定）: { "sg": { "nom": "fjandi", "acc": "fjanda", "dat": ..., "gen": ... }, "pl": { ... } }
## 形式 2（形容詞・性別可変、v0.14 で追加）: { "sg": { "masculine": { "nom": "mikill", "acc": "mikinn", ... }, "feminine": {...}, "neuter": {...} } }
##   get_inflected(number, case, gender) で性別を渡せば形容詞活用も引ける。
@export var inflection: Dictionary = {}

## 効果語のみ: 要求する目的語の格。"acc" / "dat" / "gen" / "none" / "" のいずれか。
@export var governs_case: String = ""

## 条件語/接続等のみ: 構文上の役割（例: "if"）。
@export var function_role: String = ""

## 入手手段タグ。例: ["inscription", "drop"]
@export var discovery: PackedStringArray = PackedStringArray()

## 元素相性メタ（word_class=element のみ）。
## 例: { "cycle": "strong_vs:vindr, weak_vs:vatn", "chaos_member": true }
@export var element: Dictionary = {}

## 出典（必須・03 附録A から転記）。
@export var source: String = ""

## 信頼度。verified | review | ambiguous | unchecked
@export var confidence: String = "unchecked"

## confidence=verified を満たすか（M5 監修で確定）。
@export var verified: bool = false


## 簡易バリデーション。失敗理由の配列を返す（空 = OK）。
## INC-0 ではここで止めず、SpellEngine 側で読み込み時に走らせる想定。
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()

	if id.is_empty():
		errors.append("id is required")
	if word_class.is_empty():
		errors.append("word_class is required")
	if not gloss.has("ja"):
		errors.append("gloss.ja is required (DL1)")
	if tier < 1 or tier > 3:
		errors.append("tier must be 1..3 (got %d)" % tier)
	if comprehension_default < 0 or comprehension_default > 100:
		errors.append("comprehension_default must be 0..100")

	match word_class:
		"target":
			if gender.is_empty():
				errors.append("target word requires gender")
			if inflection.is_empty():
				errors.append("target word requires inflection")
		"effect":
			if governs_case.is_empty():
				errors.append("effect word requires governs_case (use 'none' for intransitive)")
		"conditional":
			if function_role.is_empty():
				errors.append("conditional word requires function_role")
		_:
			pass

	if verified and confidence != "verified":
		errors.append("verified=true requires confidence='verified'")

	return errors


## ロケール別グロス取得。フォールバック順: 指定 → ja → 空文字。
func get_gloss(locale: String) -> String:
	if gloss.has(locale):
		return gloss[locale]
	if gloss.has("ja"):
		return gloss["ja"]
	return ""


## 格変化形を取得（v0.14 で gender 引数を追加）。
##   number: "sg" | "pl"
##   grammatical_case: "nom" | "acc" | "dat" | "gen"
##   gender: "masculine" | "feminine" | "neuter" | "" (空)
##     - 形容詞（性別可変）の場合は gender を渡す。
##     - 名詞（性別固定）の場合は無視（gender="" でも内部で名詞構造として引く）。
## 見つからなければ空文字（呼び出し側で要 nil 判断）。
func get_inflected(number: String, grammatical_case: String, gender: String = "") -> String:
	if not inflection.has(number):
		return ""
	var number_paradigm = inflection[number]
	if typeof(number_paradigm) != TYPE_DICTIONARY:
		return ""

	# 形容詞（性別可変）: 性別キーがある場合は性別 → 格 の順で引く。
	if not gender.is_empty() and number_paradigm.has(gender):
		var gender_paradigm = number_paradigm[gender]
		if typeof(gender_paradigm) == TYPE_DICTIONARY and gender_paradigm.has(grammatical_case):
			return String(gender_paradigm[grammatical_case])
		return ""

	# 名詞（性別固定）: 直接格で引く。
	if number_paradigm.has(grammatical_case):
		var v = number_paradigm[grammatical_case]
		if typeof(v) == TYPE_STRING:
			return v
	return ""


## 形容詞活用を持つか（modifier の判定用）。
## inflection["sg"] のキーに gender 文字列が含まれていれば形容詞構造。
func has_gendered_inflection() -> bool:
	if not inflection.has("sg"):
		return false
	var sg = inflection["sg"]
	if typeof(sg) != TYPE_DICTIONARY:
		return false
	for key in ["masculine", "feminine", "neuter"]:
		if sg.has(key):
			return true
	return false
