extends RefCounted
class_name CombatSystem
## CombatSystem — INC-2 の戦闘状態機械（最小）。
##
## 役割: Player ↔ Enemy[] の HP・ターン・進行（雑魚→ボス→クリア／敗北）を管理する。
##       詠唱結果 (CastResult) を受け取って DamageCalculator に流し、結果を state に反映、
##       シグナルで scene 層 (combat_test.tscn) に通知する。
## 出典: 08 §1.2 / 01 §3.8 / `02` §3 INC-2。
##
## 不変条件:
##   - is_over() == true の時、apply_cast()/enemy_turn() は NOP。
##   - 現在敵は enemies[current_enemy_index]。倒れたら index を進める。
##   - 全敵撃破で state = FLOOR_CLEAR、player.hp==0 で state = DEFEAT。
##   - ターン数と世界時間 Δ は単調増加。

enum State { PLAYER_TURN, ENEMY_TURN, FLOOR_CLEAR, DEFEAT }

# --- シグナル（scene 層が購読） ---
signal turn_changed(new_state: int)
signal damage_dealt(target_name: String, amount: float)
signal heal_dealt(target_name: String, amount: float)
signal enemy_defeated(index: int, name: String)
signal floor_cleared()
signal player_defeated()
signal cast_logged(entry: Dictionary)

# --- 状態 ---
var player: Combatant = null
var enemies: Array = []  # Array[Combatant]、index 0 から順に登場
var current_enemy_index: int = 0
var state: int = State.PLAYER_TURN
var turn_count: int = 0
var world_time_delta_total: float = 0.0

# 直近 N 件の詠唱ログ（UI 表示用）。
var cast_log: Array = []
const CAST_LOG_MAX := 16

# 敵 AI の固定ダメージ（INC-2 v0.1 は最小: 雑魚=8、ボス=15）。
# enemies の index と同じ位置にダメージ値を入れる。
var enemy_attack_damage: Array = []


func start_floor(p_player: Combatant, p_enemies: Array, p_attack_damage: Array = []) -> void:
	player = p_player
	enemies = p_enemies.duplicate()
	enemy_attack_damage = p_attack_damage.duplicate() if not p_attack_damage.is_empty() else []
	# デフォルト攻撃力: 雑魚 8 / ボス 15（enemies.size() に応じて補完）
	while enemy_attack_damage.size() < enemies.size():
		var idx := enemy_attack_damage.size()
		enemy_attack_damage.append(15.0 if idx == enemies.size() - 1 else 8.0)
	current_enemy_index = 0
	state = State.PLAYER_TURN
	turn_count = 1
	world_time_delta_total = 0.0
	cast_log.clear()
	turn_changed.emit(state)


func current_enemy() -> Combatant:
	if current_enemy_index < 0 or current_enemy_index >= enemies.size():
		return null
	return enemies[current_enemy_index]


func is_over() -> bool:
	return state == State.FLOOR_CLEAR or state == State.DEFEAT


## プレイヤーが詠唱した結果を適用する。
##   cast_result: SpellEngine.cast() の戻り値
##   token_count, tier_sum: 世界時間 Δ 計算用（spell_builder 側で取得済み）
## 戻り値: ダメージ計算と適用後の情報（UI 表示用）
##   {
##     "to_target": float, "to_self": float, "delta": float,
##     "log_summary": String, "enemy_killed": bool, "floor_cleared": bool,
##   }
func apply_cast(cast_result: CastResult, token_count: int, tier_sum: int) -> Dictionary:
	var info := {
		"to_target": 0.0,
		"to_self": 0.0,
		"delta": 0.0,
		"log_summary": "",
		"enemy_killed": false,
		"floor_cleared": false,
		"player_defeated": false,
	}
	if is_over() or state != State.PLAYER_TURN:
		info["log_summary"] = "(プレイヤーターンではない)"
		return info

	var enemy := current_enemy()
	if enemy == null:
		info["log_summary"] = "(対象なし)"
		return info

	# Δ 累積
	var delta := DamageCalculator.compute_world_time_delta(token_count, tier_sum)
	world_time_delta_total += delta
	info["delta"] = delta

	# ダメージ計算
	var calc := DamageCalculator.compute(cast_result.resolved, enemy)
	info["to_target"] = calc["to_target"]
	info["to_self"] = calc["to_self"]
	info["log_summary"] = calc["log_summary"]

	# 敵への適用（負値 = effect_reversal は heal 解釈）
	var dmg_to_enemy: float = calc["to_target"]
	if dmg_to_enemy > 0.0:
		var applied := enemy.take_damage(dmg_to_enemy)
		damage_dealt.emit(enemy.display_name, applied)
	elif dmg_to_enemy < 0.0:
		var healed := enemy.heal(-dmg_to_enemy)
		heal_dealt.emit(enemy.display_name, healed)

	# 自分への適用（self_damage / sjalfr）
	if calc["to_self"] > 0.0 and player != null:
		var applied_self := player.take_damage(calc["to_self"])
		damage_dealt.emit(player.display_name, applied_self)

	# ログ記録
	var entry := {
		"turn": turn_count,
		"summary": info["log_summary"],
		"delta": delta,
	}
	cast_log.append(entry)
	while cast_log.size() > CAST_LOG_MAX:
		cast_log.pop_front()
	cast_logged.emit(entry)

	# 撃破/敗北判定
	if not enemy.is_alive():
		info["enemy_killed"] = true
		enemy_defeated.emit(current_enemy_index, enemy.display_name)
		current_enemy_index += 1
		if current_enemy_index >= enemies.size():
			state = State.FLOOR_CLEAR
			info["floor_cleared"] = true
			floor_cleared.emit()
			turn_changed.emit(state)
			return info

	if player != null and not player.is_alive():
		state = State.DEFEAT
		info["player_defeated"] = true
		player_defeated.emit()
		turn_changed.emit(state)
		return info

	# 敵ターンへ
	state = State.ENEMY_TURN
	turn_changed.emit(state)
	return info


## 敵ターン処理。固定 AI で player.hp を削る。
## 戻り値: { "damage": float, "attacker_name": String, "player_defeated": bool }
func enemy_turn() -> Dictionary:
	var info := {
		"damage": 0.0,
		"attacker_name": "",
		"player_defeated": false,
	}
	if is_over() or state != State.ENEMY_TURN:
		return info

	var enemy := current_enemy()
	if enemy == null or not enemy.is_alive():
		# 全滅済み（apply_cast 内で処理済みのはずだが防御的に）
		state = State.PLAYER_TURN
		turn_count += 1
		turn_changed.emit(state)
		return info

	var dmg: float = 0.0
	if current_enemy_index < enemy_attack_damage.size():
		dmg = float(enemy_attack_damage[current_enemy_index])
	info["damage"] = dmg
	info["attacker_name"] = enemy.display_name

	if dmg > 0.0 and player != null:
		var applied := player.take_damage(dmg)
		damage_dealt.emit(player.display_name, applied)
		if not player.is_alive():
			state = State.DEFEAT
			info["player_defeated"] = true
			player_defeated.emit()
			turn_changed.emit(state)
			return info

	# プレイヤーターンへ
	state = State.PLAYER_TURN
	turn_count += 1
	turn_changed.emit(state)
	return info


## デバッグ/テスト用: 現在の戦況をまとめて辞書で取り出す。
func snapshot() -> Dictionary:
	var enemy_list: Array = []
	for e in enemies:
		var c: Combatant = e
		enemy_list.append({
			"name": c.display_name,
			"hp": c.hp,
			"max_hp": c.max_hp,
			"alive": c.is_alive(),
		})
	return {
		"state": state,
		"turn": turn_count,
		"world_time_delta_total": world_time_delta_total,
		"player": null if player == null else {
			"name": player.display_name,
			"hp": player.hp,
			"max_hp": player.max_hp,
			"alive": player.is_alive(),
		},
		"enemies": enemy_list,
		"current_enemy_index": current_enemy_index,
	}
