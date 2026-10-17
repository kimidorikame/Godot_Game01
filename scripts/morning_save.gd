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
const VERSION := 5

## state の各項目の型（is_valid用）。GameState.SAVED_FIELDS と同じ項目を持つ。
const _FIELD_TYPES := {
	"day_count": TYPE_INT, "money": TYPE_INT, "reputation": TYPE_INT,
	"inventory": TYPE_DICTIONARY, "perishable_batches": TYPE_DICTIONARY,
	"rumors": TYPE_ARRAY, "dashi_units": TYPE_INT,
	"ledger": TYPE_ARRAY, "today_plan": TYPE_DICTIONARY, "day_records": TYPE_ARRAY,
	"customer_memory": TYPE_DICTIONARY,
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
	for rec in state["day_records"]:
		if not (rec is Dictionary) or typeof((rec as Dictionary).get("day")) != TYPE_INT:
			return false
	var plan: Dictionary = state["today_plan"]
	if typeof(plan.get("day")) != TYPE_INT or typeof(plan.get("demand_center")) != TYPE_INT \
			or typeof(plan.get("slots")) != TYPE_ARRAY \
			or typeof(plan.get("mob_instances")) != TYPE_DICTIONARY:
		return false
	# 版3（4-4a）：各枠は name・customers・regular_id・episode_id を持つ（会話を引く元）。
	# 版5（4-4b-2）：today_request（今日の頼み。辞書。無ければ空）も持つ。
	for slot in plan["slots"]:
		if not (slot is Dictionary):
			return false
		var sd: Dictionary = slot
		if typeof(sd.get("name")) != TYPE_STRING or typeof(sd.get("customers")) != TYPE_ARRAY \
				or typeof(sd.get("regular_id")) != TYPE_STRING \
				or typeof(sd.get("episode_id")) != TYPE_STRING \
				or typeof(sd.get("today_request")) != TYPE_DICTIONARY:
			return false
	# 版4（4-4b-1）：来店記録。各客は favorite_known(bool)・visits・seen_episodes(配列)・facts(辞書)。
	var memory: Dictionary = state["customer_memory"]
	for id in memory:
		var entry = memory[id]
		if typeof(id) != TYPE_STRING or not (entry is Dictionary):
			return false
		var e: Dictionary = entry
		if typeof(e.get("favorite_known")) != TYPE_BOOL or typeof(e.get("visits")) != TYPE_ARRAY \
				or typeof(e.get("seen_episodes")) != TYPE_ARRAY or typeof(e.get("facts")) != TYPE_DICTIONARY:
			return false
		for visit in e["visits"]:
			if not (visit is Dictionary):
				return false
			var v: Dictionary = visit
			if typeof(v.get("day")) != TYPE_INT or typeof(v.get("served")) != TYPE_INT \
					or typeof(v.get("slot")) != TYPE_STRING or typeof(v.get("grade")) != TYPE_STRING \
					or typeof(v.get("episode_id")) != TYPE_STRING or typeof(v.get("grades")) != TYPE_ARRAY \
					or typeof(v.get("ingredients")) != TYPE_ARRAY:
				return false
		for eid in e["seen_episodes"]:
			if typeof(eid) != TYPE_STRING:
				return false
	var panel = env.get("panel")
	if not (panel is Dictionary) or typeof((panel as Dictionary).get("day_summary_text")) != TYPE_STRING:
		return false
	return true


## 封筒の state を GameState へ戻す（is_valid()を通した封筒だけを渡すこと）。
## 画面側の状態（panel）は呼び出し側が戻す。
static func apply(envelope: Dictionary) -> void:
	GameState.from_dict(envelope["state"])


# --- 1枠セーブ（フェーズ4-1コミット②。DESIGN.md 10.6） ---
# 朝の封筒（capture()の辞書）を1ファイルに書く。朝だけ（調理中・会話途中は保存しない）。
# 形式：先頭にマジック文字列（別ファイルを読んだとき、engineのエラーを出さずに弾くため）＋
# var_to_bytes（型を保つ。JSONだと整数がfloatになり整数キーが文字列になる）。読み込みは
# bytes_to_var（Objectは復元しない＝外部ファイルから任意のObjectを組み立てさせない）。
# 保存先はプロジェクト全体で1箇所。テストは差し替える（tests/run_tests.gd・save_file_test.gd）。
static var save_path := "user://save.dat"
const _MAGIC := "YORUYUSAVE1"


static func has_file() -> bool:
	return FileAccess.file_exists(save_path)


## 封筒を書く。is_valid()でない封筒は書かない。一時ファイルへ書いてから置き換える
## （書き込み途中で終了しても、前のセーブが壊れない）。成功したらtrue。
static func write_file(envelope: Dictionary) -> bool:
	if not is_valid(envelope):
		return false
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(_MAGIC.to_ascii_buffer())
	f.store_buffer(var_to_bytes(envelope))
	f.close()
	var from_abs := ProjectSettings.globalize_path(tmp)
	var to_abs := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(to_abs)
	return DirAccess.rename_absolute(from_abs, to_abs) == OK


## セーブを読む。無い・読めない・壊れている・版やキャンペーンが違うときは空の辞書
## （呼び出し側は新規ゲームとして続ける。ファイルは消さない）。例外は出さない。
static func read_file() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var bytes := FileAccess.get_file_as_bytes(save_path)
	var magic := _MAGIC.to_ascii_buffer()
	if bytes.size() <= magic.size() or bytes.slice(0, magic.size()) != magic:
		return {}
	var value = bytes_to_var(bytes.slice(magic.size()))
	if value is Dictionary and is_valid(value):
		return value
	return {}


static func delete_file() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
