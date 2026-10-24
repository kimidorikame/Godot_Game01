extends RefCounted
## PlaySession（UI準備A③b：鍋・団体・断る・閉店）の検証。
## 対象：鍋の操作（open_pot・close_pot・add_water・add_dashi）、鍋不足で保留中の客の解決
## （resume_after_shortage と close_shop。鍋モードの出入りとは独立）、水・だしの鍵、押せるかの問い
## （can_touch_pot・can_next_event・can_complete_input・can_discard・can_decline・can_reask）、
## モブの団体の確認（mob_group_choice・group_*）、客を断る（decline_customer）。
## 操作の中身そのもの（水・だしの効果、団体の分割提供、自動閉店など）は既存のスイートが確かめる。


func _setup_open(t: SceneTree, customers: Array, inventory: Dictionary, strength: int = 3):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, maxi(strength, 1), 2)
	if strength <= 0:
		GameState.soup["strength"] = strength
	panel.session.load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel.session.next_event()
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var count := { "n": 0 }

	# --- 1. 押せるかの問い（名前あり客のADJUST・濃さ3・鍋は十分） ---
	var p1 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 })
	var s: PlaySession = p1.session
	c.check("ADJUST（鍋が足りて濃さも普通）：鍋は触れず・次のEventへは進め・廃棄できる・客を断れる",
		not s.can_touch_pot() and s.can_next_event() and s.can_discard() and s.can_decline())
	c.check("聞き直せるかは、聞き直し対象の客か（adjust_customer_id）と同じ", s.can_reask() == (s.adjust_customer_id() != ""))
	c.check("椀が空のうちは入力完了できない（具・味が欠けている）", not s.can_complete_input())
	s.select_ingredient("herbal_sauce")
	s.select_ingredient("broken_wrapper")
	c.check("味と具がそろうと入力完了できる", s.can_complete_input())

	# --- 2. 鍋：濃さ0で鍋に触れる→だしを足す。水・だしの鍵 ---
	GameState.soup["strength"] = 0
	GameState.dashi_units = 1
	c.check("濃さ0（だしがある）：鍋に触れる。名前あり客の入力完了は塞がる",
		s.can_touch_pot() and not s.can_complete_input())
	s.complete_input()   # ADJUST→SERVE（ボタン側で塞ぐ条件。呼び出し側が守る約束は従来どおり）
	s.next_event()       # SERVE→REACT：濃さ0で判定できず、鍋不足と同じ保留に落ちる
	c.check("保留中の客がいる：選択待ち・次のEvent／入力完了は押せない・閉店は押せる",
		s.is_shortage_pending() and not s.can_next_event() and not s.can_complete_input() and s.can_close_now())
	count["n"] = 0
	s.changed.connect(func(): count["n"] += 1)
	s.open_pot()
	c.check("open_pot()：鍋モードに入る・鍵はリセット・changed が1回・橋 _pot_mode も同じ値",
		s.pot_open and not s.pot_water_added and not s.pot_dashi_added and count["n"] == 1 and p1._pot_mode == s.pot_open)
	c.check("鍋モード中は、もう一度は入れない／次のEventには進めない", not s.can_touch_pot() and not s.can_next_event())
	c.check("濃さ0で入ったので『だしを入れるまで戻れない』鍵がかかる（水の鍵は無い）",
		s.pot_locked_until_dashi() and not s.pot_locked_until_water())
	var dashi_used := s.log_dashi_used
	s.add_dashi()
	c.check("add_dashi()：濃さが0→2・日次ログのだし回数が1増え・鍵が外れる",
		int(GameState.soup["strength"]) == 2 and s.log_dashi_used == dashi_used + 1 and not s.pot_locked_until_dashi())
	var served_before := GameState.served.size()
	s.resume_after_shortage()
	c.check("resume_after_shortage()：鍋モードの出入りとは独立に、保留中の客を提供する（鍋モードのまま）",
		GameState.served.size() == served_before + 1 and not s.is_shortage_pending() and s.pot_open)
	count["n"] = 0
	s.resume_after_shortage()
	c.check("保留が無いときは何もしない（提供も changed も無い）",
		GameState.served.size() == served_before + 1 and count["n"] == 0)
	s.close_pot()
	c.check("close_pot()：鍋モードを抜けるだけ（保留の処理は含まない）", not s.pot_open and count["n"] == 1)
	p1.free()

	# --- 3. DebugPanelの[戻る]：モードを抜けて、保留があれば営業を続ける（従来と同じ）---
	var p2 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 })
	GameState.soup["strength"] = 0
	GameState.dashi_units = 1
	p2.session.select_ingredient("herbal_sauce")
	p2.session.select_ingredient("broken_wrapper")
	p2.session.complete_input()
	p2.session.next_event()
	var served2 := GameState.served.size()
	p2._on_pot_pressed()
	p2._on_add_dashi_pressed()
	p2._on_pot_back_pressed()
	c.check("[戻る]：鍋モードを抜けて保留が解決する（提供が1増え、選択待ちが消え、鍋モードも終わる）",
		GameState.served.size() == served2 + 1 and not p2.session.is_shortage_pending() and not p2.session.pot_open)
	p2.free()

	# --- 4. 閉店（保留中）：選択待ちを閉店で解決する ---
	var p3 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 })
	GameState.soup["strength"] = 0
	GameState.dashi_units = 0
	p3.session.select_ingredient("herbal_sauce")
	p3.session.select_ingredient("broken_wrapper")
	p3.session.complete_input()
	p3.session.next_event()
	c.check("濃さ0・だし無し：保留に落ち、閉店できる", p3.session.is_shortage_pending() and p3.session.can_close_now())
	p3.session.close_shop()
	c.check("close_shop()：CLOSEへ・保留は消え・日次ログに『鍋不足で早仕舞い』が付く",
		GameState.phase == GameState.Phase.CLOSE and not p3.session.is_shortage_pending() and p3.session.log_closed_early)
	p3.free()

	# --- 5. モブの団体の確認 ---
	var p4 = _setup_open(t, ["mob_pot_test"], { "nam_prik_pao": 10, "tofu": 10 })
	c.check("団体の確認の前は空", p4.session.mob_group_choice().is_empty())
	p4.free()
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var p5 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(p5)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	GameState.today_plan["mob_instances"]["mob_pot_test"] = { "type": "dock_workers", "count": 4 }
	p5.session.open = OpenController.new([{ "name": "宵の口", "customers": ["mob_pot_test"] }])
	GameState.add_inventory("nam_prik_pao", 10)
	GameState.add_inventory("tofu", 10)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	p5.session.load_current_customer()
	var g5 := 0
	while p5.flow.runner.status != EventRunner.Status.WAITING_INPUT and g5 < 100:
		g5 += 1
		p5.session.next_event()
	c.check("モブのADJUST：客を断るボタンは出さない（can_decline が false）・次のEventには進める",
		p5.session.is_current_mob_order() and not p5.session.can_decline() and p5.session.can_next_event())
	p5.session.select_ingredient("nam_prik_pao")
	p5.session.select_ingredient("tofu")
	p5.session.complete_input()   # モブの最初の入力完了＝確認ボタンへ（まだ進まない）
	var choice: Dictionary = p5.session.mob_group_choice()
	c.check("団体の確認中：注文人数・出せる人数・レシピ番号1が出る。次のEvent・入力完了は押せない",
		p5.session.pending_group_choice and int(choice["ordered"]) == 4 and int(choice["recipe_number"]) == 1
			and int(choice["achievable"]) >= 0 and not p5.session.can_next_event() and not p5.session.can_complete_input(),
		str(choice))
	c.check("提供できる／挑戦できるの条件が人数と整合する",
		choice["can_serve"] == (int(choice["achievable"]) >= 1)
			and choice["can_retry"] == (int(choice["achievable"]) < int(choice["ordered"]))
			and int(choice["remaining"]) == int(choice["ordered"]) - int(choice["achievable"]))
	p5.session.group_decline(4)
	c.check("group_decline()：確認が終わり（pending_group_choice が false）、先へ進む",
		not p5.session.pending_group_choice and p5.session.mob_group_choice().is_empty())
	p5.free()

	# --- 6. 客を断る ---
	var p6 = _setup_open(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5 })
	p6.session.decline_customer()
	c.check("decline_customer()：断る印が付く（判定・売上は REACT で未提供として記録される）", p6.session.pending_decline)
	p6.free()

	GameState.reset_for_new_game()
	return c.finish()
