extends RefCounted
## 中身AA：4日目の本番の文（planning/scenario/day4/ の8本）をゲームのデータに入れたことの検証。
##   1. データ：4日目の場面（officer_02・delivery_man_03・granny_02）・モブ3組（days."4"）・市場の場面（day4_market）に印の問題が無い・
##      元の文の行が抜けなく入っている・OK は外れた札で2通り・注文の札と好物はデータのまま（今日の頼みは無い）
##   2. 市場：張姐（仕込む量の前と、選んだあとの3行）→ 市場 → 市場を出る → 梁伯。払い方は今までどおり
##   3. モブ：1組・2組・3組の晩は各職種の1組目の文、4組目（宵の口の2組目の運転手）は予備の一言と予備の退店の文
##   4. DM（4日目）：張姐・リン・阿強・ターニャ婆。常連3人の来店予告は出ない
##   5. 4日目を朝から閉店まで本番の画面で通す：元の文の行が順に出る・〔〕が出ない・反応は判定どおりの1行・
##      タイムラインのリンの 21:25 はリンの接客のあとから


## 元の文（.md）の「名前「セリフ」」の行（〔ゲーム〕の行・表・見出し・反応の行を除く）。from_heading の見出しから to_heading の見出しの前まで。
func _md_lines(file: String, from_heading: String, to_heading: String) -> Array:
	var text := FileAccess.get_file_as_string("res://planning/scenario/day4/" + file)
	var inside := false
	var out := []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			if line.contains(from_heading):
				inside = true
			elif to_heading != "" and line.contains(to_heading):
				inside = false
			continue
		if inside and line.contains("「") and line.ends_with("」") and not line.begins_with("-") and not line.begins_with("|") and not line.begins_with("〔"):
			out.append(line)
	return out


func _texts(events: Array) -> Array:
	return events.filter(func(e): return str(e.get("type", "")) == "GREET").map(func(e): return str(e["text"]))


func _ok_two_ways(reactions: Dictionary, wanted: Array) -> bool:
	var missing = reactions.get("OK_MISSING", null)
	if not (missing is Dictionary) or (missing as Dictionary).size() != 2:
		return false
	var keys: Array = (missing as Dictionary).keys()
	keys.sort()
	var want := wanted.duplicate()
	want.sort()
	return keys == want and (missing.values() as Array).has(reactions["OK"])


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	News.clear_cache()
	GameState.reset_for_new_game()
	GameState.day_count = 4

	# --- 1. データ ---
	var scenes := [["officer", "officer_02", "4日目_新人警官.md", ["SOUR", "BITE"], "rice_noodle"],
		["delivery_man", "delivery_man_03", "4日目_運び屋.md", ["HOT", "POWER"], "tofu"],
		["granny", "granny_02", "4日目_老婆.md", ["SAVORY", "FILLING"], "offal"]]
	for sc in scenes:
		var ep := ScheduleData.episode_data(sc[0], sc[1])
		var lines := _texts(Day1Events._talk(sc[0], ep["greet"])) + _texts(Day1Events._scene_lines("body", sc[0], ep["body"]))
		var md := _md_lines(sc[2], "本編", "実装メモ")
		c.check("%s：場面データの形・印に問題が無い・元の文の行（%d行）がそのまま・OK は2通り・今日の頼み無し・注文と好物はデータのまま %s" % [sc[1], md.size(), str(sc[3])],
			ScheduleData.scene_problems(ep).is_empty() and lines == md and _ok_two_ways(ep["reactions"], sc[3])
				and ScheduleData.episode_today_request(sc[0], sc[1]).is_empty() and ScheduleData.customer_profile(sc[0])["wanted_tags"] == sc[3]
				and str(ScheduleData.customer_profile(sc[0])["favorite"]) == sc[4] and str(ep.get("source", "")).ends_with(sc[2]),
			"%s / %d / %d" % [str(ScheduleData.scene_problems(ep)), lines.size(), md.size()])
	c.check("ターニャ婆の GREAT は4日目の文（仮の一言から替えた）",
		ScheduleData.episode_data("granny", "granny_02")["reactions"]["GREAT"] == ["ターニャ婆「モツも入れたんだね。いい匂いだ。……これは、急いで飲んじまうのがもったいない」"])
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	var grade_of := func(additions: Array, wanted: Array, favorite: String) -> String: return str(Judge.grade({ "additions": additions }, GameState.soup, { "wanted_tags": wanted, "favorite": favorite })["grade"])
	c.check("手がかりと札：リンの GREAT＝塩漬けライム＋歯ごたえの具＋米麺（米麺は歯ごたえの代わりにならない）・ターニャ婆の GREAT＝薬膳ナンプラーだれ＋腹もちの具＋モツ",
		grade_of.call(["pickled_lime", "cartilage", "rice_noodle"], ["SOUR", "BITE"], "rice_noodle") == "GREAT"
			and grade_of.call(["pickled_lime", "rice_noodle"], ["SOUR", "BITE"], "rice_noodle") != "GREAT"
			and grade_of.call(["herbal_sauce", "broken_wrapper", "offal"], ["SAVORY", "FILLING"], "offal") == "GREAT"
			and grade_of.call(["herbal_sauce", "offal"], ["SAVORY", "FILLING"], "offal") != "GREAT")
	# 市場
	var talk := ScheduleData.talk_data("day4_market")
	var parts: Array = talk.get("parts", []).filter(func(p): return str(p.get("when", "")) != "shop" and str(p.get("speaker", "")) != "サミル")   # UI準備AG：店の会話（when:"shop"）・5日目のサミルは別に確かめる
	var zhang_md := _md_lines("4日目_昼市場.md", "張記肉類加工", "福生豆腐麺房")
	var liang_md := _md_lines("4日目_昼市場.md", "共同水場", "実装メモ")
	c.check("市場の場面：張姐（%d行。仕込む量の印の前は「で、今日はどれ位仕込む？」まで・あとに3行。必須情報の印 old_warehouse_load）と梁伯（%d行。払う印なし）" % [zhang_md.size(), liang_md.size()],
		parts.size() == 2 and parts[0]["lines"].filter(func(l): return l is String) == zhang_md and parts[0]["lines"][zhang_md.size() - 3] is Dictionary
			and str(parts[0]["lines"][zhang_md.size() - 4]).ends_with("で、今日はどれ位仕込む？」") and parts[0]["must_info"] == ["old_warehouse_load"]
			and str(parts[1]["when"]) == "exit" and parts[1]["lines"] == liang_md and Rules.day_overrides(4).get("market_scene", "") == "day4_market")
	var before := Day1Events.prep_events({}, false)
	var after := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	var types: Array = after.map(func(e): return str(e["type"]))
	var market_at := types.find("MARKET")
	c.check("市場の列：張姐 → 仕込む量 → 選んだあとの3行 → 鍋の素 → 市場 → 梁伯 → 「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」。PAY は無い（払い方は今までどおり）",
		before.map(func(e): return str(e["text"])) == zhang_md.slice(0, zhang_md.size() - 3) and str(before.back()["type"]) == "PREP_TIER"
			and after.slice(0, 3).map(func(e): return str(e["text"])) == zhang_md.slice(zhang_md.size() - 3) and str(after[3]["type"]) == "ADD_ITEM" and market_at == 4
			and after.slice(market_at + 1, market_at + 1 + liang_md.size()).map(func(e): return str(e["text"])) == liang_md
			and str(after[market_at + 1 + liang_md.size()]["text"]) == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。"
			and not (before + after).any(func(e): return str(e["type"]) == "PAY") and not Day1Events.market_exit_pays_in_scene())

	# --- 3. モブ ---
	var mobs := { "long_haul_driver": ["宵の口　長距離運転手", "夜半　雑貨屋の夜番", ["SAVORY", "TREAT"]],
		"general_store_clerk": ["夜半　雑貨屋の夜番", "明け方　ホテルの夜番", ["BITTER", "GENTLE"]],
		"laundry_night": ["明け方　ホテルの夜番", "四組目", ["SOUR", "GENTLE"]] }
	for mob_id in mobs:
		var form := ScheduleData.mob_data_for_day(mob_id, 4)
		var two := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 2))
		var one := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 1))
		var md := _md_lines("4日目_モブ3組.md", mobs[mob_id][0], mobs[mob_id][1])
		c.check("%s（4日目）：元の文（%d行）がそのまま・2杯以上の行は2杯の組だけ・OK は2通り・注文の札はデータのまま・予備の一言と予備の退店の文がある" % [mob_id, md.size()],
			two + form["after_talk"] == md and two.size() == one.size() + 1 and _ok_two_ways(form["reactions"], mobs[mob_id][2]) and form["wanted_tags"] == mobs[mob_id][2]
				and not (form["reactions"] as Dictionary).has("GREAT") and (form["spare_greet"] as Array).size() >= 2 and (form["spare_farewell"] as Array).size() == 1,
			"%d / %d" % [(two + form["after_talk"]).size(), md.size()])
	# 予備の注文の文（11/17 に表へ足した列）：予備の一言が出た組は、元の注文の文の代わりにこれ。雑貨屋の夜番は元の注文の文のまま
	var spare_orders := {}
	var spare_shape_ok := true
	for mob_id in mobs:
		var spare_greet: Array = ScheduleData.mob_data_for_day(mob_id, 4)["spare_greet"]
		spare_orders[mob_id] = spare_greet[1]
		spare_shape_ok = spare_shape_ok and spare_greet.size() == 3 and not spare_greet.has("店主「今日は何にする」")
	c.check("予備の一言のあとの注文の行：運転手・ホテルの夜番は予備の注文の文、雑貨屋の夜番は元の注文の文（予備の一言→注文の行→2杯以上の行の3つ）",
		spare_orders["long_haul_driver"] == "運転手「魚醤のきいた汁に、ちょっといい具。荷を下ろした日くらいはな」"
			and spare_orders["laundry_night"] == "夜番「酸っぱい汁、頼める？　具はやさしいので。修理の人が来るまでに飲むよ」"
			and spare_orders["general_store_clerk"] == "夜番「持ち帰りで頼む。苦い汁に、腹にやさしい具でな」" and spare_shape_ok, str(spare_orders))
	c.check("ホテルの夜番の4日目の文に「共同洗濯場の夜番」「洗濯場の夜番」は出ない",
		not JSON.stringify(ScheduleData.mob_data_for_day("laundry_night", 4)).contains("洗濯場の夜番"))
	# 1〜4組の晩：組の配り方（1組目→夜半、2組目→宵の口、3組目→明け方、4組目→宵の口）で、4組目だけ予備の一言・予備の退店の文
	for groups in [1, 2, 3, 4]:
		GameState.reset_for_new_game()
		GameState.day_count = 4
		var slots := [{ "name": "宵の口", "mob": ScheduleData.mob_rule_for(4, "宵の口") }, { "name": "夜半", "mob": ScheduleData.mob_rule_for(4, "夜半") },
			{ "name": "明け方", "mob": ScheduleData.mob_rule_for(4, "明け方") }]
		var by_index := Day1Events._plan_mob_groups(slots, groups * 4)   # 4杯ずつの組を groups 組
		var instances := {}
		var seq := 0
		var order := []
		for i in range(3):
			for size in by_index.get(i, []):
				var iid := "mob#%d" % seq
				seq += 1
				instances[iid] = { "type": str(ScheduleData.mob_rule_for(4, slots[i]["name"])["pool"][0]), "count": size }
				order.append(iid)
		GameState.today_plan = { "day": 4, "slots": [], "mob_instances": instances }
		var spare_ids := order.filter(func(iid): return Day1Events.is_repeat_mob_group(iid))
		var ok := true
		for iid in order:
			var form := ScheduleData.mob_data_for_day(str(instances[iid]["type"]), 4)
			var want_greet := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_greet"] if spare_ids.has(iid) else form["greet"], int(instances[iid]["count"])))
			var want_after: Array = form["spare_farewell"] if spare_ids.has(iid) else form["after_talk"]
			ok = ok and Day1Events._customer_flavor(iid)["greet"] == want_greet and _texts(Day1Events.mob_after_talk_events(iid)) == want_after
		c.check("モブが%d組の晩：各組の文と退店の文が正しい（予備の一言で来る組 %d組。4組目＝宵の口の2組目の運転手だけ）" % [groups, spare_ids.size()],
			ok and order.size() == groups and spare_ids.size() == (1 if groups == 4 else 0)
				and (groups < 4 or str(instances[spare_ids[0]]["type"]) == "long_haul_driver"), str(instances))

	# --- 4. DM ---
	GameState.reset_for_new_game()
	GameState.day_count = 4
	for cid in ["officer", "delivery_man", "granny"]:
		GameState.customer_memory[cid] = { "favorite_known": false, "visits": [{ "day": 2, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	GameState.today_plan = { "day": 4, "slots": [{ "name": "宵の口", "customers": ["officer"], "regular_id": "officer" },
		{ "name": "夜半", "customers": ["delivery_man"], "regular_id": "delivery_man" }, { "name": "明け方", "customers": ["granny"], "regular_id": "granny" }],
		"mob_instances": {}, "demand_center": 9 }
	var dm := Dm.delivered_for_day(4)
	c.check("4日目の朝のDM：張姐 6:35・リン 7:10（米の麺）・阿強 7:40（いつもの肉の方）・ターニャ婆 8:05。常連3人の来店予告は出ない・仮の d4_dock_workers は無い",
		dm.map(func(x): return "%s %s" % [x["from"], x["time"]]) == ["張姐 6:35", "リン 7:10", "阿強 7:40", "ターニャ婆 8:05"]
			and str(dm[1]["text"]).contains("米の麺") and str(dm[2]["text"]).contains("いつもの肉の方")
			and not dm.any(func(x): return bool(x.get("preview", false))) and not Dm.items_for_day(4).any(func(x): return str(x["id"]) == "d4_dock_workers"),
		str(dm.map(func(x): return x["id"])))
	GameState.customer_memory.erase("granny")
	c.check("会っていない客（ターニャ婆）のDMは届かない", not Dm.delivered_for_day(4).any(func(x): return str(x["id"]) == "d4_granny"))

	# --- 5. 4日目を朝から閉店まで本番の画面で通す ---
	_play_day4(t, c)

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()


func _play_day4(t: SceneTree, c: TestCheck) -> void:
	ReadState.reset("user://test_read_day4_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while GameState.day_count < 4 and guard < 16000:
		guard += 1
		if play.step() == "":
			break
	c.check("（前提）Day1〜3 を遊び、Day4 の朝へ進んだ", GameState.day_count == 4)
	var inbox := Dm.inbox(4).filter(func(x): return int(x["day"]) == 4)
	c.check("Day4 の朝のDM：張姐・リン・阿強・ターニャ婆。常連3人の予告は無い",
		["d4_market", "d4_officer", "d4_delivery_man", "d4_granny"].all(func(id): return inbox.map(func(x): return str(x["id"])).has(id))
			and not inbox.any(func(x): return ["officer", "delivery_man", "granny"].has(str(x.get("subject", "")))), str(inbox.map(func(x): return x["id"])))
	var shown_lines := []
	var shown_keys := {}
	var bracket_shown := []
	var reactions := []
	var reacted := {}
	var plan_slots: Array = []
	var plan_mobs := {}
	var served_at_close := []
	var lin_before := false
	var lin_after := false
	guard = 0
	while GameState.day_count == 4 and guard < 9000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if GameState.phase == GameState.Phase.OPEN and plan_slots.is_empty():
			plan_slots = (GameState.today_plan["slots"] as Array).duplicate(true)
			plan_mobs = (GameState.today_plan["mob_instances"] as Dictionary).duplicate(true)
		if GameState.phase == GameState.Phase.PREP or GameState.phase == GameState.Phase.OPEN:
			var visible := Sns.visible_ids(4, s.timeline_limit(), {}, s.market_talks_done(), s.phone_visits_done_today()).has("d4_lin_alt_2125")
			var cur := str(s.open.current_customer()) if s.open != null else ""
			if visible and (GameState.phase == GameState.Phase.PREP or cur == "officer"):
				lin_before = true
			if visible and GameState.phase == GameState.Phase.OPEN and cur != "officer":
				lin_after = true
		if str(line.get("type", "")) == "REACT" and str(line.get("text", "")) != "" and s.open != null:
			var key := "%d|%d|%d" % [s.open.slot_index, s.open.index, s.flow.runner.index]
			if not reacted.has(key):
				reacted[key] = true
				var ev: Dictionary = s.flow.runner.current()
				reactions.append({ "grade": str(s.open.current_bowl.get("base_result", s.open.current_bowl.get("result", ""))) if str(s.open.current_bowl.get("result", "")) != "" else "", "text": s.current_reaction_text(),
					"pool": ev.get("reactions", {}), "customer": str(ev.get("customer", "")) })
		var name := str(line.get("speaker_name", ""))
		if s.flow.runner != null and str(line.get("text", "")) != "" and str(line.get("type", "")) != "REACT" and not ["shop_talk", "hearty", "penalty"].has(str(line.get("part", ""))):   # UI準備AG：店の会話・具だくさんの一言は別に確かめる
			var line_key := "%d|%d|%d|%d|%s" % [GameState.phase, s.open.slot_index if s.open != null else -1, s.open.index if s.open != null else -1,
				s.flow.runner.index, str(line.get("text", ""))]
			if not shown_keys.has(line_key):
				shown_keys[line_key] = true
				shown_lines.append(name + str(line.get("text", "")))
		if GameState.phase == GameState.Phase.CLOSE and served_at_close.is_empty():
			served_at_close = GameState.served.duplicate(true)
		if play.step() == "":
			break
	c.check("Day4 を閉店まで遊び、Day5 の朝へ進んだ", GameState.day_count == 5, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("会話枠に〔〕の文（〔ゲーム〕・実装メモ）が一度も出ない", bracket_shown.is_empty(), str(bracket_shown))
	var talk: Array = ScheduleData.talk_data("day4_market")["parts"]
	var expected: Array = (talk[0]["lines"] as Array).filter(func(l): return l is String)
	expected.append_array(talk[1]["lines"])
	var declined := {}
	for rec in served_at_close:
		if bool(rec.get("declined", false)) or int(rec.get("servings", 0)) <= 0:
			declined[str(rec.get("customer", ""))] = true
	var mob_types := []
	for slot in plan_slots:
		for id in slot["customers"]:
			if str(id).begins_with("mob#"):
				var type_id := str(plan_mobs[id]["type"])
				var count := int(plan_mobs[id]["count"])
				mob_types.append("%s×%d" % [type_id, count])
				var form := ScheduleData.mob_data_for_day(type_id, 4)
				var repeat := false
				for other in plan_mobs:
					repeat = repeat or (int(str(other).trim_prefix("mob#")) < int(str(id).trim_prefix("mob#")) and str(plan_mobs[other]["type"]) == type_id)
				expected.append_array(ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_greet"] if repeat else form["greet"], count)))
				if not declined.has(str(id)):
					expected.append_array(form["spare_farewell"] if repeat else form["after_talk"])
			else:
				var ep := ScheduleData.episode_data(str(id), str(slot["episode_id"]))
				expected.append_array(ScheduleData.spoken_lines(CustomerMemory.resolve_lines(ep["greet"], str(id))))
				if not declined.has(str(id)):
					expected.append_array(ScheduleData.spoken_lines(CustomerMemory.resolve_lines(ep["body"], str(id))))
	var got := shown_lines.filter(func(x): return str(x).contains("「") and not str(x).begins_with("「"))
	var first_diff := -1
	for i in range(maxi(got.size(), expected.size())):
		if i >= got.size() or i >= expected.size() or got[i] != expected[i]:
			first_diff = i
			break
	c.check("Day4 の元の文の行（%d行）が、張姐→梁伯→宵の口→夜半→明け方の順に、抜けも重なりも無く出た（モブ %s）" % [expected.size(), str(mob_types)],
		first_diff == -1, "最初に違う行 %d：%s ／ 期待 %s" % [first_diff, str(got[first_diff]) if first_diff >= 0 and first_diff < got.size() else "（無い）",
			str(expected[first_diff]) if first_diff >= 0 and first_diff < expected.size() else "（無い）"])
	var react_ok := true
	for r in reactions:
		var pool: Array = (r["pool"] as Dictionary).get(r["grade"] if r["grade"] != "" else "UNSERVED", []).duplicate()   # UI準備AG：断った反応は UNSERVED
		if r["grade"] == "OK" and (r["pool"] as Dictionary).get("OK_MISSING") is Dictionary:
			for tag in r["pool"]["OK_MISSING"]:
				pool.append_array(r["pool"]["OK_MISSING"][tag])
		react_ok = react_ok and pool.has(r["text"]) and not str(r["text"]).contains("\n") and not str(r["text"]).contains("〔")
	c.check("反応は、判定の結果の段の元の文の1行だけ（OK は外れた札の文も。%d回）" % reactions.size(), react_ok and reactions.size() >= 2,
		str(reactions.map(func(r): return "%s %s %s" % [r["customer"], r["grade"], r["text"]])))
	c.check("タイムラインのリンの 21:25：市場・リンの接客中は見えず、リンのあとは見える", not lin_before and lin_after)
	root.queue_free()
