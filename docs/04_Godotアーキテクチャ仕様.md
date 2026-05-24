# Godotアーキテクチャ仕様 — Málfráedingur

| 項目 | 内容 |
|------|------|
| エンジン | Godot 4.x（GDScript 主体。重い処理のみ後で最適化） |
| 役割 | 実装エージェントが従うプロジェクト構造・設計規約 |
| ステータス | Draft v0.7 |

## 更新履歴
- v0.1 初版
- v0.2 戦闘まわり確定を反映：`run/combat.tscn`（コマンド入力型ターン制コントローラ）追加、SpellComposer をタイル選択＋格サブ選択／無辞書フルテキストに確定、データフローをターン制＋詠唱コスト（1手番＋世界時間Δ、MP不使用）に更新
- v0.3 枠物語確定を反映：セーブ/永続を「記録アーティファクト＋巻き戻し」にマッピング（§7）。`öld renna aptr` はコア呪文 API を通さない固定イベントと明記。テスト名をループ/巻き戻し前提に更新
- v0.4 項目5確定を反映：SpellComposer に補助段階（scaffold_level）の責務を明記（補助はUI層のみ・Validator/G非関与・未解禁構文は非表示）。`Lexicon` 永続に `grammar_progress` を追加（D7恒久）
- v0.5 項目10確定を反映：設計方針に i18n（INC-0外部化・JA先行・ENリリース必須）とフォント全字カバー制約を追加。SpellComposer にロケール別グロス表示／カナ副ラベル／無辞書で発音非表示／発音は非メカニクスを明記
- **v0.6 マス目移動・グリッド戦術導入の大改訂**（2026-05-23 ユーザー判断、`01 v0.9` / `02 v0.9` / `03 v0.18` / 新規 `09` と一体）。`core/map/` レイヤを新規追加（dungeon_generator / map_data / tile_grid / pathfinder）。`core/spell/spatial_resolver.gd` を新規追加（範囲語・方向語から対象タイル集合 T を計算、INC-3.5 で本格化）。autoload に `MapState`（現階層・プレイヤー位置・向き）を追加。EventBus に新規シグナル（enemy_in_sight / player_moved / floor_changed）。シーン構成は `run/combat.tscn` を廃止し `scenes/dungeon/dungeon_view.tscn` に統合（シームレス型）。SpellComposer に射程プレビュー責務を追加（scaffold=max でタイルハイライト・方向矢印・AoE 範囲）
- **v0.7 INC-3.5 完了後の磨き上げ**（2026-05-24）。§2 ツリーから `scenes/combat/combat_test.tscn` 廃止（dungeon_view に役割統合、二重保守解消）。`tests/scenarios/combat/` も同時廃止。§5 主要シーン表を更新

---

## 1. 設計方針

- **データ駆動**: 語彙・文法規則・敵・フロアは Resource(`.tres`)/JSON。コードにゲーム内容をハードコードしない。
- **疎結合**: 呪文エンジンはゲームプレイから独立してテスト可能（M1 が戦闘なしで成立する根拠）。
- **シグナル中心**: ノード間直接参照を避け `EventBus` 経由。
- **永続と一時の分離**: `Lexicon`（永続）と `GameState`（ループ一時）を明確に分ける（テーマ実装の根幹）。
- **i18n を INC-0 から（DL1）**: 全 UI 文字列を翻訳テーブル経由で表示（ハードコード禁止）。ロケール切替を実装。JA を先行作成、EN はリリース必須（後付けは改修が重いので構造だけ最初に通す）。グロスは `WordResource.gloss[locale]`（`05`）。
- **【フォント制約・確定】古ノルド語字形の全カバー必須**: 使用フォントは `þ ð æ ö œ ǫ á é í ó ú ý ø` 等を全字レンダリングできること（豆腐化防止）。古綴（長母音 œ・ǫ 等）が正典表記のため、これらを含むフォントを INC-0 で選定・固定する。等幅/可読性重視（言語ゲームのため）。

---

## 2. ディレクトリ規約

```
res://
├── autoload/            # シングルトン
│   ├── game_state.gd
│   ├── lexicon.gd
│   ├── spell_engine.gd
│   ├── map_state.gd     # v0.6 新規: 現階層・プレイヤー位置・向き・FOV キャッシュ
│   └── event_bus.gd
├── core/spell/          # 呪文エンジン（ゲームプレイ非依存）
│   ├── tokenizer.gd
│   ├── parser.gd
│   ├── validator.gd
│   ├── evaluator.gd
│   ├── spatial_resolver.gd  # v0.6 新規: 範囲語・方向語から対象タイル T を計算（INC-3.5）
│   ├── resolver.gd
│   └── models/          # SpellAST, GrammarReport, EffectSpec, ResolvedEffect, TargetSet ...
├── core/map/            # v0.6 新規: マップ・移動レイヤ（09 と一対一）
│   ├── dungeon_generator.gd  # 部屋＋通路の seed 駆動生成（09 §2）
│   ├── map_data.gd           # タイル配列・部屋リスト・階段位置を保持
│   ├── tile_grid.gd          # 描画・FOV キャッシュ
│   ├── pathfinder.gd         # A* / BFS（敵 AI 用）
│   └── models/               # TileKind, RoomRect, DungeonSeed ...
├── core/combat/         # v0.6 新規（INC-2 で先行存在）: 戦闘ロジック
│   ├── combatant.gd
│   ├── damage_calculator.gd
│   └── combat_system.gd
├── data/                # データ駆動アセット
│   ├── words/           # WordResource (.tres)
│   ├── grammar/         # 規則セット・語順定義
│   ├── enemies/         # v0.6: 巡回・追跡 AI パラメータを追記
│   ├── tiles/           # v0.6 新規: tile_kinds.tres（09 §3.3）
│   └── floors/          # フロアテンプレート（v0.6: helgrind_1〜3.tres）
├── scenes/
│   ├── main.tscn
│   ├── dungeon/         # v0.6 新規: シームレス探索＝戦闘
│   │   ├── dungeon_view.tscn      # マス目グリッド描画＋シームレス戦闘モード切替
│   │   └── player_token.tscn      # プレイヤー駒（向き矢印付き）
│   ├── run/             # 1ループ統括: run.tscn（floor.tscn / combat.tscn は v0.6 で dungeon_view に統合・廃止）
│   ├── actors/          # player.tscn, enemy.tscn
│   └── ui/              # spell_composer.tscn, lexicon_screen.tscn, hud.tscn
├── debug/
│   └── spell_lab.tscn   # INC-1 検証用（戦闘なし）
└── tests/               # GUT 等での単体テスト
```

> **v0.6 重要変更**: 旧 v0.2 で追加した `scenes/run/combat.tscn`（コマンド入力型ターン制の独立シーン）は**廃止**。シームレス型では探索と戦闘が同一シーン `scenes/dungeon/dungeon_view.tscn` に統合される（`09 §6.1` の「警戒モード/平時モード」は UI 層の前景/後景の切替えで表現）。
> **v0.9.7 追記**: `combat_test.tscn`（INC-2 デバッグ用）は INC-3.5 完了をもって役割を終え、**廃止**。dungeon_view が grid-aware の戦闘検証も兼ねるため、二重保守を避ける。CombatSystem / DamageCalculator のロジックは `tests/test_smoke.gd` の統合 E2E テスト（INC-2 v0.4 由来）で継続検証。

---

## 3. Autoload（シングルトン）責務

| Autoload | 責務 | 永続 |
|----------|------|------|
| `EventBus` | グローバルシグナルのハブ。直接参照を排除。v0.6 で `enemy_in_sight` / `player_moved` / `player_turned` / `floor_changed` / `enter_combat_mode` / `exit_combat_mode` を追加 | – |
| `Lexicon` | 全語彙と理解度＋`grammar_progress`（解禁フェーズ/補助段階/解禁構文・D7で巻き戻し非対象）。発見/学習の更新。`user://` へセーブ/ロード | **永続** |
| `GameState` | 現ループの状態（HP・到達階・**世界時間残量**・**現手番**・一時バフ）。`advance_world_time(Δ)` / 手番進行を提供 | 一時（死亡でリセット） |
| `MapState` (v0.6 新規) | **現階層のマップデータ（`MapData`）・プレイヤータイル座標 `(x,y)`・プレイヤーの向き（N/S/E/W）・FOV キャッシュ・敵リスト**。`move_player(dx,dy)` / `turn_player(dir)` / `recompute_fov()` / `enemies_in_sight()` を提供。巻き戻しで `reset()`、知識ではなくループ状態なので `Lexicon` には書かない | 一時（巻き戻しでリセット、`09 §2.5`） |
| `SpellEngine` | 呪文パイプラインのファサード。`cast(tokens, ruleset, spatial_context) -> CastResult`（v0.6 で `spatial_context` 引数追加。プレイヤー位置・向き・FOV を渡し、SpatialResolver が対象タイル集合 T を計算） | – |

> **不変条件:** 死亡処理は `GameState` のみ初期化し `Lexicon` に触れない。これがテーマ「知識は残る」のコード上の保証点。テストで担保すること（`04` §7）。

---

## 4. 呪文エンジン API（ゲームプレイ非依存）

```gdscript
# SpellEngine（Autoload, ファサード, v0.6 改訂）
func cast(word_ids: Array[String], ruleset: GrammarRuleset, spatial_context: SpatialContext = null) -> CastResult

# SpatialContext（v0.6 新規、09 §6/§7）
#   player_pos    : Vector2i   # プレイヤータイル座標
#   player_facing : int        # 0=N 1=E 2=S 3=W
#   visible_tiles : Dictionary # {Vector2i: bool}（FOV、視界外の対象は届かない判定）
#   enemies       : Array      # [{pos:Vector2i, id:String}, …]
#   map_data      : MapData    # 壁・タイル属性アクセス用

# CastResult（モデル, v0.6 拡張）
#   grammar_report : GrammarReport   # 規則ごと pass/fail と理由（UIフィードバック源）
#   effect_spec    : EffectSpec      # 評価された効果（威力=Σtier, 期待値）
#   target_set     : TargetSet       # v0.6 新規: 対象タイル集合 T と対象敵 ID（SpatialResolver の出力）
#   resolved       : ResolvedEffect  # 制御精度適用後（ばらつき/暴発/対象ズレ確定）
#   debug          : Dictionary      # Control, variance, misfire_chance 等（spell_lab表示用）
```

- パイプライン（Tokenizer→Parser→Validator→Evaluator→**SpatialResolver**→Resolver）は `03` §4・§5 と `09 §7.4` を正とする。
- `ruleset` を注入可能にし、`03` §6 のフェーズ解禁（格判定 ON/OFF・範囲語/方向語の minor↔コア違反スイッチなど）を実現する。
- `spatial_context` は INC-3 以降必須。INC-1/2 の spell_lab/combat_test は `null` を渡し、SpatialResolver は「タイル指定なし＝最隣接敵自動」の最小モードで動作（後方互換）。
- 乱数は seed 注入可能（ローグライク再現性・テスト）。
- **物語固定詠唱 `öld renna aptr`（巻き戻し）は本 API を通さない。** §7 の巻き戻し処理（記録アーティファクト）が固定イベントとして扱う（`03` 附録A.9）。`SpellEngine` は戦闘用の自由構築呪文のみ責務とする。

---

## 5. 主要シーン構成

| シーン | 役割 | 依存 |
|--------|------|------|
| `main.tscn` | 起動・タイトル・モード選択（通常/碑文モード） | Lexicon |
| `run/run.tscn` | 1ループ(7日)の進行管理。階層生成・タイムリミット駆動 | GameState, MapState |
| `dungeon/dungeon_view.tscn` (v0.6 新規) | **シームレス探索＝戦闘**。マス目グリッド描画／プレイヤー駒（向き矢印）／敵描画／FOV 表示／**警戒モード/平時モードの UI 切替**／詠唱対象タイルのハイライト。`run/floor.tscn` と旧 `run/combat.tscn` を統合（`09 §6.1`） | MapState, GameState, SpellEngine |
| `dungeon/player_token.tscn` (v0.6 新規) | プレイヤー駒（向きを示す矢印または三角形） | MapState |
| `actors/player.tscn` | プレイヤー。詠唱入力を SpellComposer に委譲 | SpellEngine |
| `actors/enemy.tscn` | データ駆動の敵（v0.6: 巡回・追跡 AI、`09 §5`） | data/enemies, MapState |
| `ui/spell_composer.tscn` | **習得語タイル選択＋対象語の格サブ選択**で呪文構築。無辞書モードはフルテキスト入力欄に切替。GrammarReport を可読化して提示。**v0.6 で射程プレビュー責務を追加**（scaffold=max でタイルハイライト・方向矢印・AoE 範囲のライブプレビュー、`09 §9`） | SpellEngine, Lexicon, MapState |
| `ui/lexicon_screen.tscn` | 語彙閲覧・集中学習（時間消費） | Lexicon, GameState |
| `ui/hud.tscn` | HP・タイムリミット残量・現手番・**現在地・既知マップ縮小表示**（v0.6）の常時可視化 | GameState, MapState |
| `debug/spell_lab.tscn` | **INC-1専用**: 語入力→判定/威力/ばらつき/暴発率を可視化（戦闘なし） | SpellEngine |
| ~~`combat_test.tscn`~~ | **v0.9.7 で廃止**。INC-2 デバッグ用だったが INC-3.5 完了をもって dungeon_view に役割統合。CombatSystem/DamageCalculator は test_smoke の E2E で継続検証 | – |

> **v0.6 廃止**: 旧 v0.2 の `run/floor.tscn` および `run/combat.tscn` は `dungeon/dungeon_view.tscn` に統合（シームレス型）。`scenes/run/` には `run.tscn`（ループ統括）のみが残る。

> **SpellComposer 入力モデル（確定）**: 通常モードは `Lexicon` の習得語からタイルを生成し、対象語タイル選択時に格サブ選択UI（主格/対格…）を出す。無辞書モードはタイルを隠し生テキスト入力にする。いずれも出力を **`{word_id, case}` の正規化トークン列**にして `EventBus.spell_cast_requested` に渡す（`03` §4 の2系統正規化と一致）。
>
> **補助段階（scaffold_level）の責務（項目5・確定）**: SpellComposer は `grammar_progress.scaffold_level`（`05`）に応じて補助量を変える＝max:正格自動提示/不正語順グレーアウト/ライブプレビュー、mid:要求時ヒント＋詠唱前警告、low:詠唱後 `GrammarReport` のみ、none:補助なし（無辞書は none＋使用可能範囲で最厳 ruleset 強制）。**補助は入力支援のみ。`SpellEngine`/`Validator` の合否・`G` には一切影響しない**（`03` §6.1/§8、D3）。未解禁構文のタイル・入力は**出さない**（可用性ゲート＝寛容化ではない）。`GrammarReport` の是正フィードバックは全段階で常時表示。
>
> **表示言語・発音（項目10・確定）**: タイル/グロスは `WordResource.gloss[現在ロケール]` で表示（JA先行・ENリリース必須）。タイル副ラベルに `reading_kana` を表示補助として出す。詳細ビューで `ipa` 任意表示。**無辞書モードはグロス・カナ読みとも非表示**（DP3）。発音は表示のみで `SpellEngine` に渡さない（DP2、`01` 3.3/6.1）。

---

## 6. データフロー（v0.6 シームレス・位置あり）

```
[プレイヤー手番] dungeon_view が入力受付（移動/旋回/詠唱/待機 の 4 択）
   │
   ├─ 移動 1 タイル ──> MapState.move_player(dx,dy) → FOV 再計算 → 世界時間 Δ_move 消費
   │
   ├─ 旋回 ──> MapState.turn_player(dir) → FOV 再計算 → 世界時間 Δ=0
   │
   └─ 詠唱:
       SpellComposer（タイル選択＋格サブ選択＋[方向語/距離語/タイル指定] / 無辞書はテキスト）
          │ scaffold=max では射程プレビュー: SpellEngine.preview(tokens, ruleset, spatial_context)
          │ を呼び対象タイルをハイライト（詠唱前に毎フレーム）
          └─emit─> EventBus.spell_cast_requested(tokens)
                        │
                   spatial_context := MapState.snapshot()  # player_pos/facing/visible/enemies
                        │
                   SpellEngine.cast(tokens, ruleset, spatial_context) ──> CastResult
                        │（パイプライン: Tokenizer→Parser→Validator→Evaluator→SpatialResolver→Resolver）
   ┌────────────────────┴────────────────────┐
   ▼                                          ▼
HUD/Composer に                            Player/Enemy に
GrammarReport を可読表示                    ResolvedEffect を適用（対象は CastResult.target_set）
（失敗=学習フィードバック・射程外も）        （ダメージ/回復/暴発、AoE は対象敵集合に展開）
                        │
                   Lexicon.gain_comprehension(used_words, source="combat")
                        │
                   詠唱コストを消費:
                     ・GameState のプレイヤーターンを終了（1詠唱＝1手番）
                     ・GameState.advance_world_time(Δ_cast)  # Δ=語数・語ティア依存（05 BalanceConfig）
                        │
                   [敵手番] 各敵について:
                     ・MapState.enemies_in_sight_of_enemy(e) でプレイヤー視認チェック
                     ・追跡 (pathfinder) or 巡回 or 隣接攻撃 を選択
                     ・MapState.move_enemy(e, ...) / 攻撃なら Player.take_damage(...)
                        │
                   次のプレイヤー手番へ
```

> MP は存在しない。連打抑制は **1詠唱＝1手番＋世界時間Δ** で表現（`01` 3.8 / `05`）。v0.6 では**移動も世界時間 Δ_move を消費**するため、「歩く Δ も滅びを早める」コアジレンマが追加で成立（`01 §3.5`）。
>
> `dungeon_view` がこの消費の唯一の適用点（テスト容易性のため一箇所に集約）。INC-2 の `combat_test.tscn` は `MapState` を持たない簡易環境で `spatial_context=null` を渡し、後方互換動作（最隣接敵自動）で動かす。

---

## 7. セーブ / 永続設計（＝記録アーティファクト＋巻き戻し）

物語上、セーブ／ロード／死に戻りは **「時を記録するアーティファクト」と巻き戻し詠唱 `öld renna aptr`** に対応する（`01` 1.5/3.6）。実装マッピングは以下。

| 物語 | 実装 |
|------|------|
| アーティファクトが7日前の基点を記録 | `Lexicon.save()`（永続）＋ループ開始スナップショット |
| `öld renna aptr` で巻き戻し | `GameState.reset()`（ループ状態を開始時へ） |
| 主人公の記憶は巻き戻らない | `Lexicon` は `reset()` 対象外（不変条件、§3） |

- 保存先: `user://lexicon.save`（Lexicon のみ。バージョンフィールド必須）。物語上の「アーティファクトの刻印」。
- 保存内容: 語ごとの `comprehension`、解禁文法フェーズ、実績/統計。
- **保存しない**: HP・到達階・装備・ループ一時状態・**マップデータ・プレイヤー位置・FOV キャッシュ**（v0.6、巻き戻る側＝`01` 3.6 の左列、`09 §2.5`）。
- 巻き戻し（死亡/7日切れ/任意巻き戻し）時: `Lexicon.save()` → `GameState.reset()` → `MapState.reset()` → 新規 seed で `DungeonGenerator.generate()` の順（v0.6）。**逆順厳禁**（先に記憶を確定保存してから世界を戻す）。
- 任意巻き戻し（`01` 3.6 の損切り）：プレイヤー操作 → 同じ巻き戻し経路を通る（死亡時と同一処理。`öld renna aptr` 演出を表示）。
- セーブ運用方針（確定）：アーティファクトの記録点は**ループ境界**。ループ途中の任意地点セーブによる save-scum は不可（ローグライトの緊張を保つ）。中断再開は「同一ループの一時中断」として別途扱い、巻き戻し記録とは区別する。
- 必須テスト:
  - `test_rewind_preserves_lexicon`（巻き戻し後も理解度が一致＝記憶保持）
  - `test_gamestate_reset_clears_loop`（ループ状態が開始時へ）
  - `test_mapstate_reset_clears_position` (v0.6 新規・INC-3 範囲): プレイヤー位置・向き・FOV が初期化される
  - `test_dungeon_regenerates_on_rewind` (v0.6 新規・INC-3 範囲): 巻き戻しで新規 seed のマップが生成される。起点部屋の配置のみ固定（`09 §2.5`）
  - `test_spell_engine_pure`（同一入力・同一 seed で決定的）
  - `test_fixed_incantation_bypasses_engine`（`öld renna aptr` がコア呪文パイプラインを通らず固定イベントとして処理される）
  - `test_spatial_resolver_targeting` (v0.6 新規・INC-3.5 範囲): 範囲語・方向語から対象タイル集合 T が `09 §7` の規定通り計算される（`fram` で前方タイル、`nær` で隣接、`vítt` で AoE、`í gegnum` で壁貫通線）
  - `test_spatial_resolver_out_of_range` (v0.6 新規・INC-3.5 範囲): 射程外・視界外・壁の向こうの対象は T から除外され `range_required` finding が出る

---

## 8. テスト方針（M1 を支える）

- 呪文エンジンはゲームプレイ非依存 → **単体テストを最優先整備**。
- `03` §5.5 の不変条件 T1〜T11 を自動テスト化（v0.6 で T10/T11 追加、`03 v0.18`）:
  - T1: 理解度変化で期待威力不変
  - T2: 文法 full pass で暴発単調減少
  - T3: 強ティア未習語＝高期待威力/高分散/高暴発
  - T6: G 線形乗算で文法違反時 effect_power 確定減衰
  - T7/T8/T9: elements / modifier_agreement / 語順隣接性
  - **T10/T11 (v0.6/INC-3.5)**: 範囲語の射程外検出・方向語の対象タイル決定が `09 §7` 通り
- フレームワーク: GUT（Godot Unit Test）等を想定。INC-0 で導入。

---

## 9. 実装順序（マイルストーン対応）

| MS | 実装範囲 |
|----|----------|
| INC-0 | ディレクトリ・Autoload 雛形・データスキーマ・テスト基盤 |
| INC-1 | core/spell 一式 + `spell_lab.tscn`（戦闘なし）+ T1〜T3 テスト |
| INC-2 | actors + spell_composer + `combat_test.tscn`（1フロア1敵1ボス、位置なし、INC-2 v0.4 完了済み） |
| **INC-3 (v0.6)** | **core/map/ 一式（dungeon_generator/map_data/tile_grid/pathfinder）+ MapState autoload + dungeon/dungeon_view.tscn + player_token.tscn + 敵 AI（巡回/追跡/隣接攻撃）+ 7日ループ + 巻き戻し + 3 階構造**。SpatialResolver は最小モード（タイル指定なし=最隣接敵自動）。test_mapstate_reset_clears_position / test_dungeon_regenerates_on_rewind |
| **INC-3.5 (v0.6)** | **core/spell/spatial_resolver.gd 本実装 + SpellEngine.cast() に spatial_context 引数 + SpellComposer 射程プレビュー（scaffold=max）+ Validator 拡張（range_*/direction_* コア違反扱い）+ MISFIRE_MULT_BY_RULE 拡張**。test_spatial_resolver_targeting / test_spatial_resolver_out_of_range。INC-1/2 シナリオ S1〜S6 / C1〜C5 を位置あり仕様で再走 |
| INC-4 | Lexicon 永続 + 学習3経路（碑文タイル・学習スポット・実戦学習）+ 碑文モード |
| INC-5 | data/ 量産投入 + 言語監修反映 + バランス + EN グロス着手 |
| INC-6 | UI/音/オンボーディング/配布 + EN 完全実装 |

---

参照: 全体目標 → `01` / コア仕様 → `03` / データ → `05_データ定義テンプレート.md`
