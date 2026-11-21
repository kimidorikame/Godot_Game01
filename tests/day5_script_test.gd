extends RefCounted
## 中身AB：5日目の本番の文（planning/scenario/day5/ の8本）をゲームのデータに入れたことの検証。
##   1. データ：5日目の場面（hooker_03・streamer_02・officer_03）・モブ3組（days."5"）・市場の場面（day5_market）に印の問題が無い・
##      元の文の行が抜けなく入っている・OK は外れた札で2通り・注文の札と好物はデータのまま（今日の頼みは無い）
##   2. 市場：張姐（仕込む量の前と、選んだあとの2行）→ 市場 → 市場を出る → 梁伯。払い方は今までどおり
##   3. モブ：1組・2組・3組の晩は各職種の1組目の文、4組目（宵の口の2組目の荷捌き人夫）は予備の一言と予備の退店の文。
##      港湾労働者は、2杯以上の晩だけ労働者Aの行（注文のあとの2行・食事の終わりの3行）が出る
##   4. DM（5日目）：張姐・セティヤ・ニカ・リン。常連3人の来店予告は出ない
##   5. ニュース（5日目）：5本・2本目に must_info（contract_shift）
##   6. 文の検査：5日目の会話・ニュース・投稿に「火事」「放火」「煙」が無い。リンの会話・DMに裏をにおわせる語が無い
##   7. 5日目を朝から閉店まで本番の画面で通す：元の文の行が順に出る・〔〕が出ない・反応は判定どおりの1行


## 元の文（.md）の「名前「セリフ」」の行（〔ゲーム〕の行・表・見出し・反応の行を除く）。from_heading の見出しから to_heading の見出しの前まで。
func _md_lines(file: String, from_heading: String, to_heading: String) -> Array:
	var text := FileAccess.get_file_as_string("res://planning/scenario/day5/" + file)
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


## 行の配列（文字列と { min_count, line }）を、JSON にして文字列の検査に使う。
func _all_text(value) -> String:
	return JSON.stringify(value)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	News.clear_cache()
	GameState.reset_for_new_game()
	GameState.day_count = 5

	# --- 1. データ ---
	var scenes := [["hooker", "hooker_03", "5日目_夜の女.md", ["BITTER", "TREAT"], "pickled_lime"],
		["streamer", "streamer_02", "5日目_配信者.md", ["MELLOW", "BITE"], "shrimp"],
		["officer", "officer_03", "5日目_新人警官.md", ["SOUR", "BITE"], "rice_noodle"]]
	for sc in scenes:
		var ep := ScheduleData.episode_data(sc[0], sc[1])
		var lines := _texts(Day1Events._talk(sc[0], ep["greet"])) + _texts(Day1Events._scene_lines("body", sc[0], ep["body"]))
		var md := _md_lines(sc[2], "本編", "実装メモ")
		c.check("%s：場面データの形・印に問題が無い・元の文の行（%d行）がそのまま・OK は2通り・今日の頼み無し・注文と好物はデータのまま %s" % [sc[1], md.size(), str(sc[3])],
			ScheduleData.scene_problems(ep).is_empty() and lines == md and _ok_two_ways(ep["reactions"], sc[3])
				and ScheduleData.episode_today_request(sc[0], sc[1]).is_empty() and ScheduleData.customer_profile(sc[0])["wanted_tags"] == sc[3]
				and str(ScheduleData.customer_profile(sc[0])["favorite"]) == sc[4] and str(ep.get("source", "")).ends_with(sc[2]),
			"%s / %d / %d" % [str(ScheduleData.scene_problems(ep)), lines.size(), md.size()])
	c.check("ニカ・リンは最初から名前で出る（名乗る前の名前の行・名乗りの印は無い）",
		not _all_text(ScheduleData.episode_data("streamer", "streamer_02")).contains("初めての客") and not _all_text(ScheduleData.episode_data("streamer", "streamer_02")).contains("reveal_name")
			and not _all_text(ScheduleData.episode_data("officer", "officer_03")).contains("警官「") and not _all_text(ScheduleData.episode_data("officer", "officer_03")).contains("reveal_name"))
	c.check("ニカの場面：店主が映像の男を「レックスのところの兄貴分」と見分ける行がある",
		(ScheduleData.episode_data("streamer", "streamer_02")["body"] as Array).has("店主「……レックスのところの兄貴分だな」"))
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	var grade_of := func(additions: Array, wanted: Array, favorite: String) -> String: return str(Judge.grade({ "additions": additions }, GameState.soup, { "wanted_tags": wanted, "favorite": favorite })["grade"])
	c.check("手がかりと札：セティヤの GREAT＝苦瓜＋ごちそうの具＋塩漬けライム・ニカの GREAT＝ココナッツミルク＋歯ごたえの具＋海老（海老は歯ごたえの代わりにならない）・リンの GREAT＝塩漬けライム＋歯ごたえの具＋米麺",
		grade_of.call(["bitter_melon", "clam", "pickled_lime"], ["BITTER", "TREAT"], "pickled_lime") == "GREAT"
			and grade_of.call(["bitter_melon", "clam"], ["BITTER", "TREAT"], "pickled_lime") != "GREAT"
			and grade_of.call(["coconut_milk", "cartilage", "shrimp"], ["MELLOW", "BITE"], "shrimp") == "GREAT"
			and grade_of.call(["coconut_milk", "shrimp"], ["MELLOW", "BITE"], "shrimp") != "GREAT"
			and grade_of.call(["pickled_lime", "cartilage", "rice_noodle"], ["SOUR", "BITE"], "rice_noodle") == "GREAT"
			and grade_of.call(["pickled_lime", "rice_noodle"], ["SOUR", "BITE"], "rice_noodle") != "GREAT")
	# 市場
	var talk := ScheduleData.talk_data("day5_market")
	var parts: Array = talk.get("parts", [])
	var zhang_md := _md_lines("5日目_昼市場.md", "張記肉類加工", "炭屋")
	var liang_md := _md_lines("5日目_昼市場.md", "共同水場", "実装メモ")
	c.check("市場の場面：張姐（%d行。仕込む量の印の前は「で、今日はどれ位仕込む？」まで・あとに2行。必須情報の印 contract_shift）と梁伯（%d行。払う印なし）・サミル・羅文は入れない" % [zhang_md.size(), liang_md.size()],
		parts.size() == 2 and parts[0]["lines"].filter(func(l): return l is String) == zhang_md and parts[0]["lines"][zhang_md.size() - 2] is Dictionary
			and str(parts[0]["lines"][zhang_md.size() - 3]).ends_with("で、今日はどれ位仕込む？」") and parts[0]["must_info"] == ["contract_shift"]
			and str(parts[1]["when"]) == "exit" and parts[1]["lines"] == liang_md and Rules.day_overrides(5).get("market_scene", "") == "day5_market"
			and not _all_text(talk).contains("サミル「") and not _all_text(talk).contains("羅文「"))
	var before := Day1Events.prep_events({}, false)
	var after := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	var types: Array = after.map(func(e): return str(e["type"]))
	var market_at := types.find("MARKET")
	c.check("市場の列：張姐 → 仕込む量 → 選んだあとの2行 → 鍋の素 → 市場 → 梁伯 → 「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」。PAY は無い（払い方は今までどおり）",
		before.map(func(e): return str(e["text"])) == zhang_md.slice(0, zhang_md.size() - 2) and str(before.back()["type"]) == "PREP_TIER"
			and after.slice(0, 2).map(func(e): return str(e["text"])) == zhang_md.slice(zhang_md.size() - 2) and str(after[2]["type"]) == "ADD_ITEM" and market_at == 3
			and after.slice(market_at + 1, market_at + 1 + liang_md.size()).map(func(e): return str(e["text"])) == liang_md
			and str(after[market_at + 1 + liang_md.size()]["text"]) == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。"
			and not (before + after).any(func(e): return str(e["type"]) == "PAY") and not Day1Events.market_exit_pays_in_scene())

	# --- 3. モブ ---
	var mobs := { "market_porter": ["宵の口　市場の荷捌き人夫", "夜半　夜勤警備員", ["HOT", "FILLING"], 1, 0],
		"security_guard": ["夜半　夜勤警備員", "明け方　港湾労働者", ["SAVORY", "BITE"], 1, 0],
		"dock_workers": ["明け方　港湾労働者", "四組目", ["HOT", "POWER"], 2, 3] }
	for mob_id in mobs:
		var form := ScheduleData.mob_data_for_day(mob_id, 5)
		var two := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 2))
		var one := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 1))
		var two_after := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["after_talk"], 2))
		var one_after := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["after_talk"], 1))
		var md := _md_lines("5日目_モブ3組.md", mobs[mob_id][0], mobs[mob_id][1])
		c.check("%s（5日目）：元の文（%d行）がそのまま・2杯以上の行は2杯の組だけ（挨拶 %d行・食事の終わり %d行）・OK は2通り・注文の札はデータのまま・予備の一言と予備の退店の文がある" % [mob_id, md.size(), mobs[mob_id][3], mobs[mob_id][4]],
			two + two_after == md and two.size() == one.size() + mobs[mob_id][3] and two_after.size() == one_after.size() + mobs[mob_id][4]
				and _ok_two_ways(form["reactions"], mobs[mob_id][2]) and form["wanted_tags"] == mobs[mob_id][2]
				and not (form["reactions"] as Dictionary).has("GREAT") and (form["spare_greet"] as Array).size() >= 2 and (form["spare_farewell"] as Array).size() == 1,
			"%d / %d" % [(two + two_after).size(), md.size()])
	# 予備の一言のあとの注文の行（11/21 に表へ足した「予備の注文の文」の列）：警備員・港湾労働者Bは予備の注文の文、荷捌き人夫は元の注文の文。店主「今日は何にする」の行は無い
	var porter_spare: Array = ScheduleData.mob_data_for_day("market_porter", 5)["spare_greet"]
	var guard_spare: Array = ScheduleData.mob_data_for_day("security_guard", 5)["spare_greet"]
	var dock_spare: Array = ScheduleData.mob_data_for_day("dock_workers", 5)["spare_greet"]
	c.check("予備の一言のあとの注文の行：警備員・港湾労働者Bは予備の注文の文、荷捌き人夫は元の注文の文（店主「何にする」→ 人夫の注文）。そのあとに2杯以上の行",
		porter_spare.slice(0, 3) == ["人夫「荷は動かしてきた。俺の飯は、ここで止めて食う」", "店主「何にする」", "人夫「辛いの。具は腹にたまるやつ。今日の休憩、あとが短えから、食う方は長く持たせたい」"]
			and guard_spare.slice(0, 2) == ["警備員「交代が早く来た。早く来る奴は、だいたい腹を空かせてない」", "警備員「魚醤の汁に、噛みごたえのある具を。座って食ってく」"]
			and dock_spare.slice(0, 2) == ["労働者B「さっき来た奴ら、同じ班だろ。俺も『待て』のまんまだって」", "労働者B「辛いの、肉っ気のあるやつ。待ってる間に食っとく」"]
			and porter_spare.size() == 4 and guard_spare.size() == 3 and dock_spare.size() == 4
			and dock_spare.filter(func(x): return x is Dictionary).size() == 2 and not (porter_spare + guard_spare + dock_spare).has("店主「今日は何にする」"), str([porter_spare, guard_spare, dock_spare]))
	# 港湾労働者：1杯の晩は労働者Bだけ、2杯以上の晩は労働者Aも（注文のあとの2行・食事の終わりの3行）。椀のあとの会話でも杯数で選ぶ
	for count in [1, 2, 3]:
		GameState.reset_for_new_game()
		GameState.day_count = 5
		GameState.today_plan = { "day": 5, "slots": [], "mob_instances": { "mob#0": { "type": "dock_workers", "count": count } } }
		var greet: Array = Day1Events._customer_flavor("mob#0")["greet"]
		var after_lines := _texts(Day1Events.mob_after_talk_events("mob#0"))
		var a_lines := (greet + after_lines).filter(func(x): return str(x).begins_with("労働者A「"))
		c.check("港湾労働者が%d杯の晩：労働者Aの行は %d 行（2杯以上の晩だけ。注文のあとの2行のうち A は1行・食事の終わりの3行のうち A は2行）" % [count, 0 if count == 1 else 3],
			a_lines.size() == (0 if count == 1 else 3) and after_lines.has("労働者B「割らずに持ってく。今夜は、卵の方を待たせる」")
				and (count >= 2) == after_lines.has("労働者A「今は椀を持っとけ。冷めるぞ」")
				and (count >= 2) == greet.has("労働者B「そっちだけ連絡が来てるかもしれねえじゃん！」"), str(greet + after_lines))
	# 1〜4組の晩：組の配り方（1組目→夜半、2組目→宵の口、3組目→明け方、4組目→宵の口）で、4組目だけ予備の一言・予備の退店の文
	for groups in [1, 2, 3, 4]:
		GameState.reset_for_new_game()
		GameState.day_count = 5
		var slots := [{ "name": "宵の口", "mob": ScheduleData.mob_rule_for(5, "宵の口") }, { "name": "夜半", "mob": ScheduleData.mob_rule_for(5, "夜半") },
			{ "name": "明け方", "mob": ScheduleData.mob_rule_for(5, "明け方") }]
		var by_index := Day1Events._plan_mob_groups(slots, groups * 4)   # 4杯ずつの組を groups 組
		var instances := {}
		var seq := 0
		var order := []
		for i in range(3):
			for size in by_index.get(i, []):
				var iid := "mob#%d" % seq
				seq += 1
				instances[iid] = { "type": str(ScheduleData.mob_rule_for(5, slots[i]["name"])["pool"][0]), "count": size }
				order.append(iid)
		GameState.today_plan = { "day": 5, "slots": [], "mob_instances": instances }
		var spare_ids := order.filter(func(iid): return Day1Events.is_repeat_mob_group(iid))
		var ok := true
		for iid in order:
			var form := ScheduleData.mob_data_for_day(str(instances[iid]["type"]), 5)
			var cnt := int(instances[iid]["count"])
			var want_greet := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_greet"] if spare_ids.has(iid) else form["greet"], cnt))
			var want_after := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_farewell"] if spare_ids.has(iid) else form["after_talk"], cnt))
			ok = ok and Day1Events._customer_flavor(iid)["greet"] == want_greet and _texts(Day1Events.mob_after_talk_events(iid)) == want_after
		var types_by_order := order.map(func(iid): return str(instances[iid]["type"]))
		c.check("モブが%d組の晩：各組の文と退店の文が正しい（予備の一言で来る組 %d組。1組なら夜勤警備員だけ・4組目＝宵の口の2組目の荷捌き人夫だけ）" % [groups, spare_ids.size()],
			ok and order.size() == groups and spare_ids.size() == (1 if groups == 4 else 0)
				and (groups != 1 or types_by_order == ["security_guard"])
				and (groups < 4 or str(instances[spare_ids[0]]["type"]) == "market_porter"), str(instances))

	# --- 4. DM ---
	GameState.reset_for_new_game()
	GameState.day_count = 5
	for cid in ["hooker", "streamer", "officer"]:
		GameState.customer_memory[cid] = { "favorite_known": false, "visits": [{ "day": 3, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	GameState.today_plan = { "day": 5, "slots": [{ "name": "宵の口", "customers": ["hooker"], "regular_id": "hooker" },
		{ "name": "夜半", "customers": ["streamer"], "regular_id": "streamer" }, { "name": "明け方", "customers": ["officer"], "regular_id": "officer" }],
		"mob_instances": {}, "demand_center": 9 }
	var dm := Dm.delivered_for_day(5)
	c.check("5日目の朝のDM：張姐 6:35・セティヤ 7:05（苦い方）・ニカ 7:35（白い汁）・リン 8:00（酸っぱい汁）。常連3人の来店予告は出ない・仮の d5_thug は無い・本番の文",
		dm.map(func(x): return "%s %s" % [x["from"], x["time"]]) == ["張姐 6:35", "セティヤ 7:05", "ニカ 7:35", "リン 8:00"]
			and str(dm[1]["text"]).contains("苦い方") and str(dm[2]["text"]).contains("白い汁") and str(dm[3]["text"]).contains("酸っぱい汁")
			and not dm.any(func(x): return bool(x.get("preview", false))) and not Dm.items_for_day(5).any(func(x): return str(x["id"]) == "d5_thug")
			and Dm.items_for_day(5).all(func(x): return not bool(x.get("provisional", false)) and str(x.get("hint", "")) == "none"),
		str(dm.map(func(x): return x["id"])))
	GameState.customer_memory.erase("streamer")
	c.check("会っていない客（ニカ）のDMは届かない", not Dm.delivered_for_day(5).any(func(x): return str(x["id"]) == "d5_streamer"))

	# --- 5. ニュース ---
	var day5_news: Array = News.day_entry(5)["news"]
	c.check("5日目は本番の5本（5日目_ニュース.md）：provisional なし・2本目だけ must_info（contract_shift）・1本目は印なし・3本目は消防の注意・仮の d5_removal・d5_rights は無い",
		day5_news.size() == 5 and day5_news.all(func(i): return not bool(i.get("provisional", false)))
			and day5_news.map(func(i): return str(i["id"])) == ["d5_detour_full", "d5_window_notice", "d5_aisle_safety", "d5_paper_signs", "d5_laundry_pairs"]
			and day5_news[1]["must_info"] == ["contract_shift"] and (day5_news[0]["must_info"] as Array).is_empty()
			and day5_news.slice(2).all(func(i): return (i["must_info"] as Array).is_empty())
			and str(day5_news[2]["headline"]) == "【安全】倉庫の通路に荷、消防が注意呼びかけ　「消火設備の前を空けて」"
			and day5_news.all(func(i): return (i["body"] as Array).size() >= 4),
		str(day5_news.map(func(i): return i["id"])))

	# --- 6. 文の検査 ---
	var day5_text := _all_text(ScheduleData.talk_data("day5_market")) + _all_text(day5_news) + _all_text(Dm.items_for_day(5))
	for sc in scenes:
		day5_text += _all_text(ScheduleData.episode_data(sc[0], sc[1]))
	for mob_id in mobs:
		day5_text += _all_text(ScheduleData.mob_data(mob_id)["days"]["5"])
	for x in Sns.posts().filter(func(p): return int(p["day"]) == 5):
		day5_text += str(x["text"])
	var fire_words := ["火事", "放火", "煙"].filter(func(w): return day5_text.contains(w))
	c.check("5日目の会話・ニュース・DM・投稿の本文に「火事」「放火」「煙」が無い（火事は6日目の夜）", fire_words.is_empty(), str(fire_words))
	var lin_text := _all_text(ScheduleData.episode_data("officer", "officer_03")) + _all_text(Dm.items_for_day(5).filter(func(x): return str(x["from"]) == "リン"))
	var lin_words := ["報告", "指示", "接触", "暗号", "組織", "上の人"].filter(func(w): return lin_text.contains(w))
	c.check("リンの会話・DMに、裏をにおわせる語（報告・指示・接触・暗号・組織・上の人）が無い（裏はタイムラインの暗号だけ）", lin_words.is_empty(), str(lin_words))

	# --- 7. 5日目を朝から閉店まで本番の画面で通す ---
	_play_day5(t, c)

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()


func _play_day5(t: SceneTree, c: TestCheck) -> void:
	ReadState.reset("user://test_read_day5_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while GameState.day_count < 5 and guard < 22000:
		guard += 1
		if play.step() == "":
			break
	c.check("（前提）Day1〜4 を遊び、Day5 の朝へ進んだ", GameState.day_count == 5)
	# このテストの中だけ：自動の遊び手は5日目の朝に所持金が少なく（具を買えず全部断る）、反応と椀のあとの会話を通せないので、所持金を足す
	GameState.money += 500
	var inbox := Dm.inbox(5).filter(func(x): return int(x["day"]) == 5)
	c.check("Day5 の朝のDM：張姐・セティヤ・ニカ・リン。常連3人の予告は無い",
		["d5_market", "d5_hooker", "d5_streamer", "d5_officer"].all(func(id): return inbox.map(func(x): return str(x["id"])).has(id))
			and not inbox.any(func(x): return ["hooker", "streamer", "officer"].has(str(x.get("subject", "")))), str(inbox.map(func(x): return x["id"])))
	var shown_lines := []
	var shown_keys := {}
	var bracket_shown := []
	var reactions := []
	var reacted := {}
	var plan_slots: Array = []
	var plan_mobs := {}
	var served_at_close := []
	guard = 0
	while GameState.day_count == 5 and guard < 9000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if GameState.phase == GameState.Phase.OPEN and plan_slots.is_empty():
			plan_slots = (GameState.today_plan["slots"] as Array).duplicate(true)
			plan_mobs = (GameState.today_plan["mob_instances"] as Dictionary).duplicate(true)
		if str(line.get("type", "")) == "REACT" and str(line.get("text", "")) != "" and s.open != null:
			var key := "%d|%d|%d" % [s.open.slot_index, s.open.index, s.flow.runner.index]
			if not reacted.has(key):
				reacted[key] = true
				var ev: Dictionary = s.flow.runner.current()
				reactions.append({ "grade": str(s.open.current_bowl.get("result", "")), "text": s.current_reaction_text(),
					"pool": ev.get("reactions", {}), "customer": str(ev.get("customer", "")) })
		var name := str(line.get("speaker_name", ""))
		if s.flow.runner != null and str(line.get("text", "")) != "" and str(line.get("type", "")) != "REACT":
			var line_key := "%d|%d|%d|%d|%s" % [GameState.phase, s.open.slot_index if s.open != null else -1, s.open.index if s.open != null else -1,
				s.flow.runner.index, str(line.get("text", ""))]
			if not shown_keys.has(line_key):
				shown_keys[line_key] = true
				shown_lines.append(name + str(line.get("text", "")))
		if GameState.phase == GameState.Phase.CLOSE and served_at_close.is_empty():
			served_at_close = GameState.served.duplicate(true)
		if play.step() == "":
			break
	c.check("Day5 を閉店まで遊び、Day6 の朝へ進んだ", GameState.day_count == 6, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("会話枠に〔〕の文（〔ゲーム〕・実装メモ）が一度も出ない", bracket_shown.is_empty(), str(bracket_shown))
	var talk: Array = ScheduleData.talk_data("day5_market")["parts"]
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
				var form := ScheduleData.mob_data_for_day(type_id, 5)
				var repeat := false
				for other in plan_mobs:
					repeat = repeat or (int(str(other).trim_prefix("mob#")) < int(str(id).trim_prefix("mob#")) and str(plan_mobs[other]["type"]) == type_id)
				expected.append_array(ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_greet"] if repeat else form["greet"], count)))
				if not declined.has(str(id)):
					expected.append_array(ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_farewell"] if repeat else form["after_talk"], count)))
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
	c.check("Day5 の元の文の行（%d行）が、張姐→梁伯→宵の口→夜半→明け方の順に、抜けも重なりも無く出た（モブ %s）" % [expected.size(), str(mob_types)],
		first_diff == -1, "最初に違う行 %d：%s ／ 期待 %s" % [first_diff, str(got[first_diff]) if first_diff >= 0 and first_diff < got.size() else "（無い）",
			str(expected[first_diff]) if first_diff >= 0 and first_diff < expected.size() else "（無い）"])
	var react_ok := true
	for r in reactions:
		var pool: Array = (r["pool"] as Dictionary).get(r["grade"], []).duplicate()
		if r["grade"] == "OK" and (r["pool"] as Dictionary).get("OK_MISSING") is Dictionary:
			for tag in r["pool"]["OK_MISSING"]:
				pool.append_array(r["pool"]["OK_MISSING"][tag])
		react_ok = react_ok and pool.has(r["text"]) and not str(r["text"]).contains("\n") and not str(r["text"]).contains("〔")
	c.check("反応は、判定の結果の段の元の文の1行だけ（OK は外れた札の文も。%d回）" % reactions.size(), react_ok and reactions.size() >= 2,
		str(reactions.map(func(r): return "%s %s %s" % [r["customer"], r["grade"], r["text"]])))
	root.queue_free()
