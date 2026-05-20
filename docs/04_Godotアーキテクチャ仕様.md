# Godotアーキテクチャ仕様 — Málfráedingur

| 項目 | 内容 |
|------|------|
| エンジン | Godot 4.x（GDScript 主体。重い処理のみ後で最適化） |
| 役割 | 実装エージェントが従うプロジェクト構造・設計規約 |
| ステータス | Draft v0.1 |

## 更新履歴
- v0.1 初版
- v0.2 戦闘まわり確定を反映：`run/combat.tscn`（コマンド入力型ターン制コントローラ）追加、SpellComposer をタイル選択＋格サブ選択／無辞書フルテキストに確定、データフローをターン制＋詠唱コスト（1手番＋世界時間Δ、MP不使用）に更新
- v0.3 枠物語確定を反映：セーブ/永続を「記録アーティファクト＋巻き戻し」にマッピング（§7）。`öld renna aptr` はコア呪文 API を通さない固定イベントと明記。テスト名をループ/巻き戻し前提に更新
- v0.4 項目5確定を反映：SpellComposer に補助段階（scaffold_level）の責務を明記（補助はUI層のみ・Validator/G非関与・未解禁構文は非表示）。`Lexicon` 永続に `grammar_progress` を追加（D7恒久）
- v0.5 項目10確定を反映：設計方針に i18n（INC-0外部化・JA先行・ENリリース必須）とフォント全字カバー制約を追加。SpellComposer にロケール別グロス表示／カナ副ラベル／無辞書で発音非表示／発音は非メカニクスを明記

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
│   └── event_bus.gd
├── core/spell/          # 呪文エンジン（ゲームプレイ非依存）
│   ├── tokenizer.gd
│   ├── parser.gd
│   ├── validator.gd
│   ├── evaluator.gd
│   ├── resolver.gd
│   └── models/          # SpellAST, GrammarReport, EffectSpec ...
├── data/                # データ駆動アセット
│   ├── words/           # WordResource (.tres)
│   ├── grammar/         # 規則セット・語順定義
│   ├── enemies/
│   └── floors/          # フロアテンプレート
├── scenes/
│   ├── main.tscn
│   ├── run/             # 1ループ: run.tscn, floor.tscn
│   ├── actors/          # player.tscn, enemy.tscn
│   └── ui/              # spell_composer.tscn, lexicon_screen.tscn, hud.tscn
├── debug/
│   └── spell_lab.tscn   # M1 検証用（戦闘なし）
└── tests/               # GUT 等での単体テスト
```

---

## 3. Autoload（シングルトン）責務

| Autoload | 責務 | 永続 |
|----------|------|------|
| `EventBus` | グローバルシグナルのハブ。直接参照を排除 | – |
| `Lexicon` | 全語彙と理解度＋`grammar_progress`（解禁フェーズ/補助段階/解禁構文・D7で巻き戻し非対象）。発見/学習の更新。`user://` へセーブ/ロード | **永続** |
| `GameState` | 現ループの状態（HP・到達階・**世界時間残量**・**現手番**・一時バフ）。`advance_world_time(Δ)` / 手番進行を提供 | 一時（死亡でリセット） |
| `SpellEngine` | 呪文パイプラインのファサード。`cast(tokens, ruleset) -> CastResult` | – |

> **不変条件:** 死亡処理は `GameState` のみ初期化し `Lexicon` に触れない。これがテーマ「知識は残る」のコード上の保証点。テストで担保すること（`04` §7）。

---

## 4. 呪文エンジン API（ゲームプレイ非依存）

```gdscript
# SpellEngine（Autoload, ファサード）
func cast(word_ids: Array[String], ruleset: GrammarRuleset) -> CastResult

# CastResult（モデル）
#   grammar_report : GrammarReport   # 規則ごと pass/fail と理由（UIフィードバック源）
#   effect_spec    : EffectSpec      # 評価された効果（威力=Σtier, 期待値）
#   resolved       : ResolvedEffect  # 制御精度適用後（ばらつき/暴発/対象ズレ確定）
#   debug          : Dictionary      # Control, variance, misfire_chance 等（spell_lab表示用）
```

- パイプライン（Tokenizer→Parser→Validator→Evaluator→Resolver）は `03` §4・§5 を正とする。
- `ruleset` を注入可能にし、`03` §6 のフェーズ解禁（格判定 ON/OFF など）を実現する。
- 乱数は seed 注入可能（ローグライク再現性・テスト）。
- **物語固定詠唱 `öld renna aptr`（巻き戻し）は本 API を通さない。** §7 の巻き戻し処理（記録アーティファクト）が固定イベントとして扱う（`03` 附録A.9）。`SpellEngine` は戦闘用の自由構築呪文のみ責務とする。

---

## 5. 主要シーン構成

| シーン | 役割 | 依存 |
|--------|------|------|
| `main.tscn` | 起動・タイトル・モード選択（通常/碑文モード） | Lexicon |
| `run/run.tscn` | 1ループ(7日)の進行管理。階層生成・タイムリミット駆動 | GameState |
| `run/floor.tscn` | 手続き生成された1フロア（敵・碑文・学習スポット配置） | data/floors |
| `run/combat.tscn` | **戦闘コントローラ（コマンド入力型ターン制）**。手番管理（プレイヤー手番→解決→敵手番）、詠唱コスト（1ターン＋世界時間Δ）の適用、勝敗判定 | GameState, SpellEngine |
| `actors/player.tscn` | プレイヤー。詠唱入力を SpellComposer に委譲 | SpellEngine |
| `actors/enemy.tscn` | データ駆動の敵 | data/enemies |
| `ui/spell_composer.tscn` | **習得語タイル選択＋対象語の格サブ選択**で呪文構築。無辞書モードはフルテキスト入力欄に切替。GrammarReport を可読化して提示 | SpellEngine, Lexicon |
| `ui/lexicon_screen.tscn` | 語彙閲覧・集中学習（時間消費） | Lexicon, GameState |
| `ui/hud.tscn` | HP・タイムリミット残量・現手番の常時可視化 | GameState |
| `debug/spell_lab.tscn` | **INC-1専用**: 語入力→判定/威力/ばらつき/暴発率を可視化（戦闘なし） | SpellEngine |

> **SpellComposer 入力モデル（確定）**: 通常モードは `Lexicon` の習得語からタイルを生成し、対象語タイル選択時に格サブ選択UI（主格/対格…）を出す。無辞書モードはタイルを隠し生テキスト入力にする。いずれも出力を **`{word_id, case}` の正規化トークン列**にして `EventBus.spell_cast_requested` に渡す（`03` §4 の2系統正規化と一致）。
>
> **補助段階（scaffold_level）の責務（項目5・確定）**: SpellComposer は `grammar_progress.scaffold_level`（`05`）に応じて補助量を変える＝max:正格自動提示/不正語順グレーアウト/ライブプレビュー、mid:要求時ヒント＋詠唱前警告、low:詠唱後 `GrammarReport` のみ、none:補助なし（無辞書は none＋使用可能範囲で最厳 ruleset 強制）。**補助は入力支援のみ。`SpellEngine`/`Validator` の合否・`G` には一切影響しない**（`03` §6.1/§8、D3）。未解禁構文のタイル・入力は**出さない**（可用性ゲート＝寛容化ではない）。`GrammarReport` の是正フィードバックは全段階で常時表示。
>
> **表示言語・発音（項目10・確定）**: タイル/グロスは `WordResource.gloss[現在ロケール]` で表示（JA先行・ENリリース必須）。タイル副ラベルに `reading_kana` を表示補助として出す。詳細ビューで `ipa` 任意表示。**無辞書モードはグロス・カナ読みとも非表示**（DP3）。発音は表示のみで `SpellEngine` に渡さない（DP2、`01` 3.3/6.1）。

---

## 6. データフロー（戦闘時：コマンド入力型ターン制）

```
[プレイヤー手番] CombatController が入力受付
   │
SpellComposer（タイル選択＋格サブ選択 / 無辞書はテキスト）
   └─emit─> EventBus.spell_cast_requested(tokens)   # tokens = [{word_id, case}, …]
                 │
            SpellEngine.cast(tokens, ruleset) ──> CastResult
                 │
   ┌─────────────┴───────────────┐
   ▼                             ▼
HUD/Composer に                Player/Enemy に
GrammarReport を可読表示        ResolvedEffect を適用
（失敗=学習フィードバック）       （ダメージ/回復/暴発）
                 │
            Lexicon.gain_comprehension(used_words, source="combat")
                 │
   CombatController: 詠唱コストを消費
     ・GameState のプレイヤーターンを終了（1詠唱＝1手番）
     ・GameState.advance_world_time(Δ)   # Δ=語数・語ティア依存（05 BalanceConfig）
                 │
            [敵手番] → 解決 → 次のプレイヤー手番へ
```

> MP は存在しない。連打抑制は **1詠唱＝1手番＋世界時間Δ** で表現（`01` 3.8 / `05`）。`CombatController` がこの消費の唯一の適用点（テスト容易性のため一箇所に集約）。

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
- **保存しない**: HP・到達階・装備・ループ一時状態（巻き戻る側＝`01` 3.6 の左列）。
- 巻き戻し（死亡/7日切れ/任意巻き戻し）時: `Lexicon.save()` → `GameState.reset()` の順。逆順厳禁（先に記憶を確定保存してから世界を戻す）。
- 任意巻き戻し（`01` 3.6 の損切り）：プレイヤー操作 → 同じ巻き戻し経路を通る（死亡時と同一処理。`öld renna aptr` 演出を表示）。
- セーブ運用方針（確定）：アーティファクトの記録点は**ループ境界**。ループ途中の任意地点セーブによる save-scum は不可（ローグライトの緊張を保つ）。中断再開は「同一ループの一時中断」として別途扱い、巻き戻し記録とは区別する。
- 必須テスト:
  - `test_rewind_preserves_lexicon`（巻き戻し後も理解度が一致＝記憶保持）
  - `test_gamestate_reset_clears_loop`（ループ状態が開始時へ）
  - `test_spell_engine_pure`（同一入力・同一 seed で決定的）
  - `test_fixed_incantation_bypasses_engine`（`öld renna aptr` がコア呪文パイプラインを通らず固定イベントとして処理される）

---

## 8. テスト方針（M1 を支える）

- 呪文エンジンはゲームプレイ非依存 → **単体テストを最優先整備**。
- `03` §5.5 の不変条件 T1〜T3 を自動テスト化:
  - T1: 理解度変化で期待威力不変
  - T2: 文法 full pass で暴発単調減少
  - T3: 強ティア未習語＝高期待威力/高分散/高暴発
- フレームワーク: GUT（Godot Unit Test）等を想定。M0 で導入。

---

## 9. 実装順序（マイルストーン対応）

| MS | 実装範囲 |
|----|----------|
| M0 | ディレクトリ・Autoload 雛形・データスキーマ・テスト基盤 |
| M1 | core/spell 一式 + `spell_lab.tscn`（戦闘なし）+ T1〜T3 テスト |
| M2 | actors + spell_composer + 1フロアプレイアブル |
| M3 | run/floor 生成 + タイムリミット + 死亡/踏破/周回 |
| M4 | Lexicon 永続 + 学習3経路 + 碑文モード |
| M5 | data/ 量産投入 + 言語監修反映 + バランス |
| M6 | UI/音/オンボーディング/配布 |

---

参照: 全体目標 → `01` / コア仕様 → `03` / データ → `05_データ定義テンプレート.md`
