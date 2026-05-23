extends RefCounted
class_name TileGrid
## TileGrid — FOV（Field of View）計算（INC-3 v0.9 新規、09 §4.1）。
##
## INC-3 暫定: 簡易レイキャスト方式（中心からの全方向にレイを飛ばし、視界を遮るタイルで止める）。
## 影投影 (shadowcasting) は本来の方式だが、INC-3 縦切りでは簡易方式で十分。INC-3.5 以降で最適化。

## 視界半径 radius のタイル集合を計算する。
## 戻り値: Dictionary { Vector2i: true } の集合（in 演算で高速判定するため）。
static func compute_fov(map: MapData, origin: Vector2i, radius: int) -> Dictionary:
	var visible: Dictionary = {}
	visible[origin] = true

	# 円周上のタイルにレイを飛ばす（角度ステップ細かめ、INC-3 暫定値 360 ステップ）
	var angle_steps := 360
	for step in range(angle_steps):
		var angle := step * TAU / angle_steps
		var dx := cos(angle)
		var dy := sin(angle)
		var x := float(origin.x) + 0.5
		var y := float(origin.y) + 0.5
		for r in range(1, radius + 1):
			x += dx
			y += dy
			var tile_pos := Vector2i(int(floor(x)), int(floor(y)))
			# 範囲外で打ち切り
			if tile_pos.x < 0 or tile_pos.x >= map.size.x or tile_pos.y < 0 or tile_pos.y >= map.size.y:
				break
			visible[tile_pos] = true
			# 視界を遮るタイルで打ち切り（壁自体は見えるが、その先は見えない）
			if map.blocks_sight(tile_pos):
				break

	return visible


## マンハッタン距離。
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


## 隣接（マンハッタン距離 1）か。
static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return manhattan(a, b) == 1
