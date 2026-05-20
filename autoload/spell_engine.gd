extends Node
## SpellEngine — 呪文パイプライン Facade（Autoload）。
## API: cast(word_ids: Array[String], ruleset: Resource) -> CastResult
## パイプライン: Tokenizer → Parser → Validator → Evaluator → Resolver（04 §4）。
## 物語固定詠唱 `öld renna aptr`（巻き戻し）は本 API を通さない（04 §4 末尾）。
## INC-0: 空シェル。core/spell/ 一式は INC-1 で実装。

# func cast(word_ids: Array, ruleset) -> Resource:
#     # CastResult を返す。INC-1 で実装。
#     return null
