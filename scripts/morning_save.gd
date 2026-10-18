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
## 版6（4-7①）：保存レシピ（saved_recipes）を足した。版5以前は読めない（新規ゲームにする）。
const VERSION := 6

## state の各項目の型（is_valid用）。GameState.SAVED_FIELDS と同じ項目を持つ。
const _FIELD_TYPES := {
	"day_count": TYPE_INT, "money": TYPE_INT, "reputation": TYPE_INT,
	"inventory": TYPE_DICTIONARY, "perishable_batches": TYPE_DICTIONARY,
	"rumors": TYPE_ARRAY, "dashi_units": TYPE_INT,
	"ledger": TYPE_ARRAY, "today_plan": TYPE_DICTIONARY, "day_records": TYPE_ARRAY,
	"customer_memory": TYPE_DICTIONARY, "saved_recipes": TYPE_ARRAY,
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
			# 任意キー（システム整理C2。旧形式の来店記録には無いので、あるときだけ型を検査する。
			# 保存の版は上げない）：choices＝{選択id: 選択肢id}、request_honored＝bool。
			if v.has("choices"):
				if typeof(v["choices"]) != TYPE_DICTIONARY:
					return false
				for choice_id in v["choices"]:
					if typeof(choice_id) != TYPE_STRING or typeof(v["choices"][choice_id]) != TYPE_STRING:
						return false
			if v.has("request_honored") and typeof(v["request_honored"]) != TYPE_BOOL:
				return false
		for eid in e["seen_episodes"]:
			if typeof(eid) != TYPE_STRING:
				return false
	# 版6（4-7①）：保存レシピは枠数以内で、各要素は name（文字列）と ingredients（1〜3個の文字列）。
	var recipes: Array = state["saved_recipes"]
	if recipes.size() > Rules.recipe_slots():
		return false
	for recipe in recipes:
		if not RecipeBook.is_valid_recipe(recipe):
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


## セーブがあるか：本体・.bak・.tmp のどれかがあれば true（置換の途中で落ちても「続きから」を出す）。
## 読めるかどうかは read_file() で決まる（.tmp が書きかけなら読めずに空になる）。
static func has_file() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_bak_path()) \
			or FileAccess.file_exists(_tmp_path())


static func _tmp_path() -> String:
	return save_path + ".tmp"


static func _bak_path() -> String:
	return save_path + ".bak"


## テスト専用：true の間、write_file の「.tmp→本体」への置換だけを失敗させる（旧版の復元を確かめる）。
static var fail_install_for_test := false


## 封筒を書く。is_valid()でない封筒は書かない。置換は次の順で行い、どの時点で落ちても
## 本体・.tmp・.bak のどれかに有効なセーブが残る（read_file() がその順に拾う）：
##   1. 一時ファイル（.tmp）へ書き、読み戻して検証する
##   2. 本体があれば .bak へ rename する（古い .bak は先に消す）
##   3. .tmp を本体へ rename する（失敗したら .bak を本体へ戻す）
##   4. 成功したら .bak を消す
## 成功したらtrue。
static func write_file(envelope: Dictionary) -> bool:
	if not is_valid(envelope):
		return false
	var tmp := _tmp_path()
	var bak := _bak_path()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(_MAGIC.to_ascii_buffer())
	f.store_buffer(var_to_bytes(envelope))
	f.close()
	if _read_valid(tmp).is_empty():
		_remove(tmp)   # 書き込みが途中で切れた（容量不足など）。本体には触れない
		return false
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	var main_abs := ProjectSettings.globalize_path(save_path)
	var bak_abs := ProjectSettings.globalize_path(bak)
	var had_main := FileAccess.file_exists(save_path)
	if had_main:
		_remove(bak)
		if DirAccess.rename_absolute(main_abs, bak_abs) != OK:
			_remove(tmp)
			return false   # 本体は動いていない
	var installed := not fail_install_for_test and DirAccess.rename_absolute(tmp_abs, main_abs) == OK
	if not installed:
		if had_main:
			DirAccess.rename_absolute(bak_abs, main_abs)   # 旧版を戻す
		_remove(tmp)
		return false
	_remove(bak)
	return true


## セーブを読む。順序は 本体 → .tmp → .bak。置換の最中に落ちると「本体なし・.tmp が新版・
## .bak が旧版」になるので、.tmp を .bak より先に読む（is_valid を通った .tmp だけ採用。
## 書きかけの .tmp は弾く）。どれも無い・読めない・壊れている・版やキャンペーンが違うときは
## 空の辞書（呼び出し側は新規ゲームとして続ける。ファイルは消さない）。例外は出さない。
static func read_file() -> Dictionary:
	for path in [save_path, _tmp_path(), _bak_path()]:
		var env := _read_valid(path)
		if not env.is_empty():
			return env
	return {}


## 1ファイルを読み、マジックと is_valid() を通ったときだけ封筒を返す（それ以外は空）。
static func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var bytes := FileAccess.get_file_as_bytes(path)
	var magic := _MAGIC.to_ascii_buffer()
	if bytes.size() <= magic.size() or bytes.slice(0, magic.size()) != magic:
		return {}
	var value = bytes_to_var(bytes.slice(magic.size()))
	if value is Dictionary and is_valid(value):
		return value
	return {}


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 本体・.bak・.tmp をすべて消す。
static func delete_file() -> void:
	_remove(save_path)
	_remove(_bak_path())
	_remove(_tmp_path())
