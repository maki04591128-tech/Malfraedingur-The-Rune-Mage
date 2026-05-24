extends RefCounted
class_name SpatialResolver
## SpatialResolver — 範囲語・方向語から対象タイル集合 T を計算（INC-3 v0.9 新規、09 §7.4）。
##
## INC-3 範囲（最小実装）:
##   - spatial_context が null なら null を返す（後方互換、spell_lab/combat_test）
##   - spatial_context があれば、範囲語・方向語を読み取って簡易解釈
##   - INC-3 では「タイル直接指定 or 最隣接敵自動」が基本動作
##   - 範囲語・方向語が呪文にあっても、minor finding にとどめて T 自体は最隣接敵にフォールバック
##
## INC-3.5 で本格化:
##   - range_required / range_conflict / direction_required をコア違反扱い
##   - vítt の AoE 計算、í gegnum の貫通直線、fjarri/nær の距離レンジ判定
##   - 暴発倍率 MISFIRE_MULT_BY_RULE への接続

const TARGET_SET := preload("res://core/spell/models/target_set.gd")


## 対象タイル集合を計算。spatial_context が null なら null を返し、呼び側は target_set を null のまま扱う。
##   ast: Parser の出力 Dictionary
##   spatial_context: SpatialContext or null
##   ruleset: GrammarRuleset（INC-3.5 で range_*/direction_* のコア違反スイッチを見る）
static func resolve(ast: Dictionary, spatial_context, _ruleset) -> TargetSet:
	if spatial_context == null:
		return null  # 後方互換: spell_lab/combat_test 既存挙動

	var result := TARGET_SET.new()

	# 呪文中の範囲語・方向語を検出（INC-3 では情報収集のみ）
	# トークン構造: {word_id: String, case: String, resource: WordResource}
	var range_tokens: Array = []
	var direction_tokens: Array = []
	var tokens: Array = ast.get("tokens", [])
	for t in tokens:
		if t == null:
			continue
		var res = t.get("resource", null)
		var cls := String(res.word_class) if res != null else ""
		var wid := String(t.get("word_id", ""))
		match cls:
			"range":
				range_tokens.append(wid)
			"direction":
				direction_tokens.append(wid)

	if range_tokens.size() > 0:
		result.used_range_word = String(range_tokens[0])
	if direction_tokens.size() > 0:
		result.used_direction_word = String(direction_tokens[0])

	# INC-3 では下記の advisory_findings を記録するが、ダメージ計算には影響させない（minor finding）
	if range_tokens.size() >= 2:
		result.advisory_findings["range_conflict"] = "範囲語が複数指定されています（INC-3.5 で詳細判定）"

	# INC-3 v0.9.2 動作: 向き軸 ±45° の扇状範囲内の最近敵を対象に
	# （v0.9.1 までは視界内全敵から最近敵。v0.9.2 で「向いている方向にしか撃てない」に変更）
	# 扇外に敵がいても「方向違い」で当たらない仕様。 INC-3.5 で方向語 (fram/aptr/...) を
	# 解釈してこの軸を変える予定。
	var nearest = spatial_context.nearest_enemy_in_arc(45.0)
	if nearest.is_empty():
		result.reachable = false
		result.advisory_findings["no_target_in_arc"] = "向いている方向の扇状範囲 (±45°) に視界内の敵がいない"
		return result

	result.target_tiles = [Vector2i(nearest["pos"])]
	result.target_enemy_ids = PackedStringArray([String(nearest["id"])])
	result.center_pos = Vector2i(nearest["pos"])
	result.reachable = true
	return result
