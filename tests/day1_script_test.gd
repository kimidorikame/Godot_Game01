extends RefCounted
## 中身U1：1日目の本番の文（planning/scenario/day1/ の8本）をゲームのデータに入れたことの検証。
##   1. 話し手の名前の札：行の頭の「名前「セリフ」」を名前と本文に分ける（split_speaker）
##   2. 〔演出〕の行：データには持つが、Event にしない（spoken_lines）。〔ゲーム〕の行は持たない（marker_problems）
##   3. データ：1日目の場面・モブ・朝の会話に印の問題が無い・注文の札・好物・名前
##   4. 朝の昼市場の会話（炭屋→水場→張記）：PREP の先頭・水道代は梁伯の場面の行のあとで払う・2日目には無い
##   5. モブのその日だけの文（days."1"）：1日目は元の文、2日目は日をまたぐ文。椀を出したあとの会話は、出したときだけ
##   6. 港湾労働者の OK：外れた札で出し分ける（OK_MISSING）。減点の OK は1つ目の OK
##   7. Day1 を最初から閉店まで本番の画面で通す：元の文の行が順に出る・〔演出〕〔ゲーム〕が出ない・反応は判定どおりの1行だけ・
##      名前の札（店主など）


const TALK_ID := "day1_market"


func _setup_mob(t: SceneTree, mob_type: String, count: int):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	GameState.today_plan["mob_instances"]["mob#9"] = { "type": mob_type, "count": count }
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": ["mob#9"] }])
	for id in ["nam_prik_pao", "meat_ball", "coconut_milk", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel.session.load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 80:
		guard += 1
		panel.session.next_event()
	return panel


## 椀を選んで団体に出し（n=0 なら断る）、REACT まで進めて、そのあとの列の文（GREET の text）を返す。
func _serve_mob(panel, picks: Array, n: int, ordered: int) -> Dictionary:
	for id in picks:
		panel.session.select_ingredient(id)
	if n > 0:
		panel.session.group_serve(n, ordered)
	else:
		panel.session.group_decline(ordered)
	var guard := 0
	while str(panel.session.flow.runner.current().get("type", "")) != "REACT" and guard < 10:
		guard += 1
		panel.session.next_event()
	var reaction: String = panel.session.current_reaction_text()
	var after := []
	for i in range(panel.session.flow.runner.index + 1, panel.session.flow.runner.events.size()):
		after.append(str(panel.session.flow.runner.events[i].get("text", "")))
	return { "reaction": reaction, "after": after }


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()

	# --- 1. 話し手の名前の札 ---
	c.check("「名前「セリフ」」は名前と「」からの本文に分かれる",
		PlaySession.split_speaker("阿強「まだやってる？」") == { "name": "阿強", "text": "「まだやってる？」" }
			and PlaySession.split_speaker("修理屋の声「読み取り機、下の端子も見せて。」") == { "name": "修理屋の声", "text": "「読み取り機、下の端子も見せて。」" }
			and PlaySession.split_speaker("労働者B「この辛さ、いいな。」　+¥5") == { "name": "労働者B", "text": "「この辛さ、いいな。」　+¥5" })
	c.check("名前の無い行は分けない（地の文・「はいよ、お待ち。」・句読点のある前置き・括弧の行）",
		str(PlaySession.split_speaker("「はいよ、お待ち。」")["name"]) == ""
			and str(PlaySession.split_speaker("荷捌き裏通りへ回る。半端市「拾味」。今日は財布が軽い")["name"]) == ""
			and str(PlaySession.split_speaker("（味を調える）")["name"]) == ""
			and str(PlaySession.split_speaker("レックス（場所代）")["name"]) == ""
			and str(PlaySession.split_speaker("配達員（2日目以降・注文: 辛い・スタミナ）")["name"]) == "")

	# --- 2. 〔演出〕〔ゲーム〕の印 ---
	c.check("spoken_lines：〔演出〕の行・空文字・文字列でない要素を落とす",
		ScheduleData.spoken_lines(["〔演出〕湯気。", "阿強「辛。」", "", 3, "店主「ほら。」"]) == ["阿強「辛。」", "店主「ほら。」"])
	var marks := ScheduleData.marker_problems(["〔ゲーム〕1杯目。", "阿強「〔演出〕のつもり」", "〔演出〕行の頭はよい"], "x")
	c.check("marker_problems：〔ゲーム〕の行と、行の途中の〔演出〕を弾く（行の頭の〔演出〕はよい）",
		marks.size() == 2 and str(marks[0]).contains("〔ゲーム〕") and str(marks[1]).contains("途中"), str(marks))

	# --- 3. データ ---
	for pair in [["delivery_man", "delivery_man_01"], ["thug", "thug_01"], ["granny", "granny_01"]]:
		var ep := ScheduleData.episode_data(pair[0], pair[1])
		c.check("%s：場面データの形・印に問題が無い・元の文の場所（source）を持つ" % pair[1],
			ScheduleData.scene_problems(ep).is_empty() and str(ep.get("source", "")).begins_with("planning/scenario/day1/")
				and FileAccess.file_exists("res://" + str(ep.get("source", ""))), str(ScheduleData.scene_problems(ep)))
	for mob in ["dock_workers", "inn_clerk"]:
		var form: Dictionary = ScheduleData.mob_data(mob)["days"]["1"]
		var problems := []
		for key in ["greet", "after_talk"]:
			problems.append_array(ScheduleData.marker_problems(form[key], key))
		for key in form["reactions"]:
			if form["reactions"][key] is Array:
				problems.append_array(ScheduleData.marker_problems(form["reactions"][key], key))
		c.check("%s の1日目の文：印に問題が無い・GREAT は無い（モブ）" % mob, problems.is_empty() and not (form["reactions"] as Dictionary).has("GREAT"), str(problems))
	var talk := ScheduleData.talk_data(TALK_ID)
	var talk_problems := []
	for part in talk["parts"]:
		talk_problems.append_array(ScheduleData.marker_problems((part["lines"] as Array).filter(func(l): return l is String), str(part["place"])))
	c.check("朝の会話（data/talks/day1_market.json）：炭屋→共同水場→張記の3場面・話し手・印に問題が無い",
		talk["parts"].map(func(p): return str(p["place"])) == ["炭屋", "共同水場", "張記肉類加工"]
			and talk["parts"].map(func(p): return str(p["speaker"])) == ["サミル", "梁伯", "張姐"] and talk_problems.is_empty(), str(talk_problems))
	var cups := ScheduleData.episode_cups("delivery_man", "delivery_man_01")
	c.check("阿強：3杯。1・2杯目は札を持たない（プロフィールの 辛い＋スタミナ・好物 豆腐）、3杯目は持ち帰りで好物なし",
		cups.size() == 3 and not cups[0].has("tags") and not cups[1].has("tags") and cups[2].has("tags") and cups[2]["favorite"] == false
			and ScheduleData.customer_profile("delivery_man")["wanted_tags"] == ["HOT", "POWER"] and ScheduleData.customer_profile("delivery_man")["favorite"] == "tofu")
	c.check("レックス＝まろやか＋やさしい（好物 肉団子）・ターニャ婆＝うましお＋腹もち（好物 モツ）・港湾労働者＝辛い＋スタミナ・安宿の夜勤受付＝まろやか＋やさしい",
		ScheduleData.customer_profile("thug")["wanted_tags"] == ["MELLOW", "GENTLE"] and ScheduleData.customer_profile("thug")["favorite"] == "meat_ball"
			and ScheduleData.customer_profile("granny")["wanted_tags"] == ["SAVORY", "FILLING"] and ScheduleData.customer_profile("granny")["favorite"] == "offal"
			and ScheduleData.mob_data("dock_workers")["wanted_tags"] == ["HOT", "POWER"] and ScheduleData.mob_data("inn_clerk")["wanted_tags"] == ["MELLOW", "GENTLE"])
	c.check("名前：阿強・レックス・ターニャ婆（1日目の最初から。DMの差出人も同じ名前）",
		ScheduleData.customer_display_name("delivery_man") == "阿強" and ScheduleData.customer_display_name("thug") == "レックス"
			and ScheduleData.customer_display_name("granny") == "ターニャ婆"
			and str(Dm.data()["previews"]["pools"]["delivery_man"]["from"]) == "阿強" and str(Dm.data()["previews"]["pools"]["thug"]["from"]) == "レックス"
			and str(Dm.data()["previews"]["pools"]["granny"]["from"]) == "ターニャ婆")

	# --- 4. 朝の昼市場の会話（PREP の先頭） ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var morning := Day1Events.morning_talk_events()
	var spoken_total := 0
	for part in talk["parts"]:
		spoken_total += ScheduleData.spoken_lines(part["lines"]).size()
	var pays := morning.filter(func(e): return str(e["type"]) == "PAY")
	var pay_at := -1
	for i in range(morning.size()):
		if str(morning[i]["type"]) == "PAY":
			pay_at = i
	c.check("Day1：朝の会話は行（TEXT）だけ＋水道代の PAY が1つ（kind=water・50・文「梁伯（水道代）」）。〔演出〕は出さない",
		morning.size() == spoken_total + 1 and pays.size() == 1 and int(pays[0]["amount"]) == 50 and str(pays[0]["kind"]) == "water"
			and str(pays[0]["text"]) == "梁伯（水道代）" and morning.all(func(e): return not str(e["text"]).contains("〔")), str(pays))
	c.check("水道代は梁伯の「へこみのおかげで、こぼさずに済んでるんだ」のすぐあと・先頭は行（列の先頭の効果は適用されない）",
		pay_at > 0 and str(morning[pay_at - 1]["text"]) == "梁伯「へこみのおかげで、こぼさずに済んでるんだ」" and str(morning[0]["type"]) == "TEXT"
			and str(morning[0]["text"]) == "サミル「縫ったのか」")
	var prep := Day1Events.prep_events({}, false)
	c.check("Day1 の PREP の列は朝の会話から始まり、そのあとに初日セットの受け取り",
		prep.slice(0, morning.size()) == morning and str(prep[morning.size()]["text"]) == "いつもの仕入れ先で、仕込みに使う分をまとめて受け取った。")
	GameState.day_count = 2
	c.check("Day2 には朝の会話が無い（PREP の列は今までどおり）", Day1Events.morning_talk_events().is_empty()
		and str(Day1Events.prep_events({}, false)[0]["text"]) == "食肉売場へ来た")

	# --- 5. モブのその日だけの文 ---
	var day1_dock := ScheduleData.mob_data_for_day("dock_workers", 1)
	var day2_dock := ScheduleData.mob_data_for_day("dock_workers", 2)
	c.check("港湾労働者：1日目は元の文（挨拶・反応・椀のあとの会話）、2日目は日をまたぐ文のまま（after_talk なし）・注文は同じ",
		str(day1_dock["greet"].back()) == "労働者A「頼む。あいつの椀から取ると、数でばれる」" and day1_dock.has("after_talk")
			and day2_dock["greet"] == ScheduleData.mob_data("dock_workers")["greet"] and not day2_dock.has("after_talk")
			and day1_dock["wanted_tags"] == day2_dock["wanted_tags"])
	var panel = _setup_mob(t, "dock_workers", 2)
	var greets: Array = panel.session.flow.runner.events.filter(func(e): return str(e["type"]) == "GREET").map(func(e): return str(e["text"]))
	c.check("1日目の港湾労働者の挨拶は元の文（〔演出〕を除く）・人数の「%d人」は出ない", greets == ScheduleData.spoken_lines(day1_dock["greet"]), str(greets))
	var served: Dictionary = _serve_mob(panel, ["nam_prik_pao", "meat_ball"], 2, 2)
	c.check("2人に出した：GOOD の反応（元の文の1行）のすぐあとに、椀のあとの会話（元の文。〔演出〕なし）",
		served["reaction"] == "労働者B「この辛さ、いいな。底にもまだ肉がある」"
			and (served["after"] as Array).slice(0, ScheduleData.spoken_lines(day1_dock["after_talk"]).size()) == ScheduleData.spoken_lines(day1_dock["after_talk"]),
		str(served))
	panel.free()
	panel = _setup_mob(t, "dock_workers", 2)
	var declined: Dictionary = _serve_mob(panel, ["nam_prik_pao", "meat_ball"], 0, 2)
	c.check("断った：椀のあとの会話は出ない", not (declined["after"] as Array).has(str(ScheduleData.spoken_lines(day1_dock["after_talk"])[0])), str(declined))
	panel.free()

	# --- 6. 港湾労働者の OK の出し分け ---
	panel = _setup_mob(t, "dock_workers", 2)
	var ok_hot: Dictionary = _serve_mob(panel, ["nam_prik_pao", "tofu"], 2, 2)   # 辛さは合った・肉が外れた（POWER が外れた）
	c.check("OK（辛さは合った・肉が外れた）：「汗はかけた。肉っ気はもうちょい欲しかったけど」", ok_hot["reaction"] == "労働者B「汗はかけた。肉っ気はもうちょい欲しかったけど」", str(ok_hot["reaction"]))
	panel.free()
	panel = _setup_mob(t, "dock_workers", 2)
	var ok_meat: Dictionary = _serve_mob(panel, ["coconut_milk", "meat_ball"], 2, 2)   # 肉は合った・辛さが外れた（HOT が外れた）
	c.check("OK（肉は合った・辛さが外れた）：「腹にはたまる。辛さ、もう一段いける？」", ok_meat["reaction"] == "労働者B「腹にはたまる。辛さ、もう一段いける？」", str(ok_meat["reaction"]))
	panel.free()
	c.check("missing_tags：札が2つとも合えば外れは無し（減点で OK になったときは1つ目の OK の文）",
		PlaySession.missing_tags(["HOT", "POWER"], { "additions": ["nam_prik_pao", "meat_ball"] }).is_empty()
			and PlaySession.missing_tags(["HOT", "POWER"], { "additions": ["tofu"] }) == ["HOT", "POWER"])

	# --- 7. Day1 を最初から閉店まで、本番の画面で通す ---
	ReadState.reset("user://test_read_day1_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var log_copy := []
	var bracket_shown := []
	var reactions := []   # [{ grade, text, pool }]
	var reacted := {}
	var plate := {}       # 名前の札の確かめ：話し手の名前 → 札の文字・本文の頭
	var guard := 0
	while GameState.day_count == 1 and guard < 5000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if str(line.get("type", "")) == "REACT" and str(line.get("text", "")) != "" and s.open != null:
			var key := "%d|%d|%d" % [s.open.slot_index, s.open.index, s.flow.runner.index]
			if not reacted.has(key):
				reacted[key] = true
				var ev: Dictionary = s.flow.runner.current()
				reactions.append({ "grade": str(s.open.current_bowl.get("result", "")), "text": s.current_reaction_text(),
					"pool": ev.get("reactions", {}), "customer": str(ev.get("customer", "")) })
		var name := str(line.get("speaker_name", ""))
		if name != "" and not plate.has(name) and root.left.get_node("%NamePlate").visible:
			plate[name] = [str(root.left.get_node("%NameLabel").text), box_text.substr(0, 1)]
		if GameState.phase == GameState.Phase.CLOSE or GameState.phase == GameState.Phase.OPEN or GameState.phase == GameState.Phase.PREP:
			log_copy = TalkLog.entries.duplicate(true)
		if play.step() == "":
			break
	c.check("（前提）Day1 を閉店まで遊び、Day2 の朝へ進んだ", GameState.day_count == 2, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("会話枠に〔演出〕〔ゲーム〕の文が一度も出ない", bracket_shown.is_empty(), str(bracket_shown))
	# 元の文の行（名前「セリフ」）を、出てくるはずの順に並べる（〔演出〕は除く。椀は全部出した前提）
	var expected := []
	for part in talk["parts"]:
		expected.append_array(ScheduleData.spoken_lines(part["lines"]))
	var dm := ScheduleData.episode_data("delivery_man", "delivery_man_01")
	expected.append_array(ScheduleData.spoken_lines(dm["greet"]))
	expected.append(str(cups[0]["serve"]))
	for cup in cups:
		expected.append_array(ScheduleData.spoken_lines(cup["after_talk"]))
	expected.append_array(ScheduleData.spoken_lines(day1_dock["greet"]))
	expected.append_array(ScheduleData.spoken_lines(day1_dock["after_talk"]))
	var thug := ScheduleData.episode_data("thug", "thug_01")
	for key in ["greet", "body", "after_bill"]:
		expected.append_array(ScheduleData.spoken_lines(thug[key]))
	var inn := ScheduleData.mob_data_for_day("inn_clerk", 1)
	expected.append_array(ScheduleData.spoken_lines(inn["greet"]))
	expected.append_array(ScheduleData.spoken_lines(inn["after_talk"]))
	var granny := ScheduleData.episode_data("granny", "granny_01")
	for key in ["greet", "body"]:
		expected.append_array(ScheduleData.spoken_lines(granny[key]))
	var got := []
	for e in log_copy:
		if str(e["kind"]) != "reaction" and str(e["speaker"]) != "" and str(e["text"]).begins_with("「"):
			got.append(str(e["speaker"]) + str(e["text"]))
	var first_diff := -1
	for i in range(maxi(got.size(), expected.size())):
		if i >= got.size() or i >= expected.size() or got[i] != expected[i]:
			first_diff = i
			break
	c.check("Day1 の元の文の行（%d行）が、朝の会話→阿強→港湾労働者→レックス→安宿の夜勤受付→ターニャ婆の順に、抜けも重なりも無く出た" % expected.size(),
		first_diff == -1, "最初に違う行 %d：%s ／ 期待 %s" % [first_diff, str(got[first_diff]) if first_diff >= 0 and first_diff < got.size() else "（無い）",
			str(expected[first_diff]) if first_diff >= 0 and first_diff < expected.size() else "（無い）"])
	c.check("反応は7回（阿強3杯・港湾労働者・レックス・安宿の夜勤受付・ターニャ婆）", reactions.size() == 7, str(reactions.map(func(r): return r["customer"] + ":" + r["grade"])))
	var react_ok := true
	for r in reactions:
		var pool: Array = (r["pool"] as Dictionary).get(r["grade"], [])
		var missing_pool: Dictionary = (r["pool"] as Dictionary).get("OK_MISSING", {}) if r["grade"] == "OK" else {}
		var allowed := pool.duplicate()
		for k in missing_pool:
			allowed.append_array(missing_pool[k])
		react_ok = react_ok and allowed.has(r["text"]) and not str(r["text"]).contains("\n") and not str(r["text"]).contains("〔")
	c.check("反応は、判定の結果の段の元の文の1行だけ（改行・〔演出〕なし）", react_ok,
		str(reactions.map(func(r): return "%s %s %s" % [r["customer"], r["grade"], r["text"]])))
	c.check("名前の札：店主の行は「店主」、客の行はその人の名前（行の頭の名前）・本文は「」から",
		plate.get("店主", [])  == ["店主", "「"] and plate.get("阿強", []) == ["阿強", "「"] and plate.get("サミル", []) == ["サミル", "「"]
			and plate.get("労働者B", []) == ["労働者B", "「"] and plate.get("端末音声", []) == ["端末音声", "「"], str(plate))
	root.queue_free()

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()
