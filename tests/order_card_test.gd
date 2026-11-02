extends RefCounted
## 注文カードの「前回」「今日」の欄（UI準備D・D-5、UI準備O2で「いつもの」を「前回」に）。表示だけで、判定・乱数・保存は変えない。
## 対象：欄は常に出る（客がいないときも）、「前回」＝前回の来店で頼んだ注文（来店の最初から。初来店・モブは空白）、
## 「今日」＝その杯の注文（来店の会話が終わった時点＝その杯の ADJUST で入る。それまでは「？」）、複数杯の場面（配達員）は杯ごと、
## 場面データの card_last・card_today で出す札を変えられる（データの検査つき）、好物を知った状態・来店記録の中身は増えも変わりもしない、
## [聞き直す]は聞き直せるときだけ出る。


func _open(t: SceneTree, customers: Array, setup: Callable = Callable(), mob: Dictionary = {}, day: int = 3) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = day
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("tofu", 3, 8)
	GameState.add_inventory("nam_prik_pao", 5)
	if setup.is_valid():
		setup.call()
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	for id in mob:
		GameState.today_plan["mob_instances"][id] = mob[id]
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	root.close_overlay()
	return root


## 欄の文字。トッピングのタブは、椀を作っているとき以外は隠れていて描き直されないので、読む前に描き直す（欄そのものは常に出る）。
func _texts(top) -> Array:
	top.refresh()
	return [str(top.get_node("%UsualTags").text), str(top.get_node("%TodayTags").text)]


func _advance_to_adjust(root: UiGameRoot) -> void:
	var guard := 0
	while not root.session.is_choosing_ingredients() and guard < 40:
		guard += 1
		root.left.advance()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 客がいないとき：欄は出る（前回は空白・今日は「？」）---
	var root := _open(t, ["granny"])
	var s: PlaySession = root.session
	var top = root.pane_kaiten.topping
	s.open = null
	s.notify_changed()
	var no_customer_texts := _texts(top)
	c.check("客がいない：注文カードは空。欄は出ていて、前回は空白・今日は「？」（薄い）", s.order_card_view().is_empty() and top.get_node("%UsualRow").visible and top.get_node("%TodayRow").visible
		and no_customer_texts == ["", "？"] and (top.get_node("%TodayTags") as Label).modulate.a < 0.6 and not (top.get_node("%ReaskButton") as Button).visible,
		str(no_customer_texts))
	c.check("欄の見出しは「前回」「今日」", (top.get_node("%UsualRow/Caption") as Label).text == "前回")
	root.queue_free()

	# --- 2. 名前あり客の初来店：前回は空白。今日は来店の会話が終わった時点（ADJUST）で入る。注文を言う行ではまだ「？」 ---
	root = _open(t, ["granny"])
	s = root.session
	top = root.pane_kaiten.topping
	s.flow.runner.events.insert(0, { "type": "GREET", "customer": "granny", "text": "（前回への一言・仮）" })
	s.notify_changed()
	var card := s.order_card_view()
	c.check("初来店・来店の会話の途中：前回は空白・今日は「？」", not bool(card["last_known"]) and not bool(card["today_known"]) and _texts(top) == ["", "？"], str(card))
	var memory_before := GameState.customer_memory.duplicate(true)
	root.left.advance()   # 注文を言う行へ
	c.check("注文を言う行（来店の会話の最後の行）では、まだ「？」", s.flow.runner.current().get("type") == "GREET" and _texts(top) == ["", "？"], str(_texts(top)))
	root.left.advance()   # ADJUST
	card = s.order_card_view()
	c.check("来店の会話が終わった時点（ADJUST）で今日が入る：うましお・腹もち（前回は空白のまま）・[聞き直す]が出る",
		s.is_choosing_ingredients() and bool(card["today_known"]) and card["today"] == ["SAVORY", "FILLING"] and _texts(top) == ["", "うましお・腹もち"]
		and (top.get_node("%ReaskButton") as Button).visible and not (top.get_node("%ReaskButton") as Button).disabled, str(_texts(top)))
	c.check("見分けやすさ：分かった欄は濃い色", (top.get_node("%TodayTags") as Label).modulate.a == 1.0)
	c.check("好物を知った状態（favorite_known）は、欄が埋まっても変わらない（まだ知らない）", GameState.known_favorite_ids().is_empty())
	var memory_after := GameState.customer_memory.duplicate(true)
	var keys_ok := true
	for id in memory_after:
		keys_ok = keys_ok and (memory_after[id] as Dictionary).keys() == (memory_before.get(id, memory_after[id]) as Dictionary).keys()
	c.check("来店記録のキーは増えない（欄の「分かった」を保存していない）", keys_ok)
	s.select_ingredient("tofu")
	s.select_ingredient("nam_prik_pao")
	s.complete_input()
	s.next_event()   # SERVE→REACT のあたり
	c.check("提供・反応のあいだも、同じ杯の欄が出ている", _texts(top) == ["", "うましお・腹もち"])
	root.queue_free()

	# --- 3. 前の日に来たことがある客：前回は最初から入る。今日は ADJUST まで「？」 ---
	root = _open(t, ["granny"], func():
		var day := GameState.day_count
		GameState.day_count = 1
		CustomerMemory.arrive("granny", "宵の口", "granny_01")
		GameState.day_count = day)
	s = root.session
	top = root.pane_kaiten.topping
	s.flow.runner.events.insert(0, { "type": "GREET", "customer": "granny", "text": "（前回への一言・仮）" })
	s.notify_changed()
	card = s.order_card_view()
	c.check("次に同じ客が来たとき：来店の最初から前回が入っている（うましお・腹もち）・今日は「？」",
		bool(card["last_known"]) and card["last"] == ["SAVORY", "FILLING"] and not bool(card["today_known"]) and _texts(top) == ["うましお・腹もち", "？"], str(card))
	_advance_to_adjust(root)
	c.check("ADJUST で今日も入る", _texts(top) == ["うましお・腹もち", "うましお・腹もち"], str(_texts(top)))
	root.queue_free()
	# 前回の来店の場面に今日の頼みがあったら、前回はその札
	root = _open(t, ["granny"], func():
		var day := GameState.day_count
		GameState.day_count = 1
		CustomerMemory.arrive("granny", "宵の口", "granny_01")
		GameState.day_count = day
		ScheduleData.episode_data("granny", "granny_01")["order"] = { "today_request": { "tags": ["MELLOW", "GENTLE"], "label": "" } })
	s = root.session
	top = root.pane_kaiten.topping
	c.check("前回の来店に今日の頼みがあったら、前回はその頼んだ札（まろやか・やさしい）", _texts(top)[0] == "まろやか・やさしい", str(_texts(top)))
	ScheduleData.episode_data("granny", "granny_01").erase("order")
	root.queue_free()

	# --- 4. 複数杯の場面（配達員の3杯）：杯ごと。持ち帰りの杯の今日は、その杯の ADJUST で入る ---
	root = _open(t, ["delivery_man"], Callable(), {}, 1)   # Day1：配達員の3杯の場面（delivery_man_01）
	s = root.session
	top = root.pane_kaiten.topping
	_advance_to_adjust(root)
	c.check("配達員の1杯目：前回は空白（初来店）・今日＝辛い・スタミナ", _texts(top) == ["", "辛い・スタミナ"]
		and not (top.get_node("%ReaskButton") as Button).visible, str(_texts(top)))
	var texts_seen: Array = []
	var guard := 0
	var take_out_seen := false
	var question_between := false
	while guard < 80 and not take_out_seen:
		guard += 1
		if s.is_choosing_ingredients():
			if s.open.current_bowl["additions"].is_empty():
				s.select_ingredient("tofu")
				s.select_ingredient("nam_prik_pao")
			s.complete_input()
		else:
			root.left.advance()
		texts_seen.append(_texts(top))
		question_between = question_between or _texts(top)[1] == "？"
		if _texts(top)[1] == "まろやか・やさしい":
			take_out_seen = true
	c.check("配達員の3杯目（持ち帰り）：今日＝まろやか・やさしい（その杯の ADJUST で）。杯のあいだの会話では「？」",
		take_out_seen and question_between and s.is_choosing_ingredients(), str(texts_seen.slice(-4)))
	var q := s.order_card_view()
	c.check("そのとき、今日の注文は MELLOW・GENTLE（基本の注文 base は HOT・POWER のまま）", q["base"] == ["HOT", "POWER"] and bool(q["today_known"]) and q["today"] == ["MELLOW", "GENTLE"], str(q))
	root.queue_free()

	# --- 5. モブの団体：前回は空白・今日＝団体の注文（ADJUST で）。聞き直せない ---
	root = _open(t, ["mob_card"], Callable(), { "mob_card": { "type": "dock_workers", "count": 4 } })
	s = root.session
	top = root.pane_kaiten.topping
	_advance_to_adjust(root)
	card = s.order_card_view()
	c.check("モブ：前回は空白・今日＝辛い・スタミナ（団体の注文）。[聞き直す]は出ない",
		not bool(card["last_known"]) and bool(card["today_known"]) and _texts(top) == ["", "辛い・スタミナ"] and not (top.get_node("%ReaskButton") as Button).visible, str(card))
	root.queue_free()

	# --- 6. 場面データで出す札を変える（card_last・card_today）---
	var ep := ScheduleData.episode_data("granny", "granny_02")
	ep["card_last"] = ["SAVORY", "FILLING"]
	ep["card_today"] = ["FILLING"]
	root = _open(t, ["granny"], func():
		GameState.today_plan = { "day": 3, "slots": [{ "name": "宵の口", "customers": ["granny"], "regular_id": "granny", "episode_id": "granny_02", "today_request": {} }],
			"mob_instances": {} })
	s = root.session
	top = root.pane_kaiten.topping
	c.check("card_last：初来店でも、場面データの前回を出す（ゲームの始まる前から通っている客）", Day1Events.episode_id_of("granny") == "granny_02" and _texts(top)[0] == "うましお・腹もち",
		str(_texts(top)) + " " + Day1Events.episode_id_of("granny"))
	_advance_to_adjust(root)
	c.check("card_today：今日に出す札を会話に合わせて変えられる（腹もちだけ）。判定に使う注文は変わらない", _texts(top) == ["うましお・腹もち", "腹もち"]
		and s.flow.runner.events.any(func(e): return e is Dictionary and str(e.get("type", "")) == "REACT" and e.get("wanted_tags", []) == ["SAVORY", "FILLING"]), str(_texts(top)))
	ep["card_last"] = []
	s.notify_changed()
	c.check("card_last が [] なら前回は空白", _texts(top)[0] == "", str(_texts(top)))
	ep.erase("card_last")
	ep.erase("card_today")
	root.queue_free()
	c.check("検査：card_today は、その日の注文の札の中から（無い札は弾く）",
		ScheduleData.scene_problems({ "customer": "granny", "card_today": ["HOT"] }).any(func(x): return str(x).contains("card_today"))
			and ScheduleData.scene_problems({ "customer": "granny", "card_today": ["FILLING"] }).is_empty()
			and ScheduleData.scene_problems({ "customer": "granny", "order": { "today_request": { "tags": ["MELLOW", "GENTLE"] } }, "card_today": ["MELLOW"] }).is_empty())
	c.check("検査：札でない値・3つ以上・モブの場面は弾く。card_last は札なら何でもよい",
		not ScheduleData.scene_problems({ "customer": "granny", "card_last": ["からい"] }).is_empty()
			and not ScheduleData.scene_problems({ "customer": "granny", "card_last": ["HOT", "POWER", "SOUR"] }).is_empty()
			and not ScheduleData.scene_problems({ "customer": "dock_workers", "card_last": ["HOT"] }).is_empty()
			and ScheduleData.scene_problems({ "customer": "granny", "card_last": ["HOT", "POWER"] }).is_empty())
	c.check("検査：複数杯の場面に card_today は置けない", ScheduleData.scene_problems({ "customer": "delivery_man", "card_today": ["HOT"],
		"cups": [{ "adjust": "a" }, { "adjust": "b" }] }).any(func(x): return str(x).contains("card_today")), str(ScheduleData.scene_problems({ "customer": "delivery_man", "card_today": ["HOT"],
		"cups": [{ "adjust": "a" }, { "adjust": "b" }] })))

	GameState.reset_for_new_game()
	return c.finish()
