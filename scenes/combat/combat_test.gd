extends Control
## combat_test.gd — INC-2 v0.1 戦闘最小縦切り。
##
## 目的: SpellEngine 経由で詠唱した結果を CombatSystem に流し、敵 HP を削って倒すまでの
##       E2E を 1 画面で見せる。spell_builder の語タイル+格選択 UX をシンプル化して移植。
##
## 構成:
##   - 上部: Player HP / Enemy HP / Turn ラベル / 世界時間 Δ
##   - 中部: 使える語タイル + 「現在の呪文」+ 詠唱ボタン
##   - 下部: 戦闘ログ (RichTextLabel)
##
## INC-2 v0.1 スコープ:
##   - 敵 1 体（雑魚）+ ボス 1 体の最小構成（02 §3 / 08 §1）
##   - scaffold_level は ruleset から取得（spell_builder と同じ実装思想）
##   - 敵 AI は固定ダメージ（CombatSystem の既定値）
##
## v0.2 以降で追加予定:
##   - 詠唱前確認 (scaffold=mid)、ライブプレビュー (scaffold=max)
##   - シナリオドロップダウン
##   - スクショ撮影ボタン

const DEFAULT_RULESET_PATH := "res://data/grammar/phase_intro.tres"

const CASE_OPTIONS: Array = ["nom", "acc", "dat", "gen"]
const CASE_LABELS: Dictionary = {
	"nom": "主格",
	"acc": "対格",
	"dat": "与格",
	"gen": "属格",
}

# 戦闘パラメータ（INC-2 v0.1: ハードコード、v0.3 で BalanceConfig 化）
const PLAYER_HP_MAX: float = 100.0
const ENEMY_ZAKO_HP: float = 30.0
const ENEMY_BOSS_HP: float = 80.0
const ENEMY_ZAKO_ATK: float = 8.0
const ENEMY_BOSS_ATK: float = 15.0

# UI 色（spell_builder と同系統）
const COLOR_OK := Color(0.55, 0.95, 0.55)
const COLOR_FAIL := Color(0.95, 0.5, 0.5)
const COLOR_MUTED := Color(0.7, 0.7, 0.75)
const COLOR_ACCENT := Color(0.85, 0.85, 0.95)
const COLOR_PLAYER := Color(0.6, 0.85, 1.0)
const COLOR_ENEMY := Color(1.0, 0.6, 0.6)

# --- 状態 ---
var _ruleset: Resource
var _combat: CombatSystem
var _spell: Array = []  # {word_id, case}
var _c_value: float = 50.0

# --- UI refs ---
var _player_hp_bar: ProgressBar
var _player_hp_label: Label
var _enemy_hp_bar: ProgressBar
var _enemy_hp_label: Label
var _enemy_name_label: Label
var _turn_label: Label
var _world_time_label: Label
var _spell_panel: VBoxContainer
var _preview_label: Label
var _log_label: RichTextLabel
var _cast_button: Button
var _reset_button: Button


func _ready() -> void:
	_ruleset = load(DEFAULT_RULESET_PATH)
	_build_ui()
	_start_new_floor()


# ----------------- UI 構築 -----------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 20
	root.offset_top = 16
	root.offset_right = -20
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# --- タイトル ---
	var title := Label.new()
	title.text = "combat_test — INC-2 v0.1 戦闘最小縦切り"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	root.add_child(HSeparator.new())

	# --- 上部: HP / Turn / Δ ---
	_build_status_panel(root)
	root.add_child(HSeparator.new())

	# --- 中部: 語タイル + 呪文ビルダー ---
	_build_spell_panel(root)
	root.add_child(HSeparator.new())

	# --- 下部: 戦闘ログ ---
	var log_header := Label.new()
	log_header.text = "■ 戦闘ログ"
	log_header.add_theme_font_size_override("font_size", 14)
	log_header.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(log_header)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = true
	_log_label.scroll_following = true
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.custom_minimum_size = Vector2(0, 180)
	_log_label.text = "[i]戦闘開始[/i]"
	root.add_child(_log_label)


func _build_status_panel(root: Node) -> void:
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 24)
	root.add_child(status_row)

	# Player
	var player_box := VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 2)
	player_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(player_box)

	var p_name := Label.new()
	p_name.text = "Player"
	p_name.add_theme_font_size_override("font_size", 13)
	p_name.add_theme_color_override("font_color", COLOR_PLAYER)
	player_box.add_child(p_name)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.min_value = 0
	_player_hp_bar.max_value = PLAYER_HP_MAX
	_player_hp_bar.value = PLAYER_HP_MAX
	_player_hp_bar.custom_minimum_size = Vector2(220, 14)
	_player_hp_bar.show_percentage = false
	player_box.add_child(_player_hp_bar)

	_player_hp_label = Label.new()
	_player_hp_label.text = "HP %d / %d" % [PLAYER_HP_MAX, PLAYER_HP_MAX]
	_player_hp_label.add_theme_font_size_override("font_size", 11)
	player_box.add_child(_player_hp_label)

	# Enemy
	var enemy_box := VBoxContainer.new()
	enemy_box.add_theme_constant_override("separation", 2)
	enemy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(enemy_box)

	_enemy_name_label = Label.new()
	_enemy_name_label.text = "Enemy"
	_enemy_name_label.add_theme_font_size_override("font_size", 13)
	_enemy_name_label.add_theme_color_override("font_color", COLOR_ENEMY)
	enemy_box.add_child(_enemy_name_label)

	_enemy_hp_bar = ProgressBar.new()
	_enemy_hp_bar.min_value = 0
	_enemy_hp_bar.max_value = ENEMY_ZAKO_HP
	_enemy_hp_bar.value = ENEMY_ZAKO_HP
	_enemy_hp_bar.custom_minimum_size = Vector2(220, 14)
	_enemy_hp_bar.show_percentage = false
	enemy_box.add_child(_enemy_hp_bar)

	_enemy_hp_label = Label.new()
	_enemy_hp_label.text = "HP %d / %d" % [ENEMY_ZAKO_HP, ENEMY_ZAKO_HP]
	_enemy_hp_label.add_theme_font_size_override("font_size", 11)
	enemy_box.add_child(_enemy_hp_label)

	# Turn / 世界時間
	var meta_box := VBoxContainer.new()
	meta_box.add_theme_constant_override("separation", 2)
	status_row.add_child(meta_box)

	_turn_label = Label.new()
	_turn_label.text = "あなたのターン (T1)"
	_turn_label.add_theme_font_size_override("font_size", 14)
	meta_box.add_child(_turn_label)

	_world_time_label = Label.new()
	_world_time_label.text = "Δ累積: 0.0"
	_world_time_label.add_theme_font_size_override("font_size", 11)
	_world_time_label.add_theme_color_override("font_color", COLOR_MUTED)
	meta_box.add_child(_world_time_label)


func _build_spell_panel(root: Node) -> void:
	# 使える語タイル
	var tile_header := Label.new()
	tile_header.text = "■ 使える語（クリックで追加）"
	tile_header.add_theme_font_size_override("font_size", 13)
	tile_header.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(tile_header)

	var tiles_row := HBoxContainer.new()
	tiles_row.add_theme_constant_override("separation", 6)
	root.add_child(tiles_row)

	var lex := get_node_or_null("/root/Lexicon")
	if lex != null and lex.has_method("get_known_word_ids"):
		for word_id in lex.get_known_word_ids():
			var res: WordResource = lex.get_word(word_id)
			if res == null:
				continue
			_add_tile_button(tiles_row, res)

	# 現在の呪文
	var spell_header := Label.new()
	spell_header.text = "■ 現在の呪文"
	spell_header.add_theme_font_size_override("font_size", 13)
	spell_header.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(spell_header)

	_spell_panel = VBoxContainer.new()
	_spell_panel.add_theme_constant_override("separation", 4)
	root.add_child(_spell_panel)

	_preview_label = Label.new()
	_preview_label.text = "（語タイルをクリック）"
	_preview_label.add_theme_font_size_override("font_size", 12)
	_preview_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(_preview_label)

	# 詠唱・リセットボタン
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	root.add_child(btn_row)

	_cast_button = Button.new()
	_cast_button.text = "詠唱（1手番）"
	_cast_button.pressed.connect(_on_cast_pressed)
	btn_row.add_child(_cast_button)

	var clear_btn := Button.new()
	clear_btn.text = "呪文クリア"
	clear_btn.pressed.connect(_clear_spell)
	btn_row.add_child(clear_btn)

	_reset_button = Button.new()
	_reset_button.text = "最初から"
	_reset_button.pressed.connect(_start_new_floor)
	btn_row.add_child(_reset_button)


func _add_tile_button(parent: Node, res: WordResource) -> void:
	var btn := Button.new()
	var display := _display_form(res)
	btn.text = "%s\n[%s]" % [display, _word_class_label_ja(res.word_class)]
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(78, 44)
	btn.pressed.connect(_on_tile_pressed.bind(res.id))
	parent.add_child(btn)


func _word_class_label_ja(word_class: String) -> String:
	match word_class:
		"effect": return "効果"
		"target": return "対象"
		"element": return "属性"
		"modifier": return "修飾"
		_: return word_class


func _display_form(res: WordResource) -> String:
	if res.word_class == "target":
		var nom := res.get_inflected("sg", "nom")
		if not nom.is_empty():
			return nom
	return res.id


# ----------------- フロア進行 -----------------

func _start_new_floor() -> void:
	# Player
	var player := Combatant.new("Player", PLAYER_HP_MAX, {})
	# 雑魚 + ボス
	var zako := Combatant.new("雑魚 fjandi", ENEMY_ZAKO_HP, {})
	var boss := Combatant.new("ボス Helgrind 番人", ENEMY_BOSS_HP, {})
	var enemies := [zako, boss]
	var atks := [ENEMY_ZAKO_ATK, ENEMY_BOSS_ATK]

	_combat = CombatSystem.new()
	_combat.turn_changed.connect(_on_turn_changed)
	_combat.damage_dealt.connect(_on_damage_dealt)
	_combat.heal_dealt.connect(_on_heal_dealt)
	_combat.enemy_defeated.connect(_on_enemy_defeated)
	_combat.floor_cleared.connect(_on_floor_cleared)
	_combat.player_defeated.connect(_on_player_defeated)
	_combat.cast_logged.connect(_on_cast_logged)

	_combat.start_floor(player, enemies, atks)
	_spell.clear()
	_redraw_spell_panel()
	_log_label.text = "[i]戦闘開始: vs %s（次は %s）[/i]" % [zako.display_name, boss.display_name]
	_refresh_status()


# ----------------- 詠唱 -----------------

func _on_cast_pressed() -> void:
	if _combat == null or _combat.is_over():
		_log("[color=#aaa](戦闘終了。「最初から」を押してリセット)[/color]")
		return
	if _spell.is_empty():
		_log("[color=#ffaa55]呪文が空です。語タイルをクリックして追加[/color]")
		return

	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		_log("[color=#f88]SpellEngine が起動していません[/color]")
		return

	var result: CastResult = engine.cast(_spell.duplicate(true), _ruleset, {"c_override": _c_value})
	if result == null:
		_log("[color=#f88]詠唱結果なし[/color]")
		return

	# 詠唱前情報
	var spell_text := _preview_text()
	_log("[b]→[/b] 詠唱: %s" % spell_text)

	# 文法レポート要約
	var rep := result.grammar_report
	if rep != null:
		if rep.overall_pass:
			_log("  [color=#8aff8a]✓ 文法 OK (G=%.2f)[/color]" % rep.g_score)
		else:
			_log("  [color=#ff8888]✗ 文法 NG (G=%.2f)[/color]" % rep.g_score)
			for f in rep.failures():
				var reason := String(f.get("reason", ""))
				var recommended := String(f.get("recommended", ""))
				if recommended.is_empty():
					_log("    [color=#f88]・%s[/color]" % reason)
				else:
					_log("    [color=#f88]・%s → [color=#fc0]%s[/color][/color]" % [reason, recommended])

	# ダメージ計算 + 適用（CombatSystem 内）。token 数は _spell.size、tier_sum は EffectSpec から。
	var tier_sum: int = result.effect_spec.tier_sum if result.effect_spec != null else 0
	var info := _combat.apply_cast(result, _spell.size(), tier_sum)
	_log("  Δ %.1f, %s" % [info["delta"], String(info["log_summary"])])

	_refresh_status()

	# 敵ターン進行（戦闘終了でなければ）
	if _combat.is_over():
		return
	# 即座に敵ターンを処理（INC-2 v0.1 はリアルタイム遅延なし）
	var einfo := _combat.enemy_turn()
	if einfo["damage"] > 0.0:
		_log("  [color=#f88]← %s の攻撃: %d ダメージ[/color]" % [einfo["attacker_name"], int(einfo["damage"])])
	_refresh_status()


func _on_tile_pressed(word_id: String) -> void:
	if _combat != null and _combat.is_over():
		return
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return
	var res: WordResource = lex.get_word(word_id)
	if res == null:
		return
	var default_case := ""
	if res.word_class == "target":
		default_case = "acc"
	elif res.word_class == "modifier" and res.has_gendered_inflection():
		default_case = _get_current_target_case()
		if default_case.is_empty():
			default_case = "acc"
	var new_entry := {"word_id": word_id, "case": default_case}
	if res.word_class == "modifier" and res.has_gendered_inflection():
		var t_idx := _find_target_index()
		if t_idx >= 0:
			_spell.insert(t_idx, new_entry)
			_redraw_spell_panel()
			return
	_spell.append(new_entry)
	_redraw_spell_panel()


func _clear_spell() -> void:
	_spell.clear()
	_redraw_spell_panel()


# ----------------- スペル UI 描画 -----------------

func _redraw_spell_panel() -> void:
	for child in _spell_panel.get_children():
		child.queue_free()
	var lex := get_node_or_null("/root/Lexicon")
	for slot_idx in _spell.size():
		var entry: Dictionary = _spell[slot_idx]
		var word_id := String(entry.get("word_id", ""))
		var res: WordResource = null
		if lex != null:
			res = lex.get_word(word_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_spell_panel.add_child(row)

		var num_label := Label.new()
		num_label.text = "%d." % (slot_idx + 1)
		num_label.custom_minimum_size = Vector2(22, 0)
		row.add_child(num_label)

		var label := Label.new()
		var display := word_id
		var class_label := "?"
		if res != null:
			var cur_case := String(entry.get("case", ""))
			if res.word_class == "target" and not cur_case.is_empty():
				display = res.get_inflected("sg", cur_case)
			elif res.word_class == "modifier" and res.has_gendered_inflection() and not cur_case.is_empty():
				var tgender := _get_current_target_gender()
				if not tgender.is_empty():
					display = res.get_inflected("sg", cur_case, tgender)
			if display.is_empty():
				display = _display_form(res)
			class_label = _word_class_label_ja(res.word_class)
		label.text = "%s（%s）" % [display, class_label]
		label.custom_minimum_size = Vector2(130, 0)
		row.add_child(label)

		var show_case: bool = res != null and (
			res.word_class == "target"
			or (res.word_class == "modifier" and res.has_gendered_inflection())
		)
		if show_case:
			var opt := OptionButton.new()
			for i in CASE_OPTIONS.size():
				opt.add_item(String(CASE_LABELS.get(CASE_OPTIONS[i], CASE_OPTIONS[i])), i)
			var cur := String(entry.get("case", "acc"))
			var idx := CASE_OPTIONS.find(cur)
			if idx < 0:
				idx = 0
			opt.select(idx)
			opt.item_selected.connect(_on_case_changed.bind(slot_idx))
			row.add_child(opt)

		var rm_btn := Button.new()
		rm_btn.text = "×"
		rm_btn.pressed.connect(_on_remove_pressed.bind(slot_idx))
		row.add_child(rm_btn)

	_update_preview()


func _on_case_changed(idx: int, slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _spell.size():
		return
	_spell[slot_idx]["case"] = CASE_OPTIONS[idx]
	_redraw_spell_panel()


func _on_remove_pressed(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _spell.size():
		return
	_spell.remove_at(slot_idx)
	_redraw_spell_panel()


func _update_preview() -> void:
	_preview_label.text = "詠唱: " + _preview_text()


func _preview_text() -> String:
	if _spell.is_empty():
		return "（語タイルをクリック）"
	var lex := get_node_or_null("/root/Lexicon")
	var target_gender := _get_current_target_gender()
	var parts: PackedStringArray = PackedStringArray()
	for entry in _spell:
		var word_id := String(entry.get("word_id", ""))
		var case_id := String(entry.get("case", ""))
		if lex == null:
			parts.append(word_id)
			continue
		var res: WordResource = lex.get_word(word_id)
		if res == null:
			parts.append(word_id)
			continue
		var form := ""
		if res.word_class == "target" and not case_id.is_empty():
			form = res.get_inflected("sg", case_id)
		elif res.word_class == "modifier" and res.has_gendered_inflection() and not case_id.is_empty() and not target_gender.is_empty():
			form = res.get_inflected("sg", case_id, target_gender)
		if form.is_empty():
			form = _display_form(res)
		parts.append(form)
	return " ".join(parts)


# ----------------- ヘルパ（spell_builder と同等の最小版） -----------------

func _find_target_index() -> int:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return -1
	for i in _spell.size():
		var word_id := String(_spell[i].get("word_id", ""))
		var res: WordResource = lex.get_word(word_id)
		if res != null and res.word_class == "target":
			return i
	return -1


func _get_current_target_case() -> String:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return ""
	for entry in _spell:
		var word_id := String(entry.get("word_id", ""))
		var res: WordResource = lex.get_word(word_id)
		if res != null and res.word_class == "target":
			return String(entry.get("case", ""))
	return ""


func _get_current_target_gender() -> String:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return ""
	for entry in _spell:
		var word_id := String(entry.get("word_id", ""))
		var res: WordResource = lex.get_word(word_id)
		if res != null and res.word_class == "target":
			return res.gender
	return ""


# ----------------- 状態反映 -----------------

func _refresh_status() -> void:
	if _combat == null:
		return
	var snap := _combat.snapshot()
	# Player
	if snap.has("player") and snap["player"] != null:
		var p = snap["player"]
		_player_hp_bar.max_value = float(p["max_hp"])
		_player_hp_bar.value = float(p["hp"])
		_player_hp_label.text = "HP %d / %d" % [int(p["hp"]), int(p["max_hp"])]
	# Enemy
	var enemy := _combat.current_enemy()
	if enemy != null:
		_enemy_name_label.text = enemy.display_name
		_enemy_hp_bar.max_value = enemy.max_hp
		_enemy_hp_bar.value = enemy.hp
		_enemy_hp_label.text = "HP %d / %d" % [int(enemy.hp), int(enemy.max_hp)]
	else:
		_enemy_name_label.text = "（敵なし）"
		_enemy_hp_bar.value = 0
		_enemy_hp_label.text = "—"
	# Turn / Δ
	var turn_str := "ターン %d: " % snap["turn"]
	match snap["state"]:
		CombatSystem.State.PLAYER_TURN:
			turn_str += "あなたのターン"
		CombatSystem.State.ENEMY_TURN:
			turn_str += "敵のターン"
		CombatSystem.State.FLOOR_CLEAR:
			turn_str = "🏁 フロアクリア！"
		CombatSystem.State.DEFEAT:
			turn_str = "💀 敗北"
	_turn_label.text = turn_str
	_world_time_label.text = "Δ累積: %.1f" % snap["world_time_delta_total"]


# ----------------- CombatSystem シグナル受信 -----------------

func _on_turn_changed(_new_state: int) -> void:
	_refresh_status()


func _on_damage_dealt(target_name: String, amount: float) -> void:
	# apply_cast 内で詳細ログは出しているため、シグナル側はサマリ無し
	pass


func _on_heal_dealt(target_name: String, amount: float) -> void:
	_log("  [color=#fc0](回復) %s に +%.1f[/color]" % [target_name, amount])


func _on_enemy_defeated(_index: int, enemy_name: String) -> void:
	_log("[b][color=#8aff8a]🗡 %s を撃破！[/color][/b]" % enemy_name)


func _on_floor_cleared() -> void:
	_log("[b][color=#80ffd0]🏁 フロアクリア！[/color][/b]")
	_log("  ターン数: %d / Δ累積: %.1f" % [_combat.turn_count, _combat.world_time_delta_total])


func _on_player_defeated() -> void:
	_log("[b][color=#ff8080]💀 敗北... 「最初から」を押してリセット[/color][/b]")
	_log("  ターン数: %d / Δ累積: %.1f" % [_combat.turn_count, _combat.world_time_delta_total])


func _on_cast_logged(_entry: Dictionary) -> void:
	# CombatSystem 側のログは既に apply_cast の戻り値経由で表示済み
	pass


# ----------------- ログ -----------------

func _log(msg: String) -> void:
	if _log_label == null:
		return
	_log_label.append_text("\n" + msg)
