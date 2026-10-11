extends RefCounted
## 3-7 朝の一画面・予報の幅（DESIGN.md 10.4）の検証。対象はForecast（集計）・
## GameState.demand_center_today()・SNSタブ本文（_format_tonight_memo）・
## Ledger.usable_cash()。自動購入はしない（表示のみ）。

func _panel(t: SceneTree):
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. Day1は完全公開：9杯・配達員の3杯内訳・必要数がDESIGN.md 10.3.4の数と一致 ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = _panel(t)
	GameState.inventory.clear()
	DayPlanner.build()
	c.check("Day1はexact", Forecast.mode() == "exact")
	var total1 := Forecast.total()
	c.check("Day1の総杯数は確定の9杯", bool(total1["exact"]) and int(total1["low"]) == 9
		and int(total1["high"]) == 9, str(total1))
	var dm_orders: Array = Forecast.orders_of("delivery_man")
	c.check("配達員Day1は3杯の内訳が取れる(本人2杯＋持ち帰り1杯)", dm_orders.size() == 3, str(dm_orders))
	c.check("持ち帰りはMELLOW+GENTLE", dm_orders.size() == 3
		and dm_orders[2]["tags"] == ["MELLOW", "GENTLE"], str(dm_orders))
	var req1 := Forecast.required_exact()
	c.check("必要数はHOT4 POWER4 MELLOW4 GENTLE4 SAVORY1 FILLING1（辞書として）",
		req1 == { "HOT": 4, "POWER": 4, "MELLOW": 4, "GENTLE": 4, "SAVORY": 1, "FILLING": 1 }, str(req1))
	c.check("空在庫なら全タグが不足", Forecast.shortages(req1).size() == 6, str(Forecast.shortages(req1)))
	for id in { "nam_prik_pao": 5, "coconut_milk": 6, "herbal_sauce": 5,
			"meat_ball": 6, "tofu": 6, "broken_wrapper": 3 }:
		GameState.add_inventory(id, int({ "nam_prik_pao": 5, "coconut_milk": 6, "herbal_sauce": 5,
			"meat_ball": 6, "tofu": 6, "broken_wrapper": 3 }[id]))
	c.check("初日セット相当の在庫なら不足なし", Forecast.shortages(req1).is_empty(),
		str(Forecast.shortages(req1)))
	var memo1: String = panel._format_tonight_memo()
	c.check("Day1メモに総杯数9杯・配達員の内訳・モブの人数が出る",
		memo1.contains("総杯数: 9杯") and memo1.contains("HOT/POWER×2・MELLOW/GENTLE×1")
		and memo1.contains("港湾労働者2人") and memo1.contains("安宿の夜勤受付2人"), memo1)
	c.check("Day1メモに必要数・在庫との過不足・使える現金が出る",
		memo1.contains("HOT4 MELLOW4 SAVORY1 POWER4 GENTLE4 FILLING1")
		and memo1.contains("不足なし") and memo1.contains("使える現金"), memo1)

	# --- 2. 範囲は実際に引いた値ではなく「中心」基準（中心±1が毎回変わらない） ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 45   # DEMAND_TABLE: 45以上→中心11
	var seen_actual := {}
	var range_stable := true
	for i in range(60):
		DayPlanner.build()
		var t2 := Forecast.total()
		if int(GameState.today_plan["demand_center"]) != 11 or bool(t2["exact"]) \
				or int(t2["low"]) != 10 or int(t2["high"]) != 12:
			range_stable = false
		seen_actual[Forecast.actual_cups()] = true
	c.check("Day2は60回作り直しても総杯数の幅が常に10〜12(中心11基準)", range_stable)
	c.check("実際の総杯数はその間にばらつく(幅が実際値に連動していない証拠)",
		seen_actual.size() >= 2, str(seen_actual))
	c.check("range日はmode()がrange", Forecast.mode() == "range")

	# --- 3. モブは種類の一覧（重複除去）。人数・組数は出さない ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 45
	GameState.today_plan = {
		"day": 2, "demand_center": 11,
		"slots": [{ "name": "夜半", "customers": ["mob#0", "mob#1"] }],
		"mob_instances": {
			"mob#0": { "type": "dock_workers", "count": 3 },
			"mob#1": { "type": "dock_workers", "count": 1 },
		},
	}
	var memo3: String = panel._format_tonight_memo()
	c.check("同じ種類のモブ2組でも名前は1回だけ出る",
		memo3.count("港湾労働者") == 1, memo3)
	c.check("モブの人数・組数は出ない", not memo3.contains("人（") and not memo3.contains("3人")
		and not memo3.contains("1人"), memo3)
	c.check("range日は平均案・上限案の2案を出す",
		memo3.contains("必要（平均案）") and memo3.contains("必要（上限案）"), memo3)
	c.check("range日は総杯数が幅で出る", memo3.contains("総杯数: 10〜12杯"), memo3)

	# --- 4. モブ推定は種類へ均等割り（5杯→dock3＋inn2） ---
	GameState.today_plan = {
		"day": 2, "demand_center": 11,
		"slots": [{ "name": "夜半", "customers": ["mob#0", "mob#1"] }],
		"mob_instances": {
			"mob#0": { "type": "dock_workers", "count": 1 },
			"mob#1": { "type": "inn_clerk", "count": 4 },
		},
	}
	var est := Forecast.required_estimated(5)
	c.check("モブ5杯は種類へ均等に割る(組の人数配分は使わない)",
		est == { "HOT": 3, "POWER": 3, "MELLOW": 2, "GENTLE": 2 }, str(est))

	# --- 5. 使える現金はbudget行と同じ式(残金−確保) ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.money = 300
	Ledger.record("reserve", -80)
	c.check("Ledger.usable_cashは残金−確保", Ledger.usable_cash() == 220)
	c.check("budget行の使えるが同じ値",
		panel._format_game_state().contains("budget(残金/確保/使える): 300 / 80 / 220"),
		panel._format_game_state())

	# --- 6. demand_center_today()：乱数を引かず、total_demand_today()は常に中心±1の範囲 ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65   # 中心14
	c.check("評判65の中心は14", GameState.demand_center_today() == 14)
	var in_range := true
	for i in range(40):
		var v := GameState.total_demand_today()
		if v < 13 or v > 15:
			in_range = false
		if GameState.demand_center_today() != 14:
			in_range = false
	c.check("total_demand_today()は中心±1に収まり、中心自体は引くたびに変わらない", in_range)
	GameState.day_count = 1
	c.check("Day1の中心は固定需要9(day_overrides.fixed_demand)", GameState.demand_center_today() == 9
		and GameState.total_demand_today() == 9)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
