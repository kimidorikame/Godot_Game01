extends RefCounted
## 日別スケジュールの汎用化（JSON外部化。CURRENT_SPEC.md §9-C）と、
## Day2-7ダミーデータ・モブの枠ごと独立抽選の検証。
## 実データ（Day1・Day2の非モブ客）の文言そのものは、コミット時点の値と比較して確認する
## （膨大な会話文をここへ複製すると保守が難しくなるため）。ここでは仕組みそのもの
## （フォールバック・抽選プール・モブの独立抽選・書式）を検証する。

func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 日程（4-4a：regular_slots／mob_rule_for。旧day_scheduleと"1"へのフォールバックは撤去） ---
	var day1 := ScheduleData.regular_slots(1)
	c.check("regular_slots(1)は3枠", day1.size() == 3)
	c.check("日程の無い日（Day8）は枠が空（Day1へのフォールバックはしない）",
		ScheduleData.regular_slots(8).is_empty())
	for d in range(1, 8):
		var ds := ScheduleData.regular_slots(d)
		var complete := ds.size() == 3
		for slot in ds:
			if str(slot.get("regular", "")) == "" or str(slot.get("episode_id", "")) == "":
				complete = false
		c.check("regular_slots(%d)は3枠で、各枠が常連・場面idを持つ" % d, complete)
	c.check("Day2は3枠（宵の口・夜半・明け方）", ScheduleData.regular_slots(2).size() == 3)

	# --- 2. 客のプロフィールと来店場面（日番号キーを持たない） ---
	# 会話文は調整中のためプレースホルダー（名前＋要求タグ／結果ラベルのみ）。ここでは
	# 実際の文言ではなく、構造（favorite/wanted_tags/servings）だけを見る。
	GameState.reset_for_new_game()
	var thug := ScheduleData.customer_profile("thug")
	var thug_ep := ScheduleData.episode_data("thug", "thug_01")
	c.check("thugのfavorite/wanted_tagsが読める（プロフィール）",
		thug.get("favorite") == "meat_ball" and thug.get("wanted_tags") == ["MELLOW", "GENTLE"])
	c.check("thugの場面にservings・反応文のGREATキーがある",
		int(thug_ep.get("servings", 0)) == 1 and thug_ep.get("reactions", {}).has("GREAT"))
	c.check("プロフィールにdays（日番号キー）が無い", not thug.has("days"))
	var dm := ScheduleData.customer_profile("delivery_man")
	c.check("delivery_manのfavorite/wanted_tags（プロフィール）",
		dm.get("favorite") == "tofu" and dm.get("wanted_tags") == ["HOT", "POWER"])
	var dm2 := ScheduleData.episode_data("delivery_man", "delivery_man_02")
	c.check("delivery_manの2回目以降の場面は通常フローのデータ(greet/reactions/servings)を持つ",
		not dm2.get("greet", []).is_empty() and dm2.get("servings") == 1
		and dm2.get("reactions", {}).has("GREAT"))
	c.check("officerのプロフィール（favoriteは実データのまま）",
		ScheduleData.customer_profile("officer").get("favorite") == "rice_noodle")
	for n in range(1, 5):
		c.check("officerの場面officer_%02dが読める" % n,
			not ScheduleData.episode_data("officer", "officer_%02d" % n).get("greet", []).is_empty())
	for n in range(1, 4):
		c.check("hookerの場面hooker_%02dが読める" % n,
			not ScheduleData.episode_data("hooker", "hooker_%02d" % n).get("greet", []).is_empty())
		c.check("streamerの場面streamer_%02dが読める" % n,
			not ScheduleData.episode_data("streamer", "streamer_%02d" % n).get("greet", []).is_empty())
	c.check("存在しない客idは空辞書", ScheduleData.customer_profile("no_such_customer_xyz").is_empty())

	# --- 3. （4-4aで撤去）_pick_main()のmain_pool抽選は、データでは使わないため関数ごと削除した ---

	# --- 4. _pick_mob(): 型と人数を独立して決める（新設） ---
	var mob_seen := {}
	for i in range(300):
		var mob: Dictionary = Day1Events._pick_mob({"mob": {"pool": ["a", "b", "c", "d"]}}, -1)
		mob_seen[mob["type"]] = true
	c.check("モブ抽選プール: 4種すべて出うる(重複除外なし)", mob_seen.size() == 4, str(mob_seen))
	c.check("mob:trueは常にdock_workers", Day1Events._pick_mob({"mob": true}, 3) == {"type": "dock_workers", "count": 3})
	c.check("mob:falseはモブなし", Day1Events._pick_mob({"mob": false}, 3).is_empty())
	c.check("mob無指定もモブなし", Day1Events._pick_mob({}, 3).is_empty())
	c.check("デバッグ上書きの人数がそのまま入る", Day1Events._pick_mob({"mob": {"pool": ["a"]}}, 2)["count"] == 2)
	# ④評判の更新+⑤客数の決め方：_pick_mob()の自動フォールバック(debug_count<0)は
	# customer_schedule()からDay1でしか呼ばれなくなったため、GameState.DAY1_MOB_COUNT
	# （評判に関わらず常に4）を返す。評判→モブ杯数の抽選はtotal_demand_today()側へ
	# 移った（tests/reputation_demand_test.gdで検証）。
	c.check("_pick_mobの自動フォールバックはDAY1_MOB_COUNTを返す(評判に関わらず)",
		Day1Events._pick_mob({"mob": {"pool": ["a"]}}, -1)["count"] == GameState.DAY1_MOB_COUNT)
	GameState.reset_for_new_game()

	# --- 5. customer_schedule(): Day1の並び（宵の口=delivery_man固定+dock_workers固定、
	#        夜半=thug固定+プール抽選モブ、明け方=granny固定・モブなし） ---
	GameState.day_count = 1
	var sched_day1: Array = Day1Events.customer_schedule(4)
	c.check("Day1宵の口: 配達員+dock_workers(mob:true固定)",
		sched_day1[0]["customers"].size() == 2 and sched_day1[0]["customers"][0] == "delivery_man",
		str(sched_day1[0]))
	c.check("Day1夜半: チンピラ+モブのインスタンスid",
		sched_day1[1]["customers"].size() == 2 and sched_day1[1]["customers"][0] == "thug"
		and str(sched_day1[1]["customers"][1]).begins_with("mob#"), str(sched_day1[1]))
	c.check("Day1明け方: 老婆のみ(モブなし)", sched_day1[2]["customers"] == ["granny"])
	var sched_day1_m0: Array = Day1Events.customer_schedule(0)
	c.check("Day1: モブ人数を0で上書きすると全枠モブなし",
		sched_day1_m0[0]["customers"] == ["delivery_man"] and sched_day1_m0[1]["customers"] == ["thug"])

	# --- 6. 3-5（DESIGN.md 10.3.3・10.9）：デバッグ上書きが無いDay1（自動）は
	#        Rules.day_overrides(1).mobsに固定された編成になり、抽選ではなくなった
	#        （以前はday_schedule.jsonの生のmob:{"pool":[...]}を独立抽選していたが、
	#        F1 day_overrides.mobsが優先されるようになったため）。 ---
	var types_at_night := {}
	for i in range(20):
		Day1Events.customer_schedule(-1)
		var night_id: String = "mob#1"   # Day1は宵の口(mob#0)→夜半(mob#1)の順
		if GameState.today_plan["mob_instances"].has(night_id):
			types_at_night[GameState.today_plan["mob_instances"][night_id]["type"]] = true
	c.check("Day1夜半のモブ種類は安宿の夜勤受付(inn_clerk)に固定される(抽選ではない)",
		types_at_night.keys() == ["inn_clerk"], str(types_at_night))
	c.check("Day1夜半のモブ人数は2(day_overrides.mobs固定)",
		int(GameState.today_plan["mob_instances"]["mob#1"]["count"]) == 2)
	c.check("Day1宵の口のモブは港湾労働者(dock_workers)に固定される",
		GameState.today_plan["mob_instances"].get("mob#0", {}).get("type", "") == "dock_workers")
	c.check("Day1宵の口のモブ人数は2(day_overrides.mobs固定)",
		int(GameState.today_plan["mob_instances"]["mob#0"]["count"]) == 2)

	# --- 7. デバッグ上書き: 全モブ枠の人数が揃う（種類は揃わなくてよい） ---
	GameState.day_count = 2
	var counts := {}
	var types2 := {}
	for i in range(50):
		Day1Events.customer_schedule(2)
		for id in GameState.today_plan["mob_instances"]:
			var inst: Dictionary = GameState.today_plan["mob_instances"][id]
			counts[int(inst["count"])] = true
			types2[str(inst["type"])] = true
	c.check("デバッグ上書き時は全モブ枠の人数が2で揃う", counts.keys() == [2], str(counts))
	c.check("デバッグ上書き中も種類はばらつく", types2.size() > 1, str(types2))

	# --- 8. Day2: 3枠すべてが埋まる（夜半・明け方が復活） ---
	GameState.day_count = 2
	var sched_day2: Array = Day1Events.customer_schedule(3)
	c.check("Day2: 3枠とも客がいる", sched_day2.size() == 3
		and not sched_day2[0]["customers"].is_empty()
		and not sched_day2[1]["customers"].is_empty()
		and not sched_day2[2]["customers"].is_empty(), str(sched_day2))
	c.check("Day2宵の口はofficer固定", sched_day2[0]["customers"][0] == "officer")
	# 4-3：常連は抽選ではなく固定日程（10.5.1）。旧「granny/thug/delivery_manのいずれか」
	# （main_poolの抽選）は、Day2夜半＝delivery_man・明け方＝thug の固定に置き換わった。
	c.check("Day2夜半はdelivery_man・明け方はthug（固定日程。抽選ではない）",
		sched_day2[1]["customers"][0] == "delivery_man" and sched_day2[2]["customers"][0] == "thug",
		str(sched_day2))

	# --- 9. is_mob_customer() / customer_events(): インスタンスidを正しく解決する ---
	GameState.day_count = 1
	var sched: Array = Day1Events.customer_schedule(4)
	var night_mob_id2: String = sched[1]["customers"][1]
	c.check("モブのインスタンスidはis_mob_customerでtrue", Day1Events.is_mob_customer(night_mob_id2))
	c.check("非モブ(thug)はis_mob_customerでfalse", not Day1Events.is_mob_customer("thug"))
	var mob_flavor: Dictionary = Day1Events._customer_flavor(night_mob_id2)
	c.check("モブのflavorはfavoriteを持たない", mob_flavor.get("favorite", "?") == "")
	c.check("モブのservingsはインスタンスの人数と一致",
		mob_flavor["servings"] == GameState.today_plan["mob_instances"][night_mob_id2]["count"])
	var mob_events: Array = Day1Events.customer_events(night_mob_id2)
	var greet_types := []
	for e in mob_events:
		if e["type"] == "GREET":
			greet_types.append(e["text"])
	c.check("customer_events()がモブの会話を組み立てる", not greet_types.is_empty(), str(mob_events))

	# --- 10. _format_mob_greet(): "%d"を含む行だけ埋め込み、含まない行はそのまま ---
	# 実ファイル（mobs/*.json）の行数・文言に依存させず、関数を直接値で検証する
	# （会話文は調整中で行数・内容が変わりうるため）。
	c.check("%dを含む行は人数が埋め込まれる", Day1Events._format_mob_greet("%d人", 4) == "4人")
	c.check("%dを含まない行はそのまま", Day1Events._format_mob_greet("素の台詞", 4) == "素の台詞")
	GameState.today_plan["mob_instances"]["mob_test_dw"] = {"type": "dock_workers", "count": 4}
	var dw_flavor: Dictionary = Day1Events._customer_flavor("mob_test_dw")
	c.check("customer_flavor(モブ)のgreetにも同じ書式が適用される",
		not dw_flavor["greet"].is_empty(), str(dw_flavor["greet"]))

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
