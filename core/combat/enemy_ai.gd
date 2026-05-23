extends RefCounted
class_name EnemyAI
## EnemyAI — INC-3 v0.9 新規（09 §5）。
##
## 役割: 巡回・追跡・隣接攻撃の最小 AI。
##   - プレイヤーが視界外 (敵側 sight_radius=4) なら巡回
##   - 視界内なら追跡（pathfinder 経由 BFS）
##   - 隣接 (マンハッタン距離1) なら攻撃（dungeon_view 側で発動、本クラスは移動だけ）
##
## INC-3.5 で拡張: 飛び道具・ボス専用パターン・連携 AI など。

const PATHFINDER = preload("res://core/map/pathfinder.gd")
const TILE_GRID = preload("res://core/map/tile_grid.gd")


## 敵 1 体のターンを処理する。
## map_state は autoload Node（player_pos / map_data を持つ）。
## enemy_db は { id: EnemyResource } の辞書。
static func take_turn(enemy: Dictionary, map_state, enemy_db: Dictionary) -> void:
	if int(enemy.get("hp", 0)) <= 0:
		return
	var enemy_pos: Vector2i = Vector2i(enemy["pos"])
	var player_pos: Vector2i = map_state.player_pos
	var sight_radius := 4
	var behavior := "aggressive"
	var enemy_id := String(enemy["id"])
	if enemy_db.has(enemy_id):
		var er = enemy_db[enemy_id]
		sight_radius = er.sight_radius
		behavior = er.behavior

	# 隣接していたら攻撃（移動はしない、攻撃は dungeon_view 側で発動）
	if TILE_GRID.manhattan(enemy_pos, player_pos) == 1:
		return

	# プレイヤーが視界内か（敵側）
	var dist := TILE_GRID.manhattan(enemy_pos, player_pos)
	var can_see_player := false
	if behavior != "patrol_only" and dist <= sight_radius:
		# 視線判定（マンハッタン距離だけで判定。INC-3.5 で壁越し判定追加）
		can_see_player = true

	if can_see_player:
		# 追跡: BFS で 1 タイル進む
		var next_pos: Vector2i = PATHFINDER.next_step_towards(map_state.map_data, enemy_pos, player_pos)
		if next_pos != enemy_pos and _can_move_to(map_state.map_data, next_pos, enemy_pos):
			enemy["pos"] = next_pos
			# 目的地を player_pos に更新（次ターンも追跡）
			enemy["patrol_target"] = player_pos
		return

	# 巡回: 目的地まで移動。到達したら新規目的地を引く
	var patrol_target: Vector2i = Vector2i(enemy.get("patrol_target", enemy_pos))
	if patrol_target == enemy_pos:
		# 新規目的地: ランダム床タイル（簡易：周辺 6 タイル範囲）
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var attempts := 8
		while attempts > 0:
			var candidate := enemy_pos + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			if map_state.map_data.is_passable(candidate):
				enemy["patrol_target"] = candidate
				patrol_target = candidate
				break
			attempts -= 1
		if attempts == 0:
			return  # 諦め

	var next_step: Vector2i = PATHFINDER.next_step_towards(map_state.map_data, enemy_pos, patrol_target)
	if next_step != enemy_pos and _can_move_to(map_state.map_data, next_step, enemy_pos):
		enemy["pos"] = next_step


## next_pos に敵が居なくて player でもなく passable か。
static func _can_move_to(map_data, next_pos: Vector2i, _from_pos: Vector2i) -> bool:
	if not map_data.is_passable(next_pos):
		return false
	# 他の敵が居ないか
	if not map_data.enemy_at(next_pos).is_empty():
		return false
	return true
