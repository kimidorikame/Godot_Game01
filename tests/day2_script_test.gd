extends RefCounted
## 中身X：2日目の本番の文（planning/scenario/day2/ の8本）をゲームのデータに入れたことの検証。
##   1. データ：2日目の場面（officer_01・thug_02・hooker_01）・モブ3組（days."2"）・市場の場面（day2_market）に印の問題が無い・
##      元の文の行が抜けなく入っている・注文の札と好物（手がかりと合う）
##   2. 市場：張姐の会話（仕込む量の前。最後の問いが仕込む量を選ぶ場面の文）→ 出汁を受け取る → 新人警官の会話（買い物の前）→ 市場。
##      払い方は今までどおり（市場を出るときにまとめて払う。市場の場面の行に支払いは無い）
##   3. モブの「2杯以上のときだけ」の1行（min_count）：組の杯数が2以上のときだけ出る
##   4. 新人警官：食後の本文が会計・退店まで持つので、仮の行（_OFFICER_AFTER）は出ない（仮の文の officer_02 は今までどおり）
##   5. 2日目を朝から閉店まで本番の画面で通す：元の文の行が順に出る・〔〕の文が出ない・反応は判定どおりの1行だけ・名前の札
##      （警官→会計のあとの「リンです」のあとからリン・セティヤ）・朝のDM（レックス2通・阿強・張姐。新人警官の予告なし）・
##      タイムラインのリンの 14:10 は市場の会話のあとから


func _setup_mob(t: SceneTree, mob_type: String, count: int):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	GameState.today_plan["mob_instances"]["mob#9"] = { "type": mob_type, "count": count }
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": ["mob#9"] }])
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel.session.load_current_customer()
	return panel


func _greets(panel) -> Array:
	return panel.session.flow.runner.events.filter(func(e): return str(e["type"]) == "GREET").map(func(e): return str(e["text"]))


## 元の文（.md）の「名前「セリフ」」の行の数（〔ゲーム〕の行・表・見出し・反応の行を除く）。
func _md_spoken_count(file: String, from_heading: String, to_heading: String) -> int:
	var text := FileAccess.get_file_as_string("res://planning/scenario/day2/" + file)
	var inside := false
	var n := 0
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			if line.contains(from_heading):
				inside = true
			elif to_heading != "" and line.contains(to_heading):
				inside = false
			continue
		if inside and line.contains("「") and line.ends_with("」") and not line.begins_with("-") and not line.begins_with("|") and not line.begins_with("〔"):
			n += 1
	return n


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()

	# --- 1. データ ---
	var officer := ScheduleData.episode_data("officer", "officer_01")
	var thug := ScheduleData.episode_data("thug", "thug_02")
	var hooker := ScheduleData.episode_data("hooker", "hooker_01")
	for ep in [officer, thug, hooker]:
		c.check("%s：場面データの形・印に問題が無い・元の文の場所（source）がある" % ep["id"], ScheduleData.scene_problems(ep).is_empty()
			and str(ep.get("source", "")).begins_with("planning/scenario/day2/"), str(ScheduleData.scene_problems(ep)))
		var all_lines: Array = ScheduleData.spoken_lines(ep["greet"]) + ScheduleData.spoken_lines(ep["body"]) + ScheduleData.spoken_lines(ep.get("market_talk", []))
		for grade in ep["reactions"]:
			all_lines.append_array(ep["reactions"][grade])
		c.check("%s：どの行も「名前「セリフ」」の形で、〔〕の印・行の終わりの空白を含まない" % ep["id"],
			all_lines.all(func(x): return str(x).contains("「") and str(x).ends_with("」") and not str(x).contains("〔") and not str(x).ends_with(" ")))
		c.check("%s：反応は4段（GREAT・GOOD・OK・BAD）各1行" % ep["id"], (ep["reactions"] as Dictionary).keys().size() == 4
			and ["GREAT", "GOOD", "OK", "BAD"].all(func(g): return (ep["reactions"][g] as Array).size() == 1))
	c.check("元の文の行がそろっている：警官（市場27・来店と注文24・食後44）・レックス（17・27）・セティヤ（20・21）",
		(officer["market_talk"] as Array).size() == 27 and (officer["greet"] as Array).size() == 24 and ScheduleData.spoken_lines(officer["body"]).size() == 44
			and (thug["greet"] as Array).size() == 17 and (thug["body"] as Array).size() == 27
			and (hooker["greet"] as Array).size() == 20 and (hooker["body"] as Array).size() == 21
			and _md_spoken_count("2日目_昼市場.md", "張記を出たところ", "寄った店") == 27
			and _md_spoken_count("2日目_新人警官.md", "本編", "実装メモ") == 24 + 44
			and _md_spoken_count("2日目_チンピラ.md", "本編", "実装メモ") == 17 + 27
			and _md_spoken_count("2日目_夜の女.md", "本編", "実装メモ") == 20 + 21)
	var talk := ScheduleData.talk_data("day2_market")
	var zhang: Array = ScheduleData.spoken_lines(talk["parts"][0]["lines"])
	c.check("市場の場面 day2_market：張姐の会話（着いたときだけ）8行・最後は仕込む量の問い・市場を出たあとの部分は無い",
		(talk["parts"] as Array).size() == 1 and str(talk["parts"][0]["when"]) == "arrive" and zhang.size() == 8
			and str(zhang.back()).ends_with("で、今日はどれ位仕込む？」") and _md_spoken_count("2日目_昼市場.md", "張記肉類加工", "張記を出たところ") == 8
			and ScheduleData.marker_problems(talk["parts"][0]["lines"], "day2_market").is_empty())
	# 注文の札と好物（手がかりと合う。データのまま）
	c.check("注文の札・好物：新人警官＝酸っぱい＋歯ごたえ（米麺）・セティヤ＝苦い＋ごちそう（塩漬けライム）・レックスの好物は肉団子",
		ScheduleData.customer_profile("officer")["wanted_tags"] == ["SOUR", "BITE"] and str(ScheduleData.customer_profile("officer")["favorite"]) == "rice_noodle"
			and ScheduleData.customer_profile("hooker")["wanted_tags"] == ["BITTER", "TREAT"] and str(ScheduleData.customer_profile("hooker")["favorite"]) == "pickled_lime"
			and str(ScheduleData.customer_profile("thug")["favorite"]) == "meat_ball")
	var mob_tags := { "market_porter": ["HOT", "FILLING"], "laundry_night": ["SOUR", "GENTLE"], "long_haul_driver": ["SAVORY", "TREAT"] }
	var mob_counts := { "market_porter": [8, 1, 1], "laundry_night": [11, 1, 1], "long_haul_driver": [10, 1, 2] }
	for mob_id in mob_tags:
		var day2 := ScheduleData.mob_data_for_day(mob_id, 2)
		var raw: Array = ScheduleData.mob_data(mob_id)["days"]["2"]["greet"]
		var plain: Array = raw.filter(func(x): return x is String)
		var conditional: Array = raw.filter(func(x): return x is Dictionary)
		c.check("%s：2日目の文（挨拶%d行＋2杯以上の1行・反応 GOOD/OK/BAD 各1行・退店%d行）・注文の札はデータのまま %s" % [mob_id, mob_counts[mob_id][0], mob_counts[mob_id][2], str(mob_tags[mob_id])],
			plain.size() == mob_counts[mob_id][0] and conditional.size() == mob_counts[mob_id][1] and int(conditional[0]["min_count"]) == 2
				and (day2["reactions"] as Dictionary).keys().size() == 3 and not (day2["reactions"] as Dictionary).has("GREAT")
				and (day2["after_talk"] as Array).size() == mob_counts[mob_id][2] and day2["wanted_tags"] == mob_tags[mob_id]
				and ScheduleData.marker_problems(plain + day2["after_talk"], mob_id).is_empty())
		var day3 := ScheduleData.mob_data_for_day(mob_id, 3)
		c.check("%s：ほかの日は日をまたぐ文のまま（after_talk なし）" % mob_id, not day3.has("after_talk") and day3["greet"] == ScheduleData.mob_data(mob_id)["greet"])

	# --- 2. 市場 ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var before := Day1Events.prep_events({}, false)
	c.check("市場に着いたら張姐の会話（7行）→ 仕込む量（PREP_TIER の文は張姐の最後の問い）。食肉売場の文・前日の杯数の行は出さない",
		before.map(func(e): return str(e["text"])) == zhang and str(before.back()["type"]) == "PREP_TIER"
			and before.all(func(e): return str(e.get("part", "")) == "market_scene") and Day1Events.has_market_scene() and not Day1Events.has_market_exit_scene())
	var after := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	var types: Array = after.map(func(e): return str(e["type"]))
	var market_at := types.find("MARKET")
	var officer_lines: Array = after.slice(0, market_at).filter(func(e): return str(e["type"]) == "GREET").map(func(e): return str(e["text"]))
	c.check("選んだあと：「中仕込みにした。」（先頭は効果の無い文）→ 出汁を受け取る → 新人警官の会話（market_talk）→ 市場",
		str(after[0]["type"]) == "TEXT" and str(after[0]["text"]) == "中仕込みにした。" and str(after[1]["type"]) == "ADD_ITEM"
			and officer_lines == ScheduleData.episode_market_talk("officer", "officer_01") and types.slice(2, market_at).all(func(x): return x == "GREET"))
	c.check("払い方は今までどおり：市場の場面の行に支払いは無く、市場を出たあとの語りは「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」",
		not (before + after).any(func(e): return str(e["type"]) == "PAY") and str(after[market_at + 1]["text"]) == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。")
	var scraps := Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[0], true)
	c.check("端材屋の日も新人警官の会話は出る（場面の会話は市場の解禁と無関係）",
		scraps.filter(func(e): return str(e["type"]) == "GREET").map(func(e): return str(e["text"])) == ScheduleData.episode_market_talk("officer", "officer_01"))
	GameState.day_count = 3
	c.check("3日目は今までどおり（食肉売場へ来た・市場の場面なし）", not Day1Events.has_market_scene() and str(Day1Events.prep_events({}, false)[0]["text"]) == "食肉売場へ来た")

	# --- 3. モブの「2杯以上のときだけ」の1行 ---
	for mob_id in mob_tags:
		var raw: Array = ScheduleData.mob_data(mob_id)["days"]["2"]["greet"]
		var extra := str(raw.filter(func(x): return x is Dictionary)[0]["line"])
		var order_line := str(raw.filter(func(x): return x is String).back())
		var one = _setup_mob(t, mob_id, 1)
		var g1 := _greets(one)
		one.free()
		var two = _setup_mob(t, mob_id, 2)
		var g2 := _greets(two)
		two.free()
		var three = _setup_mob(t, mob_id, 4)
		var g4 := _greets(three)
		three.free()
		c.check("%s：1杯の組には「%s」を出さない・2杯以上の組は注文の行のすぐあとに出す" % [mob_id, extra],
			not g1.has(extra) and g1.back() == order_line and g2.back() == extra and g2[g2.size() - 2] == order_line and g4.back() == extra
				and not (g1 + g2).any(func(x): return str(x).contains("%d") or str(x).contains("{")), str(g2))
	c.check("min_count の行の読み口：文字列の行はそのまま・形の違う要素は残す（spoken_lines が落とす）",
		ScheduleData.mob_lines_for_count(["a", { "min_count": 2, "line": "b" }, { "x": 1 }], 1) == ["a", { "x": 1 }]
			and ScheduleData.mob_lines_for_count(["a", { "min_count": 2, "line": "b" }], 3) == ["a", "b"])

	# --- 4. 新人警官の仮の行 ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var officer_events := Day1Events.customer_events("officer")
	c.check("officer_01：REACT のあとに仮の行（「警官（提供後・共通会話）」など）を出さない（食後の本文が会計・退店まで持つ）",
		str(officer_events.back()["type"]) == "REACT" and not officer_events.any(func(e): return str(e.get("text", "")).contains("（提供後"))
			and str(Day1Events.after_serve_events("officer", "officer_01", { "served": true, "grade": "GOOD" }).back()["text"]) == "店主「仕事が終わってから言いな」")
	GameState.day_count = 4
	c.check("仮の文の officer_02 は今までどおり（仮の行が出る）", Day1Events.customer_events("officer").any(func(e): return str(e.get("text", "")).contains("（提供後")))

	# --- 5. 2日目を本番の画面で通す ---
	ReadState.reset("user://test_read_day2_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while GameState.day_count == 1 and guard < 6000:
		guard += 1
		if play.step() == "":
			break
	c.check("（前提）Day1 を閉店まで遊び、Day2 の朝へ進んだ", GameState.day_count == 2)
	var inbox := Dm.inbox(2).filter(func(x): return int(x["day"]) == 2)
	var dm_list: Array = inbox.map(func(x): return "%s %s" % [x["from"], x["time"]])
	c.check("Day2 の朝のDM：レックス（4:40・4:42）・阿強 5:50・張姐 6:40。新人警官の予告・レックスの予告は無い。セティヤの予告は差出人セティヤ",
		dm_list.has("レックス 4:40") and dm_list.has("レックス 4:42") and dm_list.has("阿強 5:50") and dm_list.has("張姐 6:40")
			and not inbox.any(func(x): return str(x.get("subject", "")) == "officer" or str(x.get("subject", "")) == "thug" or str(x["from"]) == "新人警官")
			and inbox.filter(func(x): return str(x.get("subject", "")) == "hooker").all(func(x): return str(x["from"]) == "セティヤ"), str(dm_list))
	var shown_lines := []
	var shown_keys := {}
	var bracket_shown := []
	var reactions := []
	var reacted := {}
	var plate := {}
	var served_at_close := []
	var lin_hidden_before_talk := true
	var lin_seen_after_talk := false
	var plan_slots: Array = []
	var plan_mobs := {}
	var name_at := {}   # UI準備Y：その行が出ているときの新人警官の表示名
	guard = 0
	while GameState.day_count == 2 and guard < 6000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if GameState.phase == GameState.Phase.PREP:
			var lin_visible := Sns.visible_ids(2, s.timeline_limit(), {}, s.market_talks_done()).has("d2_lin_alt_1410")
			if str(line.get("speaker_name", "")) == "張姐" and lin_visible:
				lin_hidden_before_talk = false
			if s.is_in_market() and lin_visible:
				lin_seen_after_talk = true
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
		if name != "" and not plate.has(name) and root.left.get_node("%NamePlate").visible:
			plate[name] = str(root.left.get_node("%NameLabel").text)
		if s.flow.runner != null and str(line.get("text", "")) != "" and str(line.get("type", "")) != "REACT":
			var line_key := "%d|%d|%d|%d|%s" % [GameState.phase, s.open.slot_index if s.open != null else -1, s.open.index if s.open != null else -1,
				s.flow.runner.index, str(line.get("text", ""))]
			if not shown_keys.has(line_key):
				shown_keys[line_key] = true
				shown_lines.append(name + str(line.get("text", "")))
				if str(line.get("speaker", "")) == "officer" or GameState.phase == GameState.Phase.OPEN:
					name_at[name + str(line.get("text", ""))] = CustomerMemory.display_name("officer")
		if GameState.phase == GameState.Phase.CLOSE and served_at_close.is_empty():
			served_at_close = GameState.served.duplicate(true)
		if play.step() == "":
			break
	c.check("（前提）Day2 を閉店まで遊び、Day3 の朝へ進んだ", GameState.day_count == 3, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("会話枠に〔〕の文（〔ゲーム〕・実装メモ）が一度も出ない", bracket_shown.is_empty(), str(bracket_shown))
	c.check("タイムラインのリンの 14:10：張姐の会話のあいだは見えず、市場（新人警官の会話のあと）では見える", lin_hidden_before_talk and lin_seen_after_talk)
	# 出てくるはずの順（張姐 → 新人警官（市場）→ 夜の枠の順に客。モブは出したときだけ椀のあとの会話）
	var expected := zhang.duplicate()
	expected.append_array(ScheduleData.episode_market_talk("officer", "officer_01"))
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
				var day2 := ScheduleData.mob_data_for_day(type_id, 2)
				expected.append_array(ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(day2["greet"], count)))
				if not declined.has(str(id)):
					expected.append_array(day2["after_talk"])
			else:
				var ep := ScheduleData.episode_data(str(id), str(slot["episode_id"]))
				expected.append_array(ScheduleData.spoken_lines(ep["greet"]))
				expected.append_array(ScheduleData.spoken_lines(ep["body"]))
	var got := shown_lines.filter(func(x): return str(x).contains("「") and not str(x).begins_with("「"))
	var first_diff := -1
	for i in range(maxi(got.size(), expected.size())):
		if i >= got.size() or i >= expected.size() or got[i] != expected[i]:
			first_diff = i
			break
	c.check("Day2 の元の文の行（%d行）が、張姐→新人警官（市場）→宵の口→夜半→明け方の順に、抜けも重なりも無く出た（モブ %s）" % [expected.size(), str(mob_types)],
		first_diff == -1, "最初に違う行 %d：%s ／ 期待 %s" % [first_diff, str(got[first_diff]) if first_diff >= 0 and first_diff < got.size() else "（無い）",
			str(expected[first_diff]) if first_diff >= 0 and first_diff < expected.size() else "（無い）"])
	var react_ok := true
	for r in reactions:
		var pool: Array = (r["pool"] as Dictionary).get(r["grade"], [])
		react_ok = react_ok and pool.has(r["text"]) and not str(r["text"]).contains("\n") and not str(r["text"]).contains("〔")
	c.check("反応は、判定の結果の段の元の文の1行だけ（%d回）" % reactions.size(), react_ok and reactions.size() >= 4,
		str(reactions.map(func(r): return "%s %s %s" % [r["customer"], r["grade"], r["text"]])))
	var rin_at := shown_lines.find("警官「リンです。皆、そう呼びます」")
	c.check("名前の札：警官（市場・来店）→「リンです」のあとの行から「リン」・セティヤ・モブ（人夫・夜番・運転手は来た組だけ）",
		plate.get("警官", "") == "警官" and plate.get("リン", "") == "リン" and plate.get("セティヤ", "") == "セティヤ" and plate.get("張姐", "") == "張姐"
			and rin_at >= 0 and shown_lines[rin_at + 1] == "店主「じゃあリン、捜される前に戻れ。先輩によろしくな」" and shown_lines[rin_at + 2] == "リン「はい。おやすみなさい」"
			and not shown_lines.slice(0, rin_at).any(func(x): return str(x).begins_with("リン「")), str(plate))
	c.check("UI準備Y：新人警官の表示名は「名前は。」の行まで「新人警官」、「リンです。皆、そう呼びます」が出た時点から「リン」（3日目の朝も）",
		name_at.get("店主「名前は。報告書には書かないから」", "") == "新人警官" and name_at.get("警官「リンです。皆、そう呼びます」", "") == "リン"
			and name_at.get("リン「はい。おやすみなさい」", "") == "リン" and CustomerMemory.display_name("officer") == "リン", str(name_at.get("警官「リンです。皆、そう呼びます」", "")))
	root.queue_free()

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()

