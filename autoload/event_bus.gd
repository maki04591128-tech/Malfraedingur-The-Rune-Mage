extends Node
## EventBus — Global signal hub (Autoload).
## Per 04 §3: ノード間直接参照を避けるためのシグナルハブ。
##
## 不変条件: この autoload は他の autoload を class スコープで参照しない
##           （Godot 4 の autoload parse 順序問題を避けるため）。

# --- 呪文関連 (INC-1+) ---
signal spell_cast_requested(tokens: Array)
signal spell_resolved(cast_result: Resource)
signal lexicon_word_learned(word_id: String, new_comprehension: int)

# --- マップ・移動関連 (INC-3 v0.9 新規, 04 v0.6 / 09 §6) ---
## プレイヤーが 1 タイル移動した。
signal player_moved(from_pos: Vector2i, to_pos: Vector2i, new_facing: int)
## プレイヤーが向きを変えた（移動なし）。
signal player_turned(new_facing: int)
## 視界内に新しい敵が入った（警戒モード切替トリガ）。
signal enemy_in_sight(enemy_data: Dictionary)
## 視界内の敵が全て居なくなった（平時モード切替トリガ）。
signal sight_cleared()
## フロアが変わった（階段で次階 or 巻き戻しで再生成）。
signal floor_changed(new_depth: int, reason: String)  ## reason: "stairs" | "rewind"
## ターン進行（プレイヤー or 敵）。
signal turn_advanced(current_actor: String, turn_index: int)
## 7 日切れまたは死亡で巻き戻し発火。
signal rewind_triggered(reason: String)  ## reason: "death" | "timeout" | "manual"
## Helgrind 踏破でクリア。
signal helgrind_cleared()
