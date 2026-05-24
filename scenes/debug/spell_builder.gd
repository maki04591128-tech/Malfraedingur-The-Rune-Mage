extends Control
## spell_builder.gd — INC-1 自由構築 UI（タイル列ビルダー）。
##
## 目的: 4 パターン固定の spell_lab を超えて、任意の語列を組み立てて試せる探索的ラボ。
##       06_INC1検証仕様.md §2.1 のタイル列ビルダー相当（最小版）。
##
## 操作:
##   - 上段の「使える語」タイルをクリック → 「現在の呪文」へ追加
##   - target 語（fjandi/sjalfr）には格選択（主格/対格）がつく
##   - 効果語・属性語は格不要
##   - 順序変更は最初は省略（クリア→組み直し）
##   - 1回/10回/100回詠唱で SpellEngine.cast() を呼び結果表示
##
## 後続増分:
##   - 上下矢印で順序入れ替え（S6 を builder 上で試せる）
##   - ruleset 切替ドロップダウン
##   - チューニングパネル
##   - 無辞書経路（unknown_word ×4）— INC-2/3

## 利用可能な ruleset 一覧（label, path）。v0.16: 4 段階に拡張。INC-2 以降で無辞書を追加。
const RULESETS: Array = [
	{"id": "phase_intro",        "label": "入門",   "path": "res://data/grammar/phase_intro.tres"},
	{"id": "phase_beginner",     "label": "初級",   "path": "res://data/grammar/phase_beginner.tres"},
	{"id": "phase_intermediate", "label": "中級",   "path": "res://data/grammar/phase_intermediate.tres"},
	{"id": "phase_advanced",     "label": "上級",   "path": "res://data/grammar/phase_advanced.tres"},
]
const DEFAULT_RULESET_INDEX: int = 0

const SMALL_BATCH_N: int = 10
const MEDIUM_BATCH_N: int = 100
const LARGE_BATCH_N: int = 200  # v0.17 (06 §2.3): 統計信頼性のため 200 回必須バッチ

const COLOR_OK := Color(0.55, 0.95, 0.55)
const COLOR_FAIL := Color(0.95, 0.5, 0.5)
const COLOR_MUTED := Color(0.7, 0.7, 0.75)
const COLOR_ACCENT := Color(0.85, 0.85, 0.95)
const COLOR_TILE_EFFECT  := Color(0.95, 0.55, 0.55)  # 赤系
const COLOR_TILE_TARGET  := Color(0.55, 0.75, 0.95)  # 青系
const COLOR_TILE_ELEMENT := Color(0.55, 0.95, 0.65)  # 緑系
const COLOR_TILE_OTHER   := Color(0.85, 0.85, 0.85)

# 格選択肢（v0.14 で 4 格対応）。
const CASE_OPTIONS: Array = ["nom", "acc", "dat", "gen"]
const CASE_LABELS: Dictionary = {
	"nom": "主格 nom",
	"acc": "対格 acc",
	"dat": "与格 dat",
	"gen": "属格 gen",
}

## v0.17 (06 §3): シナリオ JSON 一覧の格納パス。
const SCENARIO_INDEX_PATH := "res://tests/scenarios/index.json"

var _ruleset: Resource
var _ruleset_index: int = DEFAULT_RULESET_INDEX
var _c_value: float = 50.0

var _c_slider: HSlider
var _c_label: Label
var _ruleset_option: OptionButton
var _ruleset_info_label: Label
var _spell_panel: VBoxContainer
var _preview_label: Label
var _result_label: RichTextLabel
# v0.16: scaffold 補助の UI 要素
var _live_preview_label: RichTextLabel  # max のみ表示
var _hint_button: Button                # mid のみ表示
var _confirm_dialog: ConfirmationDialog # mid 詠唱前確認
var _pending_cast: Dictionary = {}      # 確認後に再開する詠唱情報
# v0.17: シナリオ呼び出し + 計測
var _scenario_option: OptionButton
var _scenarios: Array = []  # ロード済みシナリオ辞書の配列
var _scenario_desc_label: Label
var _timer_label: Label
var _ready_time_ms: int = 0
var _first_pass_time_ms: int = 0
var _cast_count: int = 0
var _pass_count: int = 0

## 現在組み立てた呪文。各要素: {word_id: String, case: String}
## case は target 以外は "" のまま。
var _spell: Array = []


func _ready() -> void:
	_ruleset = _load_ruleset(_ruleset_index)
	_load_scenarios()
	_ready_time_ms = Time.get_ticks_msec()
	_build_ui()
	_update_ruleset_info()
	_refresh_scaffold_ui()
	_redraw_spell_panel()


## v0.17: tests/scenarios/index.json を読んでシナリオ一覧を _scenarios に格納。
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
		var path := "res://tests/scenarios/" + String(fname)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var scn: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(scn) == TYPE_DICTIONARY:
			_scenarios.append(scn)


func _load_ruleset(idx: int) -> Resource:
	if idx < 0 or idx >= RULESETS.size():
		return null
	return load(String(RULESETS[idx]["path"]))


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# --- ヘッダ ---
	var title := Label.new()
	title.text = tr("ui.app.title")
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "spell_builder — INC-1: 呪文を組み立てて試す（任意語列）"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(subtitle)

	root.add_child(HSeparator.new())

	# --- 上部: ruleset 切替 / C スライダ ---
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	root.add_child(top_row)

	var ruleset_prefix := Label.new()
	ruleset_prefix.text = "ruleset:"
	ruleset_prefix.add_theme_font_size_override("font_size", 13)
	top_row.add_child(ruleset_prefix)

	_ruleset_option = OptionButton.new()
	for i in RULESETS.size():
		_ruleset_option.add_item(String(RULESETS[i]["label"]), i)
	_ruleset_option.select(_ruleset_index)
	_ruleset_option.item_selected.connect(_on_ruleset_changed)
	top_row.add_child(_ruleset_option)

	_ruleset_info_label = Label.new()
	_ruleset_info_label.text = ""
	_ruleset_info_label.add_theme_font_size_override("font_size", 12)
	_ruleset_info_label.add_theme_color_override("font_color", COLOR_MUTED)
	top_row.add_child(_ruleset_info_label)

	var c_box := HBoxContainer.new()
	c_box.add_theme_constant_override("separation", 8)
	c_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(c_box)

	var c_prefix := Label.new()
	c_prefix.text = "C (理解度):"
	c_prefix.add_theme_font_size_override("font_size", 13)
	c_box.add_child(c_prefix)

	_c_slider = HSlider.new()
	_c_slider.min_value = 0.0
	_c_slider.max_value = 100.0
	_c_slider.step = 1.0
	_c_slider.value = _c_value
	_c_slider.custom_minimum_size = Vector2(280, 0)
	_c_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_c_slider.value_changed.connect(_on_c_slider_changed)
	c_box.add_child(_c_slider)

	_c_label = Label.new()
	_c_label.text = "%d" % int(_c_value)
	_c_label.add_theme_font_size_override("font_size", 13)
	_c_label.custom_minimum_size = Vector2(40, 0)
	c_box.add_child(_c_label)

	# --- v0.17: シナリオ呼び出し + 計測タイマー ---
	var scenario_row := HBoxContainer.new()
	scenario_row.add_theme_constant_override("separation", 8)
	root.add_child(scenario_row)

	var scenario_prefix := Label.new()
	scenario_prefix.text = "シナリオ:"
	scenario_prefix.add_theme_font_size_override("font_size", 13)
	scenario_row.add_child(scenario_prefix)

	_scenario_option = OptionButton.new()
	_scenario_option.add_item("（手動）", -1)
	for i in _scenarios.size():
		var scn: Dictionary = _scenarios[i]
		_scenario_option.add_item(String(scn.get("name", "scenario %d" % i)), i)
	_scenario_option.select(0)
	_scenario_option.item_selected.connect(_on_scenario_selected)
	scenario_row.add_child(_scenario_option)

	_scenario_desc_label = Label.new()
	_scenario_desc_label.text = ""
	_scenario_desc_label.add_theme_font_size_override("font_size", 11)
	_scenario_desc_label.add_theme_color_override("font_color", COLOR_MUTED)
	_scenario_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scenario_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenario_row.add_child(_scenario_desc_label)

	_timer_label = Label.new()
	_timer_label.text = "詠唱 0 / 文法 OK 0 / 初成功 -"
	_timer_label.add_theme_font_size_override("font_size", 11)
	_timer_label.add_theme_color_override("font_color", COLOR_MUTED)
	scenario_row.add_child(_timer_label)

	# --- 使える語タイル ---
	var tiles_header := Label.new()
	tiles_header.text = "■ 使える語（クリックで追加）"
	tiles_header.add_theme_font_size_override("font_size", 15)
	tiles_header.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(tiles_header)

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

	# --- 現在の呪文 ---
	var spell_header := Label.new()
	spell_header.text = "■ 現在の呪文"
	spell_header.add_theme_font_size_override("font_size", 15)
	spell_header.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(spell_header)

	_spell_panel = VBoxContainer.new()
	_spell_panel.add_theme_constant_override("separation", 4)
	root.add_child(_spell_panel)

	_preview_label = Label.new()
	_preview_label.text = "（語タイルをクリック）"
	_preview_label.add_theme_font_size_override("font_size", 13)
	_preview_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(_preview_label)

	# --- v0.16: ライブ文法プレビュー (scaffold=max 専用) ---
	_live_preview_label = RichTextLabel.new()
	_live_preview_label.bbcode_enabled = true
	_live_preview_label.fit_content = true
	_live_preview_label.scroll_active = false
	_live_preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_preview_label.custom_minimum_size = Vector2(0, 32)
	_live_preview_label.text = ""
	_live_preview_label.visible = false
	root.add_child(_live_preview_label)

	# --- 詠唱ボタン ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	root.add_child(btn_row)

	var one_btn := Button.new()
	one_btn.text = "1 回詠唱"
	one_btn.pressed.connect(_cast_once)
	btn_row.add_child(one_btn)

	var batch_btn := Button.new()
	batch_btn.text = "%d 回" % SMALL_BATCH_N
	batch_btn.pressed.connect(_cast_batch.bind(SMALL_BATCH_N))
	btn_row.add_child(batch_btn)

	var medium_btn := Button.new()
	medium_btn.text = "%d 回" % MEDIUM_BATCH_N
	medium_btn.pressed.connect(_cast_batch.bind(MEDIUM_BATCH_N))
	btn_row.add_child(medium_btn)

	var large_btn := Button.new()
	large_btn.text = "%d 回" % LARGE_BATCH_N
	large_btn.pressed.connect(_cast_batch.bind(LARGE_BATCH_N))
	btn_row.add_child(large_btn)

	var clear_btn := Button.new()
	clear_btn.text = "クリア"
	clear_btn.pressed.connect(_clear_spell)
	btn_row.add_child(clear_btn)

	# v0.16: ヒントボタン (scaffold=mid 専用、表示制御は _refresh_scaffold_ui)
	_hint_button = Button.new()
	_hint_button.text = "ヒント"
	_hint_button.pressed.connect(_on_hint_pressed)
	_hint_button.visible = false
	btn_row.add_child(_hint_button)

	# v0.16: 詠唱前警告ダイアログ (scaffold=mid)
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "文法に問題があります"
	_confirm_dialog.dialog_text = ""
	_confirm_dialog.confirmed.connect(_on_confirm_cast)
	add_child(_confirm_dialog)

	# --- v0.17: チューニングパネル (06 §2.4) ---
	_build_tuning_panel(root)

	# --- 結果表示 ---
	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.scroll_active = true
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_label.custom_minimum_size = Vector2(0, 200)
	_result_label.text = "[i]未詠唱[/i]"
	root.add_child(_result_label)

	# --- INC-3 v0.9.2 (要求 4): スロット 1-5 への保存パネル ---
	# dungeon_view から F キーで開いた時に、現在のトークン列 _spell を Lexicon._spell_slots に保存できる。
	# 独立シーンとして起動した場合も使えるが用途は dungeon_view からの呼び出しが主。
	var slot_panel := HBoxContainer.new()
	slot_panel.add_theme_constant_override("separation", 8)
	root.add_child(slot_panel)

	var slot_header := Label.new()
	slot_header.text = "魔法スロット保存:"
	slot_panel.add_child(slot_header)

	for i in range(1, 6):
		var slot_btn := Button.new()
		slot_btn.text = "スロット %d に保存" % i
		var captured_slot: int = i
		slot_btn.pressed.connect(func(): _on_save_to_slot(captured_slot))
		slot_panel.add_child(slot_btn)

	var slot_hint := Label.new()
	slot_hint.text = "  (ESC で dungeon に戻る)"
	slot_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	slot_panel.add_child(slot_hint)


## INC-3 v0.9.2: スロット保存ハンドラ。
func _on_save_to_slot(slot: int) -> void:
	if _spell.is_empty():
		_result_label.text = "[color=#e88]✗ スロット %d: 保存する呪文がありません（タイルを並べてから）[/color]" % slot
		return
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null or not lex.has_method("set_spell_slot"):
		_result_label.text = "[color=#e88]✗ Lexicon.set_spell_slot が利用できません[/color]"
		return
	lex.set_spell_slot(slot, _spell)
	var preview: Array = []
	for t in _spell:
		preview.append(String(t.get("word_id", "?")))
	_result_label.text = "[color=#8fc]✦ スロット %d に保存: %s[/color]" % [slot, " ".join(preview)]


## タイルボタンを 1 個作る。
func _add_tile_button(parent: Node, res: WordResource) -> void:
	var btn := Button.new()
	# 表示は古綴の代表形（target は主格、その他は基本形）。
	# WordResource にカナ id ("meida" 等) はあるが、表示用には id をそのまま使う。
	# 厳密には res.id の古綴フォームを別フィールドに持つべきだが INC-1 では id で十分。
	var display := _display_form(res)
	btn.text = "%s\n[%s]" % [display, _word_class_label_ja(res.word_class)]
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size = Vector2(86, 48)
	btn.add_theme_color_override("font_color", _color_for_class(res.word_class))
	btn.pressed.connect(_on_tile_pressed.bind(res.id))
	parent.add_child(btn)


func _word_class_label_ja(word_class: String) -> String:
	match word_class:
		"effect": return "効果"
		"target": return "対象"
		"element": return "属性"
		"modifier": return "修飾"
		_: return word_class


func _color_for_class(word_class: String) -> Color:
	match word_class:
		"effect": return COLOR_TILE_EFFECT
		"target": return COLOR_TILE_TARGET
		"element": return COLOR_TILE_ELEMENT
		_: return COLOR_TILE_OTHER


## 表示用の語形。target は主格、他は基本形（id をそのまま）。
func _display_form(res: WordResource) -> String:
	if res.word_class == "target":
		var nom := res.get_inflected("sg", "nom")
		if not nom.is_empty():
			return nom
	return res.id


# --- イベントハンドラ ---

func _on_c_slider_changed(value: float) -> void:
	_c_value = value
	_c_label.text = "%d" % int(_c_value)


func _on_ruleset_changed(idx: int) -> void:
	_ruleset_index = idx
	_ruleset = _load_ruleset(idx)
	_update_ruleset_info()
	# v0.16: scaffold UI の表示を切替
	_refresh_scaffold_ui()
	# 既存の呪文・結果は維持（次の詠唱で新 ruleset 適用）


## v0.17: シナリオ選択時の処理。
##   item_id == -1 は「（手動）」で何もしない。
##   それ以外: シナリオ JSON の ruleset_id / c_override / tokens を適用。
func _on_scenario_selected(option_idx: int) -> void:
	# OptionButton の item_id を取得（メタデータ）
	var meta_id: int = _scenario_option.get_item_id(option_idx)
	if meta_id < 0:
		_scenario_desc_label.text = ""
		return
	if meta_id < 0 or meta_id >= _scenarios.size():
		return
	var scn: Dictionary = _scenarios[meta_id]
	_scenario_desc_label.text = String(scn.get("description", ""))

	# ruleset 切替
	var ruleset_id: String = String(scn.get("ruleset_id", ""))
	if not ruleset_id.is_empty():
		for i in RULESETS.size():
			if String(RULESETS[i]["id"]) == ruleset_id:
				_ruleset_index = i
				_ruleset = _load_ruleset(i)
				_ruleset_option.select(i)
				_update_ruleset_info()
				_refresh_scaffold_ui()
				break

	# C override
	if scn.has("c_override"):
		_c_value = float(scn["c_override"])
		_c_slider.value = _c_value
		_c_label.text = "%d" % int(_c_value)

	# tokens を上書き
	var tokens_data: Array = scn.get("tokens", [])
	_spell.clear()
	for t in tokens_data:
		if typeof(t) == TYPE_DICTIONARY:
			_spell.append({
				"word_id": String(t.get("word_id", "")),
				"case": String(t.get("case", "")),
			})
	_redraw_spell_panel()


## scaffold_level に応じて補助 UI の表示を切り替える（v0.16）。
func _refresh_scaffold_ui() -> void:
	var scaffold: String = ""
	if _ruleset != null:
		scaffold = String(_ruleset.get("scaffold_level"))
	# max: ライブプレビュー表示、mid: ヒントボタン表示、それ以外: 両方非表示
	if _live_preview_label != null:
		_live_preview_label.visible = (scaffold == "max")
		if scaffold == "max":
			_update_live_preview()
	if _hint_button != null:
		_hint_button.visible = (scaffold == "mid")


## 現在の呪文を Validator にかけて、live preview を更新（scaffold=max のみ）。
func _update_live_preview() -> void:
	if _live_preview_label == null or not _live_preview_label.visible:
		return
	if _spell.is_empty():
		_live_preview_label.text = "[i][color=#888]プレビュー: 語を選んでください[/color][/i]"
		return
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		_live_preview_label.text = ""
		return
	# 詠唱せずに文法判定だけ行うため、c_override で C=100 にして暴発確率を下げ、
	# rng_seed=1 で決定的に。判定結果（GrammarReport）のみを使う。
	var result: CastResult = engine.cast(_spell.duplicate(true), _ruleset, {"c_override": 100.0, "rng_seed": 1})
	if result == null or result.grammar_report == null:
		_live_preview_label.text = ""
		return
	var rep: GrammarReport = result.grammar_report
	if rep.overall_pass:
		_live_preview_label.text = "[b][color=#8aff8a]✓ プレビュー: 文法 OK[/color][/b]"
	else:
		var lines: PackedStringArray = PackedStringArray()
		lines.append("[b][color=#ff8888]✗ プレビュー: 文法 NG[/color][/b]")
		for f in rep.failures():
			var reason: String = String(f.get("reason", ""))
			var recommended: String = String(f.get("recommended", ""))
			var line := "  [color=#ff8888]✗[/color] %s" % reason
			if not recommended.is_empty():
				line += " → [color=#ffd060]%s[/color]" % recommended
			lines.append(line)
		_live_preview_label.text = "\n".join(lines)


## ヒントボタン押下（scaffold=mid）。最重要違反を 1 つ提示。
func _on_hint_pressed() -> void:
	if _spell.is_empty():
		_result_label.text = "[i]呪文が空です[/i]"
		return
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		return
	var result: CastResult = engine.cast(_spell.duplicate(true), _ruleset, {"c_override": 100.0, "rng_seed": 1})
	if result == null or result.grammar_report == null:
		return
	var rep: GrammarReport = result.grammar_report
	if rep.overall_pass:
		_result_label.text = "[b][color=#8aff8a]✓ 現在の呪文は文法的に正しいです[/color][/b]"
		return
	var fails := rep.failures()
	if fails.is_empty():
		return
	var f = fails[0]
	var reason: String = String(f.get("reason", ""))
	var recommended: String = String(f.get("recommended", ""))
	var msg := "[b]ヒント:[/b]\n  [color=#ff8888]✗[/color] %s" % reason
	if not recommended.is_empty():
		msg += "\n  → [color=#ffd060]%s[/color]" % recommended
	_result_label.text = msg


## ConfirmationDialog 確認後に詠唱を実行（v0.16）。
func _on_confirm_cast() -> void:
	if _pending_cast.is_empty():
		return
	var mode: String = String(_pending_cast.get("mode", ""))
	var n: int = int(_pending_cast.get("n", 1))
	_pending_cast.clear()
	if mode == "once":
		_do_cast_once()
	elif mode == "batch":
		_do_cast_batch(n)


## scaffold=mid の場合、詠唱前に文法をチェックし NG なら確認ダイアログ。
## 確認した結果 false (キャンセル) なら呼び出し元は中断。true (進行) ならそのまま続行。
## ダイアログを出した場合は false を返して呼び出し元を中断させ、_on_confirm_cast 経由で再開する。
func _maybe_warn_before_cast(mode: String, n: int) -> bool:
	if _ruleset == null:
		return true
	var scaffold: String = String(_ruleset.get("scaffold_level"))
	if scaffold != "mid":
		return true  # 警告対象外
	# 文法を試走
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		return true
	var result: CastResult = engine.cast(_spell.duplicate(true), _ruleset, {"c_override": 100.0, "rng_seed": 1})
	if result == null or result.grammar_report == null:
		return true
	var rep: GrammarReport = result.grammar_report
	if rep.overall_pass:
		return true
	# 違反あり → ダイアログを出して中断
	var fails := rep.failures()
	var msg := "現在の呪文には以下の問題があります:\n"
	for f in fails:
		msg += "  ✗ %s\n" % String(f.get("reason", ""))
	msg += "\n続行しますか?"
	_confirm_dialog.dialog_text = msg
	_pending_cast = {"mode": mode, "n": n}
	_confirm_dialog.popup_centered()
	return false  # 呼び出し元を中断（_on_confirm_cast で再開）


func _update_ruleset_info() -> void:
	if _ruleset == null:
		_ruleset_info_label.text = ""
		return
	var enabled_rules: PackedStringArray = PackedStringArray()
	for rule_name in ["case_agreement", "word_order", "elements", "modifier", "range"]:
		if _ruleset.has_method("is_rule_enabled") and _ruleset.is_rule_enabled(rule_name):
			enabled_rules.append(rule_name)
	var scaffold: String = String(_ruleset.get("scaffold_level"))
	_ruleset_info_label.text = "（scaffold=%s, 有効: %s）" % [scaffold, ", ".join(enabled_rules)]


func _on_tile_pressed(word_id: String) -> void:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return
	var res: WordResource = lex.get_word(word_id)
	if res == null:
		return
	var default_case := ""
	if res.word_class == "target":
		default_case = "acc"  # 正準（meida などの効果語の要求格に一致）
	elif res.word_class == "modifier" and res.has_gendered_inflection():
		# v0.14: 修飾語は target に合わせて初期値を決定（一致が正準）
		default_case = _get_current_target_case()
		if default_case.is_empty():
			default_case = "acc"
	var new_entry := {"word_id": word_id, "case": default_case}
	# v0.15: 修飾語は正準語順「V 修 名」のため target の直前に挿入。
	if res.word_class == "modifier" and res.has_gendered_inflection():
		var t_idx := _find_target_index()
		if t_idx >= 0:
			_spell.insert(t_idx, new_entry)
			_redraw_spell_panel()
			return
	_spell.append(new_entry)
	_redraw_spell_panel()


## 現在の呪文中の target 語のインデックス（最初の 1 つ）。なければ -1。
func _find_target_index() -> int:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return -1
	for i in _spell.size():
		var word_id: String = String(_spell[i].get("word_id", ""))
		var res: WordResource = lex.get_word(word_id)
		if res != null and res.word_class == "target":
			return i
	return -1


## 現在の呪文中の target 語の case を返す（複数あれば最初）。なければ "".
func _get_current_target_case() -> String:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return ""
	for entry in _spell:
		var word_id: String = String(entry.get("word_id", ""))
		var res: WordResource = lex.get_word(word_id)
		if res != null and res.word_class == "target":
			return String(entry.get("case", ""))
	return ""


## 現在の呪文中の target 語の gender を返す。
func _get_current_target_gender() -> String:
	var lex := get_node_or_null("/root/Lexicon")
	if lex == null:
		return ""
	for entry in _spell:
		var word_id: String = String(entry.get("word_id", ""))
		var res: WordResource = lex.get_word(word_id)
		if res != null and res.word_class == "target":
			return res.gender
	return ""


func _on_case_changed(idx: int, slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _spell.size():
		return
	_spell[slot_idx]["case"] = CASE_OPTIONS[idx]
	# v0.15: 行ラベルの表層形（mikill ↔ mikinn など）も即時反映するため再描画。
	_redraw_spell_panel()


func _on_remove_pressed(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _spell.size():
		return
	_spell.remove_at(slot_idx)
	_redraw_spell_panel()


func _on_move_pressed(slot_idx: int, direction: int) -> void:
	var new_idx := slot_idx + direction
	if new_idx < 0 or new_idx >= _spell.size() or slot_idx < 0 or slot_idx >= _spell.size():
		return
	var tmp = _spell[slot_idx]
	_spell[slot_idx] = _spell[new_idx]
	_spell[new_idx] = tmp
	_redraw_spell_panel()


func _clear_spell() -> void:
	_spell.clear()
	_redraw_spell_panel()
	_result_label.text = "[i]未詠唱[/i]"


# --- 描画 ---

func _redraw_spell_panel() -> void:
	for child in _spell_panel.get_children():
		child.queue_free()

	var lex := get_node_or_null("/root/Lexicon")
	for slot_idx in _spell.size():
		var entry: Dictionary = _spell[slot_idx]
		var word_id: String = String(entry.get("word_id", ""))
		var res: WordResource = null
		if lex != null:
			res = lex.get_word(word_id)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_spell_panel.add_child(row)

		var num_label := Label.new()
		num_label.text = "%d." % (slot_idx + 1)
		num_label.custom_minimum_size = Vector2(24, 0)
		row.add_child(num_label)

		var word_label := Label.new()
		var display_form := ""
		var class_label := "?"
		if res != null:
			# 現在の格・性別を反映した表層形を表示。
			var current_case: String = String(entry.get("case", ""))
			if res.word_class == "target" and not current_case.is_empty():
				display_form = res.get_inflected("sg", current_case)
			elif res.word_class == "modifier" and res.has_gendered_inflection() and not current_case.is_empty():
				var target_gender := _get_current_target_gender()
				if not target_gender.is_empty():
					display_form = res.get_inflected("sg", current_case, target_gender)
			if display_form.is_empty():
				display_form = _display_form(res)
			class_label = _word_class_label_ja(res.word_class)
		else:
			display_form = word_id
			class_label = "unknown"
		word_label.text = "%s（%s）" % [display_form, class_label]
		word_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(word_label)

		# 格選択（target または形容詞活用を持つ modifier）
		var show_case_option: bool = res != null and (
			res.word_class == "target"
			or (res.word_class == "modifier" and res.has_gendered_inflection())
		)
		if show_case_option:
			var case_opt := OptionButton.new()
			for i in CASE_OPTIONS.size():
				case_opt.add_item(String(CASE_LABELS.get(CASE_OPTIONS[i], CASE_OPTIONS[i])), i)
			var current_case: String = String(entry.get("case", "acc"))
			var current_idx: int = CASE_OPTIONS.find(current_case)
			if current_idx < 0:
				current_idx = 0
			case_opt.select(current_idx)
			case_opt.item_selected.connect(_on_case_changed.bind(slot_idx))
			row.add_child(case_opt)

		# 上下移動・削除
		var up_btn := Button.new()
		up_btn.text = "↑"
		up_btn.disabled = (slot_idx == 0)
		up_btn.pressed.connect(_on_move_pressed.bind(slot_idx, -1))
		row.add_child(up_btn)

		var down_btn := Button.new()
		down_btn.text = "↓"
		down_btn.disabled = (slot_idx == _spell.size() - 1)
		down_btn.pressed.connect(_on_move_pressed.bind(slot_idx, 1))
		row.add_child(down_btn)

		var remove_btn := Button.new()
		remove_btn.text = "×"
		remove_btn.pressed.connect(_on_remove_pressed.bind(slot_idx))
		row.add_child(remove_btn)

	_update_preview()


## _update_preview の呼び出し後にライブプレビュー（scaffold=max）も更新するヘルパー。
func _update_preview_and_live() -> void:
	_update_preview()
	_update_live_preview()


func _update_preview() -> void:
	if _spell.is_empty():
		_preview_label.text = "（語タイルをクリック）"
		_update_live_preview()  # v0.16: 空でもライブプレビュー側を更新
		return
	var lex := get_node_or_null("/root/Lexicon")
	var target_gender := _get_current_target_gender()
	var parts: PackedStringArray = PackedStringArray()
	for entry in _spell:
		var word_id: String = String(entry.get("word_id", ""))
		var case_id: String = String(entry.get("case", ""))
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
	_preview_label.text = "詠唱: " + " ".join(parts)
	# v0.16: ライブプレビュー（scaffold=max のみ visible）も同時更新
	_update_live_preview()


# --- 詠唱 ---

func _cast_once() -> void:
	if _spell.is_empty():
		_result_label.text = "[color=#ffaa55]呪文が空です。語タイルをクリックして追加してください。[/color]"
		return
	# v0.16: scaffold=mid なら詠唱前確認
	if not _maybe_warn_before_cast("once", 1):
		return
	_do_cast_once()


func _do_cast_once() -> void:
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		_result_label.text = "[color=#ff8888]SpellEngine が起動していません[/color]"
		return
	var result: CastResult = engine.cast(_spell.duplicate(true), _ruleset, {"c_override": _c_value})
	_result_label.text = _format_single_cast(result)
	_record_cast(result)


func _cast_batch(n: int) -> void:
	if _spell.is_empty():
		_result_label.text = "[color=#ffaa55]呪文が空です。語タイルをクリックして追加してください。[/color]"
		return
	# v0.16: scaffold=mid なら詠唱前確認
	if not _maybe_warn_before_cast("batch", n):
		return
	_do_cast_batch(n)


func _do_cast_batch(n: int) -> void:
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		_result_label.text = "[color=#ff8888]SpellEngine が起動していません[/color]"
		return

	var powers: Array[float] = []
	var misfire_count: int = 0
	var last_report: GrammarReport = null
	var sample: CastResult = null
	for i in n:
		var r: CastResult = engine.cast(_spell.duplicate(true), _ruleset, {"c_override": _c_value})
		if r == null:
			continue
		sample = r
		if r.resolved != null:
			powers.append(r.resolved.effect_power)
			if r.resolved.misfired:
				misfire_count += 1
		if r.grammar_report != null:
			last_report = r.grammar_report

	_result_label.text = _format_batch(sample, powers, misfire_count, last_report)
	# 計測: バッチも 1 回の試行としてカウント（代表 sample で記録）
	_record_cast(sample)


# --- 表示整形（spell_lab と同じ） ---

func _format_single_cast(result: CastResult) -> String:
	if result == null:
		return "[color=#ff8888]結果なし[/color]"

	var lines: PackedStringArray = PackedStringArray()
	var rep: GrammarReport = result.grammar_report
	var res: ResolvedEffect = result.resolved
	var debug: Dictionary = result.debug

	var pass_color := "#8aff8a" if (rep != null and rep.overall_pass) else "#ff8888"
	var pass_text := "文法 OK" if (rep != null and rep.overall_pass) else "文法 NG"
	lines.append("[b][color=%s]%s[/color][/b]   G=%.2f" % [
		pass_color, pass_text, float(debug.get("G", 0.0))
	])

	if res != null:
		if res.misfired:
			lines.append("[color=#ffaa55]暴発: %s (%s)[/color]   威力=%.2f" % [
				res.misfire_category, res.misfire_outcome, res.effect_power
			])
			if res.self_damage > 0.0:
				lines.append("[color=#ff8888]自爆 %.2f[/color]" % res.self_damage)
		else:
			lines.append("成功   威力=%.2f   variance×%.2f" % [
				res.effect_power, res.variance_mult
			])

	lines.append("[color=#a0a0b0]P_base=%.1f × G=%.2f → 期待威力=%.2f  C=%.0f  p_misfire=%.3f (base=%.3f)[/color]" % [
		float(debug.get("p_base", 0.0)),
		float(debug.get("g_mult", 1.0)),
		float(debug.get("p_base", 0.0)) * float(debug.get("g_mult", 1.0)),
		float(debug.get("C", 0.0)),
		float(debug.get("misfire_chance", 0.0)),
		float(debug.get("misfire_base", 0.0)),
	])

	if rep != null:
		var fails := rep.failures()
		if fails.size() > 0:
			lines.append("")
			# v0.16: scaffold=none では詳細を出さない（上級者は自力で原因を探る）
			if _is_scaffold_none():
				lines.append("[color=#ff8888]✗ 文法違反あり（詳細非表示・上級）[/color]")
			else:
				lines.append("[i]GrammarReport[/i]")
				for f in fails:
					var reason: String = String(f.get("reason", ""))
					var recommended: String = String(f.get("recommended", ""))
					var sev: String = String(f.get("severity", ""))
					lines.append("  [color=#ff8888]✗[/color] %s [color=#888888](%s)[/color]" % [reason, sev])
					if not recommended.is_empty():
						lines.append("    → [color=#ffd060]%s[/color]" % recommended)

	return "\n".join(lines)


## v0.17 (06 §2.4): チューニングパネルを構築。SpellResolver の static 変数を直接書き換える。
##   - case_agreement 暴発倍率
##   - word_order 暴発倍率
##   - tier 1 の V_max（成功時 variance 上限）
func _build_tuning_panel(parent: Node) -> void:
	var toggle_btn := CheckButton.new()
	toggle_btn.text = "チューニング (倍率・variance を即調整)"
	toggle_btn.add_theme_font_size_override("font_size", 12)
	parent.add_child(toggle_btn)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)
	panel.visible = false
	parent.add_child(panel)

	toggle_btn.toggled.connect(func(pressed: bool): panel.visible = pressed)

	_add_tuning_slider(panel, "case_mult (暴発 ×)",
		1.0, 10.0, 0.5, float(SpellResolver.MISFIRE_MULT_BY_RULE.get("case_agreement", 2.0)),
		func(v: float):
			SpellResolver.MISFIRE_MULT_BY_RULE["case_agreement"] = v
			_update_live_preview())
	_add_tuning_slider(panel, "word_order_mult (暴発 ×)",
		1.0, 10.0, 0.5, float(SpellResolver.MISFIRE_MULT_BY_RULE.get("word_order", 6.0)),
		func(v: float):
			SpellResolver.MISFIRE_MULT_BY_RULE["word_order"] = v
			_update_live_preview())
	_add_tuning_slider(panel, "modifier_agreement_mult (暴発 ×)",
		1.0, 10.0, 0.5, float(SpellResolver.MISFIRE_MULT_BY_RULE.get("modifier_agreement", 2.0)),
		func(v: float):
			SpellResolver.MISFIRE_MULT_BY_RULE["modifier_agreement"] = v
			_update_live_preview())
	_add_tuning_slider(panel, "V_max(tier=1) (成功時 variance 上限)",
		0.0, 1.0, 0.05, float(SpellResolver.V_MAX_BY_TIER.get(1, 0.15)),
		func(v: float):
			SpellResolver.V_MAX_BY_TIER[1] = v)


## チューニングスライダの 1 行を追加するヘルパー。
func _add_tuning_slider(parent: Node, label_text: String, min_v: float, max_v: float, step_v: float, default_v: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.custom_minimum_size = Vector2(260, 0)
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
	value_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float):
		value_label.text = "%.2f" % v
		on_change.call(v))


## v0.17 (06 §4.2): 詠唱結果を記録し、計測ラベルを更新。
##   - _cast_count: 詠唱の総試行数（バッチも 1 とカウント）
##   - _pass_count: 文法 OK だった試行数
##   - _first_pass_time_ms: 最初に文法 OK が出た時刻（ready から）
func _record_cast(result: CastResult) -> void:
	if result == null:
		return
	_cast_count += 1
	var passed: bool = result.grammar_report != null and result.grammar_report.overall_pass
	if passed:
		_pass_count += 1
		if _first_pass_time_ms == 0:
			_first_pass_time_ms = Time.get_ticks_msec() - _ready_time_ms
			print("[計測] 最初の文法 OK 詠唱までの時間: %.2f 秒（試行 %d 回目）" % [_first_pass_time_ms / 1000.0, _cast_count])
	_update_timer_label()


func _update_timer_label() -> void:
	if _timer_label == null:
		return
	var first_str := "-"
	if _first_pass_time_ms > 0:
		first_str = "%.2fs (#%d)" % [_first_pass_time_ms / 1000.0, _pass_count]
	_timer_label.text = "詠唱 %d / 文法 OK %d / 初成功 %s" % [_cast_count, _pass_count, first_str]


## v0.16: scaffold=none 判定
func _is_scaffold_none() -> bool:
	if _ruleset == null:
		return false
	return String(_ruleset.get("scaffold_level")) == "none"


func _format_batch(sample: CastResult, powers: Array[float], misfire_count: int, last_report: GrammarReport) -> String:
	if powers.is_empty():
		return "[color=#ff8888]バッチ失敗[/color]"

	var sum: float = 0.0
	var minv: float = powers[0]
	var maxv: float = powers[0]
	for p in powers:
		sum += p
		if p < minv: minv = p
		if p > maxv: maxv = p
	var avg: float = sum / float(powers.size())

	var lines: PackedStringArray = PackedStringArray()
	var pass_color := "#8aff8a" if (last_report != null and last_report.overall_pass) else "#ff8888"
	var pass_text := "文法 OK" if (last_report != null and last_report.overall_pass) else "文法 NG"
	var g_score: float = last_report.g_score if last_report != null else 0.0
	lines.append("[b][color=%s]%s[/color][/b]   G=%.2f   N=%d" % [
		pass_color, pass_text, g_score, powers.size()
	])

	lines.append("威力: 平均 [b]%.2f[/b]  最小 %.2f  最大 %.2f  幅 %.2f" % [
		avg, minv, maxv, maxv - minv
	])
	var misfire_pct: float = 100.0 * float(misfire_count) / float(powers.size())
	lines.append("暴発: [b]%d / %d 回[/b] (%.0f%%)" % [misfire_count, powers.size(), misfire_pct])

	if sample != null:
		var debug: Dictionary = sample.debug
		lines.append("[color=#a0a0b0]期待威力=%.2f  C=%.0f  p_misfire=%.3f (base=%.3f)[/color]" % [
			float(debug.get("p_base", 0.0)) * float(debug.get("g_mult", 1.0)),
			float(debug.get("C", 0.0)),
			float(debug.get("misfire_chance", 0.0)),
			float(debug.get("misfire_base", 0.0)),
		])

	if last_report != null:
		var fails := last_report.failures()
		if fails.size() > 0:
			lines.append("")
			# v0.16: scaffold=none では詳細を出さない
			if _is_scaffold_none():
				lines.append("[color=#ff8888]✗ 文法違反あり（詳細非表示・上級）[/color]")
			else:
				lines.append("[i]GrammarReport (代表)[/i]")
				for f in fails:
					var reason: String = String(f.get("reason", ""))
					lines.append("  [color=#ff8888]✗[/color] %s" % reason)

	return "\n".join(lines)
