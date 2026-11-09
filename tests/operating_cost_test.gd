extends RefCounted
## 日々の運営費（水と炭）の支払いのタイミング（UI準備D・D-4）。朝は払えるかだけを見て、支払い予定として確保する。
## 引くのは市場を出るとき（「水を汲み、炭を買った（−¥75）」）。市場を通らずに開店へ進むときは開店に入るとき。
## 払えないときのゲームオーバーの判定は今までどおり朝。徴収日（Day1）の場所代・水道代のタイミングは変えない
## （水道代＝市場を出るとき、場所代＝開店中のチンピラの来店）。「使える」の上限まで買っても、市場を出るときの支払いは必ず通る。


func _to_market(s: PlaySession) -> void:
	s.flow.advance_phase()   # WAKE→PREP
	var guard := 0
	while not s.is_in_prep_tier() and guard < 60:
		guard += 1
		s.next_event()
	s.choose_prep_tier("small")
	guard = 0
	while not s.is_in_market() and guard < 60:
		guard += 1
		s.next_event()


func _kit_amounts() -> Array:
	var out: Array = []
	for e in GameState.ledger:
		if str(e["category"]) == "kit":
			out.append([str(e["category"]), int(e["amount"]), str(e["phase"])])
	return out


func _category_amounts(from_index: int) -> Array:
	var out: Array = []
	for i in range(from_index, GameState.ledger.size()):
		var e: Dictionary = GameState.ledger[i]
		if str(e["category"]) in ["daily_cost", "water", "rent"]:
			out.append([str(e["category"]), int(e["amount"]), str(e["phase"])])
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var daily: int = GameState.DAILY_OPERATING_COST

	# --- 1. 朝：払えるかだけを見る。運営費は支払い予定として確保（まだ引かない） ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var s := PlaySession.new()
	t.root.add_child(s)
	s.start()
	c.check("朝（WAKE）：残金は引かれない（%d）" % GameState.INITIAL_MONEY, GameState.money == GameState.INITIAL_MONEY)
	var b := s.budget()
	c.check("支払い予定（reserved）に運営費が入る・使える＝残金−支払い予定・operating は運営費の分",
		int(b["reserved"]) == daily and int(b["usable"]) == GameState.INITIAL_MONEY - daily and int(b["operating"]) == daily and s.operating_cost_pending() == daily, str(b))
	c.check("朝は運営費の支出を記帳しない（払った額は0）", s.morning_cost() == 0 and not Ledger.spend_by_category_today().has("daily_cost"))
	var wake_texts: Array = []
	for ev in s.flow.runner.events:
		wake_texts.append(str(ev.get("text", "")))
	c.check("朝の語り：「炭代¥40・水代¥35は、市場を出るときに払う。」（中身U2：運営費を炭代と水代に分けて見せる）", wake_texts.has("炭代¥40・水代¥35は、市場を出るときに払う。"), str(wake_texts))

	# --- 2. 市場を出るときに引く ---
	_to_market(s)
	var money_before := GameState.money
	var ledger_before := GameState.ledger.size()
	c.check("市場の中では、まだ引かれていない", s.operating_cost_pending() == daily and GameState.money == money_before)
	c.check("exit_market() は true", s.exit_market())
	c.check("市場を出るとき：運営費を引く（残金−%d・支払い予定は0・使える＝残金）" % daily,
		GameState.money == money_before - daily and s.operating_cost_pending() == 0 and int(s.budget()["reserved"]) == 0
			and s.budget()["usable"] == GameState.money, str(s.budget()))
	c.check("帳簿：daily_cost −%d（PREP）。1日の支出の合計は今までと同じ" % daily, _category_amounts(ledger_before) == [["daily_cost", -daily, "PREP"]]
		and int(Ledger.spend_by_category_today()["daily_cost"]) == daily and s.morning_cost() == daily, str(_category_amounts(ledger_before)))
	var money_after := GameState.money
	c.check("市場を出る操作をもう一度しても、二重に引かない", s.exit_market() and GameState.money == money_after)
	var next_text := str(s.current_line().get("text", ""))
	c.check("市場を出たあとの語り：「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」（中身U2）", next_text == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。", next_text)
	s.free()

	# --- 3. 払えないときは今までどおり朝のゲームオーバー（所持金は動かない） ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.money = daily - 1
	var poor := PlaySession.new()
	t.root.add_child(poor)
	poor.start()
	c.check("残金が運営費に足りない朝：朝（市場の前）にゲームオーバー・所持金はそのまま・詰んだ支払いは運営費",
		GameState.phase == GameState.Phase.GAME_OVER and GameState.money == daily - 1
			and str(poor.game_over_info()["kind"]) == "daily_cost" and int(poor.game_over_info()["amount"]) == daily
			and int(poor.game_over_info()["phase"]) == GameState.Phase.WAKE, str(poor.game_over_info()))
	poor.free()

	# --- 4. 「使える」の上限まで買っても、市場を出るときの支払いは必ず通る ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.money = 500
	var s4 := PlaySession.new()
	t.root.add_child(s4)
	s4.start()
	_to_market(s4)
	var cap_ok := true
	var bought := 0
	var guard := 0
	var shops := ["meat_wholesale", "produce", "dry_goods", "tofu_noodles", "seafood", "scraps"]
	var progress := true
	while progress and guard < 400:
		guard += 1
		progress = false
		for shop in shops:
			for good in PlaySession.shop_goods(shop):
				var price := int(good["price"])
				var limit_before := s4.purchase_limit()
				var money_then := GameState.money
				s4.buy_item(shop, str(good["id"]))
				if GameState.money != money_then:
					bought += 1
					progress = true
					cap_ok = cap_ok and price <= limit_before   # 使える現金を超える額は買えていない
				else:
					cap_ok = cap_ok and price > limit_before    # 買えなかったのは、使える現金を超えるとき
	c.check("使える現金を超える購入は1つも通らず、超えないものは買えた（%d回買った）" % bought, cap_ok and bought > 0)
	c.check("使える現金を使い切った：残金は運営費ぶん（以上）残っている・使える0以上", GameState.money >= daily and s4.purchase_limit() >= 0 and s4.purchase_limit() < 12,
		"%d / %d" % [GameState.money, s4.purchase_limit()])
	var money_cap := GameState.money
	c.check("そのまま市場を出る：運営費の支払いが通る（ゲームオーバーにならない・残金は運営費ぶん減る）",
		s4.exit_market() and GameState.phase == GameState.Phase.PREP and GameState.money == money_cap - daily and GameState.money >= 0, str(GameState.money))
	s4.free()

	# --- 5. 徴収日（Day1）：水道代は朝の昼市場の会話（梁伯の場面。中身U1）、運営費は市場を出るとき。場所代は開店中（変えない） ---
	GameState.reset_for_new_game()
	var s5 := PlaySession.new()
	t.root.add_child(s5)
	s5.start()
	c.check("Day1の朝：支払い予定＝運営費＋場所代＋水道代（%d）" % (daily + 140), int(s5.budget()["reserved"]) == daily + 140 and s5.operating_cost_pending() == daily)
	# 中身U2：Day1は初日セットを朝に引き（210）、市場を出たあと炭屋の会話のあとに炭代40、水場の会話のあとに水代35と水道代50を払う。
	c.check("Day1の朝：初日セット（210）を朝に引いた（帳簿の kit・WAKE）", _kit_amounts() == [["kit", -210, "WAKE"]] and GameState.money == GameState.INITIAL_MONEY - 210)
	s5.flow.advance_phase()   # WAKE→PREP
	var guard5 := 0
	while not s5.is_in_prep_tier() and guard5 < 80:
		guard5 += 1
		s5.next_event()
	s5.choose_prep_tier("small")
	guard5 = 0
	while not s5.is_in_market() and guard5 < 60:
		guard5 += 1
		s5.next_event()
	var ledger5 := GameState.ledger.size()
	var money5 := GameState.money
	c.check("Day1：市場を出る操作では払わない（このあとの炭屋・水場の会話のあとで払う）", s5.exit_market() and GameState.money == money5
		and _category_amounts(ledger5).is_empty() and s5.operating_cost_pending() == daily, str(_category_amounts(ledger5)))
	guard5 = 0
	while GameState.phase == GameState.Phase.PREP and not s5.flow.is_runner_done() and guard5 < 80:
		guard5 += 1
		s5.next_event()
	c.check("Day1：炭屋の会話のあと炭代40、水場の会話のあと水代35・水道代50（運営費の合計75は今までと同じ・確保も外れた）",
		_category_amounts(ledger5) == [["daily_cost", -40, "PREP"], ["daily_cost", -35, "PREP"], ["water", -50, "PREP"]]
			and GameState.money == money5 - 125 and s5.operating_cost_pending() == 0 and int(Ledger.spend_by_category_today()["daily_cost"]) == daily
			and s5.market_visited_water, str(_category_amounts(ledger5)))
	c.check("場所代（90）は、まだ支払い予定のまま（開店中のチンピラの来店で払う。タイミングは変えない）",
		int(s5.budget()["reserved"]) == 90 and not GameState.rent_paid_today)
	s5.free()

	# --- 6. 市場を通らず開店へ進むとき（保険）：開店に入るときに引く ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var s6 := PlaySession.new()
	t.root.add_child(s6)
	s6.start()
	var money6 := GameState.money
	GameState.phase = GameState.Phase.OPEN
	s6.set_runner_for_phase(GameState.Phase.OPEN)
	c.check("市場を通らずに開店へ：開店に入るとき運営費を引く（支払い予定は0）", GameState.money == money6 - daily and s6.operating_cost_pending() == 0
		and int(Ledger.spend_by_category_today()["daily_cost"]) == daily)
	s6.free()

	GameState.reset_for_new_game()
	return c.finish()
