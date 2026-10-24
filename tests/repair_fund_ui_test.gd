extends RefCounted
## 修繕基金の画面（フェーズ4・手順4-9②／④。DESIGN.md 10.7のMVP版。仮UI）の検証。
## CLOSE の語りを読み終えた後にだけ積み立て行（額のボタンと状態の文）を出す。[次のPhase]のゲートは変えず、
## CLOSE の close_events（TEXT列）には足さない。修繕済みになった瞬間は label を使った一行「修繕できた：〇〇」。
## 翌朝サマリー・結果画面・STATE VIEWER に、積んだ（累計が1以上の）ときだけ各対象の進捗を足す（積まなければ
## 従来と同一）。機能オフの設定では何も出ない。基金でゲームオーバーにならない。
## 状態は 評判55・今日の計画の需要の中心14 にそろえる（翌日の確保額＝運営費＋仕込み140＋材料費350。所持金が確保額を上回った分だけ積める）。


func _setup(t: SceneTree, day: int, money: int):
	GameState.reset_for_new_game()
	GameState.day_count = day
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.ledger.clear()   # 朝の確保などの記帳を外す（使える現金＝所持金にする）
	GameState.money = money
	GameState.reputation = 55
	GameState.today_plan = { "day": day, "demand_center": 14, "slots": [], "mob_instances": {} }
	return panel


## CLOSE へ進み、語りを最後まで読む（runner が DONE になる）。
func _to_close_done(panel) -> void:
	panel.session.flow.force_phase(GameState.Phase.CLOSE)
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.DONE and guard < 100:
		guard += 1
		panel.session.next_event()


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


func _add_fund(day: int, amount: int, ref: String) -> void:
	GameState.ledger.append({ "day": day, "phase": "CLOSE", "category": "fund", "amount": -amount,
		"item": "repair_fund", "count": 0, "unit_price": 0, "ref": ref })


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	# 運営費に連動する値は定数から計算する（運営費を変えても境目の検査が追従する）。
	# r14＝見込み14杯の翌日の確保額＝運営費＋仕込み140＋材料費14×25、r11＝見込み11杯＝運営費＋仕込み110＋材料費11×25。
	var op: int = GameState.DAILY_OPERATING_COST
	var r14: int = op + 140 + 350
	var r11: int = op + 110 + 275
	Rules.set_campaign("week7")
	Rules.bills()
	ScheduleData.clear_cache()
	var fund_config = Rules._cache["repair_fund"]

	# --- 1. 積み立て行は CLOSE の語りを読み終えた後にだけ出る ---
	var p1 = _setup(t, 2, 600)
	p1.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("CLOSE の語りの途中（runner が未完了）は積み立て行を出さない",
		_fund_buttons(p1).is_empty() and not p1._runner_label.text.contains("修繕基金"))
	_to_close_done(p1)
	c.check("語りを読み終えた後：刻み10／30のボタンが出る",
		_fund_buttons(p1).map(func(b): return b.text) == ["修繕基金に積む +10", "修繕基金に積む +30"])
	var label: String = p1._runner_label.text
	c.check("状態：各対象の進捗・今夜積んだ額0／30・今日積める上限30",
		label.contains("── 修繕基金（任意・返金なし）──")
			and label.contains("手書きの看板 0/150／棚 0/200／雨よけ 0/200／屋台を自分の名義に 0/600（未解放）")
			and label.contains("今夜積んだ額: 0／30") and label.contains("今日積める上限: 30"), label)
	c.check("上限（600−確保額）が1晩の上限（30）以上なので2つとも押せる", _fund_buttons(p1).all(func(b): return not b.disabled))
	c.check("CLOSE の close_events（TEXT列）は変えていない（足していない）",
		JSON.stringify(p1.session.flow.runner.events) == JSON.stringify(Day1Events.close_events()))
	c.check("積まなくても [次のPhase] は押せる（ゲートは変えない）", not p1.session.flow.is_advance_blocked())

	# --- 2. 押すと最初の未修繕の対象（看板）に積まれる。1晩の上限に届くとボタンは全部無効 ---
	var rep_before: int = GameState.reputation
	var inventory_before := JSON.stringify(GameState.inventory)
	_press(p1, 30)
	c.check("30を積む：所持金が30減り、帳簿に fund が負額で1行（ref＝sign）", GameState.money == 570
		and GameState.ledger.filter(func(e): return e["category"] == "fund" and e["ref"] == "sign" and e["amount"] == -30).size() == 1)
	c.check("進捗は 手書きの看板 30/150。今夜積んだ額は30／30で、修繕済みではないので一行は出ない",
		p1._runner_label.text.contains("手書きの看板 30/150") and p1._runner_label.text.contains("今夜積んだ額: 30／30")
			and not p1._runner_label.text.contains("修繕できた"))
	c.check("1晩の上限に届いたので、ボタンは全部無効", _fund_buttons(p1).all(func(b): return b.disabled)
		and p1._runner_label.text.contains("今日積める上限: 0"))
	c.check("積んでも評判・在庫は変わらない（所持金と帳簿以外）", GameState.reputation == rep_before
		and JSON.stringify(GameState.inventory) == inventory_before)
	p1.session.flow.advance_phase()   # CLOSE → NEXT_DAY
	c.check("NEXT_DAY に進むと積み立て行と通知は消える", GameState.phase == GameState.Phase.NEXT_DAY
		and _fund_buttons(p1).is_empty() and p1.session.fund_notice == "" and not p1._runner_label.text.contains("修繕基金"))

	# --- 3. 安全上限が1晩の上限より小さい夜：額のボタンの有効・無効 ---
	var p3 = _setup(t, 2, r14 + 20)   # 確保額+20−確保額＝20（< 30）
	_to_close_done(p3)
	var b3 := _fund_buttons(p3)
	c.check("安全上限20：+30は無効・+10は有効（上限が1晩の上限より小さい）", b3[0].disabled == false and b3[1].disabled == true
		and p3._runner_label.text.contains("今日積める上限: 20"), p3._runner_label.text)
	_press(p3, 30)
	c.check("無効な+30を押しても積まれない", GameState.money == r14 + 20 and RepairFund.paid() == 0)
	p3.free()

	# --- 4. 修繕済みになった瞬間：label を使った一行「修繕できた：〇〇」。次の対象へ移る ---
	var p4 = _setup(t, 4, 700)
	_add_fund(2, 120, "sign")
	_to_close_done(p4)
	_press(p4, 30)
	c.check("看板が150に届く：「修繕できた：手書きの看板」と進捗に「修繕済み」",
		p4._runner_label.text.contains("修繕できた：手書きの看板") and p4._runner_label.text.contains("手書きの看板 150/150 修繕済み")
			and not p4._runner_label.text.contains("（仮）"), p4._runner_label.text)
	c.check("通知は会話ログ（TalkLog）に入らない", not str(TalkLog.entries).contains("修繕できた"))
	p4.free()
	var p4b = _setup(t, 4, 700)
	_add_fund(2, 150, "sign")
	_to_close_done(p4b)
	_press(p4b, 10)
	c.check("看板が修繕済みなら、次の積む先は棚", RepairFund.target_paid("shelf") == 10 and RepairFund.target_paid("sign") == 150)
	p4b.free()

	# --- 5. 翌朝サマリー・STATE VIEWER：積んだ日だけ各対象の進捗。積まなかった日は従来と同一 ---
	var p5 = _setup(t, 2, 600)
	_to_close_done(p5)
	_press(p5, 30)
	p5.session.flow.advance_phase()   # CLOSE → NEXT_DAY
	p5.session.flow.advance_phase()   # NEXT_DAY → WAKE（day_ending で前日の成績を作る）
	var summary: String = p5.session.last_day_summary_text if p5.session.last_day_summary_text != "" else p5.session.flow.runner.events[0]["text"]
	c.check("翌朝サマリーに「屋台: 手書きの看板 30/150／…」と支出内訳の修繕基金30",
		summary.contains("屋台: 手書きの看板 30/150／棚 0/200／雨よけ 0/200") and summary.contains("修繕基金30"), summary)
	c.check("STATE VIEWER に fund の行（累計と修繕済み：なし）", p5._format_game_state().contains("fund(修繕基金): 累計30／修繕済み: なし"))
	p5.free()
	var entry := { "day": 2, "opening_money": 600, "closing_money": 510, "opening_reputation": 30, "closing_reputation": 31,
		"served_cups": 8, "planned_cups": 9, "unserved_cups": 1, "sale_total": 360,
		"quality_counts": { "GREAT": 1, "GOOD": 5, "OK": 2, "BAD": 0 }, "quality": 72.5, "spoiled_value": 0,
		"water_used": 1, "dashi_used": 0, "closed_early": false,
		"spend_by_category": { "daily_cost": 65, "prep": 80 } }
	var p5b = _setup(t, 2, 600)
	var with_feature: String = p5b._format_day_summary(entry)
	Rules._cache.erase("repair_fund")
	var without_feature: String = p5b._format_day_summary(entry)
	Rules._cache["repair_fund"] = fund_config
	c.check("基金を積まなかった日のサマリーは、基金の機能が無い場合と1文字も変わらない",
		with_feature == without_feature and not with_feature.contains("屋台") and not with_feature.contains("修繕基金"))
	c.check("積まない間（累計0）は STATE VIEWER に fund の行を出さない", not p5b._format_game_state().contains("fund("))
	c.check("支出内訳の表示名：fund は修繕基金（末尾）",
		p5b._format_spend_by_category({ "daily_cost": 65, "fund": 30 }) == "支出内訳: 運営費65／修繕基金30")
	p5b.free()

	# --- 6. 結果画面 1枚目：累計が1以上のときだけ各対象の進捗の行。累計0は従来と同一 ---
	var report0 := Result.format_report(Result.summarize([], [], 700))
	c.check("累計0：結果画面1枚目に屋台の行は無い", not report0.contains("屋台"))
	GameState.reset_for_new_game()
	GameState.ledger = [ { "category": "fund", "amount": -150, "ref": "sign", "day": 5 }, { "category": "fund", "amount": -40, "ref": "shelf", "day": 6 } ]
	var report1 := Result.format_report(Result.summarize([], GameState.ledger, 510))
	c.check("累計190：現金の行の次に「屋台: 各対象の進捗」（修繕済みの対象名が分かる）",
		report1.split("\n")[2] == "屋台: 手書きの看板 150/150 修繕済み／棚 40/200／雨よけ 0/200／屋台を自分の名義に 0/600（未解放）"
			and report1.split("\n")[1].begins_with("現金: 510 ＋ 支払済み修繕額: 190"), report1)
	c.check("行を足した以外は従来と同じ", report1.split("\n").size() == report0.split("\n").size() + 1)
	Rules._cache.erase("repair_fund")
	c.check("機能オフでは修繕額があっても屋台の行を足さない", not Result.format_report(Result.summarize([], GameState.ledger, 510)).contains("屋台"))
	Rules._cache["repair_fund"] = fund_config

	# --- 7. 全対象が修繕済み：完了。ボタンは出さない ---
	var p7 = _setup(t, 3, 1000)
	for pair in [["sign", 150], ["shelf", 200], ["awning", 200], ["owner", 600]]:
		_add_fund(2, pair[1], pair[0])
	_to_close_done(p7)
	c.check("全対象が修繕済みなら「完了」・ボタンなし", p7._runner_label.text.contains("完了") and _fund_buttons(p7).is_empty())
	p7.free()

	# --- 8. スマホを開いている間・機能オフでは出ない ---
	var p8 = _setup(t, 2, 600)
	_to_close_done(p8)
	p8._phone_mode = true
	p8._refresh()
	c.check("スマホを開いている間は積み立て行を出さない", _fund_buttons(p8).is_empty() and not p8._runner_label.text.contains("修繕基金"))
	p8.free()
	Rules._cache.erase("repair_fund")
	var p8b = _setup(t, 2, 600)
	_to_close_done(p8b)
	c.check("repair_fund の無い設定：積み立て行・状態の文が出ない（CLOSE の画面は従来のまま）",
		_fund_buttons(p8b).is_empty() and not p8b._runner_label.text.contains("修繕基金") and _buttons(p8b).is_empty())
	p8b.free()
	Rules._cache["repair_fund"] = fund_config

	# --- 9. 基金でゲームオーバーにならない：積めるだけ積んで翌朝へ ---
	for money in [r14, r14 + 5, r14 + 20, r14 + 30, 700, 1000]:
		var p9 = _setup(t, 2, money)
		_to_close_done(p9)
		var guard := 0
		while guard < 100 and _fund_buttons(p9).any(func(b): return not b.disabled):
			guard += 1
			for step in [30, 10]:
				if RepairFund.can_contribute(RepairFund.first_open_target(), step):
					_press(p9, step)
					break
		p9.session.flow.advance_phase()   # CLOSE → NEXT_DAY
		p9.session.flow.advance_phase()   # NEXT_DAY → WAKE（運営費を払う）
		c.check("所持金%dから積めるだけ積んでも、翌朝（Day3）に運営費が払えてゲームオーバーにならない（残り%d）" % [money, GameState.money],
			GameState.phase == GameState.Phase.WAKE and GameState.day_count == 3 and GameState.money >= r14 - op)
		p9.free()

	# --- 10. 最終日：1晩の上限が掛かる。積んだ分が結果画面の現金＋修繕額に入る（翌朝の運営費は発生しない） ---
	var p10 = _setup(t, GameState.FINAL_DAY, 300)
	_to_close_done(p10)
	c.check("最終日の安全上限は使える現金そのものだが、積めるのは1晩の上限30まで", p10._runner_label.text.contains("今日積める上限: 30"))
	_press(p10, 30)
	_press(p10, 10)
	p10.session.flow.advance_phase()   # CLOSE → NEXT_DAY
	p10.session.flow.advance_phase()   # NEXT_DAY → RESULT
	c.check("最終日の基金は結果画面へ：現金270＋支払済み修繕額30＝300（1晩の上限で一括払いはできない）",
		GameState.phase == GameState.Phase.RESULT and GameState.money == 270 and RepairFund.paid() == 30
			and Result.summarize(GameState.day_records, GameState.ledger, GameState.money)["cash_plus_repair"] == 300)
	c.check("結果画面の1枚目に屋台の行", str(p10.session.flow.runner.events[0]["text"]).contains("屋台: 手書きの看板 30/150／"),
		str(p10.session.flow.runner.events[0]["text"]))
	p10.free()

	# --- 11. 積む先の選択（切り替えボタン。実行時のみ・保存しない） ---
	var p11 = _setup(t, 3, 700)
	_to_close_done(p11)
	var selectors: Array = _buttons(p11).filter(func(b): return b.text.begins_with("積む先："))
	c.check("対象ごとの切り替えボタン（進捗つき）。既定は最初の未修繕の対象（看板）に「▶」、名義は未解放で無効",
		selectors.map(func(b): return b.text) == ["積む先：▶手書きの看板 0/150", "積む先：棚 0/200", "積む先：雨よけ 0/200",
			"積む先：屋台を自分の名義に 0/600（未解放）"] and selectors[3].disabled and not selectors[1].disabled,
		str(selectors.map(func(b): return b.text)))
	c.check("状態の文：積む先は看板・安全上限の根拠（明日の仕入れ分を残す）が出る",
		p11._runner_label.text.contains("積む先: 手書きの看板")
			and p11._runner_label.text.contains("（明日の仕入れ分を残す：運営費%d＋請求0＋仕込み140＋材料費350＝%d。見込み14杯）" % [op, r14]),
		p11._runner_label.text)
	selectors[1].pressed.emit()   # 棚を選ぶ
	c.check("棚を選ぶと「▶」が移り、状態の文の積む先も棚になる",
		_buttons(p11).filter(func(b): return b.text == "積む先：▶棚 0/200").size() == 1 and p11._runner_label.text.contains("積む先: 棚")
			and p11._fund_selected() == "shelf")
	_press(p11, 30)
	c.check("選んだ対象（棚）に積まれ、帳簿の ref は shelf・看板は0のまま", RepairFund.target_paid("shelf") == 30
		and RepairFund.target_paid("sign") == 0 and GameState.ledger.filter(func(e): return e["category"] == "fund" and e["ref"] == "shelf").size() == 1)
	p11._on_fund_target_selected("owner")
	c.check("未解放の名義は選べない（選択は変わらない）", p11._fund_selected() == "shelf")
	p11._on_fund_target_selected("nothing")
	c.check("存在しない対象も選べない", p11._fund_selected() == "shelf")
	c.check("選択は保存の項目ではない（朝の保存に入らない）", not GameState.to_dict().has("fund_target") and MorningSave.VERSION == 6)
	p11.session.flow.advance_phase()   # CLOSE → NEXT_DAY
	c.check("フェーズが替わると選択は消える（既定に戻る）", p11.session.fund_target == "" and p11._fund_selected() == "sign")
	p11.free()
	# 選んだ対象が修繕済みになったら、既定（最初の未修繕の対象）へ戻る
	var p11b = _setup(t, 4, 700)
	_add_fund(2, 120, "awning")
	_add_fund(2, 100, "sign")
	_to_close_done(p11b)
	p11b._on_fund_target_selected("awning")
	_press(p11b, 30)
	c.check("雨よけを150/200まで積んでも修繕済みでなければ、選択は雨よけのまま", RepairFund.target_paid("awning") == 150
		and p11b._fund_selected() == "awning")
	_add_fund(3, 50, "awning")
	p11b._refresh()
	c.check("選んだ対象が修繕済みになると、選択は最初の未修繕の対象（看板）に戻り、修繕済みの対象は選べない",
		RepairFund.is_repaired("awning") and p11b._fund_selected() == "sign"
			and _buttons(p11b).filter(func(b): return b.text == "積む先：雨よけ 200/200 修繕済み")[0].disabled)
	p11b.free()
	# 最終日は翌日が無いので「明日の仕入れ分」の行は出ない
	var p11c = _setup(t, GameState.FINAL_DAY, 300)
	_to_close_done(p11c)
	c.check("最終日は翌日の確保額が0なので「明日の仕入れ分を残す」の行は出ない", not p11c._runner_label.text.contains("明日の仕入れ分を残す")
		and p11c._runner_label.text.contains("今日積める上限: 30"))
	p11c.free()

	Rules.set_campaign("week7")
	GameState.reset_for_new_game()
	return c.finish()
