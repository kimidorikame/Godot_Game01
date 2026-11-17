extends RefCounted
## 中身Z2：1〜3日目の直し。
##   1. OK の反応を外れた札で2通り（OK_MISSING）：1日目（阿強の3杯・レックス・安宿の夜勤受付・ターニャ婆）・2日目（新人警官・レックス・
##      セティヤ・モブ3組）・3日目。札はその注文（杯の札・今日の頼み・基本の注文）のどれかで、2つの札に1つずつ。OK の文は2つのうち1つ目
##   2. モブの名前：共同洗濯場の夜番 → 港のホテルの夜番（id laundry_night はそのまま）。1〜3日目の会話・予告DMに旧名が残っていない
##   3. ニュースの本文（1〜3日目）：各日4本・どの記事も4段落・見出しと必須情報の印は今のまま
##   4. タイムラインのニカの 23:00 は動画（photo_kind "video"）。スマホの画面に「［動画：…］」と出る
##   5. 2日目の阿強のDMは、1日目の3杯目を出した道（facts.day1_takeout_served）だけ


func _labels(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_labels(child, out)
	return out


## OK_MISSING の形：札2つ（注文の2つの札に1つずつ）・どれも1行・OK の文はそのうちの1つ・GREAT/GOOD/BAD は1行のまま。
func _ok_two_ways(reactions: Dictionary, wanted: Array) -> bool:
	var missing = reactions.get("OK_MISSING", null)
	if not (missing is Dictionary) or (missing as Dictionary).size() != 2:
		return false
	var keys: Array = (missing as Dictionary).keys()
	keys.sort()
	var want := wanted.duplicate()
	want.sort()
	if keys != want:
		return false
	for tag in missing:
		if not (missing[tag] is Array) or (missing[tag] as Array).size() != 1:
			return false
	return (reactions["OK"] as Array).size() == 1 and (missing.values() as Array).has(reactions["OK"]) and missing[keys[0]] != missing[keys[1]]


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	News.clear_cache()
	GameState.reset_for_new_game()

	# --- 1. OK の2通り ---
	var cups := ScheduleData.episode_cups("delivery_man", "delivery_man_01")
	c.check("1日目の阿強：3杯とも OK が2通り（1・2杯目＝辛い／スタミナ・3杯目＝うましお／やさしい）",
		_ok_two_ways(cups[0]["reactions"], ["HOT", "POWER"]) and _ok_two_ways(cups[1]["reactions"], ["HOT", "POWER"])
			and _ok_two_ways(cups[2]["reactions"], ["SAVORY", "GENTLE"]))
	c.check("1日目の阿強の1杯目：辛さは合った（スタミナが外れた）・スタミナは合った（辛さが外れた）の文",
		str(cups[0]["reactions"]["OK_MISSING"]["POWER"][0]) == "阿強「辛さはこれ。でも肉は？　腹に力が入るやつって言ったじゃん」"
			and str(cups[0]["reactions"]["OK_MISSING"]["HOT"][0]) == "阿強「肉はうまいんだけど、赤いの足りなくない？　一番赤いやつって言ったのに」")
	var scenes := [["thug", "thug_01", ["MELLOW", "GENTLE"]], ["granny", "granny_01", ["SAVORY", "FILLING"]], ["officer", "officer_01", ["SOUR", "BITE"]],
		["thug", "thug_02", ["MELLOW", "POWER"]], ["hooker", "hooker_01", ["BITTER", "TREAT"]],
		["delivery_man", "delivery_man_02", ["HOT", "FILLING"]], ["streamer", "streamer_01", ["MELLOW", "BITE"]], ["hooker", "hooker_02", ["MELLOW", "TREAT"]]]
	for sc in scenes:
		var ep := ScheduleData.episode_data(sc[0], sc[1])
		c.check("%s：OK が2通り（%s）・場面の検査に問題なし" % [sc[1], str(sc[2])], _ok_two_ways(ep["reactions"], sc[2]) and ScheduleData.scene_problems(ep).is_empty(),
			str(ScheduleData.scene_problems(ep)))
	var setiya2: Dictionary = ScheduleData.episode_data("hooker", "hooker_01")["reactions"]["OK_MISSING"]
	c.check("2日目のセティヤ：苦いは合った（ごちそうが外れた）・ごちそうは合った（苦いが外れた）の文",
		str(setiya2["TREAT"][0]).begins_with("セティヤ「苦いのは、いつものね。") and str(setiya2["BITTER"][0]).begins_with("セティヤ「具は贅沢で嬉しいわ。"))
	c.check("2日目のレックスは今日の頼み（まろやか＋スタミナ）に対する2通り",
		str(ScheduleData.episode_data("thug", "thug_02")["reactions"]["OK_MISSING"]["POWER"][0]).contains("肉はどこだ"))
	var mobs := [["inn_clerk", 1, ["MELLOW", "GENTLE"]], ["dock_workers", 1, ["HOT", "POWER"]], ["market_porter", 2, ["HOT", "FILLING"]],
		["laundry_night", 2, ["SOUR", "GENTLE"]], ["long_haul_driver", 2, ["SAVORY", "TREAT"]], ["inn_clerk", 3, ["MELLOW", "GENTLE"]],
		["general_store_clerk", 3, ["BITTER", "GENTLE"]], ["street_cleaners", 3, ["SOUR", "FILLING"]]]
	for m in mobs:
		var form := ScheduleData.mob_data_for_day(m[0], m[1])
		c.check("%s（%d日目）：OK が2通り・札は注文 %s（データのまま）" % [m[0], m[1], str(m[2])], _ok_two_ways(form["reactions"], m[2]) and form["wanted_tags"] == m[2])
	# OK の文の出し分け（PlaySession.missing_tags）：外れた札が1つなら、その札の文
	var bowl := { "additions": ["nam_prik_pao"] }
	c.check("出し分け：辛い調味料だけの椀は、阿強の1杯目でスタミナが外れた＝「辛さはこれ…」の文",
		PlaySession.missing_tags(["HOT", "POWER"], bowl) == ["POWER"] and cups[0]["reactions"]["OK_MISSING"][PlaySession.missing_tags(["HOT", "POWER"], bowl)[0]][0].begins_with("阿強「辛さはこれ。"))

	# --- 2. ホテルの夜番 ---
	c.check("モブの名前：laundry_night は「港のホテルの夜番」（id は変えない）・予告DMの差出人も同じ・本文は新しい2文（ヒントの語は やさしい）",
		Day1Events.mob_display_name("laundry_night") == "港のホテルの夜番"
			and str(Dm.previews_config()["pools"]["laundry_night"]["from"]) == "港のホテルの夜番"
			and Dm.previews_config()["pools"]["laundry_night"]["texts"] == ["お客が寝静まったら寄る予定です。{hint}のを一杯", "夜、呼び出しが途切れたら顔を出すかも。{hint}なのがいいな"]
			and str(Dm.previews_config()["pools"]["laundry_night"]["tag_hint"]) == "GENTLE"
			and Dm.preview_text(Dm.previews_config()["pools"]["laundry_night"], "laundry_night", 2).contains("やさしい"))
	var hotel2 := ScheduleData.mob_data_for_day("laundry_night", 2)
	c.check("2日目のホテルの夜番：来店の数行・2杯以上の行・退店の文を差し替えた",
		(hotel2["greet"] as Array).has("夜番「港のホテル。フロントは機械だから、それ以外ぜんぶ。電球に、流しに、洗濯もね」")
			and int((hotel2["greet"] as Array).back()["min_count"]) == 2 and str((hotel2["greet"] as Array).back()["line"]) == "夜番「相方の分も、同じのを。呼び出しの番をしてくれてるの」"
			and hotel2["after_talk"] == ["夜番「ごちそうさま。その袖、今度持っておいでよ。洗濯機が回ってる間に縫ってあげるから」"])
	var old_names := []
	var all_lines := []
	for pair in [["delivery_man", "delivery_man_01"], ["thug", "thug_01"], ["granny", "granny_01"], ["officer", "officer_01"], ["thug", "thug_02"],
			["hooker", "hooker_01"], ["delivery_man", "delivery_man_02"], ["streamer", "streamer_01"], ["hooker", "hooker_02"]]:
		all_lines.append(JSON.stringify(ScheduleData.episode_data(pair[0], pair[1])))
	for mob in ["dock_workers", "inn_clerk", "market_porter", "laundry_night", "long_haul_driver", "general_store_clerk", "street_cleaners"]:
		all_lines.append(JSON.stringify(ScheduleData.mob_data(mob)))
	for talk_id in ["day1_market", "day2_market", "day3_market"]:
		all_lines.append(JSON.stringify(ScheduleData.talk_data(talk_id)))
	all_lines.append(JSON.stringify(Dm.data()))
	for text in all_lines:
		if str(text).contains("洗濯場の夜番"):
			old_names.append(str(text).substr(0, 40))
	c.check("1〜3日目の会話・モブ・市場の場面・DM（予告を含む）に「共同洗濯場の夜番」「洗濯場の夜番」が残っていない", old_names.is_empty(), str(old_names))
	c.check("タイムラインの第三区ランドリーは共同洗濯場のまま（プロフィールは変えない。書き手用の note・truth は「ホテルの夜番とは別の店」）",
		str(Sns.accounts()["laundry_3"]["profile"]) == "忘れ物と営業のお知らせ。" and str(Sns.accounts()["laundry_3"]["note"]).contains("ホテルの夜番とは別の店")
			and not JSON.stringify(Sns.data()).contains("夜番の職場"))

	# --- 3. ニュースの本文 ---
	var news_ok := true
	var detail := []
	for day in [1, 2, 3]:
		var items: Array = News.day_entry(day)["news"]
		news_ok = news_ok and items.size() == 4
		for item in items:
			news_ok = news_ok and (item["body"] as Array).size() == 4 and not bool(item.get("provisional", false))
			detail.append("%s %d段落" % [item["id"], (item["body"] as Array).size()])
	c.check("1〜3日目のニュース：各日4本・どの記事も4段落（本番の文）", news_ok, str(detail))
	c.check("必須情報の印と並びは今のまま（1本目に strike_started・checkpoints・new_window_cargo）",
		News.day_entry(1)["news"][0]["must_info"] == ["strike_started"] and News.day_entry(2)["news"][0]["must_info"] == ["checkpoints"]
			and News.day_entry(3)["news"][0]["must_info"] == ["new_window_cargo"] and News.problems().is_empty())
	c.check("2日目の靴下の棚：話す人は「窓口の係」", JSON.stringify(News.day_entry(2)["news"][3]["body"]).contains("窓口の係")
		and not JSON.stringify(News.day_entry(2)["news"][3]["body"]).contains("夜番の係"))

	# --- 4. ニカの 23:00 は動画 ---
	var nika23: Array = Sns.posts().filter(func(x): return str(x["id"]) == "d3_exposure_test_2300")
	c.check("ニカの 23:00：photo_kind は video・説明は元の文のとおり・データの検査に問題なし",
		nika23.size() == 1 and str(nika23[0]["photo_kind"]) == "video" and str(nika23[0]["photo"]) == "車列。運転席の窓ごしに弁当箱。顔は分からない"
			and Sns.problems().is_empty())
	var bad_kind: Dictionary = (Sns.data() as Dictionary).duplicate(true)
	(bad_kind["posts"] as Array)[0]["photo_kind"] = "video"
	c.check("photo_kind の検査：photo の無い投稿・photo/video 以外は弾く", not Sns.problems(bad_kind).is_empty())
	ReadState.reset("user://test_read_day1_3_fix.json")
	GameState.reset_for_new_game()
	GameState.day_count = 4
	GameState.day_records.append({ "day": 3 })
	var game: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.open_phone("sns")
	var texts := _labels(game.pane_phone)
	c.check("スマホのタイムライン：ニカの 23:00 は「［動画：…］」、ほかの写真は「［写真：…］」のまま",
		texts.has("［動画：車列。運転席の窓ごしに弁当箱。顔は分からない］")
			and texts.any(func(x): return str(x).begins_with("［写真：")), str(texts.filter(func(x): return str(x).begins_with("［"))))
	game.queue_free()

	# --- 5. 2日目の阿強のDM ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.customer_memory["delivery_man"] = { "favorite_known": false, "visits": [{ "day": 1, "served": 2, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	var declined := Dm.delivered_for_day(2).map(func(x): return str(x["id"]))
	CustomerMemory.set_fact("delivery_man", "day1_takeout_served", true)
	var served := Dm.delivered_for_day(2).map(func(x): return str(x["id"]))
	c.check("2日目の阿強のDM「昨日の容器、門のおっさんに預けてきた」：3杯目を出した道だけ（断った道では出ない）",
		not declined.has("d2_delivery_man") and served.has("d2_delivery_man"), "%s / %s" % [str(declined), str(served)])

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()
