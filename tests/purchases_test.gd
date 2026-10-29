extends RefCounted
## 収支の表示と最終日の注意（UI準備I）。表示だけ（判定・乱数・評判の式・チップは変えない）。
## 対象：仕入れ（市場・鍋の素・追加のだし・初日セット。運営費・場所代・水道代は含めない）／日次ログ（day_records・BALANCE_LOG）の purchases／
## 朝の「昨日の仕入れ」「昨日の収支」（売上−仕入れ−運営費。古い記録は帳簿のカテゴリから）／結果画面の仕入れ合計／最終日の市場の1行。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 仕入れの定義 ---
	var spend := { "market": 100, "prep": 110, "dashi": 16, "kit": 210, "daily_cost": 75, "rent": 90, "water": 50 }
	c.check("仕入れ＝市場＋鍋の素＋追加のだし＋初日セット（運営費・場所代・水道代は含めない）", PlaySession.purchases_from(spend) == 436 and PlaySession.purchases_from({}) == 0)

	# --- 2. 通しで遊ぶ（Day1）：日次ログ・朝の表示 ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		play.step()
	var rec: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	var day_spend: Dictionary = rec.get("spend_by_category", {})
	var expected := int(day_spend.get("market", 0)) + int(day_spend.get("prep", 0)) + int(day_spend.get("dashi", 0)) + int(day_spend.get("kit", 0))
	c.check("日次ログ（day_records）に purchases：Day1は初日セット＋鍋の素（運営費・場所代・水道代は入らない）", int(rec.get("purchases", -1)) == expected and expected > 0
		and int(day_spend.get("kit", 0)) > 0, "%s / %s" % [str(rec.get("purchases")), str(expected)])
	var log_text := FileAccess.get_file_as_string(BalanceLog.path) if FileAccess.file_exists(BalanceLog.path) else ""
	var last_line := ""
	for line in log_text.split("\n"):
		if line.strip_edges() != "":
			last_line = line
	var parsed = JSON.parse_string(last_line) if last_line != "" else null
	c.check("BALANCE_LOG（jsonl）にも purchases（追加のみ）", parsed is Dictionary and int((parsed as Dictionary).get("purchases", -1)) == expected, last_line.left(100))
	var morning: UiPaneMorning = root.pane_morning
	morning.refresh()
	var balance := int(rec["sale_total"]) - expected - int(day_spend.get("daily_cost", 0))
	var bills := int(day_spend.get("rent", 0)) + int(day_spend.get("water", 0))
	c.check("朝の「昨夜の成績」：「昨日の仕入れ ¥%d」" % expected, morning.get_node("%PurchaseLabel").text == "昨日の仕入れ ¥%d" % expected, morning.get_node("%PurchaseLabel").text)
	var balance_text: String = morning.get_node("%BalanceLabel").text
	c.check("「昨日の収支」＝売上（チップ込み）−仕入れ−運営費（Day1は場所代・水道代を別に添える）", balance_text.begins_with("昨日の収支 %s¥%d（売上 − 仕入れ − 運営費）" % ["+" if balance >= 0 else "−", absi(balance)])
		and (bills == 0 or morning.get_node("%Caption").text.contains("ほかに場所代・水道代 ¥%d" % bills)), balance_text)
	# 古い記録（purchases が無い）は帳簿のカテゴリから出す・赤字は「−」
	var old := rec.duplicate(true)
	old.erase("purchases")
	old["sale_total"] = 100
	old["spend_by_category"] = { "market": 250, "prep": 110, "daily_cost": 75 }
	GameState.day_records = [old]
	morning.refresh()
	c.check("古い記録（purchases なし）も帳簿のカテゴリから出す・赤字は「−」", morning.get_node("%PurchaseLabel").text == "昨日の仕入れ ¥360"
		and morning.get_node("%BalanceLabel").text.begins_with("昨日の収支 −¥335"), morning.get_node("%BalanceLabel").text)
	GameState.day_records = [rec]

	# --- 3. 結果画面の成績 ---
	var records: Array = [{ "day": 1, "purchases": 320, "spend_by_category": {} }, { "day": 2, "purchases": 384 }, { "day": 3, "spend_by_category": { "market": 100, "prep": 110 } }]
	var summary := Result.summarize(records, GameState.ledger, GameState.money)
	c.check("結果画面の成績：7日間の仕入れ合計（purchases の合計。無い日は帳簿のカテゴリから）の1行", int(summary["purchases"]) == 320 + 384 + 210
		and Result.format_report(summary).contains("仕入れ合計: ¥914"), Result.format_report(summary))

	# --- 4. 最終日の市場の1行 ---
	GameState.money = 1000
	s.notify_changed()
	_press(root.pane_market.get_node("%Stalls").get_child(3))
	var shop: UiPaneBuyShop = root.pane_buy_shop
	var day_before := GameState.day_count
	root.pane_market.refresh()
	shop.refresh()
	root.pane_buy_meat.refresh()
	var hidden_before: bool = not root.pane_market.get_node("%FinalNote").visible and not shop.get_node("%FinalNote").visible and not root.pane_buy_meat.get_node("%FinalNote").visible
	GameState.day_count = GameState.FINAL_DAY
	root.pane_market.refresh()
	shop.refresh()
	root.pane_buy_meat.refresh()
	var note := "今夜が最後の営業。残った材料は持ち越せない"
	c.check("最終日（Day7）の市場・店・張記に1行（「今夜が最後の営業。残った材料は持ち越せない」）。ほかの日は出ない",
		hidden_before and root.pane_market.get_node("%FinalNote").visible and root.pane_market.get_node("%FinalNote").text == note
			and shop.get_node("%FinalNote").visible and shop.get_node("%FinalNote").text == note
			and root.pane_buy_meat.get_node("%FinalNote").visible and root.pane_buy_meat.get_node("%FinalNote").text == note)
	c.check("店では1行ぶん、商品の一覧の上端が下がる（最終日だけ）", (shop.get_node("%Scroll") as Control).offset_top > 127.0)
	GameState.day_count = day_before
	shop.refresh()
	c.check("最終日でなければ元に戻る", not shop.get_node("%FinalNote").visible and is_equal_approx((shop.get_node("%Scroll") as Control).offset_top, 127.0))
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
