extends Resource
class_name SpatialContext
## SpatialContext — 詠唱時の空間情報スナップショット（INC-3 v0.9 新規、04 v0.6 §4 / 09 §6）。
##
## SpellEngine.cast() に options["spatial_context"] として渡され、SpatialResolver が
## 範囲語・方向語から対象タイル集合 T を計算する元データになる。INC-3 では最小実装
## （タイル指定なし=最隣接敵自動）、INC-3.5 で本格化。

@export var player_pos: Vector2i = Vector2i(-1, -1)
@export var player_facing: int = 0           ## MapState.FACING_*
@export var visible_tiles: Dictionary = {}    ## { Vector2i: true } FOV
@export var enemies: Array = []               ## [{ "id": String, "pos": Vector2i, "hp": int }, ...]
@export var map_size: Vector2i = Vector2i(0, 0)

## map_data のタイル種別取得関数（範囲外と壁判定のため、Callable）。
## INC-3 では _wall_lookup で簡易関数を渡す。
var wall_lookup: Callable = Callable()


## MapState からスナップショットを生成。
static func from_map_state(map_state) -> SpatialContext:
	var ctx := SpatialContext.new()
	if map_state == null or map_state.map_data == null:
		return ctx
	ctx.player_pos = map_state.player_pos
	ctx.player_facing = map_state.player_facing
	ctx.visible_tiles = map_state.fov_cache.duplicate()
	ctx.map_size = map_state.map_data.size
	# 視界内の生存敵だけ
	var enemies: Array = []
	for e in map_state.map_data.enemies:
		if int(e.get("hp", 0)) > 0:
			enemies.append({
				"id": String(e["id"]),
				"pos": Vector2i(e["pos"]),
				"hp": int(e["hp"]),
			})
	ctx.enemies = enemies
	# wall_lookup
	var md = map_state.map_data
	ctx.wall_lookup = Callable(md, "blocks_sight")
	return ctx


## 最隣接敵を取得（視界内・マンハッタン距離最小）。
func nearest_enemy_in_sight() -> Dictionary:
	var best: Dictionary = {}
	var best_dist := 999999
	for e in enemies:
		if not (Vector2i(e["pos"]) in visible_tiles):
			continue
		var d: int = abs(Vector2i(e["pos"]).x - player_pos.x) + abs(Vector2i(e["pos"]).y - player_pos.y)
		if d < best_dist:
			best = e
			best_dist = d
	return best
