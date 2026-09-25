extends RefCounted
## 仕込み3段階化＋鍋容量拡大（BALANCE_REDESIGN_PLAN.md §1・§2）の検証。対象は
## PREP_TIER（3段階から選ぶ）・端材屋フォールバック・水込みの上限だけ。
## 判定ロジック・評判・客数・場所代/水道代などは変更していないことも合わせて確認する。


func _setup(t: SceneTree, money: int, day: int = 3):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が自動でinitial_inventory()を積む
	GameState.phase = GameState.Phase.PREP
	panel._set_runner_for_phase(GameState.Phase.PREP)
	return panel


## PREP_TIER（またはDONE）に着くまで[次のEvent]で進める。
func _drive_to_waiting_input(panel) -> void:
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT \
			and panel.flow.runner.status != EventRunner.Status.DONE and guard < 100:
		guard += 1
		panel._on_next_event_pressed()


## PREP_TIER選択後（または端材屋ルート）の残りをDONEまで進める。MARKETだけ
## WAITING_INPUTなので[市場を出る]で抜け、他は[次のEvent]で進む。
func _drive_after_tier(panel) -> void:
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.DONE and guard < 50:
		guard += 1
		if panel._is_in_market():
			panel._on_market_exit_pressed()
		else:
			panel._on_next_event_pressed()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. PREP_TIERSの数値が目標表(小80/8・中110/11・大140/14)と一致 ---
	c.check("PREP_TIERSは3段階", Day1Events.PREP_TIERS.size() == 3, str(Day1Events.PREP_TIERS))
	c.check("小仕込み: 80円8杯",
		int(Day1Events.PREP_TIERS[0]["price"]) == 80 and int(Day1Events.PREP_TIERS[0]["servings"]) == 8)
	c.check("中仕込み: 110円11杯",
		int(Day1Events.PREP_TIERS[1]["price"]) == 110 and int(Day1Events.PREP_TIERS[1]["servings"]) == 11)
	c.check("大仕込み: 140円14杯",
		int(Day1Events.PREP_TIERS[2]["price"]) == 140 and int(Day1Events.PREP_TIERS[2]["servings"]) == 14)

	# --- 2. 小/中/大それぞれ選んだ場合の所持金・鍋残量(仕込み杯数と一致) ---
	var cases := [["small", 80, 8], ["medium", 110, 11], ["large", 140, 14]]
	for tier_case in cases:
		var tier_id: String = tier_case[0]
		var price: int = tier_case[1]
		var servings: int = tier_case[2]
		var panel = _setup(t, 1000, 3)
		_drive_to_waiting_input(panel)
		c.check("%s: PREP_TIERで止まる" % tier_id, panel._is_in_prep_tier())
		var money_before: int = GameState.money
		panel._on_prep_tier_selected(tier_id)
		c.check("%s: 所持金が%dだけ減る" % [tier_id, price],
			GameState.money == money_before - price, str(GameState.money))
		_drive_after_tier(panel)
		c.check("%s: 鍋残量が%d杯" % [tier_id, servings],
			int(GameState.soup.get("remaining_servings", -1)) == servings, str(GameState.soup))
		c.check("%s: 濃さは3スタート" % tier_id,
			int(GameState.soup.get("strength", -1)) == 3)

	# --- 3. 端材屋フォールバック(所持金<80): PREP_TIERが出ず、支払い無し・8杯・濃さ1 ---
	var panel2 = _setup(t, 50, 3)
	c.check("所持金50(<80)ではPREP_TIERが出ない",
		not panel2._is_in_prep_tier() and str(panel2.flow.runner.current().get("type", "")) == "TEXT")
	var money_before2: int = GameState.money
	_drive_after_tier(panel2)
	c.check("端材屋ルート: 支払い無し", GameState.money == money_before2, str(GameState.money))
	c.check("端材屋ルート: 杯数は小仕込みと同じ8", int(GameState.soup.get("remaining_servings", -1)) == 8)
	c.check("端材屋ルート: 濃さ1スタート", int(GameState.soup.get("strength", -1)) == 1)

	# --- 4. 所持金不足の段階を直接選ぼうとしても何も起きない(ボタン無効化の二重防御) ---
	var panel3 = _setup(t, 100, 3)   # 小(80)は買えるが中(110)/大(140)は買えない
	_drive_to_waiting_input(panel3)
	var before_money3: int = GameState.money
	var before_index3: int = panel3.flow.runner.index
	panel3._on_prep_tier_selected("large")
	c.check("所持金不足の段階を選んでも所持金・進行が変わらない",
		GameState.money == before_money3 and panel3.flow.runner.index == before_index3)

	# --- 5. 水を2回使い切った場合の残量上限が段階ごとに12/15/18になる(鍋容量拡大の確認) ---
	var water_cases := [["small", 12], ["medium", 15], ["large", 18]]
	for wcase in water_cases:
		var tier_id2: String = wcase[0]
		var expected_max: int = wcase[1]
		var panel4 = _setup(t, 1000, 3)
		_drive_to_waiting_input(panel4)
		panel4._on_prep_tier_selected(tier_id2)
		_drive_after_tier(panel4)
		GameState.add_water()
		GameState.add_water()
		c.check("%s: 水2回込みで%d杯" % [tier_id2, expected_max],
			int(GameState.soup.get("remaining_servings", -1)) == expected_max, str(GameState.soup))

	# --- 6. prep_after_tier_events(): 先頭は必ずTEXT(index 0の効果スキップ対策)、
	#        末尾はSET_SOUPでservingsが選んだ段階と一致 ---
	for tier in Day1Events.PREP_TIERS:
		var tail: Array = Day1Events.prep_after_tier_events(tier, false)
		c.check("%s: prep_after_tier_eventsの先頭はTEXT" % str(tier.get("id")),
			str(tail[0].get("type", "")) == "TEXT", str(tail[0]))
		var last: Dictionary = tail[-1]
		c.check("%s: 末尾はSET_SOUPでservingsが一致" % str(tier.get("id")),
			str(last.get("type", "")) == "SET_SOUP" and int(last.get("servings", -1)) == int(tier.get("servings")),
			str(last))

	# --- 7. Day2は仕込みの後・市場の前に新人警官の立ち話が挟まる(既存動作の回帰) ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var tail_day2: Array = Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[1], false)
	var market_index := -1
	for i in range(tail_day2.size()):
		if str(tail_day2[i].get("type", "")) == "MARKET":
			market_index = i
	c.check("Day2: MARKETより前に会話がある(officer talk挿入)", market_index >= 2, str(tail_day2))

	# --- 8. 既存のprep_events()の先頭(傷み通知)は無改修で動く(回帰) ---
	var spoiled := { "tofu": { "count": 3, "value": 12 } }
	var events: Array = Day1Events.prep_events(spoiled, false, false)
	c.check("prep_eventsの先頭に破棄の一言が入る(既存動作の回帰)",
		str(events[0].get("type", "")) == "TEXT" and str(events[0].get("text", "")).contains("捨てた"))
	c.check("その後、食肉売場のTEXT→PREP_TIER(3段階選択)の順で並ぶ",
		str(events[1].get("type", "")) == "TEXT" and str(events[2].get("type", "")) == "PREP_TIER",
		str(events))

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
