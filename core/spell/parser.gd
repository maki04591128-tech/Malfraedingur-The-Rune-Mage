extends RefCounted
class_name SpellParser
## SpellParser — トークン列を SpellAST（呪文の抽象構文木）に変換。
##
## 役割: 03 §4 のパース段。語の役割（effect/target/element/modifier...）と
##       構文的な親子関係を確定する。
## 出典: 03 §3.1, §4, 04 §4。
##
## INC-1: 効果語/対象語/属性語の役割分類まで。修飾・範囲・条件はストレッチ（§6.2）。

## トークン列 → SpellAST（辞書形）。
##   tokens: Tokenizer の出力 [{word_id, case, resource}, ...]
## 返り値:
##   {
##     "tokens": [...],
##     "effect": Token or null,
##     "target": Token or null,
##     "elements": [Token, ...],
##     "modifiers": [Token, ...],   // INC-1 未使用（ストレッチ）
##     "word_order": [String, ...]  // word_class の出現順（語順ボーナス判定用）
##   }
static func parse(tokens: Array) -> Dictionary:
	var effect = null
	var target = null
	var elements: Array = []
	var modifiers: Array = []
	var word_order: Array = []

	for tok in tokens:
		var res: WordResource = tok.get("resource", null)
		if res == null:
			# 解決できなかったトークンは word_order に "?" で記録するに留める。
			word_order.append("?")
			continue
		word_order.append(res.word_class)
		match res.word_class:
			"effect":
				if effect == null:
					effect = tok
			"target":
				if target == null:
					target = tok
			"element":
				elements.append(tok)
			"modifier":
				modifiers.append(tok)
			_:
				# range / conditional / numeral / time_unit / suffix は INC-1 では未使用。
				pass

	return {
		"tokens": tokens.duplicate(),
		"effect": effect,
		"target": target,
		"elements": elements,
		"modifiers": modifiers,
		"word_order": word_order,
	}
