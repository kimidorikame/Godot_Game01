extends RefCounted
## 日別スケジュールの汎用化（JSON外部化。CURRENT_SPEC.md §9-C）と、
## Day2-7ダミーデータ・モブの枠ごと独立抽選の検証。
## 実データ（Day1・Day2の非モブ客）の文言そのものは、コミット時点の値と比較して確認する
## （膨大な会話文をここへ複製すると保守が難しくなるため）。ここでは仕組みそのもの
## （フォールバック・抽選プール・モブの独立抽選・書式）を検証する。

func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. day_schedule() のフォールバック（Day8以降はDay1へ。Day3〜7は実データが埋まった） ---
	var day1 := ScheduleData.day_schedule(1)
	var day8 := ScheduleData.day_schedule(8)
	c.check("day_schedule(1)にslotsがある", day1.has("slots") and day1["slots"].size() == 3)
	c.check("day_schedule(8)はday_schedule(1)へフォールバック(未定義日)", day8 == day1, str(day8))
	for d in range(1, 8):
		var ds := ScheduleData.day_schedule(d)
		c.check("day_schedule(%d)にslotsがある" % d, ds.has("slots") and not ds["slots"].is_empty())
	c.check("Day2は3枠に増えた(夜半・明け方が復活)", ScheduleData.day_schedule(2)["slots"].size() == 3)

	# --- 2. customer_data() のフォールバック（客データ自身も独立して1日目へ） ---
	# 会話文は調整中のためプレースホルダー（名前＋要求タグ／結果ラベルのみ）。ここでは
	# 実際の文言ではなく、構造（favorite/wanted_tags/servings・フォールバック）だけを見る。
	GameState.reset_for_new_game()
	var thug1 := ScheduleData.customer_data("thug", 1)
	var thug3 := ScheduleData.customer_data("thug", 3)
	c.check("thugのfavorite/wanted_tagsが読める", thug1.get("favorite") == "meat_ball"
		and thug1.get("wanted_tags") == ["MELLOW", "GENTLE"] and thug1.get("servings") == 1)
	c.check("thugのDay3はDay1へフォールバック(thug.jsonはDay1分のみ)", thug3 == thug1, str(thug3))
	c.check("thugの反応文にGREATキーがある", thug1.get("reactions", {}).has("GREAT"))
	var dm1 := ScheduleData.customer_data("delivery_man", 1)
	c.check("delivery_manのfavorite/wanted_tagsはトップレベルに持つ",
		dm1.get("favorite") == "tofu" and dm1.get("wanted_tags") == ["HOT", "POWER"])
	var dm5 := ScheduleData.customer_data("delivery_man", 5)
	c.check("delivery_manは2日目以降ぶんの通常フローデータ(greet/reactions/servings)も持つ",
		not dm5.get("greet", []).is_empty() and dm5.get("servings") == 1
		and dm5.get("reactions", {}).has("GREAT"))
	c.check("officerはDay2のデータを持つ(favoriteは実データのまま)",
		ScheduleData.customer_data("officer", 2).get("favorite") == "rice_noodle")
	for d in range(3, 8):
		c.check("officerのDay%dぶんが読める(未設定なら1へフォールバックでも可)" % d,
			not ScheduleData.customer_data("officer", d).get("greet", []).is_empty())
	for d in range(3, 8):
		c.check("hookerのDay%dぶんが読める" % d,
			not ScheduleData.customer_data("hooker", d).get("greet", []).is_empty())
	for d in range(4, 8):
		c.check("streamerのDay%dぶんが読める" % d,
			not ScheduleData.customer_data("streamer", d).get("greet", []).is_empty())
	c.check("存在しない客idは空辞書", ScheduleData.customer_data("no_such_customer_xyz", 1).is_empty())

	# --- 3. _pick_main(): 抽選プール・同日内重複禁止（既存機能・回帰確認） ---
	var seen := {}
	for i in range(200):
		var picked: String = Day1Events._pick_main({"main_pool": ["a", "b", "c"]}, ["a"])
		seen[picked] = true
	c.check("main抽選プール: 除外したidは選ばれない", not seen.has("a"), str(seen))
	c.check("main抽選プール: 残りの候補から選ばれる", seen.has("b") and seen.has("c"))
	c.check("main指定はプールより優先", Day1Events._pick_main({"main": "granny", "main_pool": ["x"]}, []) == "granny")
	c.check("main抽選プール枯渇時は選び直す(クラッシュしない)",
		Day1Events._pick_main({"main_pool": ["a"]}, ["a"]) == "a")

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
	GameState.day_count = 2   # Day1は人数固定(DAY1_MOB_COUNT)なので、評判依存を見るにはDay2以降にする
	GameState.reputation = -100
	c.check("人数0(評判が低い等)ならモブなし",
		Day1Events._pick_mob({"mob": {"pool": ["a"]}}, -1).is_empty())
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

	# --- 6. モブの枠ごとの独立抽選（種類がばらつきうること） ---
	# _mob_instancesを直接見て、同日2枠(宵の口=固定dock_workers/夜半=プール抽選)で
	# 型が独立して決まりうることを確認する。
	var types_at_night := {}
	for i in range(300):
		Day1Events.customer_schedule(-1)
		var night_id: String = "mob#1"   # Day1は宵の口(mob#0固定dock_workers)→夜半(mob#1)の順
		if Day1Events._mob_instances.has(night_id):
			types_at_night[Day1Events._mob_instances[night_id]["type"]] = true
	c.check("Day1夜半のモブ種類は複数出うる(dock_workers固定ではなくなった)",
		types_at_night.size() > 1, str(types_at_night))
	c.check("Day1宵の口のモブは常にdock_workers(mob:true)",
		Day1Events._mob_instances.get("mob#0", {}).get("type", "") == "dock_workers")

	# --- 7. デバッグ上書き: 全モブ枠の人数が揃う（種類は揃わなくてよい） ---
	GameState.day_count = 2
	var counts := {}
	var types2 := {}
	for i in range(50):
		Day1Events.customer_schedule(2)
		for id in Day1Events._mob_instances:
			var inst: Dictionary = Day1Events._mob_instances[id]
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
	c.check("Day2夜半・明け方はgranny/thug/delivery_manのいずれか",
		["granny", "thug", "delivery_man"].has(sched_day2[1]["customers"][0])
		and ["granny", "thug", "delivery_man"].has(sched_day2[2]["customers"][0]))

	# --- 9. is_mob_customer() / customer_events(): インスタンスidを正しく解決する ---
	GameState.day_count = 1
	var sched: Array = Day1Events.customer_schedule(4)
	var night_mob_id2: String = sched[1]["customers"][1]
	c.check("モブのインスタンスidはis_mob_customerでtrue", Day1Events.is_mob_customer(night_mob_id2))
	c.check("非モブ(thug)はis_mob_customerでfalse", not Day1Events.is_mob_customer("thug"))
	var mob_flavor: Dictionary = Day1Events._customer_flavor(night_mob_id2)
	c.check("モブのflavorはfavoriteを持たない", mob_flavor.get("favorite", "?") == "")
	c.check("モブのservingsはインスタンスの人数と一致",
		mob_flavor["servings"] == Day1Events._mob_instances[night_mob_id2]["count"])
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
	Day1Events._mob_instances["mob_test_dw"] = {"type": "dock_workers", "count": 4}
	var dw_flavor: Dictionary = Day1Events._customer_flavor("mob_test_dw")
	c.check("customer_flavor(モブ)のgreetにも同じ書式が適用される",
		not dw_flavor["greet"].is_empty(), str(dw_flavor["greet"]))

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
