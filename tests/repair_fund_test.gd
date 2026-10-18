extends RefCounted
## 修繕基金（フェーズ4・手順4-9④-①。DESIGN.md 10.7のMVP版）の検証。
## 修繕の対象ごとの累計と修繕済み（帳簿の ref＝対象id）、1晩の上限（最終日にも掛かる）、安全上限（新：毎日、
## 全客に味1＋具2の椀を出せるだけ残す）、拒否される場合、目標判定（現金＋修繕額）が不利にならないこと、
## 効果が無いこと、朝の保存（版6のまま・再挑戦で戻る）、機能オフ・不正な設定。
## 初期値（week7.json）：刻み10／30、1晩の上限30、看板150・棚200・雨よけ200・名義600（名義は他の3つが
## 修繕済みになるまで積めない）。値段は最小の刻みの倍数（刻みだけで値段ぴったりに届く）。
## 初期値のもとでの見込み：評判55・今日の計画の需要の中心14 → 翌日の見込み杯数14 → 仕込み140・材料費
## 14×25＝350・運営費65 → 翌日の確保額555。


func _at_close(day: int, money: int, reputation: int = 55) -> void:
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	GameState.reputation = reputation
	GameState.phase = GameState.Phase.CLOSE


func _funds() -> Array:
	return GameState.ledger.filter(func(e): return e["category"] == "fund")


## 帳簿に fund を直接足す（過去の夜の積み立てを作る。ref が空・未知の記帳も作れる）。
func _add_fund(day: int, amount: int, ref: String) -> void:
	GameState.ledger.append({ "day": day, "phase": "CLOSE", "category": "fund", "amount": -amount,
		"item": "repair_fund", "count": 0, "unit_price": 0, "ref": ref })


## 所持金と帳簿以外の状態の写し（基金は効果を持たない）。
func _others() -> String:
	var d := GameState.to_dict()
	d.erase("money")
	d.erase("ledger")
	return JSON.stringify([d, GameState.phase])


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	# 運営費に連動する値は定数から計算する（運営費を変えても境目の検査が追従する）。
	# r14＝見込み14杯の翌日の確保額＝運営費＋仕込み140＋材料費14×25、r11＝見込み11杯＝運営費＋仕込み110＋材料費11×25。
	var op: int = GameState.DAILY_OPERATING_COST
	var r14: int = op + 140 + 350
	var r11: int = op + 110 + 275
	Rules.set_campaign("week7")
	Rules.bills()
	GameState.reset_for_new_game()

	# --- 0. 設定の読み出しと前提 ---
	c.check("機能オン：刻み10／30・1晩の上限30", RepairFund.enabled() and RepairFund.steps() == [10, 30] and RepairFund.nightly_max() == 30)
	var ts := RepairFund.targets()
	c.check("対象は 看板150・棚200・雨よけ200・名義600（データの並び順・label は仮）",
		ts.map(func(x): return x["id"]) == ["sign", "shelf", "awning", "owner"]
			and ts.map(func(x): return x["price"]) == [150, 200, 200, 600]
			and ts.map(func(x): return x["label"]) == ["手書きの看板", "棚", "雨よけ", "屋台を自分の名義に"])
	c.check("名義は看板・棚・雨よけが修繕済みになるまで積めない（requires）", ts[3]["requires"] == ["sign", "shelf", "awning"]
		and ts[0]["requires"].is_empty())
	var smallest: int = RepairFund.steps()[0]
	c.check("前提：対象の値段は最小の刻み（%d）の倍数（刻みだけで値段ぴったりに届く）" % smallest,
		ts.all(func(x): return int(x["price"]) % smallest == 0))
	c.check("対象の note は仮（（仮））のままデータに残る", ts.all(func(x): return x["note"] == "（仮）"))
	c.check("1杯の材料費の目安は市場のデータから求める（味の素材の単価の中央値5＋具の素材の中央値10×2＝25）",
		RepairFund.cup_material_cost() == 25)
	Rules._cache["repair_fund"]["cup_material_cost"] = 19
	c.check("data に cup_material_cost があればそれを優先する", RepairFund.cup_material_cost() == 19)
	Rules.set_campaign("week7")
	Rules.bills()
	c.check("Rules.bills_total_on：徴収日（Day1）は140、他の日は0", Rules.bills_total_on(1) == 140 and Rules.bills_total_on(2) == 0)

	# --- 1. 対象ごとの累計と修繕済み（帳簿の ref） ---
	_at_close(3, 1000)
	c.check("（前提）最初は累計0・進捗は全部0（名義は未解放）", RepairFund.paid() == 0 and _funds().is_empty()
		and RepairFund.progress_text() == "手書きの看板 0/150／棚 0/200／雨よけ 0/200／屋台を自分の名義に 0/600（未解放）",
		RepairFund.progress_text())
	c.check("既定の積む先は最初の未修繕の対象（看板）", RepairFund.first_open_target() == "sign")
	c.check("看板に30を積める", RepairFund.contribute("sign", 30) and GameState.money == 970)
	var rows := _funds()
	c.check("帳簿に fund が負額で1行：ref＝対象id・項目 repair_fund・日・フェーズ",
		rows.size() == 1 and rows[0]["amount"] == -30 and rows[0]["ref"] == "sign" and rows[0]["item"] == "repair_fund"
			and rows[0]["day"] == 3 and rows[0]["phase"] == "CLOSE")
	c.check("対象ごとの累計は ref が一致する記帳の合計（看板30・棚0）。全体は Result.repair_paid と同じ",
		RepairFund.target_paid("sign") == 30 and RepairFund.target_paid("shelf") == 0 and RepairFund.paid() == 30
			and Result.repair_paid(GameState.ledger) == 30 and RepairFund.remaining("sign") == 120)
	GameState.day_count = 4   # 同じ夜は1晩の上限30に達しているので、次の夜に積む
	c.check("棚に10を積むと、看板とは別に数える", RepairFund.contribute("shelf", 10) and RepairFund.target_paid("shelf") == 10
		and RepairFund.target_paid("sign") == 30 and RepairFund.paid() == 40)
	# 看板を修繕済みにする（日をまたいで30ずつ）
	_at_close(3, 1000)
	var before_ids := RepairFund.repaired_ids()
	for day in [3, 4, 5, 6]:
		GameState.day_count = day
		RepairFund.contribute("sign", 30)
	GameState.day_count = 7   # 次の夜（日が替わると1晩の上限が戻る）
	c.check("4夜で120（残り30）。あと1夜で値段ぴったり", RepairFund.target_paid("sign") == 120 and RepairFund.remaining("sign") == 30)
	c.check("値段ちょうど（150）に届く＝修繕済み。進捗の文に「修繕済み」", RepairFund.contribute("sign", 30) and RepairFund.is_repaired("sign")
		and RepairFund.repaired_ids() == ["sign"] and RepairFund.progress_text().begins_with("手書きの看板 150/150 修繕済み／"))
	c.check("修繕できた瞬間の一行（label を使った固定の言い回し）",
		RepairFund.repaired_message(before_ids, RepairFund.repaired_ids()) == "修繕できた：手書きの看板"
			and RepairFund.repaired_message(RepairFund.repaired_ids(), RepairFund.repaired_ids()) == "")
	c.check("修繕済みの対象にはもう積めない・既定の積む先は次の対象（棚）へ移る",
		not RepairFund.can_contribute("sign", 10) and RepairFund.first_open_target() == "shelf")
	# 値段を超える額
	_at_close(3, 1000)
	_add_fund(1, 140, "sign")
	c.check("残り10：30は積めず（値段を超える）、10は積める",
		RepairFund.remaining("sign") == 10 and not RepairFund.contribute("sign", 30) and RepairFund.contribute("sign", 10)
			and RepairFund.is_repaired("sign") and RepairFund.target_paid("sign") == 150)

	# --- 2. 1晩の上限（30）：当日の合計。日が替われば戻る。最終日にも掛かる ---
	_at_close(3, 1000)
	c.check("30を積むと今夜の上限いっぱい（残り0）", RepairFund.contribute("sign", 30) and RepairFund.paid_tonight() == 30
		and RepairFund.nightly_remaining() == 0)
	c.check("同じ夜はもう積めない（10も30も）。所持金・帳簿は不変",
		not RepairFund.contribute("sign", 10) and not RepairFund.contribute("shelf", 30) and GameState.money == 970 and _funds().size() == 1)
	c.check("対象を変えても1晩の上限は合算（別の対象に10も不可）", not RepairFund.contribute("awning", 10))
	GameState.day_count = 4
	c.check("日が替われば上限は戻る（今夜0／30）", RepairFund.paid_tonight() == 0 and RepairFund.nightly_remaining() == 30
		and RepairFund.contribute("sign", 10) and RepairFund.paid_tonight() == 10)
	c.check("10＋10＋10で30（3回）、4回目は不可",
		RepairFund.contribute("shelf", 10) and RepairFund.contribute("awning", 10) and not RepairFund.contribute("sign", 10)
			and RepairFund.paid_tonight() == 30)
	_at_close(GameState.FINAL_DAY, 1000)
	c.check("最終日にも1晩の上限が掛かる（最終日の一括払いはできない）：30は積めるが次の10は不可・100を超える額もない",
		RepairFund.contribute("sign", 30) and not RepairFund.contribute("sign", 10) and RepairFund.paid() == 30)
	_at_close(GameState.FINAL_DAY, 5000)
	c.check("最終日の最大は30（所持金が十分あっても）", RepairFund.max_contribution("sign") == 30)

	# --- 3. 安全上限（新）：使える現金 − 翌日の確保額（運営費・翌日の請求・翌日の仕込み・翌日の材料費） ---
	c.check("見込み杯数：評判から引く総需要の中心（7／9／11／14／17）と日の固定需要",
		RepairFund.demand_center(0, 2) == 7 and RepairFund.demand_center(20, 2) == 9 and RepairFund.demand_center(45, 2) == 11
			and RepairFund.demand_center(60, 2) == 14 and RepairFund.demand_center(71, 2) == 17
			and RepairFund.demand_center(71, 1) == 9)
	c.check("仕込みは見込み杯数に足りる最小の段階（9→110／11→110／12→140／20→140＝最大の段階）",
		RepairFund.prep_price_for(8) == 80 and RepairFund.prep_price_for(9) == 110 and RepairFund.prep_price_for(11) == 110
			and RepairFund.prep_price_for(12) == 140 and RepairFund.prep_price_for(20) == 140)
	_at_close(3, 1000, 55)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	var reserve := RepairFund.next_day_reserve()
	c.check("翌日の確保額の内訳：運営費＋請求0＋仕込み140＋材料費14×25＝350（見込み14杯＝今日の計画14）",
		reserve["operating"] == op and reserve["bills"] == 0 and reserve["prep"] == 140 and reserve["materials"] == 350
			and reserve["expected_cups"] == 14 and reserve["total"] == r14, str(reserve))
	GameState.today_plan = { "day": 3, "demand_center": 9, "slots": [], "mob_instances": {} }
	c.check("評判から引く値（評判55→11）のほうが大きければそちら（11杯：運営費＋仕込み110＋材料費275）",
		RepairFund.expected_cups_tomorrow() == 11 and RepairFund.next_day_reserve()["total"] == r11)
	# 今日の計画の需要の中心が無い場合（再挑戦直後など）：評判から引く値だけを使う（安全側）
	for plan in [{}, { "day": 3, "demand_center": -1, "slots": [] }, { "day": 2, "demand_center": 17, "slots": [] },
			{ "slots": [] }, { "day": 3, "demand_center": "x" }]:
		GameState.today_plan = plan
		c.check("今日の計画に有効な需要の中心が無い（%s）：評判から引く値だけ（11杯・確保額は運営費＋385）" % str(plan),
			RepairFund.expected_cups_tomorrow() == 11 and RepairFund.next_day_reserve()["total"] == r11)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }

	# 安全上限が1晩の上限（30）より小さくなる夜：その額を超えると拒否、ちょうどなら積める
	_at_close(3, r14 + 20, 55)   # 使える現金（確保額+20） − 確保額 ＝ 上限20（< 1晩の上限30）
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	c.check("安全上限20：1晩の上限（30）より小さいので、積める最大は20", RepairFund.safe_limit() == 20
		and RepairFund.nightly_remaining() == 30 and RepairFund.max_contribution("sign") == 20)
	c.check("上限を超える30は拒否・所持金と帳簿は不変", not RepairFund.contribute("sign", 30) and GameState.money == r14 + 20 and _funds().is_empty())
	c.check("10は積める。積んだ後の上限は10", RepairFund.contribute("sign", 10) and RepairFund.safe_limit() == 10 and GameState.money == r14 + 10)
	c.check("ちょうど（残り10）の10は積める。その後の上限は0で、もう積めない",
		RepairFund.contribute("shelf", 10) and RepairFund.safe_limit() == 0 and not RepairFund.contribute("sign", 10)
			and GameState.money == r14)
	c.check("積んだ後の所持金は翌日の確保額ちょうど＝翌朝の運営費も仕込みも材料費も賄える",
		GameState.money == int(RepairFund.next_day_reserve()["total"]))
	_at_close(3, r14 + 29, 55)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	c.check("上限29：30は拒否・10は積める（刻みとの兼ね合い）", RepairFund.safe_limit() == 29 and not RepairFund.can_contribute("sign", 30)
		and RepairFund.can_contribute("sign", 10))
	_at_close(3, r14 + 30, 55)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	c.check("上限30ちょうど：30は積める（上限＝1晩の上限）", RepairFund.safe_limit() == 30 and RepairFund.contribute("sign", 30))
	_at_close(3, r14 - 1, 55)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	c.check("確保額に満たない所持金（確保額−1）では、どの額も積めない", RepairFund.safe_limit() == 0 and not RepairFund.can_contribute("sign", 10))
	# 確保額（今日まだ払っていない請求）は使える現金から引く
	_at_close(3, r14 + 145, 55)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	Ledger.record("reserve", -140)
	c.check("今日の確保額140があると、使える現金（確保額+5）−確保額＝5が上限", Ledger.usable_cash() == r14 + 5 and RepairFund.safe_limit() == 5
		and not RepairFund.can_contribute("sign", 10))
	# 翌日が徴収日：請求140が確保額に加わる
	Rules._cache["bills"] = [ { "id": "rent", "amount": 90, "days": [4.0], "scene": "thug" },
		{ "id": "water", "amount": 50, "days": [4.0], "scene": "water_stall" } ]
	_at_close(3, r14 + 145, 55)
	GameState.today_plan = { "day": 3, "demand_center": 14, "slots": [], "mob_instances": {} }
	c.check("翌日（Day4）が徴収日なら確保額に請求140が加わる（確保額＋140。上限は所持金−それ＝5）",
		RepairFund.next_day_reserve()["bills"] == 140 and RepairFund.next_day_reserve()["total"] == r14 + 140 and RepairFund.safe_limit() == 5)
	Rules.set_campaign("week7")
	Rules.bills()
	# 最終日：翌日が無いので確保額は0（使える現金そのもの。1晩の上限は別に掛かる）
	_at_close(GameState.FINAL_DAY, 300, 55)
	c.check("最終日の確保額は0・安全上限は使える現金そのもの（300）。積める最大は1晩の上限30",
		RepairFund.next_day_reserve()["total"] == 0 and RepairFund.safe_limit() == 300 and RepairFund.max_contribution("sign") == 30)
	Ledger.record("reserve", -280)
	c.check("最終日でも今日の確保額は使える現金から引く（使える現金20＝上限20）", RepairFund.safe_limit() == 20
		and RepairFund.max_contribution("sign") == 20)

	# 毎晩上限まで積む周の模擬：どの所持金から始めても、積んだ後に翌朝の運営費・仕込み・材料費が賄える
	for money in [300, 450, r14, r14 + 5, r14 + 25, 600, 700, 900]:
		_at_close(2, money, 55)
		GameState.today_plan = { "day": 2, "demand_center": 14, "slots": [], "mob_instances": {} }
		var need: int = int(RepairFund.next_day_reserve()["total"])
		var guard := 0
		while guard < 100 and (RepairFund.contribute("sign", 30) or RepairFund.contribute("sign", 10)):
			guard += 1
		c.check("所持金%dから積めるだけ積んでも、残り%dは翌日の確保額%d以上（積んだ額%d）" % [money, GameState.money, need, RepairFund.paid()],
			GameState.money >= need or GameState.money == money)
		c.check("所持金%d：1晩の上限（30）を超えて積まない" % money, RepairFund.paid_tonight() <= 30)

	# --- 3b. 実際の流れ：積めるだけ積んで、CLOSE → NEXT_DAY → WAKE（運営費を払う）へ進める（ゲームオーバーにならない） ---
	for money in [r14 + 20, r14 + 30, 700]:
		GameState.reset_for_new_game()
		GameState.day_count = 2
		var panel = load("res://scenes/debug_panel.tscn").instantiate()
		t.root.add_child(panel)
		GameState.ledger.clear()
		GameState.money = money
		GameState.reputation = 55
		GameState.today_plan = { "day": 2, "demand_center": 14, "slots": [], "mob_instances": {} }
		panel.flow.force_phase(GameState.Phase.CLOSE)
		var g2 := 0
		while panel.flow.runner.status != EventRunner.Status.DONE and g2 < 100:
			g2 += 1
			panel._on_next_event_pressed()
		var need2: int = int(RepairFund.next_day_reserve()["total"])
		var guard2 := 0
		while guard2 < 100 and (RepairFund.contribute("sign", 30) or RepairFund.contribute("sign", 10)):
			guard2 += 1
		panel.flow.advance_phase()   # CLOSE → NEXT_DAY
		panel.flow.advance_phase()   # NEXT_DAY → WAKE（運営費を払う）
		c.check("所持金%d：積んだ後も翌朝（Day3）のWAKEへ進め、運営費が払えてゲームオーバーにならない（WAKE後%d）" % [money, GameState.money],
			GameState.phase == GameState.Phase.WAKE and GameState.day_count == 3 and GameState.money >= need2 - op)
		panel.free()

	# --- 4. 拒否される場合：所持金・帳簿が変わらない ---
	_at_close(3, 1000)
	var ledger_size := GameState.ledger.size()
	for bad in [0, -10, 5, 20, 25, 60, 100]:
		c.check("刻みに無い額 %d は積めない" % bad, not RepairFund.contribute("sign", bad))
	c.check("存在しない対象・空の対象は積めない", not RepairFund.contribute("nothing", 10) and not RepairFund.contribute("", 10))
	c.check("名義（owner）は他の3つが修繕済みになるまで未解放＝積めない", not RepairFund.unlocked("owner")
		and not RepairFund.contribute("owner", 30) and RepairFund.max_contribution("owner") == 0)
	c.check("拒否では所持金・帳簿は不変", GameState.money == 1000 and GameState.ledger.size() == ledger_size)
	for phase in [GameState.Phase.WAKE, GameState.Phase.PREP, GameState.Phase.OPEN, GameState.Phase.NEXT_DAY]:
		GameState.phase = phase
		c.check("CLOSE 以外（%s）では積めない" % GameState.Phase.keys()[phase], not RepairFund.contribute("sign", 10))
	c.check("CLOSE 以外では所持金・帳簿は不変", GameState.money == 1000 and GameState.ledger.size() == ledger_size)
	GameState.phase = GameState.Phase.CLOSE
	# 名義の解放：3つが修繕済みになったら積める
	_add_fund(1, 150, "sign")
	_add_fund(1, 200, "shelf")
	c.check("2つ修繕済みではまだ未解放", RepairFund.is_repaired("sign") and RepairFund.is_repaired("shelf") and not RepairFund.unlocked("owner"))
	_add_fund(2, 200, "awning")
	c.check("3つが修繕済みになると名義が解放され、積める", RepairFund.unlocked("owner") and RepairFund.first_open_target() == "owner"
		and RepairFund.contribute("owner", 30) and RepairFund.target_paid("owner") == 30)
	c.check("進捗の文：名義は解放後は（未解放）が外れる", RepairFund.progress_text().ends_with("屋台を自分の名義に 30/600"))
	# 全部修繕済み＝完了
	_add_fund(3, 570, "owner")
	c.check("全対象が修繕済みなら完了・積めない", RepairFund.complete() and RepairFund.first_open_target() == ""
		and not RepairFund.contribute("owner", 10) and not RepairFund.contribute("sign", 10))

	# --- 5. ref が空・未知の記帳（4-9①②の記帳・開発中の記帳）：合計には数え、どの対象にも割り当てない ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.money = 1000
	GameState.phase = GameState.Phase.CLOSE
	_add_fund(1, 100, "")
	_add_fund(2, 50, "no_such_target")
	c.check("ref が空・未知の記帳は合計（repair_paid）には数える（150）が、どの対象にも割り当てない（全対象0）",
		RepairFund.paid() == 150 and Result.repair_paid(GameState.ledger) == 150 and RepairFund.unassigned_paid() == 150
			and RepairFund.target_paid("sign") == 0 and RepairFund.remaining("sign") == 150 and RepairFund.repaired_ids().is_empty())
	c.check("そのうえでも対象へ積める（合計は加算される）", RepairFund.contribute("sign", 30) and RepairFund.paid() == 180
		and RepairFund.target_paid("sign") == 30 and RepairFund.unassigned_paid() == 150)
	var env_legacy := MorningSave.capture("")
	c.check("ref が空の記帳を持つ封筒も有効で読める", MorningSave.is_valid(env_legacy))

	# --- 6. 目標判定は「現金＋支払済み修繕額」：積んでも不利にならない ---
	_at_close(3, 700)
	var before := Result.summarize([], GameState.ledger, GameState.money)
	RepairFund.contribute("sign", 30)
	GameState.day_count = 4
	RepairFund.contribute("shelf", 30)
	var after := Result.summarize([], GameState.ledger, GameState.money)
	c.check("積む前後で cash_plus_repair は変わらない（700）", before["cash_plus_repair"] == 700 and after["cash_plus_repair"] == 700
		and after["repair_paid"] == 60 and after["cash"] == 640)
	var goals := Rules.goals()
	c.check("judge_goals の結果は積んだだけでは変わらない",
		JSON.stringify(Result.judge_goals(before, goals, Rules.final_day())) == JSON.stringify(Result.judge_goals(after, goals, Rules.final_day())))

	# --- 7. 効果が無い：所持金と帳簿以外は不変（評判・需要・料金・在庫・DayPlan） ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.money = 1000
	GameState.reputation = 55
	GameState.add_inventory("tofu", 4)
	GameState.today_plan = { "day": 3, "demand_center": 11, "slots": [], "mob_instances": {} }
	GameState.phase = GameState.Phase.CLOSE
	var others_before := _others()
	var price_before := GameState.PRICE_PER_SERVING
	RepairFund.contribute("sign", 30)
	c.check("積んでも 評判・需要・在庫・DayPlan・来店記録は不変で、料金も変わらない",
		_others() == others_before and GameState.PRICE_PER_SERVING == price_before and GameState.reputation == 55)

	# --- 8. 朝の保存：版6のまま・ref つきの fund が残る・同じ日の朝へ戻すと消える ---
	c.check("保存の版は6のまま（帳簿の1行で、MorningSave の検証は category・ref を限定しない）", MorningSave.VERSION == 6)
	GameState.reset_for_new_game()
	GameState.day_count = 4
	GameState.money = 1000
	GameState.phase = GameState.Phase.CLOSE
	RepairFund.contribute("shelf", 30)
	var env := MorningSave.capture("")
	c.check("ref つきの fund を持つ封筒は有効", MorningSave.is_valid(env) and int(env["version"]) == 6)
	var funds_in_env := (env["state"]["ledger"] as Array).filter(func(e): return e["category"] == "fund")
	c.check("封筒の帳簿に fund が ref つきで残る", funds_in_env.size() == 1 and funds_in_env[0]["amount"] == -30 and funds_in_env[0]["ref"] == "shelf")
	GameState.reset_for_new_game()
	GameState.from_dict(env["state"])
	c.check("復元後も対象ごとの累計が残る（棚30・合計30）", RepairFund.target_paid("shelf") == 30 and RepairFund.paid() == 30 and GameState.money == 970)
	var saved_path := MorningSave.save_path
	MorningSave.save_path = "user://repair_fund_test.dat"
	MorningSave.delete_file()
	c.check("ファイルへ書いて読んでも ref が残る", MorningSave.write_file(env)
		and (MorningSave.read_file()["state"]["ledger"] as Array).filter(func(e): return e["ref"] == "shelf").size() == 1)
	MorningSave.delete_file()
	MorningSave.save_path = saved_path
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel8 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel8)
	GameState.money = 900
	GameState.phase = GameState.Phase.CLOSE
	RepairFund.contribute("sign", 30)
	c.check("（前提）Day2の朝の記録があり、CLOSEで積んだ", GameState.morning_snapshots.has(2) and RepairFund.paid() == 30)
	c.check("同じ日（Day2）の朝へ戻すと、その日に積んだ分は消える（累計0・看板0）", panel8.retry_from_morning(2)
		and RepairFund.paid() == 0 and RepairFund.target_paid("sign") == 0 and GameState.day_count == 2)
	panel8.free()

	# --- 9. 機能オフ・不正な設定 ---
	var fund_config = Rules._cache["repair_fund"]
	Rules._cache.erase("repair_fund")
	_at_close(3, 1000)
	c.check("repair_fund が無い設定は機能オフ：積めず、所持金・帳簿は不変",
		not RepairFund.enabled() and not RepairFund.contribute("sign", 10) and GameState.money == 1000 and _funds().is_empty()
			and not RepairFund.complete() and RepairFund.first_open_target() == "" and RepairFund.progress_text() == "")
	for broken in [{}, "x", { "steps": [10], "nightly_max": 30, "targets": [] },
			{ "steps": [], "nightly_max": 30, "targets": [ { "id": "a", "label": "A", "price": 100 } ] },
			{ "steps": [10], "nightly_max": 0, "targets": [ { "id": "a", "label": "A", "price": 100 } ] },
			{ "steps": [10], "targets": [ { "id": "a", "label": "A", "price": 100 } ] },
			{ "steps": [10], "nightly_max": -5, "targets": [ { "id": "a", "label": "A", "price": 100 } ] }]:
		Rules._cache["repair_fund"] = broken
		c.check("機能オフになる設定（%s）" % str(broken).left(40), not RepairFund.enabled())
	Rules._cache["repair_fund"] = {
		"steps": [30, 0, -10, 10, 10, "x", 12.5, 30.0], "nightly_max": 30.0,
		"targets": [ { "id": "b", "label": "B", "price": 100 }, { "id": "a", "label": "A", "price": 50, "requires": ["b", "zzz", "a"] },
			{ "id": "b", "label": "重複", "price": 10 }, { "id": "", "label": "空id", "price": 10 },
			{ "id": "c", "label": "", "price": 10 }, { "id": "d", "label": "D", "price": 0 }, { "id": "e", "label": "E" },
			{ "id": "f", "label": "F", "price": -5 }, 7 ] }
	c.check("不正な刻み（0・負・文字列・小数・重複）は無視し、昇順に整える", RepairFund.steps() == [10, 30] and RepairFund.nightly_max() == 30)
	c.check("不正な対象（id が空・重複、label が空、price が不正、辞書でない）は無視する", RepairFund.targets().map(func(x): return x["id"]) == ["b", "a"])
	c.check("requires は存在する他の対象だけ残す（未知・自分自身は除く）", RepairFund.target("a")["requires"] == ["b"])
	c.check("整えた設定で機能オン・未解放の判定ができる", RepairFund.enabled() and not RepairFund.unlocked("a") and RepairFund.unlocked("b")
		and RepairFund.first_open_target() == "b")
	Rules._cache["repair_fund"] = fund_config
	Rules.set_campaign("week7")
	Rules.bills()
	c.check("後始末：現行の設定へ戻っている", RepairFund.steps() == [10, 30] and RepairFund.targets().size() == 4)

	GameState.reset_for_new_game()
	return c.finish()
