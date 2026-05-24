extends Resource
class_name InscriptionResource
## InscriptionResource — ルーン碑文（翻訳パズル）。INC-4 B-3 新規（05 §6）。
##
## ゲーム内では床に書かれた碑文タイルを踏んで「翻訳」を試みる。
## 初期 INC-4 実装では「runes（ルーン表記）に対応する語 id を選択肢から当てる」最小 UI。
## 選択肢は answer_word_ids（正答）+ choices_word_ids（誤答候補）からシャッフルされる。
## 正解で comprehension_gain の各語が一定量加算される。
##
## 不変条件:
##   - difficulty ∈ { "intro", "beginner", "intermediate", "advanced" }
##   - answer_word_ids 非空
##   - reward.comprehension_gain は [ { word_id, amount } ] 配列

@export var id: String = ""
@export var difficulty: String = "intro"
@export var runes: String = ""             ## ルーン表記（表示用）
@export var prompt_ja: String = ""         ## 「この碑文の意味は？」プロンプト
@export var answer_word_ids: PackedStringArray = PackedStringArray()
@export var choices_word_ids: PackedStringArray = PackedStringArray()  ## 誤答候補
@export var comprehension_gain: Array = []   ## [{ "word_id": String, "amount": int }, ...]
@export var time_cost: float = 1.0
@export var unlock_hint: String = ""
@export var source: String = "オリジナル"
@export var verified: bool = false


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id.is_empty():
		errors.append("id is required")
	if difficulty not in ["intro", "beginner", "intermediate", "advanced"]:
		errors.append("difficulty must be intro|beginner|intermediate|advanced (got '%s')" % difficulty)
	if answer_word_ids.is_empty():
		errors.append("answer_word_ids is required (non-empty)")
	for g in comprehension_gain:
		if typeof(g) != TYPE_DICTIONARY:
			errors.append("comprehension_gain entries must be Dictionary")
			continue
		if not g.has("word_id") or not g.has("amount"):
			errors.append("comprehension_gain entry requires word_id and amount")
	return errors
