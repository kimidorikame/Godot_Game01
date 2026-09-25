extends RefCounted
## 濃さメカニクス三点セット（BALANCE_REDESIGN_PLAN.md §1・§2）の検証。水の効果(-2)・
## 濃縮だし(+2)・上下限の切り捨て撤廃・明け方だけの自動+1・濃さ0の提供不可を対象とする。
## 判定ロジック本体（一致数の計算）・②拒否と部分提供の分岐・具材の腐敗は変更していないことも
## 合わせて確認する。


func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	return panel


func _setup_open(t: SceneTree, customers: Array, inventory: Dictionary, soup_strength: int = 3):
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
	# set_soup()自体はSTRENGTH_MIN(1)でクランプする（濃さ0はadd_water()経由でのみ到達する
	# 想定で、初期生成時に0を渡すことは実際のゲームでは起こらないため）。テストで直接0を
	# 作りたいときは、生成後にDictionaryへ直接書き込む。
	GameState.set_soup("bone_broth", ["meaty"], 999, maxi(soup_strength, 1), 2)
	if soup_strength <= 0:
		GameState.soup["strength"] = soup_strength
	panel._load_current_customer()
	return panel


func _drive_to_adjust(panel) -> void:
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 濃さ2→水1回→濃さ0・残量+2。以後can_add_water()はfalse ---
	var panel = _setup(t)
	GameState.set_soup("bone_broth", ["meaty"], 10, 2, 2)
	GameState.add_water()
	c.check("濃さ2から水1回で濃さ0", int(GameState.soup["strength"]) == 0, str(GameState.soup))
	c.check("濃さ2から水1回で残量+2(12杯)", int(GameState.soup["remaining_servings"]) == 12)
	c.check("濃さ0ではもう水を足せない", not GameState.can_add_water())

	# --- 2. 濃さ0→濃縮だし1回→濃さ2。だしはdashi_unitsを1消費する ---
	GameState.dashi_units = 1
	c.check("濃さ0・だしありでcan_add_dashiはtrue", GameState.can_add_dashi())
	GameState.add_dashi()
	c.check("濃さ0からだし1回で濃さ2", int(GameState.soup["strength"]) == 2)
	c.check("だしを使うとdashi_unitsが減る", GameState.dashi_units == 0)

	# --- 3. 濃さ3から濃縮だし：1回目(3→5)は通り、2回目(5+2=7>5)は無効化 ---
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	GameState.dashi_units = 5
	c.check("濃さ3+2=5は上限以内なのでcan_add_dashiはtrue", GameState.can_add_dashi())
	GameState.add_dashi()
	c.check("1回目のだしで濃さ5になる", int(GameState.soup["strength"]) == 5)
	c.check("濃さ5+2=7は上限超えなのでcan_add_dashiはfalse", not GameState.can_add_dashi())
	var dashi_before: int = GameState.dashi_units
	GameState.add_dashi()
	c.check("上限超えのadd_dashiは何もしない(濃さ・在庫とも不変)",
		int(GameState.soup["strength"]) == 5 and GameState.dashi_units == dashi_before)

	# --- 4. 名前あり客ADJUST中に濃さ0：入力完了しても判定が成立せず保留に落ちる。
	#    だし無しなら[閉店]相当(_can_close_now)が有効になる ---
	var panel2 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 }, 3)
	_drive_to_adjust(panel2)
	GameState.soup["strength"] = 0
	c.check("濃さ0のADJUST中は_is_strength_zero_in_adjustがtrue", panel2._is_strength_zero_in_adjust())
	c.check("濃さ0・だし無しでは_can_close_nowが有効(ADJUST中から)", panel2._can_close_now())
	panel2._on_ingredient_selected("herbal_sauce")
	panel2._on_ingredient_selected("broken_wrapper")
	panel2._on_complete_input_pressed()   # ADJUST -> SERVE
	var served_before: int = GameState.served.size()
	panel2._on_next_event_pressed()   # SERVE -> REACT（濃さ0の保留フォールバックが働く）
	c.check("濃さ0では判定が成立せずservedが増えない(保留に落ちる)",
		GameState.served.size() == served_before)
	c.check("濃さ0で保留に落ちた後も_can_close_nowが有効(_pending_shortage_ev経由)",
		panel2._can_close_now())

	# --- 5. 濃さ0から濃縮だしを入れて[戻る]すると、保留が解決して提供される ---
	GameState.dashi_units = 1
	panel2._on_pot_pressed()
	panel2._on_add_dashi_pressed()
	c.check("だしを入れると濃さが回復する(0→2)", int(GameState.soup["strength"]) == 2)
	panel2._on_pot_back_pressed()
	c.check("濃さ回復後は保留が解決してservedが増える", GameState.served.size() == served_before + 1)

	# --- 6. モブ客ADJUST中に濃さ0：具材・残量が十分でも達成可能人数が0になり
	#    「断る」しか出せない（既存の達成可能0パターンにそのまま乗る） ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel3 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel3)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	Day1Events._mob_instances["mob_strength_test"] = { "type": "dock_workers", "count": 4 }
	panel3._open = OpenController.new([{ "name": "宵の口", "customers": ["mob_strength_test"] }])
	GameState.add_inventory("nam_prik_pao", 10)
	GameState.add_inventory("meat_ball", 10)
	# set_soup()自体はSTRENGTH_MIN(1)でクランプする（濃さ0はadd_water()経由でのみ到達する
	# 想定で、初期生成時に0を渡すことは実際のゲームでは起こらないため）。テストでは
	# 直接0を作りたいので、生成後にDictionaryへ直接書き込む。
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.soup["strength"] = 0
	panel3._load_current_customer()
	_drive_to_adjust(panel3)
	panel3._on_ingredient_selected("nam_prik_pao")
	panel3._on_ingredient_selected("meat_ball", false)
	c.check("濃さ0のモブは達成可能人数が0になる(具材・残量は十分でも)",
		panel3._mob_achievable_servings(4) == 0,
		"achievable=%s soup=%s mob_picks=%s is_mob=%s" % [
			panel3._mob_achievable_servings(4), str(GameState.soup),
			str(panel3._mob_picks), panel3._is_current_mob_order()])

	# --- 7. 明け方（最後の時間帯）に入った瞬間だけ濃さ+1。宵の口→夜半では+1しない ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel4 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel4)
	GameState.phase = GameState.Phase.OPEN
	panel4._open = OpenController.new([
		{ "name": "宵の口", "customers": ["dummy1"] },
		{ "name": "夜半", "customers": ["dummy2"] },
		{ "name": "明け方", "customers": ["dummy3"] },
	])
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel4.flow.set_runner([])   # 即DONE扱いにして退店条件を満たす
	panel4._advance_open_queue_if_customer_done()   # 宵の口 -> 夜半
	c.check("宵の口->夜半では濃さは変わらない", int(GameState.soup["strength"]) == 3, str(GameState.soup))
	panel4.flow.set_runner([])
	panel4._advance_open_queue_if_customer_done()   # 夜半 -> 明け方（最後の枠）
	c.check("夜半->明け方（最後の枠）で濃さ+1", int(GameState.soup["strength"]) == 4, str(GameState.soup))
	panel4.flow.set_runner([])
	panel4._advance_open_queue_if_customer_done()   # 明け方をさばき終える（もう次の枠は無い）
	c.check("全枠さばき終えた後は濃さが変わらない(2回目の+1は起きない)",
		int(GameState.soup["strength"]) == 4, str(GameState.soup))

	# --- 8. 濃縮だしの購入：¥16・毎日何度でも買える。dashi_unitsは日をまたいで持ち越され、
	#    新しい周回でリセットされる ---
	var panel5 = _setup(t)
	GameState.money = 100
	GameState.dashi_units = 0
	panel5._on_shop_item_selected("meat_wholesale", "dashi")
	c.check("濃縮だし購入で所持金が16減る", GameState.money == 84, str(GameState.money))
	c.check("濃縮だし購入でdashi_unitsが1増える", GameState.dashi_units == 1)
	panel5._on_shop_item_selected("meat_wholesale", "dashi")
	c.check("濃縮だしは1周1回の制限が無く、何度でも買える", GameState.dashi_units == 2)
	GameState.reset_for_new_day()
	c.check("dashi_unitsはreset_for_new_dayでは変化しない(日をまたいで持ち越す)",
		GameState.dashi_units == 2)
	GameState.reset_for_new_game()
	c.check("dashi_unitsは新しい周回(reset_for_new_game)で0に戻る", GameState.dashi_units == 0)

	# --- 9. [戻る]の二重ロック：資源が無ければ塞がない（既存の水ロックと同じ設計をだしにも複製） ---
	var panel6 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 }, 0)
	GameState.dashi_units = 0
	panel6._on_pot_pressed()   # 濃さ0で鍋モードに入る（_pot_dashi_addedがリセットされる）
	c.check("濃さ0で鍋モードに入った直後は_pot_locked_until_dashiがtrue", panel6._pot_locked_until_dashi())
	c.check("だしを持っていなければ、ロック中でも[戻る]は塞がれない(出口は必ずある)",
		not (panel6._pot_locked_until_dashi() and GameState.can_add_dashi()))
	GameState.dashi_units = 1
	c.check("だしを持っていれば、[戻る]はだしを入れるまで塞がれる",
		panel6._pot_locked_until_dashi() and GameState.can_add_dashi())
	panel6._on_add_dashi_pressed()
	c.check("だしを入れるとロックが解ける", not panel6._pot_locked_until_dashi())

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
