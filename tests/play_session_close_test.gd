extends RefCounted
## PlaySession（UI準備A④：閉店・日次ログ・基金）の検証。
## 対象：日の終わりの自動処理（session が day_ending を自分で受ける）・日次ログの組み立てと前日成績の文・
## 今夜の結果／前日成績の問い・修繕基金の操作と画面用の中身（fund_view）・減点の理由コード（sale_hint）。
## 操作・集計の中身そのもの（評判の更新・基金の対象と上限・日次ログのファイルなど）は既存のスイートが確かめる。


func _panel(t: SceneTree, day: int, money: int):
	GameState.reset_for_new_game()
	GameState.day_count = day
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.ledger.clear()
	GameState.money = money
	GameState.reputation = 55
	GameState.today_plan = { "day": day, "demand_center": 14, "slots": [], "mob_instances": {} }
	return panel


func _to_close_done(panel) -> void:
	panel.flow.force_phase(GameState.Phase.CLOSE)
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.DONE and guard < 100:
		guard += 1
		panel.session.next_event()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 数え方の小さな関数（評点・廃棄額） ---
	var p1 = _panel(t, 2, 500)
	var s: PlaySession = p1.session
	c.check("当夜品質：(GREAT100＋GOOD75)÷判定対象4杯＝43.75、対象0杯なら0",
		is_equal_approx(s.quality_score({ "GREAT": 1, "GOOD": 1 }, 4), 43.75) and s.quality_score({ "GREAT": 3 }, 0) == 0.0)
	c.check("廃棄額は各品目の value の合計", s.spoiled_value({ "tofu": { "value": 24 }, "x": { "value": 6 } }) == 30)
	c.check("橋 _quality_score／_spoiled_value も同じ値", is_equal_approx(p1._quality_score({ "OK": 2 }, 4), 17.5)
		and p1._spoiled_value({ "tofu": { "value": 24 } }) == 24)

	# --- 2. 今夜の結果（閉店の画面）：日次ログと同じ元から読む ---
	s.log_planned_cups = 9
	s.log_quality_counts = { "GREAT": 0, "GOOD": 1, "OK": 1, "BAD": 0, "": 0 }
	GameState.served = [{ "servings": 1, "sale": 45 }, { "servings": 1, "sale": 45 },
		{ "servings": 3, "sale": 135, "discarded": true }]
	var result: Dictionary = s.tonight_result()
	c.check("今夜の結果：注文9・提供2（廃棄した杯は数えない）・未提供7・売上90・評価の内訳",
		result["ordered_cups"] == 9 and result["served_cups"] == 2 and result["unserved_cups"] == 7
			and result["sales"] == 90 and result["grades"]["GOOD"] == 1 and result["grades"]["OK"] == 1, str(result))
	c.check("橋 _log_planned_cups と同じ元を指す", p1._log_planned_cups == 9)

	# --- 3. 日の終わり：session が自分で受け、前日成績の文と日次ログ・累計を作る（1回だけ） ---
	GameState.day_records = []
	s.last_day_summary_text = ""
	GameState.phase = GameState.Phase.NEXT_DAY
	p1.flow.advance_phase()   # NEXT_DAY→WAKE。日の終わり（day_ending）→日次リセット
	c.check("日の終わりは1回だけ処理され、その日の記録が累計に1件入る（DebugPanelは結線していない）",
		GameState.day_records.size() == 1 and int(GameState.day_records[0]["day"]) == 2, str(GameState.day_records.size()))
	c.check("記録は日次ログと同じキー（提供・未提供・売上・品質・早期閉店など）",
		["day", "opening_money", "closing_money", "planned_cups", "served_cups", "unserved_cups", "sale_total",
			"quality_counts", "quality", "spoiled_value", "water_used", "dashi_used", "closed_early",
			"spend_by_category", "regular_cups", "regular_great", "regular_visits"].all(
				func(k): return GameState.day_records[0].has(k)))
	c.check("翌朝（Day3）の前日成績の問い：前日（Day2）の記録を返す", GameState.day_count == 3
		and int(s.previous_day_record().get("day", 0)) == 2 and int(s.previous_day_record()["served_cups"]) == 2)
	var summary: String = s.format_day_summary(GameState.day_records[0])
	c.check("前日成績の文：見出し・提供杯数・品質の行が出る（橋 _format_day_summary も同じ）",
		summary.contains("◆前日（Day2）の成績◆") and summary.contains("提供: 2/9杯（未提供7杯）") and summary.contains("品質:")
			and p1._format_day_summary(GameState.day_records[0]) == summary, summary)
	p1.free()
	var p1b = _panel(t, 1, 500)
	c.check("Day1の朝は前日成績が無い（空）", p1b.session.previous_day_record().is_empty())
	p1b.free()

	# --- 4. 修繕基金：画面用の中身と操作（CLOSEの語りを読み終えたあと） ---
	var p2 = _panel(t, 3, 2000)
	c.check("CLOSE以外では積み立ては出ない（available が false だけ）", p2.session.fund_view() == { "available": false })
	_to_close_done(p2)
	var view: Dictionary = p2.session.fund_view()
	c.check("CLOSEの語りのあと：積み立てが出る・対象4つ・最初の未修繕（看板）が選択済み・刻みが並ぶ",
		view["available"] and view["targets"].size() == 4 and view["selected"] == "sign"
			and view["targets"][0]["selected"] and view["steps"].size() >= 2 and view["complete"] == false, str(view))
	c.check("名前（owner）は未解放。今夜積んだ額0・今日積める上限は1晩の上限以下",
		view["targets"][3]["locked"] and view["paid_tonight"] == 0
			and int(view["max_contribution"]) <= int(view["nightly_max"]))
	var count := { "n": 0 }
	p2.session.changed.connect(func(): count["n"] += 1)
	var money := GameState.money
	p2.session.contribute_fund(10)
	c.check("contribute_fund(10)：所持金-10・今夜の額10・看板に10・changed が出る・橋 _fund_selected も同じ",
		GameState.money == money - 10 and p2.session.fund_view()["paid_tonight"] == 10
			and p2.session.fund_view()["targets"][0]["paid"] == 10 and count["n"] >= 1
			and p2._fund_selected() == p2.session.fund_selected())
	p2.session.select_fund_target("shelf")
	c.check("積む先を棚へ切り替えられる（実行時のみ・橋 _fund_target も同じ値）",
		p2.session.fund_view()["selected"] == "shelf" and p2._fund_target == "shelf")
	p2.session.select_fund_target("owner")
	c.check("未解放の対象は選べない（選択は変わらない）", p2.session.fund_view()["selected"] == "shelf")
	p2.free()

	# --- 5. 減点の理由コード（開店のトッピング画面） ---
	var p3 = _panel(t, 2, 500)
	var s3: PlaySession = p3.session
	c.check("接客中でなければ両方空", s3.sale_hint() == { "blockers": [], "penalties": [] })
	GameState.inventory.clear()
	for id in ["nam_prik_pao", "offal", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s3.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s3.load_current_customer()
	var guard := 0
	while p3.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		s3.next_event()
	var hint: Dictionary = s3.sale_hint()
	c.check("空の椀：提供できない理由は NO_FLAVOR と NO_TOPPING・減点の理由は無い",
		hint["blockers"].has(SaleRule.NO_FLAVOR) and hint["blockers"].has(SaleRule.NO_TOPPING) and hint["penalties"].is_empty())
	c.check("橋 _format_sale_hint は、味付けも具も無いことを文で出す（文面は従来どおり）",
		p3._format_sale_hint() == "（このままでは提供できません：味付けが入っていません・具が入っていません）", p3._format_sale_hint())
	s3.select_ingredient("nam_prik_pao")
	c.check("味だけ入れる：NO_TOPPING だけ", not s3.sale_hint()["blockers"].has(SaleRule.NO_FLAVOR)
		and s3.sale_hint()["blockers"].has(SaleRule.NO_TOPPING))
	s3.select_ingredient("tofu")
	c.check("味と具がそろい濃さ3・傷み無し：両方空（文も空）", s3.sale_hint() == { "blockers": [], "penalties": [] }
		and p3._format_sale_hint() == "")
	GameState.soup["strength"] = 1
	var h1: Dictionary = s3.sale_hint()
	c.check("濃さが最小(1)：減点の理由 STRENGTH_EXTREME と濃さの値", h1["blockers"].is_empty()
		and h1["penalties"] == [{ "code": "STRENGTH_EXTREME", "value": 1 }], str(h1))
	c.check("橋 _format_sale_hint：「濃さが1」", p3._format_sale_hint() == "（このままだと1段階下がります：濃さが1）", p3._format_sale_hint())
	s3.open.current_bowl["used_spoiled"] = true
	c.check("傷んだ具材も加わると STRENGTH_EXTREME の次に SPOILED（文の並びも従来どおり）",
		s3.sale_hint()["penalties"].size() == 2 and s3.sale_hint()["penalties"][1] == { "code": "SPOILED" }
			and p3._format_sale_hint() == "（このままだと1段階下がります：濃さが1・傷んだ具材を使っています）", p3._format_sale_hint())
	p3.free()

	GameState.reset_for_new_game()
	return c.finish()
