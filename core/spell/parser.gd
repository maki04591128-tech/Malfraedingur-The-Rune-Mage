extends RefCounted
class_name SpellParser
## SpellParser — トークン列を SpellAST（呪文の抽象構文木）に変換。
##
## 役割: 03 §4 のパース段。語の役割（effect/target/element/modifier...）と
##       構文的な親子関係を確定する。
## 出典: 03 §4, 04 §4。
##
## INC-0: 空シェル。AST 形は INC-1 で固める。

## トークン列 → SpellAST（辞書形）。
##   tokens: Tokenizer の出力
## 返り値（INC-1 で詳細化）:
##   { "effect": {...}, "target": {...}, "elements": [...], "modifiers": [...], "word_order": [...] }
static func parse(tokens: Array) -> Dictionary:
	# INC-0: 構造化せずトークン列だけ詰めて返す。
	return {
		"tokens": tokens.duplicate(),
		"effect": null,
		"target": null,
		"elements": [],
		"modifiers": [],
		"word_order": [],
	}
