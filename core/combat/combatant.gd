extends RefCounted
class_name Combatant
## Combatant — 戦闘エンティティの最小データ＋振る舞い（Player/Enemy 共通）。
##
## 役割: HP/最大HP/表示名/属性耐性 を持ち、ダメージ適用と生死判定を提供する。
## 出典: 08 §1.1 / 01 §3.8。INC-2 v0.1 では Resource 化せず RefCounted。
##
## 不変条件:
##   - hp は 0..max_hp に常に clamp。
##   - take_damage(0) や heal(0) は副作用ゼロ（NOP）。
##   - element_resist が無い属性は倍率 1.0（無効化しない）。

## 表示名（UI ログ用）。
var display_name: String = ""

## 最大 HP。
var max_hp: float = 100.0

## 現在 HP。
var hp: float = 100.0

## 属性耐性。{ "fire": 0.5, "water": 1.5, ... } のような乗算辞書。
## 無い属性は 1.0。
var element_resist: Dictionary = {}

## INC-2 では未使用だが、Boss の AI パターン切替などに使う予定（v0.2 で活用）。
var tags: Array = []


func _init(p_name: String = "", p_max_hp: float = 100.0, p_resist: Dictionary = {}) -> void:
	display_name = p_name
	max_hp = p_max_hp
	hp = p_max_hp
	element_resist = p_resist.duplicate(true)


## 与ダメ。負値や 0 は NOP。実際に削れた量を返す。
func take_damage(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := hp
	hp = clampf(hp - amount, 0.0, max_hp)
	return before - hp


## 回復。負値や 0 は NOP。実際に回復した量を返す。
func heal(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := hp
	hp = clampf(hp + amount, 0.0, max_hp)
	return hp - before


func is_alive() -> bool:
	return hp > 0.0


## 属性倍率を取得。未定義は 1.0。
func resist_mult_for(element: String) -> float:
	if element == "":
		return 1.0
	return float(element_resist.get(element, 1.0))


## 現在 HP の比率（0..1）。HP バー表示用。
func hp_ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)
