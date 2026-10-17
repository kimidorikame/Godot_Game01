extends RefCounted
## 客の表示名（システム整理A・F1）の検証。表示名は data/customers/<id>.json の "name"。
## ScheduleData.customer_display_name(id) で引き、システムが組み立てる文面（結果画面の物語欄・
## 予告メモ）で使う。計器盤・STATE VIEWER・Ledgerはデバッグ／内部用なのでidのまま。

const REGULAR_NAMES := {
	"delivery_man": "配達員", "thug": "チンピラ", "granny": "老婆",
	"officer": "新人警官", "hooker": "夜の女", "streamer": "配信者",
}


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()

	# --- 1. 全常連の表示名が空でなく、idとは別の文字列（既存の仮の値のまま） ---
	for id in REGULAR_NAMES:
		var name := ScheduleData.customer_display_name(id)
		c.check("%s の表示名は空でなく、仮の値のまま" % id,
			name != "" and name != id and name == REGULAR_NAMES[id], name)
		c.check("%s のプロフィールに name がある" % id, ScheduleData.customer_profile(id).has("name"))

	# --- 2. 未知のid・nameの無いデータはid自体を返す（クラッシュしない） ---
	c.check("未知のidはid自体を返す", ScheduleData.customer_display_name("no_such_customer_xyz") == "no_such_customer_xyz")
	c.check("空文字はそのまま空文字", ScheduleData.customer_display_name("") == "")
	ScheduleData._customer_cache["name_less_test"] = { "is_mob": false, "favorite": "tofu", "wanted_tags": [] }
	ScheduleData._customer_cache["name_empty_test"] = { "name": "", "favorite": "tofu" }
	c.check("nameの無いプロフィールはid自体を返す", ScheduleData.customer_display_name("name_less_test") == "name_less_test")
	c.check("nameが空のプロフィールもid自体を返す", ScheduleData.customer_display_name("name_empty_test") == "name_empty_test")
	ScheduleData.clear_cache()

	# --- 3. 結果画面の物語欄：好物を知った客・来た常連が表示名で出て、idが残らない ---
	var summary := Result.summarize([], [], 0)
	summary["regular_visit_days"] = { "delivery_man": 2, "thug": 3, "granny": 1, "officer": 1, "hooker": 1, "streamer": 1 }
	var story := Result.format_story(summary, REGULAR_NAMES.keys())
	var leaked := []
	for id in REGULAR_NAMES:
		if story.contains(id):
			leaked.append(id)
	c.check("物語の欄にidが残らない", leaked.is_empty(), "%s / %s" % [str(leaked), story])
	var all_named := true
	for id in REGULAR_NAMES:
		all_named = all_named and story.contains(REGULAR_NAMES[id])
	c.check("物語の欄に6人全員の表示名が出る", all_named, story)
	c.check("来た常連は「表示名（N日）」の形", story.contains("チンピラ（3日）"), story)

	# --- 4. 予告メモ（朝の予報の文面）：名前あり客は表示名で出てidが残らない ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（今日のDayPlanができる）
	var memo: String = panel._format_tonight_memo()
	var memo_leaked := []
	for id in REGULAR_NAMES:
		if memo.contains(id):
			memo_leaked.append(id)
	c.check("予告メモにidが残らない", memo_leaked.is_empty(), "%s / %s" % [str(memo_leaked), memo])
	c.check("予告メモに今日の常連の表示名が出る（Day2：新人警官・配達員・チンピラ）",
		memo.contains("新人警官") and memo.contains("配達員") and memo.contains("チンピラ"), memo)

	GameState.reset_for_new_game()
	if is_instance_valid(panel):
		panel.free()
	return c.finish()
