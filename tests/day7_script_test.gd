extends RefCounted
## 中身AE：7日目（最後の日）の本番の文（planning/scenario/day7/ の9本）をゲームのデータに入れたことの検証。
##   1. データ：7日目の場面（officer_04・streamer_04・granny_03）・モブ2組（days."7"）・市場の場面（day7_market）・閉店の場面（d7_close）に
##      印の問題が無い・元の文の行が抜けなく入っている・OK は外れた札で2通り・注文の札と好物はデータのまま（今日の頼みは無い）
##   2. リンの「6日目に夜勤警備員が来ていた場合だけ」の5行（mob_served・day 6）
##   3. モブ：1〜4組の晩（明け方は無し。3組目＝夜半の2組目の人夫・4組目＝宵の口の2組目の受付）・予備の一言だけで注文まで済む
##   4. DM（朝の10通・阿強の 7:43 は1日目の3杯目で2通り・夜半のあとの2通は after_visit）・ニュース（朝の6本と印）・タイムライン
##   5. 閉店の場面（ターニャ婆のあと・鍋が尽きた晩も）と、閉店のあとに新しい DM・投稿が出ないこと
##   6. 文の検査（〔ゲーム〕が混ざらない・リンの裏をにおわせる語が無い・火事の原因を言い切る文）
##   7. 7日目を朝から結果の画面（週の終わりのタイトル）まで本番の画面で通す


const SRC := "res://planning/scenario/day7/"


func _md_lines(file: String, from_heading: String, to_heading: String) -> Array:
	var text := FileAccess.get_file_as_string(SRC + file)
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


## 行の配列（条件付きの行のまとまりを含む）を平らにする。
func _flat(lines: Array) -> Array:
	var out := []
	for line in lines:
		if line is String:
			out.append(line)
		elif ScheduleData.is_condition_group(line):
			out.append_array(_flat(line["lines"]))
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
	GameState.day_count = 7

	# --- 1. データ ---
	var scenes := [["officer", "officer_04", "7日目_新人警官.md", ["SOUR", "BITE"], "rice_noodle"],
		["streamer", "streamer_04", "7日目_配信者.md", ["MELLOW", "BITE"], "shrimp"],
		["granny", "granny_03", "7日目_老婆.md", ["SAVORY", "FILLING"], "offal"]]
	for sc in scenes:
		var ep := ScheduleData.episode_data(sc[0], sc[1])
		var lines: Array = ep["greet"] + _flat(ep["body"])
		var md := _md_lines(sc[2], "本編", "14:30の端末投稿用" if sc[0] == "streamer" else ("断った晩" if sc[0] == "granny" else "実装メモ"))
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
	var nika_body: Array = ScheduleData.episode_data("streamer", "streamer_04")["body"]
	var full_video := _md_lines("7日目_配信者.md", "14:30の端末投稿用", "実装メモ")
	c.check("ニカ：屋台の訂正の動画は3行（全文の第1・2・5行）だけ。全文の第3・4・6行は屋台に出ない",
		full_video.size() == 6 and nika_body.has(full_video[0]) and nika_body.has(full_video[1]) and nika_body.has(full_video[4])
			and not nika_body.has(full_video[2]) and not nika_body.has(full_video[3]) and not nika_body.has(full_video[5]))
	var granny_ep := ScheduleData.episode_data("granny", "granny_03")
	c.check("ターニャ婆：瓶の受け渡しは会話だけ（売り買い・在庫・臨時の収入の印は無い）・出来で分けない（本文は1通り）",
		not granny_ep.has("pre_order") and not granny_ep.has("choices") and not granny_ep.has("closing") and not granny_ep.has("sets_facts")
			and (granny_ep["body"] as Array).all(func(l): return l is String) and (granny_ep["body"] as Array).has("店主「いいよ。瓶、出すぞ」"))
	# 中身AE の続き：断った晩（料理を出さなかったとき）。7日目のターニャ婆だけ、4行 → 瓶 → 退店（会計は無し）
	var refuse_md := _md_lines("7日目_老婆.md", "断った晩", "実装メモ")
	var main_md := _md_lines("7日目_老婆.md", "本編", "断った晩")
	var bottle_at := main_md.find("ターニャ婆「うん。口も欠けてない。よく乾いてる」")
	GameState.reset_for_new_game()
	GameState.day_count = 7
	var refused := _texts(Day1Events.after_serve_events("granny", "granny_03", { "served": false, "grade": "" }))
	var refused_exit := _texts(Day1Events.unserved_exit_events("granny", "granny_03"))
	c.check("ターニャ婆を断った晩：断った晩の4行 → 瓶（「うん。口も欠けてない…」から）→ 退店。会計の2行（「ごちそうさん。勘定は…」「いいよ。瓶、出すぞ」）と食事の行は出ない・鍋が尽きて退店した晩も同じ",
		refuse_md.size() == 4 and bottle_at > 0 and refused == refuse_md + main_md.slice(bottle_at) and refused_exit == refused
			and not refused.has("ターニャ婆「ごちそうさん。勘定は、これでいいかい」") and not refused.has("店主「いいよ。瓶、出すぞ」")
			and ScheduleData.episode_must_info("granny", "granny_03").is_empty(), "%d / %d" % [refused.size(), refuse_md.size() + main_md.size() - bottle_at])
	c.check("断った晩の本文を持つのは7日目のターニャ婆だけ（ほかの客・ほかの日は、断った晩に本文を出さないまま）",
		ScheduleData.customer_episode_ids("granny").all(func(e): return (e == "granny_03") != ScheduleData.episode_body_unserved("granny", e).is_empty())
			and ["delivery_man", "thug", "officer", "hooker", "streamer"].all(func(cid): return ScheduleData.customer_episode_ids(cid).all(func(e): return ScheduleData.episode_body_unserved(cid, e).is_empty()))
			and _texts(Day1Events.after_serve_events("officer", "officer_04", { "served": false, "grade": "" })).is_empty())
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	var grade_of := func(additions: Array, wanted: Array, favorite: String) -> String: return str(Judge.grade({ "additions": additions }, GameState.soup, { "wanted_tags": wanted, "favorite": favorite })["grade"])
	c.check("手がかりと札：リンの GREAT＝塩漬けライム＋歯ごたえの具＋米麺・ニカの GREAT＝ココナッツミルク＋歯ごたえの具＋海老・ターニャ婆の GREAT＝薬膳ナンプラーだれ＋腹もちの具＋モツ（モツは腹もちの代わりにならない）",
		grade_of.call(["pickled_lime", "cartilage", "rice_noodle"], ["SOUR", "BITE"], "rice_noodle") == "GREAT"
			and grade_of.call(["coconut_milk", "cartilage", "shrimp"], ["MELLOW", "BITE"], "shrimp") == "GREAT"
			and grade_of.call(["herbal_sauce", "broken_wrapper", "offal"], ["SAVORY", "FILLING"], "offal") == "GREAT"
			and grade_of.call(["herbal_sauce", "offal"], ["SAVORY", "FILLING"], "offal") != "GREAT")
	# 市場
	var talk := ScheduleData.talk_data("day7_market")
	var parts: Array = talk.get("parts", []).filter(func(p): return str(p.get("when", "")) != "shop" and str(p.get("speaker", "")) != "サミル")   # UI準備AG：店の会話（when:"shop"）・5日目のサミルは別に確かめる
	var zhang_md := _md_lines("7日目_昼市場.md", "張記肉類加工", "海隆鮮貨")
	var liang_md := _md_lines("7日目_昼市場.md", "共同水場", "実装メモ")
	c.check("市場の場面：張姐（%d行。仕込む量の印の前は「で、今日はどれ位仕込む？」まで・あとに3行。必須情報の印は付けない）と梁伯（%d行。払う印なし）・海叔・ミンは入れない" % [zhang_md.size(), liang_md.size()],
		parts.size() == 2 and parts[0]["lines"].filter(func(l): return l is String) == zhang_md and parts[0]["lines"][zhang_md.size() - 3] is Dictionary
			and str(parts[0]["lines"][zhang_md.size() - 4]).ends_with("で、今日はどれ位仕込む？」") and not (parts[0] as Dictionary).has("must_info")
			and str(parts[1]["when"]) == "exit" and parts[1]["lines"] == liang_md and Rules.day_overrides(7).get("market_scene", "") == "day7_market"
			and not JSON.stringify(parts).contains("海叔「") and not JSON.stringify(parts).contains("ミン「"))
	var before := Day1Events.prep_events({}, false)
	var after := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	var market_at := after.map(func(e): return str(e["type"])).find("MARKET")
	c.check("市場の列：張姐 → 仕込む量 → 選んだあとの3行 → 鍋の素 → 市場 → 梁伯 → 「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」。PAY は無い・仕込む量の段階と値段はいつもの日と同じ",
		before.map(func(e): return str(e["text"])) == zhang_md.slice(0, zhang_md.size() - 3) and str(before.back()["type"]) == "PREP_TIER"
			and after.slice(0, 3).map(func(e): return str(e["text"])) == zhang_md.slice(zhang_md.size() - 3) and market_at == 4
			and after.slice(market_at + 1, market_at + 1 + liang_md.size()).map(func(e): return str(e["text"])) == liang_md
			and str(after[market_at + 1 + liang_md.size()]["text"]) == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。"
			and not (before + after).any(func(e): return str(e["type"]) == "PAY")
			and Rules.day_overrides(7).keys() == ["market_scene"])

	# --- 2. リンの「6日目に夜勤警備員が来ていた場合だけ」の5行 ---
	var officer_ep := ScheduleData.episode_data("officer", "officer_04")
	var guard_md := ["リン「旧倉庫の夜番の方から、ここの店主に礼を、と言われました。昨夜、交代のときにスープを食べたそうですね」", "店主「会ったのか」",
		"リン「はい。規制の外で、ご本人と話しました。持ち場のことを確認していました」", "店主「……そうか。なら、また来いって伝えてくれ」", "リン「会えたら、伝えます」"]
	var groups: Array = (officer_ep["body"] as Array).filter(func(l): return l is Dictionary)
	c.check("リンの5行は条件付きのまとまり（mob_served: security_guard・day: 6）",
		groups.size() == 1 and (groups[0]["if"] as Dictionary).size() == 2 and str(groups[0]["if"].get("mob_served", "")) == "security_guard"
			and int(groups[0]["if"].get("day", 0)) == 6 and groups[0]["lines"] == guard_md)
	GameState.reset_for_new_game()
	GameState.day_count = 7
	GameState.day_records = [{ "day": 6, "mob_types_served": ["long_haul_driver", "security_guard"] }]
	var with_guard := _texts(Day1Events._scene_lines("body", "officer", officer_ep["body"]))
	GameState.day_records = [{ "day": 6, "mob_types_served": ["long_haul_driver"] }]
	var no_guard := _texts(Day1Events._scene_lines("body", "officer", officer_ep["body"]))
	GameState.day_records = []
	var no_record := _texts(Day1Events._scene_lines("body", "officer", officer_ep["body"]))
	c.check("6日目に夜勤警備員へ出した道は5行が出る・出していない道（日次ログに無い道も）は5行とも出ない（ほかの行は同じ）",
		guard_md.all(func(l): return with_guard.has(l)) and not guard_md.any(func(l): return no_guard.has(l)) and no_record == no_guard
			and with_guard.size() == no_guard.size() + 5)

	# --- 3. モブ ---
	var mobs := { "inn_clerk": ["宵の口　安宿の夜勤受付", "夜半　市場の荷捌き人夫", ["MELLOW", "GENTLE"], 1],
		"market_porter": ["夜半　市場の荷捌き人夫", "余分の組", ["HOT", "FILLING"], 8] }
	for mob_id in mobs:
		var form := ScheduleData.mob_data_for_day(mob_id, 7)
		var two := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 2))
		var one := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["greet"], 1))
		var after_two := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["after_talk"], 2))
		var after_one := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["after_talk"], 1))
		var md := _md_lines("7日目_モブ2組.md", mobs[mob_id][0], mobs[mob_id][1])
		c.check("%s（7日目）：元の文（%d行）がそのまま・2杯以上の行（%d行）は2杯の組だけ・OK は2通り・注文の札はデータのまま・GREAT は無い" % [mob_id, md.size(), mobs[mob_id][3]],
			two + after_two == md and (two.size() + after_two.size()) == (one.size() + after_one.size()) + int(mobs[mob_id][3]) and _ok_two_ways(form["reactions"], mobs[mob_id][2])
				and form["wanted_tags"] == mobs[mob_id][2] and not (form["reactions"] as Dictionary).has("GREAT"),
			"%d / %d" % [(two + after_two).size(), md.size()])
	c.check("余分の組：来店の文は予備の一言と注文を兼ねた1行だけ（元の注文の文を出さない）・帰りの文は予備の退店の文",
		ScheduleData.mob_data_for_day("market_porter", 7)["spare_greet"] == ["人夫「辛くて腹にたまるのを。今日は座って食う。新しい集合場所、帰りだけは近かった」"]
			and ScheduleData.mob_data_for_day("market_porter", 7)["spare_farewell"] == ["人夫「ごちそうさん。次は、上の入口の方も覚えてくる」"]
			and ScheduleData.mob_data_for_day("inn_clerk", 7)["spare_greet"] == ["受付「まろやかな汁に、やさしい具を。持ち帰りで。新しい道順を送っていたら、自分の夕飯が後になってしまいまして」"]
			and ScheduleData.mob_data_for_day("inn_clerk", 7)["spare_farewell"] == ["受付「帰ったら、先に食べます。今なら、番台を見てくれる者がいるので」"])
	for count in [1, 2, 3, 4]:
		GameState.reset_for_new_game()
		GameState.day_count = 7
		var slots := [{ "name": "宵の口", "mob": ScheduleData.mob_rule_for(7, "宵の口") }, { "name": "夜半", "mob": ScheduleData.mob_rule_for(7, "夜半") },
			{ "name": "明け方", "mob": ScheduleData.mob_rule_for(7, "明け方") }]
		var by_index := Day1Events._plan_mob_groups(slots, count * 4)
		var instances := {}
		var seq := 0
		var order := []
		var slot_of := {}
		for i in range(3):
			for size in by_index.get(i, []):
				var iid := "mob#%d" % seq
				seq += 1
				instances[iid] = { "type": str(ScheduleData.mob_rule_for(7, slots[i]["name"])["pool"][0]), "count": size }
				order.append(iid)
				slot_of[iid] = slots[i]["name"]
		GameState.today_plan = { "day": 7, "slots": [], "mob_instances": instances }
		var spare_ids := order.filter(func(iid): return Day1Events.is_repeat_mob_group(iid))
		var ok := true
		for iid in order:
			var form := ScheduleData.mob_data_for_day(str(instances[iid]["type"]), 7)
			var cnt := int(instances[iid]["count"])
			var want_greet := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_greet"] if spare_ids.has(iid) else form["greet"], cnt))
			var want_after := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(form["spare_farewell"] if spare_ids.has(iid) else form["after_talk"], cnt))
			ok = ok and Day1Events._customer_flavor(iid)["greet"] == want_greet and _texts(Day1Events.mob_after_talk_events(iid)) == want_after
			if spare_ids.has(iid):
				ok = ok and (Day1Events._customer_flavor(iid)["greet"] as Array).size() == 1
		var types_by_order := order.map(func(iid): return "%s@%s" % [instances[iid]["type"], slot_of[iid]])
		var want_types: Array = [["market_porter@夜半"], ["inn_clerk@宵の口", "market_porter@夜半"],
			["inn_clerk@宵の口", "market_porter@夜半", "market_porter@夜半"], ["inn_clerk@宵の口", "inn_clerk@宵の口", "market_porter@夜半", "market_porter@夜半"]][count - 1]
		c.check("モブが%d組の晩：明け方にモブは来ない（3組目＝夜半の2組目の人夫・4組目＝宵の口の2組目の受付）・各組の文と退店の文が正しい・余分の組は予備の1行だけで注文まで" % count,
			ok and types_by_order == want_types and spare_ids.size() == maxi(count - 2, 0), str(types_by_order))

	# --- 4. DM・ニュース・タイムライン ---
	GameState.reset_for_new_game()
	GameState.day_count = 7
	for cid in ["delivery_man", "thug", "granny", "officer", "hooker", "streamer"]:
		GameState.customer_memory[cid] = { "favorite_known": false, "visits": [{ "day": 1, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	GameState.customer_memory["delivery_man"]["facts"] = { "day1_takeout_served": true }
	GameState.today_plan = { "day": 7, "slots": [{ "name": "宵の口", "customers": ["officer"], "regular_id": "officer" },
		{ "name": "夜半", "customers": ["streamer"], "regular_id": "streamer" }, { "name": "明け方", "customers": ["granny"], "regular_id": "granny" }],
		"mob_instances": {}, "demand_center": 9 }
	var morning := Dm.delivered_for_day(7).filter(func(x): return not bool(x.get("preview", false)))
	c.check("7日目の朝のDM10通：張姐 7:10・阿強 7:40〜7:45 の4通（7:43 は1日目に3杯目を出した道の文）・セティヤ 8:20・ターニャ婆 8:50・リン 9:00・ニカ 9:20・レックス 10:05",
		morning.map(func(x): return "%s %s" % [x["from"], x["time"]]) == ["張姐 7:10", "阿強 7:40", "阿強 7:41", "阿強 7:43", "阿強 7:45", "セティヤ 8:20", "ターニャ婆 8:50", "リン 9:00", "ニカ 9:20", "レックス 10:05"]
			and _ids(morning).has("d7_delivery_man_3") and not _ids(morning).has("d7_delivery_man_3_declined"),
		str(morning.map(func(x): return x["id"])))
	c.check("リン・ニカ・ターニャ婆の来店予告は7日目の朝に出ない",
		not Dm.delivered_for_day(7).any(func(x): return bool(x.get("preview", false)) and ["officer", "streamer", "granny"].has(str(x.get("subject", "")))),
		str(Dm.delivered_for_day(7).map(func(x): return x["id"])))
	GameState.customer_memory["delivery_man"]["facts"] = {}
	var morning_no := _ids(Dm.delivered_for_day(7))
	c.check("1日目に3杯目を出していない道：7:43 は「前に車輪の紐を外してくれた門のおっさんも」の文", morning_no.has("d7_delivery_man_3_declined") and not morning_no.has("d7_delivery_man_3")
		and str(Dm.item_by_id(7, "d7_delivery_man_3_declined")["text"]).contains("車輪の紐"))
	var photo := Dm.item_by_id(7, "d7_delivery_man_1")
	c.check("阿強の 7:40 の写真は photo の欄（本文に［写真：…］を書かない）",
		str(photo["photo"]) == "中古のロードバイク。ハンドルの端に傷。会社の番号の札は付いていない" and not str(photo["text"]).contains("［写真") and Dm.body_text(photo).ends_with("］"))
	GameState.customer_memory.erase("granny")
	GameState.customer_memory.erase("officer")
	GameState.customer_memory.erase("streamer")
	GameState.customer_memory.erase("hooker")
	var unmet := _ids(Dm.delivered_for_day(7))
	c.check("セティヤ・ターニャ婆・リン・ニカの朝のDMは、その客に会っていないと届かない（張姐・阿強・レックスは届く）",
		not unmet.has("d7_hooker") and not unmet.has("d7_granny") and not unmet.has("d7_officer") and not unmet.has("d7_streamer")
			and unmet.has("d7_market") and unmet.has("d7_delivery_man_1") and unmet.has("d7_thug"), str(unmet))
	var night_items := Dm.items_for_day(7).filter(func(x): return Dm.is_night(x))
	c.check("夜半のあとのDM2通：港湾労働者（条件なしの npc）00:10・00:12・ニカの接客のあと（after_visit）",
		night_items.map(func(x): return "%s %s %s %s" % [x["time"], x["from"], x["from_kind"], x["after_visit"]]) == ["00:10 港湾労働者 npc streamer", "00:12 港湾労働者 npc streamer"])
	c.check("ニカの接客の前は届かない・済んだら届く", not _ids(Dm.inbox(7, {}, [], ["officer"])).has("d7_dock_0010")
		and _ids(Dm.inbox(7, {}, [], ["officer", "streamer"])).has("d7_dock_0010") and _ids(Dm.inbox(7, {}, [], ["officer", "streamer"])).has("d7_dock_0012"))
	c.check("7日目の DM・ニュース・タイムラインは本番の文（provisional なし）",
		Dm.items_for_day(7).all(func(x): return not bool(x.get("provisional", true))) and News.day_entry(7)["news"].all(func(x): return not bool(x.get("provisional", true)))
			and Sns.posts().filter(func(x): return int(x["day"]) == 7).all(func(x): return not bool(x.get("provisional", true))))
	var news7: Array = News.day_entry(7)["news"]
	c.check("ニュース：朝の記事6本（6日目の台本の 05:10 の記事は入れない）・1本目に police_wiring_probe と truth_unresolved、2本目に window_changed_before_fire",
		news7.size() == 6 and not news7.any(func(x): return str(x["headline"]).contains("朝の便に遅れ見込み"))
			and news7[0]["must_info"] == ["police_wiring_probe", "truth_unresolved"] and news7[1]["must_info"] == ["window_changed_before_fire"]
			and News.delivered_days()["police_wiring_probe"] == [7] and News.delivered_days()["window_changed_before_fire"] == [7] and News.delivered_days()["truth_unresolved"] == [7])
	c.check("1本目の警察発表の文言は、リンが屋台で話す文言と同じ（仮設配線付近・放火を裏付ける証拠は確認されていない・原因の特定には至っていない）",
		str(news7[0]["body"][1]).contains("現時点で放火を裏付ける証拠は確認されておらず、原因の特定には至っていない")
			and (officer_ep["body"] as Array).has("リン「現時点で、放火を裏付ける証拠は確認されていない、という発表です」")
			and (officer_ep["body"] as Array).has("リン「はい。旧倉庫の仮設配線付近を調べている、と公表されています」"))
	c.check("データの検査に問題が無い（ニュース・DM・タイムライン）", News.problems().is_empty() and Dm.problems().is_empty() and Sns.problems().is_empty(),
		str(News.problems()) + str(Dm.problems()) + str(Sns.problems()))

	# --- 5. 閉店の場面と、閉店のあと ---
	var close_ev: Array = News.day_entry(7)["events"]
	c.check("閉店の場面（d7_close・at=close）：店主の3行（「1．閉店」のとおり）",
		close_ev.size() == 1 and str(close_ev[0]["at"]) == "close" and close_ev[0]["lines"] == _md_lines("7日目_閉店と週の終わり.md", "1．閉店", "2．朝の音"))
	var all_times_ok := Dm.items_for_day(7).all(func(x): return Dm.order_minutes(x) <= Sns.day_minutes("00:12"))
	var last_post := 0
	for x in Sns.posts().filter(func(p): return int(p["day"]) == 7):
		last_post = maxi(last_post, Sns.day_minutes(str(x["time"])))
	c.check("ターニャ婆（明け方）より後の時刻の DM・投稿は無い（最後の投稿は 23:50、最後の DM は 00:12）", all_times_ok and last_post == Sns.day_minutes("23:50"))
	# 鍋が尽きて早く閉めた晩（宵の口のうちに閉める）：閉店の場面は出る。ニカが来なかったので、ニカの退店のあとの DM は届かない
	GameState.reset_for_new_game()
	GameState.day_count = 7
	var p_early = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(p_early)
	GameState.phase = GameState.Phase.OPEN
	p_early.session.set_runner_for_phase(GameState.Phase.OPEN)
	GameState.soup = null
	p_early.session.flow.force_phase(GameState.Phase.CLOSE)
	var early_texts: Array = p_early.session.flow.runner.events.filter(func(e): return str(e.get("part", "")) == "common_event").map(func(e): return str(e["text"]))
	c.check("鍋が尽きて早く閉めた晩：閉店の前に閉店の場面（店主の3行）が1回出る", early_texts == close_ev[0]["lines"] and p_early.session.played_events == ["d7_close"])
	c.check("鍋が尽きて早く閉めた晩（ニカが来ていない）：閉店のあとも、ニカの退店のあとの DM 2通は届かない（DM は来た客で決める。UI準備AE）",
		not _ids(p_early.session.dm_inbox()).has("d7_dock_0010") and not _ids(p_early.session.dm_inbox()).has("d7_dock_0012")
			and p_early.session.visits_done_today().has("streamer"))
	# 中身AE の続き：接客のあとの投稿（requires.visited）も、閉店のあとは今日ほんとうに来た客で決める（来なかった客も済んだ扱い〔visits_done_today〕は変えない）
	var es = p_early.session
	var arrived: Array = es.phone_visits_done_today()
	var early_posts := Sns.visible_ids(7, Sns.LIMIT_DAY_END, {}, es.market_talks_done(), arrived, es.played_events)
	c.check("鍋が尽きて早く閉めた晩（ニカが来ていない）：ニカ 23:30 の投稿は出ない。リン 21:25 は、リンが来ていれば出る（この晩に来た客 %s）" % str(arrived),
		not early_posts.has("d7_exposure_test_2330") and early_posts.has("d7_lin_alt_2125") == arrived.has("officer")
			and _ids(es.sns_timeline()[0]["posts"]).has("d7_lin_alt_2125") == arrived.has("officer")
			and not arrived.has("streamer") and not arrived.has("granny") and es.visits_done_today().has("officer"), str(early_posts.slice(0, 6)))
	for cid in ["officer", "streamer", "granny"]:   # リンも来なかった晩にする（今日の来店記録を外す）
		if GameState.customer_memory.has(cid):
			GameState.customer_memory[cid]["visits"] = (GameState.customer_memory[cid]["visits"] as Array).filter(func(v): return int(v.get("day", -1)) != 7)
	var none_posts := Sns.visible_ids(7, Sns.LIMIT_DAY_END, {}, es.market_talks_done(), es.phone_visits_done_today(), es.played_events)
	c.check("リンもニカも来なかった晩：閉店のあとも 21:25・23:30 の投稿と 00:10・00:12 の DM は出ない（次の日も見えない＝UI準備AF）",
		not none_posts.has("d7_lin_alt_2125") and not none_posts.has("d7_exposure_test_2330") and es.phone_visits_done_today().is_empty()
			and not _ids(es.dm_inbox()).has("d7_dock_0010") and not _ids(es.dm_inbox()).has("d7_dock_0012")
			and not Sns.is_visible(Sns.posts().filter(func(x): return str(x["id"]) == "d7_lin_alt_2125")[0], 8, Sns.LIMIT_MORNING), str(none_posts.slice(0, 6)))
	p_early.free()
	# ほかの日の requires.visited の投稿も同じ（3日目のニカ 23:00・4日目のリン 21:25 など）：Sns は渡された「来た客」だけを見る
	var visited_posts := Sns.posts().filter(func(x): return (x.get("requires", {}) as Dictionary).has("visited"))
	var gate_ok := true
	for x in visited_posts:
		gate_ok = gate_ok and not Sns.is_visible(x, int(x["day"]), Sns.LIMIT_DAY_END, [], [], []) and Sns.is_visible(x, int(x["day"]), Sns.LIMIT_DAY_END, [], [str(x["requires"]["visited"])], ["d6_fire"])
	c.check("requires.visited の投稿（%d件。3日目のニカ 23:00・4日目のリン 21:25 を含む）は、その日その客が来ていなければ、閉店のあとでも見えない" % visited_posts.size(),
		visited_posts.size() >= 3 and gate_ok
			and visited_posts.any(func(x): return int(x["day"]) == 3 and str(x["time"]) == "23:00") and visited_posts.any(func(x): return int(x["day"]) == 4 and str(x["time"]) == "21:25"),
		str(visited_posts.map(func(x): return "%d %s" % [x["day"], x["time"]])))

	# --- 6. 文の検査 ---
	var all7 := JSON.stringify(talk) + JSON.stringify(News.day_entry(7)) + JSON.stringify(Dm.items_for_day(7))
	for sc in scenes:
		all7 += JSON.stringify(ScheduleData.episode_data(sc[0], sc[1]))
	for mob_id in mobs:
		all7 += JSON.stringify(ScheduleData.mob_data(mob_id)["days"]["7"])
	c.check("7日目の会話・閉店の場面・DM・ニュースに〔ゲーム〕〔演出〕の文が混ざらない", not all7.contains("〔"))
	var lin_side := JSON.stringify(officer_ep) + str(Dm.item_by_id(7, "d7_officer")["text"]) + JSON.stringify(news7)
	var lin_words := ["報告", "暗号", "指令", "組織", "上の者", "本部"].filter(func(w): return lin_side.contains(w))
	c.check("リンの会話・DM・7日目のニュースに、リンの裏をにおわせる語（報告・暗号・指令・組織・上の者・本部）が無い", lin_words.is_empty(), str(lin_words))
	var cause := []
	for line in _flat(officer_ep["body"]) + _flat(ScheduleData.episode_data("streamer", "streamer_04")["body"]) + _flat(granny_ep["body"]):
		if ["放火", "焼かせ", "火をつけ", "事故"].any(func(w): return str(line).contains(w)):
			cause.append(line)
	for x in Dm.items_for_day(7) + Sns.posts().filter(func(p): return int(p["day"]) == 7):
		if ["放火", "焼かせ", "火をつけ", "事故"].any(func(w): return str(x["text"]).contains(w)):
			cause.append(str(x["text"]))
	for x in news7:
		for para in [x["headline"]] + (x["body"] as Array):
			if ["放火", "焼かせ", "火をつけ", "事故"].any(func(w): return str(para).contains(w)):
				cause.append(str(para))
	print("  7日目の火事の原因に触れる文（%d）：" % cause.size())
	for line in cause:
		print("    ", str(line).substr(0, 60))
	c.check("火事の原因に触れる7日目の文は、撤回・否定・発表の言い方（「放火」「焼かせた」と言い切る文は無い）",
		cause.all(func(l): return ["撤回", "誤り", "ねえ", "確認されていない", "決まったわけでもない", "って話は", "見ていません", "人から聞いただけ", "別って", "原因はまだ", "書いたのは私", "確認されておらず"].any(func(w): return str(l).contains(w))),
		str(cause))

	# --- 7. 7日目を朝から結果の画面まで本番の画面で通す ---
	_play_day7(t, c)

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()


func _play_day7(t: SceneTree, c: TestCheck) -> void:
	ReadState.reset("user://test_read_day7_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var topped := {}
	while GameState.day_count < 7 and guard < 40000:
		guard += 1
		if GameState.day_count >= 5 and not topped.has(GameState.day_count) and GameState.phase == GameState.Phase.WAKE:
			topped[GameState.day_count] = true
			GameState.money += 500   # このテストの中だけ：自動の遊び手は所持金が少なく、具を買えずに全部断るため（day6_script_test と同じ）
		if play.step() == "":
			break
	c.check("（前提）Day1〜6 を遊び、Day7 の朝へ進んだ", GameState.day_count == 7)
	GameState.money += 500   # このテストの中だけ
	var guard_on_day6: bool = Day1Events.mob_types_served_on(6).has("security_guard")
	var shown := []
	var shown_keys := {}
	var bracket_shown := []
	var plan_slots: Array = []
	var expected_common := []
	var inbox_at_close := []
	var timeline_at_close := []
	guard = 0
	while GameState.phase != GameState.Phase.RESULT and guard < 12000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if GameState.phase == GameState.Phase.OPEN and plan_slots.is_empty():
			plan_slots = (GameState.today_plan["slots"] as Array).duplicate(true)
		if s.flow.runner != null and str(line.get("text", "")) != "" and str(line.get("type", "")) != "REACT" and not ["shop_talk", "hearty", "penalty"].has(str(line.get("part", ""))):   # UI準備AG：店の会話・具だくさんの一言は別に確かめる
			var key := "%d|%d|%d|%d|%s" % [GameState.phase, s.open.slot_index if s.open != null else -1, s.open.index if s.open != null else -1,
				s.flow.runner.index, str(line.get("text", ""))]
			if not shown_keys.has(key):
				shown_keys[key] = true
				shown.append({ "text": str(line.get("speaker_name", "")) + str(line.get("text", "")), "part": str(line.get("part", "")), "type": str(line.get("type", "")) })
		if GameState.phase == GameState.Phase.CLOSE and inbox_at_close.is_empty():
			inbox_at_close = _ids(s.dm_inbox())
			timeline_at_close = Sns.visible_ids(7, Sns.LIMIT_DAY_END, {}, s.market_talks_done(), s.phone_visits_done_today(), s.played_events)
			expected_common = News.event_texts(News.day_entry(7)["events"][0], 7)
		if play.step() == "":
			break
	c.check("Day7 を閉店まで遊び、結果の画面へ入った", GameState.phase == GameState.Phase.RESULT and root.full_result.visible, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("会話枠に〔〕の文が一度も出ない", bracket_shown.is_empty(), str(bracket_shown))
	var dawn: Array = plan_slots.filter(func(sl): return str(sl["name"]) == "明け方")
	c.check("明け方の客はターニャ婆だけ（この週の最後の客。モブは来ない）", dawn.size() == 1 and dawn[0]["customers"] == ["granny"], str(plan_slots))
	var texts := shown.map(func(x): return str(x["text"]))
	var granny_last := -1
	for i in range(texts.size()):
		if str(texts[i]).begins_with("ターニャ婆「"):
			granny_last = i
	var common := shown.filter(func(x): return str(x["part"]) == "common_event").map(func(x): return str(x["text"]))
	var first_common := texts.find(expected_common[0]) if not expected_common.is_empty() else -1
	c.check("閉店の場面（店主の3行）は、ターニャ婆の最後の行のあとに1回だけ出る。そのあと客の行は無い",
		common == expected_common and first_common > granny_last and granny_last >= 0
			and shown.slice(first_common).all(func(x): return str(x["part"]) == "common_event" or str(x["type"]) != "GREET"), str(common))
	var guard_lines := texts.filter(func(x): return str(x).begins_with("リン「旧倉庫の夜番の方から"))
	c.check("リンの5行：6日目に夜勤警備員へ出した道なら出る・出していない道なら出ない（この通しでは6日目に夜勤警備員%s）" % ("あり" if guard_on_day6 else "なし"),
		guard_lines.size() == (1 if guard_on_day6 else 0))
	c.check("閉店のあと（結果の画面まで）に、新しい DM・投稿は出ない",
		_ids(s.dm_inbox()) == inbox_at_close and Sns.visible_ids(7, Sns.LIMIT_DAY_END, {}, s.market_talks_done(), s.phone_visits_done_today(), s.played_events) == timeline_at_close
			and inbox_at_close.has("d7_dock_0010"))
	var card: Control = root.full_result.get_node("TitleCard")
	c.check("週の終わり：結果の画面に入ると、まず「夜湯」のタイトルが1枚（画面いっぱい）", card.visible and (card.get_node("TitleText") as Label).text == "夜湯"
		and root.full_result.title_open)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card.gui_input.emit(click)
	c.check("タイトルを押すと結果の1ページ目（成績）へ", not card.visible and not root.full_result.title_open and root.full_result.page == 0
		and (root.full_result.get_node("%Body") as Label).text.begins_with("◆結果：店の成績"))
	root.queue_free()
