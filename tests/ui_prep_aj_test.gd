extends RefCounted
## UI準備AJ・中身AJ：具を選んでいる間（ADJUST の入力待ち）は、会話枠に「（味を調える）」の代わりに、その客が注文を言った行を出す。
##   名前あり客は場面の order.reask、1日目の阿強は杯ごとの cups[i].reask、モブはその日の days.<日>.reask。行の無い客は今までどおり。
##   2ページになる場面は会話枠のクリックでページを送り、最後のページのあとは1ページ目に戻る（列は進めない）。ログには足さない。


func _open(t: SceneTree, customers: Array, day: int, mob: Dictionary = {}, servings: int = 14) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = day
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["coconut_milk", "tofu", "winter_melon", "nam_prik_pao", "meat_ball", "herbal_sauce", "pickled_lime", "cartilage"]:
		GameState.add_inventory(id, 6, 8)
	GameState.set_soup("bone_broth", ["meaty"], servings, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	for id in mob:
		GameState.today_plan["mob_instances"][id] = mob[id]
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	root.close_overlay()
	return root


func _to_adjust(s: PlaySession) -> void:
	var guard := 0
	while not s.is_choosing_ingredients() and guard < 120 and not s.flow.is_runner_done():
		guard += 1
		s.next_event()


func _shown(root: UiGameRoot) -> String:
	root.left.refresh()
	return str(root.left._display().get("text", ""))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ReadState.reset("user://test_read_ui_prep_aj.json")
	ScheduleData.clear_cache()

	# --- 1. モブ1組（1日目の安宿の夜勤受付）：2ページの注文の行。ページを送れて、最後のあとは1ページ目へ。列は進まない ---
	var root := _open(t, ["mob#0"], 1, { "mob#0": { "type": "inn_clerk", "count": 1 } })
	var s: PlaySession = root.session
	_to_adjust(s)
	var inn_lines: Array = ScheduleData.mob_data("inn_clerk")["days"]["1"]["reask"]
	var left: UiLeftSide = root.left
	c.check("ADJUST の入力待ちでは、会話枠に注文の行（「（味を調える）」ではない）",
		_shown(root) == "\n".join(PackedStringArray(inn_lines)) and str(left._display().get("speaker", "")) == "mob#0", _shown(root))
	c.check("1日目の安宿の受付は2ページ", left._pages.size() == 2 and left._page == 0, str(left._pages))
	var index_before: int = s.flow.runner.index
	var log_before := TalkLog.entries.size()
	left.advance()
	c.check("会話枠のクリックで2ページ目へ（列は進まない）", left._page == 1 and s.flow.runner.index == index_before
		and s.is_choosing_ingredients(), "%d %d" % [left._page, s.flow.runner.index])
	s.select_ingredient("coconut_milk")
	left.refresh()
	c.check("具を足しても注文の行のまま・ページもそのまま", _shown(root) == "\n".join(PackedStringArray(inn_lines)) and left._page == 1,
		"%s / %d" % [_shown(root), left._page])
	left.advance()
	c.check("最後のページのあとは1ページ目に戻る（列は進まない）", left._page == 0 and s.flow.runner.index == index_before
		and s.is_choosing_ingredients())
	s.discard_bowl()
	left.refresh()
	c.check("椀を作り直しても注文の行のまま", _shown(root) == "\n".join(PackedStringArray(inn_lines)))
	c.check("会話ログには注文の行を足さない（クリック・具の操作で増えない）", TalkLog.entries.size() == log_before, str(TalkLog.entries.size() - log_before))
	c.check("ADJUST の文（「（味を調える）」）のログは今のまま",
		TalkLog.entries.any(func(e): return str(e.get("text", "")) == "（味を調える）"))
	s.select_ingredient("coconut_milk")
	s.select_ingredient("tofu")
	s.group_serve(1, 1)
	c.check("椀を出したら、注文の行は消える（反応へ）", s.adjust_order_lines().is_empty() and _shown(root) != "\n".join(PackedStringArray(inn_lines)))
	root.free()

	# --- 2. 注文の行の無い客（その日の文の無いモブ）は「（味を調える）」のまま ---
	root = _open(t, ["mob#0"], 2, { "mob#0": { "type": "inn_clerk", "count": 1 } })
	s = root.session
	_to_adjust(s)
	c.check("注文の行の無い客（2日目の安宿の受付・日の文なし）は「（味を調える）」", s.is_choosing_ingredients() and _shown(root) == "（味を調える）"
		and s.adjust_order_lines().is_empty(), _shown(root))
	root.free()

	# --- 3. 2日目の警官：店主の行が入る（行の頭の名前は行のとおり）。話し手の枠は警官 ---
	root = _open(t, ["officer"], 2)
	s = root.session
	_to_adjust(s)
	var officer_lines: Array = ScheduleData.episode_data("officer", "officer_01")["order"]["reask"]
	c.check("2日目の警官：注文の行（店主の行を含む）", _shown(root) == "\n".join(PackedStringArray(officer_lines))
		and str(officer_lines[0]).begins_with("店主「") and str(root.left._display().get("speaker", "")) == "officer", _shown(root))
	c.check("2日目の警官は1ページ", root.left._pages.size() == 1)
	var idx: int = s.flow.runner.index
	root.left.advance()
	c.check("1ページの場面でクリックしても列は進まない", s.flow.runner.index == idx and s.is_choosing_ingredients() and root.left._page == 0)
	root.free()

	# --- 4. 1日目の阿強：杯ごとに別の行（2杯目は1杯目の2行＋「同じので。肉団子も足して」） ---
	root = _open(t, ["delivery_man"], 1)
	s = root.session
	var cups := ScheduleData.episode_cups("delivery_man", "delivery_man_01")
	var per_cup := []
	for i in range(3):
		_to_adjust(s)
		per_cup.append(_shown(root))
		s.select_ingredient("nam_prik_pao")
		s.select_ingredient("meat_ball")
		s.complete_input()
		s.next_event()
	c.check("阿強の1杯目：cups[0].reask", per_cup[0] == "\n".join(PackedStringArray(cups[0]["reask"])), per_cup[0])
	c.check("阿強の2杯目：1杯目の2行＋「同じので。肉団子も足して」",
		per_cup[1] == "\n".join(PackedStringArray(cups[1]["reask"])) and per_cup[1].begins_with(per_cup[0] + "\n")
			and per_cup[1].contains("同じので。肉団子も足して"), per_cup[1])
	c.check("阿強の3杯目（持ち帰り）：cups[2].reask", per_cup[2] == "\n".join(PackedStringArray(cups[2]["reask"]))
		and per_cup[2].contains("持ち帰り"), per_cup[2])
	root.free()

	# --- 5. モブの組の2杯目（残りに挑戦した2つ目のレシピの ADJUST）も同じ行 ---
	root = _open(t, ["mob#0"], 3, { "mob#0": { "type": "inn_clerk", "count": 2 } }, 1)
	s = root.session
	_to_adjust(s)
	var first := _shown(root)
	s.select_ingredient("coconut_milk")
	s.select_ingredient("tofu")
	s.complete_input()
	var choice := s.mob_group_choice()
	s.group_retry(int(choice.get("achievable", 1)), int(choice.get("ordered", 2)))
	GameState.set_soup("bone_broth", ["meaty"], 3, 3, 2)
	_to_adjust(s)
	var second := _shown(root)
	c.check("モブの組の2つ目のレシピの ADJUST も、同じ注文の行", first == "\n".join(PackedStringArray(ScheduleData.mob_data("inn_clerk")["days"]["3"]["reask"]))
		and s.is_choosing_ingredients() and second == first and s.mob_recipe_number == 2, "%s / %s / %d" % [first, second, s.mob_recipe_number])
	root.free()

	# --- 6. 同じ晩の同じ職種の2組目（予備の一言で来た組）：行が spare_greet にそろう日だけ出す ---
	root = _open(t, ["mob#0", "mob#1"], 3, { "mob#0": { "type": "inn_clerk", "count": 1 }, "mob#1": { "type": "inn_clerk", "count": 1 } })
	s = root.session
	c.check("3日目の安宿の受付の2組目：注文の行が spare_greet にそろう → 出す",
		Day1Events.order_reask_lines("mob#1") == ScheduleData.mob_data("inn_clerk")["days"]["3"]["reask"], str(Day1Events.order_reask_lines("mob#1")))
	root.free()
	root = _open(t, ["mob#0", "mob#1"], 7, { "mob#0": { "type": "inn_clerk", "count": 1 }, "mob#1": { "type": "inn_clerk", "count": 1 } })
	s = root.session
	c.check("7日目の安宿の受付の2組目：spare_greet に注文の行が無い → 出さない（「（味を調える）」）。1組目は出す",
		Day1Events.order_reask_lines("mob#1").is_empty() and not Day1Events.order_reask_lines("mob#0").is_empty())
	root.free()

	# --- 7. データ：常連21場面（阿強の1日目は杯ごと3通り）とモブ19の日に注文の行。どれも来店の会話の行と同じ・2ページ以内 ---
	var missing := []
	var problems := []
	var over := []
	var scene_count := 0
	for d in range(1, 8):
		for slot in ScheduleData.regular_slots(d):
			var ep := ScheduleData.episode_data(str(slot["regular"]), str(slot["episode_id"]))
			scene_count += 1
			problems.append_array(ScheduleData.reask_problems(ep))
			var sets := []
			if ep.get("cups") is Array:
				for cup in ep["cups"]:
					sets.append(cup.get("reask", []))
			else:
				sets.append((ep.get("order", {}) as Dictionary).get("reask", []))
			for lines in sets:
				if (lines as Array).is_empty():
					missing.append(str(slot["episode_id"]))
				elif UiLeftSide.paginate("\n".join(PackedStringArray(lines))).size() > 2:
					over.append(str(slot["episode_id"]))
	var mob_days := 0
	for id in ["dock_workers", "general_store_clerk", "inn_clerk", "laundry_night", "long_haul_driver", "market_porter", "security_guard", "street_cleaners"]:
		problems.append_array(ScheduleData.mob_reask_problems(id))
		var days: Dictionary = ScheduleData.mob_data(id).get("days", {})
		for day in days:
			mob_days += 1
			var lines: Array = (days[day] as Dictionary).get("reask", [])
			if lines.is_empty():
				missing.append("%s days.%s" % [id, str(day)])
			elif UiLeftSide.paginate("\n".join(PackedStringArray(lines))).size() > 2:
				over.append("%s days.%s" % [id, str(day)])
	c.check("常連21場面・モブ19の日のどれにも注文の行がある", scene_count == 21 and mob_days == 19 and missing.is_empty(),
		"%d %d %s" % [scene_count, mob_days, str(missing)])
	c.check("注文の行は、その場面の来店の会話（greet）・前の杯の after_talk の行と一字一句同じ", problems.is_empty(), str(problems))
	c.check("どの場面の注文の行も2ページ以内（行頭禁則を入れて数える）", over.is_empty(), str(over))
	var bad := ScheduleData.reask_problems({ "greet": ["a「x」"], "order": { "reask": ["a「y」"] } })
	var bad_cup := ScheduleData.reask_problems({ "greet": ["a「x」"], "cups": [{ "after_talk": ["a「z」"] }, { "reask": ["a「x」", "a「z」"] }, { "reask": [] }] })
	c.check("データの検査：来店の会話に無い行・空の行を弾く（杯は前の杯の after_talk まで見る）", bad.size() == 1 and bad_cup.size() == 1,
		"%s / %s" % [str(bad), str(bad_cup)])

	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	TestCheck.free_added(t, root_before)
	return c.finish()
