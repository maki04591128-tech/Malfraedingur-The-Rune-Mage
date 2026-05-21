extends RefCounted
class_name SpellTokenizer
## SpellTokenizer — 呪文パイプラインの最初の段。
##
## 役割: SpellComposer の出力（{word_id, case} 列）と無辞書テキスト経路の両方を、
##       共通の正規化トークン列に揃える（03 §4 の2系統正規化）。
## 出典: 03 §4, 04 §4。
##
## INC-0: 空シェル。実装は INC-1 で。

## SpellComposer 経路の入力をトークン列に変換。
##   inputs: [ {"word_id": "fjandi", "case": "acc"}, ... ]
##   ruleset: GrammarRuleset（無辞書フラグや可用性ゲートの参照に使う想定。INC-1で）
## 返り値: トークン辞書配列。INC-1 で形を確定する。
static func tokenize(inputs: Array, _ruleset: Resource = null) -> Array:
	# INC-0: 入力をそのまま通すだけ。正規化は INC-1 で。
	return inputs.duplicate()


## 無辞書（フルテキスト）経路。生綴りからトークン列に正規化（03 §4）。
##   raw_text: ユーザー入力の素テキスト
## INC-1 で形態素分割・格推定を実装。
static func tokenize_freetext(_raw_text: String, _ruleset: Resource = null) -> Array:
	return []
