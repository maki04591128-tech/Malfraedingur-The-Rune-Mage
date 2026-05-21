extends Resource
class_name ResolvedEffect
## ResolvedEffect — 制御精度適用後の最終効果（ばらつき/暴発/対象ズレ確定）。
##
## 役割: Resolver の出力。Player/Enemy にダメージ適用する直前の確定値。
## 出典: 04 §4 / 03 §5.2・§5.3（暴発確率 = clamp(0.10 - 0.001*C, 0, 0.10)、重篤度バンド）。
##
## INC-0: 空シェル。値は INC-1 で Resolver が seed 固定で計算。

## 最終威力（暴発時は category に応じて変動）。
@export var effect_power: float = 0.0

## 効果対象の語ID（target_shift などで EffectSpec から変わり得る）。
@export var target_word_id: String = ""

## 暴発したか。
@export var misfired: bool = false

## 暴発カテゴリ（03 §5.3 のバンド境界）:
##   ""           : 暴発なし
##   "activation" : C≤30 — fizzle / collapse
##   "execution"  : C 31..60 — target_shift / power_drop / halve_or_misrange
##   "control"    : C 61..99 — self_damage / effect_reversal / recoil
@export var misfire_category: String = ""

## 暴発カテゴリ内の具体的アウトカム（"fizzle" / "self_damage" 等）。
@export var misfire_outcome: String = ""

## 自爆ダメージ（control バンドの self_damage 用、ティア比例）。
@export var self_damage: float = 0.0

## variance/jitter 起因の係数（成功時の軽微なゆらぎ、03 §5.4）。1.0 = ゆらぎなし。
@export var variance_mult: float = 1.0
