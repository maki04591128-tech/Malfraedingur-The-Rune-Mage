extends Resource
class_name EffectSpec
## EffectSpec — 呪文の効果記述（評価フェーズの出力）。
##
## 役割: Evaluator が出す「制御精度適用前」の効果。
## 出典: 04 §4 / 03 §5（数式は INC-1 実装、シェルは INC-0）。
##
## INC-0: 空シェル。値は INC-1 で Evaluator が計算。

## 効果種別。"damage" | "heal" | "buff" | "debuff" | "move" | "none" 等。
## 詳細は 03 附録A の効果語クラスに従う。
@export var kind: String = ""

## 構成語の合計ティア（= 期待威力 P_base の主成分）。03 §5.1。
@export var tier_sum: int = 0

## 期待威力（成功時威力天井 P_base）。語順ボーナス込み。
@export var p_base: float = 0.0

## 効果対象の語ID（acc 格で参照された語）。なければ空。
@export var target_word_id: String = ""

## 元素属性ID（あれば）。なければ空。
@export var element_word_id: String = ""

## 修飾/範囲/条件などの拡張ペイロード（INC-2 以降で増える）。
@export var modifiers: Dictionary = {}
