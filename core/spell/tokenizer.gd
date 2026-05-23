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
##   raw_text: ユーザー入力の素テキスト
## INC-1: 未実装。INC-2/3 で形態素分割・格推定を実装。
static func tokenize_freetext(_raw_text: String, _ruleset: Resource = null, _word_lookup: Callable = Callable()) -> Array:
	return []
