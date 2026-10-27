extends RefCounted
## 市場の買い物画面の配置（UI準備F3）。表示だけの変更の検証。
## 対象：「購入して店を出る」が無い／下段に「購入確定」「店を出る」が横に並ぶ／かごは空で1行・品が入ると最大3行まで伸びて、それ以上はかごの中で縦に送る／
## かごは下（ボタンの上）に寄り、あいた高さは商品の一覧に回る（一覧の下端＝かごの上−6）／全6店（張記を含む）で同じ配置／
## 商品の行が重ならず、一覧の枠の外に描かれない（clip_contents）。

const TOL := 3.0


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)


## 1つの買い物画面（pane）の配置を調べる。ok なら ""、だめなら理由。
func _check_pane(pane: Control, scroll_path: String) -> String:
	var origin := pane.get_global_rect().position
	var confirm: Button = pane.get_node("%ConfirmButton")
	var back: Button = pane.get_node("%BackButton")
	var cart: Control = pane.get_node("%CartBox")
	var scroll: ScrollContainer = pane.get_node(scroll_path)
	if pane.has_node("%ExitBuyButton"):
		return "「購入して店を出る」が残っている"
	var cr := confirm.get_global_rect()
	var br := back.get_global_rect()
	if absf(cr.position.x - (origin.x + 16.0)) > TOL or absf(cr.size.x - 190.0) > TOL or absf(cr.position.y - (origin.y + 616.0)) > TOL:
		return "購入確定の位置：%s" % str(cr)
	if absf(br.position.x - (origin.x + 214.0)) > TOL or absf(br.size.x - 190.0) > TOL or absf(br.position.y - cr.position.y) > TOL:
		return "店を出るの位置：%s" % str(br)
	var cart_r := cart.get_global_rect()
	if absf(cart_r.end.y - (origin.y + 588.0)) > TOL:
		return "かごの下端が動いた：%s" % str(cart_r)
	var sr := scroll.get_global_rect()
	if absf(sr.end.y - (cart_r.position.y - 6.0)) > TOL:
		return "一覧の下端がかごの上−6でない：%s／%s" % [str(sr), str(cart_r)]
	if not scroll.clip_contents:
		return "一覧の枠が外を切っていない（clip_contents）"
	return ""


func _rows_ok(goods: Control) -> String:
	var rows: Array = []
	for row in goods.get_children():
		if (row as Control).visible:
			rows.append((row as Control).get_global_rect())
	for i in range(rows.size() - 1):
		var gap: float = (rows[i + 1] as Rect2).position.y - (rows[i] as Rect2).end.y
		if gap < 5.0 or gap > 7.0:
			return "行%dと%dの間が%.1f（6のはず）" % [i, i + 1, gap]
		if (rows[i] as Rect2).intersects(rows[i + 1] as Rect2):
			return "行%dと%dが重なっている" % [i, i + 1]
	return ""


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var session: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while not (GameState.day_count == 2 and root.pane_buy_meat.visible and session.is_in_prep_tier()) and guard < 3000:
		guard += 1
		play.step()
	var meat: UiPaneBuyMeat = root.pane_buy_meat
	GameState.money = 1000   # かごに何品か入れられるように
	session.notify_changed()
	_sort(root)
	c.check("Day2の張記（鍋の素の選択）まで進んだ", meat.visible and session.is_in_prep_tier())
	# 文字の高さは headless と実機で違う（headless は大きい）ので、高さは「相対」で見る
	c.check("張記：配置（下段の2つ・かごは下・一覧の下端はかごの上）。鍋の素の3枚は 124×98（低くした）", _check_pane(meat, "%GoodsScroll") == ""
		and absf(meat.get_node("%Tiers").get_child(0).size.y - 98.0) <= TOL, _check_pane(meat, "%GoodsScroll"))
	var note: Label = meat.get_node("%WarnNote")
	c.check("張記：注意の一文はボタン段の上にある（購入確定の上端より上）", note.visible
		and note.get_global_rect().position.y < (meat.get_node("%ConfirmButton") as Button).get_global_rect().position.y)
	var empty_scroll_h: float = (meat.get_node("%GoodsScroll") as Control).size.y
	_press(meat.get_node("%Tiers").get_child(1))
	_press(meat.get_node("%ConfirmButton"))
	_sort(root)
	var goods: UiGoodsList = meat.get_node("%Goods")
	c.check("張記：商品の一覧は、前（118）より高い", (meat.get_node("%GoodsScroll") as Control).size.y > 118.0 + 40.0, str((meat.get_node("%GoodsScroll") as Control).size))
	var cart_h0: float = (meat.get_node("%CartBox") as Control).size.y
	for i in range(8):
		_press(goods.get_child(i % 4).get_node("BuyButton"))
	_sort(root)
	var cart_h1: float = (meat.get_node("%CartBox") as Control).size.y
	var cart_list: Label = meat.get_node("%CartBox/CartScroll/CartList")
	var line_h := cart_list.get_theme_font("font", "LabelSub").get_height(cart_list.get_theme_font_size("font_size", "LabelSub"))
	c.check("かごは空でも2行ぶん・品が入ると最大3行まで伸びる・下端は動かず、一覧の下端がそれに合わせて縮む", cart_h1 >= cart_h0 and cart_h1 <= cart_h0 + 1.0 * line_h + 2.0
		and _check_pane(meat, "%GoodsScroll") == "" and (meat.get_node("%GoodsScroll") as Control).size.y < empty_scroll_h + 1.0, "%s %s %s" % [cart_h0, cart_h1, _check_pane(meat, "%GoodsScroll")])
	c.check("商品の行は重ならない（間隔6）", _rows_ok(goods) == "", _rows_ok(goods))
	# 4行以上になる中身：かごの中で縦に送る（枠は3行より伸びない）
	meat.get_node("%CartBox").show_cart([
		{ "label": "あああああああああああああああ", "qty": 1, "price": 10 }, { "label": "いいいいいいいいいいいいいいい", "qty": 1, "price": 10 },
		{ "label": "ううううううううううううううう", "qty": 1, "price": 10 }, { "label": "ええええええええええええええ", "qty": 1, "price": 10 },
		{ "label": "おおおおおおおおおおおおおお", "qty": 1, "price": 10 }, { "label": "かかかかかかかかかかかかかか", "qty": 1, "price": 10 },
		{ "label": "ききききききききききききき", "qty": 1, "price": 10 }], 70)
	_sort(root)
	c.check("かごの中身が4行を超えても枠は3行まで（それ以上は中で縦に送る）", (meat.get_node("%CartBox") as Control).size.y <= cart_h0 + 1.0 * line_h + 2.0
		and (meat.get_node("%CartBox/CartScroll") as ScrollContainer).size.y < cart_list.get_minimum_size().y + 0.5, "%s %s" % [(meat.get_node("%CartBox") as Control).size, cart_list.get_minimum_size()])
	_press(meat.get_node("%CartBox/ClearButton"))
	_press(meat.get_node("%BackButton"))
	guard = 0
	while not root.pane_market.visible and guard < 3000:
		guard += 1
		play.step()

	# --- 全6店（張記を含む）で同じ配置 ---
	GameState.money = 1000
	session.notify_changed()
	var stalls: Control = root.pane_market.get_node("%Stalls")
	var seen := 0
	var all_ok := true
	var detail := ""
	for i in range(stalls.get_child_count()):
		var stall: Button = stalls.get_child(i)
		if not stall.visible or stall.disabled:
			continue
		_press(stall)
		_sort(root)
		var pane: Control = root.pane_buy_shop if root.pane_buy_shop.visible else (root.pane_buy_meat if root.pane_buy_meat.visible else null)
		if pane == null:
			all_ok = false
			detail = "店%dに入れない" % i
			break
		seen += 1
		var scroll_path := "%GoodsScroll" if pane == root.pane_buy_meat else "%Scroll"
		var why := _check_pane(pane, scroll_path)
		if why == "":
			why = _rows_ok(pane.get_node("%Goods"))
		if why != "":
			all_ok = false
			detail = "店%d：%s" % [i, why]
		_press(pane.get_node("%BackButton"))
	c.check("市場の全%d店で同じ配置（下段に購入確定・店を出る／かごは下／一覧は広い／行は重ならない）" % seen, all_ok and seen == 6, detail)
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
