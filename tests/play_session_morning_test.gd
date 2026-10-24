extends RefCounted
## PlaySession（UI準備A⑤：朝・再挑戦・続きから・結果・フェーズの組み立て）の検証。
## 対象：PlaySession を画面なし（DebugPanelなし）で起動して、朝〜夜〜翌朝まで進められること
## （本番UIが画面の前に PlaySession だけを使える）、フェーズの合図（phase_entering）、再挑戦・
## 新しい周・続きから、ゲームオーバーの出口。各処理の中身そのもの（保存の形式・日程・結果の集計など）は
## 既存のスイート（save_state_test・result_flow_test・save_file_test など）が確かめる。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 画面なしで起動して、朝→仕込み→開店→閉店→翌朝まで進める ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var s := PlaySession.new()
	t.root.add_child(s)
	var entered := []
	s.phase_entering.connect(func(phase): entered.append(phase))
	var changes := { "n": 0 }
	s.changed.connect(func(): changes["n"] += 1)
	s.start()
	c.check("start()：朝（WAKE）の列が組まれ、運営費が引かれ、朝の記録が1件ある",
		GameState.phase == GameState.Phase.WAKE and s.flow.runner != null and s.flow.runner.events.size() > 0
			and GameState.money == GameState.INITIAL_MONEY - GameState.DAILY_OPERATING_COST
			and GameState.morning_snapshots.has(2))
	c.check("最初の組み立て（start）でも phase_entering が出る", entered == [GameState.Phase.WAKE])
	s.flow.advance_phase()   # WAKE→PREP（フェーズの遷移を session が自分で受ける）
	c.check("フェーズが替わると、session が自分で列を組み直し、phase_entering と changed を出す",
		GameState.phase == GameState.Phase.PREP and entered.back() == GameState.Phase.PREP and changes["n"] >= 1
			and s.flow.runner.events.size() > 0)
	var guard := 0
	while not s.is_in_prep_tier() and guard < 50:
		guard += 1
		s.next_event()
	s.choose_prep_tier("small")
	guard = 0
	while not s.is_in_market() and guard < 50:
		guard += 1
		s.next_event()
	s.exit_market()
	guard = 0
	while s.flow.runner.status != EventRunner.Status.DONE and guard < 50:
		guard += 1
		s.next_event()
	s.flow.advance_phase()   # PREP→OPEN
	c.check("OPEN：客キューが session に作られ、最初の客が読み込まれる",
		GameState.phase == GameState.Phase.OPEN and s.open != null)
	s.flow.force_phase(GameState.Phase.CLOSE)
	guard = 0
	while s.flow.runner.status != EventRunner.Status.DONE and guard < 100:
		guard += 1
		s.next_event()
	s.flow.advance_phase()   # CLOSE→NEXT_DAY
	s.flow.advance_phase()   # NEXT_DAY→WAKE（日の終わり→翌朝）
	c.check("翌朝（Day3）：その日の記録が累計に1件・朝の記録がDay3に増える・前日成績の問いが前日を返す",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == 3 and GameState.day_records.size() == 1
			and GameState.morning_snapshots.has(3) and int(s.previous_day_record().get("day", 0)) == 2)
	s.free()

	# --- 2. 再挑戦・新しい周・続きから・ゲームオーバーの出口（DebugPanelの橋と同じ状態を指す） ---
	GameState.reset_for_new_game()
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	var p: PlaySession = panel.session
	GameState.money = 0
	p.game_over("テスト")
	c.check("ゲームオーバー：GAME_OVER・[Day1の朝から]の記録が無ければ新しい周と同じ動作（run_again）",
		GameState.phase == GameState.Phase.GAME_OVER)
	var ex: Dictionary = p.exits()
	c.check("exits()（GAME_OVER・朝の記録あり）：同じ朝から・直近の朝・Day1の朝から・新しい周が選べる。Day1の朝からは新しい周ではない",
		ex["available"] and ex["can_retry"] and ex["can_last_morning"] and ex["can_run_again"] and not ex["run_again_is_new_run"]
			and ex["can_new_run"], str(ex))
	GameState.morning_snapshots.clear()
	ex = p.exits()
	c.check("exits()（GAME_OVER・朝の記録が空）：直近の朝は選べず、Day1の朝からは『新しい周と同じ』になる",
		not ex["can_retry"] and not ex["can_last_morning"] and ex["can_run_again"] and ex["run_again_is_new_run"]
			and ex["can_new_run"], str(ex))
	p.run_again()
	c.check("run_again()：記録が空でも新しい周のDay1のWAKEへ", GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
		and GameState.money == GameState.INITIAL_MONEY - GameState.DAILY_OPERATING_COST)
	GameState.day_count = 1
	var morning_money := GameState.money
	GameState.money = 5
	c.check("retry_from_morning(1)：Day1の朝へ戻る（所持金が朝の値に戻る）",
		p.retry_from_morning(1) and GameState.money == GameState.INITIAL_MONEY - GameState.DAILY_OPERATING_COST
			and GameState.phase == GameState.Phase.WAKE and morning_money == GameState.money)
	c.check("存在しない日の朝へは戻れない（false）", not p.retry_from_morning(9))
	panel._phone_mode = true
	panel._phone_tab = "news"
	p.flow.advance_phase()
	c.check("フェーズが替わるとき、DebugPanelは表示だけの状態（スマホの開閉・タブ）を捨てる（phase_entering を受ける）",
		not panel._phone_mode and panel._phone_tab == "recipe")
	p.new_run()
	c.check("new_run()：新しい周のDay1のWAKE・累計空・朝の記録は新しいDay1だけ",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1 and GameState.day_records.is_empty()
			and GameState.morning_snapshots.size() == 1 and GameState.morning_snapshots.has(1))
	c.check("橋 _save_armed／_pending_continue は session の状態を指す",
		panel._save_armed == p.save_armed and panel._pending_continue == p.pending_continue)
	ex = p.exits()
	c.check("exits()：結果でもゲームオーバーでもない通常の朝は available が false", not ex["available"])
	GameState.phase = GameState.Phase.RESULT
	ex = p.exits()
	c.check("exits()（RESULT・Day1の記録あり）：Day1の朝から・直近の朝・新しい周が選べる（同じ朝からの仮ボタンは GAME_OVER のみ）",
		ex["available"] and ex["can_run_again"] and ex["can_last_morning"] and ex["can_new_run"] and not ex["can_retry"])
	GameState.morning_snapshots.erase(1)
	c.check("exits()（RESULT・Day1の記録が無い）：Day1の朝からは選べない", not p.exits()["can_run_again"])
	var rv: Dictionary = p.result_view()
	c.check("result_view()：成績の集計と、目標の判定（完走・標準・挑戦・料理・常連の5つ）",
		rv["summary"].has("cash") and rv["goals"].size() == 5 and rv["goals"][0]["id"] == "complete", str(rv["goals"].size()))
	panel.free()
	GameState.reset_for_new_game()
	return c.finish()
