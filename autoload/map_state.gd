extends Node
## MapState — 現階層のマップ実体・プレイヤー位置・向き・FOV を保持する Autoload。
## INC-3 v0.9 新規（04 v0.6 §3 / 09 §3〜§6）。
##
## 不変条件:
##   - MapData は Lexicon に保存しない（ループ一時状態、04 v0.6 §7）。
##   - reset() で破棄、DungeonGenerator が新規 seed で再生成。
##   - 巻き戻しで起点部屋のみ位置・寸法をループ間で固定（fixed_start_room=true、09 §2.5）。

const TILE_GRID := preload("res://core/map/tile_grid.gd")
const PATHFINDER := preload("res://core/map/pathfinder.gd")
const DUNGEON_GENERATOR := preload("res://core/map/dungeon_generator.gd")
const DUNGEON_SEED := preload("res://core/map/models/dungeon_seed.gd")

## 向き定数（時計回り、北 = 0）
const FACING_NORTH := 0
const FACING_EAST := 1
const FACING_SOUTH := 2
const FACING_WEST := 3

## 4 方向移動ベクトル
const FACING_VECTORS := {
	FACING_NORTH: Vector2i( 0, -1),
	FACING_EAST:  Vector2i( 1,  0),
	FACING_SOUTH: Vector2i( 0,  1),
	FACING_WEST:  Vector2i(-1,  0),
}

const FOV_RADIUS_PLAYER := 8   ## 05 v0.9 BalanceConfig.fov.radius_player

var map_data: MapData = null
var player_pos: Vector2i = Vector2i(-1, -1)
var player_facing: int = FACING_NORTH
var fov_cache: Dictionary = {}        ## { Vector2i: true }
var fov_explored: Dictionary = {}     ## { Vector2i: true } 既知タイル（暗いグレー表示用）
var enemies_in_sight_cache: Array = []   ## 前フレームで視認している敵 ID（変化検知用）


## マップを再生成して状態を初期化（ループ開始 or 階段で次階）。
func load_floor(floor_template, dungeon_seed) -> void:
	map_data = DUNGEON_GENERATOR.generate(floor_template, dungeon_seed)
	player_pos = map_data.player_start_pos
	player_facing = FACING_NORTH
	fov_cache = {}
	fov_explored = {}
	enemies_in_sight_cache = []
	_recompute_fov()


## ループ巻き戻しでマップを破棄（次の load_floor を待つ）。
func reset() -> void:
	map_data = null
	player_pos = Vector2i(-1, -1)
	player_facing = FACING_NORTH
	fov_cache.clear()
	fov_explored.clear()
	enemies_in_sight_cache.clear()


## プレイヤー移動。成功すれば true、壁などで失敗すれば false。
## 戻り値が true でも、enemy へのぶつかりは false 扱い（隣接で詠唱する仕様、09 §4.3）。
func move_player(dx: int, dy: int) -> bool:
	if map_data == null:
		return false
	var new_pos := player_pos + Vector2i(dx, dy)
	if not map_data.is_passable(new_pos):
		return false
	if not map_data.enemy_at(new_pos).is_empty():
		# 敵のいるタイルには進めない（向きだけ更新）
		_update_facing_from_delta(Vector2i(dx, dy))
		return false
	var old_pos := player_pos
	player_pos = new_pos
	_update_facing_from_delta(Vector2i(dx, dy))
	_recompute_fov()
	EventBus.player_moved.emit(old_pos, new_pos, player_facing)
	_check_sight_change()
	return true


## 向きだけ変更（移動なし、Δ=0）。
func turn_player(new_facing: int) -> void:
	if new_facing < 0 or new_facing > 3:
		return
	if new_facing == player_facing:
		return
	player_facing = new_facing
	EventBus.player_turned.emit(player_facing)
	# 旋回は FOV を変えない（INC-3 暫定: 全周視界、向きは方向語のみに影響）


## プレイヤーが指定位置を視認できるか。
func is_visible(pos: Vector2i) -> bool:
	return pos in fov_cache


## 視界内の敵リストを返す。
func enemies_in_sight() -> Array:
	if map_data == null:
		return []
	var result: Array = []
	for e in map_data.enemies:
		if int(e.get("hp", 0)) > 0 and Vector2i(e["pos"]) in fov_cache:
			result.append(e)
	return result


## プレイヤーの向きに相対方向 axis を適用してベクトルを返す。
##   axis: "forward" | "backward" | "left" | "right"
## 09 §7.2 / 03 v0.18 附録 A.8。
func get_relative_direction_vector(axis: String) -> Vector2i:
	var rel_offset := 0
	match axis:
		"forward":  rel_offset = 0
		"right":    rel_offset = 1
		"backward": rel_offset = 2
		"left":     rel_offset = 3
		_: return Vector2i.ZERO
	var resolved_facing := (player_facing + rel_offset) % 4
	return FACING_VECTORS[resolved_facing]


## 最隣接敵（マンハッタン距離最小）を返す。視界内のみ。
func nearest_enemy_in_sight() -> Dictionary:
	var enemies := enemies_in_sight()
	if enemies.is_empty():
		return {}
	var best: Dictionary = enemies[0]
	var best_dist := TILE_GRID.manhattan(player_pos, Vector2i(best["pos"]))
	for e in enemies:
		var d := TILE_GRID.manhattan(player_pos, Vector2i(e["pos"]))
		if d < best_dist:
			best = e
			best_dist = d
	return best


## プレイヤーが階段上に居るか（次階遷移トリガ）。
func is_player_on_stairs() -> bool:
	if map_data == null:
		return false
	return map_data.is_stairs_down(player_pos)


# --- 内部 ---

func _recompute_fov() -> void:
	if map_data == null:
		return
	fov_cache = TILE_GRID.compute_fov(map_data, player_pos, FOV_RADIUS_PLAYER)
	for k in fov_cache:
		fov_explored[k] = true


func _update_facing_from_delta(delta: Vector2i) -> void:
	# v0.9.3 (要求 7): 斜め移動対応。縦方向優先で向きを決める。
	# (1, 1) → 南、(1, -1) → 北、(1, 0) → 東 のように。
	if delta.y < 0:
		player_facing = FACING_NORTH
	elif delta.y > 0:
		player_facing = FACING_SOUTH
	elif delta.x > 0:
		player_facing = FACING_EAST
	elif delta.x < 0:
		player_facing = FACING_WEST


func _check_sight_change() -> void:
	var current := enemies_in_sight()
	if current.size() > enemies_in_sight_cache.size():
		# 新しい敵が視界に入った
		for e in current:
			var found := false
			for prev in enemies_in_sight_cache:
				if Vector2i(prev["pos"]) == Vector2i(e["pos"]) and String(prev["id"]) == String(e["id"]):
					found = true
					break
			if not found:
				EventBus.enemy_in_sight.emit(e)
	elif current.is_empty() and not enemies_in_sight_cache.is_empty():
		EventBus.sight_cleared.emit()
	enemies_in_sight_cache = current.duplicate(true)
