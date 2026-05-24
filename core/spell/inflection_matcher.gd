extends RefCounted
class_name InflectionMatcher
## InflectionMatcher — 屈折形 → (word_id, case, number, gender) 逆引き。
##
## 役割（INC-5.1 / 03 §3.3「動詞活用・複数形対応」）:
##   - 無辞書経路で `fjanda` と入力されたら、word_id=fjandi + case=acc + number=sg を返す。
##   - 名詞/形容詞の inflection 表全体を線形走査し、Orthography 正規化形での完全一致を探す。
##   - 動詞 (effect) は verb_forms (INC-5.1 新規) も同様に走査し、mood (inf/imp_2sg/imp_2pl) を返す。
##
## 不変条件:
##   - WordResource.id が変わらない限り、同じ入力に対して同じ結果を返す（決定性）。
##   - 複数語にヒットする場合は KNOWN_WORD_IDS 配列の出現順で最初に当たった語を採用。
##     （INC-5.2 以降で曖昧性スコア・優先度テーブルを導入候補）
##   - 主格 (nom) と word_id が同じ場合は word_id 完全一致を優先（既存パスを壊さない）。
##
## 出典: docs/03 §3.3, INC-4 引き継ぎ「freetext の屈折形・古綴表記揺れ対応」。

## 屈折マッチ結果の辞書スキーマ:
##   {
##     "word_id":   String, # 主格基本形の id
##     "case":      String, # "nom" | "acc" | "dat" | "gen" | "" (verb)
##     "number":    String, # "sg" | "pl" | ""
##     "gender":    String, # 形容詞のみ "masculine"|"feminine"|"neuter"、それ以外 ""
##     "mood":      String, # 動詞のみ "inf"|"imp_2sg"|"imp_2pl"|"ind_3sg"、それ以外 ""
##     "resource":  WordResource,
##     "matched_form": String, # 実際に一致した綴り (例: "fjanda")
##     "confidence":   String, # "exact" | "inflected" | "verb_form"
##   }
##
## マッチ失敗時: 空辞書 {} を返す。

## 検査対象キー
const _CASES: Array = ["nom", "acc", "dat", "gen"]
const _NUMBERS: Array = ["sg", "pl"]
const _GENDERS: Array = ["masculine", "feminine", "neuter"]
const _VERB_MOODS: Array = ["inf", "imp_2sg", "imp_2pl", "ind_3sg"]


## 屈折形を逆引き。
##   form_text: ユーザー入力綴り（古綴可、大小区別なし）
##   word_lookup: Callable(word_id: String) -> WordResource
##   known_word_ids: 走査対象の word_id 配列（通常 Lexicon.KNOWN_WORD_IDS）
## 返り値: マッチ結果辞書、なければ {}
static func match_form(form_text: String, word_lookup: Callable, known_word_ids: Array) -> Dictionary:
	if form_text.is_empty() or not word_lookup.is_valid():
		return {}
	var needle: String = Orthography.normalize(form_text)
	if needle.is_empty():
		return {}

	# Pass 1: word_id 完全一致（既存パス、最優先）
	for wid in known_word_ids:
		if Orthography.normalize(String(wid)) == needle:
			var res_exact = word_lookup.call(wid)
			if res_exact is WordResource:
				return {
					"word_id": String(wid),
					"case": "",
					"number": "",
					"gender": "",
					"mood": "",
					"resource": res_exact,
					"matched_form": form_text,
					"confidence": "exact",
				}

	# Pass 2: inflection 表（名詞・形容詞）と verb_forms（動詞）を走査
	for wid in known_word_ids:
		var res = word_lookup.call(wid)
		if not (res is WordResource):
			continue
		var hit: Dictionary = _scan_resource(res, needle)
		if not hit.is_empty():
			hit["word_id"] = String(wid)
			hit["resource"] = res
			hit["matched_form"] = form_text
			return hit

	return {}


## 1 つの WordResource の inflection / verb_forms を走査して一致を探す。
## 内部用。返り値は word_id / resource / matched_form 抜きの部分辞書。
static func _scan_resource(res: WordResource, needle_normalized: String) -> Dictionary:
	# 動詞 (word_class == "effect") は verb_forms を見る（INC-5.1 新規スキーマ）
	if String(res.word_class) == "effect":
		var verb_forms = res.get("verb_forms")
		if typeof(verb_forms) == TYPE_DICTIONARY:
			for mood in _VERB_MOODS:
				if not verb_forms.has(mood):
					continue
				var form: String = String(verb_forms[mood])
				if Orthography.normalize(form) == needle_normalized:
					return {
						"case": "",
						"number": "",
						"gender": "",
						"mood": mood,
						"confidence": "verb_form",
					}
		# verb_forms 未整備の動詞はここで終了（id 完全一致は Pass 1 で拾われる）
		return {}

	# 名詞・形容詞: inflection 表を走査
	if typeof(res.inflection) != TYPE_DICTIONARY:
		return {}

	for number in _NUMBERS:
		if not res.inflection.has(number):
			continue
		var number_paradigm = res.inflection[number]
		if typeof(number_paradigm) != TYPE_DICTIONARY:
			continue

		# 形容詞形式: { gender: { case: form } }
		var is_gendered: bool = false
		for g in _GENDERS:
			if number_paradigm.has(g):
				is_gendered = true
				break

		if is_gendered:
			for gender in _GENDERS:
				if not number_paradigm.has(gender):
					continue
				var gender_paradigm = number_paradigm[gender]
				if typeof(gender_paradigm) != TYPE_DICTIONARY:
					continue
				for c in _CASES:
					if not gender_paradigm.has(c):
						continue
					var form_a: String = String(gender_paradigm[c])
					if Orthography.normalize(form_a) == needle_normalized:
						return {
							"case": c,
							"number": number,
							"gender": gender,
							"mood": "",
							"confidence": "inflected",
						}
		else:
			# 名詞形式: { case: form }
			for c in _CASES:
				if not number_paradigm.has(c):
					continue
				var form_n: String = String(number_paradigm[c])
				if Orthography.normalize(form_n) == needle_normalized:
					return {
						"case": c,
						"number": number,
						"gender": String(res.gender),
						"mood": "",
						"confidence": "inflected",
					}

	return {}
