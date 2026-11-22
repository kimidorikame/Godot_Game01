extends RefCounted
## UI準備AG・中身AF：
##   1. 市場の店ごとの会話：店を押した日だけ・その日に1回だけ出る（会話の列には触れない・買い物は変わらない）。5日目のサミルは市場を出るときに毎回。
##   2. 具だくさんの一言：具だくさんのチップが付いた提供（具の材料2種類・GOOD 以上）だけ、反応のすぐあとに1行（常連・阿強の1日目の3杯目・モブ）。
##   3. 断ったときの一言（reactions.UNSERVED）：常連・モブ（「注文を断る」）で出る。阿強の1日目は断った杯でそこで帰る。
##      2日目のリンは断ったときの一言で名乗る。1日目のレックスは断っても場所代を取る。6日目の警備員を断った晩は「来ていた」にならない。

const TOP := ["HEARTY", "UNSERVED"]


func _open(t: SceneTree, customers: Array, day: int, mob: Dictionary = {}) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = day
	TalkLog.clear()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["coconut_milk", "tofu", "winter_melon", "nam_prik_pao", "meat_ball", "herbal_sauce", "broken_wrapper"]:
		GameState.add_inventory(id, 6, 8)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	for id in mob:
		GameState.today_plan["mob_instances"][id] = mob[id]
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	root.close_overlay()
	return root


func _to_adjust(s: PlaySession) -> void:
	var guard := 0
	while not s.is_choosing_ingredients() and guard < 120 and not s.flow.is_runner_done():
		guard += 1
		s.next_event()


func _pick(s: PlaySession, ids: Array) -> void:
	for id in ids:
		s.select_ingredient(str(id))


## 反応（REACT）まで進め、その次の Event を返す（無ければ空）。
func _react_then_next(s: PlaySession) -> Dictionary:
	var guard := 0
	while s.flow.runner != null and str((s.flow.runner.current() as Dictionary).get("type", "")) != "REACT" and guard < 10:
		guard += 1
		s.next_event()
	var i: int = s.flow.runner.index + 1
	return s.flow.runner.events[i] if i < s.flow.runner.events.size() else {}


## 市場の画面（MARKET の入力待ち）に入った状態を作る。
func _market(day: int) -> PlaySession:
	GameState.reset_for_new_game()
	GameState.day_count = day
	var s := PlaySession.new()
	GameState.phase = GameState.Phase.PREP
	var events := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	s.flow.set_runner(events)
	var at := events.map(func(e): return str(e.get("type", ""))).find("MARKET")
	s.flow.runner.index = at
	s.flow.runner.status = EventRunner.Status.WAITING_INPUT
	return s


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ReadState.reset("user://test_read_ui_prep_ag.json")
	ScheduleData.clear_cache()

	# --- 1. 市場の店ごとの会話 ---
	var want := { 2: { "seafood": "海叔" }, 3: { "tofu_noodles": "ミン", "seafood": "海叔" }, 4: { "tofu_noodles": "ミン", "produce": "アユ" },
		5: { "dry_goods": "羅文" }, 6: { "seafood": "海叔", "scraps": "ヨヨ" }, 7: { "seafood": "海叔", "tofu_noodles": "ミン" } }
	var data_ok := true
	var bad_words := []
	for day in want:
		var parts: Array = ScheduleData.talk_data("day%d_market" % day)["parts"]
		var shops := parts.filter(func(p): return str(p["when"]) == "shop")
		data_ok = data_ok and shops.map(func(p): return str(p["shop"])) == (want[day] as Dictionary).keys()
		for p in shops:
			data_ok = data_ok and str(p["speaker"]) == str(want[day][p["shop"]]) and not (p["lines"] as Array).is_empty()
			for line in p["lines"]:
				for w in ["客足", "〔"]:
					if str(line).contains(w):
						bad_words.append(line)
	c.check("店の会話のデータ：2日目 海叔／3日目 ミン・海叔／4日目 ミン・アユ／5日目 羅文／6日目 海叔・ヨヨ／7日目 海叔・ミン（when:\"shop\"）・「客足」や〔〕の行は無い",
		data_ok and bad_words.is_empty(), str(bad_words))
	c.check("2日目の海叔は1行（「客足」の語を外した文）", ScheduleData.talk_data("day2_market")["parts"].filter(func(p): return str(p["when"]) == "shop")[0]["lines"]
		== ["海叔「明日は一日雨だって。貝を見るならこっち。今夜の鍋に入れる分、選んでいきなよ」"])

	var s := _market(3)
	var money := GameState.money
	var inv := GameState.inventory.duplicate(true)
	var events_before: int = s.flow.runner.events.size()
	c.check("（前提）3日目の市場の画面にいる・店の会話はまだ無い", s.is_in_market() and not s.has_shop_talk())
	s.select_stall("seafood")
	var first := s.current_line()
	var heard := []
	var guard := 0
	while s.has_shop_talk() and guard < 60:
		guard += 1
		heard.append(str(s.current_line()["speaker_name"]) + str(s.current_line()["text"]))
		s.record_visible_event()
		s.advance_shop_talk()
	var sea3: Array = Day1Events.shop_talk_lines("seafood")
	c.check("3日目に海隆鮮貨を押すと、海叔の会話が会話枠に1行ずつ出る（%d行）・会話の列（MARKET の入力待ち）は動かない・ログに残る" % sea3.size(),
		str(first["speaker_name"]) == "海叔" and heard == sea3 and s.is_in_market() and s.flow.runner.events.size() == events_before
			and TalkLog.entries.any(func(e): return str(e["speaker"]) == "海叔"), str(heard.slice(0, 2)))
	s.leave_shop()
	s.select_stall("seafood")
	c.check("同じ日に2回目に押しても出ない（1日に1回）", not s.has_shop_talk())
	s.leave_shop()
	s.select_stall("produce")
	c.check("会話の無い店（3日目の永順青果）では何も出ない", not s.has_shop_talk())
	s.leave_shop()
	s.select_stall("tofu_noodles")
	c.check("3日目の福生豆腐麺房はミンの会話", s.has_shop_talk() and str(s.current_line()["speaker_name"]) == "ミン")
	c.check("店の会話の前後で、所持金・持ち物は変わらない", GameState.money == money and GameState.inventory == inv)
	s.exit_market()
	c.check("市場を出たら、読み残した店の会話は出ない", not s.has_shop_talk())
	var s4 := _market(4)
	c.check("店を押さなかった日（4日目）は店の会話が出ない", not s4.has_shop_talk() and s4.shop_talks_done.is_empty())
	GameState.reset_for_new_game()
	GameState.day_count = 5
	var exit5 := Day1Events.market_scene_events("exit").map(func(e): return str(e["text"]))
	var samir_at := exit5.find("サミル「……袋、そこ。縫い終わる」")
	var liang_at := exit5.find(exit5.filter(func(x): return str(x).begins_with("梁伯「"))[0])
	c.check("5日目のサミル（炭屋）は、市場を出るとき・梁伯の前に毎回出る（店を押さなくても）", samir_at == 0 and liang_at > samir_at
		and Day1Events.shop_talk_lines("dry_goods").size() > 0, str(exit5.slice(0, 2)))

	# --- 2. 具だくさんの一言 ---
	var thug3: Dictionary = ScheduleData.episode_data("thug", "thug_03")
	var root := _open(t, ["thug"], 6)
	s = root.session
	_to_adjust(s)
	_pick(s, ["coconut_milk", "tofu", "winter_melon"])
	s.complete_input()
	var nxt := _react_then_next(s)
	c.check("常連（6日目のレックス）：具の材料が2種類・GOOD 以上なら、反応のすぐあとに具だくさんの一言（チップの表示はそのまま）",
		s.last_serve_hearty > 0 and str(nxt.get("part", "")) == "hearty" and str(nxt.get("text", "")) == str(thug3["reactions"]["HEARTY"][0])
			and s.current_line()["text"].contains("具だくさん +¥"), str(nxt))
	root.free()
	root = _open(t, ["thug"], 6)
	s = root.session
	_to_adjust(s)
	_pick(s, ["coconut_milk", "tofu"])
	s.complete_input()
	nxt = _react_then_next(s)
	var one_kind := str(nxt.get("part", "")) != "hearty" and s.last_serve_hearty == 0
	root.free()
	root = _open(t, ["thug"], 6)
	s = root.session
	_to_adjust(s)
	_pick(s, ["nam_prik_pao", "tofu", "winter_melon"])
	s.complete_input()
	nxt = _react_then_next(s)
	var low := str(nxt.get("part", "")) != "hearty" and not ["GOOD", "GREAT"].has(str(s.open.current_bowl.get("result", "")))
	c.check("具が1種類・GOOD 未満（OK）のときは出ない", one_kind and low)
	root.free()
	# 1日目の阿強の3杯目
	root = _open(t, ["delivery_man"], 1)
	s = root.session
	var cups: Array = ScheduleData.episode_data("delivery_man", "delivery_man_01")["cups"]
	for i in range(2):
		_to_adjust(s)
		_pick(s, ["nam_prik_pao", "meat_ball"])
		s.complete_input()
		_react_then_next(s)
		s.next_event()
	_to_adjust(s)
	_pick(s, ["herbal_sauce", "tofu", "winter_melon"])
	s.complete_input()
	nxt = _react_then_next(s)
	c.check("阿強の1日目の3杯目（持ち帰り）：具だくさんなら3杯目の一言", str(nxt.get("part", "")) == "hearty" and str(nxt.get("text", "")) == str(cups[2]["reactions"]["HEARTY"][0]), str(nxt))
	root.free()
	# モブ（3日目の安宿の夜勤受付）
	root = _open(t, ["mob#0"], 3, { "mob#0": { "type": "inn_clerk", "count": 2 } })
	s = root.session
	_to_adjust(s)
	_pick(s, ["coconut_milk", "tofu", "winter_melon"])
	s.group_serve(2, 2)
	nxt = _react_then_next(s)
	var inn3: Dictionary = ScheduleData.mob_data_for_day("inn_clerk", 3)
	c.check("モブ（3日目の受付・2杯の組）：反応のすぐあとに、その日のその職種の具だくさんの一言を1行だけ",
		str(nxt.get("part", "")) == "hearty" and str(nxt.get("text", "")) == str(inn3["reactions"]["HEARTY"][0])
			and s.flow.runner.events.filter(func(e): return str(e.get("part", "")) == "hearty").size() == 1, str(nxt))
	root.free()

	# --- 3. 断ったときの一言 ---
	root = _open(t, ["hooker"], 3)
	s = root.session
	_to_adjust(s)
	s.decline_customer()
	s.next_event()
	c.check("常連（3日目のセティヤ）を断る：反応は断ったときの一言", s.current_reaction_text() == str(ScheduleData.episode_data("hooker", "hooker_02")["reactions"]["UNSERVED"][0]))
	root.free()
	root = _open(t, ["mob#0"], 6, { "mob#0": { "type": "security_guard", "count": 1 } })
	s = root.session
	_to_adjust(s)
	s.group_decline(1)
	s.next_event()
	c.check("モブ（6日目の警備員）の「注文を断る」：反応はその日のその職種の断ったときの一言",
		s.current_reaction_text() == str(ScheduleData.mob_data_for_day("security_guard", 6)["reactions"]["UNSERVED"][0]), s.current_reaction_text())
	c.check("6日目の警備員を断った晩は「来ていた」にならない：火事の場面の店主の1行は「……阿強、今夜はどこの門だ」",
		not Day1Events.mob_types_served_on(6).has("security_guard")
			and News.event_texts(News.day_entry(6)["events"][0], 6).has("店主「……阿強、今夜はどこの門だ」")
			and not News.event_texts(News.day_entry(6)["events"][0], 6).has("店主「……さっきの飯、持って帰ったばかりだぞ」"))
	root.free()
	# 2日目のリン：断ったときの一言で名乗る
	root = _open(t, ["officer"], 2)
	s = root.session
	_to_adjust(s)
	var before_name := CustomerMemory.display_name("officer")
	s.decline_customer()
	s.next_event()
	var lin_line := s.current_reaction_text()
	var after_name := CustomerMemory.display_name("officer")
	GameState.day_count = 3
	c.check("2日目のリンを断った道：断ったときの一言（「リンです」）で名前が「リン」に替わり、3日目以降も「リン」",
		before_name != "リン" and lin_line.contains("リンです") and after_name == "リン" and CustomerMemory.display_name("officer") == "リン", "%s / %s" % [before_name, after_name])
	root.free()
	# 1日目のレックス：断っても場所代を取る
	root = _open(t, ["thug"], 1)
	s = root.session
	_to_adjust(s)
	var money1 := GameState.money
	s.decline_customer()
	guard = 0
	while not s.flow.is_runner_done() and guard < 80:
		guard += 1
		s.next_event()
	c.check("1日目のレックスを断った晩も、場所代（¥%d）を今までどおり取る・断ったときの一言は「飯は今度だ…」" % GameState.RENT_PRICE,
		GameState.money == money1 - GameState.RENT_PRICE and str(ScheduleData.episode_data("thug", "thug_01")["reactions"]["UNSERVED"][0]).begins_with("レックス「飯は今度だ"),
		"%d → %d" % [money1, GameState.money])
	root.free()
	# 1日目の阿強：1杯目を断ったら、そこで帰る
	root = _open(t, ["delivery_man"], 1)
	s = root.session
	_to_adjust(s)
	var money_a := GameState.money
	s.decline_customer()
	s.next_event()
	var rest: Array = s.flow.runner.events.slice(s.flow.runner.index + 1)
	c.check("阿強の1杯目を断った道：断ったときの一言（1杯目）のあと、残りの杯と会話は出ない・払いは0",
		s.current_reaction_text() == str(cups[0]["reactions"]["UNSERVED"][0]) and not rest.any(func(e): return str(e.get("customer", "")) == "delivery_man")
			and GameState.money == money_a, str(rest.map(func(e): return e.get("type", ""))))
	root.free()
	# 2杯目を断った道：1杯目の分だけ払う
	root = _open(t, ["delivery_man"], 1)
	s = root.session
	_to_adjust(s)
	var money_b := GameState.money
	_pick(s, ["nam_prik_pao", "meat_ball"])
	s.complete_input()
	_react_then_next(s)
	var after_cup1 := GameState.money
	_to_adjust(s)
	s.decline_customer()
	s.next_event()
	var react2 := s.current_reaction_text()
	rest = s.flow.runner.events.slice(s.flow.runner.index + 1)
	guard = 0
	while not s.flow.is_runner_done() and guard < 20:
		guard += 1
		s.next_event()
	s.advance_open_queue_if_customer_done()
	var visit: Dictionary = CustomerMemory.last_visit("delivery_man")
	c.check("阿強の2杯目を断った道：2杯目の断ったときの一言のあと帰る・払いは1杯目の分だけ・3杯目の事実（持ち帰り）は付かない",
		react2 == str(cups[1]["reactions"]["UNSERVED"][0]) and not rest.any(func(e): return str(e.get("customer", "")) == "delivery_man")
			and after_cup1 > money_b and GameState.money == after_cup1 and int(visit.get("served", 0)) == 1
			and not bool(CustomerMemory.fact("delivery_man", "day1_takeout_served", false)), "%s / %d" % [str(visit), GameState.money - money_b])
	root.free()
	c.check("7日目のターニャ婆は断ったときの一言を持たない（断った晩の本文が兼ねる）・具だくさんの一言はある",
		not (ScheduleData.episode_data("granny", "granny_03")["reactions"] as Dictionary).has("UNSERVED")
			and (ScheduleData.episode_data("granny", "granny_03")["reactions"] as Dictionary).has("HEARTY"))
	c.check("データの検査：場面（unserved_reveal_name・HEARTY・UNSERVED）に問題が無い",
		["officer_01", "thug_01", "granny_03"].all(func(e): return ScheduleData.scene_problems(ScheduleData.episode_data({ "officer_01": "officer", "thug_01": "thug", "granny_03": "granny" }[e], e)).is_empty())
			and ScheduleData.scene_problems(ScheduleData.episode_data("delivery_man", "delivery_man_01")).is_empty())

	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	TestCheck.free_added(t, root_before)
	return c.finish()
