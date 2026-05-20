extends Node
## EventBus — Global signal hub (Autoload).
## Per 04 §3: ノード間直接参照を避けるためのシグナルハブ。
## INC-0: 空シェル。シグナル定義は INC-1 以降で追加。
##
## 不変条件: この autoload は他の autoload を class スコープで参照しない
##           （Godot 4 の autoload parse 順序問題を避けるため）。

# 将来のシグナル例（INC-1 で有効化）:
# signal spell_cast_requested(tokens: Array)
# signal spell_resolved(cast_result: Resource)
# signal lexicon_word_learned(word_id: String, new_comprehension: int)
