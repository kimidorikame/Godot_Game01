extends RefCounted
## PlaySession（UI準備A⑥の追加：画面の共通・開店の鍋とトッピング・朝の問い）の検証。
## 対象：day_info・current_line・is_waiting_input・current_choices・pot_view・order_card_view・bowl_view・
## ingredient_options・morning_cost。どれも読むだけで、状態を変えない。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 朝：運営費・共通の問い ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	var s: PlaySession = panel.session
	var info: Dictionary = s.day_info()
	c.check("朝の共通：日・フェーズ（WAKE）・所持金・評判が出る。時間帯は開店前なので空",
		info["day"] == 2 and info["phase"] == GameState.Phase.WAKE and info["phase_name"] == "WAKE"
			and info["money"] == GameState.money and info["reputation"] == GameState.reputation
			and info["slot_name"] == "" and info["slot_index"] == -1, str(info))
	c.check("今朝払った運営費：帳簿の運営費", s.morning_cost() == GameState.DAILY_OPERATING_COST)
	var line: Dictionary = s.current_line()
	c.check("いま表示すべき文：種類・話し手・本文が出る（朝の語りは地の文＝話し手なし）",
		line.has("type") and line.has("speaker") and line.has("text") and line["speaker"] == "" and str(line["text"]) != "", str(line))
	c.check("入力待ちかどうか：runner の状態と同じ", s.is_waiting_input() == (s.flow.runner.status == EventRunner.Status.WAITING_INPUT))
	c.check("選択肢（CHOICE）でないときは空", s.current_choices().is_empty())
	c.check("鍋がまだ無い朝は pot_view が exists:false だけ", s.pot_view() == { "exists": false })
	c.check("接客中でなければ椀・注文カード・品目の一覧は空", s.bowl_view().is_empty() and s.order_card_view().is_empty()
		and s.ingredient_options().is_empty())

	# --- 2. 開店：新人警官のADJUST ---
	GameState.reputation = 65
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["nam_prik_pao", "offal", "coconut_milk", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.add_inventory("tofu", 2)
	GameState.set_soup("bone_broth", ["meaty"], 12, 3, 2)
	GameState.dashi_units = 1
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		s.next_event()
	info = s.day_info()
	c.check("開店の共通：時間帯の名前と位置が出る", info["phase_name"] == "OPEN" and info["slot_name"] == "宵の口"
		and info["slot_index"] == 0 and info["customer_index"] == 0, str(info))
	var pot: Dictionary = s.pot_view()
	c.check("開店の鍋：残り12・上限14・濃さ3・水は足せる（残り2回）・だし1・まだ椀を作っている最中なので触れない",
		pot["exists"] and pot["remaining"] == 12 and pot["capacity"] == 14 and pot["strength"] == 3
			and pot["can_add_water"] and pot["water_doses_left"] == 2 and pot["can_add_dashi"] and pot["dashi_units"] == 1
			and not pot["can_touch"] and not pot["pot_open"] and not pot["shortage_pending"]
			and not pot["locked_until_water"] and not pot["locked_until_dashi"], str(pot))
	var card: Dictionary = s.order_card_view()
	c.check("注文カード：客・いつものタグ・今日のタグ・ラベル（文は作らない）", card.get("customer", "") == "officer"
		and card["base"] is Array and not (card["base"] as Array).is_empty() and card["today"] is Array and card.has("label"), str(card))
	var options: Array = s.ingredient_options()
	var tofu := {}
	var nam := {}
	for o in options:
		if o["id"] == "tofu" and not o["damaged"]:
			tofu = o
		if o["id"] == "nam_prik_pao":
			nam = o
	c.check("選べる品目：具（豆腐）と味付け（ナンプリックパオ）が種類つきで出る・在庫と選べるか",
		not options.is_empty() and tofu.get("kind", "") == "topping" and tofu.get("fresh", -1) == 11
			and tofu.get("damaged_stock", -1) == 0 and tofu.get("count", -1) == 11 and tofu.get("can_pick", false)
			and nam.get("kind", "") == "seasoning" and nam.get("tags", []) is Array, str(options.slice(0, 3)))
	s.select_ingredient("tofu")
	var bowl: Dictionary = s.bowl_view()
	c.check("椀の中身：客・具材・上限3・傷んだ具材は未使用・判定前は結果が空・廃棄0回",
		bowl["customer"] == "officer" and bowl["additions"] == ["tofu"] and bowl["max_additions"] == 3
			and not bowl["used_spoiled"] and bowl["result"] == "" and bowl["discard_count"] == 0, str(bowl))
	s.select_ingredient("tofu")
	s.select_ingredient("tofu")
	var full: Array = s.ingredient_options()
	c.check("椀が上限（3つ）に達すると、どの品目も選べない（can_pick が false）",
		not full.is_empty() and full.all(func(o): return not o["can_pick"]))

	# --- 3. 読むだけで状態を変えない ---
	var snapshot := JSON.stringify(GameState.to_dict())
	s.day_info()
	s.current_line()
	s.pot_view()
	s.order_card_view()
	s.bowl_view()
	s.ingredient_options()
	s.morning_cost()
	c.check("これらの問いは状態を変えない（GameStateの保存用の辞書が同じ）", JSON.stringify(GameState.to_dict()) == snapshot)
	panel.free()
	GameState.reset_for_new_game()
	return c.finish()
