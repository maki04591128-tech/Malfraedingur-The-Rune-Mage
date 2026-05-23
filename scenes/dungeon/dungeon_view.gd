extends Node2D
## DungeonView — シームレス探索＝戦闘のメインシーン（INC-3 v0.9 新規、04 v0.6 §5 / 09 §6）。
##
## INC-3 縦切り:
##   - キー入力 (WASD / 矢印): 1 タイル移動、向き自動更新
##   - Q/E: 旋回 (Δ=0)
##   - Space: 隣接敵への `meiða fjanda` 簡易詠唱（SpellComposer フル UI は INC-3.5 で）
##   - 階段に乗って Enter で次階
##   - 死亡 / 時間切れで巻き戻し
##   - 3 階のボス撃破でクリア
##
## 描画は _draw() で最小実装（TileMap は INC-3.5 以降で本格化）。

const FLOOR_TEMPLATE = preload("res://data/floors/floor_template.gd")
const ENEMY_RESOURCE = preload("res://data/enemies/enemy_resource.gd")
const DUNGEON_SEED = preload("res://core/map/models/dungeon_seed.gd")
const SPATIAL_CONTEXT = preload("res://core/spell/models/spatial_context.gd")
const ENEMY_AI = preload("res://core/combat/enemy_ai.gd")
const MAP_STATE_SCRIPT = preload("res://autoload/map_state.gd")  ## const アクセス用（autoload class スコープ問題回避）

# autoload インスタンスは関数ローカルで取得（Godot 4 autoload parse 順序問題回避、メモリ §INC-0 知見）
func _ms():
	return get_node("/root/MapState")

func _gs():
	return get_node("/root/GameState")

func _eb():
	return get_node("/root/EventBus")

const TILE_SIZE := 24  ## 描画タイル寸法（ピクセル）
const COLOR_FLOOR := Color(0.12, 0.10, 0.08)
const COLOR_WALL := Color(0.30, 0.26, 0.20)
const COLOR_FLOOR_EXPLORED := Color(0.05, 0.04, 0.03)
const COLOR_WALL_EXPLORED := Color(0.12, 0.10, 0.08)
const COLOR_STAIRS := Color(0.85, 0.65, 0.20)
const COLOR_PLAYER := Color(0.30, 0.85, 0.95)
const COLOR_ENEMY := Color(0.85, 0.30, 0.25)
const COLOR_BOSS := Color(0.95, 0.15, 0.15)
const COLOR_FOV_HIGHLIGHT := Color(1, 1, 1, 0.05)

var floor_templates: Array = []         ## [helgrind_1, _2, _3] resources
var enemy_db: Dictionary = {}            ## { "draugr_lesser": EnemyResource, ... }
var rng_master_seed: int = 0             ## 巻き戻しでシフトしていく
var current_floor_template = null

var hud_label: Label = null
var combat_log_label: RichTextLabel = null
var game_over: bool = false
var log_lines: PackedStringArray = PackedStringArray()
const LOG_MAX_LINES := 6

# 詠唱モード UI
var spell_input_active: bool = false


func _ready() -> void:
	# Camera2D を追加（中央を画面中央に）
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.enabled = true
	add_child(cam)

	# HUD（CanvasLayer + Label）
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	add_child(hud_layer)

	hud_label = Label.new()
	hud_label.name = "HUDLabel"
	hud_label.position = Vector2(16, 16)
	hud_label.add_theme_font_size_override("font_size", 16)
	hud_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	hud_label.add_theme_constant_override("shadow_offset_x", 1)
	hud_label.add_theme_constant_override("shadow_offset_y", 1)
	hud_layer.add_child(hud_label)

	# 戦闘ログ（画面下部）
	combat_log_label = RichTextLabel.new()
	combat_log_label.name = "CombatLog"
	combat_log_label.bbcode_enabled = true
	combat_log_label.fit_content = true
	combat_log_label.scroll_active = false
	combat_log_label.size = Vector2(800, 180)
	combat_log_label.position = Vector2(16, 460)
	combat_log_label.add_theme_color_override("default_color", Color(0.95, 0.92, 0.85))
	hud_layer.add_child(combat_log_label)

	# データロード
	_load_data()
	# ループ開始
	_start_new_loop()
	queue_redraw()
	_update_hud()


func _load_data() -> void:
	# フロアテンプレ
	floor_templates = [
		load("res://data/floors/helgrind_1.tres"),
		load("res://data/floors/helgrind_2.tres"),
		load("res://data/floors/helgrind_3.tres"),
	]
	# 敵 DB
	enemy_db = {
		"draugr_lesser": load("res://data/enemies/draugr_lesser.tres"),
		"draugr_warden": load("res://data/enemies/draugr_warden.tres"),
	}
	rng_master_seed = int(Time.get_unix_time_from_system())


func _start_new_loop() -> void:
	GameState.reset()
	game_over = false
	log_lines.clear()
	_log("[color=#f0d080]── 新しいループ %d 開始 ──[/color]" % GameState.loop_count)
	_load_floor_for(GameState.floor_index)


func _load_floor_for(depth: int) -> void:
	current_floor_template = floor_templates[depth - 1]
	# Seed: 巻き戻しごとに変える
	var seed := rng_master_seed + GameState.loop_count * 1000 + depth
	var dseed = DUNGEON_SEED.new(seed, GameState.loop_count, depth)
	MapState.load_floor(current_floor_template, dseed)
	# 敵 HP を EnemyResource から正規化
	for e in MapState.map_data.enemies:
		var eid: String = String(e["id"])
		if enemy_db.has(eid):
			var er = enemy_db[eid]
			e["hp"] = er.hp
			e["atk"] = er.atk
			e["max_hp"] = er.hp
	_log("[color=#a0c8f0]Helgrind 第 %d 階へ[/color]" % depth)
	EventBus.floor_changed.emit(depth, "enter")


# --- 入力 ---

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if game_over:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_start_new_loop()
			queue_redraw()
			_update_hud()
		return

	# 詠唱モード
	if spell_input_active:
		if event.keycode == KEY_ESCAPE:
			spell_input_active = false
			_log("詠唱中止")
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			spell_input_active = false
			_cast_meida_fjanda()
		return

	match event.keycode:
		KEY_W, KEY_UP:
			_player_action_move(0, -1)
		KEY_S, KEY_DOWN:
			_player_action_move(0, 1)
		KEY_A, KEY_LEFT:
			_player_action_move(-1, 0)
		KEY_D, KEY_RIGHT:
			_player_action_move(1, 0)
		KEY_Q:
			_player_action_turn(-1)
		KEY_E:
			_player_action_turn(1)
		KEY_SPACE:
			_open_spell_input()
		KEY_ENTER:
			_try_descend_stairs()


func _player_action_move(dx: int, dy: int) -> void:
	var moved := MapState.move_player(dx, dy)
	if moved:
		_advance_world_time(0.5)  ## Δ_move = 0.5 (05 v0.9)
		_enemies_take_turn()
	else:
		# 壁・敵にぶつかっただけ。向きは更新されている可能性あり。世界時間消費せず
		pass
	queue_redraw()
	_update_hud()


func _player_action_turn(direction: int) -> void:
	# direction: -1=左へ旋回, +1=右へ旋回
	var new_facing := (MapState.player_facing + direction + 4) % 4
	MapState.turn_player(new_facing)
	# 旋回は Δ=0、敵ターンも回さない（戦闘中の自由旋回を許す、09 §3.2）
	queue_redraw()
	_update_hud()


func _open_spell_input() -> void:
	# INC-3 最小: 隣接敵に対する `meiða fjanda` を発動する確認ダイアログ的なものを
	# 文字 UI で簡易表示。SpellComposer フル統合は INC-3.5。
	spell_input_active = true
	var nearest := MapState.nearest_enemy_in_sight()
	if nearest.is_empty():
		_log("[color=#888]視界内に敵がいない[/color]")
		spell_input_active = false
		return
	_log("[color=#f0d080]詠唱準備: meiða fjanda (Enter で実行 / ESC で中止)[/color]")


func _cast_meida_fjanda() -> void:
	# INC-3 最小詠唱: タイル ["meida", "fjanda"]、ruleset phase_intermediate
	var ruleset: Resource = load("res://data/grammar/phase_intermediate.tres")
	var tokens_in: Array = [
		{"word_id": "meida", "case": ""},
		{"word_id": "fjandi", "case": "acc"},
	]
	var spatial_ctx = SPATIAL_CONTEXT.from_map_state(MapState)
	var result: CastResult = SpellEngine.cast(tokens_in, ruleset, {
		"spatial_context": spatial_ctx,
	})
	_apply_cast_result(result)
	_advance_world_time(2.0)  ## 簡易 Δ_cast = 2.0 (語数2 × 0.5 + 1.0)
	_enemies_take_turn()
	queue_redraw()
	_update_hud()


func _apply_cast_result(result: CastResult) -> void:
	if result == null:
		_log("[color=#888]詠唱失敗[/color]")
		return
	# 文法レポート要約
	var g_score := 0.0
	if result.grammar_report != null:
		g_score = result.grammar_report.g_score
		if not result.grammar_report.overall_pass:
			_log("[color=#e88]✗ 文法 NG (G=%.2f)[/color]" % g_score)
	# 暴発
	if result.resolved != null and result.resolved.misfired:
		var cat := result.resolved.misfire_category
		_log("[color=#f88]✸ 暴発 (%s)[/color]" % str(cat))
		# 自爆系なら自分にダメージ
		var self_dmg := int(result.resolved.self_damage)
		if self_dmg > 0:
			_log("  自身に %d ダメージ" % self_dmg)
			if GameState.take_damage(self_dmg):
				_trigger_rewind("death")
				return
		return
	# 対象タイルにダメージ
	if result.target_set == null or result.target_set.is_empty():
		_log("[color=#888]対象なし[/color]")
		return
	var power := 0.0
	if result.resolved != null:
		power = result.resolved.effect_power
	var dmg := int(round(power * 3.0))  ## DAMAGE_SCALE=3.0 (INC-2 v0.4 継承)
	for i in range(result.target_set.target_tiles.size()):
		var pos: Vector2i = result.target_set.target_tiles[i]
		var enemy_dict := MapState.map_data.enemy_at(pos)
		if enemy_dict.is_empty():
			continue
		enemy_dict["hp"] = int(enemy_dict["hp"]) - dmg
		_log("[color=#8f8]→ %s に %d ダメージ (残 HP: %d)[/color]" % [String(enemy_dict["id"]), dmg, int(enemy_dict["hp"])])
		if int(enemy_dict["hp"]) <= 0:
			_log("[color=#fc8]💀 %s を撃破[/color]" % String(enemy_dict["id"]))


func _enemies_take_turn() -> void:
	if MapState.map_data == null:
		return
	for e in MapState.map_data.enemies:
		if int(e.get("hp", 0)) <= 0:
			continue
		ENEMY_AI.take_turn(e, MapState, enemy_db)
		# 隣接攻撃
		if abs(Vector2i(e["pos"]).x - MapState.player_pos.x) + abs(Vector2i(e["pos"]).y - MapState.player_pos.y) == 1:
			var atk := int(e.get("atk", 6))
			_log("[color=#e88]敵 %s が %d ダメージ[/color]" % [String(e["id"]), atk])
			if GameState.take_damage(atk):
				_trigger_rewind("death")
				return


func _advance_world_time(delta: float) -> void:
	if GameState.advance_world_time(delta):
		_trigger_rewind("timeout")


func _try_descend_stairs() -> void:
	if MapState.is_player_on_stairs():
		GameState.descend_floor()
		if GameState.floor_index > floor_templates.size():
			# 全踏破
			_log("[color=#ff8]✦ Helgrind 踏破 — 滅びを止めた[/color]")
			EventBus.helgrind_cleared.emit()
			game_over = true
		else:
			_load_floor_for(GameState.floor_index)
			queue_redraw()
	else:
		_log("[color=#888]ここに階段はない[/color]")


func _trigger_rewind(reason: String) -> void:
	EventBus.rewind_triggered.emit(reason)
	_log("[color=#a8f]── öld renna aptr — 時を巻き戻す (%s) ──[/color]" % reason)
	_log("[color=#888]Space で次のループへ[/color]")
	game_over = true


# --- 描画 ---

func _draw() -> void:
	if MapState.map_data == null:
		return
	var md = MapState.map_data
	var origin := -Vector2(MapState.player_pos) * TILE_SIZE  # プレイヤーを中央に
	for y in range(md.size.y):
		for x in range(md.size.x):
			var pos := Vector2i(x, y)
			var tile := md.get_tile(pos)
			var visible := MapState.is_visible(pos)
			var explored := pos in MapState.fov_explored
			if not visible and not explored:
				continue
			var rect_pos := origin + Vector2(x, y) * TILE_SIZE
			var c: Color
			if tile == "wall":
				c = COLOR_WALL if visible else COLOR_WALL_EXPLORED
			elif tile == "stairs_down":
				c = COLOR_STAIRS if visible else COLOR_FLOOR_EXPLORED
			else:
				c = COLOR_FLOOR if visible else COLOR_FLOOR_EXPLORED
			draw_rect(Rect2(rect_pos, Vector2(TILE_SIZE - 1, TILE_SIZE - 1)), c, true)
			if tile == "stairs_down" and visible:
				# 階段マーク
				var center := rect_pos + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
				draw_circle(center, TILE_SIZE / 4.0, Color(0.2, 0.15, 0.05))

	# 敵
	for e in md.enemies:
		if int(e.get("hp", 0)) <= 0:
			continue
		var epos := Vector2i(e["pos"])
		if not MapState.is_visible(epos):
			continue
		var rect_pos := origin + Vector2(epos) * TILE_SIZE
		var ec := COLOR_BOSS if String(e["id"]) == "draugr_warden" else COLOR_ENEMY
		draw_rect(Rect2(rect_pos + Vector2(2, 2), Vector2(TILE_SIZE - 5, TILE_SIZE - 5)), ec, true)
		# HP バー
		var hp_ratio := float(e["hp"]) / float(e.get("max_hp", 18))
		draw_rect(Rect2(rect_pos + Vector2(2, 0), Vector2((TILE_SIZE - 4) * hp_ratio, 2)), Color(0.9, 0.3, 0.3), true)

	# プレイヤー
	var p_rect_pos := origin + Vector2(MapState.player_pos) * TILE_SIZE
	draw_rect(Rect2(p_rect_pos + Vector2(3, 3), Vector2(TILE_SIZE - 7, TILE_SIZE - 7)), COLOR_PLAYER, true)
	# 向き矢印
	var p_center := p_rect_pos + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var arrow_vec := Vector2(MapState.FACING_VECTORS[MapState.player_facing])
	var arrow_end := p_center + arrow_vec * (TILE_SIZE / 2.0 - 2)
	draw_line(p_center, arrow_end, Color(0.15, 0.10, 0.05), 2.0)


func _update_hud() -> void:
	if hud_label == null:
		return
	var status := GameState.get_status_summary()
	var pos_str: String = "(%d, %d)" % [MapState.player_pos.x, MapState.player_pos.y]
	var facing_names: Array = ["北", "東", "南", "西"]
	var facing_str: String = facing_names[MapState.player_facing]
	var in_sight: int = MapState.enemies_in_sight().size()
	var mode: String = "[警戒]" if in_sight > 0 else "[平時]"
	hud_label.text = "%s | 位置 %s 向き %s | 視界内 %d 体 %s\nWASD/矢印=移動  Q/E=旋回  Space=詠唱  Enter=階段" % [
		status, pos_str, facing_str, in_sight, mode
	]
	_render_log()


func _log(line: String) -> void:
	log_lines.append(line)
	while log_lines.size() > LOG_MAX_LINES:
		log_lines.remove_at(0)
	_render_log()


func _render_log() -> void:
	if combat_log_label == null:
		return
	combat_log_label.text = "\n".join(log_lines)
