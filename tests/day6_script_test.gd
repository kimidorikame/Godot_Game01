extends RefCounted
## 中身AD：6日目（火事の日）の本番の文（planning/scenario/day6/ の9本）をゲームのデータに入れたことの検証。
##   1. データ：6日目の場面（hooker_04・streamer_03・thug_03）・モブ3組（days."6"）・市場の場面（day6_market）・火事の共通場面4件に印の問題が無い・
##      元の文の行が抜けなく入っている・OK は外れた札で2通り・注文の札と好物はデータのまま（今日の頼みは無い）
##   2. 市場：張姐（仕込む量の前と、選んだあとの3行）→ 市場 → 市場を出る → 梁伯。払い方は今までどおり
##   3. モブ：1〜4組の晩の文と退店の文（4組目＝宵の口の2組目の運転手）・予備の注文の文（清掃員だけ）
##   4. 火事の共通場面：夜勤警備員が来た晩・来なかった晩の店主の1行・show_news／show_dm の位置・鍋が尽きた晩も閉店の前に出る
##   5. DM・ニュース・タイムラインの形（朝のDM3件・夜のDM9件・朝の記事4本・速報2本・転送のDMにニカの投稿の全文）
##   6. 文の検査（〔ゲーム〕が混ざらない・火事のあとの物が火事の場面より前に見えない）
##   7. 6日目を朝から閉店まで本番の画面で通す


const DAWN_IDS := ["d6_fire", "d6_fire_news", "d6_dawn"]


func _md_lines(file: String, from_heading: String, to_heading: String) -> Array:
	var text := FileAccess.get_file_as_string("res://planning/scenario/day6/" + file)
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
		if inside and line.contains("「") and line.ends_with("」") and not line.begins_with("-") and not line.begins_with("|") and not line.begins_with("〔") and not line.begins_with(">"):
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


## 共通イベントの行の配列から、会話の行（文字列・条件付きの行の中の行）を平らにして返す。
func _event_speech(lines: Array) -> Array:
	var out := []
	for line in lines:
		if line is String:
			out.append(line)
		elif ScheduleData.is_condition_group(line):
			out.append_array(_event_speech(line["lines"]))
	return out


func _ids(items: Array) -> Array:
	return items.map(func(x): return str(x["id"]))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	News.clear_cache()
	GameState.reset_for_new_game()
	GameState.day_count = 6

	# --- 1. データ ---
	var scenes := [["hooker", "hooker_04", "6日目_夜の女.md", ["BITTER", "TREAT"], "pickled_lime"],
		["streamer", "streamer_03", "6日目_配信者.md", ["MELLOW", "BITE"], "shrimp"],
		["thug", "thug_03", "6日目_チンピラ.md", ["MELLOW", "GENTLE"], "meat_ball"]]
	for sc in scenes:
		var ep := ScheduleData.episode_data(sc[0], sc[1])
		var lines := _texts(Day1Events._talk(sc[0], ep["greet"])) + _texts(Day1Events._scene_lines("body", sc[0], ep["body"]))
		var md := _md_lines(sc[2], "本編", "実装メモ")
		c.check("%s：場面データの形・印に問題が無い・元の文の行（%d行）がそのまま・OK は2通り・今日の頼み無し・注文と好物はデータのまま %s" % [sc[1], md.size(), str(sc[3])],
			ScheduleData.scene_problems(ep).is_empty() and lines == md and _ok_two_ways(ep["reactions"], sc[3])
				and ScheduleData.episode_today_request(sc[0], sc[1]).is_empty() and ScheduleData.customer_profile(sc[0])["wanted_tags"] == sc[3]
				and str(ScheduleData.customer_profile(sc[0])["favorite"]) == sc[4] and str(ep.get("source", "")).ends_with(sc[2]),
			"%s / %d / %d" % [str(ScheduleData.scene_problems(ep)), lines.size(), md.size()])
	var named_ok := true
	for sc in scenes:
		var raw := JSON.stringify(ScheduleData.episode_data(sc[0], sc[1]))
		named_ok = named_ok and not raw.contains("reveal_name") and not raw.contains("初めての客")
	c.check("3人とも最初から名前で出る（名乗る前の名前・名乗りの印は無い）", named_ok)
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	var grade_of := func(additions: Array, wanted: Array, favorite: String) -> String: return str(Judge.grade({ "additions": additions }, GameState.soup, { "wanted_tags": wanted, "favorite": favorite })["grade"])
	c.check("手がかりと札：セティヤの GREAT＝苦瓜＋ごちそうの具＋塩漬けライム・ニカの GREAT＝ココナッツミルク＋歯ごたえの具＋海老・レックスの GREAT＝ココナッツミルク＋やさしい具＋肉団子",
		grade_of.call(["bitter_melon", "clam", "pickled_lime"], ["BITTER", "TREAT"], "pickled_lime") == "GREAT"
			and grade_of.call(["coconut_milk", "cartilage", "shrimp"], ["MELLOW", "BITE"], "shrimp") == "GREAT"
			and grade_of.call(["coconut_milk", "tofu", "meat_ball"], ["MELLOW", "GENTLE"], "meat_ball") == "GREAT"
			and grade_of.call(["coconut_milk", "meat_ball"], ["MELLOW", "GENTLE"], "meat_ball") != "GREAT")
	# 市場
	var talk := ScheduleData.talk_data("day6_market")
	var parts: Array = talk.get("parts", []).filter(func(p): return str(p.get("when", "")) != "shop" and str(p.get("speaker", "")) != "サミル")   # UI準備AG：店の会話（when:"shop"）・5日目のサミルは別に確かめる
	var zhang_md := _md_lines("6日目_昼市場.md", "張記肉類加工", "海隆鮮貨")
	var liang_md := _md_lines("6日目_昼市場.md", "共同水場", "実装メモ")
	c.check("市場の場面：張姐（%d行。仕込む量の印の前は「で、今日はどれ位仕込む？」まで・あとに3行。必須情報の印は付けない）と梁伯（%d行。払う印なし）・海叔・ヨヨは入れない" % [zhang_md.size(), liang_md.size()],
		parts.size() == 2 and parts[0]["lines"].filter(func(l): return l is String) == zhang_md and parts[0]["lines"][zhang_md.size() - 3] is Dictionary
			and str(parts[0]["lines"][zhang_md.size() - 4]).ends_with("で、今日はどれ位仕込む？」") and not (parts[0] as Dictionary).has("must_info")
			and str(parts[1]["when"]) == "exit" and parts[1]["lines"] == liang_md and Rules.day_overrides(6).get("market_scene", "") == "day6_market"
			and not JSON.stringify(parts).contains("海叔「") and not JSON.stringify(parts).contains("ヨヨ「"))
	var before := Day1Events.prep_events({}, false)
	var after := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	var market_at := after.map(func(e): return str(e["type"])).find("MARKET")
	c.check("市場の列：張姐 → 仕込む量 → 選んだあとの3行 → 鍋の素 → 市場 → 梁伯 → 「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」。PAY は無い",
		before.map(func(e): return str(e["text"])) == zhang_md.slice(0, zhang_md.size() - 3) and str(before.back()["type"]) == "PREP_TIER"
			and after.slice(0, 3).map(func(e): return str(e["text"])) == zhang_md.slice(zhang_md.size() - 3) and market_at == 4
			and after.slice(market_at + 1, market_at + 1 + liang_md.size()).map(func(e): return str(e["text"])) == liang_md
			and str(after[market_at + 1 + liang_md.size()]["text"]) == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。"
			and not (before + after).any(func(e): return str(e["type"]) == "PAY"))

	# --- 3. モブ ---
	var mobs := { "long_haul_driver": ["宵の口　長距離運転手", "夜半　夜勤警備員", ["SAVORY", "TREAT"]],
		"security_guard": ["夜半　夜勤警備員", "明け方　夜間清掃員", ["SAVORY", "BITE"]],
		"street_cleaners": ["明け方　夜間清掃員", "四組目", ["SOUR", "FILLING"]] }
	for mob_id in mobs:
		var form := ScheduleData.mob_data_for_day(mob_id, 6)
		var two := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 2))
		var one := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 1))
		var md := _md_lines("6日目_モブ3組.md", mobs[mob_id][0], mobs[mob_id][1])
		c.check("%s（6日目）：元の文（%d行）がそのまま・2杯以上の行は2杯の組だけ・OK は2通り・注文の札はデータのまま・予備の一言と予備の退店の文がある" % [mob_id, md.size()],
			two + ScheduleData.spoken_lines(form["after_talk"]) == md and two.size() == one.size() + 1 and _ok_two_ways(form["reactions"], mobs[mob_id][2])
				and form["wanted_tags"] == mobs[mob_id][2] and not (form["reactions"] as Dictionary).has("GREAT")
				and (form["spare_greet"] as Array).size() >= 3 and (form["spare_farewell"] as Array).size() == 1,
			"%d / %d" % [(two + ScheduleData.spoken_lines(form["after_talk"])).size(), md.size()])
	var spare := {}
	for mob_id in mobs:
		spare[mob_id] = ScheduleData.spoken_lines(ScheduleData.mob_data_for_day(mob_id, 6)["spare_greet"])
	c.check("予備の一言のあとの注文の行：清掃員は予備の注文の文、運転手・警備員は元の注文の文",
		spare["street_cleaners"] == ["清掃員「同じ所で待てと言われた連中が、順に食いに来てる。俺もその一人だ」", "清掃員「酸っぱい汁に、腹にたまる具を。座って待つ」"]
			and spare["long_haul_driver"] == ["運転手「前の車が動いたら、俺も動く。動くまでに、蓋のできるやつを頼む」", "店主「魚醤の汁と、いい具だな」", "運転手「ああ。待ってる間に、せめて飯の中身だけでも変えたい」"]
			and spare["security_guard"] == ["警備員「交代の順が早まった。早まると、腹の順も早まる」", "警備員「魚醤の汁に、噛める具。今日は蓋をしてくれ。交代で飯を食う」"], str(spare))
	for groups in [1, 2, 3, 4]:
		GameState.reset_for_new_game()
		GameState.day_count = 6
		var slots := [{ "name": "宵の口", "mob": ScheduleData.mob_rule_for(6, "宵の口") }, { "name": "夜半", "mob": ScheduleData.mob_rule_for(6, "夜半") },
			{ "name": "明け方", "mob": ScheduleData.mob_rule_for(6, "明け方") }]
		var by_index := Day1Events._plan_mob_groups(slots, groups * 4)
		var instances := {}
		var seq := 0
		var order := []
		for i in range(3):
			for size in by_index.get(i, []):
				var iid := "mob#%d" % seq
				seq += 1
				instances[iid] = { "type": str(ScheduleData.mob_rule_for(6, slots[i]["name"])["pool"][0]), "count": size }
				order.append(iid)
		GameState.today_plan = { "day": 6, "slots": [], "mob_instances": instances }
		var spare_ids := order.filter(func(iid): return Day1Events.is_repeat_mob_group(iid))
		var ok := true
		for iid in order:
			var form := ScheduleData.mob_data_for_day(str(instances[iid]["type"]), 6)
			var cnt := int(instances[iid]["count"])
			var want_greet := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_greet"] if spare_ids.has(iid) else form["greet"], cnt))
			var want_after := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_farewell"] if spare_ids.has(iid) else form["after_talk"], cnt))
			ok = ok and Day1Events._customer_flavor(iid)["greet"] == want_greet and _texts(Day1Events.mob_after_talk_events(iid)) == want_after
		var types_by_order := order.map(func(iid): return str(instances[iid]["type"]))
		c.check("モブが%d組の晩：各組の文と退店の文が正しい（1組なら夜勤警備員だけ・3組目は明け方の清掃員・4組目＝宵の口の2組目の運転手）" % groups,
			ok and order.size() == groups and spare_ids.size() == (1 if groups == 4 else 0)
				and (groups != 1 or types_by_order == ["security_guard"]) and (groups < 3 or types_by_order.has("street_cleaners"))
				and (groups < 4 or str(instances[spare_ids[0]]["type"]) == "long_haul_driver"), str(instances))

	# --- 4. 火事の共通場面 ---
	var events: Array = News.day_entry(6)["events"]
	var fire_md := _md_lines("6日目_火事の共通場面.md", "1．火事", "2．速報")
	var news_md := _md_lines("6日目_火事の共通場面.md", "2．速報", "3．明け方の始め")
	var dawn_md := _md_lines("6日目_火事の共通場面.md", "3．明け方の始め", "4．閉店の前")
	var close_md := _md_lines("6日目_火事の共通場面.md", "4．閉店の前", "実装メモ")
	c.check("共通場面4件：元の文の会話の行がそのまま（1 火事 %d行・2 速報と連絡 %d行・3 明け方の始め %d行・4 閉店の前 %d行）・本番の文（provisional なし）・warehouse_fire は1に" % [fire_md.size(), news_md.size(), dawn_md.size(), close_md.size()],
		events.map(func(e): return "%s@%s" % [e["id"], e["at"]]) == ["d6_fire@明け方", "d6_fire_news@明け方", "d6_dawn@明け方", "d6_close@close"]
			and _event_speech(events[0]["lines"]) == fire_md and _event_speech(events[1]["lines"]) == news_md
			and _event_speech(events[2]["lines"]) == dawn_md and _event_speech(events[3]["lines"]) == close_md
			and events.all(func(e): return not bool(e.get("provisional", true))) and events[0]["must_info"] == ["warehouse_fire"]
			and events.slice(1).all(func(e): return (e["must_info"] as Array).is_empty()))
	c.check("show_news・show_dm の位置：2 の最初に速報 02:12、張姐 02:18・02:20／3 に転送 03:05 と 03:12／4 の最後に張姐 04:55",
		events[1]["lines"][0] == { "show_news": "d6_flash_fire" } and (events[1]["lines"] as Array).has({ "show_dm": "d6_zhang_0218" })
			and (events[1]["lines"] as Array).has({ "show_dm": "d6_zhang_0220" }) and (events[2]["lines"] as Array).has({ "show_dm": "d6_dock_0305" })
			and (events[2]["lines"] as Array).has({ "show_dm": "d6_dock_0312" }) and (events[3]["lines"] as Array).back() == { "show_dm": "d6_zhang_0455" })
	GameState.reset_for_new_game()
	GameState.day_count = 6
	GameState.today_plan = { "day": 6, "slots": [], "mob_instances": { "mob#0": { "type": "security_guard", "count": 1 } } }
	var no_guard := News.event_texts(events[0], 6)
	GameState.served = [{ "customer": "mob#0", "servings": 1 }]
	var with_guard := News.event_texts(events[0], 6)
	c.check("火事の場面：夜勤警備員が来た晩は「……さっきの飯、持って帰ったばかりだぞ」、来なかった晩は「……阿強、今夜はどこの門だ」（1行だけ）",
		with_guard.has("店主「……さっきの飯、持って帰ったばかりだぞ」") and not with_guard.has("店主「……阿強、今夜はどこの門だ」")
			and no_guard.has("店主「……阿強、今夜はどこの門だ」") and not no_guard.has("店主「……さっきの飯、持って帰ったばかりだぞ」")
			and with_guard.size() == no_guard.size() and with_guard.size() == fire_md.size() - 1)
	# 鍋が尽きて早く閉めた晩（宵の口のうちに閉める）：閉店の前に4件とも出る
	var p_early = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(p_early)
	GameState.phase = GameState.Phase.OPEN
	p_early.session.set_runner_for_phase(GameState.Phase.OPEN)
	GameState.soup = null
	p_early.session.flow.force_phase(GameState.Phase.CLOSE)
	var early_texts: Array = p_early.session.flow.runner.events.filter(func(e): return str(e.get("part", "")) == "common_event").map(func(e): return str(e["text"]))
	var want_early := []
	for e in events:
		want_early.append_array(News.event_texts(e, 6))
	c.check("鍋が尽きて早く閉めた晩：閉店の前に、火事 → 速報と連絡 → 明け方の始め → 閉店の前 が1回ずつ出る", early_texts == want_early and p_early.session.played_events == DAWN_IDS + ["d6_close"])
	p_early.free()

	# --- 5. DM・ニュース・タイムライン ---
	GameState.reset_for_new_game()
	GameState.day_count = 6
	for cid in ["hooker", "streamer", "thug"]:
		GameState.customer_memory[cid] = { "favorite_known": false, "visits": [{ "day": 3, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	GameState.today_plan = { "day": 6, "slots": [{ "name": "宵の口", "customers": ["hooker"], "regular_id": "hooker" },
		{ "name": "夜半", "customers": ["streamer"], "regular_id": "streamer" }, { "name": "明け方", "customers": ["thug"], "regular_id": "thug" }],
		"mob_instances": {}, "demand_center": 9 }
	var morning := Dm.delivered_for_day(6).filter(func(x): return not bool(x.get("preview", false)))
	c.check("6日目の朝のDM：張姐 6:35・セティヤ 7:10・ニカ 7:40。セティヤ・ニカの来店予告は出ない（レックスの予告は今の仕組みのまま）",
		morning.map(func(x): return "%s %s" % [x["from"], x["time"]]) == ["張姐 6:35", "セティヤ 7:10", "ニカ 7:40"]
			and not Dm.delivered_for_day(6).any(func(x): return bool(x.get("preview", false)) and ["hooker", "streamer"].has(str(x.get("subject", "")))),
		str(Dm.delivered_for_day(6).map(func(x): return x["id"])))
	var night_items := Dm.items_for_day(6).filter(func(x): return Dm.is_night(x))
	c.check("火事のあとのDM9件：時刻は台本のとおり・全部 after_event（02:xx は火事の場面、03:xx は明け方の始め、04:55 は閉店の前）・本番の文",
		night_items.map(func(x): return "%s %s %s" % [x["time"], x["from"], x["after_event"]]) == ["02:18 張姐 d6_fire", "02:20 張姐 d6_fire", "02:26 梁伯 d6_fire",
			"02:34 セティヤ d6_fire", "02:36 セティヤ d6_fire", "03:05 港湾労働者 d6_dawn", "03:12 港湾労働者 d6_dawn", "03:40 海隆鮮貨 d6_dawn", "04:55 張姐 d6_close"]
			and night_items.all(func(x): return not bool(x.get("provisional", true))), str(night_items.map(func(x): return x["time"])))
	c.check("場面の前：火事のあとのDMは1件も届いていない", not _ids(Dm.inbox(6)).any(func(id): return _ids(night_items).has(id)))
	c.check("全部再生したあと：火事のあとのDM9件が届く（セティヤの2件は、会っている客なので届く）",
		_ids(night_items).all(func(id): return _ids(Dm.inbox(6, {}, DAWN_IDS + ["d6_close"])).has(id)))
	var nika_post: Dictionary = Sns.posts().filter(func(x): return str(x["id"]) == "d6_exposure_test_0242")[0]
	var forward := Dm.item_by_id(6, "d6_dock_0305")
	c.check("転送（03:05）の本文にニカの 02:42 の投稿の全文が入り、写真の説明も投稿と同じ（差出人は条件なしの「港湾労働者」）",
		str(forward["text"]).contains(str(nika_post["text"])) and str(forward["photo"]) == str(nika_post["photo"]) and str(forward["from_kind"]) == "npc"
			and str(forward["text"]).begins_with("これ、見た？"))
	var news6: Array = News.day_entry(6)["news"]
	c.check("ニュース：朝の記事4本（仮の d6_forced は無い・印なし）と速報2本（02:12 は火事の場面のあと・02:55 は明け方の始めのあと）。どれも本番の文・must_info なし",
		news6.size() == 6 and news6.filter(func(x): return not News.is_flash(x)).size() == 4 and not _ids(news6).has("d6_forced")
			and news6.filter(func(x): return News.is_flash(x)).map(func(x): return "%s %s" % [x["time"], x["after_event"]]) == ["02:12 d6_fire", "02:55 d6_dawn"]
			and news6.all(func(x): return (x["must_info"] as Array).is_empty() and not bool(x.get("provisional", true))))
	c.check("6日目の必須情報の印は火事（warehouse_fire）の1つだけで、火事の場面に付いている（朝の記事には付けない）",
		News.catalog().filter(func(x): return int(x["day"]) == 6).map(func(x): return x["id"]) == ["warehouse_fire"]
			and News.delivered_days()["warehouse_fire"] == [6])
	c.check("データの検査に問題が無い（ニュース・DM・タイムライン）", News.problems().is_empty() and Dm.problems().is_empty() and Sns.problems().is_empty(),
		str(News.problems()) + str(Dm.problems()) + str(Sns.problems()))

	# --- 6. 文の検査 ---
	var all6 := JSON.stringify(talk) + JSON.stringify(News.day_entry(6)) + JSON.stringify(Dm.items_for_day(6))
	for sc in scenes:
		all6 += JSON.stringify(ScheduleData.episode_data(sc[0], sc[1]))
	for mob_id in mobs:
		all6 += JSON.stringify(ScheduleData.mob_data(mob_id)["days"]["6"])
	c.check("6日目の会話・共通場面・DM・ニュースに〔ゲーム〕〔演出〕の文が混ざらない", not all6.contains("〔ゲーム〕") and not all6.contains("〔"))
	var before_fire := JSON.stringify(talk["parts"]) + JSON.stringify(News.visible_news(6, 6, []))   # 書き手用の note は画面に出ないので見ない + JSON.stringify(Dm.inbox(6).filter(func(x): return int(x["day"]) == 6))
	for sc in scenes.slice(0, 2):
		before_fire += JSON.stringify(ScheduleData.episode_data(sc[0], sc[1]))
	for mob_id in ["long_haul_driver", "security_guard"]:
		before_fire += JSON.stringify(ScheduleData.mob_data(mob_id)["days"]["6"])
	for x in Sns.posts().filter(func(p): return int(p["day"]) == 6 and not p.has("requires")):
		before_fire += str(x["text"])
	var fire_words := ["火事", "火災", "放火", "燃え"].filter(func(w): return before_fire.contains(w))
	c.check("火事の前に見える物（市場・セティヤ・ニカ・運転手・警備員・朝のDM・朝の記事・火事の前の投稿）に、火事の語（火事・火災・放火・燃え）が無い", fire_words.is_empty(), str(fire_words))

	# --- 7. 6日目を朝から閉店まで本番の画面で通す ---
	_play_day6(t, c)

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()


func _play_day6(t: SceneTree, c: TestCheck) -> void:
	ReadState.reset("user://test_read_day6_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var topped := {}
	while GameState.day_count < 6 and guard < 30000:
		guard += 1
		if GameState.day_count == 5 and not topped.has(5):
			topped[5] = true
			GameState.money += 500   # このテストの中だけ：自動の遊び手は所持金が少なく、具を買えずに全部断るため（day5_script_test と同じ）
		if play.step() == "":
			break
	c.check("（前提）Day1〜5 を遊び、Day6 の朝へ進んだ", GameState.day_count == 6)
	GameState.money += 500   # このテストの中だけ
	var shown := []
	var shown_keys := {}
	var bracket_shown := []
	var plan_slots: Array = []
	var plan_mobs := {}
	var served_at_close := []
	var expected_common := []
	var dm_tag_ok := true
	guard = 0
	while GameState.day_count == 6 and guard < 12000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if GameState.phase == GameState.Phase.OPEN and plan_slots.is_empty():
			plan_slots = (GameState.today_plan["slots"] as Array).duplicate(true)
			plan_mobs = (GameState.today_plan["mob_instances"] as Dictionary).duplicate(true)
		if s.flow.runner != null and str(line.get("text", "")) != "" and str(line.get("type", "")) != "REACT" and not ["shop_talk", "hearty", "penalty"].has(str(line.get("part", ""))):   # UI準備AG：店の会話・具だくさんの一言は別に確かめる
			var ev = s.flow.runner.current()
			var key := "%d|%d|%d|%d|%s" % [GameState.phase, s.open.slot_index if s.open != null else -1, s.open.index if s.open != null else -1,
				s.flow.runner.index, str(line.get("text", ""))]
			if not shown_keys.has(key):
				shown_keys[key] = true
				var name := str(line.get("speaker_name", ""))
				if ev is Dictionary and str((ev as Dictionary).get("dm_id", "")) != "":
					dm_tag_ok = dm_tag_ok and name.ends_with("（DM）")
				shown.append({ "text": name.trim_suffix("（DM）") + str(line.get("text", "")), "part": str(line.get("part", "")), "slot": s.open.current_slot_name() if s.open != null and GameState.phase == GameState.Phase.OPEN else "" })
		if GameState.phase == GameState.Phase.CLOSE and served_at_close.is_empty():
			served_at_close = GameState.served.duplicate(true)
			for e in News.day_entry(6)["events"]:
				expected_common.append_array(News.event_texts(e, 6))
		if play.step() == "":
			break
	c.check("Day6 を閉店まで遊び、Day7 の朝へ進んだ", GameState.day_count == 7, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("会話枠に〔〕の文が一度も出ない", bracket_shown.is_empty(), str(bracket_shown))
	c.check("会話枠に出した DM の名前の札は「差出人（DM）」", dm_tag_ok)
	var common := shown.filter(func(x): return str(x["part"]) == "common_event").map(func(x): return str(x["text"]))
	c.check("火事の共通場面の行（%d行）が、火事 → 速報と連絡 → 明け方の始め → 閉店の前 の順に1回ずつ出た" % expected_common.size(),
		common == expected_common and not expected_common.is_empty(), "%s / %s" % [str(common.slice(0, 3)), str(expected_common.slice(0, 3))])
	var first_fire := -1
	for i in range(shown.size()):
		if str(shown[i]["part"]) == "common_event":
			first_fire = i
			break
	var mob_types := []
	var midnight_or_earlier_after_fire := false
	var cleaner_before_fire := false
	for i in range(shown.size()):
		var sl := str(shown[i]["slot"])
		if i > first_fire and (sl == "宵の口" or sl == "夜半"):
			midnight_or_earlier_after_fire = true
		if i < first_fire and str(shown[i]["text"]).begins_with("清掃員「"):
			cleaner_before_fire = true
	for id in plan_mobs:
		mob_types.append("%s×%d" % [str(plan_mobs[id]["type"]), int(plan_mobs[id]["count"])])
	c.check("火事の場面は夜半の客がみんな帰ったあと（宵の口・夜半の行は火事の場面より前）。清掃員の行は火事の場面より前に出ない（モブ %s）" % str(mob_types),
		first_fire >= 0 and not midnight_or_earlier_after_fire and not cleaner_before_fire)
	root.queue_free()
