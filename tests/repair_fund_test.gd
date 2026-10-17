extends RefCounted
## 修繕基金（フェーズ4・手順4-9①。DESIGN.md 10.7）の検証。
## 段階の境目、積む処理（所持金と帳簿の fund）、安全上限（積んでも翌朝の運営費が払える・翌日に最小の
## 仕込みが買える・ゲームオーバーにならない）、拒否される場合、目標判定（現金＋修繕額）が不利に
## ならないこと、効果が無いこと（所持金と帳簿以外が不変）、朝の保存（版6のまま・再挑戦で戻る）、
## 機能オフ・不正な設定。段階の境目は最小の刻みの倍数（コメントの前提を検査する）。


func _at_close(day: int, money: int) -> void:
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	GameState.phase = GameState.Phase.CLOSE


func _funds() -> Array:
	return GameState.ledger.filter(func(e): return e["category"] == "fund")


## 所持金と帳簿以外の状態の写し（基金は効果を持たない）。
func _others() -> String:
	var d := GameState.to_dict()
	d.erase("money")
	d.erase("ledger")
	return JSON.stringify([d, GameState.phase])


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Rules.set_campaign("week7")
	Rules.bills()
	GameState.reset_for_new_game()

	# --- 0. 設定の読み出しと前提 ---
	c.check("機能オン：刻み25／50／100・段階150／300／600（DESIGN.md 10.7）",
		RepairFund.enabled() and RepairFund.steps() == [25, 50, 100]
			and RepairFund.stages().map(func(s): return s["total"]) == [150, 300, 600]
			and RepairFund.stages().map(func(s): return s["label"]) == ["手書きの看板", "棚と雨よけ", "屋台を自分の名義に"])
	var smallest: int = RepairFund.steps()[0]
	c.check("前提：段階の境目は最小の刻み（%d）の倍数（刻みだけで境目ぴったりに届く）" % smallest,
		RepairFund.stages().all(func(s): return int(s["total"]) % smallest == 0))
	c.check("段階の note は仮（（仮））のままデータに残る", RepairFund.stages().all(func(s): return s["note"] == "（仮）"))
	c.check("最初の段階に届かないうちの呼び名は in_progress_label", RepairFund.in_progress_label() == "積み立て中")
	c.check("最小の仕込み額は80（week7 の prep_tiers の最小）", RepairFund.min_prep_price() == 80)
	c.check("Rules.bills_total_on：徴収日（Day1）は場所代＋水道代＝140、他の日は0",
		Rules.bills_total_on(1) == 140 and Rules.bills_total_on(2) == 0 and Rules.bills_total_on(7) == 0)

	# --- 1. 段階の境目（累計は帳簿の fund から導く） ---
	var expected := {
		0: [-1, 150, 600], 149: [-1, 1, 451], 150: [0, 150, 450], 299: [0, 1, 301],
		300: [1, 300, 300], 599: [1, 1, 1], 600: [2, 0, 0],
	}
	for total in expected:
		var e: Array = expected[total]
		c.check("累計%d：段階%d・次の段階まで%d・最終段階まで%d" % [total, e[0], e[1], e[2]],
			RepairFund.stage_index(total) == e[0] and RepairFund.remaining_to_next(total) == e[1]
				and RepairFund.remaining_to_cap(total) == e[2])
	c.check("段階名：149は積み立て中・150は手書きの看板・300は棚と雨よけ・600は屋台を自分の名義に",
		RepairFund.stage_label(149) == "積み立て中" and RepairFund.stage_label(150) == "手書きの看板"
			and RepairFund.stage_label(300) == "棚と雨よけ" and RepairFund.stage_label(600) == "屋台を自分の名義に")
	c.check("累計0は段階の辞書が空", RepairFund.stage(0).is_empty() and RepairFund.stage(150)["id"] == "sign")

	# --- 2. 積む処理：所持金が減り、帳簿に fund が負額で1行。repair_paid が合計。複数回で加算 ---
	_at_close(3, 500)
	c.check("（前提）最初は累計0・fund の行なし", RepairFund.paid() == 0 and _funds().is_empty())
	c.check("100を積める", RepairFund.contribute(100))
	c.check("所持金が100減る", GameState.money == 400)
	var rows := _funds()
	c.check("帳簿に fund が負額で1行（日・フェーズ・項目つき）", rows.size() == 1 and rows[0]["amount"] == -100
		and rows[0]["day"] == 3 and rows[0]["phase"] == "CLOSE" and rows[0]["item"] == "repair_fund")
	c.check("Result.repair_paid が合計（100）で、paid() も同じ", Result.repair_paid(GameState.ledger) == 100 and RepairFund.paid() == 100)
	c.check("何度でも積める（25＋50）：累計175・行は3つ・所持金325",
		RepairFund.contribute(25) and RepairFund.contribute(50) and RepairFund.paid() == 175 and _funds().size() == 3
			and GameState.money == 325)
	c.check("段階は150を超えて手書きの看板", RepairFund.stage_label(RepairFund.paid()) == "手書きの看板")

	# --- 3. 安全上限（Q3）：使える現金 − 翌朝に必ず払う額 − 最小の仕込み額 ---
	_at_close(3, 244)
	c.check("上限＝244−運営費65−最小仕込み80＝99", RepairFund.safe_limit() == 99)
	c.check("上限を超える100は積めず、50は積める", not RepairFund.can_contribute(100) and RepairFund.can_contribute(50))
	_at_close(3, 245)
	c.check("上限ちょうど（100）は積める／1超えない", RepairFund.safe_limit() == 100 and RepairFund.contribute(100) and GameState.money == 145)
	c.check("積んだ後の上限は0（もう積めない）。所持金145＝翌朝の運営費65＋最小の仕込み80",
		RepairFund.safe_limit() == 0 and not RepairFund.contribute(25))
	_at_close(3, 144)
	c.check("所持金が145に満たなければ、どの額も積めない", RepairFund.safe_limit() == 0 and not RepairFund.can_contribute(25))
	# 確保額（今日まだ払っていない請求）は使える現金から引く
	_at_close(3, 400)
	Ledger.record("reserve", -90)
	c.check("確保額90があると使える現金310−145＝165が上限", Ledger.usable_cash() == 310 and RepairFund.safe_limit() == 165)
	# 翌日が徴収日：請求140が翌朝に必ず払う額に加わる（徴収日の前日）
	Rules._cache["bills"] = [ { "id": "rent", "amount": 90, "days": [4.0], "scene": "thug" },
		{ "id": "water", "amount": 50, "days": [4.0], "scene": "water_stall" } ]
	_at_close(3, 400)
	c.check("翌日（Day4）が徴収日なら、運営費65＋請求140＋最小仕込み80＝285を引く（400−285＝115）",
		RepairFund.safe_limit() == 115)
	c.check("請求の合計は日ごとに引く（Day3は0・Day4は140）。今日の請求は上限に関係しない", Rules.bills_total_on(3) == 0 and Rules.bills_total_on(4) == 140)
	Rules.set_campaign("week7")
	Rules.bills()
	# 最終日：翌日が無いので使える現金そのもの（運営費・仕込みの下限は不要）
	_at_close(GameState.FINAL_DAY, 300)
	c.check("最終日の上限は所持金そのもの（300）", RepairFund.safe_limit() == 300 and RepairFund.can_contribute(100))
	Ledger.record("reserve", -50)
	c.check("最終日でも確保額は引く（使える現金250）", RepairFund.safe_limit() == 250)
	# 上限いっぱいまで積んでも、翌朝の運営費が払え、翌日の最小の仕込みが買える
	for money in [145, 146, 200, 245, 260, 400, 1000]:
		_at_close(2, money)
		var guard := 0
		while guard < 100 and (RepairFund.contribute(100) or RepairFund.contribute(50) or RepairFund.contribute(25)):
			guard += 1
		c.check("所持金%dから積めるだけ積んでも：残り%dで運営費が払え、最小の仕込みも買える" % [money, GameState.money],
			GameState.money >= GameState.DAILY_OPERATING_COST + RepairFund.min_prep_price() or GameState.money == money)
		c.check("所持金%d：累計は最終段階（600）を超えない" % money, RepairFund.paid() <= 600)

	# --- 4. 拒否される場合：所持金・帳簿が変わらない ---
	_at_close(3, 1000)
	var ledger_size := GameState.ledger.size()
	for bad in [0, -25, 30, 24, 75, 200]:
		c.check("刻みに無い額 %d は積めない" % bad, not RepairFund.contribute(bad))
	c.check("拒否では所持金・帳簿は変わらない", GameState.money == 1000 and GameState.ledger.size() == ledger_size)
	for phase in [GameState.Phase.WAKE, GameState.Phase.PREP, GameState.Phase.OPEN, GameState.Phase.NEXT_DAY]:
		GameState.phase = phase
		c.check("CLOSE 以外（%s）では積めない" % GameState.Phase.keys()[phase], not RepairFund.contribute(100))
	c.check("CLOSE 以外では所持金・帳簿は変わらない", GameState.money == 1000 and GameState.ledger.size() == ledger_size)
	GameState.phase = GameState.Phase.CLOSE
	# 最終段階に届いた後
	GameState.ledger.append({ "day": 3, "phase": "CLOSE", "category": "fund", "amount": -600, "item": "", "count": 0,
		"unit_price": 0, "ref": "" })
	c.check("最終段階（600）に届いたら完了・それ以上は積めない", RepairFund.complete() and RepairFund.remaining_to_cap(RepairFund.paid()) == 0
		and not RepairFund.contribute(25) and GameState.money == 1000)
	# 最終段階までの残りより大きい額
	GameState.ledger.clear()
	GameState.ledger.append({ "day": 3, "phase": "CLOSE", "category": "fund", "amount": -550, "item": "", "count": 0,
		"unit_price": 0, "ref": "" })
	c.check("最終段階までの残り50：100は積めず、50は積める", not RepairFund.contribute(100) and RepairFund.contribute(50)
		and RepairFund.paid() == 600 and RepairFund.complete())

	# --- 5. 目標判定は「現金＋支払済み修繕額」：積んでも不利にならない ---
	_at_close(3, 700)
	var before := Result.summarize([], GameState.ledger, GameState.money)
	RepairFund.contribute(100)
	RepairFund.contribute(50)
	var after := Result.summarize([], GameState.ledger, GameState.money)
	c.check("積む前後で cash_plus_repair は変わらない（700）", before["cash_plus_repair"] == 700 and after["cash_plus_repair"] == 700
		and after["repair_paid"] == 150 and after["cash"] == 550)
	var goals := Rules.goals()
	var judge_before := Result.judge_goals(before, goals, Rules.final_day())
	var judge_after := Result.judge_goals(after, goals, Rules.final_day())
	c.check("judge_goals の結果は積んだだけでは変わらない", JSON.stringify(judge_before) == JSON.stringify(judge_after))

	# --- 6. 効果が無い：所持金と帳簿以外は不変（評判・需要・料金・在庫・DayPlan） ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.money = 600
	GameState.reputation = 55
	GameState.add_inventory("tofu", 4)
	GameState.today_plan = { "day": 3, "demand_center": 11, "slots": [], "mob_instances": {} }
	GameState.phase = GameState.Phase.CLOSE
	var others_before := _others()
	var price_before := GameState.PRICE_PER_SERVING
	RepairFund.contribute(100)
	RepairFund.contribute(100)
	c.check("積んでも 評判・需要・在庫・DayPlan・来店記録は不変で、料金も変わらない",
		_others() == others_before and GameState.PRICE_PER_SERVING == price_before and GameState.reputation == 55)

	# --- 7. 朝の保存：版6のまま・帳簿の fund が残る・同じ日の朝へ戻すと消える ---
	c.check("保存の版は6のまま（帳簿の1行なので上げない）", MorningSave.VERSION == 6)
	GameState.reset_for_new_game()
	GameState.day_count = 4
	GameState.money = 800
	GameState.phase = GameState.Phase.CLOSE
	RepairFund.contribute(100)
	var env := MorningSave.capture("")
	c.check("fund の行を持つ封筒は有効（検証は category を限定しない）", MorningSave.is_valid(env) and int(env["version"]) == 6)
	var funds_in_env := (env["state"]["ledger"] as Array).filter(func(e): return e["category"] == "fund")
	c.check("封筒の帳簿に fund が残る", funds_in_env.size() == 1 and funds_in_env[0]["amount"] == -100)
	GameState.reset_for_new_game()
	GameState.from_dict(env["state"])
	c.check("復元後も累計と所持金が残る（累計100・所持金700）", RepairFund.paid() == 100 and GameState.money == 700)
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.money = 900
	GameState.phase = GameState.Phase.CLOSE
	RepairFund.contribute(100)
	c.check("（前提）Day2の朝の記録があり、CLOSEで積んだ", GameState.morning_snapshots.has(2) and RepairFund.paid() == 100)
	c.check("同じ日（Day2）の朝へ戻すと、その日に積んだ分は消える（累計0）", panel.retry_from_morning(2) and RepairFund.paid() == 0
		and GameState.day_count == 2)
	panel.free()

	# --- 8. 機能オフ・不正な設定 ---
	Rules._cache.erase("repair_fund")
	_at_close(3, 1000)
	c.check("repair_fund が無い設定は機能オフ：積めず、所持金・帳簿は不変",
		not RepairFund.enabled() and not RepairFund.contribute(25) and GameState.money == 1000 and _funds().is_empty()
			and not RepairFund.complete())
	Rules._cache["repair_fund"] = {}
	c.check("空の repair_fund も機能オフ", not RepairFund.enabled())
	Rules._cache["repair_fund"] = { "steps": [25], "stages": [] }
	c.check("段階が無ければ機能オフ", not RepairFund.enabled())
	Rules._cache["repair_fund"] = { "steps": [], "stages": [ { "id": "a", "total": 100, "label": "A" } ] }
	c.check("刻みが無ければ機能オフ", not RepairFund.enabled())
	Rules._cache["repair_fund"] = "x"
	c.check("辞書でない repair_fund も機能オフ（クラッシュしない）", not RepairFund.enabled())
	Rules._cache["repair_fund"] = {
		"steps": [50, 0, -25, 25, 25, "x", 12.5, 100.0],
		"in_progress_label": "",
		"stages": [ { "id": "c", "total": 300, "label": "C" }, { "id": "a", "total": 100, "label": "A" },
			{ "id": "dup", "total": 100, "label": "重複" }, { "id": "bad", "total": 0, "label": "B" },
			{ "id": "bad2", "total": 200, "label": "" }, { "id": "bad3", "total": -5, "label": "E" },
			{ "id": "bad4", "label": "F" }, 7 ] }
	c.check("不正な刻み（0・負・文字列・小数・重複）は無視し、昇順に整える", RepairFund.steps() == [25, 50, 100])
	c.check("不正な段階（total が不正・label が空・重複・辞書でない）は無視し、total の昇順に整える",
		RepairFund.stages().map(func(s): return s["id"]) == ["a", "c"])
	c.check("in_progress_label が空なら既定の呼び名", RepairFund.in_progress_label() == "積み立て中")
	c.check("整えた設定で機能オン・段階の判定ができる", RepairFund.enabled() and RepairFund.stage_label(250) == "A"
		and RepairFund.remaining_to_cap(250) == 50)
	Rules.set_campaign("week7")
	Rules.bills()
	c.check("後始末：現行の設定へ戻っている", RepairFund.steps() == [25, 50, 100] and RepairFund.stages().size() == 3)

	GameState.reset_for_new_game()
	return c.finish()
