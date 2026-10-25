extends RefCounted
## DM（SNSタブ）と張記の店主との会話（UI準備C③・DESIGN.md 10.4）の検証。
## 対象：DMのデータの形・仮の文の種類（名前あり客の条件／モブの条件／many／few）、届く条件（名前あり客は初めて提供した翌日から・
## モブは同じ種類に2夜提供した翌日から・客でない差出人は条件なし）、匂わせの向きと需要の中心が矛盾しないこと（データのテスト）、
## 未読、モブの種類の記録（mob_types_served）、張記の会話（Day1は目安の杯数・Day2以降は前日の事実だけ・クズ野菜の日は無し）。
## 文面は仮。向き（hint）と条件はデータが持つので、文を差し替えても、このテストが矛盾を弾く。

func _state(day: int, reputation: int = 30) -> void:
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.reputation = reputation
	GameState.today_plan = { "day": day, "slots": [], "mob_instances": {}, "demand_center": -1 }


func _ids(items: Array) -> Array:
	return items.map(func(x): return str(x["id"]))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Dm.clear_cache()

	# --- 1. データの形 ---
	c.check("キャンペーンのDMのidは week7（Rules.dm）", Rules.dm() == "week7")
	c.check("DMのデータが読め、形の問題が無い", Dm.problems().is_empty(), str(Dm.problems()))
	var all_items: Array = []
	for day in range(1, Rules.final_day() + 1):
		for item in Dm.items_for_day(day):
			item["day"] = day
			all_items.append(item)
	c.check("DMは Day2〜7 に毎日1通以上（Day1は無し）", range(2, 8).all(func(d): return not Dm.items_for_day(d).is_empty()) and Dm.items_for_day(1).is_empty())
	c.check("仮の文の種類：名前あり客の条件が最低1通", all_items.any(func(x): return str(x["from_kind"]) == "customer" and (x["requires"] as Dictionary).has("customer")))
	c.check("仮の文の種類：モブの条件が最低1通", all_items.any(func(x): return str(x["from_kind"]) == "mob" and (x["requires"] as Dictionary).has("mob_type")))
	c.check("仮の文の種類：hint:many が最低1通", all_items.any(func(x): return str(x["hint"]) == "many"))
	c.check("仮の文の種類：hint:few が最低1通", all_items.any(func(x): return str(x["hint"]) == "few"))
	c.check("客でない差出人（npc）は条件なしで届く（requires を持たない）",
		all_items.filter(func(x): return str(x["from_kind"]) == "npc").all(func(x): return not x.has("requires")))
	c.check("全部に provisional が付いている（本文はチャット側で差し替える）", all_items.all(func(x): return bool(x.get("provisional", false))))
	c.check("DMに必須情報（must_info）を置かない（10.5.5）", all_items.all(func(x): return not x.has("must_info")))
	# 壊れたデータは落ちる
	var broken: Dictionary = (Dm.data() as Dictionary).duplicate(true)
	broken["days"]["2"][0]["hint"] = "lots"
	c.check("hint が many／few／none 以外だと落ちる", not Dm.problems(broken).is_empty())
	broken = (Dm.data() as Dictionary).duplicate(true)
	broken["days"]["2"][0]["must_info"] = ["checkpoints"]
	c.check("DMに must_info があると落ちる", not Dm.problems(broken).is_empty())
	broken = (Dm.data() as Dictionary).duplicate(true)
	broken["days"]["2"][1]["requires"] = { "customer": "no_such_customer" }
	c.check("存在しない客を条件にすると落ちる", not Dm.problems(broken).is_empty())
	broken = (Dm.data() as Dictionary).duplicate(true)
	broken["days"]["2"][0]["requires"] = { "customer": "officer" }
	c.check("客でない差出人（npc）に条件を付けると落ちる", not Dm.problems(broken).is_empty())
	broken = (Dm.data() as Dictionary).duplicate(true)
	broken["days"]["2"].append(broken["days"]["2"][0].duplicate(true))
	c.check("DMの id が重複すると落ちる", not Dm.problems(broken).is_empty())

	# --- 2. 匂わせの向きと需要の中心（データのテスト）---
	var table: Array = Rules.demand_table()
	var centers: Array = table.map(func(r): return int((r as Array)[1]))   # 多い順：17・14・11・9・7
	var many_min := UiLabels.demand_row_center(str(Dm.data()["hints"]["many"]["demand_word"]))
	var few_max := UiLabels.demand_row_center(str(Dm.data()["hints"]["few"]["demand_word"]))
	c.check("条件の数値は需要表と客足の言葉から読む：many＝「多め」の行の中心、few＝「少ない」の行の中心",
		many_min == int((table[2] as Array)[1]) and few_max == int((table.back() as Array)[1]) and many_min > few_max, "%d・%d" % [many_min, few_max])
	var consistent := true
	var detail := ""
	for center in centers:
		for item in all_items:
			var allowed := Dm.hint_allows(str(item["hint"]), int(center))
			# 矛盾：多いのに中心が少ない側／少ないのに中心が多い側
			if str(item["hint"]) == "many" and allowed and int(center) < many_min:
				consistent = false
				detail += " %s@%d" % [str(item["id"]), center]
			if str(item["hint"]) == "few" and allowed and int(center) > few_max:
				consistent = false
				detail += " %s@%d" % [str(item["id"]), center]
	c.check("どの需要の中心でも、届くDMの向きは中心と矛盾しない（many＝多め以上、few＝少ないだけ）", consistent, detail)
	var many_centers: Array = centers.filter(func(x): return Dm.hint_allows("many", int(x)))
	var few_centers: Array = centers.filter(func(x): return Dm.hint_allows("few", int(x)))
	c.check("many が届く中心＝多め以上の行（17・14・11）、few＝少ないの行だけ（7）、none はどれでも",
		many_centers == centers.slice(0, 3) and few_centers == [centers.back()] and centers.all(func(x): return Dm.hint_allows("none", int(x))),
		"%s %s" % [str(many_centers), str(few_centers)])
	c.check("その日の中心が分からない（-1）とき、many・few は届かない", not Dm.hint_allows("many", -1) and not Dm.hint_allows("few", -1))
	# 匂わせの文：ニュース・共通イベントに「客足」の語を含めない。DMは hint を持つものだけ対象外
	var news_texts: Array = []
	for day in range(1, Rules.final_day() + 1):
		var entry := News.day_entry(day)
		for item in entry["news"]:
			news_texts.append(str(item.get("headline", "")))
			news_texts.append_array(item.get("body", []))
		for item in entry["events"]:
			news_texts.append_array(item.get("lines", []))
	c.check("ニュースと共通イベントの本文に「客足」の語を含めない（需要は評判で決まり、ニュースでは言えないため）",
		not news_texts.any(func(x): return str(x).contains("客足")), str(news_texts.filter(func(x): return str(x).contains("客足"))))
	c.check("DMは hint を持つものだけ「客足」の語を使ってよい（hint:none のDMは使わない）",
		not all_items.any(func(x): return str(x["hint"]) == "none" and str(x["text"]).contains("客足")))
	c.check("DMとニュースの本文に数（「11杯」「3組」）を書かない", not all_items.any(func(x): return _has_count(str(x["text"]))))

	# --- 3. 届く条件 ---
	_state(2, 30)
	c.check("市場の顔なじみ（条件なし）は、その日に届く。Day2は配達員のDMはまだ（まだ誰にも提供していない）",
		_ids(Dm.delivered_for_day(2)) == ["d2_market"], str(_ids(Dm.delivered_for_day(2))))
	GameState.customer_memory["delivery_man"] = { "favorite_known": false, "visits": [{ "day": 1, "served": 3, "grade": "GOOD" }], "facts": {},
		"seen_episodes": [] }
	c.check("名前あり客に初めて提供した翌日から、その客のDMが届く（Day1に提供→Day2）",
		_ids(Dm.delivered_for_day(2)) == ["d2_market", "d2_delivery_man"], str(_ids(Dm.delivered_for_day(2))))
	GameState.customer_memory["delivery_man"]["visits"] = [{ "day": 2, "served": 1, "grade": "GOOD" }]
	c.check("提供した当日は届かない（翌日から）", not _ids(Dm.delivered_for_day(2)).has("d2_delivery_man"))
	GameState.customer_memory["delivery_man"]["visits"] = [{ "day": 1, "served": 0, "grade": "" }]
	c.check("来ただけで1杯も提供していない客のDMは届かない", not _ids(Dm.delivered_for_day(2)).has("d2_delivery_man"))
	# 条件が後から満たされても、過去の日のDMは届かない
	_state(5, 30)
	GameState.customer_memory["officer"] = { "favorite_known": false, "visits": [{ "day": 3, "served": 1, "grade": "GOOD" }], "facts": {},
		"seen_episodes": [] }
	GameState.day_records = [{ "day": 2, "opening_reputation": 50 }]
	c.check("Day3に初めて提供した客のDM（Day3の項目）は、あとから条件が満たされても届かない",
		not _ids(Dm.inbox(5)).has("d3_officer"), str(_ids(Dm.inbox(5))))
	# モブ：同じ種類に2夜提供した翌日から
	_state(4, 50)
	GameState.today_plan["demand_center"] = 11
	GameState.day_records = [{ "day": 1, "opening_reputation": 30, "mob_types_served": ["dock_workers"] },
		{ "day": 2, "opening_reputation": 30, "mob_types_served": ["inn_clerk"] },
		{ "day": 3, "opening_reputation": 30, "mob_types_served": [] }]
	c.check("モブは同じ種類に2夜提供するまで届かない（dock_workers は1夜だけ）", not _ids(Dm.delivered_for_day(4)).has("d4_dock_workers"))
	GameState.day_records[1]["mob_types_served"] = ["dock_workers"]
	c.check("同じ種類（dock_workers）に2夜提供した翌日（Day4）から届く（今日の中心が多め以上のとき）",
		_ids(Dm.delivered_for_day(4)).has("d4_dock_workers"), str(_ids(Dm.delivered_for_day(4))))
	GameState.today_plan["demand_center"] = 9
	c.check("条件を満たしていても、匂わせ（many）が今日の中心と矛盾する日（中心9）には届かない", not _ids(Dm.delivered_for_day(4)).has("d4_dock_workers"))
	c.check("同じ日・同じ状態の npc のDMは、中心に関わらず届く", _ids(Dm.delivered_for_day(4)).has("d4_market"))
	GameState.day_records[1]["mob_types_served"] = ["dock_workers"]
	GameState.day_records.append({ "day": 4, "opening_reputation": 30, "mob_types_served": ["dock_workers"] })
	c.check("2夜の数え方は「その日より前」の夜だけ（Day4の夜は Day4 には数えない）", Dm.mob_nights_before("dock_workers", 4) == 2
		and Dm.mob_nights_before("dock_workers", 5) == 3 and Dm.mob_nights_before("dock_workers", 1) == 0)

	# 匂わせは「その日の朝」の中心で決まる：過ぎた日は、その朝の評判から引く
	_state(6, 65)
	GameState.today_plan["demand_center"] = 14
	GameState.day_records = [{ "day": 2, "opening_reputation": 30 }, { "day": 3, "opening_reputation": 10 }, { "day": 4, "opening_reputation": 50 },
		{ "day": 5, "opening_reputation": 50 }]
	c.check("過ぎた日の中心は、その朝の評判から需要表で引く（Day3は評判10→少ない行）", Dm.center_of_day(3) == few_max and Dm.center_of_day(4) == many_min)
	c.check("今日の中心は朝に確定した値（today_plan）", Dm.center_of_day(6) == 14)
	c.check("Day1は固定需要の値", Dm.center_of_day(1) == int(Rules.day_overrides(1)["fixed_demand"]))
	var inbox_ids := _ids(Dm.inbox(6))
	c.check("Day3は中心が少ない日だった：few のDM（d3_market_quiet）は読み返せる", inbox_ids.has("d3_market_quiet"), str(inbox_ids))
	GameState.day_records[1]["opening_reputation"] = 50
	c.check("同じ日が中心の多い日なら few は届かなかった扱い（過去の日も、その朝の状態で決まる）", not _ids(Dm.inbox(6)).has("d3_market_quiet"))
	c.check("一覧は新しい日が上", _day_sorted_desc(Dm.inbox(6)))

	# --- 4. 未読（ReadState。保存とは別）---
	_state(2, 30)
	ReadState.reset("user://test_read_state_dm.json")
	var panel_session := PlaySession.new()
	t.root.add_child(panel_session)
	c.check("届いたDMは未読", panel_session.dm_unread_count() == 1 and bool(panel_session.phone_dm()[0]["unread"]))
	panel_session.mark_dms_read()
	c.check("読んだ扱いにすると未読は0・各DMの unread が false", panel_session.dm_unread_count() == 0 and not bool(panel_session.phone_dm()[0]["unread"]))
	c.check("既読はDMのidで持つ（文が差し替わっても読んだままにする）",
		ReadState.is_read(ReadState.line_key("dm", "", "d2_market", "d2_market")))
	panel_session.free()
	ReadState.reset("user://test_read_state.json")

	# --- 5. モブの種類の記録（日次ログ mob_types_served）---
	_state(3, 30)
	GameState.today_plan["mob_instances"] = { "mob#0": { "type": "dock_workers", "count": 2 }, "mob#1": { "type": "inn_clerk", "count": 2 } }
	GameState.served = [{ "customer": "mob#0", "servings": 2, "sale": 90 }, { "customer": "mob#1", "servings": 0, "declined": true },
		{ "customer": "delivery_man", "servings": 1, "sale": 45 }, { "customer": "mob#0", "servings": 1, "discarded": true }]
	var recorder := PlaySession.new()
	t.root.add_child(recorder)
	c.check("その夜に1杯以上提供したモブの種類だけ（断った・廃棄・名前あり客は数えない）", recorder.mob_types_served_tonight() == ["dock_workers"],
		str(recorder.mob_types_served_tonight()))
	recorder.free()

	# --- 6. 張記の店主との会話（鍋の素を選ぶ直前）---
	_state(1, 30)
	var day1 := Day1Events.prep_talk_events()
	var fixed := int(Rules.day_overrides(1)["fixed_demand"])
	c.check("Day1：店主の問いのあと、主人公が目安の杯数を一度だけ言う（数は fixed_demand から読む）",
		day1.size() == 2 and str(day1[0]["text"]) == "「今日はどれぐらい仕込む？」" and str(day1[1]["text"]).contains("%d杯" % fixed),
		str(day1))
	c.check("会話は表示だけの TEXT（part:prep_talk）", day1.all(func(e): return str(e["type"]) == "TEXT" and str(e["part"]) == "prep_talk"))
	_state(2, 30)
	c.check("前日の記録が無いDay2は、店主の問いだけ", Day1Events.prep_talk_events().size() == 1)
	GameState.day_records = [{ "day": 1, "planned_cups": 9, "unserved_cups": 0, "sale_total": 405 }]
	var talk := Day1Events.prep_talk_events()
	c.check("Day2：主人公は前日の注文の杯数だけを言う（足りなかった杯数が0なら言わない）",
		talk.size() == 2 and str(talk[1]["text"]) == "「昨日は9杯の注文だった」", str(talk))
	GameState.day_records = [{ "day": 1, "planned_cups": 11, "unserved_cups": 2 }]
	talk = Day1Events.prep_talk_events()
	c.check("足りなかった杯数があれば、それも言う", str(talk[1]["text"]) == "「昨日は11杯の注文だった。2杯、足りなかった」", str(talk))
	c.check("今夜の見込みの数は言わない（前日の事実の数以外の数字を含まない）",
		str(talk[1]["text"]).replace("11", "").replace("2", "").replace("杯", "").find("0") == -1 and not str(talk[1]["text"]).contains(str(Dm.center_of_day(2))))
	# 前日の注文の杯数は、前日成績に出る「注文◯杯」と同じ値（planned_cups＝その夜の注文の総杯数）
	var seer := PlaySession.new()
	t.root.add_child(seer)
	c.check("使う値は previous_day_record() の planned_cups（前日成績の「注文◯杯」と同じ）",
		int(seer.previous_day_record()["planned_cups"]) == 11 and str(talk[1]["text"]).contains("11杯"))
	seer.free()
	# 組み立て：クズ野菜ベースの日は会話を入れない。通常の日は PREP_TIER の直前
	var normal := Day1Events.prep_events({}, false)
	c.check("通常の日：食肉売場のあと PREP_TIER の直前に会話が並ぶ",
		str(normal[normal.size() - 1]["type"]) == "PREP_TIER" and str(normal[normal.size() - 2]["part"]) == "prep_talk")
	var scraps := Day1Events.prep_events({}, true)
	c.check("クズ野菜ベースの日（鍋の素を選ばない日）は会話を入れない", not scraps.any(func(e): return str(e.get("part", "")) == "prep_talk"))
	return c.finish()


## 本文に数（「11杯」「3組」「5人」の形）が入っているか。
func _has_count(text: String) -> bool:
	var re := RegEx.new()
	re.compile("[0-9０-９]+\\s*(杯|組|人)")
	return re.search(text) != null


func _day_sorted_desc(items: Array) -> bool:
	for i in range(items.size() - 1):
		if int(items[i]["day"]) < int(items[i + 1]["day"]):
			return false
	return true
