extends RefCounted
class_name SpellTokenizer
## SpellTokenizer — 呪文パイプラインの最初の段。
##
## 役割: SpellComposer の出力（{word_id, case} 列）と無辞書テキスト経路の両方を、
##       共通の正規化トークン列に揃える（03 §4 の2系統正規化）。
## 出典: 03 §4, 04 §4。
##
## INC-1: SpellComposer 経路（タイル列）の正規化を実装。
##        word_id → WordResource を引いて token に attach する。
##        無辞書経路（tokenize_freetext）は INC-2/3 で。

## SpellComposer 経路の入力をトークン列に変換。
##   inputs: [ {"word_id": "fjandi", "case": "acc"}, ... ]
##   _ruleset: GrammarRuleset（未使用。INC-2 で無辞書フラグ等の参照）
##   word_lookup: Callable(word_id: String) -> WordResource
##                未指定なら resource は null（テスト用）。
## 返り値: [ {"word_id": ..., "case": ..., "resource": WordResource or null}, ... ]
static func tokenize(inputs: Array, _ruleset: Resource = null, word_lookup: Callable = Callable()) -> Array:
	var out: Array = []
	for entry in inputs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var word_id: String = String(entry.get("word_id", ""))
		var grammatical_case: String = String(entry.get("case", ""))
		var resource: WordResource = null
		if word_lookup.is_valid() and not word_id.is_empty():
			var result = word_lookup.call(word_id)
			if result is WordResource:
				resource = result
		out.append({
			"word_id": word_id,
			"case": grammatical_case,
			"resource": resource,
		})
	return out


## 無辞書（フルテキスト）経路。生綴りからトークン列に正規化（03 §4）。
##   raw_text: ユーザー入力の素テキスト。空白区切り。各語は "word_id" または "word_id:case" 形式。
##   _ruleset: 未使用（将来の最厳 ruleset 強制チェック用）
##   word_lookup: Callable(word_id) -> WordResource。lookup 失敗時は resource=null
##                （Validator/Resolver 層で unknown_word ×4 として扱える）。
##
## INC-4 最小実装（無辞書モード v1）:
##   - 空白で分割し、各語を { word_id, case, resource } トークンに正規化
##   - 既知綴り（word_id 完全一致）はそのまま採用
##   - 未知綴りは word_id をそのまま入れ、resource=null（→ 将来 unknown_word finding）
##   - "word:case" 構文で格指定可（例: "meida fjandi:acc"）
##
## 制約（INC-5 で本格化）:
##   - 古綴の表記揺れ（á/ǽ/œ）は正規化しない
##   - 屈折形（fjanda）からの主格復元（fjandi）はしない
##   - 形態素解析もしない
static func tokenize_freetext(raw_text: String, _ruleset: Resource = null, word_lookup: Callable = Callable()) -> Array:
	var out: Array = []
	var text: String = String(raw_text).strip_edges()
	if text.is_empty():
		return out
	var parts: PackedStringArray = text.split(" ", false)  # 連続空白は無視
	for part_raw in parts:
		var s: String = String(part_raw).strip_edges()
		if s.is_empty():
			continue
		var word_id: String = ""
		var grammatical_case: String = ""
		if s.contains(":"):
			var split: PackedStringArray = s.split(":")
			word_id = String(split[0]).strip_edges()
			if split.size() >= 2:
				grammatical_case = String(split[1]).strip_edges()
		else:
			word_id = s
		var resource: WordResource = null
		if word_lookup.is_valid() and not word_id.is_empty():
			var result = word_lookup.call(word_id)
			if result is WordResource:
				resource = result
		out.append({
			"word_id": word_id,
			"case": grammatical_case,
			"resource": resource,
		})
	return out
