extends RefCounted
class_name DungeonSeed
## DungeonSeed — マップ生成の決定論的 seed（INC-3 v0.9 新規、09 §2.4）。
##
## 巻き戻しごとに新規生成、同一 seed → 同一マップ（テスト容易性のため）。

var seed_value: int
var loop_index: int
var floor_depth: int


func _init(p_seed: int = 0, p_loop_index: int = 0, p_floor_depth: int = 1) -> void:
	seed_value = p_seed
	loop_index = p_loop_index
	floor_depth = p_floor_depth


## 同じ DungeonSeed 値の RandomNumberGenerator を生成。
func make_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# 階層ごとに state をシフトすることで同 loop 内の階で別マップにする。
	rng.state = seed_value ^ (floor_depth * 1000003)
	return rng
