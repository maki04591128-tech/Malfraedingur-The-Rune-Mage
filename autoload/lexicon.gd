extends Node
## Lexicon — 永続語彙＋文法進行（Autoload）。
## 永続: user://lexicon.save に保存。死亡時 reset されない（テーマ「知識は残る」の保証点）。
## スキーマ詳細は 04 §3 / 05_データ定義テンプレート.md を参照。
## INC-0: 空シェル。

# var comprehension: Dictionary = {}        # word_id (String) -> int (0..100)
# var grammar_progress: Dictionary = {}     # { phase, scaffold_level, unlocked_constructs }

# func save_to_disk() -> void:
#     pass

# func load_from_disk() -> void:
#     pass
