extends RefCounted
## 修繕基金の画面（フェーズ4・手順4-9②。DESIGN.md 10.7。仮UI）の検証。
## CLOSE の語りを読み終えた後にだけ積み立て行（刻みのボタンと状態の文）を出す。[次のPhase]のゲートは
## 変えず、CLOSE の close_events（TEXT列）には足さない。段階が上がった瞬間は label を使った一行
## 「屋台が変わった：〇〇」。翌朝サマリー・結果画面・STATE VIEWER に、積んだ（累計が1以上の）ときだけ
## 屋台の行を足す（積まなければ従来と同一）。機能オフの設定では何も出ない。基金でゲームオーバーにならない。


func _setup(t: SceneTree, day: int, money: int):
	GameState.reset_for_new_game()
	GameState.day_count = day
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.ledger.clear()   # 朝の確保などの記帳を外す（使える現金＝所持金にする）
	GameState.money = money
	return panel


## CLOSE へ進み、語りを最後まで読む（runner が DONE になる）。
func _to_close_done(panel) -> void:
	panel.flow.force_phase(GameState.Phase.CLOSE)
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.DONE and guard < 100:
		guard += 1
		panel._on_next_event_pressed()


func _buttons(panel) -> Array:
	var out := []
	for child in panel._options_row.get_children():
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _fund_buttons(panel) -> Array:
	return _buttons(panel).filter(func(b): return b.text.begins_with("修繕基金に積む"))


func _press(panel, step: int) -> void:
	for b in _fund_buttons(panel):
		if b.text == "修繕基金に積む +%d" % step:
			b.pressed.emit()
			return


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Rules.set_campaign("week7")
	Rules.bills()
	ScheduleData.clear_cache()

	# --- 1. 積み立て行は CLOSE の語りを読み終えた後にだけ出る ---
	var p1 = _setup(t, 2, 245)
	p1.flow.force_phase(GameState.Phase.CLOSE)
	c.check("CLOSE の語りの途中（runner が未完了）は積み立て行を出さない",
		_fund_buttons(p1).is_empty() and not p1._runner_label.text.contains("修繕基金"))
	_to_close_done(p1)
	c.check("語りを読み終えた後：刻み25／50／100のボタンが出る",
		_fund_buttons(p1).map(func(b): return b.text) == ["修繕基金に積む +25", "修繕基金に積む +50", "修繕基金に積む +100"])
	var label: String = p1._runner_label.text
	c.check("状態：累計0（積み立て中）・次の段階まであと150・今日積める上限100",
		label.contains("── 修繕基金（任意・返金なし）──") and label.contains("累計: 0（積み立て中）")
			and label.contains("次の段階（手書きの看板）まであと150") and label.contains("今日積める上限: 100"), label)
	c.check("上限ちょうど（245−145＝100）なので3つとも押せる", _fund_buttons(p1).all(func(b): return not b.disabled))
	c.check("CLOSE の close_events（TEXT列）は変えていない（足していない）",
		JSON.stringify(p1.flow.runner.events) == JSON.stringify(Day1Events.close_events()))
	c.check("積まなくても [次のPhase] は押せる（ゲートは変えない）", not p1.flow.is_advance_blocked())

	# --- 2. 押すと積まれる。段階が上がった瞬間は label を使った一行 ---
	var money_before: int = GameState.money
	var rep_before: int = GameState.reputation
	var inventory_before := JSON.stringify(GameState.inventory)
	var plan_before := JSON.stringify(GameState.today_plan)
	_press(p1, 100)
	c.check("100を積む：所持金が100減り、帳簿に fund が負額で1行", GameState.money == money_before - 100
		and GameState.ledger.filter(func(e): return e["category"] == "fund").size() == 1
		and RepairFund.paid() == 100)
	c.check("累計100（積み立て中）・段階は上がらないので一行は出ない",
		p1._runner_label.text.contains("累計: 100（積み立て中）") and not p1._runner_label.text.contains("屋台が変わった"))
	c.check("上限が0になり、ボタンは全部無効", _fund_buttons(p1).all(func(b): return b.disabled)
		and p1._runner_label.text.contains("今日積める上限: 0"))
	GameState.money += 200   # 段階を上げるために現金を足す（上限の計算は別のテストで見ている）
	p1._refresh()
	_press(p1, 50)
	c.check("累計150で段階が上がる：「屋台が変わった：手書きの看板」（label を使った固定の言い回し）",
		RepairFund.paid() == 150 and p1._runner_label.text.contains("累計: 150（手書きの看板）")
			and p1._runner_label.text.contains("屋台が変わった：手書きの看板") and not p1._runner_label.text.contains("（仮）"),
		p1._runner_label.text)
	c.check("次の段階は棚と雨よけ（あと150）", p1._runner_label.text.contains("次の段階（棚と雨よけ）まであと150"))
	_press(p1, 25)
	c.check("さらに25を積んで175（段階は手書きの看板のまま）", RepairFund.paid() == 175
		and p1._runner_label.text.contains("累計: 175（手書きの看板）"))
	c.check("積んでも評判・在庫・DayPlan は変わらない（所持金と帳簿以外）",
		GameState.reputation == rep_before and JSON.stringify(GameState.inventory) == inventory_before
			and JSON.stringify(GameState.today_plan) == plan_before)
	# フェーズが替わると行も通知も消える
	p1.flow.advance_phase()   # CLOSE → NEXT_DAY
	c.check("NEXT_DAY に進むと積み立て行と通知は消える（フェーズは NEXT_DAY）",
		GameState.phase == GameState.Phase.NEXT_DAY and _fund_buttons(p1).is_empty() and p1._fund_notice == ""
			and not p1._runner_label.text.contains("修繕基金"))

	# --- 3. 翌朝サマリーと STATE VIEWER：積んだ日だけ屋台の行・支出内訳に修繕基金 ---
	p1.flow.advance_phase()   # NEXT_DAY → WAKE（day_ending で前日の成績を作る）
	var summary: String = p1._last_day_summary_text if p1._last_day_summary_text != "" else p1.flow.runner.events[0]["text"]
	c.check("翌朝サマリーに「屋台: 手書きの看板（修繕 累計175）」と支出内訳の修繕基金175",
		summary.contains("屋台: 手書きの看板（修繕 累計175）") and summary.contains("修繕基金175"), summary)
	c.check("STATE VIEWER に fund の行（budget の次）", p1._format_game_state().contains("fund(修繕基金): 累計175（手書きの看板）"))
	p1.free()

	# 積まなかった日は従来と同一（機能オフと文字列が一致）
	var entry := { "day": 2, "opening_money": 600, "closing_money": 510, "opening_reputation": 30, "closing_reputation": 31,
		"served_cups": 8, "planned_cups": 9, "unserved_cups": 1, "sale_total": 360,
		"quality_counts": { "GREAT": 1, "GOOD": 5, "OK": 2, "BAD": 0 }, "quality": 72.5, "spoiled_value": 0,
		"water_used": 1, "dashi_used": 0, "closed_early": false,
		"spend_by_category": { "daily_cost": 65, "prep": 80 } }
	var p3 = _setup(t, 2, 600)
	var with_feature: String = p3._format_day_summary(entry)
	var fund_cache = Rules._cache["repair_fund"]
	Rules._cache.erase("repair_fund")
	var without_feature: String = p3._format_day_summary(entry)
	Rules._cache["repair_fund"] = fund_cache
	c.check("基金を積まなかった日のサマリーは、基金の機能が無い場合と1文字も変わらない",
		with_feature == without_feature and not with_feature.contains("屋台") and not with_feature.contains("修繕基金"))
	c.check("積まない間（累計0）は STATE VIEWER に fund の行を出さない", not p3._format_game_state().contains("fund("))
	c.check("支出内訳の表示名：fund は修繕基金（末尾）",
		p3._format_spend_by_category({ "daily_cost": 65, "fund": 100 }) == "支出内訳: 運営費65／修繕基金100")
	p3.free()

	# --- 4. 結果画面 1枚目：累計が1以上のときだけ屋台の行。累計0は従来と同一 ---
	var base_summary := Result.summarize([], [], 700)
	var report0 := Result.format_report(base_summary)
	c.check("累計0：結果画面1枚目に屋台の行は無い", not report0.contains("屋台"))
	var ledger_fund := [ { "category": "fund", "amount": -150 } ]
	var report1 := Result.format_report(Result.summarize([], ledger_fund, 550))
	c.check("累計150：現金の行の次に「屋台: 手書きの看板（修繕 累計150）」",
		report1.split("\n")[2] == "屋台: 手書きの看板（修繕 累計150）" and report1.split("\n")[1].begins_with("現金: 550 ＋ 支払済み修繕額: 150"), report1)
	c.check("行を足した以外は従来と同じ（行を除くと累計0と同じ構造）",
		report1.split("\n").size() == report0.split("\n").size() + 1)
	Rules._cache.erase("repair_fund")
	c.check("機能オフでは修繕額があっても屋台の行を足さない", not Result.format_report(Result.summarize([], ledger_fund, 550)).contains("屋台"))
	Rules._cache["repair_fund"] = fund_cache

	# --- 5. 最終段階：完了。ボタンは出さない ---
	var p5 = _setup(t, 3, 1000)
	GameState.ledger.append({ "day": 2, "phase": "CLOSE", "category": "fund", "amount": -600, "item": "", "count": 0,
		"unit_price": 0, "ref": "" })
	_to_close_done(p5)
	c.check("最終段階（600）に届いたら「完了」・ボタンなし",
		p5._runner_label.text.contains("累計: 600（屋台を自分の名義に）完了") and _fund_buttons(p5).is_empty())
	p5.free()

	# --- 6. スマホを開いている間は出さない ---
	var p6 = _setup(t, 2, 400)
	_to_close_done(p6)
	p6._phone_mode = true
	p6._refresh()
	c.check("スマホを開いている間は積み立て行を出さない", _fund_buttons(p6).is_empty() and not p6._runner_label.text.contains("修繕基金"))
	p6.free()

	# --- 7. 会話ログ・既読は基金の表示に影響されない ---
	TalkLog.clear()
	var p7 = _setup(t, 2, 400)
	_to_close_done(p7)
	_press(p7, 25)
	c.check("基金の状態の文・通知は会話ログ（TalkLog）に入らない", not str(TalkLog.entries).contains("修繕基金"))
	p7.free()

	# --- 8. 機能オフ：積み立て行も表示も出ない ---
	Rules._cache.erase("repair_fund")
	var p8 = _setup(t, 2, 400)
	_to_close_done(p8)
	c.check("repair_fund の無い設定：積み立て行・状態の文が出ない（CLOSE の画面は従来のまま）",
		_fund_buttons(p8).is_empty() and not p8._runner_label.text.contains("修繕基金") and _buttons(p8).is_empty())
	p8.free()
	Rules._cache["repair_fund"] = fund_cache

	# --- 9. 基金でゲームオーバーにならない：積めるだけ積んで翌朝へ ---
	for money in [145, 150, 200, 300, 500]:
		var p9 = _setup(t, 2, money)
		_to_close_done(p9)
		var guard := 0
		while guard < 100 and _fund_buttons(p9).any(func(b): return not b.disabled):
			guard += 1
			for step in [100, 50, 25]:
				if RepairFund.can_contribute(step):
					_press(p9, step)
					break
		p9.flow.advance_phase()   # CLOSE → NEXT_DAY
		p9.flow.advance_phase()   # NEXT_DAY → WAKE（運営費を払う）
		c.check("所持金%dから積めるだけ積んでも、翌朝（Day3）に運営費が払えてゲームオーバーにならない（残り%d）" % [money, GameState.money],
			GameState.phase == GameState.Phase.WAKE and GameState.day_count == 3
				and GameState.money >= RepairFund.min_prep_price())
		p9.free()

	# --- 10. 最終日：積んだ分が結果画面の現金＋修繕額に入る（翌朝の運営費は発生しない） ---
	var p10 = _setup(t, GameState.FINAL_DAY, 300)
	_to_close_done(p10)
	c.check("最終日の上限は使える現金そのもの（300）", p10._runner_label.text.contains("今日積める上限: 300"))
	_press(p10, 100)
	_press(p10, 100)
	p10.flow.advance_phase()   # CLOSE → NEXT_DAY
	p10.flow.advance_phase()   # NEXT_DAY → RESULT
	c.check("最終日の基金は結果画面へ：現金100＋支払済み修繕額200＝300（目標判定は不利にならない）",
		GameState.phase == GameState.Phase.RESULT and GameState.money == 100
			and Result.summarize(GameState.day_records, GameState.ledger, GameState.money)["cash_plus_repair"] == 300)
	c.check("結果画面の1枚目に屋台の行", str(p10.flow.runner.events[0]["text"]).contains("屋台: 手書きの看板（修繕 累計200）"),
		str(p10.flow.runner.events[0]["text"]))
	p10.free()

	Rules.set_campaign("week7")
	GameState.reset_for_new_game()
	return c.finish()
