extends RefCounted
## UI準備P-4：仕入れの在庫を、かごを含めて見せる（表示だけ。判定・評判・乱数・経済は変えない）。
## 対象：市場の商品の行の「手持ちN → 購入後」（購入後＝手持ち〔新鮮＋傷〕＋かごに入れた分。かごが空なら「手持ちN」だけ）、
## 同じ品目の2つの商品（モツのパックと小口）はかごの分を合わせる、購入確定の前後の表示、
## スマホの持ち物（市場にいるあいだ、かごの分を「＋N（かご）」で足す・かごの分で点く札は「＋」付きの半分の明るさ）、
## PlaySession.inventory_view(かご) の形。どれもボタンの pressed だけで操作する（押せないボタンは押さない）。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _label_texts(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append((child as Label).text)
		out.append_array(_label_texts(child))
	return out


## 性質チェックの札（state のメタを持つ）を { 言葉: [state, 文字] } で返す。
func _trait_chips(content: Node) -> Dictionary:
	var out := {}
	for node in content.get_children():
		for chip in node.get_children():
			if chip.has_meta("state"):
				out[str(chip.get_meta("tag"))] = [str(chip.get_meta("state")), (chip as Label).text]
	return out


## 行の「手持ち」「→ 購入後」の文字（購入後が出ていなければ ""）。
func _row_stock(row: UiGoodsRow) -> Array:
	var after: Label = row.get_node("Stock/After")
	return [row.get_node("Stock/Have").text, after.text if after.visible else ""]


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. PlaySession.inventory_view(かご)：表示の形だけ ---
	GameState.reset_for_new_game()
	var s := PlaySession.new()
	t.root.add_child(s)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("tofu", 2)
	var plain := s.inventory_view()
	var with_cart := s.inventory_view({ "tofu": 3, "shrimp": 3, "dashi": 1 })
	var rows := {}
	for r in (with_cart["flavors"] as Array) + (with_cart["toppings"] as Array):
		rows[str(r["id"])] = r
	var states := {}
	for tr in with_cart["traits"]:
		states[str(tr["tag"])] = str(tr["state"])
	c.check("かごなし：今までどおり（行に cart は 0・海老の行は無い・ごちそうは暗い）",
		(plain["toppings"] as Array).size() == 1 and int(plain["toppings"][0]["cart"]) == 0
			and (plain["traits"] as Array).any(func(x): return x["tag"] == "TREAT" and x["state"] == "dark"))
	c.check("かごあり：手持ちの行にかごの分（豆腐 2＋かご3）・手持ちが0でもかごにある材料は行が出る（海老 0＋かご3）・だしは出ない",
		int(rows["tofu"]["fresh"]) == 2 and int(rows["tofu"]["cart"]) == 3 and rows.has("shrimp") and int(rows["shrimp"]["fresh"]) == 0
			and int(rows["shrimp"]["cart"]) == 3 and not rows.has("dashi"), str(rows))
	c.check("性質チェック：手持ちの新鮮で点く札は lit のまま（やさしい）、かごの分でだけ点く札は cart（ごちそう）、どちらも無いのは dark",
		states["GENTLE"] == "lit" and states["TREAT"] == "cart" and states["HOT"] == "dark", str(states))
	s.free()

	# --- 2. 画面：Day2 の市場（豆腐麺房）---
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
	GameState.money += 300   # かごに何品も入れるため
	_press(root.pane_market.get_node("%Stalls").get_child(3))   # 福生豆腐麺房（豆腐3個・米麺5個）
	var shop: UiPaneBuyShop = root.pane_buy_shop
	var goods: UiGoodsList = shop.get_node("%Goods")
	var tofu_row: UiGoodsRow = goods.get_child(0)
	var noodle_row: UiGoodsRow = goods.get_child(1)
	var tofu_have := GameState.fresh_count("tofu") + GameState.damaged_count("tofu")
	var noodle_have := GameState.fresh_count("rice_noodle") + GameState.damaged_count("rice_noodle")
	var tofu_count := int(session.shop_view("tofu_noodles")[0]["count"])
	var noodle_count := int(session.shop_view("tofu_noodles")[1]["count"])
	c.check("かごが空：「手持ちN」だけ（→ は出さない）", _row_stock(tofu_row) == ["手持ち%d" % tofu_have, ""]
		and _row_stock(noodle_row) == ["手持ち%d" % noodle_have, ""], str(_row_stock(tofu_row)))
	_press(tofu_row.get_node("BuyButton"))
	_press(tofu_row.get_node("BuyButton"))
	c.check("豆腐を2回かごへ：「手持ち%d → %d」（購入後＝手持ち＋かごの分）" % [tofu_have, tofu_have + 2 * tofu_count],
		_row_stock(tofu_row) == ["手持ち%d" % tofu_have, "→ %d" % (tofu_have + 2 * tofu_count)]
			and _row_stock(noodle_row) == ["手持ち%d" % noodle_have, ""], str(_row_stock(tofu_row)))
	c.check("「→ 購入後」は強調色の型（LabelStockAfter）", (tofu_row.get_node("Stock/After") as Label).theme_type_variation == &"LabelStockAfter")
	c.check("かごに入れただけでは在庫は変わらない", GameState.fresh_count("tofu") + GameState.damaged_count("tofu") == tofu_have)

	# スマホの持ち物（市場にいるあいだ、かごの分を足して見せる）
	_press(noodle_row.get_node("BuyButton"))
	root.open_phone("inventory")
	var phone: UiPanePhone = root.pane_phone
	var content: Control = phone.get_node("%Content")
	var texts := _label_texts(content)
	c.check("持ち物：かごの分を「＋N（かご）」で足す（豆腐＋%d・米麺＋%d）" % [2 * tofu_count, noodle_count],
		texts.has("＋%d（かご）" % (2 * tofu_count)) and texts.has("＋%d（かご）" % noodle_count), str(texts))
	var chips := _trait_chips(content)
	var filling_by_stock := false
	for id in GameState.inventory:
		if Ingredients.tags_for(str(id)).has("FILLING") and GameState.fresh_count(str(id)) > 0:
			filling_by_stock = true
	c.check("性質チェック：かごの分でだけ点く札は「＋」付き・半分の明るさ（腹もち＝米麺。手持ちに新鮮な腹もちがあれば lit のまま）",
		(chips["FILLING"] == ["lit", "腹もち"]) if filling_by_stock else (chips["FILLING"] == ["cart", "＋腹もち"]), str(chips))
	var cart_chip_alpha := -1.0
	for node in content.get_children():
		for chip in node.get_children():
			if chip.has_meta("state") and chip.get_meta("state") == "cart":
				cart_chip_alpha = (chip as Label).modulate.a
	c.check("かごの分の札は、点灯（1.0）と暗い（0.25）の間の明るさ", filling_by_stock or (cart_chip_alpha > 0.25 and cart_chip_alpha < 1.0), str(cart_chip_alpha))
	c.check("説明の行に「＋付き＝かごの分」", texts.any(func(x): return str(x).contains("＋付き＝かごの分")), str(texts))
	root.close_overlay()

	# 購入確定 → 手持ちに入る
	_press(shop.get_node("%ConfirmButton"))
	c.check("購入確定：かごが空になり、手持ちに入る（→ は消える）",
		root.cart.count("tofu_noodles") == 0
			and _row_stock(tofu_row) == ["手持ち%d" % (tofu_have + 2 * tofu_count), ""]
			and _row_stock(noodle_row) == ["手持ち%d" % (noodle_have + noodle_count), ""], str(_row_stock(tofu_row)))
	root.open_phone("inventory")
	texts = _label_texts(phone.get_node("%Content"))
	c.check("購入確定のあとの持ち物：かごの印は無く、個数が増えている",
		not texts.any(func(x): return str(x).contains("（かご）")) and texts.has("×%d" % (tofu_have + 2 * tofu_count)), str(texts))
	root.close_overlay()
	_press(shop.get_node("%BackButton"))

	# 張記：モツのパックと小口は同じ品目（offal）なので、かごの分を合わせて購入後を出す
	_press(root.pane_market.get_node("%Stalls").get_child(0))
	var meat_goods: UiGoodsList = root.pane_buy_meat.get_node("%Goods")
	var pack_row: UiGoodsRow = meat_goods.get_child(0)
	var single_row: UiGoodsRow = meat_goods.get_child(1)
	var offal_have := GameState.fresh_count("offal") + GameState.damaged_count("offal")
	_press(pack_row.get_node("BuyButton"))
	_press(single_row.get_node("BuyButton"))
	var offal_after := offal_have + 3 + 1
	c.check("モツ（パック3個）と小口1個をかごへ：どちらの行も「手持ち%d → %d」" % [offal_have, offal_after],
		_row_stock(pack_row) == ["手持ち%d" % offal_have, "→ %d" % offal_after]
			and _row_stock(single_row) == ["手持ち%d" % offal_have, "→ %d" % offal_after], str(_row_stock(pack_row)))
	var dashi_row: UiGoodsRow = null
	for row in meat_goods.get_children():
		if (row as UiGoodsRow).visible and row.get_node("Tags/Name").text == "濃縮だし":
			dashi_row = row
	if dashi_row != null:
		var dashi_have := GameState.dashi_units
		_press(dashi_row.get_node("BuyButton"))
		c.check("濃縮だし：「手持ち%d → %d」（1回で1つ）" % [dashi_have, dashi_have + 1], _row_stock(dashi_row) == ["手持ち%d" % dashi_have, "→ %d" % (dashi_have + 1)],
			str(_row_stock(dashi_row)))
	else:
		c.check("張記に濃縮だしの行がある", false)
	_press(root.pane_buy_meat.get_node("%ConfirmButton"))
	c.check("張記の購入確定：モツの手持ちに入る（→ は消える）", _row_stock(pack_row) == ["手持ち%d" % offal_after, ""], str(_row_stock(pack_row)))
	_press(root.pane_buy_meat.get_node("%BackButton"))
	_press(root.pane_market.get_node("%ExitButton"))
	c.check("市場を出たあとは、スマホの持ち物にかごの分を足さない（市場にいるあいだだけ）", not session.is_in_market())
	root.queue_free()
	return c.finish()
