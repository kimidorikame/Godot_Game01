extends RefCounted
## ④評判の更新＋⑤客数の決め方（BALANCE_REDESIGN_PLAN.md §5）の検証。対象は
## 「評判は閉店時に1回だけ更新する」計算式と、「総需要からモブ杯数を割り出して
## 組へ配分する」客数決定ロジックだけ。判定ロジック（judge_bowl）・②拒否と部分提供の
## 分岐・day_schedule.jsonのメイン客/モブ抽選プールのデータは変更していないことも
## 合わせて確認する。


func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が自動でinitial_inventory()を積む
	return panel


func _setup_open(t: SceneTree, customers: Array, inventory: Dictionary):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	return panel


func _drive_to_adjust(panel) -> void:
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 評判の確定式：GREAT/GOOD/OK/BAD混在+未提供混在で、閉店時に1回だけ動く ---
	var panel = _setup(t)
	GameState.reputation = 50
	panel._log_quality_counts = { "GREAT": 1, "GOOD": 1, "OK": 1, "BAD": 1, "": 0 }
	# 評点合計 = 100+75+35+0 = 210。判定対象4杯+未提供1杯(部分提供の残り等)=分母5。
	panel._log_judged_planned_cups = 5
	GameState.phase = GameState.Phase.NEXT_DAY
	panel.flow.set_runner([])
	panel.flow.advance_phase()
	# Q = 210/5 = 42.0。新評判 = round(50*0.7 + 42*0.3) = round(35+12.6) = round(47.6) = 48
	c.check("評判はround(現評判*0.7+Q*0.3)どおりに閉店時1回だけ動く",
		GameState.reputation == 48, str(GameState.reputation))

	# --- 2. Qの分母0ガード：判定対象の杯が1つも無ければQは0扱い(評判は0.3倍だけ動く) ---
	panel = _setup(t)
	GameState.reputation = 50
	panel._log_quality_counts = { "GREAT": 0, "GOOD": 0, "OK": 0, "BAD": 0, "": 0 }
	panel._log_judged_planned_cups = 0
	GameState.phase = GameState.Phase.NEXT_DAY
	panel.flow.set_runner([])
	panel.flow.advance_phase()
	c.check("判定対象0杯ならQ=0とみなし、評判はround(50*0.7)=35になる",
		GameState.reputation == 35, str(GameState.reputation))
	c.check("_quality_scoreは分母0のとき例外を出さず0.0を返す",
		panel._quality_score({}, 0) == 0.0)

	# --- 3. judge:falseの杯("" キー)はQの分子・分母どちらにも影響しない ---
	panel = _setup(t)
	var with_unjudged := { "GREAT": 2, "GOOD": 0, "OK": 0, "BAD": 0, "": 100 }
	var without_unjudged := { "GREAT": 2, "GOOD": 0, "OK": 0, "BAD": 0, "": 0 }
	c.check("空文字キー(judge:false)はQの計算から除外される",
		panel._quality_score(with_unjudged, 2) == panel._quality_score(without_unjudged, 2))

	# --- 4. Day1のjudged_planned_cupsは12(配達員3杯目=judge:falseの1杯を除く。
	#        planned_cups(13)との差はちょうど1) ---
	panel = _setup(t)
	panel._seed_initial_inventory()
	GameState.phase = GameState.Phase.OPEN
	panel._set_runner_for_phase(GameState.Phase.OPEN)
	c.check("Day1のjudged_planned_cupsは12", panel._log_judged_planned_cups == 12,
		str(panel._log_judged_planned_cups))
	c.check("planned_cupsとjudged_planned_cupsの差はちょうど1(配達員3杯目のみ)",
		panel._log_planned_cups - panel._log_judged_planned_cups == 1)

	# --- 5. 評判は接客中(OPEN)は動かない。名前あり客(granny)を1人提供した直後も朝の値のまま ---
	# _setup_openの内部でreset_for_new_game()が走る(評判が0に戻る)ため、評判のセットは
	# _setup_open()の戻り値を受け取った後に行う。
	var panel2 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 })
	GameState.reputation = 30
	_drive_to_adjust(panel2)
	panel2._on_ingredient_selected("herbal_sauce")
	panel2._on_ingredient_selected("broken_wrapper")
	panel2._on_complete_input_pressed()
	panel2._on_next_event_pressed()   # SERVE -> REACT
	c.check("名前あり客を提供した直後も評判は朝の値のまま(閉店時に一括確定)",
		GameState.reputation == 30, str(GameState.reputation))

	# --- 6. total_demand_today(): Day1は常に9固定 ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var all_nine := true
	for i in range(200):
		if GameState.total_demand_today() != 9:
			all_nine = false
	c.check("Day1のtotal_demand_todayは常に9", all_nine)

	# --- 7. total_demand_today(): 評判帯の境界で中心値の分岐点どおりになる
	#        (どの乱数を引いても中心±1の範囲には収まるはず、という決定的な確認) ---
	GameState.day_count = 2
	var boundary_cases := [
		[100, 17], [71, 17], [70, 14], [60, 14], [59, 11],
		[45, 11], [44, 9], [20, 9], [19, 7], [0, 7],
	]
	for case in boundary_cases:
		GameState.reputation = int(case[0])
		var got := GameState.total_demand_today()
		c.check("評判%dは中心%d±1の範囲(実測%d)" % [int(case[0]), int(case[1]), got],
			got >= int(case[1]) - 1 and got <= int(case[1]) + 1)

	# --- 8. total_demand_today(): 中心-1/中心/中心+1がおよそ25%/50%/25%(大量試行) ---
	var bands := [[90, 17], [65, 14], [50, 11], [30, 9], [10, 7]]
	for band in bands:
		GameState.reputation = int(band[0])
		var center: int = int(band[1])
		var counts := { center - 1: 0, center: 0, center + 1: 0 }
		var n := 4000
		for i in range(n):
			var d := GameState.total_demand_today()
			counts[d] = int(counts.get(d, 0)) + 1
		var ratio_center: float = float(counts[center]) / float(n)
		var ratio_low: float = float(counts[center - 1]) / float(n)
		var ratio_high: float = float(counts[center + 1]) / float(n)
		c.check("評判%d: 中心値の比率がおよそ50%%(実測%.3f)" % [int(band[0]), ratio_center],
			ratio_center > 0.44 and ratio_center < 0.56, str(ratio_center))
		c.check("評判%d: 中心-1の比率がおよそ25%%(実測%.3f)" % [int(band[0]), ratio_low],
			ratio_low > 0.20 and ratio_low < 0.30, str(ratio_low))
		c.check("評判%d: 中心+1の比率がおよそ25%%(実測%.3f)" % [int(band[0]), ratio_high],
			ratio_high > 0.20 and ratio_high < 0.30, str(ratio_high))

	# --- 9. _customer_total_servings(): 配達員Day1は3(3杯のREACT合計)、他の名前あり客は1 ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	c.check("_customer_total_servingsは配達員Day1で3", Day1Events._customer_total_servings("delivery_man") == 3)
	c.check("_customer_total_servingsはthugで1", Day1Events._customer_total_servings("thug") == 1)

	# --- 10. _plan_mob_groups(): 組数・組サイズ(1〜4・大きい順)・配置枠(固定テーブル)どおり ---
	var slots3 := [
		{ "name": "宵の口", "mob": { "pool": ["a"] } },
		{ "name": "夜半", "mob": { "pool": ["a"] } },
		{ "name": "明け方", "mob": { "pool": ["a"] } },
	]
	c.check("1組(mob_cups=4)は夜半(index1)のみ",
		Day1Events._plan_mob_groups(slots3, 4) == { 1: [4] })
	c.check("2組(mob_cups=8)は宵の口(index0)+夜半(index1)",
		Day1Events._plan_mob_groups(slots3, 8) == { 1: [4], 0: [4] })
	c.check("3組(mob_cups=11)は宵4夜4明3(大きい組から)",
		Day1Events._plan_mob_groups(slots3, 11) == { 1: [4], 0: [4], 2: [3] })
	c.check("4組(mob_cups=16)は宵2(4+4)・夜半1(4)・明け方1(4)",
		Day1Events._plan_mob_groups(slots3, 16) == { 1: [4], 0: [4, 4], 2: [4] })
	c.check("mob_cups=0なら組は無い", Day1Events._plan_mob_groups(slots3, 0).is_empty())

	# --- 11. _plan_mob_groups(): 明け方が「モブなし」の日は3組目以降が夜半へ振り替わる ---
	var slots_no_dawn := [
		{ "name": "宵の口", "mob": { "pool": ["a"] } },
		{ "name": "夜半", "mob": { "pool": ["a"] } },
		{ "name": "明け方", "mob": false },
	]
	c.check("明け方がモブなしの日、3組目(mob_cups=11)は夜半へ振り替わる",
		Day1Events._plan_mob_groups(slots_no_dawn, 11) == { 1: [4, 3], 0: [4] })

	# --- 12. customer_schedule()統合：Day2のautoは3枠とも客がいて、総杯数が需要の
	#         範囲(中心±1)に収まる ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65   # 中心14
	for i in range(50):
		var sched: Array = Day1Events.customer_schedule(-1)
		c.check("Day2: 3枠とも客がいる(自動抽選)", sched.size() == 3
			and not sched[0]["customers"].is_empty() and not sched[1]["customers"].is_empty()
			and not sched[2]["customers"].is_empty(), str(sched))
		var total := 0
		for slot in sched:
			for cid in slot.get("customers", []):
				total += Day1Events._customer_total_servings(str(cid))
		c.check("Day2(評判65)の総杯数が中心14±1の範囲(実測%d)" % total,
			total >= 13 and total <= 15, str(total))

	# --- 13. customer_schedule()統合：Day7の明け方はgranny固定でモブが入らない
	#         (高評判・組数過多でも明け方には配分されない) ---
	GameState.reset_for_new_game()
	GameState.day_count = 7
	GameState.reputation = 100
	var saw_double_group_at_night := false
	for i in range(50):
		var sched7: Array = Day1Events.customer_schedule(-1)
		c.check("Day7の明け方はgranny固定でモブが入らない",
			sched7[2]["customers"] == ["granny"], str(sched7[2]))
		var night_mob_count := 0
		for cid in sched7[1].get("customers", []):
			if Day1Events.is_mob_customer(str(cid)):
				night_mob_count += 1
		if night_mob_count >= 2:
			saw_double_group_at_night = true
	c.check("Day7(高評判)は明け方の分が夜半へ振り替わり2組になることがある",
		saw_double_group_at_night)

	# --- 14. デバッグ上書き(_debug_mob_count>=0)は総需要システムをバイパスし、
	#         全モブ許可枠へ一律適用する既存挙動のまま(Day2以降でも) ---
	GameState.day_count = 2
	var sched_override: Array = Day1Events.customer_schedule(3)
	var override_ok := true
	for slot in sched_override:
		for cid in slot.get("customers", []):
			if Day1Events.is_mob_customer(str(cid)) and int(Day1Events._mob_instances[str(cid)]["count"]) != 3:
				override_ok = false
	c.check("デバッグ上書きは総需要システムをバイパスし、全モブ枠に一律適用される", override_ok)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
