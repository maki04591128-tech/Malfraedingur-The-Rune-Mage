extends Resource
class_name EnemyResource
## EnemyResource — 敵の正典データ（INC-3 v0.9 拡張、05 §4）。
##
## INC-2 までは combat_test シナリオ JSON 内に直書きだったが、INC-3 で
## マス目戦闘・敵 AI が入るため Resource 化する。05 §4 と附録 S-2 を実装。
##
## behavior: "aggressive" | "boss" | "patrol_only"
##   - aggressive: 視認すれば追跡、隣接で攻撃
##   - boss: 視認ですぐ追跡、隣接で大ダメージ（INC-3 ではパラメータ違いの aggressive と等価）
##   - patrol_only: 巡回のみ、追跡しない（INC-3.5 以降のステルス系で使用）

@export var id: String = ""
@export var name_loc: Dictionary = {}  ## { "ja": "下級ドラウグル", "en": "Lesser Draugr" }
@export var hp: int = 30
@export var atk: int = 8
@export var weak_to: PackedStringArray = PackedStringArray()
@export var resist: PackedStringArray = PackedStringArray()
@export var sight_radius: int = 4   ## 09 §5.2 既定
@export var behavior: String = "aggressive"
@export var drops: Array = []       ## [{ "word_id": "eldr", "chance": 0.25 }]
@export var time_cost_on_fight_days: float = 0.2
@export var source: String = "オリジナル"
@export var verified: bool = true


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id.is_empty():
		errors.append("id is required")
	if not name_loc.has("ja"):
		errors.append("name_loc.ja is required (DL1)")
	if hp <= 0:
		errors.append("hp must be > 0")
	if behavior not in ["aggressive", "boss", "patrol_only"]:
		errors.append("behavior must be aggressive|boss|patrol_only (got '%s')" % behavior)
	return errors


func get_localized_name(locale: String) -> String:
	if name_loc.has(locale):
		return name_loc[locale]
	if name_loc.has("ja"):
		return name_loc["ja"]
	return id
