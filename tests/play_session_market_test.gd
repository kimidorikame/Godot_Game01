extends RefCounted
## PlaySession（UI準備A②：市場・仕込み・支払い）の検証。
## 対象：本番UIが読む問い（店の一覧・店の商品・仕込み3段階・鍋の素を買ったか・市場を出られるか・予算）、
## 市場・仕込みの操作（店へ入る／出る・買う・段階を選ぶ・水場）、支払いとゲームオーバー、
## 操作ごとに changed が1回出ること、DebugPanelの橋が同じ状態を指すこと。
## 操作の中身そのものは既存のスイート（prep_tier_test・upkeep_test・ingredient_pricing_test など）が確かめる。


## 朝（WAKE）で運営費が引かれたあと、指定の所持金に置き直してから仕込み（PREP）へ進める
## （keep_wake_money=true なら置き直さず、朝の所持金のまま）。
func _setup(t: SceneTree, money: int, day: int, keep_wake_money: bool = false):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	if not keep_wake_money:
		GameState.money = money
		# このスイートの所持金は「運営費（水と炭）を引いたあと」の値（運営費は市場を出るとき・開店のときに引く。UI準備D・D-4）。
		# 引き終えた状態にそろえる（確保を解くだけ。所持金は動かさない）。
		var pending: int = panel.session.operating_cost_pending()
		if pending > 0:
			Ledger.record("release", pending, "", 0, 0, "operating")
	GameState.phase = GameState.Phase.PREP
	panel.session.set_runner_for_phase(GameState.Phase.PREP)
	return panel


## 仕込みの段階選択（PREP_TIER）まで進める。
func _to_tier(panel) -> void:
	var guard := 0
	while not panel.session.is_in_prep_tier() and guard < 50:
		guard += 1
		panel.session.next_event()


## 市場（MARKET）まで進める（段階を選んだあと）。
func _to_market(panel) -> void:
	var guard := 0
	while not panel.session.is_in_market() and guard < 50:
		guard += 1
		panel.session.next_event()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var counter := { "n": 0 }

	# --- 1. 予算（共通）：残金・確保・使える ---
	var p1 = _setup(t, 300, 1, true)
	var b: Dictionary = p1.session.budget()
	c.check("Day1の朝の予算：残金300・支払い予定215（運営費75＋場所代・水道代140）・使える85（運営費は市場を出るときに引く）",
		b == { "money": 300, "reserved": 215, "usable": 85, "operating": 75 }, str(b))
	p1.free()

	# --- 2. 仕込み3段階：段階の一覧・買えるか・鍋の素を買ったか ---
	var p2 = _setup(t, 100, 3)
	p2.session.changed.connect(func(): counter["n"] += 1)
	c.check("段階を選ぶ前は『鍋の素を買った』にならない", not p2.session.prep_tier_paid())
	_to_tier(p2)
	c.check("段階の選択に着いた", p2.session.is_in_prep_tier() and not p2.session.can_exit_market())
	var tiers: Array = p2.session.prep_tiers()
	c.check("3段階（小・中・大）の id・杯数・値段が出る",
		tiers.map(func(x): return x["id"]) == ["small", "medium", "large"]
			and tiers.map(func(x): return x["servings"]) == [8, 11, 14]
			and tiers.map(func(x): return x["price"]) == [80, 110, 140], str(tiers))
	c.check("所持金100なら、買えるのは小仕込みだけ",
		tiers.map(func(x): return x["affordable"]) == [true, false, false], str(tiers))
	counter["n"] = 0
	p2.session.choose_prep_tier("large")
	c.check("買えない段階は選べない（所持金・段階の選択は変わらない）", GameState.money == 100 and p2.session.is_in_prep_tier()
		and not p2.session.prep_tier_paid())
	c.check("買えない段階を選んでも changed は出さない（何も変わっていない）", counter["n"] == 0)
	p2.session.choose_prep_tier("small")
	c.check("小仕込みを選ぶ：所持金-80・鍋の素を買った・changed が出る（runner の差し替えでも出るので回数は問わない）", GameState.money == 20
		and p2.session.prep_tier_paid() and counter["n"] >= 1, str(counter["n"]))
	c.check("選んだあとは段階の選択ではなくなる（残りの列に差し替わる）", not p2.session.is_in_prep_tier())
	var base: Dictionary = p2.session.today_base()
	c.check("今日の鍋の素：買った・小仕込み・8杯・クズ野菜ではない",
		base == { "paid": true, "tier_id": "small", "label": "小仕込み", "servings": 8, "scraps": false }, str(base))
	p2.free()
	# 今日の鍋の素：買う前
	var p2b = _setup(t, 1000, 3)
	_to_tier(p2b)
	c.check("買う前の鍋の素：買っていない・段階なし",
		p2b.session.today_base() == { "paid": false, "tier_id": "", "label": "", "servings": 0, "scraps": false },
		str(p2b.session.today_base()))
	p2b.session.choose_prep_tier("medium")
	c.check("中仕込みを買うと『中・11杯・買った』",
		p2b.session.today_base() == { "paid": true, "tier_id": "medium", "label": "中仕込み", "servings": 11, "scraps": false },
		str(p2b.session.today_base()))
	p2b.free()
	# クズ野菜ベースの日：所持金が一番安い仕込みにも満たない
	var p2c = _setup(t, 50, 3)
	c.check("クズ野菜ベースの日：支払いは無く、小仕込み相当（8杯）の自動の鍋の素",
		p2c.session.today_base() == { "paid": false, "tier_id": "small", "label": "小仕込み", "servings": 8, "scraps": true }
			and p2c.session.scraps_base, str(p2c.session.today_base()))
	p2c.session.scraps_base = true
	GameState.phase = GameState.Phase.WAKE
	c.check("仕込みの前（朝）は、前日のクズ野菜の印が残っていても scraps は false",
		p2c.session.today_base()["scraps"] == false)
	p2c.free()

	# --- 3. 市場：店の一覧・店の商品・買う・店を出る ---
	var p3 = _setup(t, 1000, 3)
	p3.session.changed.connect(func(): counter["n"] += 1)
	_to_tier(p3)
	p3.session.choose_prep_tier("small")
	_to_market(p3)
	c.check("市場に着いた：市場を出られる", p3.session.is_in_market() and p3.session.can_exit_market())
	var stalls: Array = p3.session.market_stalls()
	c.check("店の一覧：6店・id と開いているか（3日目はすべて開いている）",
		stalls.size() == 6 and stalls.all(func(x): return x["enabled"] == true)
			and stalls.map(func(x): return x["id"]).has("meat_wholesale")
			and stalls.map(func(x): return x["id"]).has("scraps"), str(stalls))
	c.check("店の中にいない間は market_shop が空", p3.session.market_shop == "")
	counter["n"] = 0
	p3.session.select_stall("produce")
	c.check("店へ入る：market_shop が店のid・changed が1回・DebugPanelの橋も同じ値",
		p3.session.market_shop == "produce" and counter["n"] == 1)
	p3.session.select_stall("nothing")
	c.check("知らない店のidでは市場のトップに戻らず現在の店のまま", p3.session.market_shop == "produce")
	GameState.inventory.erase("winter_melon")
	GameState.perishable_batches.erase("winter_melon")
	var view: Array = p3.session.shop_view("produce")
	var melon := {}
	for g in view:
		if g["item"] == "winter_melon":
			melon = g
	c.check("店の商品：id・品目・値段・個数・単価・在庫の新鮮／傷んだ数・買えるか・具か味付けか",
		not melon.is_empty() and melon["price"] == 50 and melon["count"] == 5 and melon["unit_price"] == 10
			and melon["fresh"] == 0 and melon["damaged"] == 0 and melon["affordable"] == true
			and melon["kind"] == "topping", str(melon))
	var money_before: int = GameState.money
	counter["n"] = 0
	p3.session.buy_item("produce", melon["id"])
	c.check("買う：所持金-50・在庫が個数ぶん増える・帳簿 market・changed が1回",
		GameState.money == money_before - 50 and GameState.fresh_count("winter_melon") == 5
			and int(Ledger.spend_by_category_today().get("market", 0)) >= 50 and counter["n"] == 1)
	var view2: Array = p3.session.shop_view("produce")
	var melon2 := {}
	for g in view2:
		if g["item"] == "winter_melon":
			melon2 = g
	c.check("買ったあとの在庫が商品の問いに反映される（新鮮5）", melon2["fresh"] == 5)
	# だし（個数を持たない商品）
	var meat: Array = p3.session.shop_view("meat_wholesale")
	var dashi := {}
	for g in meat:
		if g["id"] == "dashi":
			dashi = g
	c.check("だしは個数・単価を持たず、在庫は手持ちのだしの数、種類は空",
		not dashi.is_empty() and dashi["count"] == 0 and dashi["item"] == "" and dashi["kind"] == ""
			and dashi["fresh"] == GameState.dashi_units and dashi["damaged"] == 0, str(dashi))
	var dashi_before: int = GameState.dashi_units
	p3.session.buy_item("meat_wholesale", "dashi")
	c.check("だしを買う：手持ちが1増える", GameState.dashi_units == dashi_before + 1)
	GameState.money = 0
	var broke: Array = p3.session.shop_view("produce")
	c.check("所持金0では、どの商品も買えない（affordable がすべて false）", broke.all(func(x): return x["affordable"] == false))
	counter["n"] = 0
	p3.session.buy_item("produce", melon["id"])
	c.check("所持金が足りなければ買えない（所持金・在庫は変わらない）",
		GameState.money == 0 and GameState.fresh_count("winter_melon") == 5)
	p3.session.leave_shop()
	c.check("店を出る：market_shop が空に戻る", p3.session.market_shop == "")
	c.check("市場の店の中身は未実装の店なら空", PlaySession.shop_goods("nothing").is_empty())
	p3.free()

	# --- 4. 市場を出る（水場）：徴収日だけ水道代・払えなければゲームオーバー ---
	var p4 = _setup(t, 1000, 1)
	_to_tier(p4)
	p4.session.choose_prep_tier("small")
	_to_market(p4)
	c.check("徴収日（Day1）：まだ水場に寄っていない", not p4.session.market_visited_water)
	var money4: int = GameState.money
	var reserved4: int = p4.session.budget()["reserved"]
	c.check("exit_market() は true（先へ進んでよい）・水道代50を払って確保から外れる",
		p4.session.exit_market() and GameState.money == money4 - 50 and p4.session.market_visited_water
			and p4.session.budget()["reserved"] == reserved4 - 50, str(p4.session.budget()))
	money4 = GameState.money
	c.check("2回目は水道代を払わない", p4.session.exit_market() and GameState.money == money4)
	p4.free()
	var p5 = _setup(t, 1000, 3)
	_to_tier(p5)
	p5.session.choose_prep_tier("small")
	_to_market(p5)
	var money5: int = GameState.money
	c.check("非徴収日は水道代を払わない（水場には寄った扱い）",
		p5.session.exit_market() and GameState.money == money5 and p5.session.market_visited_water)
	p5.free()
	var p6 = _setup(t, 1000, 1)
	_to_tier(p6)
	p6.session.choose_prep_tier("small")
	_to_market(p6)
	GameState.money = 30
	c.check("水道代が払えなければ exit_market() は false で、ゲームオーバーになる",
		not p6.session.exit_market() and GameState.phase == GameState.Phase.GAME_OVER)
	c.check("ゲームオーバーでも所持金は変わらない（マイナスにならない）", GameState.money == 30, str(GameState.money))
	p6.free()

	# --- 5. 支払いとゲームオーバー ---
	var p7 = _setup(t, 300, 2)
	var paid_before: int = GameState.money
	c.check("払えれば true・所持金が減り・帳簿に記帳される",
		p7.session.pay_or_game_over(40, "water") and GameState.money == paid_before - 40
			and int(Ledger.spend_by_category_today().get("water", 0)) >= 40)
	c.check("category を省略すると記帳しない", p7.session.pay_or_game_over(10) and GameState.money == paid_before - 50)
	GameState.money = 5
	c.check("払えなければ false・所持金は変わらず GAME_OVER", not p7.session.pay_or_game_over(10, "water")
		and GameState.money == 5 and GameState.phase == GameState.Phase.GAME_OVER)
	p7.free()

	GameState.reset_for_new_game()
	return c.finish()
