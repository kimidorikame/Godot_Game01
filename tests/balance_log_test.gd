extends RefCounted
## 日次ログ導入（BALANCE_REDESIGN_PLAN.md §8「①消費と鮮度の明確化・日次ログ」）の検証。
## 経済数値・計算式には触れず、記録の配線だけを見る：
##   - discard_spoiled_inventory() が個数付き(Dictionary)で返ること
##   - Day1Events.ingredient_prices() が全腐る品目を網羅すること
##   - quality_counts の合計が served_cups（廃棄した椀を除く）と一致すること
##   - planned_cups の先読み計算がDay1の固定スケジュールで期待どおりになること
##   - FlowController.day_ending が日次リセットより前に発火すること

func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. discard_spoiled_inventory(): 個数・実額付きDictionaryを返す ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	GameState.add_inventory("tofu", 5, 4)
	GameState.add_inventory("offal", 3, 10)
	GameState.day_count = 4
	var spoiled: Dictionary = GameState.discard_spoiled_inventory()
	c.check("discard_spoiled_inventoryはDictionaryを返す", spoiled is Dictionary)
	c.check("豆腐5個・モツ3個が個数付きで返る",
		int(spoiled.get("tofu", {}).get("count", 0)) == 5
			and int(spoiled.get("offal", {}).get("count", 0)) == 3, str(spoiled))
	c.check("廃棄額はロットの実際に払った単価×個数の合計(豆腐4*5=20・モツ10*3=30)",
		int(spoiled.get("tofu", {}).get("value", -1)) == 20
			and int(spoiled.get("offal", {}).get("value", -1)) == 30, str(spoiled))
	c.check("破棄後は在庫から消える",
		not GameState.inventory.has("tofu") and not GameState.inventory.has("offal"))

	# --- 2. prep_events() は Dictionary をそのまま受け取れる（後方互換） ---
	GameState.reset_for_new_game()
	var events: Array = Day1Events.prep_events(spoiled, false)
	c.check("prep_eventsの先頭に破棄の一言が入る",
		events[0]["type"] == "TEXT" and str(events[0]["text"]).contains("捨てた"))

	# --- 3. ingredient_prices(): 腐る10品目すべてに価格がある
	#    (fish_mawは①具材の購入単位で非生鮮に変更されたため対象外) ---
	var prices: Dictionary = Day1Events.ingredient_prices()
	var perishable_ids := ["coconut_milk", "offal", "meat_ball", "tofu", "broken_wrapper",
		"bitter_melon", "cartilage", "tendon_meat", "shrimp", "clam"]
	var all_have_price := true
	for id in perishable_ids:
		if not prices.has(id) or int(prices[id]) <= 0:
			all_have_price = false
	c.check("腐る10品目すべてに価格がある", all_have_price, str(prices))
	c.check("dashiは含まない", not prices.has("dashi"))
	c.check("軟骨の価格はmeat_wholesale_goods()と一致",
		int(prices.get("cartilage", -1)) == 24)

	# --- 4. planned_cups: Day1固定スケジュールでの先読み合計 ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	panel._seed_initial_inventory()
	GameState.phase = GameState.Phase.OPEN
	panel._set_runner_for_phase(GameState.Phase.OPEN)
	# Day1: 配達員3(1+1+1) + 宵の口モブ4(mob:true固定) + チンピラ1 + 夜半モブ(独立抽選、
	# GameState.mob_count_today()と同じ値=Day1は固定4) + 老婆1 = 13
	c.check("Day1のplanned_cupsは13", panel._log_planned_cups == 13, str(panel._log_planned_cups))

	# --- 5. quality_counts: 合計が served_cups(廃棄した椀を除く)と一致する ---
	GameState.reset_for_new_game()
	GameState.served = [
		{ "customer": "a", "sale": 50, "servings": 1, "result": "GREAT" },
		{ "customer": "b", "sale": 50, "servings": 1, "result": "GOOD" },
		{ "customer": "c", "sale": 50, "servings": 1, "result": "", "discarded": true },
		{ "customer": "d", "sale": 150, "servings": 3, "results": { "GREAT": 1, "BAD": 2 } },
	]
	var served_cups := 0
	for record in GameState.served:
		if not bool(record.get("discarded", false)):
			served_cups += int(record.get("servings", 0))
	var quality := { "GREAT": 2, "GOOD": 1, "OK": 0, "BAD": 2, "": 0 }
	var quality_sum := 0
	for key in quality:
		quality_sum += int(quality[key])
	c.check("quality_countsの合計はserved_cups(廃棄除く)と一致する",
		quality_sum == served_cups, "%d vs %d" % [quality_sum, served_cups])

	# --- 6. FlowController.day_ending: 日次リセットより前に発火する ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	GameState.money = 999
	GameState.reputation = 42
	GameState.record_served({ "customer": "x", "sale": 50, "servings": 1, "result": "GOOD" })
	var flow := FlowController.new()
	t.root.add_child(flow)
	flow.set_runner([])
	GameState.phase = GameState.Phase.NEXT_DAY
	# GDScriptのラムダはプリミティブ(int/bool)を値渡しで捕捉し、内部で再代入しても
	# 外側の変数には反映されない。Dictionary（参照型）に詰めて外へ持ち出す。
	var seen := { "day": -1, "served_size": -1, "money": -1 }
	var on_ending := func():
		seen["day"] = GameState.day_count
		seen["served_size"] = GameState.served.size()
		seen["money"] = GameState.money
	flow.day_ending.connect(on_ending)
	flow.advance_phase()
	c.check("day_ending発火時、day_countはまだリセット前(1のまま)", seen["day"] == 1, str(seen["day"]))
	c.check("day_ending発火時、servedはまだ消えていない(1件)", seen["served_size"] == 1, str(seen["served_size"]))
	c.check("day_ending発火時、moneyはまだ当日の値", seen["money"] == 999, str(seen["money"]))
	c.check("day_ending後、通常の折り返しでservedは消える", GameState.served.is_empty())
	flow.queue_free()

	# --- 7. 最終日でもday_endingが発火する ---
	GameState.reset_for_new_game()
	GameState.day_count = GameState.FINAL_DAY
	GameState.phase = GameState.Phase.NEXT_DAY
	var flow2 := FlowController.new()
	t.root.add_child(flow2)
	flow2.set_runner([])
	var fired := { "v": false }
	flow2.day_ending.connect(func(): fired["v"] = true)
	flow2.advance_phase()
	c.check("最終日のNEXT_DAY→WAKE折り返しでもday_endingが発火する", fired["v"])
	flow2.queue_free()

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
