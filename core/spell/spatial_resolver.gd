extends RefCounted
class_name SpatialResolver
## SpatialResolver — 範囲語・方向語から対象タイル集合 T を計算（INC-3 v0.9 新規 / INC-3.5 v0.9.5 本格化、09 §7.4）。
##
## INC-3 (v0.9.x): 最小実装。spatial_context が null なら null を返し、minor finding のみ。
## INC-3.5 v0.9.5: 本格化。
##   - 距離レンジ (nær 1-2 / fjarri 3-8) → 射程フィルタ
##   - 形状 (vítt 半径 2 円 AoE / í gegnum 直線貫通) → 対象タイル列を展開
##   - 方向 (fram/aptr/vinstri/hœgri) → プレイヤー向き基準で軸ベクトル決定
##   - 射程外なら `range_required` finding を TargetSet.core_findings に立てる
##     → SpellEngine が grammar_report.findings にマージし、暴発倍率に乗る
##
## 設計判断:
##   - range_conflict と direction_required は Validator が構造的に判定（座標不要）
##   - range_required は座標が要るのでここで判定
##   - 範囲語・方向語が無いシンプル詠唱は従来通り扇 ±45° 最近敵 (v0.9.2 互換)

const TARGET_SET := preload("res://core/spell/models/target_set.gd")

## 形状系の範囲語 ID（Validator と同期、複数定義禁止のためここでは const のみ）
const SHAPE_AOE_RADIUS_DEFAULT := 2          # vítt のデフォルト半径（spatial.params.radius で上書き）
const DEFAULT_IMPLICIT_RANGE := 1            # 範囲語なし＋方向あり = 隣接（1 タイル）


## 対象タイル集合を計算。spatial_context が null なら null を返し、呼び側は target_set を null のまま扱う。
##   ast: Parser の出力 Dictionary（ranges / directions / target が入っている）
##   spatial_context: SpatialContext or null
##   ruleset: GrammarRuleset（コア違反スイッチを見る — 現状は呼び側で参照のみ）
static func resolve(ast: Dictionary, spatial_context, _ruleset) -> TargetSet:
	if spatial_context == null:
		return null  # 後方互換: spell_lab/combat_test 既存挙動

	var result := TARGET_SET.new()

	# === 範囲語・方向語を収集 ===
	var ranges: Array = ast.get("ranges", [])
	var directions: Array = ast.get("directions", [])

	# 範囲語の解析（最初の 1 個を採用）— 種別と params を取り出す
	var range_kind: String = ""           # "" / "distance" / "shape"
	var range_shape: String = ""           # "circle_aoe" / "line_pierce"
	var range_min: int = -1
	var range_max: int = -1
	var range_radius: int = SHAPE_AOE_RADIUS_DEFAULT
	var range_ignores_walls: bool = false
	if ranges.size() > 0:
		var rres: WordResource = ranges[0].get("resource", null)
		if rres != null:
			result.used_range_word = String(rres.id)
			var sp: Dictionary = rres.spatial
			range_kind = String(sp.get("kind", ""))
			var params = sp.get("params", {})
			if typeof(params) == TYPE_DICTIONARY:
				match range_kind:
					"distance":
						range_min = int(params.get("min", 1))
						range_max = int(params.get("max", 1))
					"shape":
						range_shape = String(params.get("shape", ""))
						range_radius = int(params.get("radius", SHAPE_AOE_RADIUS_DEFAULT))
						range_ignores_walls = bool(params.get("ignores_walls", false))

	# 方向語の解析（最初の 1 個）— 軸を採用
	var direction_axis: String = ""        # "" / "forward" / "backward" / "left" / "right"
	if directions.size() > 0:
		var dres: WordResource = directions[0].get("resource", null)
		if dres != null:
			result.used_direction_word = String(dres.id)
			var ds: Dictionary = dres.spatial
			var dparams = ds.get("params", {})
			if typeof(dparams) == TYPE_DICTIONARY:
				direction_axis = String(dparams.get("axis", ""))

	# === 形状系（AoE / 貫通）===
	if range_kind == "shape" and range_shape == "circle_aoe":
		_resolve_circle_aoe(result, spatial_context, direction_axis, range_radius)
		return result
	if range_kind == "shape" and range_shape == "line_pierce":
		_resolve_line_pierce(result, spatial_context, direction_axis, range_ignores_walls)
		return result

	# === 距離系または方向単独 ===
	var min_d: int = range_min if range_kind == "distance" else DEFAULT_IMPLICIT_RANGE
	var max_d: int = range_max if range_kind == "distance" else DEFAULT_IMPLICIT_RANGE

	# 方向指定があるなら、軸ベクトルに沿った最近敵を探す（その範囲内）
	if direction_axis != "":
		var dir_vec: Vector2i = _vec_for_axis(spatial_context.player_facing, direction_axis)
		_resolve_directional_single(result, spatial_context, dir_vec, min_d, max_d)
		return result

	# 方向指定もない → 扇 ±45° 最近敵で距離フィルタ（範囲語が距離系なら）
	# 範囲語もない → 旧 v0.9.2 互換: 扇 ±45° 最近敵（距離無視）
	_resolve_arc_nearest(result, spatial_context, min_d, max_d, range_kind == "distance")
	return result


# === 形状: 半径 R の円 AoE ===
# 中心 = プレイヤー位置 + 方向ベクトル × R（指定方向に R タイル先を中心に展開）
# 視界内かつ生存中の敵をすべて対象。
static func _resolve_circle_aoe(result: TargetSet, ctx, axis: String, radius: int) -> void:
	var center: Vector2i = ctx.player_pos
	if axis != "":
		var dir_vec: Vector2i = _vec_for_axis(ctx.player_facing, axis)
		center = ctx.player_pos + dir_vec * radius
	result.center_pos = center
	var tiles: Array = []
	var eids: PackedStringArray = PackedStringArray()
	for e in ctx.enemies:
		var epos: Vector2i = Vector2i(e["pos"])
		var d: int = abs(epos.x - center.x) + abs(epos.y - center.y)
		if d <= radius and epos in ctx.visible_tiles:
			tiles.append(epos)
			eids.append(String(e["id"]))
	result.target_tiles = tiles
	result.target_enemy_ids = eids
	result.reachable = true  # 着弾自体は成立（敵 0 でも reachable）
	if tiles.is_empty():
		result.advisory_findings["aoe_empty"] = "AoE 範囲内に敵がいません（着弾は成立）"


# === 形状: 直線貫通 ===
# プレイヤー位置から方向ベクトルに沿って 1 タイルずつ進み、マップ範囲内の全タイルを集め、
# その上に居る生存敵を全て対象。ignores_walls=true なら壁を貫通。
static func _resolve_line_pierce(result: TargetSet, ctx, axis: String, ignores_walls: bool) -> void:
	var dir_vec: Vector2i = _vec_for_axis(ctx.player_facing, axis) if axis != "" else _facing_vec(ctx.player_facing)
	var tiles: Array = []
	var eids: PackedStringArray = PackedStringArray()
	var cur: Vector2i = ctx.player_pos + dir_vec
	var step_max: int = 100  # 暴走防止上限（マップ最大辺 30 を十分超える値）
	for _i in step_max:
		# マップ外で停止
		if cur.x < 0 or cur.y < 0 or cur.x >= ctx.map_size.x or cur.y >= ctx.map_size.y:
			break
		# 壁チェック
		var blocked := false
		if ctx.wall_lookup.is_valid():
			blocked = bool(ctx.wall_lookup.call(cur))
		if blocked and not ignores_walls:
			break
		# このタイルに居る生存敵を対象に追加
		for e in ctx.enemies:
			if Vector2i(e["pos"]) == cur:
				tiles.append(cur)
				eids.append(String(e["id"]))
				break
		cur += dir_vec
	result.target_tiles = tiles
	result.target_enemy_ids = eids
	result.center_pos = ctx.player_pos + dir_vec
	result.reachable = true
	if tiles.is_empty():
		result.advisory_findings["line_empty"] = "貫通直線上に敵がいません"


# === 距離 + 方向: 単体ターゲット ===
# 方向ベクトルに沿って min_d〜max_d 範囲を走査し、その距離レンジ内に居る最初の敵を対象に。
# レンジ内に敵がいなければ、レンジ外で見つかった敵を range_required finding の対象とする。
# どこにも敵がなければ「射程内に敵なし」の range_required finding。
static func _resolve_directional_single(result: TargetSet, ctx, dir_vec: Vector2i, min_d: int, max_d: int) -> void:
	var in_range_enemy = null         # min_d..max_d 内に居る最初の敵
	var in_range_dist: int = -1
	var out_of_range_enemy = null     # min_d 未満 or max_d 超で見つかった敵（report 用）
	var out_of_range_dist: int = -1
	var cur: Vector2i = ctx.player_pos + dir_vec
	# 線上を max_d + 5 タイル先まで走査（はみ出した敵を range_required で報告するため少し先まで見る）
	var scan_max: int = max(max_d + 5, 10)
	for d in range(1, scan_max + 1):
		if cur.x < 0 or cur.y < 0 or cur.x >= ctx.map_size.x or cur.y >= ctx.map_size.y:
			break
		for e in ctx.enemies:
			if Vector2i(e["pos"]) == cur:
				if d >= min_d and d <= max_d:
					in_range_enemy = e
					in_range_dist = d
				elif out_of_range_enemy == null:
					# 最初に出会う「範囲外の敵」を記憶（range_required report 用）
					out_of_range_enemy = e
					out_of_range_dist = d
				break
		if in_range_enemy != null:
			break  # 範囲内が見つかったらその時点で確定
		cur += dir_vec
	if in_range_enemy != null:
		result.target_tiles = [Vector2i(in_range_enemy["pos"])]
		result.target_enemy_ids = PackedStringArray([String(in_range_enemy["id"])])
		result.center_pos = Vector2i(in_range_enemy["pos"])
		result.reachable = true
		return
	# 範囲内に敵なし
	result.reachable = false
	if out_of_range_enemy != null:
		result.center_pos = Vector2i(out_of_range_enemy["pos"])
		result.core_findings.append(_range_required_finding(String(out_of_range_enemy["id"]), out_of_range_dist))
	else:
		result.core_findings.append(_range_required_finding("（射程内に敵なし）", max_d))


# === 扇 ±45° 最近敵（旧 v0.9.2 互換、INC-3.5 では距離フィルタ追加可能）===
# distance_filter=true なら min_d..max_d の射程内の最近敵に限定。
static func _resolve_arc_nearest(result: TargetSet, ctx, min_d: int, max_d: int, distance_filter: bool) -> void:
	var nearest: Dictionary = ctx.nearest_enemy_in_arc(45.0)
	if nearest.is_empty():
		result.reachable = false
		result.advisory_findings["no_target_in_arc"] = "向いている方向の扇状範囲 (±45°) に視界内の敵がいない"
		return
	if distance_filter:
		var epos: Vector2i = Vector2i(nearest["pos"])
		var d: int = abs(epos.x - ctx.player_pos.x) + abs(epos.y - ctx.player_pos.y)
		if d < min_d or d > max_d:
			result.reachable = false
			result.center_pos = epos
			result.core_findings.append(_range_required_finding(String(nearest["id"]), d))
			return
	result.target_tiles = [Vector2i(nearest["pos"])]
	result.target_enemy_ids = PackedStringArray([String(nearest["id"])])
	result.center_pos = Vector2i(nearest["pos"])
	result.reachable = true


# --- ヘルパ ---

## 方向軸 (forward/backward/left/right) を facing と合成して 4 方向の単位ベクトル化。
##   facing: 0=N, 1=E, 2=S, 3=W（MapState.FACING_*）
##   axis: "forward" / "backward" / "left" / "right"
static func _vec_for_axis(facing: int, axis: String) -> Vector2i:
	var rel_offset := 0
	match axis:
		"forward":  rel_offset = 0
		"right":    rel_offset = 1
		"backward": rel_offset = 2
		"left":     rel_offset = 3
		_: return _facing_vec(facing)  # 不明な軸は forward 扱い
	var resolved: int = (facing + rel_offset) % 4
	return _facing_vec(resolved)


static func _facing_vec(facing: int) -> Vector2i:
	match facing:
		0: return Vector2i( 0, -1)  # N
		1: return Vector2i( 1,  0)  # E
		2: return Vector2i( 0,  1)  # S
		3: return Vector2i(-1,  0)  # W
		_: return Vector2i( 0, -1)


## range_required finding を組み立てる。GrammarReport.failures() で拾える形式。
static func _range_required_finding(target_label: String, distance: int) -> Dictionary:
	return {
		"rule": "range_required",
		"pass": false,
		"severity": "moderate",
		"reason": TranslationServer.translate("grammar.range_required.reason") % [target_label, distance],
		"recommended": TranslationServer.translate("grammar.range_required.recommended"),
	}
