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

## 向きベクトルテーブル（MapState.FACING_VECTORS と一致、独立性のためローカル定義）。
const FACING_VECTORS_LOCAL := {
	0: Vector2i( 0, -1),  # NORTH
	1: Vector2i( 1,  0),  # EAST
	2: Vector2i( 0,  1),  # SOUTH
	3: Vector2i(-1,  0),  # WEST
}


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
## INC-3 v0.9.1 までは詠唱対象選択にこれを使っていたが、v0.9.2 で扇状版を採用。
## 後方互換のため残す（test_smoke / 将来の対象指定 UI 等で利用可能）。
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


## 扇状範囲内の最隣接敵を取得（INC-3 v0.9.2 新規）。
##   half_angle_deg: 向き軸からの片側角度（既定 45° → 全 90° の扇）
## プレイヤーの向きベクトルと「プレイヤー→敵」ベクトルの内積で角度判定。
## 内積 / (両ベクトルの長さ) = cos(角度)、cos(half_angle_deg) 以上で扇内。
##   - half_angle_deg=45  → cos=0.7071、扇の総開度 90°
##   - half_angle_deg=90  → cos=0、扇の総開度 180°（前方半円）
##   - half_angle_deg=180 → cos=-1、全方位（nearest_enemy_in_sight と等価）
## 視界外の敵は除外。プレイヤーと同タイルの敵は対象外。
func nearest_enemy_in_arc(half_angle_deg: float = 45.0) -> Dictionary:
	var forward_vec: Vector2i = FACING_VECTORS_LOCAL.get(player_facing, Vector2i(0, -1))
	var cos_threshold: float = cos(deg_to_rad(half_angle_deg))
	var best: Dictionary = {}
	var best_dist: int = 999999
	for e in enemies:
		var epos: Vector2i = Vector2i(e["pos"])
		if not (epos in visible_tiles):
			continue
		var to_enemy: Vector2i = epos - player_pos
		if to_enemy == Vector2i.ZERO:
			continue
		# 内積で角度判定（forward と to_enemy のなす角の cos）
		var dot_val: float = float(to_enemy.x * forward_vec.x + to_enemy.y * forward_vec.y)
		var to_enemy_len: float = sqrt(float(to_enemy.x * to_enemy.x + to_enemy.y * to_enemy.y))
		var forward_len: float = sqrt(float(forward_vec.x * forward_vec.x + forward_vec.y * forward_vec.y))
		if to_enemy_len == 0.0 or forward_len == 0.0:
			continue
		var cos_angle: float = dot_val / (to_enemy_len * forward_len)
		if cos_angle < cos_threshold:
			continue  # 扇外
		# マンハッタン距離で最近敵選択
		var d: int = abs(to_enemy.x) + abs(to_enemy.y)
		if d < best_dist:
			best = e
			best_dist = d
	return best
