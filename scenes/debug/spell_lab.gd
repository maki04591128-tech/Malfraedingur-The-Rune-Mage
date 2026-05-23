extends Control
## spell_lab.gd — INC-1 検証 UI（4 パターン 2×2 比較）。
##
## 目的: 06_INC1検証仕様.md のシナリオ S1 / S6 / 複合違反を**触って手応えが分かる**形に可視化。
##       格違反のみ・語順違反のみ・両方違反を 1 画面で比べて、03 §5.2 v0.11 暴発合算と
##       §5.4 v0.12 G 線形乗算の効果を体感する。
##
## INC-1 範囲:
##   - 入力は 4 つの固定トークン列（S1 正/誤・S6 誤・複合誤）。タイル列ビルダーは S2/S3 で追加。
##   - C はスライダ（0..100、初期 50）で可変。
##   - 1回詠唱 / 10回詠唱 / 100回詠唱 ボタン。チューニングパネルは未実装。
##   - GrammarReport の reason / recommended を提示（附録B.1 文言）。
##   - スペルミス（unknown_word, ×4）は無辞書経路（INC-2/3）でのみ発生するため本ラボでは未試行。
##
## 後続増分:
##   - 200回バッチ＋暴発統計
##   - チューニングパネル（BalanceConfig ライブ編集）
##   - ruleset 切替・タイル列ビルダー・無辞書経路（unknown_word, ×4）

const RULESET_PATH := "res://data/grammar/phase_intro.tres"

## 4 パターンのトークン列。
## - s1_correct: 格 OK, 語順 OK（基準）
## - s1_wrong_case: 格 NG, 語順 OK（×2 倍率）
## - s6_wrong_order: 格 OK, 語順 NG（×6 倍率）
## - s1s6_wrong_both: 格 NG, 語順 NG（×2 + ×6 = ×8 倍率, G=0）
const TOKENS_BY_PATTERN: Dictionary = {
	"s1_correct": [
		{"word_id": "meida", "case": ""},
		{"word_id": "fjandi", "case": "acc"},  # 対格 "fjanda"
	],
	"s1_wrong_case": [
		{"word_id": "meida", "case": ""},
		{"word_id": "fjandi", "case": "nom"},  # 主格 "fjandi" (格 NG)
	],
	"s6_wrong_order": [
		{"word_id": "fjandi", "case": "acc"},  # 対格は保持
		{"word_id": "meida", "case": ""},      # 効果語が後ろ (語順 NG)
	],
	"s1s6_wrong_both": [
		{"word_id": "fjandi", "case": "nom"},  # 主格 (格 NG)
		{"word_id": "meida", "case": ""},      # 効果語が後ろ (語順 NG)
	],
}

const HEADERS_BY_PATTERN: Dictionary = {
	"s1_correct":      "正: meiða fjanda（対格＋正準語順）",
	"s1_wrong_case":   "格違反: meiða fjandi（主格・×2）",
	"s6_wrong_order":  "語順違反: fjanda meiða（逆順・×6）",
	"s1s6_wrong_both": "両方違反: fjandi meiða（×2＋×6＝×8）",
}

const PATTERN_ORDER: Array = [
	"s1_correct", "s1_wrong_case",
	"s6_wrong_order", "s1s6_wrong_both",
]

const SMALL_BATCH_N: int = 10
const MEDIUM_BATCH_N: int = 100
const LARGE_BATCH_N: int = 200  # v0.17 (06 §2.3) 統計信頼性

const COLOR_OK := Color(0.55, 0.95, 0.55)
const COLOR_FAIL := Color(0.95, 0.5, 0.5)
const COLOR_MUTED := Color(0.7, 0.7, 0.75)
const COLOR_ACCENT := Color(0.85, 0.85, 0.95)

var _ruleset: Resource
var _c_value: float = 50.0

var _c_slider: HSlider
var _c_label: Label
## pattern_id (String) -> RichTextLabel
var _result_labels: Dictionary = {}


func _ready() -> void:
	_ruleset = load(RULESET_PATH)
	_build_ui()
	# 初回起動時に C=50 で 1 回ずつ詠唱して結果を初期表示。
	for pattern_id in PATTERN_ORDER:
		_cast_once(pattern_id)


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
	subtitle.text = "spell_lab — INC-1: 文法違反パターン比較（S1 / S6 / 複合）"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(subtitle)

	root.add_child(HSeparator.new())

	# --- 上部: ruleset / C スライダ ---
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	root.add_child(top_row)

	var ruleset_label := Label.new()
	var ruleset_id: String = ""
	if _ruleset != null:
		ruleset_id = String(_ruleset.get("id"))
	ruleset_label.text = "ruleset: %s（格一致＋語順 ON）" % ruleset_id
	ruleset_label.add_theme_font_size_override("font_size", 12)
	ruleset_label.add_theme_color_override("font_color", COLOR_MUTED)
	top_row.add_child(ruleset_label)

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

	# --- 中央: 2×2 グリッド比較 ---
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	for pattern_id in PATTERN_ORDER:
		var label := _build_cell(grid, pattern_id)
		_result_labels[pattern_id] = label

	# --- フッタ注記 ---
	var footer := Label.new()
	footer.text = "p_misfire の合算（基準×倍率）と威力ペナルティ G（線形乗算）の効きを 4 セルで比べる。100回詠唱で暴発回数と平均威力の差が安定して観測可能。"
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(footer)


## 1 セル分の UI を組み立て、結果表示用 RichTextLabel を返す。
##   parent: 親 GridContainer
##   pattern_id: パターン ID（"s1_correct" 等）
func _build_cell(parent: Node, pattern_id: String) -> RichTextLabel:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(cell)

	var header := Label.new()
	header.text = String(HEADERS_BY_PATTERN.get(pattern_id, pattern_id))
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	cell.add_child(header)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	cell.add_child(btn_row)

	var one_btn := Button.new()
	one_btn.text = "1回"
	one_btn.pressed.connect(_cast_once.bind(pattern_id))
	btn_row.add_child(one_btn)

	var batch_btn := Button.new()
	batch_btn.text = "%d回" % SMALL_BATCH_N
	batch_btn.pressed.connect(_cast_batch.bind(pattern_id, SMALL_BATCH_N))
	btn_row.add_child(batch_btn)

	var medium_btn := Button.new()
	medium_btn.text = "%d回" % MEDIUM_BATCH_N
	medium_btn.pressed.connect(_cast_batch.bind(pattern_id, MEDIUM_BATCH_N))
	btn_row.add_child(medium_btn)

	var large_btn := Button.new()
	large_btn.text = "%d回" % LARGE_BATCH_N
	large_btn.pressed.connect(_cast_batch.bind(pattern_id, LARGE_BATCH_N))
	btn_row.add_child(large_btn)

	var result_label := RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.scroll_active = true
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_label.custom_minimum_size = Vector2(0, 140)
	result_label.text = "[i]未詠唱[/i]"
	cell.add_child(result_label)

	return result_label


# --- イベントハンドラ ---

func _on_c_slider_changed(value: float) -> void:
	_c_value = value
	_c_label.text = "%d" % int(_c_value)


func _cast_once(pattern_id: String) -> void:
	var tokens: Array = TOKENS_BY_PATTERN.get(pattern_id, [])
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		_set_result(pattern_id, "[color=#ff8888]SpellEngine が起動していません[/color]")
		return
	var result: CastResult = engine.cast(tokens, _ruleset, {"c_override": _c_value})
	_set_result(pattern_id, _format_single_cast(result))


func _cast_batch(pattern_id: String, n: int) -> void:
	var tokens: Array = TOKENS_BY_PATTERN.get(pattern_id, [])
	var engine := get_node_or_null("/root/SpellEngine")
	if engine == null:
		_set_result(pattern_id, "[color=#ff8888]SpellEngine が起動していません[/color]")
		return

	var powers: Array[float] = []
	var misfire_count: int = 0
	var last_report: GrammarReport = null
	var sample: CastResult = null
	for i in n:
		var r: CastResult = engine.cast(tokens, _ruleset, {"c_override": _c_value})
		if r == null:
			continue
		sample = r
		if r.resolved != null:
			powers.append(r.resolved.effect_power)
			if r.resolved.misfired:
				misfire_count += 1
		if r.grammar_report != null:
			last_report = r.grammar_report

	_set_result(pattern_id, _format_batch(sample, powers, misfire_count, last_report))


# --- 表示整形 ---

func _format_single_cast(result: CastResult) -> String:
	if result == null:
		return "[color=#ff8888]結果なし[/color]"

	var lines: PackedStringArray = PackedStringArray()
	var rep: GrammarReport = result.grammar_report
	var res: ResolvedEffect = result.resolved
	var debug: Dictionary = result.debug

	# 文法判定
	var pass_color := "#8aff8a" if (rep != null and rep.overall_pass) else "#ff8888"
	var pass_text := "文法 OK" if (rep != null and rep.overall_pass) else "文法 NG"
	lines.append("[b][color=%s]%s[/color][/b]   G=%.2f" % [
		pass_color, pass_text, float(debug.get("G", 0.0))
	])

	# 効果威力 / 暴発
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

	# サマリ
	lines.append("[color=#a0a0b0]P_base=%.1f × G=%.2f → 期待威力=%.2f  C=%.0f  p_misfire=%.3f (base=%.3f)[/color]" % [
		float(debug.get("p_base", 0.0)),
		float(debug.get("g_mult", 1.0)),
		float(debug.get("p_base", 0.0)) * float(debug.get("g_mult", 1.0)),
		float(debug.get("C", 0.0)),
		float(debug.get("misfire_chance", 0.0)),
		float(debug.get("misfire_base", 0.0)),
	])

	# GrammarReport finding（fail のみ）
	if rep != null:
		var fails := rep.failures()
		if fails.size() > 0:
			for f in fails:
				var reason: String = String(f.get("reason", ""))
				var recommended: String = String(f.get("recommended", ""))
				lines.append("[color=#ff8888]✗[/color] %s" % reason)
				if not recommended.is_empty():
					lines.append("  → [color=#ffd060]%s[/color]" % recommended)

	return "\n".join(lines)


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
			for f in fails:
				var reason: String = String(f.get("reason", ""))
				lines.append("[color=#ff8888]✗[/color] %s" % reason)

	return "\n".join(lines)


func _set_result(pattern_id: String, text: String) -> void:
	if _result_labels.has(pattern_id):
		(_result_labels[pattern_id] as RichTextLabel).text = text
