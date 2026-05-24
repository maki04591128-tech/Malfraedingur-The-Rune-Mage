extends Node
## Lexicon — 永続語彙＋文法進行＋語レジストリ（Autoload）。
##
## 役割（INC-1 で部分実装）:
##   - 語 ID から WordResource を引く中央レジストリ（get_word）。
##   - 各語の現在の理解度（comprehension）を返す。
##     INC-1 では永続化せずデフォルト 0 を返す。永続化と上昇ロジックは INC-4。
##
## 不変条件:
##   - 死亡時 reset されない（テーマ「知識は残る」の保証点。永続化は INC-4）。
##   - この autoload は他の autoload を **class スコープで参照しない**
##     （Godot 4 の autoload parse 順序問題回避）。
##
## スキーマ詳細は 04 §3 / 05_データ定義テンプレート.md を参照。

## 既知語の ID 一覧（INC-1 暫定）。INC-5 で監修語彙台帳から自動生成へ。
const KNOWN_WORD_IDS: Array = [
	"meida", "fjandi", "sjalfr",  # 効果＋対象
	"eldr", "vatn", "vindr", "jorth",  # 四大元素
	"mikill", "litill",  # 修飾語（phase_intermediate で解禁）
]

## .tres の格納パス雛形。
const WORD_RES_PATH := "res://data/words/%s.tres"

## 語 ID → WordResource のメモリキャッシュ（同セッション内で重複 load を避ける）。
var _word_cache: Dictionary = {}

## 語 ID → 理解度（0..100）。INC-1 は空。永続化は INC-4 で user://lexicon.save へ。
var _comprehension: Dictionary = {}

## 魔法スロット（INC-3 v0.9.2 新規、要求 4）。
## スロット 1-5 にトークン列 (Array[Dictionary { word_id, case }]) を保存。
## SaveData の grammar_progress と同じ「知識側」扱いで、ループ巻き戻し非対象（D7 と同思想）。
## 永続化は INC-4 で user://lexicon.save に統合予定。INC-3 v0.9.2 はメモリ保持のみ。
## デフォルト: スロット 1 = meida + fjandi(acc)（INC-3 既定詠唱、F で上書き可能）。
var _spell_slots: Dictionary = {
	1: [
		{"word_id": "meida", "case": ""},
		{"word_id": "fjandi", "case": "acc"},
	],
}


## スロット番号 (1-5) から保存済みトークン列を取得。未設定なら空配列。
func get_spell_slot(slot: int) -> Array:
	if slot < 1 or slot > 5:
		return []
	return _spell_slots.get(slot, []).duplicate(true)


## スロット番号にトークン列を保存。slot ∈ [1, 5]。
##   tokens: [{ "word_id": String, "case": String }, ...]
func set_spell_slot(slot: int, tokens: Array) -> void:
	if slot < 1 or slot > 5:
		return
	_spell_slots[slot] = tokens.duplicate(true)


## スロット 1-5 の状態スナップショット（UI 表示用）。
##   返り値: { 1: [tokens] or null, 2: ..., ..., 5: ... }
func get_all_spell_slots() -> Dictionary:
	var result: Dictionary = {}
	for i in range(1, 6):
		result[i] = _spell_slots.get(i, null)
	return result


## 語 ID から WordResource を取得。なければ null。
##   word_id: meida, fjandi, ...
func get_word(word_id: String) -> WordResource:
	if word_id.is_empty():
		return null
	if _word_cache.has(word_id):
		return _word_cache[word_id]
	var path := WORD_RES_PATH % word_id
	if not ResourceLoader.exists(path):
		return null
	var res: WordResource = load(path) as WordResource
	if res != null:
		_word_cache[word_id] = res
	return res


## 既知語の ID 配列（重複 load を避ける用途）。
func get_known_word_ids() -> Array:
	return KNOWN_WORD_IDS.duplicate()


## 語の現在理解度（0..100）。INC-1: 未登録なら WordResource.comprehension_default を返す。
##   word_id: 語 ID
##   返り値: 0..100
func get_comprehension(word_id: String) -> int:
	if _comprehension.has(word_id):
		return int(_comprehension[word_id])
	var w := get_word(word_id)
	if w != null:
		return w.comprehension_default
	return 0


## デバッグ/テスト用: 理解度を直接設定。INC-4 で永続化導線と統合予定。
##   word_id: 語 ID
##   value: 0..100
func set_comprehension(word_id: String, value: int) -> void:
	_comprehension[word_id] = clampi(value, 0, 100)


# --- INC-4 で実装 ---
# func save_to_disk() -> void:
#     pass
#
# func load_from_disk() -> void:
#     pass
