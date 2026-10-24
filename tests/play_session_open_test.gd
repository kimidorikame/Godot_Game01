extends RefCounted
## PlaySession（UI準備A③a：開店の客キュー・椀・提供・Eventの受け側）の検証。
## 対象：本番UIが使う操作（next_event・select_ingredient・discard_bowl・reask・complete_input）と問い
## （adjust_customer_id・react_for_now・current_servings・is_choosing_ingredients・is_awaiting_react・
## can_close_now など）が、PlaySession 単体で使えること、操作ごとに changed が出ること、
## DebugPanel の橋（_open・_reask_text など）が同じ状態を指すこと。
## 操作の中身そのもの（判定・売上・来店記録・団体・自動閉店など）は既存のスイートが確かめる。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	# Day2・新人警官（名前あり・1杯）を1人だけ接客する客キューで、ADJUST（椀作り）まで進める。
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	var s: PlaySession = panel.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["nam_prik_pao", "offal", "coconut_milk", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	var count := { "n": 0 }
	s.changed.connect(func(): count["n"] += 1)

	c.check("客キュー（open）：橋 _open も同じものを指し、最初の客は新人警官",
		s.open != null and panel._open == s.open and str(s.open.current_customer()) == "officer")
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 30:
		guard += 1
		s.next_event()
	c.check("next_event() で入力待ち（ADJUST）まで進み、操作ごとに changed が出る（runner の更新でも出るので、操作の回数以上）",
		s.flow.runner.status == EventRunner.Status.WAITING_INPUT and count["n"] >= guard, "%d／%d" % [count["n"], guard])
	c.check("ADJUST：名前あり客のid・椀を作れる・まだ判定待ちではない",
		s.adjust_customer_id() == "officer" and s.is_choosing_ingredients() and not s.is_awaiting_react())
	var react: Dictionary = s.react_for_now()
	c.check("今の注文の杯数は、注文（REACT）の servings と同じ", int(react.get("servings", 0)) > 0
		and s.current_servings() == int(react["servings"]), str(react))
	c.check("鍋が足りていて濃さも0でなければ、提供できない理由は無く、閉店もできない",
		not s.is_short_now() and not s.is_strength_zero() and not s.can_close_now())

	# 具材：選ぶと椀に入り、在庫が注文杯数ぶん減る
	var stock_before := GameState.fresh_count("tofu")
	count["n"] = 0
	s.select_ingredient("tofu")
	c.check("select_ingredient()：椀に入り・在庫が減り・changed が出る",
		(s.open.current_bowl["additions"] as Array).has("tofu")
			and GameState.fresh_count("tofu") == stock_before - s.current_servings() and count["n"] >= 1)
	s.select_ingredient("not_in_stock_item")
	c.check("在庫の無い品目は椀に入らない", not (s.open.current_bowl["additions"] as Array).has("not_in_stock_item"))

	# 聞き直し：状態は reask_*。表示文は橋が組む。何も変えない
	var money := GameState.money
	count["n"] = 0
	s.reask()
	c.check("reask()：聞き直した客のidと台詞の行が入り、changed が出る",
		s.reask_customer_id == "officer" and not s.reask_lines.is_empty() and count["n"] == 1)
	c.check("橋 _reask_text は注文カード＋台詞の行", panel._reask_text.contains("いつもの")
		and panel._reask_text.contains(str(s.reask_lines[0])), panel._reask_text)
	c.check("聞き直しは所持金を変えない", GameState.money == money)
	s.clear_reask()
	c.check("clear_reask() で消える（橋も空）", s.reask_customer_id == "" and s.reask_lines.is_empty() and panel._reask_text == "")

	# 廃棄：椀を作り直す（客は進めない）
	s.discard_bowl()
	c.check("discard_bowl()：作り直し（具材が空）・廃棄回数が1・橋 _bowl_discard_count も同じ値",
		(s.open.current_bowl["additions"] as Array).is_empty() and s.bowl_discard_count == 1 and panel._bowl_discard_count == 1)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("tofu")
	s.complete_input()
	c.check("complete_input()：入力待ちを抜けて先へ進む（ADJUSTより先）", s.flow.runner.current().get("type", "") != "ADJUST",
		str(s.flow.runner.current().get("type", "")))
	c.check("ログの記録用の状態も session が持つ（日次ログの客・杯数は橋 _log_* と同じ値）",
		panel._log_planned_cups == s.log_planned_cups and panel._log_quality_counts == s.log_quality_counts)

	panel.free()
	GameState.reset_for_new_game()
	return c.finish()
