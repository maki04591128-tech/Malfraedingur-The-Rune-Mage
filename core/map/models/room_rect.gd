extends RefCounted
class_name RoomRect
## RoomRect — ダンジョン部屋の矩形領域（INC-3 v0.9 新規、09 §2/§3）。
##
## (x, y) は左上、(w, h) は幅・高さ。座標系は 09 §3.1 に従う（原点左上、x:右、y:下）。
## kind: "start" | "stairs" | "normal"（09 §2.2 起点部屋・階段部屋・通常部屋）

var x: int
var y: int
var w: int
var h: int
var kind: String  ## "start" | "stairs" | "normal"


func _init(p_x: int = 0, p_y: int = 0, p_w: int = 0, p_h: int = 0, p_kind: String = "normal") -> void:
	x = p_x
	y = p_y
	w = p_w
	h = p_h
	kind = p_kind


## 部屋の中心タイル座標。
func center() -> Vector2i:
	return Vector2i(x + w / 2, y + h / 2)


## 部屋内の任意タイル群を返す。
func interior_tiles() -> Array:
	var tiles: Array = []
	for j in range(y, y + h):
		for i in range(x, x + w):
			tiles.append(Vector2i(i, j))
	return tiles


## 他の部屋と重なるか（境界 1 タイル分のバッファ込み、09 §2.1 非隣接）。
func overlaps_with_buffer(other: RoomRect, buffer: int = 1) -> bool:
	return (x - buffer < other.x + other.w + buffer
		and x + w + buffer > other.x - buffer
		and y - buffer < other.y + other.h + buffer
		and y + h + buffer > other.y - buffer)


## このタイルが部屋内か。
func contains(pos: Vector2i) -> bool:
	return pos.x >= x and pos.x < x + w and pos.y >= y and pos.y < y + h
