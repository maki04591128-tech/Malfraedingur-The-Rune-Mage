extends Node
## GameState — 1ループ一時状態（Autoload）。
## HP・到達階・世界時間残量・現手番・一時バフ。死亡/巻き戻しで reset される側。
## 不変条件（04 §3）: 死亡処理は GameState のみ初期化し Lexicon に触れない。
##
## INC-3 v0.9: 7 日ループ・世界時間予算・階層進行を本格化。

const LOOP_WORLD_TIME_BUDGET := 168.0    ## 7 日抽象単位（05 v0.9 BalanceConfig）
const PLAYER_MAX_HP := 100

var hp: int = PLAYER_MAX_HP
var floor_index: int = 1                  ## 1〜3（INC-3 暫定 3 階）
var world_time_remaining: float = LOOP_WORLD_TIME_BUDGET
var current_turn: int = 0
var loop_count: int = 0                   ## 何回目のループか（巻き戻し累計）


## ループ開始状態へ戻す（Lexicon には触らない）。
func reset() -> void:
	hp = PLAYER_MAX_HP
	floor_index = 1
	world_time_remaining = LOOP_WORLD_TIME_BUDGET
	current_turn = 0
	loop_count += 1


## 世界時間を消費。0 以下になったら巻き戻しトリガを返す（呼び側で EventBus に流す）。
## 戻り値: true なら巻き戻し条件成立。
func advance_world_time(delta: float) -> bool:
	world_time_remaining = max(0.0, world_time_remaining - delta)
	return world_time_remaining <= 0.0


## ダメージ。HP <= 0 なら巻き戻し条件成立を返す。
func take_damage(amount: int) -> bool:
	hp = max(0, hp - amount)
	return hp <= 0


## 階層進行。
func descend_floor() -> void:
	floor_index += 1


## デバッグ表示用。
func get_status_summary() -> String:
	return "Loop %d / Floor %d / HP %d / Time %.1f" % [loop_count, floor_index, hp, world_time_remaining]
