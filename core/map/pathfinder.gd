extends RefCounted
class_name Pathfinder
## Pathfinder — BFS 最短経路探索（INC-3 v0.9 新規、09 §5 敵 AI 用）。
##
## INC-3 暫定: シンプル BFS（4 方向）。マンハッタン距離ベース、敵密度が低いので十分。
## INC-3.5 以降で必要なら A* に置き換え可能。

## start から goal までの最短経路（Vector2i 列）を返す。
## start も goal も含まれる。経路がなければ空配列。
## map の passable タイルのみ通過可能。enemies は無視（味方の隣接を経路扱いするか否かは呼び側）。
static func find_path(map: MapData, start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return [start]
	if not map.is_passable(start) and start != map.player_start_pos:
		return []
	if not map.is_passable(goal):
		return []

	var directions := [
		Vector2i( 1,  0),
		Vector2i(-1,  0),
		Vector2i( 0,  1),
		Vector2i( 0, -1),
	]

	var visited: Dictionary = {start: null}  ## key=Vector2i, value=前タイル（最初は null）
	var queue: Array = [start]

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			# 経路を逆順に再構築
			var path: Array = []
			var p = goal
			while p != null:
				path.push_front(p)
				p = visited[p]
			return path

		for d in directions:
			var next_pos: Vector2i = current + d
			if next_pos in visited:
				continue
			if not map.is_passable(next_pos) and next_pos != goal:
				continue
			visited[next_pos] = current
			queue.push_back(next_pos)

	return []  # 到達不能


## start から goal へ向かう次の 1 タイル（敵 AI 用）。経路がなければ start を返す。
static func next_step_towards(map: MapData, start: Vector2i, goal: Vector2i) -> Vector2i:
	var path := find_path(map, start, goal)
	if path.size() >= 2:
		return path[1]
	return start
