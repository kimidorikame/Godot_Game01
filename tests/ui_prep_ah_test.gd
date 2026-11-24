extends RefCounted
## UI準備AH・中身AH：鍋の濃さ・傷んだ具で評価が下がったとき、反応の文は減点の前の評価（base_result）で選び、
## そのあとに理由の一言（reactions.PENALTY）を出す。表示する評価・売上・チップは result のまま。
##   濃い（濃さ5で減点）・薄い（濃さ1で減点）の一言は減点があればいつでも。傷んだ具の一言は最後の評価が BAD のときだけ。
##   濃さと傷みが重なったら濃さ → 傷みの順。具だくさんの一言は理由の一言のあと。モブの組は組で1回だけ。


func _open(t: SceneTree, customers: Array, day: int, strength: int, mob: Dictionary = {}, damaged_tofu: bool = false) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = day
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["coconut_milk", "tofu", "winter_melon", "nam_prik_pao", "meat_ball", "herbal_sauce", "pickled_lime", "cartilage"]:
		GameState.add_inventory(id, 6, 8)
	if damaged_tofu:
		GameState.perishable_batches["tofu"].push_front({ "day": GameState.day_count - 2, "count": 2, "unit_price": 8 })   # 3日目＝傷んだ2個
		GameState.inventory["tofu"] = int(GameState.inventory["tofu"]) + 2
	GameState.set_soup("bone_broth", ["meaty"], 14, strength, 2)
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


## 椀を出して反応（REACT）まで進め、[反応の文, そのあとに続く part:penalty／hearty の行] を返す。
func _serve(s: PlaySession, picks: Array, damaged: Array = []) -> Array:
	for id in picks:
		s.select_ingredient(str(id), damaged.has(id))
	s.complete_input()
	var guard := 0
	while str((s.flow.runner.current() as Dictionary).get("type", "")) != "REACT" and guard < 10:
		guard += 1
		s.next_event()
	var after := []
	for i in range(s.flow.runner.index + 1, s.flow.runner.events.size()):
		var e: Dictionary = s.flow.runner.events[i]
		if not ["penalty", "hearty"].has(str(e.get("part", ""))):
			break
		after.append("%s:%s" % [e["part"], e["text"]])
	return [s.current_reaction_text(), after]


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ReadState.reset("user://test_read_ui_prep_ah.json")
	ScheduleData.clear_cache()
	var thug3: Dictionary = ScheduleData.episode_data("thug", "thug_03")["reactions"]
	var pen: Dictionary = thug3["PENALTY"]

	# 1. 札2つ合い＋濃さ5 → GOOD の文＋濃いの一言、評価は OK のまま
	var root := _open(t, ["thug"], 6, 5)
	var s := root.session
	_to_adjust(s)
	var got := _serve(s, ["coconut_milk", "tofu"])
	c.check("札2つ合い＋濃さ5：GOOD の文＋濃いの一言・評価（result）は OK のまま",
		got[0] == str(thug3["GOOD"][0]) and got[1] == ["penalty:" + str(pen["STRONG"][0])] and str(s.open.current_bowl["result"]) == "OK"
			and str(s.open.current_bowl["base_result"]) == "GOOD", str(got))
	root.free()
	# 2. 札2つ合い＋濃さ1 → GOOD の文＋薄いの一言
	root = _open(t, ["thug"], 6, 1)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["coconut_milk", "tofu"])
	c.check("札2つ合い＋濃さ1：GOOD の文＋薄いの一言", got[0] == str(thug3["GOOD"][0]) and got[1] == ["penalty:" + str(pen["WEAK"][0])], str(got))
	root.free()
	# 3. 札1つ外れ＋濃さ5 → OK（OK_MISSING）の文＋濃いの一言、評価は BAD のまま
	root = _open(t, ["thug"], 6, 5)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["nam_prik_pao", "tofu"])
	c.check("札1つ外れ＋濃さ5：OK（外れた札 MELLOW の OK_MISSING）の文＋濃いの一言・評価は BAD のまま",
		got[0] == str(thug3["OK_MISSING"]["MELLOW"][0]) and got[1] == ["penalty:" + str(pen["STRONG"][0])] and str(s.open.current_bowl["result"]) == "BAD", str(got))
	root.free()
	# 4. 札1つ外れ＋傷んだ具 → OK（OK_MISSING）の文＋傷みの一言
	root = _open(t, ["thug"], 6, 3, {}, true)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["nam_prik_pao", "tofu"], ["tofu"])
	c.check("札1つ外れ＋傷んだ具：OK（OK_MISSING）の文＋傷みの一言（評価は BAD）",
		got[0] == str(thug3["OK_MISSING"]["MELLOW"][0]) and got[1] == ["penalty:" + str(pen["SPOILED"][0])] and str(s.open.current_bowl["result"]) == "BAD", str(got))
	root.free()
	# 5. 札2つ合い＋傷んだ具 → GOOD の文だけ（傷みの一言は無し）
	root = _open(t, ["thug"], 6, 3, {}, true)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["coconut_milk", "tofu"], ["tofu"])
	c.check("札2つ合い＋傷んだ具：GOOD の文だけ（評価は OK。傷みの一言は出さない）",
		got[0] == str(thug3["GOOD"][0]) and (got[1] as Array).is_empty() and str(s.open.current_bowl["result"]) == "OK", str(got))
	root.free()
	# 6. 濃さと傷みが重なって BAD → 濃さ → 傷みの順に2行
	root = _open(t, ["thug"], 6, 5, {}, true)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["nam_prik_pao", "tofu"], ["tofu"])
	c.check("札1つ外れ＋濃さ5＋傷んだ具（BAD）：濃さ → 傷みの順に2行", got[1] == ["penalty:" + str(pen["STRONG"][0]), "penalty:" + str(pen["SPOILED"][0])], str(got))
	root.free()
	# 7. 減点なし → 今までと同じ文だけ
	root = _open(t, ["thug"], 6, 3)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["coconut_milk", "tofu"])
	c.check("減点なし：今までと同じ文（GOOD）だけ・理由の一言は無い", got[0] == str(thug3["GOOD"][0]) and (got[1] as Array).is_empty()
		and str(s.open.current_bowl["result"]) == str(s.open.current_bowl["base_result"]), str(got))
	root.free()
	# 8. 具だくさんの一言は理由の一言のあと（GREAT の椀を濃さ5で GOOD に下げる）
	root = _open(t, ["thug"], 6, 5)
	s = root.session
	_to_adjust(s)
	got = _serve(s, ["coconut_milk", "tofu", "meat_ball"])
	c.check("GREAT の椀＋濃さ5（GOOD）：GREAT の文 → 濃いの一言 → 具だくさんの一言の順",
		got[0] == str(thug3["GREAT"][0]) and got[1] == ["penalty:" + str(pen["STRONG"][0]), "hearty:" + str(thug3["HEARTY"][0])], str(got))
	root.free()
	# 9. モブの組：組で1行だけ（3日目の安宿の夜勤受付・2杯・濃さ1）
	root = _open(t, ["mob#0"], 3, 1, { "mob#0": { "type": "inn_clerk", "count": 2 } })
	s = root.session
	_to_adjust(s)
	s.select_ingredient("coconut_milk")
	s.select_ingredient("tofu")
	s.group_serve(2, 2)
	s.next_event()
	var lines := []
	for i in range(s.flow.runner.index + 1, s.flow.runner.events.size()):
		if str(s.flow.runner.events[i].get("part", "")) == "penalty":
			lines.append(str(s.flow.runner.events[i]["text"]))
	var inn_pen: Dictionary = ScheduleData.mob_data("inn_clerk")["reactions"]["PENALTY"]
	c.check("モブの組（2杯・濃さ1）：薄いの一言は組で1行だけ（職種のファイルの一番上の reactions.PENALTY）・反応は減点の前の評価の文",
		lines == [str(inn_pen["WEAK"][0])] and s.current_reaction_text() == str(ScheduleData.mob_data_for_day("inn_clerk", 3)["reactions"]["GOOD"][0]), str(lines))
	root.free()
	# 10. 1日目の阿強の3杯目は持ち帰りの文
	root = _open(t, ["delivery_man"], 1, 3)
	s = root.session
	var cups: Array = ScheduleData.episode_data("delivery_man", "delivery_man_01")["cups"]
	for i in range(2):
		_to_adjust(s)
		_serve(s, ["nam_prik_pao", "meat_ball"])
		s.next_event()
	_to_adjust(s)
	GameState.soup["strength"] = 5
	got = _serve(s, ["herbal_sauce", "tofu"])
	c.check("1日目の阿強の3杯目（持ち帰り）：濃いの一言は持ち帰りの文", got[1] == ["penalty:" + str(cups[2]["reactions"]["PENALTY"]["STRONG"][0])]
		and str(cups[2]["reactions"]["PENALTY"]["STRONG"][0]) != str(cups[0]["reactions"]["PENALTY"]["STRONG"][0]), str(got))
	root.free()
	# 11. データ：2日目の警官は名前が「警官」・常連の全場面とモブの職種に PENALTY
	var officer1: Dictionary = ScheduleData.episode_data("officer", "officer_01")["reactions"]["PENALTY"]
	var all_regular := true
	for cid in ["delivery_man", "thug", "granny", "officer", "hooker", "streamer"]:
		for eid in ScheduleData.customer_episode_ids(cid):
			var ep := ScheduleData.episode_data(cid, eid)
			all_regular = all_regular and ScheduleData.scene_problems(ep).is_empty()
			for r in ([ep.get("reactions", {})] if not ep.has("cups") else (ep["cups"] as Array).map(func(cup): return cup.get("reactions", {}))):
				all_regular = all_regular and (r as Dictionary).has("PENALTY") and ((r as Dictionary)["PENALTY"] as Dictionary).keys().size() == 3
	var all_mobs := ["dock_workers", "general_store_clerk", "inn_clerk", "laundry_night", "long_haul_driver", "market_porter", "security_guard", "street_cleaners"].all(
		func(m): return (ScheduleData.mob_data(m)["reactions"] as Dictionary).has("PENALTY"))
	c.check("2日目の新人警官の理由の一言は名前が「警官」（3日目以降はリン）・常連の全場面（阿強の1日目は杯ごと）とモブの全職種に濃い・薄い・傷みの3つ",
		(officer1.values() as Array).all(func(v): return str(v[0]).begins_with("警官「")) and str(ScheduleData.episode_data("officer", "officer_02")["reactions"]["PENALTY"]["STRONG"][0]).begins_with("リン「")
			and all_regular and all_mobs)
	var bad := ScheduleData.penalty_problems({ "STRONG": [], "HOT": ["x"] }, "")
	c.check("データの検査：PENALTY の空の文・未知のキーを弾く", bad.size() == 2, str(bad))

	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	TestCheck.free_added(t, root_before)
	return c.finish()
