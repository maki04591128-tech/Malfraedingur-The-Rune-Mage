extends RefCounted
class_name DungeonGenerator
## DungeonGenerator — 部屋＋通路の seed 駆動生成（INC-3 v0.9 新規、09 §2）。
##
## アルゴリズム（INC-3 暫定）:
##   1. FloorTemplate.rooms_min/max からランダムに N 部屋生成
##   2. 各部屋を非隣接で配置（最大 100 回リトライ）。空き無しなら N を減らして続行
##   3. 部屋を起点部屋（kind="start"）→ 通常 → 階段部屋（kind="stairs"）でラベル付け
##   4. 部屋間を L 字通路で順に繋ぐ（巡回サイクル: room[0] → room[1] → ... → room[N-1]）
##   5. 起点部屋に player_start を、階段部屋に stairs_down を配置
##   6. 敵を enemy_count レンジでランダムに通常部屋へ配置（起点・階段は除外）
##   7. ボスは boss_id が指定されていれば階段部屋に配置（INC-3 暫定: helgrind_3 のみ）

const ROOM_RECT := preload("res://core/map/models/room_rect.gd")
const MAP_DATA := preload("res://core/map/map_data.gd")

const MAX_ROOM_PLACE_RETRIES := 100


## メイン: FloorTemplate + DungeonSeed から MapData を生成。
##   floor_template: FloorTemplate Resource
##   dungeon_seed: DungeonSeed (seed_value, loop_index, floor_depth)
static func generate(floor_template: FloorTemplate, dungeon_seed: DungeonSeed) -> MapData:
	var rng: RandomNumberGenerator
	if dungeon_seed != null:
		rng = dungeon_seed.make_rng()
	else:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var size: Vector2i = floor_template.tile_size
	var map := MAP_DATA.new(size)
	map.depth = floor_template.depth
	map.has_boss = not floor_template.boss_id.is_empty()
	map.boss_id = floor_template.boss_id

	# 1. 部屋数決定
	var target_rooms := rng.randi_range(floor_template.rooms_min, floor_template.rooms_max)

	# 2. 部屋配置
	var rooms: Array = []
	# 起点部屋を fixed_start_room なら左上付近に固定（09 §2.5 精神的アンカー）
	if floor_template.fixed_start_room:
		var start_w := rng.randi_range(floor_template.room_min_size.x, floor_template.room_max_size.x)
		var start_h := rng.randi_range(floor_template.room_min_size.y, floor_template.room_max_size.y)
		var start_room := ROOM_RECT.new(2, 2, start_w, start_h, "start")
		rooms.append(start_room)

	# 残りの部屋
	var attempts := 0
	while rooms.size() < target_rooms and attempts < MAX_ROOM_PLACE_RETRIES * target_rooms:
		attempts += 1
		var w := rng.randi_range(floor_template.room_min_size.x, floor_template.room_max_size.x)
		var h := rng.randi_range(floor_template.room_min_size.y, floor_template.room_max_size.y)
		var x := rng.randi_range(1, max(1, size.x - w - 2))
		var y := rng.randi_range(1, max(1, size.y - h - 2))
		var candidate := ROOM_RECT.new(x, y, w, h, "normal")
		# 既存部屋と非隣接か
		var overlaps := false
		for r in rooms:
			if candidate.overlaps_with_buffer(r, 1):
				overlaps = true
				break
		if not overlaps:
			rooms.append(candidate)

	# 起点部屋が未配置（fixed_start_room=false）なら最初の部屋を start に
	if not floor_template.fixed_start_room and rooms.size() > 0:
		(rooms[0] as RoomRect).kind = "start"

	# 最後の部屋を階段部屋にラベル
	if rooms.size() >= 2:
		(rooms[rooms.size() - 1] as RoomRect).kind = "stairs"

	map.rooms = rooms

	# 3. 部屋の床タイル化
	for r_any in rooms:
		var r: RoomRect = r_any
		for j in range(r.y, r.y + r.h):
			for i in range(r.x, r.x + r.w):
				map.set_tile(Vector2i(i, j), "floor")

	# 4. L 字通路で順番に繋ぐ
	for idx in range(rooms.size() - 1):
		var a: RoomRect = rooms[idx]
		var b: RoomRect = rooms[idx + 1]
		var path := _l_corridor(a.center(), b.center(), rng)
		for p in path:
			map.set_tile(p, "floor")
		map.corridors.append({
			"from_room": idx,
			"to_room": idx + 1,
			"path": path,
		})

	# 5. player_start / stairs_down 配置
	var start_room: RoomRect = null
	var stairs_room: RoomRect = null
	for r_any in rooms:
		var r: RoomRect = r_any
		if r.kind == "start":
			start_room = r
		elif r.kind == "stairs":
			stairs_room = r
	if start_room != null:
		map.player_start_pos = start_room.center()
		map.set_tile(map.player_start_pos, "player_start")
	if stairs_room != null:
		map.stairs_down_pos = stairs_room.center()
		map.set_tile(map.stairs_down_pos, "stairs_down")

	# 6. 敵配置
	var enemy_count := rng.randi_range(floor_template.enemy_count.x, floor_template.enemy_count.y)
	for i in range(enemy_count):
		# 通常部屋からランダム選択（起点・階段は除外）
		var normal_rooms: Array = []
		for r_any in rooms:
			var r: RoomRect = r_any
			if r.kind == "normal":
				normal_rooms.append(r)
		if normal_rooms.is_empty():
			break
		var target_room: RoomRect = normal_rooms[rng.randi_range(0, normal_rooms.size() - 1)]
		var ex := target_room.x + rng.randi_range(0, target_room.w - 1)
		var ey := target_room.y + rng.randi_range(0, target_room.h - 1)
		var enemy_pos := Vector2i(ex, ey)
		# 重複・階段・起点を避ける
		if map.enemy_at(enemy_pos).is_empty() and enemy_pos != map.player_start_pos and enemy_pos != map.stairs_down_pos:
			var enemy_id: String = floor_template.enemy_ids[rng.randi_range(0, max(0, floor_template.enemy_ids.size() - 1))] if floor_template.enemy_ids.size() > 0 else "draugr_lesser"
			map.enemies.append({
				"id": enemy_id,
				"pos": enemy_pos,
				"patrol_target": _random_floor_in_room(target_room, rng),
				"hp": 0,  # 後で EnemyResource からセット
			})

	# 7. ボス配置（階段部屋に置く: 階段の手前で戦う想定、踏破=ボス撃破後）
	if map.has_boss and stairs_room != null:
		var boss_pos := stairs_room.center() + Vector2i(1, 0)
		if not stairs_room.contains(boss_pos):
			boss_pos = stairs_room.center() + Vector2i(-1, 0)
		if stairs_room.contains(boss_pos) and map.enemy_at(boss_pos).is_empty():
			map.enemies.append({
				"id": floor_template.boss_id,
				"pos": boss_pos,
				"patrol_target": boss_pos,
				"hp": 0,
			})

	return map


## L 字通路: a → 中継点 → b。横→縦 or 縦→横 をランダム選択。
static func _l_corridor(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> Array:
	var path: Array = []
	var horizontal_first := rng.randi_range(0, 1) == 0
	if horizontal_first:
		# 横移動 (a.y) → 縦移動 (b.x)
		var x_step := 1 if b.x > a.x else -1
		var i := a.x
		while i != b.x:
			path.append(Vector2i(i, a.y))
			i += x_step
		var y_step := 1 if b.y > a.y else -1
		var j := a.y
		while j != b.y:
			path.append(Vector2i(b.x, j))
			j += y_step
		path.append(b)
	else:
		var y_step := 1 if b.y > a.y else -1
		var j := a.y
		while j != b.y:
			path.append(Vector2i(a.x, j))
			j += y_step
		var x_step := 1 if b.x > a.x else -1
		var i := a.x
		while i != b.x:
			path.append(Vector2i(i, b.y))
			i += x_step
		path.append(b)
	return path


## 部屋内のランダムタイル（巡回目的地用）。
static func _random_floor_in_room(room: RoomRect, rng: RandomNumberGenerator) -> Vector2i:
	var rx := room.x + rng.randi_range(0, room.w - 1)
	var ry := room.y + rng.randi_range(0, room.h - 1)
	return Vector2i(rx, ry)
