extends Resource
class_name FloorTemplate
## FloorTemplate — Helgrind 1 階分の手続き生成テンプレート（INC-3 v0.9 拡張、05 §5）。
##
## 09 §2 を正典とする。INC-3 暫定で 3 階構造（helgrind_1/2/3）。
## 巻き戻しごとに seed を更新（seed_regenerate_on_rewind=true）、
## 起点部屋の配置はループ間で固定（fixed_start_room=true、09 §2.5）。

@export var id: String = ""
@export var realm: String = "Helgrind"
@export var depth: int = 1

## マップ生成パラメータ
@export var generation_method: String = "rooms_and_corridors"
@export var tile_size: Vector2i = Vector2i(30, 25)  ## INC-3.5 v0.9.5 で 40×30 → 30×25 に縮小（02 §3 INC-3.5 持ち越し）
@export var rooms_min: int = 5
@export var rooms_max: int = 8
@export var room_min_size: Vector2i = Vector2i(5, 4)
@export var room_max_size: Vector2i = Vector2i(10, 8)

## seed ポリシー（09 §2.5）
@export var regenerate_on_rewind: bool = true
@export var fixed_start_room: bool = true

## 配置テーブル
@export var enemy_ids: PackedStringArray = PackedStringArray()
@export var enemy_count: Vector2i = Vector2i(3, 6)  ## min, max
@export var boss_id: String = ""

## タイムリミット参照（01 §3.5、09 §4.2）
@export var time_budget_hint_days: float = 1.0

@export var source: String = "オリジナル"
@export var verified: bool = true


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id.is_empty():
		errors.append("id is required")
	if generation_method != "rooms_and_corridors":
		errors.append("only 'rooms_and_corridors' supported in INC-3")
	if tile_size.x < 20 or tile_size.y < 15:
		errors.append("tile_size too small (got %s)" % str(tile_size))
	if rooms_min < 2:
		errors.append("rooms_min must be >= 2 (start room + stairs room)")
	if rooms_max < rooms_min:
		errors.append("rooms_max must be >= rooms_min")
	return errors
