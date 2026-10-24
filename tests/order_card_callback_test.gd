extends RefCounted
## 前回を読んだ2行（callback）・注文カード・聞き直し（DESIGN.md 10.5.2・10.5.3・10.8.6。
## フェーズ4-4b-2コミット③）の検証。新しい場面データはフィクスチャ（tests/fixtures/episodes/）：
##   officer_01：callback（first・last_unserved・last_grade_good_or_better・last_grade_bad）と
##     今日の頼み（SOUR/BITE・いつもの確認）、officer_02：callback（3行＝最大2行に切る確認）、
##   thug_01：今日の頼み（HOT/POWER・持ち帰り）と聞き直しの台詞（order.reask）。
## 評価で料金・評判・関係を変えない（どの行を読むかを選ぶだけ）。聞き直しは何も変えない。

const FIXTURE_DIR := "res://tests/fixtures/episodes/"


func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


## 最初のADJUST以降のイベント。
func _from_adjust(events: Array) -> Array:
	for i in range(events.size()):
		if str(events[i].get("type", "")) == "ADJUST":
			return events.slice(i)
	return []


func _fixtures() -> void:
	ScheduleData.episodes_dir = FIXTURE_DIR
	ScheduleData.clear_cache()


func _real() -> void:
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()


## 来店の前の会話（最初のADJUSTより前のGREET）。REACTの後ろの追加会話（新人警官の会計など）は含めない。
func _greets(events: Array) -> Array:
	var out := []
	for ev in events:
		if str(ev.get("type", "")) == "ADJUST":
			break
		if str(ev.get("type", "")) == "GREET":
			out.append(str(ev.get("text", "")))
	return out


## 今日（Day2）より前の日（Day1）に来店した記録を作る（served・grade）。
func _previous_visit(customer: String, served: int, grade: String) -> void:
	var today := GameState.day_count
	GameState.day_count = 1
	CustomerMemory.arrive(customer, "宵の口", "%s_01" % customer)
	if served > 0:
		CustomerMemory.record_serve(customer, "宵の口", "%s_01" % customer, served, grade, ["tofu"])
	GameState.day_count = today


## Day2のDayPlanを（フィクスチャの場面で）作る。
func _day2() -> void:
	_fixtures()
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65


## Day2の朝（フィクスチャ）を通して、指定した客のADJUST待ちまで進めたパネルを返す。
func _panel(t: SceneTree, customer: String, mob: bool = false):
	_day2()
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	if mob:
		GameState.today_plan["mob_instances"][customer] = { "type": "dock_workers", "count": 2 }
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": [customer] }])
	for id in ["nam_prik_pao", "offal", "coconut_milk", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel.session.load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel.session.next_event()
	return panel


func _button_texts(row: HBoxContainer) -> Array:
	var out := []
	for child in row.get_children():
		if not child.is_queued_for_deletion() and child is Button:
			out.append(str((child as Button).text))
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 前回を読んだ2行：出し分け ---
	_day2()
	DayPlanner.build()
	var first_events := Day1Events.customer_events("officer")
	c.check("前回の来店なし：firstの2行が来店の前（greetの前）に出る",
		_greets(first_events) == ["初来店1", "初来店2", "F:officer_01"], str(_greets(first_events)))
	c.check("2行はGREETイベント（customerは新人警官）",
		str(first_events[0]["type"]) == "GREET" and str(first_events[0]["customer"]) == "officer")

	_day2()
	_previous_visit("officer", 0, "")
	DayPlanner.build()
	c.check("前回提供しなかった（served=0）：last_unserved",
		_greets(Day1Events.customer_events("officer")) == ["未提供1", "未提供2", "F:officer_01"])
	for pair in [["GREAT", "良1"], ["GOOD", "良1"], ["OK", "悪1"], ["BAD", "悪1"]]:
		_day2()
		_previous_visit("officer", 1, pair[0])
		DayPlanner.build()
		var lines := _greets(Day1Events.customer_events("officer"))
		var want_second := "良2" if pair[1] == "良1" else "悪2"
		c.check("前回の評価%s：%s系の2行（GREAT・GOODは良、OK・BADは悪）" % [pair[0], str(pair[1]).left(1)],
			lines == [pair[1], want_second, "F:officer_01"], str(lines))
	_day2()
	_previous_visit("officer", 1, "")
	DayPlanner.build()
	c.check("前回は提供したが評価なし：last_ungradedが無いので何も出さない（greetだけ）",
		_greets(Day1Events.customer_events("officer")) == ["F:officer_01"])

	# --- 2. callbackを持たない場面・モブは何も出さない。最大2行 ---
	_day2()
	_previous_visit("thug", 1, "GOOD")
	DayPlanner.build()
	c.check("callbackを持たない場面（thug_01）は何も出さない（greetだけ）",
		_greets(Day1Events.customer_events("thug")) == ["F:thug_01"])
	c.check("callbackが3行あっても最大2行（officer_02）",
		_greets(Day1Events.customer_events("officer", 0, "officer_02")) == ["一", "二", "F:officer_02"])
	GameState.today_plan["mob_instances"]["mob#0"] = { "type": "dock_workers", "count": 2 }
	c.check("モブは何も出さない（来店の前に前回の行が付かない）",
		not _greets(Day1Events.customer_events("mob#0")).has("初来店1"))

	# --- 3. 今日の来店を拾わない（previous_visit）。再挑戦（4-1）で戻しても同じ ---
	_day2()
	_previous_visit("officer", 1, "GOOD")   # 朝の前（Day1）の来店
	var panel_r = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel_r)               # Day2の朝を記録（Day1のGOODを含む）
	CustomerMemory.arrive("officer", "宵の口", "officer_01")                       # 今日の来店（served=0）
	CustomerMemory.record_serve("officer", "宵の口", "officer_01", 1, "BAD", ["offal"])   # 今日の提供（BAD）
	c.check("last_visitは今日の来店（BAD）・previous_visitは前日の来店（GOOD）",
		int(CustomerMemory.last_visit("officer")["day"]) == 2
			and str(CustomerMemory.last_visit("officer")["grade"]) == "BAD"
			and int(CustomerMemory.previous_visit("officer")["day"]) == 1
			and str(CustomerMemory.previous_visit("officer")["grade"]) == "GOOD")
	c.check("今日の来店（BAD）があっても、前回は前日のGOODを読む（良の2行）",
		_greets(Day1Events.customer_events("officer"))[0] == "良1")
	GameState.money = 0
	panel_r.session.game_over("テスト用ゲームオーバー")
	c.check("再挑戦できる", panel_r.session.retry_from_morning())
	c.check("再挑戦で今日の来店が消え、前回は前日のGOODのまま",
		CustomerMemory.visits_of("officer").size() == 1
			and int(CustomerMemory.previous_visit("officer")["day"]) == 1
			and _greets(Day1Events.customer_events("officer"))[0] == "良1")
	CustomerMemory.arrive("officer", "宵の口", "officer_01")   # 来店をやり直す（arriveの後でも）
	c.check("やり直した来店（今日の来店）があっても、前回は前日のGOOD",
		int(CustomerMemory.previous_visit("officer")["day"]) == 1
			and _greets(Day1Events.customer_events("officer"))[0] == "良1")

	# --- 4. customer_eventsは状態を読むだけ：副作用・杯数・REACTの数が変わらない ---
	_day2()
	_previous_visit("officer", 1, "BAD")
	DayPlanner.build()
	var before = _norm(GameState.to_dict())
	var react_counts := {}
	var totals := []
	for i in range(5):
		var events := Day1Events.customer_events("officer")
		var reacts := 0
		for ev in events:
			if str(ev.get("type", "")) == "REACT":
				reacts += 1
		react_counts[reacts] = true
		totals.append(Day1Events._customer_total_servings("officer"))
		Forecast.orders_of("officer")
	c.check("何度呼んでも状態（所持金・評判・来店記録・DayPlanほか）が変わらない",
		_norm(GameState.to_dict()) == before)
	c.check("REACTは常に1つ・杯数は常に1（callbackのGREETが杯数を変えない）",
		react_counts.keys() == [1] and totals == [1, 1, 1, 1, 1])
	# 前回の来店の有無（出し分けの行）が違っても、来店の前の会話以外（ADJUST・SERVE・REACT・追加の会話）は同一。
	_day2()
	DayPlanner.build()   # 前回の来店なし
	var ev_first := Day1Events.customer_events("officer")
	_day2()
	_previous_visit("officer", 1, "BAD")
	DayPlanner.build()
	var ev_bad := Day1Events.customer_events("officer")
	c.check("来店の前の会話（前回の行）だけが違い、ADJUST以降（SERVE・REACT・追加の会話）は同一",
		_greets(ev_first) != _greets(ev_bad) and _norm(_from_adjust(ev_first)) == _norm(_from_adjust(ev_bad)))

	# --- 5. 注文カード（仮表示）：いつもの＋今日の頼み ---
	var panel = _panel(t, "thug")
	c.check("今日の頼みがある客：「いつもの：MELLOW/GENTLE ／ 今日：HOT/POWER（持ち帰り）」",
		panel._format_order_card("thug") == "いつもの：MELLOW/GENTLE ／ 今日：HOT/POWER（持ち帰り）",
		panel._format_order_card("thug"))
	c.check("今日の頼みが基本注文と同じ客も両方出る",
		panel._format_order_card("officer") == "いつもの：SOUR/BITE ／ 今日：SOUR/BITE（いつもの確認）")
	c.check("今日の頼みが無い客は「いつもの：…」のみ",
		panel._format_order_card("delivery_man") == "いつもの：HOT/POWER")
	c.check("名前あり客以外（モブ・未知）はカードなし",
		panel._format_order_card("mob#0") == "" and panel._format_order_card("nobody") == "")
	c.check("ADJUST中のチンピラ：計器盤にカードが出る",
		panel.session.adjust_customer_id() == "thug" and panel._format_open().contains("── 注文カード ──")
			and panel._format_open().contains("いつもの：MELLOW/GENTLE ／ 今日：HOT/POWER（持ち帰り）"))

	# --- 6. [聞き直す]：ボタン・再表示・何も変えない ---
	c.check("名前あり客のADJUSTに[聞き直す]ボタンが出る", _button_texts(panel._options_row).has("聞き直す"),
		str(_button_texts(panel._options_row)))
	var snapshot = _norm(GameState.to_dict())
	var money := GameState.money
	var served := GameState.served.size()
	var ledger := GameState.ledger.size()
	var visits_before = _norm(GameState.customer_memory)
	var reask_texts := []
	for i in range(3):
		panel.session.reask()
		reask_texts.append(panel._reask_text)
	c.check("再表示はカードと客の頼みの台詞（order.reask）",
		reask_texts[0].contains("いつもの：MELLOW/GENTLE ／ 今日：HOT/POWER（持ち帰り）")
			and reask_texts[0].contains("持ち帰りを頼む（再掲）"), reask_texts[0])
	c.check("何度押しても同じ表示", reask_texts[0] == reask_texts[1] and reask_texts[1] == reask_texts[2])
	c.check("計器盤にも聞き直しが出る", panel._format_open().contains("── 聞き直し ──"))
	c.check("聞き直しは所持金・評判・提供記録・帳簿・来店記録（visits・facts）・DayPlanを一切変えない",
		GameState.money == money and GameState.served.size() == served and GameState.ledger.size() == ledger
			and _norm(GameState.customer_memory) == visits_before and _norm(GameState.to_dict()) == snapshot
			and panel.session.visit_tally.is_empty())
	c.check("聞き直しても料金・評判は下がらない（所持金・評判が同じ）",
		GameState.money == money and GameState.reputation == int(snapshot["reputation"]))
	panel.session.load_current_customer()
	c.check("次の客（再ロード）で聞き直しの表示は消える", panel._reask_text == "")

	var panel_o = _panel(t, "officer")
	panel_o.session.reask()
	c.check("order.reaskが無い場面は、客のgreetを再表示する",
		panel_o._reask_text.contains("F:officer_01") and panel_o._reask_text.contains("いつもの：SOUR/BITE"))

	# --- 7. モブ・配達員の3杯専用列には出さない ---
	var panel_m = _panel(t, "mob#9", true)
	c.check("モブには注文カード・[聞き直す]を出さない",
		panel_m.session.adjust_customer_id() == "" and not panel_m._format_open().contains("── 注文カード ──")
			and not _button_texts(panel_m._options_row).has("聞き直す"))
	panel_m.session.reask()
	c.check("モブで聞き直しを呼んでも何も起きない", panel_m._reask_text == "")
	_real()
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel_d = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel_d)
	GameState.phase = GameState.Phase.OPEN
	panel_d.session.open = OpenController.new([{ "name": "宵の口", "customers": ["delivery_man"] }])
	GameState.add_inventory("nam_prik_pao", 5)
	GameState.add_inventory("tofu", 5)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel_d.session.load_current_customer()
	var guard := 0
	while panel_d.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel_d.session.next_event()
	c.check("配達員のDay1の3杯専用列には、注文カード・[聞き直す]を出さない（動かさない列）",
		panel_d.session.adjust_customer_id() == "" and not panel_d._format_open().contains("── 注文カード ──")
			and not _button_texts(panel_d._options_row).has("聞き直す"))
	panel_d.session.reask()
	c.check("3杯列で聞き直しを呼んでも何も起きない", panel_d._reask_text == "")

	_real()
	GameState.reset_for_new_game()
	for p in [panel_r, panel, panel_o, panel_m, panel_d]:
		if is_instance_valid(p):
			p.free()
	return c.finish()
