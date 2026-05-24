extends Node
## Lexicon — 永続語彙＋文法進行＋語レジストリ（Autoload）。
##
## 役割（INC-4 で永続化を実装）:
##   - 語 ID から WordResource を引く中央レジストリ（get_word）。
##   - 各語の現在の理解度（comprehension, 0..100）を保持・更新・永続化。
##   - grammar_progress（解禁フェーズ・補助段階・解禁構文）を保持・永続化。
##   - 累積統計 stats (loops/rewinds/words_discovered/helgrind_cleared) を保持・永続化。
##   - 魔法スロット 1-5（呪文プリセット）を保持・永続化。
##   - 「今ループで新たに伸びた語」の差分 (loop_delta) を提示用に保持（C: 巻き戻し画面）。
##
## 不変条件（04 §3 / §7）:
##   - 死亡時 reset されない（テーマ「知識は残る」の保証点）。
##   - 巻き戻し順序: Lexicon.save() → GameState.reset() → MapState.reset() → 新 seed 再生成
##     （04 §7 「逆順厳禁」）。
##   - HP / 到達階 / 装備 / マップ / FOV は SaveData に保存しない（ループ一時状態）。
##   - この autoload は他の autoload を **class スコープで参照しない**
##     （Godot 4 の autoload parse 順序問題回避）。
##
## スキーマ詳細は 04 §7 / 05 §7 を参照。

const SAVE_PATH := "user://lexicon.save"
const SAVE_VERSION := 1

## 既知語の ID 一覧（INC-3.5 で 17 語に拡張）。INC-5 で監修語彙台帳から自動生成へ。
const KNOWN_WORD_IDS: Array = [
	"meida", "fjandi", "sjalfr",
	"eldr", "vatn", "vindr", "jorth",
	"mikill", "litill",
	"naer", "fjarri", "vitt", "i_gegnum",
	"fram", "aptr", "vinstri", "hoegri",
]

## .tres の格納パス雛形。
const WORD_RES_PATH := "res://data/words/%s.tres"

## 語 ID → WordResource のメモリキャッシュ（同セッション内で重複 load を避ける）。
var _word_cache: Dictionary = {}

## 語 ID → 理解度（0..100、整数）。永続化対象。
var _comprehension: Dictionary = {}

## INC-4 C: 今ループで伸びた理解度の差分。 { word_id: { "before": int, "after": int } }
## ループ開始時 (snapshot_loop_baseline) で空にし、巻き戻し時 (snapshot_loop_delta) で
## 確定。巻き戻し画面 (dungeon_view) が読む。永続化しない（一時状態）。
var _loop_baseline: Dictionary = {}
var _loop_delta: Dictionary = {}

## 文法進行 (04 §7 / 05 §7 grammar_progress)。永続化対象・D7 で巻き戻し非対象。
var grammar_progress: Dictionary = {
	"unlocked_phase": "phase_intermediate",
	"scaffold_level": "max",
	"unlocked_constructs": ["effect_target", "case", "elements", "modifier", "range", "direction"],
	"unlock_reason": "story",
}

## 累積統計 (04 §7 / 05 §7 stats)。永続化対象。
var stats: Dictionary = {
	"loops": 0,
	"rewinds": 0,
	"words_discovered": 0,
	"helgrind_cleared": false,
}

## INC-4 残課題: 無辞書（碑文）モード (01 §3.7 / 09 §9)。
##   true: 辞書ヒントを封じ、テキスト入力経路で詠唱。scaffold_level=none + 最厳 ruleset 強制。
##   false: 通常モード（タイル経路、scaffold は ruleset の指定通り）。
## 永続化対象（プレイヤーの選好）。
var freetext_mode: bool = false

## 魔法スロット (INC-3 v0.9.2 新規)。永続化対象（知識側＝巻き戻し非対象）。
## デフォルト: スロット 1 = meida + fjanda (acc) のみ。INC-3.5 v0.9.7 のデモスロット 2-4 は
## INC-4 で永続化と同時に削除（プレイヤーが Spell Builder で自由に設定する）。
var _spell_slots: Dictionary = {
	1: [
		{"word_id": "meida", "case": ""},
		{"word_id": "fjandi", "case": "acc"},
	],
}


# ============================================================================
#  ライフサイクル
# ============================================================================

func _ready() -> void:
	# INC-4 A: 起動時にディスクから読む。失敗してもデフォルト値で続行（初回起動）。
	load_from_disk()
	_snapshot_loop_baseline()


# ============================================================================
#  魔法スロット (INC-3 v0.9.2 〜)
# ============================================================================

## スロット番号 (1-5) から保存済みトークン列を取得。未設定なら空配列。
func get_spell_slot(slot: int) -> Array:
	if slot < 1 or slot > 5:
		return []
	return _spell_slots.get(slot, []).duplicate(true)


## スロット番号にトークン列を保存。slot ∈ [1, 5]。
##   tokens: [{ "word_id": String, "case": String }, ...]
func set_spell_slot(slot: int, tokens: Array) -> void:
	if slot < 1 or slot > 5:
		return
	_spell_slots[slot] = tokens.duplicate(true)
	save_to_disk()


## スロット 1-5 の状態スナップショット（UI 表示用）。
##   返り値: { 1: [tokens] or null, 2: ..., ..., 5: ... }
func get_all_spell_slots() -> Dictionary:
	var result: Dictionary = {}
	for i in range(1, 6):
		result[i] = _spell_slots.get(i, null)
	return result


# ============================================================================
#  WordResource レジストリ
# ============================================================================

## 語 ID から WordResource を取得。なければ null。
func get_word(word_id: String) -> WordResource:
	if word_id.is_empty():
		return null
	if _word_cache.has(word_id):
		return _word_cache[word_id]
	var path := WORD_RES_PATH % word_id
	if not ResourceLoader.exists(path):
		return null
	var res: WordResource = load(path) as WordResource
	if res != null:
		_word_cache[word_id] = res
	return res


## 既知語の ID 配列（重複 load を避ける用途）。
func get_known_word_ids() -> Array:
	return KNOWN_WORD_IDS.duplicate()


# ============================================================================
#  理解度 (comprehension) — INC-4 で本格化
# ============================================================================

## 語の現在理解度（0..100）。未登録なら WordResource.comprehension_default を返す。
func get_comprehension(word_id: String) -> int:
	if _comprehension.has(word_id):
		return int(_comprehension[word_id])
	var w := get_word(word_id)
	if w != null:
		return w.comprehension_default
	return 0


## デバッグ/テスト用: 理解度を直接設定。永続化される。
func set_comprehension(word_id: String, value: int) -> void:
	var clamped := clampi(value, 0, 100)
	_comprehension[word_id] = clamped
	save_to_disk()


## INC-4 B: 理解度を加算する。03 §6 D6 の「文法的に正しい詠唱でのみ伸びる」が
## 守られているかは呼び出し側（SpellEngine / dungeon_view）が保証する責務。
## 返り値: 実際に伸びた量（0..100 の clamp 後の差）。
##   word_id: 語 ID
##   amount: 加算量（正の整数。負はノーオペ）
func add_comprehension(word_id: String, amount: int) -> int:
	if amount <= 0 or word_id.is_empty():
		return 0
	# 未知語の発見扱い（初回触れた瞬間）
	var was_discovered := _comprehension.has(word_id)
	var before := get_comprehension(word_id)
	var after := clampi(before + amount, 0, 100)
	_comprehension[word_id] = after
	if not was_discovered:
		stats["words_discovered"] = int(stats.get("words_discovered", 0)) + 1
	var actual := after - before
	if actual > 0:
		var eb := get_node_or_null("/root/EventBus")
		if eb != null:
			eb.lexicon_word_learned.emit(word_id, after)
		save_to_disk()
	return actual


# ============================================================================
#  INC-4 C: 「今ループで伸びた語」差分
# ============================================================================

## ループ開始時に現在の理解度スナップショットを取る（差分計算のベースライン）。
## _ready() 起動時 / ループ巻き戻し後の reset_for_new_loop() で呼ばれる。
func _snapshot_loop_baseline() -> void:
	_loop_baseline.clear()
	for word_id in KNOWN_WORD_IDS:
		_loop_baseline[word_id] = get_comprehension(word_id)
	_loop_delta.clear()


## 巻き戻し直前に呼ばれ、今ループの差分を固定する（巻き戻し画面が読む用）。
## 差分は次ループの reset_for_new_loop() でクリアされる。
func snapshot_loop_delta() -> void:
	_loop_delta.clear()
	for word_id in KNOWN_WORD_IDS:
		var before: int = int(_loop_baseline.get(word_id, 0))
		var after: int = get_comprehension(word_id)
		if after > before:
			_loop_delta[word_id] = {"before": before, "after": after, "gain": after - before}


## 今ループで伸びた語の差分（巻き戻し画面用）。空なら「成長なし」。
##   返り値: { word_id: { "before": int, "after": int, "gain": int }, ... }
func get_loop_delta() -> Dictionary:
	return _loop_delta.duplicate(true)


## ループ巻き戻し後、新ループ用にベースラインを取り直し、差分をクリア。
## stats.loops と stats.rewinds の更新もここで一括。
##   rewind_reason: "death" | "timeout" | "manual" — stats.rewinds++ するか判定用
func reset_for_new_loop(rewind_reason: String = "") -> void:
	stats["loops"] = int(stats.get("loops", 0)) + 1
	if rewind_reason != "":
		stats["rewinds"] = int(stats.get("rewinds", 0)) + 1
	_snapshot_loop_baseline()
	save_to_disk()


## Helgrind 踏破フラグを立てる（永続）。
func mark_helgrind_cleared() -> void:
	stats["helgrind_cleared"] = true
	save_to_disk()


# ============================================================================
#  INC-4 A: 永続化 (user://lexicon.save)
# ============================================================================

## 現在の Lexicon 状態をディスクへ保存。schema は 04 §7 / 05 §7 に準拠。
func save_to_disk() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"lexicon": {},
		"grammar_progress": grammar_progress.duplicate(true),
		"stats": stats.duplicate(true),
		"spell_slots": {},
		"freetext_mode": freetext_mode,
	}
	for word_id in _comprehension.keys():
		data["lexicon"][word_id] = {"comprehension": int(_comprehension[word_id])}
	# spell_slots はキーが int だが JSON では str に変換される。読み込み時に int 化する。
	for slot_num in _spell_slots.keys():
		data["spell_slots"][str(slot_num)] = _spell_slots[slot_num]

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Lexicon.save_to_disk: cannot open %s for write" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


## ディスクから読む。ファイルが無ければデフォルト値のまま続行（初回起動）。
## バージョン不一致なら警告のみ、可能な限り部分読み込みを試みる。
func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("Lexicon.load_from_disk: cannot open %s for read" % SAVE_PATH)
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Lexicon.load_from_disk: invalid JSON (got %s)" % typeof(parsed))
		return false
	var data: Dictionary = parsed

	var version := int(data.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("Lexicon.load_from_disk: version mismatch (save=%d, current=%d) — attempting best-effort load" % [version, SAVE_VERSION])

	# lexicon
	_comprehension.clear()
	var lex_dict = data.get("lexicon", {})
	if typeof(lex_dict) == TYPE_DICTIONARY:
		for word_id in lex_dict.keys():
			var entry = lex_dict[word_id]
			if typeof(entry) == TYPE_DICTIONARY and entry.has("comprehension"):
				_comprehension[String(word_id)] = clampi(int(entry["comprehension"]), 0, 100)

	# grammar_progress
	var gp = data.get("grammar_progress", null)
	if typeof(gp) == TYPE_DICTIONARY and not gp.is_empty():
		grammar_progress = gp.duplicate(true)

	# stats
	var s = data.get("stats", null)
	if typeof(s) == TYPE_DICTIONARY and not s.is_empty():
		# 既存キーを保ちつつ上書きで取り込み
		for k in ["loops", "rewinds", "words_discovered", "helgrind_cleared"]:
			if s.has(k):
				stats[k] = s[k]

	# spell_slots（キー int 化）
	var slots = data.get("spell_slots", null)
	if typeof(slots) == TYPE_DICTIONARY and not slots.is_empty():
		_spell_slots.clear()
		for k in slots.keys():
			var slot_num := int(String(k))
			var tokens = slots[k]
			if slot_num >= 1 and slot_num <= 5 and typeof(tokens) == TYPE_ARRAY:
				_spell_slots[slot_num] = tokens.duplicate(true)

	# freetext_mode
	freetext_mode = bool(data.get("freetext_mode", false))

	return true


## ディスクのセーブを削除（テスト用 / プレイヤーの「最初からやり直す」用）。
func wipe_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("lexicon.save")
	_comprehension.clear()
	stats = {
		"loops": 0,
		"rewinds": 0,
		"words_discovered": 0,
		"helgrind_cleared": false,
	}
	_spell_slots = {
		1: [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		],
	}
	freetext_mode = false
	_snapshot_loop_baseline()


## テスト用: メモリ状態だけ初期化（ディスクは触らない）。
func _reset_memory_only_for_test() -> void:
	_comprehension.clear()
	stats = {
		"loops": 0,
		"rewinds": 0,
		"words_discovered": 0,
		"helgrind_cleared": false,
	}
	_spell_slots = {
		1: [
			{"word_id": "meida", "case": ""},
			{"word_id": "fjandi", "case": "acc"},
		],
	}
	freetext_mode = false
	_snapshot_loop_baseline()
