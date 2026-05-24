extends RefCounted
class_name MapData
## MapData — 1 階分のマップ実体（INC-3 v0.9 新規、09 §3 / 05 §10）。
##
## DungeonGenerator が FloorTemplate + DungeonSeed から構築する。
## Lexicon に保存しない（ループ一時状態）。巻き戻しで破棄。

var size: Vector2i                              ## マップ全体のタイル寸法
var tiles: Array = []                           ## 2D 配列 tiles[y][x] = TileKind.id 文字列
var rooms: Array = []                           ## [RoomRect, ...]
var corridors: Array = []                       ## [{ "from_room": int, "to_room": int, "path": [Vector2i,...] }, ...]
var stairs_down_pos: Vector2i = Vector2i(-1, -1)
var player_start_pos: Vector2i = Vector2i(-1, -1)
var enemies: Array = []                         ## [{ "id": String, "pos": Vector2i, "patrol_target": Vector2i, "hp": int }, ...]
var has_boss: bool = false                      ## このフロアでボス出現するか
var boss_id: String = ""                        ## ボス ID（has_boss=true のとき）
var depth: int = 1                              ## 階層番号（1, 2, 3...）

## INC-4 B-2: 学習スポット。 [ { "pos": Vector2i, "word_id": String, "consumed": bool }, ... ]
## consumed=true なら 1 度使用済み（同一ループで再学習不可、巻き戻しで再生成）。
var study_spots: Array = []

## INC-4 B-3: 碑文タイル。 [ { "pos": Vector2i, "inscription_id": String, "solved": bool }, ... ]
## solved=true なら翻訳済み（再表示しない、巻き戻しで再配置）。
var inscriptions: Array = []


func _init(p_size: Vector2i) -> void:
	size = p_size
	# tiles を全部 "wall" で初期化（生成時に部屋・通路を "floor" に上書き）
	tiles.clear()
	for y in range(size.y):
		var row: Array = []
		for x in range(size.x):
			row.append("wall")
		tiles.append(row)


## 範囲チェック付きタイル取得。範囲外は "wall" として扱う（衝突計算簡略化）。
func get_tile(pos: Vector2i) -> String:
	if pos.x < 0 or pos.x >= size.x or pos.y < 0 or pos.y >= size.y:
		return "wall"
	return tiles[pos.y][pos.x]


## 範囲チェック付きタイル設定。範囲外は無視。
func set_tile(pos: Vector2i, tile_id: String) -> void:
	if pos.x < 0 or pos.x >= size.x or pos.y < 0 or pos.y >= size.y:
		return
	tiles[pos.y][pos.x] = tile_id


## passable 判定（衝突計算用）。INC-4: study_spot / inscription も通行可。
func is_passable(pos: Vector2i) -> bool:
	var t := get_tile(pos)
	return t == "floor" or t == "stairs_down" or t == "player_start" \
		or t == "study_spot" or t == "inscription"


## INC-4 B-2: 指定位置の学習スポットを取得。未消費のものを優先（同位置に複数想定なし）。
func study_spot_at(pos: Vector2i) -> Dictionary:
	for s in study_spots:
		if Vector2i(s.get("pos", Vector2i.ZERO)) == pos:
			return s
	return {}


## INC-4 B-3: 指定位置の碑文を取得。
func inscription_at(pos: Vector2i) -> Dictionary:
	for ins in inscriptions:
		if Vector2i(ins.get("pos", Vector2i.ZERO)) == pos:
			return ins
	return {}


## blocks_sight 判定（FOV 用）。
func blocks_sight(pos: Vector2i) -> bool:
	return get_tile(pos) == "wall"


## 敵がそのタイルに居るか。
func enemy_at(pos: Vector2i) -> Dictionary:
	for e in enemies:
		if Vector2i(e["pos"]) == pos and int(e.get("hp", 0)) > 0:
			return e
	return {}


## 階段タイルの位置か。
func is_stairs_down(pos: Vector2i) -> bool:
	return pos == stairs_down_pos
