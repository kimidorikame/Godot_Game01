extends RefCounted
## 椀を作っている最中（ADJUST）も鍋を触れる（UI準備C④・DESIGN.md 7.6）の検証。
## 対象：can_touch_pot の条件（ADJUST中は、足りているときも、足せるものがあれば触れる。SERVE中は触れない）、
## 濃さは判定（REACT）の瞬間に読むので、椀を作る途中にだし・水を足した濃さで判定されること（途中の手当てが判定に反映される）、
## 触っても椀の中身・在庫・客の進みは変わらないこと、DebugPanel の [鍋を見る] も同じ問いで押せること。

func _open(t: SceneTree, strength: int, remaining: int = 9, dashi: int = 1):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": ["granny"] }])
	for id in ["herbal_sauce", "broken_wrapper"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], remaining, 3, 2)
	GameState.soup["strength"] = strength
	GameState.dashi_units = dashi
	panel.session.load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel.session.next_event()
	panel.session.select_ingredient("herbal_sauce")
	panel.session.select_ingredient("broken_wrapper")
	return panel


## 椀を確定して判定（REACT）まで進める。
func _judge(s: PlaySession) -> Dictionary:
	s.complete_input()
	s.next_event()
	return s.open.current_bowl


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 濃さ1（減点）で椀を作り、ADJUST中にだしを足して濃さ3にしてから出す ---
	var p1 = _open(t, GameState.STRENGTH_MIN)
	var s: PlaySession = p1.session
	c.check("ADJUST中（鍋は足りている・濃さ1）：だしを足せるので鍋を触れる", s.is_choosing_ingredients() and not s.is_short_now()
		and not s.is_strength_zero() and s.can_touch_pot())
	c.check("DebugPanel の [鍋を見る] も、同じ問いで押せる（ADJUST中）", not (p1._btn_pot as Button).disabled)
	c.check("濃さ1のままだと、事前の予告に「濃さ1で1段階下がる」が出る",
		(s.sale_hint()["penalties"] as Array).any(func(x): return str(x["code"]) == "STRENGTH_EXTREME" and int(x["value"]) == GameState.STRENGTH_MIN))
	var additions_before: Array = s.bowl_view()["additions"].duplicate()
	var stock_before := GameState.fresh_count("herbal_sauce")
	var customer_before := str(s.open.current_customer())
	var index_before := s.flow.runner.index
	s.add_dashi()   # ADJUST中に足す（鍋モードには入らない）
	c.check("だしを足すと濃さが1→3に上がる（ADJUST中）", int(GameState.soup["strength"]) == 3 and GameState.dashi_units == 0)
	c.check("触っても、椀の中身・在庫・客・会話の位置は変わらない",
		s.bowl_view()["additions"] == additions_before and GameState.fresh_count("herbal_sauce") == stock_before
			and str(s.open.current_customer()) == customer_before and s.flow.runner.index == index_before and s.is_choosing_ingredients())
	c.check("濃さが直ったので、事前の予告から濃さの減点が消える",
		not (s.sale_hint()["penalties"] as Array).any(func(x): return str(x["code"]) == "STRENGTH_EXTREME"))
	var fixed_bowl := _judge(s)
	c.check("判定は、ADJUST中に足した後の濃さ（3）で行われる：濃さの減点なし・判定時の濃さ3",
		int(fixed_bowl["strength_at_judge"]) == 3 and not bool(fixed_bowl["penalty_strength"]) and str(fixed_bowl["result"]) == str(fixed_bowl["base_result"]),
		str(fixed_bowl))
	c.check("提供の直後（判定のあと）は、まだ SERVE ではない（REACT に進んだ）", not s.is_awaiting_react())
	p1.queue_free()

	# --- 2. 対照：同じ椀・同じ濃さ1で、手当てせずに出す → 濃さの減点が付く ---
	var p2 = _open(t, GameState.STRENGTH_MIN)
	var control_bowl := _judge(p2.session)
	c.check("対照（手当てしない）：判定時の濃さ1・濃さの減点が付く（途中の手当てが判定を変えた証拠）",
		int(control_bowl["strength_at_judge"]) == 1 and bool(control_bowl["penalty_strength"]), str(control_bowl))
	c.check("同じ基準の評価（減点前）は、手当てした場合と同じ", str(control_bowl["base_result"]) == str(fixed_bowl["base_result"]))
	c.check("手当てした場合のほうが、評価が同じか良い（減点が無い分）",
		OpenController.RESULT_ORDER.find(str(fixed_bowl["result"])) >= OpenController.RESULT_ORDER.find(str(control_bowl["result"])))
	p2.queue_free()

	# --- 3. 濃さ5（減点）：ADJUST中に水を足して濃さを下げる ---
	var p3 = _open(t, GameState.STRENGTH_MAX, 9, 0)
	var s3: PlaySession = p3.session
	c.check("ADJUST中（濃さ5・残り9杯）：水を足せるので鍋を触れる", GameState.can_add_water() and s3.can_touch_pot())
	var remaining_before := int(GameState.soup["remaining_servings"])
	s3.add_water()
	c.check("水を足すと濃さが下がり（5→3）、残りが増える", int(GameState.soup["strength"]) == 3
		and int(GameState.soup["remaining_servings"]) == remaining_before + GameState.WATER_SERVINGS)
	var water_bowl := _judge(s3)
	c.check("判定は水を足した後の濃さ（3）で行われ、濃さの減点が付かない", int(water_bowl["strength_at_judge"]) == 3 and not bool(water_bowl["penalty_strength"]))
	p3.queue_free()

	# --- 4. SERVE 中（椀を確定してから判定まで）は触れない ---
	var p4 = _open(t, GameState.STRENGTH_MIN)
	var s4: PlaySession = p4.session
	s4.complete_input()   # ADJUST → SERVE
	c.check("SERVE中は、足せるものがあっても触れない（判定の前に濃さを変えられない）",
		s4.is_awaiting_react() and GameState.can_add_dashi() and not s4.can_touch_pot() and (p4._btn_pot as Button).disabled)
	p4.queue_free()

	# --- 5. 足せるものが無ければ、ADJUST中も触れない ---
	var p5 = _open(t, 3, 999, 0)
	c.check("ADJUST中（残り999・濃さ3・だし0）：水もだしも足せないので触れない", not GameState.can_add_water() and not GameState.can_add_dashi()
		and not p5.session.can_touch_pot())
	p5.queue_free()
	return c.finish()
