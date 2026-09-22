extends RefCounted
## 日別スケジュールの汎用化（JSON外部化。CURRENT_SPEC.md §9-C）の検証。
## 実データ（Day1・Day2）の文言そのものは、リファクタ前後の出力を丸ごと比較する
## 一度きりの照合（実装時にのみ実施。膨大な会話文をここへ複製すると保守が難しくなる
## ため）で確認済み。ここでは仕組みそのもの（フォールバック・抽選プール・書式）を検証する。

func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. day_schedule() のフォールバック（Day3〜7はDay1へ） ---
	var day1 := ScheduleData.day_schedule(1)
	var day3 := ScheduleData.day_schedule(3)
	c.check("day_schedule(1)にslotsがある", day1.has("slots") and day1["slots"].size() == 3)
	c.check("day_schedule(3)はday_schedule(1)へフォールバック", day3 == day1, str(day3))
	var day2 := ScheduleData.day_schedule(2)
	c.check("day_schedule(2)は1枠だけ(客のいない時間帯は含めない)", day2["slots"].size() == 1)

	# --- 2. customer_data() のフォールバック（客データ自身も独立して1日目へ） ---
	GameState.reset_for_new_game()
	var thug1 := ScheduleData.customer_data("thug", 1)
	var thug3 := ScheduleData.customer_data("thug", 3)
	c.check("thugのfavorite/wanted_tagsが読める", thug1.get("favorite") == "meat_ball"
		and thug1.get("wanted_tags") == ["MELLOW", "GENTLE"] and thug1.get("servings") == 1)
	c.check("thugのDay3はDay1の会話へフォールバック", thug3 == thug1, str(thug3))
	c.check("thugの反応文が読める(GREAT)", str(thug1.get("reactions", {}).get("GREAT", [])).contains("肉団子"))
	var dm := ScheduleData.customer_data("delivery_man", 1)
	c.check("delivery_manは最小限(is_mob/favorite/wanted_tagsのみ)",
		dm.get("favorite") == "tofu" and dm.get("wanted_tags") == ["HOT", "POWER"]
		and not dm.has("greet") and not dm.has("reactions"))
	c.check("officerはDay2のデータを持つ", ScheduleData.customer_data("officer", 2).get("favorite") == "rice_noodle")
	c.check("存在しない客idは空辞書", ScheduleData.customer_data("no_such_customer_xyz", 1).is_empty())

	# --- 3. _pick_main(): 抽選プール・同日内重複禁止 ---
	var seen := {}
	for i in range(200):
		var picked: String = Day1Events._pick_main({"main_pool": ["a", "b", "c"]}, ["a"])
		seen[picked] = true
	c.check("抽選プール: 除外したidは選ばれない", not seen.has("a"), str(seen))
	c.check("抽選プール: 残りの候補から選ばれる", seen.has("b") and seen.has("c"))
	c.check("main指定はプールより優先", Day1Events._pick_main({"main": "granny", "main_pool": ["x"]}, []) == "granny")

	# --- 4. _pick_main(): プールが尽きた場合はクラッシュせず選び直す ---
	var exhausted: String = Day1Events._pick_main({"main_pool": ["a"]}, ["a"])
	c.check("プール枯渇時はプール全体から選び直す(クラッシュしない)", exhausted == "a")

	# --- 5/6. customer_schedule(): Day1夜半のモブ追加（意図した唯一の挙動変化） ---
	GameState.day_count = 1
	var sched_m4: Array = Day1Events.customer_schedule(4)
	var sched_m0: Array = Day1Events.customer_schedule(0)
	c.check("Day1: モブ4人なら夜半にdock_workersが増える",
		sched_m4[1]["customers"] == ["thug", "dock_workers"], str(sched_m4[1]))
	c.check("Day1: モブ0人なら夜半はチンピラだけ(既存どおり)",
		sched_m0[1]["customers"] == ["thug"], str(sched_m0[1]))
	c.check("Day1: 宵の口・明け方は従来どおり",
		sched_m4[0]["customers"] == ["delivery_man", "dock_workers"]
		and sched_m4[2]["customers"] == ["granny"])

	# --- 7. Day2: 短い配列(1枠)でも、3枠+空2つの旧表現と機能的に同じ客順になる ---
	GameState.day_count = 2
	var sched_day2: Array = Day1Events.customer_schedule(1)
	c.check("Day2: 1枠だけを返す(客のいない時間帯を含めない)", sched_day2.size() == 1)
	var open_new := OpenController.new(sched_day2)
	var open_old := OpenController.new([
		{ "name": "宵の口", "customers": ["officer", "dock_workers"] },
		{ "name": "夜半", "customers": [] },
		{ "name": "明け方", "customers": [] },
	])
	var seq_new := []
	var seq_old := []
	while open_new.has_more():
		seq_new.append(open_new.current_customer())
		open_new.advance_customer()
	while open_old.has_more():
		seq_old.append(open_old.current_customer())
		open_old.advance_customer()
	c.check("Day2: 新旧の枠表現でOpenControllerの客順が一致", seq_new == seq_old, "%s vs %s" % [seq_new, seq_old])
	c.check("Day2: 両方ともopen_doneになる", open_new.is_open_done() and open_old.is_open_done())

	# --- 8. is_mob_customer() ---
	c.check("dock_workersはモブ", Day1Events.is_mob_customer("dock_workers"))
	c.check("delivery_man/thug/granny/officerはモブでない",
		not Day1Events.is_mob_customer("delivery_man") and not Day1Events.is_mob_customer("thug")
		and not Day1Events.is_mob_customer("granny") and not Day1Events.is_mob_customer("officer"))

	# --- 9. dock_workersのgreet: "%d"を含む行だけ埋め込み、含まない行はそのまま ---
	var flavor4: Dictionary = Day1Events._customer_flavor("dock_workers", 4)
	c.check("1行目に人数が入る", str(flavor4["greet"][0]).contains("4人"))
	c.check("2行目に人数が入る", str(flavor4["greet"][1]).contains("4つ頼む"))
	c.check("3行目(%dを含まない台詞)はそのまま", flavor4["greet"][2] == "労働者「辛いのを、力の出るやつで。景気づけだ」")
	c.check("dock_workersはfavoriteを持たない", flavor4.get("favorite", "?") == "")
	c.check("servingsはmob_countそのもの", flavor4["servings"] == 4)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
