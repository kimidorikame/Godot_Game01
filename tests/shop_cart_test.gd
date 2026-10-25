extends RefCounted
## 購入確定（かご。UI準備D・D-2）。「かごに入れる」では買わず、「購入確定」（店に残る）・「購入して店を出る」で入れた順に買う。
## 「使える」（残金−支払い予定）を超える購入は、PlaySession（buy_item・choose_prep_tier）で拒否し、画面ではボタンを押せなくして理由を出す。
## 対象：使える現金を超える購入の拒否（徴収日の確保分に手を付けられない）、かごの追加・1つ戻す・全部戻す・購入確定・購入して店を出る・
## 買わずに店を出る、「使える」の表示（かごの分を引く）、買った記録（帳簿・在庫）が1つずつ買ったときと同じ、鍋の素の選択と購入確定。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _market_tail(from_index: int) -> Array:
	var out: Array = []
	for i in range(from_index, GameState.ledger.size()):
		var e: Dictionary = GameState.ledger[i]
		out.append([str(e["category"]), int(e["amount"]), str(e["item"]), int(e["count"]), int(e["unit_price"])])
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. PlaySession：使える現金（残金−支払い予定）を超える購入は拒否する ---
	GameState.reset_for_new_game()
	var s := PlaySession.new()
	t.root.add_child(s)
	s.start()
	GameState.money = 275   # Day1（徴収日）の朝は、運営費75＋場所代90＋水道代50＝215を確保済み。使える＝60
	c.check("支払い予定215・残金275 → 使える60", s.purchase_limit() == 60 and int(s.budget()["usable"]) == 60 and int(s.budget()["reserved"]) == 215)
	c.check("買えない理由（使える現金を超える）が文で出る", s.purchase_block_reason(100) != "" and s.purchase_block_reason(60) == "" and s.purchase_block_reason(61) != "")
	var inv_before := GameState.inventory.duplicate(true)
	s.buy_item("seafood", "fish_maw")   # ¥100：残金200は足りるが、使える60を超える
	c.check("buy_item：残金は足りても、使える現金（60）を超える ¥100 は買えない（確保分に手を付けられない）",
		GameState.money == 275 and GameState.inventory == inv_before)
	s.buy_item("seafood", "shrimp_single")   # ¥20：使える範囲
	c.check("buy_item：使える範囲の ¥20 は買える", GameState.money == 255 and GameState.fresh_count("shrimp") >= 1)
	var tiers := s.prep_tiers()
	c.check("prep_tiers の affordable も使える現金で決まる（小¥80は使える40を超えて買えない）", not bool(tiers[0]["affordable"]) and s.purchase_limit() == 40)
	var money_before := GameState.money
	s.choose_prep_tier("small")
	c.check("choose_prep_tier：使える現金を超える鍋の素は買えない（残金255・小¥80でも、支払い予定215を引くと使えるのは40）",
		GameState.money == money_before and not s.prep_tier_paid())
	var view := s.shop_view("seafood")
	c.check("shop_view の affordable も使える現金で決まる", not bool(view[3]["affordable"]) and bool(view[1]["affordable"]) == (20 <= 40), str(view))
	s.free()

	# --- 2. 画面：かご（Day2の市場）---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var session: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		play.step()
	c.check("Day2の市場（店選び）まで進んだ", GameState.day_count == 2 and session.is_in_market() and root.pane_market.visible)
	var stalls: Control = root.pane_market.get_node("%Stalls")
	_press(stalls.get_child(3))   # 福生豆腐麺房（豆腐¥24・米麺¥40）
	var shop: UiPaneBuyShop = root.pane_buy_shop
	var goods: UiGoodsList = shop.get_node("%Goods")
	c.check("豆腐麺房に入った（豆腐・米麺）", session.market_shop == "tofu_noodles" and goods.get_child_count() == 2)
	var tofu_price := int(session.shop_view("tofu_noodles")[0]["price"])
	var noodle_price := int(session.shop_view("tofu_noodles")[1]["price"])
	var money0 := GameState.money
	var usable0 := int(session.budget()["usable"])
	var ledger0 := GameState.ledger.size()
	var tofu_stock0 := GameState.fresh_count("tofu")
	c.check("商品の行のボタンは「かごに入れる」", (goods.get_child(0).get_node("BuyButton") as Button).text == "かごに入れる")
	c.check("かごが空のとき、「購入確定」「購入して店を出る」は押せず、出口は「店を出る」",
		(shop.get_node("%ConfirmButton") as Button).disabled and (shop.get_node("%ExitBuyButton") as Button).disabled
			and (shop.get_node("%BackButton") as Button).text == "店を出る" and shop.get_node("%CartBox/CartList").text == "（空）")
	_press(goods.get_child(0).get_node("BuyButton"))
	_press(goods.get_child(0).get_node("BuyButton"))
	c.check("「かごに入れる」2回＝2セット：まだ買わない（残金・在庫・帳簿は動かない）",
		GameState.money == money0 and GameState.fresh_count("tofu") == tofu_stock0 and GameState.ledger.size() == ledger0 and root.cart.count("tofu_noodles") == 2)
	c.check("かごの表示：同じ商品はまとめて「豆腐×2 ¥%d」・合計" % (tofu_price * 2),
		shop.get_node("%CartBox/CartList").text == "豆腐×2 ¥%d" % (tofu_price * 2) and shop.get_node("%CartBox/CartTotal").text == "合計 ¥%d" % (tofu_price * 2))
	c.check("「使える」は、かごの分を引いた額（残金・確保はそのまま）",
		shop.get_node("%Budget/Usable/Value").text == "¥%d" % (usable0 - tofu_price * 2) and shop.get_node("%Budget/Money/Value").text == "¥%d" % money0)
	c.check("「購入確定」「購入して店を出る」が押せる。出口は「買わずに店を出る」", not (shop.get_node("%ConfirmButton") as Button).disabled
		and not (shop.get_node("%ExitBuyButton") as Button).disabled and (shop.get_node("%BackButton") as Button).text == "買わずに店を出る")
	_press(shop.get_node("%CartBox/UndoButton"))
	c.check("「1つ戻す」で最後に入れたものが戻る", root.cart.count("tofu_noodles") == 1 and shop.get_node("%CartBox/CartTotal").text == "合計 ¥%d" % tofu_price)
	_press(shop.get_node("%CartBox/ClearButton"))
	c.check("「全部戻す」でかごが空になる", root.cart.count("tofu_noodles") == 0 and shop.get_node("%CartBox/CartList").text == "（空）")

	# 入れた順に買う：豆腐・米麺・豆腐（購入確定）
	_press(goods.get_child(0).get_node("BuyButton"))
	_press(goods.get_child(1).get_node("BuyButton"))
	_press(goods.get_child(0).get_node("BuyButton"))
	_press(shop.get_node("%ConfirmButton"))
	var cart_tail := _market_tail(ledger0)
	c.check("「購入確定」：入れた順（豆腐・米麺・豆腐）に3件買う。店に残り、かごは空になる",
		cart_tail.size() == 3 and cart_tail[0][2] == "tofu" and cart_tail[1][2] == "rice_noodle" and cart_tail[2][2] == "tofu"
			and GameState.money == money0 - tofu_price * 2 - noodle_price and session.market_shop == "tofu_noodles" and root.cart.count("tofu_noodles") == 0,
		str(cart_tail))
	# 1つずつ買ったとき（buy_item を同じ順に呼ぶ）と、帳簿の記録が同じ
	var ledger1 := GameState.ledger.size()
	session.buy_item("tofu_noodles", "tofu")
	session.buy_item("tofu_noodles", "rice_noodle")
	session.buy_item("tofu_noodles", "tofu")
	c.check("かごで買った記録（帳簿）は、buy_item を同じ順に1つずつ呼んだときと同じ", _market_tail(ledger1) == cart_tail, str(_market_tail(ledger1)))
	c.check("「この店で買った」に、かごで買った3件が出る（UIの集計）", root.tally.entries("tofu_noodles").size() == 3)

	# 使える現金を超える分は、かごに入れられない
	GameState.money = Ledger.pending_bills_today() + 100   # 使える＝100
	session.notify_changed()
	c.check("使える100：米麺（¥%d）は2つまでかごに入る" % noodle_price, int(session.budget()["usable"]) == 100)
	_press(goods.get_child(1).get_node("BuyButton"))
	_press(goods.get_child(1).get_node("BuyButton"))
	var third := _press(goods.get_child(1).get_node("BuyButton"))
	c.check("3つ目（合計%d）は使える100を超える：行のボタンが押せない・かごは2セットのまま・理由が出る" % (noodle_price * 3),
		not third and root.cart.count("tofu_noodles") == 2 and (goods.get_child(1).get_node("BuyButton") as Button).disabled
			and shop.get_node("%ReasonLabel").text != "", shop.get_node("%ReasonLabel").text)
	GameState.money = Ledger.pending_bills_today() + noodle_price   # かごの合計が使える額を超えた状態にする（残金が減った）
	session.notify_changed()
	c.check("かごの合計が「使える」を超えると、「購入確定」「購入して店を出る」は押せない",
		(shop.get_node("%ConfirmButton") as Button).disabled and (shop.get_node("%ExitBuyButton") as Button).disabled)
	var money_cap := GameState.money
	shop._on_confirm(false)
	c.check("（押せない状態で呼んでも買わない）", GameState.money == money_cap and root.cart.count("tofu_noodles") == 2)
	GameState.money = Ledger.pending_bills_today() + 500
	session.notify_changed()

	# 買わずに店を出る：かごを空にして出る（買わない）
	var money_leave := GameState.money
	_press(shop.get_node("%BackButton"))
	c.check("「買わずに店を出る」：買わずに市場へ戻り、かごは空", session.market_shop == "" and GameState.money == money_leave and root.cart.count("tofu_noodles") == 0)

	# 購入して店を出る：買ってから出る
	_press(stalls.get_child(3))
	var ledger2 := GameState.ledger.size()
	_press(goods.get_child(0).get_node("BuyButton"))
	_press(shop.get_node("%ExitBuyButton"))
	c.check("「購入して店を出る」：かごの商品を買って、市場（店選び）へ戻る", session.market_shop == "" and _market_tail(ledger2).size() == 1
		and GameState.money == money_leave - tofu_price and root.pane_market.visible)
	root.queue_free()

	# --- 3. 鍋の素：選んで「購入して店を出る」。使える現金を超える段階は選べない ---
	GameState.reset_for_new_game()
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	session = root.session
	play = load("res://tests/ui_autoplay.gd").new(root)
	guard = 0
	while not (GameState.day_count == 2 and root.pane_buy_meat.visible and session.is_in_prep_tier()) and guard < 3000:
		guard += 1
		play.step()
	var meat: UiPaneBuyMeat = root.pane_buy_meat
	var tier_cards: Control = meat.get_node("%Tiers")
	c.check("Day2の鍋の素の選択（張記）まで進んだ", session.is_in_prep_tier() and meat.visible)
	GameState.money = 100 + session.operating_cost_pending()   # 小¥80・中¥110・大¥140：使える100なら小だけ（運営費75は支払い予定）
	session.notify_changed()
	c.check("使える100：中・大は選べない（押せない）・理由が出る", not (tier_cards.get_child(0) as Button).disabled
		and (tier_cards.get_child(1) as Button).disabled and (tier_cards.get_child(2) as Button).disabled and meat.get_node("%ReasonLabel").text != "",
		meat.get_node("%ReasonLabel").text)
	var tier_money := GameState.money
	_press(tier_cards.get_child(0))
	var small_price := int(session.prep_tiers()[0]["price"])
	c.check("小を選ぶ（まだ買わない）：「購入確定」「購入して店を出る」が押せる・「買わずに店を出る」", GameState.money == tier_money
		and not (meat.get_node("%ConfirmButton") as Button).disabled and not (meat.get_node("%ExitBuyButton") as Button).disabled
		and (meat.get_node("%BackButton") as Button).text == "買わずに店を出る" and meat.get_node("%CartBox/CartList").text.begins_with("鍋の素 小"))
	var index_before: int = session.flow.runner.index
	_press(meat.get_node("%ExitBuyButton"))
	c.check("「購入して店を出る」：鍋の素（小）を買って、会話を1つ進める", GameState.money == tier_money - small_price and session.prep_tier_paid()
		and session.flow.runner.index != index_before and not session.is_in_prep_tier())
	root.queue_free()

	GameState.reset_for_new_game()
	return c.finish()
