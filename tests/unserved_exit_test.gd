extends RefCounted
## 提供できないまま閉店して退店する客（鍋不足の[閉店]・自動閉店）の未提供版（システム整理C1-③）の検証。
## REACT が適用されないので、反応（reactions.UNSERVED）と、must_info を持つ場面だけ未提供版の本文
## （body_unserved）を、CLOSE の先頭（理由テキストの次・閉店の語りの前）に出す。
## 到着前に閉店して来なかった客は再生しない・来店記録も作らない。facts・料金・評判は変えない。

const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]


func _scene(extra: Dictionary) -> Dictionary:
	var ep := { "id": "thug_02", "customer": "thug", "greet": ["注文"], "servings": 1,
		"reactions": { "GOOD": ["R:GOOD"], "UNSERVED": ["R:UNSERVED"] } }
	ep.merge(extra, true)
	return ep


## Day2のWAKEを通し、客（チンピラ→老婆）の接客のADJUST待ちまで進める。鍋は空で水もだしも無い
## （＝残量不足かつ水が無いので、ADJUST中に[閉店]できる状態）。
func _setup(t: SceneTree, soup_empty: bool = true):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": ["thug", "granny"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.dashi_units = 0
	GameState.set_soup("bone_broth", ["meaty"], 0 if soup_empty else 999, 3, 0)
	panel._load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()
	return panel


## CLOSEのイベント列の [type, part, text]（先頭から、閉店の語り「看板の灯を落とす。」の手前まで）。
func _before_close_talk(panel) -> Array:
	var out := []
	for ev in panel.session.flow.runner.events:
		if str(ev.get("text", "")) == "看板の灯を落とす。":
			break
		out.append([str(ev["type"]), str(ev.get("part", "")), str(ev.get("text", ""))])
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"

	# --- 1. 鍋不足の[閉店]：反応 → 未提供版の本文 の順で、CLOSEの先頭に出る ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1"], "body_unserved": ["U1", "U2"],
		"closing": { "default": ["C1"] }, "must_info": ["info_a"] })
	var p1 = _setup(t)
	c.check("（前提）鍋不足で水もだしも無く、ADJUST中に[閉店]できる", p1._can_close_now())
	var money_before: int = GameState.money
	var rep_before: int = GameState.reputation
	p1._on_close_pressed()
	c.check("CLOSEへ進む", GameState.phase == GameState.Phase.CLOSE)
	c.check("CLOSEの先頭：理由 → 反応(UNSERVED) → 未提供版の本文×2 → 閉店の語り",
		_before_close_talk(p1) == [
			["TEXT", "", "（今日はここで店じまいにする。）"],
			["GREET", "reaction", "R:UNSERVED"], ["GREET", "body", "U1"], ["GREET", "body", "U2"]],
		str(_before_close_talk(p1)))
	c.check("通常の本文・締めは出ない（提供していない）",
		not str(p1.session.flow.runner.events).contains("B1") and not str(p1.session.flow.runner.events).contains("C1"))
	c.check("facts は立てない・来店記録は served=0・料金と評判は変わらない",
		(GameState.customer_memory["thug"]["facts"] as Dictionary).is_empty()
			and int(CustomerMemory.last_visit("thug")["served"]) == 0
			and GameState.money == money_before and GameState.reputation == rep_before)
	c.check("到着前だった老婆は来店記録も作らず、場面も再生しない",
		not GameState.customer_memory.has("granny") and not str(p1.session.flow.runner.events).contains("granny"))
	c.check("一度だけ：CLOSEに積んだ後は残らない", p1.session.pending_close_lines.is_empty())
	p1.free()

	# --- 2. 自動閉店（鍋が尽きた）：同じ未提供版 ---
	var p2 = _setup(t)
	p2._auto_close_kitchen()
	c.check("自動閉店：理由 → 反応 → 本文 の順",
		_before_close_talk(p2) == [
			["TEXT", "", "（鍋が尽きた。今日はもう終いだ。）"],
			["GREET", "reaction", "R:UNSERVED"], ["GREET", "body", "U1"], ["GREET", "body", "U2"]],
		str(_before_close_talk(p2)))
	p2.free()

	# --- 3. must_info が無い場面：反応だけ（本文は出さない） ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1"], "closing": { "default": ["C1"] } })
	var p3 = _setup(t)
	p3._on_close_pressed()
	c.check("must_info が無ければ、未提供の退店は反応だけ",
		_before_close_talk(p3) == [["TEXT", "", "（今日はここで店じまいにする。）"], ["GREET", "reaction", "R:UNSERVED"]],
		str(_before_close_talk(p3)))
	p3.free()

	# --- 4. 現行の21場面（UNSERVEDも本文も無い）は、従来の閉店と同一（何も足さない） ---
	ScheduleData.clear_cache()
	var p4 = _setup(t)
	p4._on_close_pressed()
	c.check("実データ：CLOSEの先頭は理由だけ（従来どおり）",
		_before_close_talk(p4) == [["TEXT", "", "（今日はここで店じまいにする。）"]], str(_before_close_talk(p4)))
	c.check("実データ：CLOSEのイベント数は 理由1＋閉店の語り（従来と同じ）",
		p4.session.flow.runner.events.size() == 1 + Day1Events.close_events().size())
	p4.free()

	# --- 5. すでに提供した客・来店記録の無い客は積まない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "must_info": ["m"], "body_unserved": ["U1"] })
	var p5 = _setup(t, false)
	CustomerMemory.record_serve("thug", "宵の口", "thug_02", 1, "GOOD", ["tofu"])
	p5._queue_unserved_exit()
	c.check("提供した客（served>0）は積まない", p5.session.pending_close_lines.is_empty())
	GameState.customer_memory.erase("thug")
	p5._queue_unserved_exit()
	c.check("来店記録の無い客は積まない", p5.session.pending_close_lines.is_empty())
	p5.free()

	# --- 6. 再挑戦・新しい周で持ち越さない ---
	var p6 = _setup(t)
	p6._queue_unserved_exit()
	c.check("（前提）積んだ", not p6.session.pending_close_lines.is_empty())
	p6._reset_transient_panel_state()
	c.check("画面側の一時状態のリセットで消える", p6.session.pending_close_lines.is_empty() and not p6.session.declined_now)
	p6.free()

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
