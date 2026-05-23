extends Resource
class_name TileKind
## TileKind — マス目グリッド上のタイル種別（INC-3 v0.9 新規、05 §9）。
##
## スキーマ出典: docs/05_データ定義テンプレート.md §9。
## 座標系上の意味: docs/09_マップ・移動仕様.md §3.3。
## 不変条件:
##   - id は 09 §3.3 の正典リスト ∈ { floor, wall, door, stairs_down, inscription, study_spot, player_start }
##   - wall は passable=false かつ blocks_sight=true 必須
##   - stairs_down は passable=true 必須
##   - blocks_spell_path=true でも `í gegnum` は座標上で貫通可（SpatialResolver の責務）

const VALID_IDS := [
	"floor", "wall", "door", "stairs_down",
	"inscription", "study_spot", "player_start",
]

@export var id: String = ""
@export var passable: bool = true
@export var blocks_sight: bool = false
@export var blocks_spell_path: bool = false
@export var role: String = ""
@export var interactable: bool = false
@export var source: String = "オリジナル"
@export var verified: bool = true


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id.is_empty():
		errors.append("id is required")
	elif id not in VALID_IDS:
		errors.append("id '%s' is not in 09 §3.3 canonical list" % id)
	if id == "wall":
		if passable:
			errors.append("wall must have passable=false")
		if not blocks_sight:
			errors.append("wall must have blocks_sight=true")
	if id == "stairs_down" and not passable:
		errors.append("stairs_down must have passable=true")
	return errors
