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
		# INC-5.1: 入力 dict に number/gender/mood/matched_form があれば保持
		# （freetext 経路が tokenize_freetext で解決した情報を SpellEngine.cast 経由で
		#  再 tokenize しても失わないため）。タイル経路では空のまま。
		out.append({
			"word_id": word_id,
			"case": grammatical_case,
			"number": String(entry.get("number", "")),
			"gender": String(entry.get("gender", "")),
			"mood": String(entry.get("mood", "")),
			"resource": resource,
			"matched_form": String(entry.get("matched_form", word_id)),
		})
	return out


## 無辞書（フルテキスト）経路。生綴りからトークン列に正規化（03 §4）。
##   raw_text: ユーザー入力の素テキスト。空白区切り。各語は "綴り" または "綴り:case" 形式。
##   _ruleset: 未使用（将来の最厳 ruleset 強制チェック用）
##   word_lookup: Callable(word_id) -> WordResource。lookup 失敗時は resource=null
##                （Validator 層で unknown_word finding が立ち、Resolver で ×4 暴発倍率発火）。
##   known_word_ids: 屈折逆引きの走査対象 word_id 配列。空ならパス 1 (id 完全一致) のみ走る。
##
## INC-5.1 強化（A: 古綴正規化 + B: 屈折マッチャ統合）:
##   - 入力綴りは Orthography.normalize() で lowercase + ASCII 互換化
##     （á/ǽ/œ/ð/þ → a/ae/oe/d/th、meiða → meida）
##   - word_id 完全一致 → 屈折表逆引き (fjanda → fjandi + case=acc + number=sg) → 動詞活用 (verb_forms)
##     の順で InflectionMatcher.match_form() が解決
##   - マッチ結果から resource / case / number / gender / mood をトークンに格納
##   - 完全に未知の綴りは word_id をそのまま（正規化済）入れ、resource=null
##   - "綴り:case" 構文で明示格指定可。明示指定がある場合は屈折マッチが返した case を上書き
##
## INC-4 までの最小実装:
##   - 空白で分割し、各語を { word_id, case, resource } トークンに正規化
##   - 既知綴り（word_id 完全一致）はそのまま採用
##   - 未知綴りは word_id をそのまま入れ、resource=null
##
## INC-5.1 で対応:
##   - 古綴の表記揺れ（á/ǽ/œ/ð/þ）
##   - 屈折形（fjanda）からの主格復元（fjandi）
##
## INC-5.2 以降に持ち越し:
##   - 編集距離による typo 寛容（fjandl → fjandi）
##   - 形態素解析（複合語分解）
static func tokenize_freetext(raw_text: String, _ruleset: Resource = null, word_lookup: Callable = Callable(), known_word_ids: Array = []) -> Array:
	var out: Array = []
	var text: String = String(raw_text).strip_edges()
	if text.is_empty():
		return out
	var parts: PackedStringArray = text.split(" ", false)  # 連続空白は無視
	for part_raw in parts:
		var s: String = String(part_raw).strip_edges()
		if s.is_empty():
			continue
		var raw_form: String = ""
		var explicit_case: String = ""
		if s.contains(":"):
			var split: PackedStringArray = s.split(":")
			raw_form = String(split[0]).strip_edges()
			if split.size() >= 2:
				explicit_case = String(split[1]).strip_edges()
		else:
			raw_form = s
		if raw_form.is_empty():
			continue

		# INC-5.1 A: 入力綴りを正規化（古綴 → ASCII 互換）
		var normalized_form: String = Orthography.normalize(raw_form)

		# INC-5.1 B: InflectionMatcher で word_id / case / number / gender / mood を解決
		var token: Dictionary = {
			"word_id": normalized_form,
			"case": explicit_case,
			"number": "",
			"gender": "",
			"mood": "",
			"resource": null,
			"matched_form": raw_form,
		}
		if word_lookup.is_valid() and known_word_ids.size() > 0:
			var hit: Dictionary = InflectionMatcher.match_form(raw_form, word_lookup, known_word_ids)
			if not hit.is_empty():
				token["word_id"] = String(hit.get("word_id", normalized_form))
				token["resource"] = hit.get("resource", null)
				token["number"] = String(hit.get("number", ""))
				token["gender"] = String(hit.get("gender", ""))
				token["mood"] = String(hit.get("mood", ""))
				# 明示 :case が無いときは屈折マッチが返した case を採用
				if explicit_case.is_empty():
					token["case"] = String(hit.get("case", ""))
		elif word_lookup.is_valid():
			# 後方互換: known_word_ids 未指定なら id 完全一致のみ
			var result_legacy = word_lookup.call(normalized_form)
			if result_legacy is WordResource:
				token["resource"] = result_legacy

		out.append(token)
	return out
