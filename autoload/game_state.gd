extends Node
## GameState — 1ループ一時状態（Autoload）。
## HP・到達階・世界時間残量・現手番・一時バフ。死亡/巻き戻しで reset される側。
## 不変条件（04 §3）: 死亡処理は GameState のみ初期化し Lexicon に触れない。
## INC-0: 空シェル。

# var hp: int = 0
# var floor_index: int = 0
# var world_time_remaining: float = 0.0
# var current_turn: int = 0

# func reset() -> void:
#     # ループ開始状態へ戻す。Lexicon には触らない。
#     pass

# func advance_world_time(delta: float) -> void:
#     pass
