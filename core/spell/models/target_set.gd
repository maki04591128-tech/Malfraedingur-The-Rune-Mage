extends Resource
class_name TargetSet
## TargetSet — SpatialResolver の出力（INC-3 v0.9 新規、04 v0.6 §4 / 09 §7.4）。
##
## 詠唱の対象タイル集合 T と対象敵 ID 列。射程外/視界外/壁の向こうで T が空なら
## reachable=false で「届かない」finding を呼び側が追加できる。

## 対象タイル列。AoE では複数、隣接単体では 1 個。
@export var target_tiles: Array = []   ## [Vector2i, ...]

## 対象敵 ID 列（target_tiles と対応）。空タイルなら "" を入れる。
@export var target_enemy_ids: PackedStringArray = PackedStringArray()

## 中心位置（AoE 中心・貫通起点）。
@export var center_pos: Vector2i = Vector2i(-1, -1)

## 詠唱が「届く」か（射程内に対象が存在し、壁等で遮られていない）。
@export var reachable: bool = true

## 解釈に使った範囲語・方向語 ID（デバッグ表示用）。
@export var used_range_word: String = ""
@export var used_direction_word: String = ""

## INC-3 では minor finding にとどめる範囲語/方向語の解釈失敗理由を記録。
##   例: { "range_required": "射程外", "direction_required": "方向未指定" }
@export var advisory_findings: Dictionary = {}

## INC-3.5 v0.9.5 新規: コア違反扱いの finding。SpellEngine が grammar_report.findings に
## マージし、overall_pass / g_score / 暴発倍率に乗せる。各要素は Validator._build_finding() と
## 同じ辞書形式（rule / pass / severity / reason / recommended）。
@export var core_findings: Array = []


## 何も対象がない（射程外・視界に敵なし）か。
func is_empty() -> bool:
	return target_tiles.is_empty()


## デバッグ表示用。
func summary() -> String:
	if is_empty():
		return "no targets"
	var parts: Array = []
	for i in range(target_tiles.size()):
		var pos: Vector2i = target_tiles[i]
		var eid: String = target_enemy_ids[i] if i < target_enemy_ids.size() else ""
		parts.append("(%d,%d:%s)" % [pos.x, pos.y, eid])
	return ", ".join(parts)
