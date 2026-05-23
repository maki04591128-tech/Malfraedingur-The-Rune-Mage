extends Control
## combat_test.gd — INC-2 v0.4 戦闘最小縦切り（フル機能版）。
##
## 目的: SpellEngine 経由で詠唱した結果を CombatSystem に流し、敵 HP を削って倒すまでの
##       E2E を 1 画面で見せる。spell_builder と同水準の周辺機能（ruleset 切替・C スライダ・
##       シナリオドロップダウン・チューニングパネル）を備える。
##
## 構成:
##   - 1 段目: ruleset OptionButton + C スライダ
##   - 2 段目: シナリオ OptionButton + 説明
##   - 3 段目: Player HP / Enemy HP / Turn ラベル / 世界時間 Δ
##   - 中部: 使える語タイル + 「現在の呪文」+ 詠唱ボタン + チューニングパネル
##   - 下部: 戦闘ログ (RichTextLabel)
##
## INC-2 v0.4 で追加:
##   - A: scenario_option (tests/scenarios/combat/index.json から自動ロード)
##   - B: ruleset_option / C スライダ (spell_builder と同形)
##   - C: チューニングパネル (DAMAGE_SCALE / enemy_zako_hp/atk / enemy_boss_hp/atk)
##   - D: ボス出現演出 + 暴発カテゴリ別色分け
##
## v0.5 以降で追加予定:
##   - ライブプレビュー (scaffold=max)
##   - 詠唱前確認 (scaffold=mid)
##   - チュートリアル / オンボーディング

const RULESETS: Array = [
	{"id": "phase_intro",        "label": "入門",   "path": "res://data/grammar/phase_intro.tres"},
	{"id": "phase_beginner",     "label": "初級",   "path": "res://data/grammar/phase_beginner.tres"},
	{"id": "phase_intermediate", "label": "中級",   "path": "res://data/grammar/phase_intermediate.tres"},
	{"id": "phase_advanced",     "label": "上級",   "path": "res://data/grammar/phase_advanced.tres"},
]
const DEFAULT_RULESET_INDEX: int = 0

const SCENARIO_INDEX_PATH := "res://tests/scenarios/combat/index.json"

const CASE_OPTIONS: Array = ["nom", "acc", "dat", "gen"]
const CASE_LABELS: Dictionary = {
	"nom": "主格",
	"acc": "対格",
	"dat": "与格",
	"gen": "属格",
}

# UI 色
const COLOR_OK := Color(0.55, 0.95, 0.55)
const COLOR_FAIL := Color(0.95, 0.5, 0.5)
const COLOR_MUTED := Color(0.7, 0.7, 0.75)
const COLOR_ACCENT := Color(0.85, 0.85, 0.95)
const COLOR_PLAYER := Color(0.6, 0.85, 1.0)
const COLOR_ENEMY := Color(1.0, 0.6, 0.6)
const COLOR_BOSS := Color(1.0, 0.4, 0.4)

# 暴発カテゴリ別の色（v0.4・D 要件）
const MISFIRE_COLORS: Dictionary = {
	"activation": "#a0a0a0",  # 灰: 不発系
	"execution":  "#ff9844",  # 橙: 実行失敗系
	"control":    "#ff5050",  # 赤: 自爆/反転
}
const MISFIRE_ICONS: Dictionary = {
	"activation": "○",  # 不発
	"execution":  "◇",  # ズレ
	"control":    "✸",  # 自爆
}

# 戦闘パラメータ既定値（v0.4 で _enemy_*_hp/atk に var 化、チューニング可能）
const PLAYER_HP_MAX: float = 100.0
const DEFAULT_ZAKO_HP: float = 30.0
const DEFAULT_BOSS_HP: float = 80.0
const DEFAULT_ZAKO_ATK: float = 8.0
const DEFAULT_BOSS_ATK: float = 15.0

# --- 状態 ---
var _ruleset: Resource
var _ruleset_index: int = DEFAULT_RULESET_INDEX
var _c_value: float = 50.0
var _combat: CombatSystem
var _spell: Array = []
var _scenarios: Array = []

# チューニング可能な敵パラメータ
var _enemy_zako_hp: float = DEFAULT_ZAKO_HP
var _enemy_boss_hp: float = DEFAULT_BOSS_HP
var _enemy_zako_atk: float = DEFAULT_ZAKO_ATK
var _enemy_boss_atk: float = DEFAULT_BOSS_ATK

# --- UI refs ---
var _ruleset_option: OptionButton
var _ruleset_info_label: Label
var _c_slider: HSlider
var _c_label: Label
var _scenario_option: OptionButton
var _scenario_desc_label: Label

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
	_ruleset = _load_ruleset(_ruleset_index)
	_load_scenarios()
	_build_ui()
	_start_new_floor()


# ----------------- 外部データロード -----------------

func _load_ruleset(idx: int) -> Resource:
	if idx < 0 or idx >= RULESETS.size():
		return null
	return load(String(RULESETS[idx]["path"]))


func _load_scenarios() -> void:
	_scenarios.clear()
	var index_file := FileAccess.open(SCENARIO_INDEX_PATH, FileAccess.READ)
	if index_file == null:
		return
	var index_text := index_file.get_as_text()
	index_file.close()
	var index_data: Variant = JSON.parse_string(index_text)
	if typeof(index_data) != TYPE_DICTIONARY:
		return
	var files: Array = index_data.get("scenarios", [])
	for fname in files:
		var path := "res://tests/scenarios/combat/" + String(fname)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var scn: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(scn) == TYPE_DICTIONARY:
			_scenarios.append(scn)


# ----------------- UI 構築 -----------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 20
	root.offset_top = 14
	root.offset_right = -20
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# タイトル
	var title := Label.new()
	title.text = "combat_test — INC-2 v0.4 戦闘最小縦切り"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	root.add_child(HSeparator.new())

	# 1 段目: ruleset + C
	_build_ruleset_and_c_row(root)
	# 2 段目: シナリオ
	_build_scenario_row(root)
	root.add_child(HSeparator.new())
	# 3 段目: ステータス
	_build_status_panel(root)
	root.add_child(HSeparator.new())
	# 中部: 呪文 UI
	_build_spell_panel(root)
	# チューニングパネル
	_build_tuning_panel(root)
	root.add_child(HSeparator.new())
	# 戦闘ログ
	_build_log(root)


func _build_ruleset_and_c_row(root: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)

	var ruleset_prefix := Label.new()
	ruleset_prefix.text = "ruleset:"
	row.add_child(ruleset_prefix)

	_ruleset_option = OptionButton.new()
	for i in RULESETS.size():
		_ruleset_option.add_item(String(RULESETS[i]["label"]), i)
	_ruleset_option.select(_ruleset_index)
	_ruleset_option.item_selected.connect(_on_ruleset_changed)
	row.add_child(_ruleset_option)

	_ruleset_info_label = Label.new()
	_ruleset_info_label.add_theme_font_size_override("font_size", 11)
	_ruleset_info_label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(_ruleset_info_label)

	# C スライダ
	var c_prefix := Label.new()
	c_prefix.text = "C (理解度):"
	c_prefix.size_flags_horizontal = Control.SIZE_SHRINK_END
	c_prefix.size_flags_stretch_ratio = 0.0
	row.add_child(c_prefix)

	_c_slider = HSlider.new()
	_c_slider.min_value = 0.0
	_c_slider.max_value = 100.0
	_c_slider.step = 1.0
	_c_slider.value = _c_value
	_c_slider.custom_minimum_size = Vector2(220, 0)
	_c_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_c_slider.value_changed.connect(_on_c_changed)
	row.add_child(_c_slider)

	_c_label = Label.new()
	_c_label.text = "%d" % int(_c_value)
	_c_label.custom_minimum_size = Vector2(34, 0)
	row.add_child(_c_label)

	_update_ruleset_info()


func _build_scenario_row(root: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	var prefix := Label.new()
	prefix.text = "シナリオ:"
	row.add_child(prefix)

	_scenario_option = OptionButton.new()
	_scenario_option.add_item("（手動）", -1)
	for i in _scenarios.size():
		var scn: Dictionary = _scenarios[i]
		_scenario_option.add_item(String(scn.get("name", "scenario %d" % i)), i)
	_scenario_option.select(0)
	_scenario_option.item_selected.connect(_on_scenario_selected)
	row.add_child(_scenario_option)

	_scenario_desc_label = Label.new()
	_scenario_desc_label.add_theme_font_size_override("font_size", 11)
	_scenario_desc_label.add_theme_color_override("font_color", COLOR_MUTED)
	_scenario_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scenario_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_scenario_desc_label)


func _build_status_panel(root: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	root.add_child(row)

	# Player
	var player_box := VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 2)
	player_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(player_box)

	var p_name := Label.new()
	p_name.text = "Player"
	p_name.add_theme_color_override("font_color", COLOR_PLAYER)
	player_box.add_child(p_name)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.min_value = 0
	_player_hp_bar.max_value = PLAYER_HP_MAX
	_player_hp_bar.value = PLAYER_HP_MAX
	_player_hp_bar.custom_minimum_size = Vector2(220, 16)
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
	row.add_child(enemy_box)

	_enemy_name_label = Label.new()
	_enemy_name_label.text = "Enemy"
	_enemy_name_label.add_theme_color_override("font_color", COLOR_ENEMY)
	enemy_box.add_child(_enemy_name_label)

	_enemy_hp_bar = ProgressBar.new()
	_enemy_hp_bar.min_value = 0
	_enemy_hp_bar.max_value = _enemy_zako_hp
	_enemy_hp_bar.value = _enemy_zako_hp
	_enemy_hp_bar.custom_minimum_size = Vector2(220, 16)
	_enemy_hp_bar.show_percentage = false
	enemy_box.add_child(_enemy_hp_bar)

	_enemy_hp_label = Label.new()
	_enemy_hp_label.text = "HP %d / %d" % [_enemy_zako_hp, _enemy_zako_hp]
	_enemy_hp_label.add_theme_font_size_override("font_size", 11)
	enemy_box.add_child(_enemy_hp_label)

	# Turn / Δ
	var meta_box := VBoxContainer.new()
	meta_box.add_theme_constant_override("separation", 2)
	row.add_child(meta_box)

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


# ----------------- チューニングパネル (Task C) -----------------

func _build_tuning_panel(root: Node) -> void:
	var toggle := CheckButton.new()
	toggle.text = "チューニング (DAMAGE_SCALE / 敵 HP / 敵 ATK)"
	toggle.add_theme_font_size_override("font_size", 12)
	root.add_child(toggle)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)
	panel.visible = false
	root.add_child(panel)

	toggle.toggled.connect(func(pressed: bool): panel.visible = pressed)

	_add_tuning_slider(panel, "DAMAGE_SCALE (×)", 0.5, 10.0, 0.25,
		DamageCalculator.DAMAGE_SCALE,
		func(v: float): DamageCalculator.DAMAGE_SCALE = v)
	_add_tuning_slider(panel, "雑魚 HP", 5.0, 200.0, 5.0,
		_enemy_zako_hp,
		func(v: float): _enemy_zako_hp = v)
	_add_tuning_slider(panel, "雑魚 ATK", 0.0, 50.0, 1.0,
		_enemy_zako_atk,
		func(v: float): _enemy_zako_atk = v)
	_add_tuning_slider(panel, "ボス HP", 20.0, 400.0, 10.0,
		_enemy_boss_hp,
		func(v: float): _enemy_boss_hp = v)
	_add_tuning_slider(panel, "ボス ATK", 0.0, 80.0, 1.0,
		_enemy_boss_atk,
		func(v: float): _enemy_boss_atk = v)

	var hint := Label.new()
	hint.text = "敵 HP/ATK の変更は「最初から」で反映"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	panel.add_child(hint)


func _add_tuning_slider(parent: Node, label_text: String, min_v: float, max_v: float,
		step_v: float, default_v: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.custom_minimum_size = Vector2(220, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = default_v
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%.2f" % default_v
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.custom_minimum_size = Vector2(54, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float):
		value_label.text = "%.2f" % v
		on_change.call(v))


func _build_log(root: Node) -> void:
	var log_header := Label.new()
	log_header.text = "■ 戦闘ログ"
	log_header.add_theme_font_size_override("font_size", 13)
	log_header.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(log_header)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = true
	_log_label.scroll_following = true
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.custom_minimum_size = Vector2(0, 160)
	_log_label.text = "[i]戦闘開始[/i]"
	root.add_child(_log_label)


# ----------------- イベントハンドラ -----------------

func _on_ruleset_changed(idx: int) -> void:
	_ruleset_index = idx
	_ruleset = _load_ruleset(idx)
	_update_ruleset_info()


func _update_ruleset_info() -> void:
	if _ruleset == null:
		_ruleset_info_label.text = ""
		return
	var enabled: PackedStringArray = PackedStringArray()
	for rule in ["case_agreement", "word_order", "elements", "modifier"]:
		if _ruleset.has_method("is_rule_enabled") and _ruleset.is_rule_enabled(rule):
			enabled.append(rule)
	var scaffold: String = String(_ruleset.get("scaffold_level"))
	_ruleset_info_label.text = "(scaffold=%s, %s)" % [scaffold, ", ".join(enabled)]


func _on_c_changed(value: float) -> void:
	_c_value = value
	_c_label.text = "%d" % int(value)


func _on_scenario_selected(option_idx: int) -> void:
	var meta_id: int = _scenario_option.get_item_id(option_idx)
	if meta_id < 0:
		_scenario_desc_label.text = ""
		return
	if meta_id < 0 or meta_id >= _scenarios.size():
		return
	var scn: Dictionary = _scenarios[meta_id]
	_scenario_desc_label.text = String(scn.get("description", ""))

	# ruleset 切替
	var ruleset_id := String(scn.get("ruleset_id", ""))
	if not ruleset_id.is_empty():
		for i in RULESETS.size():
			if String(RULESETS[i]["id"]) == ruleset_id:
				_ruleset_index = i
				_ruleset = _load_ruleset(i)
				_ruleset_option.select(i)
				_update_ruleset_info()
				break

	# C 値
	if scn.has("c_override"):
		_c_value = float(scn["c_override"])
		_c_slider.value = _c_value
		_c_label.text = "%d" % int(_c_value)

	# 敵パラメータ
	var enemies_data: Array = scn.get("enemies", [])
	if enemies_data.size() >= 1:
		_enemy_zako_hp = float(enemies_data[0].get("hp", DEFAULT_ZAKO_HP))
		_enemy_zako_atk = float(enemies_data[0].get("atk", DEFAULT_ZAKO_ATK))
	if enemies_data.size() >= 2:
		_enemy_boss_hp = float(enemies_data[1].get("hp", DEFAULT_BOSS_HP))
		_enemy_boss_atk = float(enemies_data[1].get("atk", DEFAULT_BOSS_ATK))
	# 敵 1 体のみのシナリオ (C1/C2/C4) はボスを既定値で残す

	# tokens を呪文に流し込み
	var tokens_data: Array = scn.get("tokens", [])
	_spell.clear()
	for t in tokens_data:
		if typeof(t) == TYPE_DICTIONARY:
			_spell.append({
				"word_id": String(t.get("word_id", "")),
				"case": String(t.get("case", "")),
			})

	# フロアリセット
	_start_new_floor()
	_log("[i]シナリオ %s 開始[/i]" % String(scn.get("id", "?")))


# ----------------- フロア進行 -----------------

func _start_new_floor() -> void:
	var player := Combatant.new("Player", PLAYER_HP_MAX, {})
	var zako := Combatant.new("雑魚 fjandi", _enemy_zako_hp, {})
	var boss := Combatant.new("ボス Helgrind 番人", _enemy_boss_hp, {})
	var enemies := [zako, boss]
	var atks := [_enemy_zako_atk, _enemy_boss_atk]

	_combat = CombatSystem.new()
	_combat.turn_changed.connect(_on_turn_changed)
	_combat.heal_dealt.connect(_on_heal_dealt)
	_combat.enemy_defeated.connect(_on_enemy_defeated)
	_combat.floor_cleared.connect(_on_floor_cleared)
	_combat.player_defeated.connect(_on_player_defeated)

	_combat.start_floor(player, enemies, atks)
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

	_log("[b]→[/b] 詠唱: %s" % _preview_text())

	# 文法レポート
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

	# 暴発演出 (D 要件)
	if result.resolved != null and result.resolved.misfired:
		var cat := result.resolved.misfire_category
		var outcome := result.resolved.misfire_outcome
		var color := String(MISFIRE_COLORS.get(cat, "#ff8888"))
		var icon := String(MISFIRE_ICONS.get(cat, "✗"))
		_log("  [color=%s][b]%s 暴発: %s / %s[/b][/color]" % [color, icon, cat, outcome])

	# CombatSystem へ適用
	var tier_sum := result.effect_spec.tier_sum if result.effect_spec != null else 0
	var info := _combat.apply_cast(result, _spell.size(), tier_sum)
	_log("  Δ %.1f, %s" % [info["delta"], String(info["log_summary"])])

	_refresh_status()

	if _combat.is_over():
		return
	# 敵ターン
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


# ----------------- 呪文 UI 描画 -----------------

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


# ----------------- ヘルパ -----------------

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
	if snap.has("player") and snap["player"] != null:
		var p = snap["player"]
		_player_hp_bar.max_value = float(p["max_hp"])
		_player_hp_bar.value = float(p["hp"])
		_player_hp_label.text = "HP %d / %d" % [int(p["hp"]), int(p["max_hp"])]
	var enemy := _combat.current_enemy()
	if enemy != null:
		_enemy_name_label.text = enemy.display_name
		_enemy_hp_bar.max_value = enemy.max_hp
		_enemy_hp_bar.value = enemy.hp
		_enemy_hp_label.text = "HP %d / %d" % [int(enemy.hp), int(enemy.max_hp)]
		# ボス色付け (D 要件): current_enemy_index >= 1 はボス相当
		if _combat.current_enemy_index >= 1:
			_enemy_name_label.add_theme_color_override("font_color", COLOR_BOSS)
		else:
			_enemy_name_label.add_theme_color_override("font_color", COLOR_ENEMY)
	else:
		_enemy_name_label.text = "（敵なし）"
		_enemy_hp_bar.value = 0
		_enemy_hp_label.text = "—"

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


# ----------------- シグナル受信 -----------------

func _on_turn_changed(_new_state: int) -> void:
	_refresh_status()


func _on_heal_dealt(target_name: String, amount: float) -> void:
	_log("  [color=#fc0](回復) %s に +%.1f[/color]" % [target_name, amount])


func _on_enemy_defeated(index: int, enemy_name: String) -> void:
	_log("[b][color=#8aff8a]🗡 %s を撃破！[/color][/b]" % enemy_name)
	# ボス出現演出 (D 要件): index=0 を倒した直後＝次はボス
	if _combat != null and index == 0 and _combat.current_enemy_index < _combat.enemies.size():
		var next_enemy: Combatant = _combat.enemies[_combat.current_enemy_index]
		_log("")
		_log("[b][color=#ff5050]⚔  ボス出現: %s[/color][/b]" % next_enemy.display_name)
		_log("[color=#aaa]   (HP %d / 攻撃力 %d)[/color]" % [
			int(next_enemy.max_hp),
			int(_combat.enemy_attack_damage[_combat.current_enemy_index]) if _combat.current_enemy_index < _combat.enemy_attack_damage.size() else 0
		])


func _on_floor_cleared() -> void:
	_log("[b][color=#80ffd0]🏁 フロアクリア！[/color][/b]")
	_log("  ターン数: %d / Δ累積: %.1f" % [_combat.turn_count, _combat.world_time_delta_total])


func _on_player_defeated() -> void:
	_log("[b][color=#ff8080]💀 敗北... 「最初から」を押してリセット[/color][/b]")
	_log("  ターン数: %d / Δ累積: %.1f" % [_combat.turn_count, _combat.world_time_delta_total])


# ----------------- ログ -----------------

func _log(msg: String) -> void:
	if _log_label == null:
		return
	_log_label.append_text("\n" + msg)
