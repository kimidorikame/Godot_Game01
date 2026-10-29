extends RefCounted
## 本番UI（UI準備B②）：右の枠の朝・市場・購入（食肉仲卸／ほかの店）の検証。
## 対象：各シーンの寸法（寸法表 SCREENS_UI_LAYOUT §2・§4〜§6、4px以内）、どの状態でどの画面を出すか、
## ボタンの押せる条件と呼ぶ操作（ボタンの pressed だけで朝→市場→店→市場を出るまで進める）、
## 前日成績の行の印（part:"day_summary"）、市場の「この店で買った」のUIだけの集計。
## ボタンの高さは文字の高さで決まる（ヘッドレスの文字の測りは版で違う）ので、ボタンは始点と幅を見る。

const TOL := 4.0


func _near(a: Rect2, b: Rect2, tol: float = TOL) -> bool:
	return absf(a.position.x - b.position.x) <= tol and absf(a.position.y - b.position.y) <= tol \
		and absf(a.size.x - b.size.x) <= tol and absf(a.size.y - b.size.y) <= tol


func _at(node: Control, pos: Vector2, width: float) -> bool:
	return node.get_global_position().distance_to(pos) <= TOL and absf(node.size.x - width) <= TOL


## 入れ物の並べ替えは次のフレームに起きるので、テストでは手で走らせる（子から順に）。
func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)


## 押せるボタンだけ押す（押せないボタンを押したことにしない）。押せたら true。
func _press(button: BaseButton) -> bool:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


func _visible_pane(root: UiGameRoot) -> Control:
	for pane in root._panes():
		if pane.visible:
			return pane
	return null


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. シーンが読み込める ---
	for path in ["res://scenes/ui/pane_header.tscn", "res://scenes/ui/budget_row.tscn", "res://scenes/ui/goods_row.tscn",
			"res://scenes/ui/tier_card.tscn", "res://scenes/ui/pane_morning.tscn", "res://scenes/ui/pane_market.tscn",
			"res://scenes/ui/pane_buy_meat.tscn", "res://scenes/ui/pane_buy_shop.tscn"]:
		var packed: PackedScene = load(path)
		var inst = packed.instantiate() if packed != null else null
		c.check("%s を読み込める" % path.get_file(), inst != null)
		if inst != null:
			inst.free()
	c.check("店名の表：張記肉類加工・半端市「拾味」、表に無い店は短いラベルのまま",
		UiLabels.shop_name("meat_wholesale") == "張記肉類加工" and UiLabels.shop_name("scraps") == "半端市「拾味」"
			and UiLabels.shop_name("unknown", "青果") == "青果")
	c.check("扱う品は商品から作る（小口の重複を除く）", UiLabels.shop_wares("seafood") == "海老・貝・魚の浮き袋", UiLabels.shop_wares("seafood"))

	# --- 2. 朝（Day2。前日の記録あり）---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.day_records = [{ "day": 1, "sale_total": 405, "served_cups": 9, "planned_cups": 11, "unserved_cups": 2,
		"quality_counts": { "GREAT": 2, "GOOD": 5, "OK": 1, "BAD": 1, "": 0 }, "spoiled_items": { "tofu": { "count": 2, "value": 16 } },
		"spoiled_value": 16, "opening_reputation": 30, "closing_reputation": 33 }]
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	(root.get_node("Session") as PlaySession).last_day_summary_text = "◆前日（Day1）の成績◆\n所持金: 525 → 700"
	t.root.add_child(root)
	_sort(root)
	var s: PlaySession = root.session
	var morning: UiPaneMorning = root.pane_morning
	c.check("前日成績の行に印 part:\"day_summary\" が付く（本文は元のまま）",
		str(s.flow.runner.events[0].get("part", "")) == "day_summary" and str(s.flow.runner.events[0]["text"]).begins_with("◆前日"))
	c.check("朝は右の枠に「朝（昨夜の成績）」だけを出す", _visible_pane(root) == morning)
	c.check("見出し：昨夜の成績・補足に前日のDay", morning.get_node("%Header/Title").text == "昨夜の成績"
		and morning.get_node("%Header/Sub").text == "Day 1")
	c.check("会話枠には「昨夜の成績を確かめた。」だけ", root.left.get_node("%DialogueText").text == UiLeftSide.SUMMARY_LINE)
	c.check("売上・提供／注文", morning.get_node("%SalesValue").text == "¥405" and morning.get_node("%ServedLabel").text == "提供 9杯 / 注文11杯")
	c.check("出来の数（GREAT〜BAD）", morning.get_node("%Grades/GREAT/Count").text == "2" and morning.get_node("%Grades/BAD/Count").text == "1")
	c.check("足りなかった杯数（Bでは合計だけ）と廃棄の品目・個数・額",
		morning.get_node("%ShortLabel").text == "足りなかった 2杯" and morning.get_node("%SpoilLabel").text == "廃棄 豆腐2個（¥16）",
		morning.get_node("%SpoilLabel").text)
	# 内訳のキーがある記録（UI準備C③）：素材1・鍋1（来られなかった1杯を含む）→「鍋 2」。0の項目は出さない
	GameState.day_records[0]["unserved_ingredients"] = 1
	GameState.day_records[0]["unserved_pot"] = 1
	GameState.day_records[0]["unserved_declined"] = 0
	GameState.day_records[0]["unserved_not_arrived"] = 0
	morning.refresh()
	c.check("足りなかった杯数の内訳：「足りなかった 2杯（素材 1・鍋 1）」", morning.get_node("%ShortLabel").text == "足りなかった 2杯（素材 1・鍋 1）",
		morning.get_node("%ShortLabel").text)
	GameState.day_records[0]["unserved_not_arrived"] = 1
	morning.refresh()
	c.check("来られなかった客の分は「鍋」に含める（素材 1・鍋 2）。合計は記録のunserved_cupsのまま",
		morning.get_node("%ShortLabel").text == "足りなかった 2杯（素材 1・鍋 2）", morning.get_node("%ShortLabel").text)
	c.check("評判の前後・水と炭（運営費。市場を出るときに払う）・使える現金",
		morning.get_node("%ReputationLabel").text == "評判 30 → 33"
			and morning.get_node("%CostLabel").text == "水と炭（運営費） ¥%d　市場を出るときに払う" % GameState.DAILY_OPERATING_COST
			and morning.get_node("%UsableLabel").text == "使える現金 ¥%d" % int(s.budget()["usable"]))
	var boxes := { "SalesBox": Rect2(852, 86, 388, 71), "GradesBox": Rect2(852, 167, 388, 96), "ShortBox": Rect2(852, 273, 388, 95),
		"BalanceBox": Rect2(852, 378, 388, 88), "MoneyBox": Rect2(852, 476, 388, 123) }
	for box_name in boxes:
		c.check("朝：%s の位置と大きさ（寸法表どおり）" % box_name, _near(morning.get_node("%RecordBoxes/" + box_name).get_global_rect(), boxes[box_name]),
			str(morning.get_node("%RecordBoxes/" + box_name).get_global_rect()))
	c.check("朝：右の枠は (836,24) 420×672", _near(morning.get_global_rect(), Rect2(836, 24, 420, 672)))
	var primary: Button = morning.get_node("%PrimaryButton")
	c.check("朝：主ボタンは (852,634)・幅388", _at(primary, Vector2(852, 634), 388), str(primary.get_global_rect()))
	c.check("朝の主ボタンは「市場へ」だけ（「スマホを見る」ボタンは無い）。朝の語りの途中は押せない", primary.text == "市場へ" and primary.disabled and not s.flow.is_runner_done())

	# 会話を進める：ニュースの行・スマホの入力待ち「スマホを見る。」は会話枠に出さずに続けて進む
	var guard := 0
	var shown_texts: Array = []
	while not s.flow.is_runner_done() and guard < 80:
		guard += 1
		root.left.advance()
		shown_texts.append(str(root.left.get_node("%DialogueText").text))
		if s.is_waiting_input():
			break
	c.check("朝の語りを会話枠のクリックだけで読み終える（入力待ちで止まらない）", s.flow.is_runner_done() and not s.is_waiting_input(), str(shown_texts))
	var news_shown := false
	for text in shown_texts:
		news_shown = news_shown or str(text).contains("ニュース：") or str(text).contains("スマホを見る")
	c.check("朝の会話枠に、ニュースとスマホの入力待ちの行は出ない", not news_shown and not shown_texts.is_empty(), str(shown_texts))
	c.check("朝の列を読み終えると、「市場へ」が押せる", primary.text == "市場へ" and not primary.disabled)
	_press(root.left.get_node("%PhoneIcon"))
	c.check("スマホのボタンで、右の枠がスマホに替わる（ニュースのタブ）", root.overlay == "phone" and root.pane_phone.visible and not morning.visible)
	_press(root.pane_phone.get_node("%CloseButton"))
	c.check("スマホの「閉じる」で朝の画面に戻る", root.overlay == "" and morning.visible)
	_press(primary)
	c.check("「市場へ」で仕込み（PREP）へ（flow.advance_phase）", GameState.phase == GameState.Phase.PREP)

	# --- 3. 購入（食肉仲卸）：市場の前（段階の選択と語り）---
	_sort(root)
	var meat: UiPaneBuyMeat = root.pane_buy_meat
	c.check("仕込みに入ると、右の枠は食肉仲卸（張記）", _visible_pane(root) == meat
		and meat.get_node("%Header/Title").text == "張記肉類加工")
	var tiers: Control = meat.get_node("%Tiers")
	c.check("鍋の素の3つ：(852,170) から 124×98、間隔8（UI準備F3で低くした）",
		_near(tiers.get_child(0).get_global_rect(), Rect2(852, 170, 124, 98)) and _near(tiers.get_child(1).get_global_rect(), Rect2(984, 170, 124, 98)),
		str(tiers.get_child(0).get_global_rect(), tiers.get_child(1).get_global_rect()))
	c.check("予算の3つ：(852,86) 388×55", _near(meat.get_node("%Budget").get_global_rect(), Rect2(852, 86, 388, 55)))
	var meat_scroll: Rect2 = meat.get_node("%GoodsScroll").get_global_rect()
	var meat_cart: Rect2 = meat.get_node("%CartBox").get_global_rect()
	c.check("商品の行の枠：(852,276) 幅388（縦に送る棒のぶん広いことがある）・下端はかごの上6px（かごの高さに合わせて伸び縮みする。UI準備F3）", _near(Rect2(meat_scroll.position, Vector2(388, 0)), Rect2(852, 276, 388, 0)) and meat_scroll.size.x >= 384.0
		and absf(meat_scroll.end.y - (meat_cart.position.y - 6.0)) <= 1.0 and meat_scroll.size.y >= 180.0, str(meat_scroll, meat_cart))
	var back: Button = meat.get_node("%BackButton")
	c.check("「店を出る」（張記。旧「店選びへ」）：(1050,640)・幅190（右半分。左は「購入確定」。UI準備F3）、鍋の素を買うまで押せない・注意の一文が出る",
		_at(back, Vector2(1050, 640), 190) and back.disabled and meat.get_node("%WarnNote").visible)
	c.check("段階の選択の前は、鍋の素を押せない", s.is_in_prep_tier() or (tiers.get_child(0) as Button).disabled)
	guard = 0
	while not s.is_in_prep_tier() and guard < 30:
		guard += 1
		root.left.advance()
	c.check("段階の選択（PREP_TIER）で、買える段階を押せる", s.is_in_prep_tier() and not (tiers.get_child(0) as Button).disabled)
	var money_before := GameState.money
	var small_price := int(s.prep_tiers()[0]["price"])
	var confirm: Button = meat.get_node("%ConfirmButton")
	c.check("段階を選ぶ前は「購入確定」を押せない", confirm.disabled and meat.get_node("%Budget/Usable/Value").text == "¥%d" % int(s.budget()["usable"]))
	_press(tiers.get_child(0))
	c.check("小を押す → 選択中（まだ買わない）：所持金は変わらず、「使える」から価格を引いて見せる・「購入確定」が押せる",
		GameState.money == money_before and tiers.get_child(0).get_node("Note").text == "選択中" and tiers.get_child(0).get_node("BoughtFrame").visible
			and meat.get_node("%Budget/Usable/Value").text == "¥%d" % (int(s.budget()["usable"]) - small_price) and not confirm.disabled
			and confirm.text == "購入確定（¥%d）" % small_price and s.is_in_prep_tier())
	_press(tiers.get_child(1))
	c.check("別の段階を押すと選び直せる（選択は1つ）", tiers.get_child(1).get_node("Note").text == "選択中" and tiers.get_child(0).get_node("Note").text != "選択中"
		and GameState.money == money_before)
	_press(tiers.get_child(0))
	_press(confirm)
	c.check("「購入確定」→ choose_prep_tier（支払い・買った印・注意の一文が消える）",
		GameState.money == money_before - small_price and tiers.get_child(0).get_node("BoughtFrame").visible
			and tiers.get_child(0).get_node("Note").text == "買った" and not meat.get_node("%WarnNote").visible and not s.is_in_prep_tier())
	c.check("買ったあとは、ほかの段階は押せない", (tiers.get_child(1) as Button).disabled)
	c.check("Day2 からは追加購入の行が出る", meat.get_node("%GoodsScroll").visible and meat.get_node("%Goods").get_child_count() == s.shop_view("meat_wholesale").size())
	guard = 0
	while not s.is_in_market() and guard < 30:
		guard += 1
		if not _press(back):
			root.left.advance()   # 会話の入力待ちなどで押せないときは会話を進める
	c.check("「店を出る」（張記。会話を進めるのと同じ）で市場（MARKET）に着く", s.is_in_market())

	# --- 4. 市場（店選び）---
	_sort(root)
	var market: UiPaneMarket = root.pane_market
	c.check("市場の画面：右の枠は市場", _visible_pane(root) == market and market.get_node("%Header/Title").text == "市場")
	var stalls: VBoxContainer = market.get_node("%Stalls")
	c.check("店の行：(852,151) 388×63、間隔6", _near(stalls.get_child(0).get_global_rect(), Rect2(852, 151, 388, 63))
		and _near(stalls.get_child(1).get_global_rect(), Rect2(852, 220, 388, 63)), str(stalls.get_child(1).get_global_rect()))
	c.check("「市場を出る」：(852,610)・幅388", _at(market.get_node("%ExitButton"), Vector2(852, 610), 388))
	var meat_row: Button = stalls.get_child(0)
	c.check("張記：店名・強調の枠・「鍋の素 小%d杯 買った」" % int(s.prep_tiers()[0]["servings"]),
		meat_row.get_node("Name").text == "張記肉類加工" and meat_row.get_node("BoughtFrame").visible
			and meat_row.get_node("State").text == "鍋の素 小%d杯 買った" % int(s.prep_tiers()[0]["servings"]), meat_row.get_node("State").text)
	var produce_row: Button = stalls.get_child(1)
	c.check("青果：店名は永順青果・扱う品が出る・押せる", produce_row.get_node("Name").text == "永順青果"
		and produce_row.get_node("Wares").text != "" and not produce_row.disabled)

	# --- 5. 購入（ほかの店）---
	_press(produce_row)
	_sort(root)
	var shop: UiPaneBuyShop = root.pane_buy_shop
	c.check("店を押す → select_stall：右の枠は購入（ほかの店）・見出しは店名", s.market_shop == "produce"
		and _visible_pane(root) == shop and shop.get_node("%Header/Title").text == "永順青果")
	var goods: UiGoodsList = shop.get_node("%Goods")
	c.check("商品の行は shop_view の件数", goods.get_child_count() == s.shop_view("produce").size())
	c.check("商品の行：(852,151) 388×61", _near(goods.get_child(0).get_global_rect(), Rect2(852, 151, 388, 61)),
		str(goods.get_child(0).get_global_rect()))
	var first: Dictionary = s.shop_view("produce")[0]
	var row0: UiGoodsRow = goods.get_child(0)
	c.check("1行目：品名と「腐る」、2行目：個数・単価・在庫", row0.get_node("Tags/Name").text == str(first["label"])
		and row0.get_node("Tags/Rot").visible == Ingredients.is_perishable(str(first["item"]))
		and row0.get_node("Detail").text.begins_with("%d個 / 単価%d / 在庫" % [int(first["count"]), int(first["unit_price"])]))
	c.check("まだ買っていない店では「この店で買った」を出さない", not shop.get_node("%BoughtBox").visible)
	money_before = GameState.money
	var stock_before := GameState.fresh_count(str(first["item"]))
	_press(row0.get_node("BuyButton"))
	c.check("「かごに入れる」では買わない：所持金・在庫は変わらず、かごに入る・「使える」はかごの分を引いた額",
		GameState.money == money_before and GameState.fresh_count(str(first["item"])) == stock_before and root.cart.count("produce") == 1
			and shop.get_node("%Budget/Usable/Value").text == "¥%d" % (int(s.budget()["usable"]) - int(first["price"]))
			and shop.get_node("%CartBox/CartTotal").text == "合計 ¥%d" % int(first["price"]))
	_press(shop.get_node("%ConfirmButton"))
	c.check("「購入確定」→ buy_item：所持金が価格だけ減り、在庫が増える（かごは空になる・店に残る）",
		GameState.money == money_before - int(first["price"]) and GameState.fresh_count(str(first["item"])) >= int(first["count"])
			and root.cart.count("produce") == 0 and s.market_shop == "produce")
	c.check("「この店で買った」に品名と額が出る（UIだけの集計）", shop.get_node("%BoughtBox").visible
		and shop.get_node("%BoughtList").text == "%s ¥%d" % [str(first["label"]), int(first["price"])], shop.get_node("%BoughtList").text)
	_press(shop.get_node("%BackButton"))
	c.check("「店を出る」→ leave_shop：市場に戻り、青果に「¥%d 使った」" % int(first["price"]),
		s.market_shop == "" and _visible_pane(root) == market
			and produce_row.get_node("State").text == "¥%d 使った" % int(first["price"]), produce_row.get_node("State").text)

	# 張記に入り直す：追加購入の行が押せる・「店を出る」は leave_shop
	_press(meat_row)
	c.check("市場から張記に入ると、食肉仲卸の画面（鍋の素は買った状態）", _visible_pane(root) == meat and s.market_shop == "meat_wholesale"
		and tiers.get_child(0).get_node("BoughtFrame").visible)
	var meat_goods: UiGoodsList = meat.get_node("%Goods")
	c.check("鍋の素を買ったあとは、追加購入の「かごに入れる」を押せる（買えるもの）",
		(meat_goods.get_child(0).get_node("BuyButton") as Button).disabled == (not bool(s.shop_view("meat_wholesale")[0]["affordable"])))
	_press(back)
	c.check("市場の中の張記では「店を出る」= leave_shop", s.market_shop == "" and _visible_pane(root) == market)

	# 市場を出る
	_press(market.get_node("%ExitButton"))
	c.check("「市場を出る」→ exit_market：市場の画面を抜ける", not s.is_in_market())
	root.queue_free()

	# --- 6. Day1：前日が無い朝・追加購入の行は出さない ---
	GameState.reset_for_new_game()
	var root1: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root1)
	var s1: PlaySession = root1.session
	c.check("Day1の朝（前日が無い）：右の枠を出さずにスマホ（ニュース）から始める", root1.overlay == "phone"
		and root1.pane_phone.visible and root1.pane_phone.tab == "news" and not root1.pane_morning.visible)
	_press(root1.pane_phone.get_node("%CloseButton"))
	c.check("スマホを閉じると朝の画面：成績の箱は出さず「初日」の一文", root1.pane_morning.visible and not root1.pane_morning.get_node("%RecordBoxes").visible
		and root1.pane_morning.get_node("%NoRecord").visible and root1.pane_morning.get_node("%Header/Title").text == "朝")
	s1.flow.force_phase(GameState.Phase.PREP)
	c.check("Day1の食肉仲卸：追加購入の行は出さない", _visible_pane(root1) == root1.pane_buy_meat
		and not root1.pane_buy_meat.get_node("%GoodsScroll").visible)
	guard = 0
	while not s1.is_in_market() and guard < 60:
		guard += 1
		if s1.is_in_prep_tier():
			s1.choose_prep_tier("small")
		else:
			root1.left.advance()
	var day1_rows: VBoxContainer = root1.pane_market.get_node("%Stalls")
	var closed := 0
	for row in day1_rows.get_children():
		if (row as Button).disabled and row.visible:
			closed += 1
	c.check("Day1の市場：6店とも押せない（薄く）、張記は「買った」", s1.is_in_market() and closed == 6
		and day1_rows.get_child(0).get_node("State").text.ends_with("買った"), str(closed))
	c.check("Day1：閉まっている店は「今日は閉まっている」", day1_rows.get_child(1).get_node("State").text == "今日は閉まっている")
	root1.queue_free()
	return c.finish()
