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

## INC-3.5 v0.9.5: scaffold=max 射程プレビュー UI（09 §9）
const COLOR_PREVIEW_TARGET := Color(0.20, 0.95, 0.30, 0.55)   # 緑: 着弾対象タイル
const COLOR_PREVIEW_AOE    := Color(0.95, 0.85, 0.20, 0.30)   # 黄: AoE 範囲（敵いない部分）
const COLOR_PREVIEW_RANGE_FAIL := Color(0.95, 0.20, 0.20, 0.45) # 赤: range_required で届かない
const COLOR_PREVIEW_PIERCE := Color(0.70, 0.40, 0.95, 0.35)   # 紫: 貫通直線

var floor_templates: Array = []         ## [helgrind_1, _2, _3] resources
var enemy_db: Dictionary = {}            ## { "draugr_lesser": EnemyResource, ... }
var rng_master_seed: int = 0             ## 巻き戻しでシフトしていく
var current_floor_template = null

## INC-3.5 v0.9.7: scaffold=max のプレビュー対象スロット（Tab で切替）。
## キー 1-5 を押せばこのスロットに関係なくそのスロットが詠唱される。
## プレビューに表示する射程・AoE・貫通だけがこの値で切り替わる（HUD にも表示）。
var _active_preview_slot: int = 1

var hud_label: Label = null
var combat_log_label: RichTextLabel = null
var game_over: bool = false
var log_lines: PackedStringArray = PackedStringArray()
const LOG_MAX_LINES := 6

# INC-3 v0.9.2: モーダル UI 状態（旧 spell_input_active は要求 3 の 1 ステップ詠唱化で廃止）
# v0.9.3 (要求 5): Window ノードに変更し、別 OS ウィンドウとして表示
var spell_builder_window: Window = null   ## F キーで開く spell_builder の別ウィンドウ

# INC-3 v0.9.2 (要求 1): 移動キー長押しのリピート制御。
# OS のキーリピート echo は Godot 4 で安定しないため、_process で polling する方式に変更。
# v0.9.3 (要求 6/7): Space/1-5/Q/E も polling、WASD 同時押しで斜め移動
# v0.9.6: OS キーリピートと同じ「立ち上がりで 1 発 → INITIAL_DELAY 待機 → 連続リピート」の
#         2 段階方式に変更。タップ 1 回で意図せず連続入力に乗ってしまう挙動を解消。
const MOVE_REPEAT_DELAY := 0.12     ## 秒。連続移動の間隔（連続リピート期）
const ACTION_REPEAT_DELAY := 0.30   ## 秒。詠唱・旋回・待機の連続発動間隔（連続リピート期）
const INITIAL_REPEAT_DELAY := 0.20  ## 秒。タップ後、連続リピート期に入るまでの待ち（v0.9.6）
var _move_cooldown: float = 0.0
var _action_cooldown: float = 0.0
# v0.9.6: 立ち上がり検出用。前フレームに押されていたか。
# 移動は方向別ではなく「いずれかの移動キーが押されている」かどうかでまとめる（斜め移動の方向変化で勝手にエッジが立たないように）。
var _move_was_pressed: bool = false
# アクションは押されたキーごとに独立追跡する（Q 押した直後に E 押し直し、などに対応）。
var _action_keys_was_pressed: Dictionary = {}  # key (int) → bool


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
	# v0.9.4 (持ち越し 1): 階段降下後に HUD を即更新（v0.9.1 で発見した軽微バグ修正）
	_update_hud()
	queue_redraw()


# --- 入力 ---

## INC-3 v0.9.3 (要求 5): spell_builder Window 表示中はキー入力を window 側で消化させる。
## ESC は window 自身の close_requested で閉じるため、ここでは特別な捕捉不要。
func _input(_event: InputEvent) -> void:
	pass


## INC-3 v0.9.2 (要求 1): _process で移動キー押下を polling し、連続移動を実現。
## v0.9.3 拡張:
##   - 要求 6: Space/1-5/Q/E も polling、 ACTION_REPEAT_DELAY で連続発動
##   - 要求 7: WASD 上下と左右を独立判定 → 同時押しで斜め移動 (8 方向)
## v0.9.6: タップ 1 回で連続入力に入ってしまうのを防ぐ「2 段階リピート」方式。
##   立ち上がり検出 (押されていない → 押されている) で 1 回実行 + cooldown を INITIAL_REPEAT_DELAY に。
##   200ms 経過後もキーが押し続けられていれば連続リピート期に入り、以降は MOVE/ACTION_REPEAT_DELAY 周期で発動。
func _process(delta: float) -> void:
	if game_over or spell_builder_window != null:
		return
	_move_cooldown = max(0.0, _move_cooldown - delta)
	_action_cooldown = max(0.0, _action_cooldown - delta)

	# --- 移動 (8 方向化、要求 7 + v0.9.6 二段階リピート) ---
	var dx: int = 0
	var dy: int = 0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dy = -1
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dy = 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dx = -1
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dx = 1
	var move_pressed_now: bool = (dx != 0 or dy != 0)
	if move_pressed_now:
		if not _move_was_pressed:
			# 立ち上がり: 1 回実行 + 連続リピート期に入るまで INITIAL_REPEAT_DELAY 待つ
			_player_action_move(dx, dy)
			_move_cooldown = INITIAL_REPEAT_DELAY
		elif _move_cooldown <= 0.0:
			# 既に長押し中 + cooldown 経過 → 連続リピート期
			_player_action_move(dx, dy)
			_move_cooldown = MOVE_REPEAT_DELAY
	else:
		# 全部離された → 次の立ち上がりに備えて cooldown リセット
		_move_cooldown = 0.0
	_move_was_pressed = move_pressed_now

	# --- 非移動アクション (要求 6 + v0.9.6 二段階リピート、キーごとに独立追跡) ---
	# 候補キーと対応アクションを 1 つの table にまとめて処理
	var action_keys: Array = [
		[KEY_Q,     "_turn_ccw"],
		[KEY_E,     "_turn_cw"],
		[KEY_SPACE, "_wait_heal"],
		[KEY_1,     "_slot1"],
		[KEY_2,     "_slot2"],
		[KEY_3,     "_slot3"],
		[KEY_4,     "_slot4"],
		[KEY_5,     "_slot5"],
	]
	# 立ち上がり検出（押された瞬間）を全アクションキーで一括チェック
	var any_action_just_pressed: bool = false
	for entry in action_keys:
		var k: int = entry[0]
		var pressed: bool = Input.is_key_pressed(k)
		var was: bool = bool(_action_keys_was_pressed.get(k, false))
		if pressed and not was:
			# 立ち上がり → 即実行 + INITIAL_REPEAT_DELAY 待ち
			_dispatch_action(String(entry[1]))
			_action_cooldown = INITIAL_REPEAT_DELAY
			any_action_just_pressed = true
		_action_keys_was_pressed[k] = pressed

	# 連続リピート期: 立ち上がり処理を行わなかった場合のみ、長押し中キーで cooldown 経過したら再発動
	if not any_action_just_pressed and _action_cooldown <= 0.0:
		for entry in action_keys:
			var k: int = entry[0]
			if Input.is_key_pressed(k):
				_dispatch_action(String(entry[1]))
				_action_cooldown = ACTION_REPEAT_DELAY
				break  # 同時押し時は table 上位のものだけ発動（旧挙動と整合）


## v0.9.6: action 種別 → 実行関数のディスパッチ。`_process()` をスッキリさせるため抽出。
func _dispatch_action(name: String) -> void:
	match name:
		"_turn_ccw":  _player_action_turn(-1)
		"_turn_cw":   _player_action_turn(1)
		"_wait_heal": _player_action_wait_and_heal()
		"_slot1":     _cast_slot(1)
		"_slot2":     _cast_slot(2)
		"_slot3":     _cast_slot(3)
		"_slot4":     _cast_slot(4)
		"_slot5":     _cast_slot(5)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if game_over:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_start_new_loop()
			queue_redraw()
			_update_hud()
		return

	# 別ウィンドウ表示中はキー無視（ウィンドウ側でフォーカス処理）
	if spell_builder_window != null:
		return

	# v0.9.3: 移動/旋回/詠唱/待機は _process で polling 処理（長押し連続）。
	# 単発の F (ウィンドウ開く) / Enter (階段) / Tab (プレビュースロット切替) のみここで処理。
	# v0.9.4: INC-3 検証用 DEBUG キー H/T/G は削除（INC-3 検証完了済み、INC-3.5 では不要）。
	# v0.9.7: Tab で _active_preview_slot を 1→2→3→4→5→1 で巡回切替。詠唱発火はしない、
	#         スロットキー (1-5) は従来通り独立に詠唱を打つ。
	match event.keycode:
		KEY_F:
			_open_spell_builder_modal()
		KEY_ENTER:
			_try_descend_stairs()
		KEY_TAB:
			_cycle_preview_slot()


## v0.9.7: Tab で次のスロットをプレビュー対象に。Lexicon に登録のないスロットも巡回するが、
## 巡回しすぎないよう全空ならスロット 1 に戻す。
func _cycle_preview_slot() -> void:
	for _try in 5:
		_active_preview_slot = (_active_preview_slot % 5) + 1
		if not Lexicon.get_spell_slot(_active_preview_slot).is_empty():
			break
	_log("[color=#8cf]🎯 プレビュー: スロット %d[/color]" % _active_preview_slot)
	_update_hud()
	queue_redraw()


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
## v0.9.7: scaffold=max 事前ブロック (09 §9)。詠唱前に Validator/SpatialResolver を
##   ドライランし、direction_required が立つ呪文（vítt 単独など）は世界時間を消費せず警告のみ。
##   ※コアジレンマを壊さないため、自爆系暴発や case_agreement 違反は事前ブロックしない（実プレイヤーの
##     学習機会を残す）。direction_required は「対象タイル T が確定しない＝詠唱不可」が仕様 (09 §7.3)
##     なので事前ブロックする。
func _cast_slot(slot: int) -> void:
	var tokens_in: Array = Lexicon.get_spell_slot(slot)
	if tokens_in.is_empty():
		_log("[color=#888]スロット %d に魔法が割り当てられていません (F で割当)[/color]" % slot)
		return
	var ruleset: Resource = load("res://data/grammar/phase_intermediate.tres")
	var spatial_ctx = SPATIAL_CONTEXT.from_map_state(MapState)
	# === v0.9.7 事前ブロック: direction_required を Validator で先に検出 ===
	if _is_direction_required_blocked(tokens_in, ruleset):
		_log("[color=#fd0]⚠ スロット %d: 方向語が必要です（vítt / í gegnum に fram / aptr / vinstri / hœgri を加える）— 詠唱を中止[/color]" % slot)
		# 世界時間を消費せず・敵ターンも回さない（タイプミス相当の親切な扱い）
		return

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


## v0.9.7: 詠唱前ドライラン。direction_required が立てば true を返す。
## Validator のみで完結（コア違反扱いの構造的判定）、SpatialResolver は呼ばない。
func _is_direction_required_blocked(tokens_in: Array, ruleset: Resource) -> bool:
	var word_lookup: Callable = Callable(Lexicon, "get_word") if Lexicon.has_method("get_word") else Callable()
	var tokens: Array = SpellTokenizer.tokenize(tokens_in, ruleset, word_lookup)
	var ast: Dictionary = SpellParser.parse(tokens)
	var report: GrammarReport = SpellValidator.validate(ast, ruleset)
	if report == null:
		return false
	for f in report.failures():
		if String(f.get("rule", "")) == "direction_required":
			return true
	return false


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


## INC-3 v0.9.3 (要求 5): F キーで spell_builder.tscn を別 OS ウィンドウで表示。
## Godot 4 の Window ノードを使い、dungeon_view と独立した別ウィンドウとして開く。
## サイズ調整・OS ウィンドウマネージャ操作・ALT+TAB が効く。
func _open_spell_builder_modal() -> void:
	if spell_builder_window != null:
		# 既に開いている → 前面化
		spell_builder_window.grab_focus()
		return
	var scene: PackedScene = load("res://scenes/debug/spell_builder.tscn")
	if scene == null:
		_log("[color=#e88]spell_builder.tscn が読み込めません[/color]")
		return
	# 別ウィンドウを作成
	var win := Window.new()
	win.title = "Spell Builder — 魔法構築 (スロット保存して dungeon に戻る)"
	win.size = Vector2i(1100, 800)
	win.transient = true   # 親ウィンドウと連動（最小化等）
	win.exclusive = false  # 排他しない（dungeon は閉じない、別操作可）
	win.unresizable = false
	win.close_requested.connect(_close_spell_builder_modal)
	# spell_builder シーンを instantiate して window に add_child
	var inst: Node = scene.instantiate()
	win.add_child(inst)
	add_child(win)
	win.popup_centered()
	spell_builder_window = win
	_log("[color=#a0c8f0]F: Spell Builder ウィンドウを開きました (ウィンドウ X で閉じる)[/color]")


## ウィンドウを閉じる。close_requested シグナル / F 再押下 で呼ばれる。
func _close_spell_builder_modal() -> void:
	if spell_builder_window == null:
		return
	spell_builder_window.queue_free()
	spell_builder_window = null
	_log("[color=#888]Spell Builder ウィンドウを閉じました[/color]")
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
			# v0.9.3 (要求 8): 視界外の壁は黒で塗りつぶし（floor の暗いグレーと区別）
			if tile == "wall":
				if visible:
					c = COLOR_WALL
				else:
					c = Color.BLACK  # 視界外の壁は完全黒（既知でも闇に沈む演出）
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

	# === INC-3.5 v0.9.5 (v0.9.7 でアクティブスロット切替対応): scaffold=max 射程プレビュー UI (09 §9) ===
	# `_active_preview_slot` (Tab で 1→2→3→4→5 巡回) の呪文を SpatialResolver でドライランし、
	# 対象タイル/AoE/貫通/range_required をマップ上に描画する。
	# game_over 中や別ウィンドウ展開中は省略（ノイズ低減）。
	if not game_over and spell_builder_window == null:
		_draw_preview_for_slot(_active_preview_slot, origin)


## INC-3.5 v0.9.5: スロットの呪文を SpatialResolver でドライランして射程プレビューを描く。
##   slot: 1-5
##   origin: _draw() で使ったマップ原点（プレイヤー基準）
## scaffold=max の補助 UI を最小実装した版。dungeon_view 用に「常時スロット 1 を表示」する。
func _draw_preview_for_slot(slot: int, origin: Vector2) -> void:
	var tokens_in: Array = Lexicon.get_spell_slot(slot)
	if tokens_in.is_empty() or MapState.map_data == null:
		return
	# 呪文を AST まで通して SpatialResolver にかける（Resolver は使わない＝コスト低）。
	var word_lookup: Callable = Callable(Lexicon, "get_word") if Lexicon.has_method("get_word") else Callable()
	var ruleset: Resource = load("res://data/grammar/phase_intermediate.tres")
	var tokens: Array = SpellTokenizer.tokenize(tokens_in, ruleset, word_lookup)
	var ast: Dictionary = SpellParser.parse(tokens)
	var ctx: SpatialContext = SPATIAL_CONTEXT.from_map_state(MapState)
	var ts: TargetSet = SpatialResolver.resolve(ast, ctx, ruleset)
	if ts == null:
		return

	# 形状判定（AST.ranges から）
	var range_kind: String = ""
	var range_shape: String = ""
	for r in ast.get("ranges", []):
		var rres: WordResource = r.get("resource", null)
		if rres != null:
			range_kind = String(rres.spatial.get("kind", ""))
			if range_kind == "shape":
				var params_dict = rres.spatial.get("params", {})
				if typeof(params_dict) == TYPE_DICTIONARY:
					range_shape = String(params_dict.get("shape", ""))
			break

	# AoE 範囲（黄色、半透明）— 円 AoE のみ center 周辺を塗る
	if range_shape == "circle_aoe" and ts.center_pos.x >= 0:
		var radius: int = 2  # vítt の既定半径
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) + abs(dy) > radius:
					continue
				var tile_pos: Vector2i = ts.center_pos + Vector2i(dx, dy)
				if tile_pos.x < 0 or tile_pos.y < 0 or tile_pos.x >= MapState.map_data.size.x or tile_pos.y >= MapState.map_data.size.y:
					continue
				if not MapState.is_visible(tile_pos):
					continue
				var rp_aoe: Vector2 = origin + Vector2(tile_pos) * TILE_SIZE
				draw_rect(Rect2(rp_aoe, Vector2(TILE_SIZE - 1, TILE_SIZE - 1)), COLOR_PREVIEW_AOE, true)

	# 貫通直線（紫、半透明）— line_pierce のみ
	if range_shape == "line_pierce":
		var dir_vec: Vector2i = Vector2i.ZERO
		for d in ast.get("directions", []):
			var dres: WordResource = d.get("resource", null)
			if dres != null:
				var d_params = dres.spatial.get("params", {})
				var axis: String = String(d_params.get("axis", "")) if typeof(d_params) == TYPE_DICTIONARY else ""
				dir_vec = _vec_for_axis(MapState.player_facing, axis)
				break
		if dir_vec == Vector2i.ZERO:
			dir_vec = MapState.FACING_VECTORS[MapState.player_facing]
		var cur: Vector2i = MapState.player_pos + dir_vec
		for _step in 30:
			if cur.x < 0 or cur.y < 0 or cur.x >= MapState.map_data.size.x or cur.y >= MapState.map_data.size.y:
				break
			if MapState.is_visible(cur):
				var rp_line: Vector2 = origin + Vector2(cur) * TILE_SIZE
				draw_rect(Rect2(rp_line, Vector2(TILE_SIZE - 1, TILE_SIZE - 1)), COLOR_PREVIEW_PIERCE, true)
			cur += dir_vec

	# 対象タイル（緑）
	for tgt in ts.target_tiles:
		var tgt_pos: Vector2i = tgt
		var rp_tgt: Vector2 = origin + Vector2(tgt_pos) * TILE_SIZE
		draw_rect(Rect2(rp_tgt, Vector2(TILE_SIZE - 1, TILE_SIZE - 1)), COLOR_PREVIEW_TARGET, true)

	# range_required で届かない (reachable=false) → 中心マスを赤で枠取り
	if not ts.reachable and ts.center_pos.x >= 0 and MapState.is_visible(ts.center_pos):
		var rp_fail: Vector2 = origin + Vector2(ts.center_pos) * TILE_SIZE
		draw_rect(Rect2(rp_fail + Vector2(2, 2), Vector2(TILE_SIZE - 5, TILE_SIZE - 5)), COLOR_PREVIEW_RANGE_FAIL, false, 2.0)


## SpatialResolver._vec_for_axis の dungeon_view ローカル版（const アクセス回避）
static func _vec_for_axis(facing: int, axis: String) -> Vector2i:
	var rel_offset := 0
	match axis:
		"forward":  rel_offset = 0
		"right":    rel_offset = 1
		"backward": rel_offset = 2
		"left":     rel_offset = 3
		_: return Vector2i.ZERO
	var resolved: int = (facing + rel_offset) % 4
	match resolved:
		0: return Vector2i( 0, -1)
		1: return Vector2i( 1,  0)
		2: return Vector2i( 0,  1)
		3: return Vector2i(-1,  0)
		_: return Vector2i.ZERO


func _update_hud() -> void:
	if hud_label == null:
		return
	var status := GameState.get_status_summary()
	var pos_str: String = "(%d, %d)" % [MapState.player_pos.x, MapState.player_pos.y]
	var facing_names: Array = ["北", "東", "南", "西"]
	var facing_str: String = facing_names[MapState.player_facing]
	var in_sight: int = MapState.enemies_in_sight().size()
	var mode: String = "[警戒]" if in_sight > 0 else "[平時]"
	# v0.9.7: アクティブスロットと呪文プレビューを HUD に表示
	var preview_tokens: Array = Lexicon.get_spell_slot(_active_preview_slot)
	var preview_words: Array = []
	for t in preview_tokens:
		preview_words.append(String(t.get("word_id", "?")))
	var preview_str: String = "(空)" if preview_words.is_empty() else " ".join(preview_words)
	hud_label.text = "%s | 位置 %s 向き %s | 視界内 %d 体 %s | プレビュー: スロット %d [%s]\nWASD/矢印=移動(長押し可・斜め8方向)  Q/E=旋回  1-5=スロット詠唱(±45°扇)  Space=待機+HP回復  Tab=プレビュー切替  F=Spell Builder  Enter=階段" % [
		status, pos_str, facing_str, in_sight, mode, _active_preview_slot, preview_str
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
