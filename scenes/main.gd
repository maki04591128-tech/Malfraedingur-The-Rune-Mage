extends Control
## main.gd — INC-0 Walking Skeleton の動作確認画面。
##
## F5 した時に「INC-0 の縦の骨が通っている」ことを画面に見える形で示す。
## - タイトル: tr() 経由で i18n テーブルから取得 → i18n 動作の証拠
## - autoload 4本のロード状態
## - 語彙 .tres と Ruleset .tres のロード件数
## - スモークテスト相当の縦の骨を1回流して pass/fail を表示
##
## INC-1 で spell_lab に置き換わるので、これは「INC-0 完成の見える化」専用。

const WORD_IDS := [
	"meida", "fjandi", "sjalfr", "eldr", "vatn", "vindr", "jorth",
]

const COLOR_OK := Color(0.55, 0.95, 0.55)   # 緑
const COLOR_FAIL := Color(0.95, 0.5, 0.5)   # 赤
const COLOR_MUTED := Color(0.7, 0.7, 0.75)


func _ready() -> void:
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 32
	root.offset_top = 32
	root.offset_right = -32
	root.offset_bottom = -32
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# --- タイトル（i18n 経由）---
	var title := Label.new()
	title.text = tr("ui.app.title")
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "INC-0 Walking Skeleton — 動作確認画面"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(subtitle)

	root.add_child(HSeparator.new())

	# --- autoload 4本の状態 ---
	_add_section(root, "Autoload")
	_add_check(root, "EventBus", get_node_or_null("/root/EventBus") != null)
	_add_check(root, "Lexicon", get_node_or_null("/root/Lexicon") != null)
	_add_check(root, "GameState", get_node_or_null("/root/GameState") != null)
	_add_check(root, "SpellEngine", get_node_or_null("/root/SpellEngine") != null)

	# --- データ駆動アセット ---
	_add_section(root, "データ駆動アセット")
	var words_loaded: int = 0
	var word_names: PackedStringArray = PackedStringArray()
	for word_id in WORD_IDS:
		var path := "res://data/words/%s.tres" % word_id
		var word: Resource = load(path)
		if word != null:
			words_loaded += 1
			word_names.append(word_id)
	_add_check(root, "WordResource .tres", words_loaded == WORD_IDS.size(),
		"%d / %d 語: %s" % [words_loaded, WORD_IDS.size(), ", ".join(word_names)])

	var ruleset: Resource = load("res://data/grammar/phase_intro.tres")
	var ruleset_ok: bool = ruleset != null
	var ruleset_detail: String = ""
	if ruleset_ok:
		ruleset_detail = "id=%s, scaffold=%s" % [ruleset.get("id"), ruleset.get("scaffold_level")]
	_add_check(root, "GrammarRuleset .tres", ruleset_ok, ruleset_detail)

	# --- 縦の骨が通る ---
	_add_section(root, "縦の骨 (SpellEngine.cast)")
	var engine := get_node_or_null("/root/SpellEngine")
	var cast_ok: bool = false
	var cast_detail: String = "engine not found"
	if engine != null and ruleset_ok:
		var tokens_in: Array = [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		]
		var result = engine.cast(tokens_in, ruleset)
		if result != null:
			cast_ok = (result.grammar_report != null
				and result.effect_spec != null
				and result.resolved != null
				and result.debug.has("misfire_chance"))
			cast_detail = "C=%.0f / G=%.2f / misfire=%.3f / band=%s" % [
				float(result.debug.get("C", 0.0)),
				float(result.debug.get("G", 0.0)),
				float(result.debug.get("misfire_chance", 0.0)),
				str(result.debug.get("band", "")),
			]
	_add_check(root, "cast() → CastResult", cast_ok, cast_detail)

	# --- 暴発式 (03 §5.2) サニティ ---
	_add_section(root, "Resolver 数式 (03 §5.2)")
	_add_check(root, "C=0 → 暴発10%", is_equal_approx(SpellResolver.compute_misfire_chance(0.0), 0.10),
		"got %.3f" % SpellResolver.compute_misfire_chance(0.0))
	_add_check(root, "C=50 → 暴発5%", is_equal_approx(SpellResolver.compute_misfire_chance(50.0), 0.05),
		"got %.3f" % SpellResolver.compute_misfire_chance(50.0))
	_add_check(root, "C=100 → 暴発0%", is_equal_approx(SpellResolver.compute_misfire_chance(100.0), 0.0),
		"got %.3f" % SpellResolver.compute_misfire_chance(100.0))

	# --- フッタ ---
	root.add_child(HSeparator.new())
	var footer := Label.new()
	footer.text = "詳細テスト (34アサーション) は tests/test_smoke.tscn を F6 で実行。"
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(footer)


func _add_section(parent: Node, title: String) -> void:
	var label := Label.new()
	label.text = "■ " + title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	parent.add_child(label)


func _add_check(parent: Node, name: String, ok: bool, detail: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var icon := Label.new()
	icon.text = "✓" if ok else "✗"
	icon.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_FAIL)
	icon.add_theme_font_size_override("font_size", 16)
	icon.custom_minimum_size = Vector2(24, 0)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = name
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.custom_minimum_size = Vector2(280, 0)
	row.add_child(name_label)

	if detail != "":
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.add_theme_font_size_override("font_size", 13)
		detail_label.add_theme_color_override("font_color", COLOR_MUTED)
		detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(detail_label)
