extends RefCounted
## 実効注文（DESIGN.md 10.3.2・10.5.2。フェーズ4-4b-2コミット②）の検証。
## 実効注文＝基本注文（プロフィールのwanted_tags）を、場面の今日の頼み（order.today_request.tags）
## があれば上書き（足し算ではない）したもの。判定（REACTのwanted_tags）が使い、朝の予報
## （Forecast）は基本注文のまま。好物・杯数は変えない。今日の頼みが無ければ従来と同一。
## 今日の頼みを持つ場面は tests/fixtures/episodes/（thug_01：HOT/POWER・2杯、officer_01）。

const FIXTURE_DIR := "res://tests/fixtures/episodes/"


## Day2のWAKEを（フィクスチャの場面で）通し、チンピラの接客（ADJUST待ち）まで進める。
## チンピラは日程の静的idthug_02がrequires（facts unlock）を満たさないため、DayPlanが
## thug_01（今日の頼み：HOT/POWER・2杯）を選ぶ。
func _setup(t: SceneTree, inventory: Dictionary):
	ScheduleData.episodes_dir = FIXTURE_DIR
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（DayPlanが場面を選ぶ）
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "明け方", "customers": ["thug"] }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel.session.load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel.session.next_event()
	return panel


func _serve(panel, picks: Array) -> Dictionary:
	for id in picks:
		panel.session.select_ingredient(id)
	panel.session.complete_input()
	panel.session.next_event()   # SERVE→REACT（判定が適用される）
	return panel.session.open.current_bowl


func _react(events: Array) -> Dictionary:
	for ev in events:
		if str(ev.get("type", "")) == "REACT":
			return ev
	return {}


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var stock := { "nam_prik_pao": 9, "offal": 9, "meat_ball": 9, "coconut_milk": 9, "tofu": 9 }

	# --- 1. DayPlanの枠とREACT：今日の頼みで基本注文を上書き（足し算ではない） ---
	var panel = _setup(t, stock)
	c.check("（前提）チンピラの枠はthug_01で、今日の頼みはHOT/POWER",
		str(GameState.today_plan["slots"][2]["episode_id"]) == "thug_01"
			and GameState.today_plan["slots"][2]["today_request"]["tags"] == ["HOT", "POWER"])
	var react := _react(Day1Events.customer_events("thug"))
	c.check("REACTのwanted_tagsは今日の頼み（HOT/POWER）で上書き。基本注文（MELLOW/GENTLE）は混ざらない",
		react["wanted_tags"] == ["HOT", "POWER"], str(react["wanted_tags"]))
	c.check("基本注文はbase_wanted_tagsに残る", react["base_wanted_tags"] == ["MELLOW", "GENTLE"])
	c.check("好物は変わらない（meat_ball）・杯数は場面のまま（2）・売上も場面の杯数",
		str(react["favorite"]) == "meat_ball" and int(react["servings"]) == 2
			and int(react["sale"]) == GameState.PRICE_PER_SERVING * 2)

	# --- 2. 今日の頼みが無い客は従来と同一（キーも付かない） ---
	var dm := _react(Day1Events.customer_events("delivery_man"))
	c.check("今日の頼みが無い客：wanted_tagsはプロフィールの基本注文・base_wanted_tagsは付かない",
		dm["wanted_tags"] == ["HOT", "POWER"] and not dm.has("base_wanted_tags"), str(dm))
	var off := _react(Day1Events.customer_events("officer"))
	c.check("今日の頼みが基本注文と同じ客も上書き（重複して足されない）",
		off["wanted_tags"] == ["SOUR", "BITE"] and off["base_wanted_tags"] == ["SOUR", "BITE"])

	# --- 3. 朝の予報は基本注文のまま（10.4「今日の頼みは会話で判明」） ---
	var thug_orders: Array = Forecast.orders_of("thug")
	c.check("予報（Forecast.orders_of）は基本注文（MELLOW/GENTLE）・杯数は2",
		thug_orders.size() == 1 and thug_orders[0]["tags"] == ["MELLOW", "GENTLE"]
			and int(thug_orders[0]["servings"]) == 2, str(thug_orders))
	c.check("今日の頼みが無い客の予報は従来どおり", Forecast.orders_of("delivery_man")[0]["tags"] == ["HOT", "POWER"])

	# --- 4. 判定は実効注文を使う（ADJUSTで今日の頼みを満たせばGOOD、基本注文では満たさない） ---
	var bowl_a := _serve(panel, ["nam_prik_pao", "offal"])
	c.check("今日の頼み（HOT/POWER）を2つ満たすとGOOD（一致2）",
		str(bowl_a.get("result", "")) == "GOOD" and int(bowl_a.get("match_count", -1)) == 2, str(bowl_a))
	var panel_b = _setup(t, stock)
	var bowl_b := _serve(panel_b, ["coconut_milk", "tofu"])
	c.check("基本注文（MELLOW/GENTLE）を満たしても、今日の頼みが上書きするのでBAD（一致0）",
		str(bowl_b.get("result", "")) == "BAD" and int(bowl_b.get("match_count", -1)) == 0, str(bowl_b))
	var panel_c = _setup(t, stock)
	var bowl_c := _serve(panel_c, ["nam_prik_pao", "meat_ball"])
	c.check("好物（meat_ball）は変わらず効く：今日の頼みの2つ＋好物でGREAT",
		str(bowl_c.get("result", "")) == "GREAT" and bool(bowl_c.get("has_favorite", false)), str(bowl_c))

	# --- 5. 販売条件（SaleRule）は注文タグを使わない ---
	var flavor_only := { "additions": ["nam_prik_pao", "offal"] }
	var base_style := { "additions": ["coconut_milk", "tofu"] }
	c.check("SaleRuleは味・具・濃さ・杯数だけ（どちらの椀も同じく提供可）",
		SaleRule.check(flavor_only, GameState.soup)["ok"] == true
			and SaleRule.check(base_style, GameState.soup)["ok"] == true)

	# --- 6. 実データ：今日の頼みを持たない21場面は、REACTにbase_wanted_tagsが付かない（従来と同一） ---
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()
	var has_base := false
	for d in range(1, 8):
		GameState.reset_for_new_game()
		GameState.day_count = d
		for slot in ScheduleData.regular_slots(d):
			for ev in Day1Events.customer_events(str(slot["regular"])):
				if str(ev.get("type", "")) == "REACT" and ev.has("base_wanted_tags"):
					has_base = true
	c.check("実データのREACTにはbase_wanted_tagsが付かない（今日の頼みが無い）", not has_base)

	GameState.reset_for_new_game()
	for p in [panel, panel_b, panel_c]:
		if is_instance_valid(p):
			p.free()
	return c.finish()
