extends RefCounted
## 椀の追加のキャンセル（UI準備D・D-3）。具材ボタンを同じ品目で2回押すと、2個目を入れるのではなく、取り消す（椀から外し、在庫を戻す）。
## 対象：toggle_ingredient（入れる→取り消す）、在庫が元の束（日・単価・順）のまま戻ること、傷んだ具材を外すと傷みの減点（used_spoiled）も消えること、
## 傷んだ側・新鮮な側のどちらのボタンでも取り消すこと（同じ具材は2個入らない）、団体客（モブ）の選びの記録、画面（✓と、在庫0でも押せること）、
## select_ingredient（レシピ・自動試遊が使う入れるだけの入口）は今までどおりで、重複を許すこと。


func _open(t: SceneTree, customers: Array, setup: Callable, mob: Dictionary = {}) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	setup.call()   # 在庫は客を読む前に（椀の選択肢は、そのときの在庫から作られる）
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	for id in mob:
		GameState.today_plan["mob_instances"][id] = mob[id]
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	root.close_overlay()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	return root


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 新鮮な具材：入れる→取り消す ---
	var root := _open(t, ["officer"], func():
		GameState.add_inventory("tofu", 2, 8)   # Day3：購入日は今日（新鮮）
		GameState.add_inventory("nam_prik_pao", 5))
	var s: PlaySession = root.session
	c.check("椀を作っている最中（ADJUST）", s.is_choosing_ingredients())
	var inv0 := GameState.inventory.duplicate(true)
	var batches0 := GameState.perishable_batches.duplicate(true)
	s.toggle_ingredient("tofu")
	c.check("椀に無い具材のボタン → 入る（在庫が1杯分減る）", s.open.current_bowl["additions"] == ["tofu"] and GameState.fresh_count("tofu") == 1)
	var option := _option(s, "tofu", false)
	c.check("入った具材は in_bowl（もう一度押せる）、同じ具材をもう1つ入れる can_pick は false", bool(option["in_bowl"]) and not bool(option["can_pick"]))
	s.toggle_ingredient("tofu")
	c.check("もう一度押すと取り消し：椀から外れ、在庫が戻る（束・個数が同じ）", s.open.current_bowl["additions"].is_empty() and s.open.current_bowl["additions_damaged"].is_empty()
		and GameState.inventory == inv0 and GameState.perishable_batches == batches0, str(GameState.perishable_batches))
	s.toggle_ingredient("tofu")
	s.toggle_ingredient("tofu")
	s.toggle_ingredient("tofu")
	c.check("入れる→取り消す→入れる：椀に1つだけ（同じ具材が2個になることは無い）", s.open.current_bowl["additions"] == ["tofu"] and GameState.fresh_count("tofu") == 1)
	s.toggle_ingredient("tofu", true)
	c.check("傷んだ側のボタンを押しても、椀にある同じ具材は取り消される（2個入らない）", s.open.current_bowl["additions"].is_empty() and GameState.inventory == inv0)

	# 他の具材は残る：2つ入れて、片方だけ外す
	s.toggle_ingredient("tofu")
	s.toggle_ingredient("nam_prik_pao")
	s.toggle_ingredient("tofu")
	c.check("2つ入れて片方を取り消す：もう片方は残る", s.open.current_bowl["additions"] == ["nam_prik_pao"] and GameState.fresh_count("tofu") == 2
		and GameState.fresh_count("nam_prik_pao") == 4)
	s.toggle_ingredient("nam_prik_pao")
	c.check("全部取り消すと、椀も在庫も最初の状態", s.open.current_bowl["additions"].is_empty() and GameState.inventory == inv0 and GameState.perishable_batches == batches0)

	# --- 2. 傷んだ具材：外すと傷みの減点も消える。束（日）が元のまま ---
	root.queue_free()
	root = _open(t, ["officer"], func():
		GameState.add_inventory("tofu", 1, 8)
		GameState.perishable_batches["tofu"].push_front({ "day": GameState.day_count - 2, "count": 2, "unit_price": 8 })   # 3日目＝傷んだ2個
		GameState.inventory["tofu"] = 3
		GameState.add_inventory("nam_prik_pao", 5))
	s = root.session
	var batches1 := GameState.perishable_batches.duplicate(true)
	var inv1 := GameState.inventory.duplicate(true)
	s.toggle_ingredient("tofu", true)
	c.check("傷んだ側で入れる：additions_damaged が true・used_spoiled が立つ", s.open.current_bowl["additions_damaged"] == [true]
		and bool(s.open.current_bowl.get("used_spoiled", false)) and GameState.damaged_count("tofu") == 1)
	s.toggle_ingredient("nam_prik_pao")
	var hint_with := s.sale_hint()
	c.check("傷んだ具材を入れた椀の予告に、傷みの減点が出る", (hint_with["penalties"] as Array).any(func(x): return str(x["code"]).to_lower().contains("spoil")), str(hint_with["penalties"]))
	s.toggle_ingredient("tofu")   # どちら側のボタンでも取り消し
	c.check("傷んだ具材を取り消す：used_spoiled も additions_damaged も消え、傷みの減点が予告から消える",
		s.open.current_bowl["additions"] == ["nam_prik_pao"] and s.open.current_bowl["additions_damaged"] == [false]
			and not s.open.current_bowl.has("used_spoiled") and not (s.sale_hint()["penalties"] as Array).any(func(x): return str(x["code"]).to_lower().contains("spoil")))
	c.check("傷んだ在庫は元の束（日・単価・順）へ戻る", GameState.perishable_batches == batches1 and GameState.damaged_count("tofu") == 2 and GameState.fresh_count("tofu") == 1,
		str(GameState.perishable_batches))
	s.toggle_ingredient("nam_prik_pao")
	c.check("取り消したあとの在庫は、入れる前と同じ", GameState.inventory == inv1)
	# 取り消して判定すると、減点が付かない（誤クリックの廃棄は要らない）
	s.toggle_ingredient("tofu", true)
	s.toggle_ingredient("tofu", true)
	s.toggle_ingredient("tofu")
	s.toggle_ingredient("nam_prik_pao")
	s.complete_input()
	s.next_event()
	c.check("傷んだ具材を取り消して新鮮な具材で出す → 傷みの減点なし（判定）", not bool(s.open.current_bowl.get("penalty_spoiled", false)), str(s.open.current_bowl))
	root.queue_free()

	# --- 3. 入れるだけの入口（select_ingredient）は今までどおり：レシピ・自動試遊が使う。重複も許す ---
	root = _open(t, ["officer"], func(): GameState.add_inventory("tofu", 3, 8))
	s = root.session
	s.select_ingredient("tofu")
	s.select_ingredient("tofu")
	c.check("select_ingredient は入れるだけ：同じ具材を2回押すと2個入る（従来どおり。UIは toggle_ingredient を使う）",
		s.open.current_bowl["additions"] == ["tofu", "tofu"] and GameState.fresh_count("tofu") == 1)
	s.cancel_ingredient(1)
	c.check("cancel_ingredient(index)：指定の1個だけ取り消せる", s.open.current_bowl["additions"] == ["tofu"] and GameState.fresh_count("tofu") == 2)
	root.queue_free()

	# --- 4. 画面：✓・在庫0でも取り消せる・2回押して取り消し ---
	root = _open(t, ["officer"], func(): GameState.add_inventory("tofu", 1, 8))   # 1個だけ：入れると在庫0
	s = root.session
	var top = root.pane_kaiten.topping
	var grid: GridContainer = top.get_node("%Grid")
	var button: Control = null
	for item in grid.get_children():
		if item.visible and str(item.get_node("MainButton/Name").text) == UiLabels.short_name("tofu"):
			button = item
	c.check("具材ボタン（豆腐）が出ている", button != null)
	if button != null:
		load("res://tests/ui_autoplay.gd").press(button.get_node("MainButton"))
		c.check("押す → 椀に入る：在庫0になるが、ボタンには「✓」が付き、押せる（取り消せる）", s.open.current_bowl["additions"] == ["tofu"] and GameState.fresh_count("tofu") == 0
			and str(button.get_node("MainButton/Name").text).begins_with("✓") and not (button.get_node("MainButton") as Button).disabled)
		load("res://tests/ui_autoplay.gd").press(button.get_node("MainButton"))
		c.check("もう一度押す → 取り消し：椀から外れ、在庫が戻り、「✓」が消える", s.open.current_bowl["additions"].is_empty() and GameState.fresh_count("tofu") == 1
			and not str(button.get_node("MainButton/Name").text).begins_with("✓"))
	root.queue_free()

	# --- 5. 団体客（モブ）：在庫は確定まで引かない。選びの記録だけ外す ---
	root = _open(t, ["mob_cancel"], func():
		GameState.add_inventory("meat_ball", 3)
		GameState.add_inventory("nam_prik_pao", 10), { "mob_cancel": { "type": "dock_workers", "count": 4 } })
	s = root.session
	c.check("モブの注文", s.is_current_mob_order() and s.is_choosing_ingredients())
	var inv_mob := GameState.inventory.duplicate(true)
	s.toggle_ingredient("meat_ball")
	c.check("モブ：入れても在庫はまだ引かない・選びの記録に入る", s.open.current_bowl["additions"] == ["meat_ball"] and s.mob_picks.size() == 1 and GameState.inventory == inv_mob)
	s.toggle_ingredient("meat_ball")
	c.check("モブ：取り消すと椀と選びの記録から外れる（在庫は動かない）", s.open.current_bowl["additions"].is_empty() and s.mob_picks.is_empty() and GameState.inventory == inv_mob)
	root.queue_free()

	GameState.reset_for_new_game()
	return c.finish()


func _option(s: PlaySession, id: String, damaged: bool) -> Dictionary:
	for option in s.ingredient_options():
		if str(option["id"]) == id and bool(option["damaged"]) == damaged:
			return option
	return {}
