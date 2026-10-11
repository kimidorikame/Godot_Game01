extends RefCounted
class_name MorningSave
## 朝の保存（F7・DESIGN.md 10.8.7）。WAKEで運営費を引く前の状態（GameState.to_dict()）と、
## 画面側の最小限の付随情報を「封筒」の辞書にまとめ、検証し、戻す入口。
##
## 同じ朝からの再挑戦（フェーズ4-1）・結果画面の再挑戦（4-2）・1枠セーブ（4-1コミット②）が
## 同じ封筒を使う。封筒をどこへ置くか（メモリ上＝GameState.morning_snapshots、ファイル）は
## 呼び出し側で決め、ここは形と検証だけを持つ（状態は持たない静的クラス）。
##
## 抽選は再現ではなく「保存した today_plan をそのまま戻す」方式（DESIGN.md 10.8.7）。
## 戻しても DayPlanner.build() は呼ばれない（呼ぶのは WAKE 側が判断する。debug_panel.gd）。
## 反応文の2択（OpenController の reaction_variant）は抽選ではなく演出の乱数で、
## 再挑戦では変わりうる（客・需要・組は変わらない）。

## 封筒の版。形を変えたら上げる（古い版のファイルはis_valid()で弾いて新規ゲームにする）。
const VERSION := 1

## state の各項目の型（is_valid用）。GameState.SAVED_FIELDS と同じ項目を持つ。
const _FIELD_TYPES := {
	"day_count": TYPE_INT, "money": TYPE_INT, "reputation": TYPE_INT,
	"inventory": TYPE_DICTIONARY, "perishable_batches": TYPE_DICTIONARY,
	"rumors": TYPE_ARRAY, "dashi_units": TYPE_INT, "known_favorites": TYPE_DICTIONARY,
	"ledger": TYPE_ARRAY, "today_plan": TYPE_DICTIONARY,
}


## いまのGameStateから封筒を作る。day_summary_textは画面側（DebugPanel）が朝の先頭で
## 一度だけ見せる前日成績の一言（保存しておけば、戻った朝にも同じ文を見せられる）。
static func capture(day_summary_text: String = "") -> Dictionary:
	return {
		"version": VERSION,
		"campaign": Rules.campaign_id(),
		"day": GameState.day_count,
		"state": GameState.to_dict(),
		"panel": { "day_summary_text": day_summary_text },
	}


## 封筒の形・型を確かめる（外部ファイル・古い版・別キャンペーンを弾く）。例外は出さない。
## 深さは「戻したときに他の処理が型で落ちない」ところまで：保存項目の型、在庫の個数、
## 帳簿の各行、DayPlanの形。
static func is_valid(envelope) -> bool:
	if not (envelope is Dictionary):
		return false
	var env: Dictionary = envelope
	if typeof(env.get("version")) != TYPE_INT or int(env["version"]) != VERSION:
		return false
	if typeof(env.get("campaign")) != TYPE_STRING or str(env["campaign"]) != Rules.campaign_id():
		return false
	if typeof(env.get("day")) != TYPE_INT or int(env["day"]) < 1:
		return false
	var state = env.get("state")
	if not (state is Dictionary):
		return false
	for field in _FIELD_TYPES:
		if not (state as Dictionary).has(field) \
				or typeof(state[field]) != int(_FIELD_TYPES[field]):
			return false
	if int(state["day_count"]) != int(env["day"]):
		return false
	for id in state["inventory"]:
		if typeof(id) != TYPE_STRING or typeof(state["inventory"][id]) != TYPE_INT:
			return false
	for row in state["ledger"]:
		if not (row is Dictionary):
			return false
		for key in ["day", "amount"]:
			if typeof((row as Dictionary).get(key)) != TYPE_INT:
				return false
	var plan: Dictionary = state["today_plan"]
	if typeof(plan.get("day")) != TYPE_INT or typeof(plan.get("demand_center")) != TYPE_INT \
			or typeof(plan.get("slots")) != TYPE_ARRAY \
			or typeof(plan.get("mob_instances")) != TYPE_DICTIONARY:
		return false
	var panel = env.get("panel")
	if not (panel is Dictionary) or typeof((panel as Dictionary).get("day_summary_text")) != TYPE_STRING:
		return false
	return true


## 封筒の state を GameState へ戻す（is_valid()を通した封筒だけを渡すこと）。
## 画面側の状態（panel）は呼び出し側が戻す。
static func apply(envelope: Dictionary) -> void:
	GameState.from_dict(envelope["state"])
