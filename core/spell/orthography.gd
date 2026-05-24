extends RefCounted
class_name Orthography
## Orthography — 古ノルド語の表記揺れを ASCII 互換形に正規化するヘルパ。
##
## 役割（INC-5.1 / 03 §3.3 末尾「古綴表記揺れ対応」）:
##   - ユーザーが古綴で入力（meiða / sjálfr / fjárri / hœgri）してもエンジン側と照合できるよう、
##     入力と辞書 inflection 表値の両側で同じ正規化を通す。
##   - WordResource.id は ASCII 互換綴り（meida / sjalfr / fjarri / hoegri）を正典とし、
##     プレイヤー入力に α/Á/Æ/Ǽ/Œ/Ø/Ð/Þ が混じったら本ヘルパが受け止める。
##
## 不変条件:
##   - 大文字小文字を無視する（lowercase 化）。
##   - 結果は ASCII printable のみ（a-z, 0-9, 空白, : 等）。
##   - 既に ASCII の文字列は idempotent（normalize(normalize(x)) == normalize(x)）。
##
## 出典: docs/03 §3.3「動詞活用・複数形対応・強弱変化クラス分類等は INC-5 監修フェーズ」、
##       INC-4 引き継ぎ「freetext の屈折形・古綴表記揺れ対応」。

## 単一文字 / 多重音マッピング表。
## key: 古綴の Unicode 1 文字（既に lowercase 想定）
## value: ASCII 互換綴り（1 文字または 2 文字）
const _MAP: Dictionary = {
	# 母音アクセント記号 → 素母音
	"á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ý": "y",
	"à": "a", "è": "e", "ì": "i", "ò": "o", "ù": "u",
	"ä": "a", "ë": "e", "ï": "i", "ö": "o", "ü": "u",
	# 連字
	"æ": "ae", "ǽ": "ae",
	"œ": "oe", "ø": "oe",  # ø は古ノルド語では oe 系統
	# 摩擦音
	"ð": "d",   # eth → d（meiða → meida）
	"þ": "th",  # thorn → th
	# その他北欧字
	"å": "a",
	"ß": "ss",
}


## 文字列を ASCII 正規化形に変換。
##   text: 任意の Unicode 文字列
## 返り値: lowercase + 古綴展開済みの ASCII 文字列
##         （アクセント・æ・œ・ð・þ を ASCII 互換に展開）
static func normalize(text: String) -> String:
	if text.is_empty():
		return ""
	var lower: String = text.to_lower()
	var out: String = ""
	for i in lower.length():
		var ch: String = lower.substr(i, 1)
		if _MAP.has(ch):
			out += String(_MAP[ch])
		else:
			out += ch
	return out


## 2 つの綴りが正規化後に等しいか。
##   a, b: 比較する文字列
## 返り値: 正規化後一致なら true
static func equals(a: String, b: String) -> bool:
	return normalize(a) == normalize(b)
