extends Resource
class_name CastResult
## CastResult — 呪文1詠唱の総合結果（SpellEngine.cast() の戻り値）。
##
## 役割: GrammarReport + EffectSpec + ResolvedEffect + debug の集約。
## 出典: 04 §4。
##
## INC-0: 空シェル。子モデルは null 可能（INC-1 で全て埋まる）。

## 文法判定の結果（UI フィードバック源）。
@export var grammar_report: GrammarReport = null

## 評価された効果（制御精度適用前、P_base 等）。
@export var effect_spec: EffectSpec = null

## 制御精度適用後の最終効果（暴発/ばらつき確定）。
@export var resolved: ResolvedEffect = null

## 対象タイル集合（INC-3 v0.9 新規）。null = 後方互換（spell_lab/combat_test 等の位置なし詠唱）。
## INC-3 ではタイル指定なし=最隣接敵自動。INC-3.5 で範囲語・方向語の本格解釈。
@export var target_set: TargetSet = null

## デバッグ可視化用（spell_lab の表示源）。
##   形（例）: { "C": 50.0, "G": 0.85, "control": 0.62,
##              "misfire_chance": 0.05,
##              "seed": 12345 }
@export var debug: Dictionary = {}


## 呪文が成功したか（文法 OK＋暴発なし）。spell_lab/UI から呼ぶ簡易判定。
func is_successful() -> bool:
	if grammar_report != null and not grammar_report.overall_pass:
		return false
	if resolved != null and resolved.misfired:
		return false
	return true
