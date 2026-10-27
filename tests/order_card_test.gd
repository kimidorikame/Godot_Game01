extends RefCounted
## 「いつもの」「今日」の欄を常に出す（UI準備D・D-5）。表示だけで、判定・乱数・保存は変えない。
## 対象：欄は常に出る（客がいないときも・注文を言う前も。分かるまでは「？」を薄く）、注文を言う会話の最後の行（その杯の ADJUST の直前の GREET）を出した時点で
## 「いつもの」「今日」が入る（提供のあとではない）、前の日に来たことがある名前あり客は「いつもの」が最初から入っている、複数杯の場面（配達員）は杯ごと、
## モブの団体も同じ形、好物を知った状態（favorite_known）・来店記録の中身は増えも変わりもしない、[聞き直す]は聞き直せるときだけ出る。


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

	# --- 1. 客がいないとき：欄は出る（「？」）---
	var root := _open(t, ["granny"])
	var s: PlaySession = root.session
	var top = root.pane_kaiten.topping
	s.open = null
	s.notify_changed()
	var no_customer_texts := _texts(top)
	c.check("客がいない：注文カードは空。欄は出ていて「？」「？」（薄い）", s.order_card_view().is_empty() and top.get_node("%UsualRow").visible and top.get_node("%TodayRow").visible
		and no_customer_texts == ["？", "？"] and (top.get_node("%UsualTags") as Label).modulate.a < 0.6 and not (top.get_node("%ReaskButton") as Button).visible,
		str(no_customer_texts))
	root.queue_free()

	# --- 2. 名前あり客の初回：注文を言う行（GREETの最後）を出した時点で入る。それより前は「？」 ---
	root = _open(t, ["granny"])
	s = root.session
	top = root.pane_kaiten.topping
	s.flow.runner.events.insert(0, { "type": "GREET", "customer": "granny", "text": "（前回への一言・仮）" })
	s.notify_changed()
	var card := s.order_card_view()
	c.check("注文を言う前の行（初来店）：いつもの・今日とも分かっていない（「？」「？」）", not bool(card["usual_known"]) and not bool(card["today_known"])
		and _texts(top) == ["？", "？"], str(card))
	var memory_before := GameState.customer_memory.duplicate(true)
	root.left.advance()   # 注文を言う行へ
	card = s.order_card_view()
	c.check("注文を言う行を出した時点で入る：いつもの＝SAVORY・FILLING、今日＝いつもどおり（提供のあとではない）",
		bool(card["usual_known"]) and bool(card["today_known"]) and _texts(top) == ["うましお・腹もち", "いつもどおり"] and s.flow.runner.current().get("type") == "GREET", str(_texts(top)))
	c.check("見分けやすさ：分かった欄は濃い色", (top.get_node("%UsualTags") as Label).modulate.a == 1.0)
	root.left.advance()   # ADJUST
	c.check("ADJUST中も同じ（欄が埋まったまま）・[聞き直す]が出る", s.is_choosing_ingredients() and _texts(top) == ["うましお・腹もち", "いつもどおり"]
		and (top.get_node("%ReaskButton") as Button).visible and not (top.get_node("%ReaskButton") as Button).disabled)
	c.check("好物を知った状態（favorite_known）は、欄が埋まっても変わらない（まだ知らない）", GameState.known_favorite_ids().is_empty())
	var memory_after := GameState.customer_memory.duplicate(true)
	# 来店の記録（arrive が作る今日の来店）以外は増えない：保存する状態を足していない
	var keys_ok := true
	for id in memory_after:
		keys_ok = keys_ok and (memory_after[id] as Dictionary).keys() == (memory_before.get(id, memory_after[id]) as Dictionary).keys()
	c.check("来店記録のキーは増えない（欄の「分かった」を保存していない）", keys_ok)
	# 提供のあとも出ている
	s.select_ingredient("tofu")
	s.select_ingredient("nam_prik_pao")
	s.complete_input()
	s.next_event()   # SERVE→REACT のあたり
	c.check("提供・反応のあいだも、同じ杯の欄が出ている", _texts(top) == ["うましお・腹もち", "いつもどおり"])
	root.queue_free()

	# --- 3. 前の日に来たことがある客：「いつもの」は最初から入る。「今日」は注文を言う行まで「？」 ---
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
	c.check("次に同じ客が来たとき：注文を言う前でも、いつものは入っている（SAVORY・FILLING）・今日は「？」",
		bool(card["usual_known"]) and not bool(card["today_known"]) and _texts(top) == ["うましお・腹もち", "？"], str(card))
	root.left.advance()
	c.check("注文を言う行で今日も入る（いつもどおり）", _texts(top) == ["うましお・腹もち", "いつもどおり"])
	root.queue_free()

	# --- 4. 複数杯の場面（配達員の3杯）：杯ごと。持ち帰りの頼みは2杯目のあとの会話の最後の行で分かる ---
	root = _open(t, ["delivery_man"], Callable(), {}, 1)   # Day1：配達員の3杯の場面（delivery_man_01）
	s = root.session
	top = root.pane_kaiten.topping
	_advance_to_adjust(root)
	c.check("配達員の1杯目：いつもの＝HOT・POWER・今日＝いつもどおり（欄が出る）", _texts(top) == ["辛い・スタミナ", "いつもどおり"]
		and not (top.get_node("%ReaskButton") as Button).visible, str(_texts(top)))
	var texts_seen: Array = []
	var guard := 0
	var take_out_seen := false
	var before_order_line := true
	while guard < 80 and not take_out_seen:
		guard += 1
		# 1杯ずつ出す：入力→提供→進める
		if s.is_choosing_ingredients():
			if s.open.current_bowl["additions"].is_empty():
				s.select_ingredient("tofu")
				s.select_ingredient("nam_prik_pao")
			s.complete_input()
		else:
			root.left.advance()
		texts_seen.append(_texts(top))
		if _texts(top)[1] == "まろやか・やさしい":
			take_out_seen = true
	c.check("配達員の3杯目（持ち帰り）：今日の頼み＝まろやか・やさしい（MELLOW・GENTLE）が欄に入る（2杯目のあとの会話の最後の行で）", take_out_seen, str(texts_seen.slice(-4)))
	var q := s.order_card_view()
	c.check("そのとき、いつものはHOT・POWERのまま・今日の頼みは分かっている", q["base"] == ["HOT", "POWER"] and bool(q["today_known"]) and q["today"] == ["MELLOW", "GENTLE"], str(q))
	root.queue_free()

	# --- 5. モブの団体：同じ形（いつもの＝団体の注文のタグ・今日はいつもどおり）。聞き直せない ---
	root = _open(t, ["mob_card"], Callable(), { "mob_card": { "type": "dock_workers", "count": 4 } })
	s = root.session
	top = root.pane_kaiten.topping
	card = s.order_card_view()
	c.check("モブ：注文を言う行（団体のgreet）で、いつもの＝HOT・POWER・今日＝いつもどおり。[聞き直す]は出ない",
		bool(card["usual_known"]) and bool(card["today_known"]) and _texts(top) == ["辛い・スタミナ", "いつもどおり"] and not (top.get_node("%ReaskButton") as Button).visible, str(card))
	root.queue_free()

	GameState.reset_for_new_game()
	return c.finish()
