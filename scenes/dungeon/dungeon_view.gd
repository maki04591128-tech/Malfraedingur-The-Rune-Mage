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

# INC-3 v0.9.2: モーダル UI 状態（旧 spell_input_active は要求 3 の 1 ステップ詠唱化で廃止）
var spell_builder_modal: Node = null   ## F キーで開く spell_builder のインスタンス

# INC-3 v0.9.2 (要求 1): 移動キー長押しのリピート制御。
# OS のキーリピート echo は Godot 4 で安定しないため、_process で polling する方式に変更。
const MOVE_REPEAT_DELAY := 0.12  ## 秒。連続移動の間隔（小さくするほど速い）
var _move_cooldown: float = 0.0


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

## INC-3 v0.9.2 (要求 4): spell_builder モーダル表示中の ESC / F 捕捉（_input は最優先）。
## CanvasLayer 上の spell_builder が _unhandled_key_input を消費するため、こちらで先取り。
func _input(event: InputEvent) -> void:
	if spell_builder_modal == null:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F:
		_close_spell_builder_modal()
		get_viewport().set_input_as_handled()


## INC-3 v0.9.2 (要求 1): _process で移動キー押下を polling し、連続移動を実現。
## _unhandled_key_input の echo より確実（OS リピート設定に依存しない）。
func _process(delta: float) -> void:
	if game_over or spell_builder_modal != null:
		return
	_move_cooldown = max(0.0, _move_cooldown - delta)
	if _move_cooldown > 0.0:
		return
	var dx: int = 0
	var dy: int = 0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dy = -1
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dy = 1
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dx = -1
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dx = 1
	if dx != 0 or dy != 0:
		_player_action_move(dx, dy)
		_move_cooldown = MOVE_REPEAT_DELAY


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if game_over:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_start_new_loop()
			queue_redraw()
			_update_hud()
		return

	# モーダル表示中は ESC のみ受け付け（F で開いた spell_builder を閉じる）
	if spell_builder_modal != null:
		if event.keycode == KEY_ESCAPE:
			_close_spell_builder_modal()
		return

	match event.keycode:
		# 移動キーは _process で polling 処理（v0.9.2 要求 1、長押し連続移動）
		KEY_Q:
			_player_action_turn(-1)
		KEY_E:
			_player_action_turn(1)
		# --- INC-3 v0.9.2 (要求 3/4): キー再配置 ---
		KEY_1:
			_cast_slot(1)
		KEY_2:
			_cast_slot(2)
		KEY_3:
			_cast_slot(3)
		KEY_4:
			_cast_slot(4)
		KEY_5:
			_cast_slot(5)
		KEY_SPACE:
			_player_action_wait_and_heal()
		KEY_F:
			_open_spell_builder_modal()
		KEY_ENTER:
			_try_descend_stairs()
		# --- INC-3 検証用デバッグキー（INC-3.5 以降は削除候補） ---
		KEY_H:
			# DEBUG: 致命的ダメージで死亡 → _trigger_rewind("death")
			_log("[color=#888]DEBUG: take_damage(999) → 死亡テスト[/color]")
			if GameState.take_damage(999):
				_trigger_rewind("death")
			_update_hud()
		KEY_T:
			# DEBUG: 大量時間消費で時間切れ → _trigger_rewind("timeout")
			_log("[color=#888]DEBUG: advance_world_time(999) → 時間切れテスト[/color]")
			if GameState.advance_world_time(999.0):
				_trigger_rewind("timeout")
			_update_hud()
		KEY_G:
			if MapState.map_data != null and MapState.map_data.stairs_down_pos.x >= 0:
				MapState.player_pos = MapState.map_data.stairs_down_pos
				MapState._recompute_fov()
				_log("[color=#888]DEBUG: teleport to stairs (%d, %d)[/color]" % [MapState.player_pos.x, MapState.player_pos.y])
				queue_redraw()
				_update_hud()


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


## INC-3 v0.9.2 (要求 3/4): スロット呼び出し詠唱。
## スロット 1-5 から Lexicon._spell_slots のトークン列を取得して即詠唱。
## スロット 1 はデフォルトで meida fjanda、F キーで作成した呪文を 2-5 にも割当可能。
## 対象は SpatialResolver が向き±45° 扇内の最近敵を自動選択（要求 2）。
func _cast_slot(slot: int) -> void:
	var tokens_in: Array = Lexicon.get_spell_slot(slot)
	if tokens_in.is_empty():
		_log("[color=#888]スロット %d に魔法が割り当てられていません (F で割当)[/color]" % slot)
		return
	var ruleset: Resource = load("res://data/grammar/phase_intermediate.tres")
	var spatial_ctx = SPATIAL_CONTEXT.from_map_state(MapState)
	var result: CastResult = SpellEngine.cast(tokens_in, ruleset, {
		"spatial_context": spatial_ctx,
	})
	# 詠唱の語句概要をログに（スロット番号と共に）
	var preview: Array = []
	for t in tokens_in:
		preview.append(String(t.get("word_id", "?")))
	_log("[color=#a0c8f0]🎯 スロット %d: %s[/color]" % [slot, " ".join(preview)])
	_apply_cast_result(result)
	# Δ_cast = 1.0 + 0.5 × 語数 + 0.5 × 語ティア合計（簡易近似で 1.0 + 1.0×語数）
	var delta: float = 1.0 + 0.5 * float(tokens_in.size())
	_advance_world_time(delta)
	_enemies_take_turn()
	queue_redraw()
	_update_hud()


## INC-3 v0.9.2 (要求 3): 待機 + HP+1 回復。1 ターン消費 + 世界時間 Δ=1.0。
## Space キーで発動。詠唱と同じくらいのテンポで「治癒呪文の代用」的に使える。
func _player_action_wait_and_heal() -> void:
	var healed: int = min(1, GameState.PLAYER_MAX_HP - GameState.hp)
	GameState.hp = min(GameState.PLAYER_MAX_HP, GameState.hp + 1)
	if healed > 0:
		_log("[color=#8fc]🌿 待機 (HP +%d → %d)[/color]" % [healed, GameState.hp])
	else:
		_log("[color=#888]🌿 待機 (HP %d、既に最大)[/color]" % GameState.hp)
	_advance_world_time(1.0)
	_enemies_take_turn()
	queue_redraw()
	_update_hud()


## INC-3 v0.9.2 (要求 4): F キーで spell_builder.tscn をモーダル表示。
## CanvasLayer に重ねて instantiate、ESC で閉じる。spell_builder 側に「スロット保存」UI を別途追加予定。
func _open_spell_builder_modal() -> void:
	if spell_builder_modal != null:
		return
	var scene: PackedScene = load("res://scenes/debug/spell_builder.tscn")
	if scene == null:
		_log("[color=#e88]spell_builder.tscn が読み込めません[/color]")
		return
	var inst: Node = scene.instantiate()
	# 既存 HUD レイヤーの上に重ねる
	var hud_layer: CanvasLayer = get_node_or_null("HUDLayer")
	if hud_layer != null:
		# 別レイヤーで上に
		var modal_layer := CanvasLayer.new()
		modal_layer.name = "SpellBuilderModalLayer"
		modal_layer.layer = 2  # HUD より上
		add_child(modal_layer)
		modal_layer.add_child(inst)
		spell_builder_modal = modal_layer
	else:
		add_child(inst)
		spell_builder_modal = inst
	_log("[color=#a0c8f0]F: spell_builder を開きました (ESC で閉じる)[/color]")
	# 今後: spell_builder に「現在のトークン列をスロット N に保存」ボタンを追加し、
	# 押下時に Lexicon.set_spell_slot(N, tokens) を呼ぶ。INC-3 v0.9.2 では UI 雛形のみ。
	# 暫定: モーダル内のキーボード入力は spell_builder 側が消費するため、
	# dungeon_view 側は ESC のみ反応。


## モーダルを閉じる。
func _close_spell_builder_modal() -> void:
	if spell_builder_modal == null:
		return
	spell_builder_modal.queue_free()
	spell_builder_modal = null
	_log("[color=#888]spell_builder を閉じました[/color]")
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
	hud_label.text = "%s | 位置 %s 向き %s | 視界内 %d 体 %s\nWASD/矢印=移動(長押し可)  Q/E=旋回  1-5=スロット詠唱(±45°扇)  Space=待機+HP回復  F=魔法作成  Enter=階段" % [
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
