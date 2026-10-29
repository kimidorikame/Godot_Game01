extends RefCounted
## 持ち物パネル・日次ログの在庫と仕入れ・余り在庫・客ノートの前回の材料（UI準備I2）。表示とログだけ（判定・乱数・評判の式・チップは変えない）。
## 対象：inventory_view（在庫が1つ以上の材料・味と具の分け・新鮮／傷・性質の点灯／半点灯／暗い・最終日）／パネルの表示（朝・市場・準備に出る・ログで隠れる・営業中は出ない・
## 立ち絵が出ない場面は広く／出る場面は左右2列・内部名なし）／日次ログの purchase_items・closing_stock・BALANCE_LOG／結果画面の「余り在庫」／
## 客ノートの「前回の材料」／スマホのタブは3つ。


func _label_texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_label_texts(child, out)
	return out


func _add_damaged(item: String, count: int) -> void:
	GameState.inventory[item] = int(GameState.inventory.get(item, 0)) + count
	var batches: Array = GameState.perishable_batches.get(item, [])
	batches.push_front({ "day": GameState.day_count - 2, "count": count, "unit_price": 8 })
	GameState.perishable_batches[item] = batches


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. inventory_view ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var s0 := PlaySession.new()
	t.root.add_child(s0)
	s0.start()
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("nam_prik_pao", 3)
	GameState.add_inventory("meat_ball", 2)
	GameState.add_inventory("tofu", 1)
	_add_damaged("tofu", 2)
	GameState.add_inventory("shrimp", 0)
	GameState.add_inventory("soup_base", 1)   # 鍋の素は椀に入れる材料ではないので出さない
	var view := s0.inventory_view()
	var flavor_ids: Array = (view["flavors"] as Array).map(func(r): return str(r["id"]))
	var topping_ids: Array = (view["toppings"] as Array).map(func(r): return str(r["id"]))
	c.check("在庫が1つ以上の材料だけ・味（調味料）と具で分ける・定義順", flavor_ids == ["nam_prik_pao"] and topping_ids == ["meat_ball", "tofu"], "%s / %s" % [str(flavor_ids), str(topping_ids)])
	var tofu: Dictionary = (view["toppings"] as Array)[1]
	c.check("新鮮／傷の内訳（豆腐：新鮮1・傷2）・短い名前・札のタグ", int(tofu["fresh"]) == 1 and int(tofu["damaged"]) == 2 and str(tofu["name"]) == UiLabels.short_name("tofu") and tofu["tags"] == ["GENTLE"])
	var states := {}
	for entry in view["traits"]:
		states[str(entry["tag"])] = str(entry["state"])
	c.check("性質の点灯：持っている＝lit（辛い・スタミナ・やさしい）・無い＝dark", states["HOT"] == "lit" and states["POWER"] == "lit" and states["GENTLE"] == "lit" and states["SOUR"] == "dark" and states.size() == 10)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	_add_damaged("tofu", 2)
	view = s0.inventory_view()
	states = {}
	for entry in view["traits"]:
		states[str(entry["tag"])] = str(entry["state"])
	c.check("傷んだ在庫だけの性質は半点灯（half）", states["GENTLE"] == "half" and states["HOT"] == "dark")
	c.check("最終日だけ final_day", not bool(view["final_day"]))
	GameState.day_count = GameState.FINAL_DAY
	c.check("最終日は final_day（見出しに「残った分は持ち越せない」）", bool(s0.inventory_view()["final_day"]))
	GameState.day_count = 3
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	c.check("在庫が無いと、どちらの一覧も空・性質は全部 dark", (s0.inventory_view()["flavors"] as Array).is_empty() and (s0.inventory_view()["toppings"] as Array).is_empty()
		and (s0.inventory_view()["traits"] as Array).all(func(e): return e["state"] == "dark"))

	# --- 2. 客ノートの「前回の材料」---
	GameState.day_count = 3
	GameState.customer_memory["thug"] = { "favorite_known": false, "facts": {}, "seen_episodes": [], "visits": [
		{ "day": 1, "slot": "夜半", "served": 1, "grade": "GOOD", "grades": ["GOOD"], "ingredients": [["coconut_milk", "tofu"]], "episode_id": "" }] }
	GameState.customer_memory["officer"] = { "favorite_known": false, "facts": {}, "seen_episodes": [], "visits": [
		{ "day": 2, "slot": "宵の口", "served": 0, "grade": "", "grades": [], "ingredients": [], "episode_id": "" }] }
	var notes := s0.phone_notes()
	var by_id := {}
	for r in notes["regulars"]:
		by_id[str(r["id"])] = r
	c.check("前回の材料：前回の記録がある客だけ（来たが出さなかった客は空）", by_id["thug"]["usual_ingredients"] == ["ココナッツミルク", "豆腐"] and (by_id["officer"]["usual_ingredients"] as Array).is_empty(), str(by_id))
	s0.free()

	# --- 3. 通しで遊ぶ：パネルの表示・日次ログ ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var shown_phases := {}
	var shown_in_open := false
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		play.step()
		var panel: UiInventoryPanel = root.left.get_node("%InventoryPanel")
		if GameState.phase == GameState.Phase.OPEN and panel.visible:
			shown_in_open = true
		if panel.visible:
			shown_phases[GameState.phase] = true
	c.check("持ち物パネルは朝・準備（市場を含む）に出て、営業中は出ない", shown_phases.has(GameState.Phase.WAKE) and shown_phases.has(GameState.Phase.PREP) and not shown_in_open, str(shown_phases))
	var panel: UiInventoryPanel = root.left.get_node("%InventoryPanel")
	GameState.money = 1000
	s.notify_changed()
	root.left.refresh()
	var in_market_visible := panel.visible
	var wide_layout: bool = (panel.get_node("%ListPanel") as Control).size.x > 500.0 and (panel.get_node("%TraitsPanel") as Control).position.x < 600.0
	var texts := _label_texts(panel)
	c.check("市場（立ち絵が出ない場面）：左の領域を広く使う（材料の一覧と性質チェックが横に並ぶ）・見出しと札は言葉・内部名なし",
		in_market_visible and wide_layout and texts.has("持ち物") and texts.has("性質チェック") and texts.has("味（調味料）") and texts.has("具")
			and not texts.any(func(x): return str(x).contains("HOT") or str(x).contains("POWER") or str(x).contains("GENTLE")), str(texts.slice(0, 12)))
	var chips := 0
	for node in panel.get_node("%TraitsContent").get_children():
		for chip in node.get_children():
			if chip.has_meta("state"):
				chips += 1
	c.check("性質チェック：10の札が並ぶ", chips == 10, str(chips))
	root.left.toggle_log()
	c.check("ログを開いたら隠す", not panel.visible)
	root.left.close_log()
	root.left.refresh()
	panel.refresh(s, false)
	c.check("立ち絵が出る場面（狭い配置）：材料は左の列（幅180）・性質チェックは右の列（立ち絵を避ける）",
		is_equal_approx((panel.get_node("%ListPanel") as Control).size.x, 180.0) and (panel.get_node("%TraitsPanel") as Control).position.x >= 590.0 and (panel.get_node("%TraitsPanel") as Control).size.x <= 190.0)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("nam_prik_pao", 1)
	GameState.add_inventory("meat_ball", 2)
	panel.refresh(s, false)
	var narrow_texts := _label_texts(panel.get_node("%ListPanel"))
	c.check("狭い配置も、味と具の両方の行が出る（1つの列に見出しつきで並ぶ）", narrow_texts.has("味（調味料）") and narrow_texts.has("具") and narrow_texts.has(UiLabels.short_name("nam_prik_pao"))
		and narrow_texts.has(UiLabels.short_name("meat_ball")) and narrow_texts.has("×2"), str(narrow_texts))
	# 品数が多いと縦に送れる（あふれるときだけホイールを受ける）
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in Ingredients._TAGS:
		GameState.add_inventory(str(id), 2)
	panel.refresh(s, false)
	var many_scrolls: bool = (panel.get_node("%ListScroll") as ScrollContainer).mouse_filter == Control.MOUSE_FILTER_STOP
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("nam_prik_pao", 1)
	panel.refresh(s, false)
	c.check("17品ぜんぶ持っていると縦に送れる（ホイールを受ける）／少ないときは受けない（会話を進めるクリックを塞がない）",
		many_scrolls and (panel.get_node("%ListScroll") as ScrollContainer).mouse_filter == Control.MOUSE_FILTER_IGNORE)

	var rec: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	var items: Dictionary = rec.get("purchase_items", {})
	var amount_sum := 0
	for key in items:
		amount_sum += int((items[key] as Dictionary).get("amount", 0))
	c.check("日次ログ purchase_items：その日に買った品目ごとの個数と額（Day1＝初日セットの品目＋鍋の素）。額の合計は仕入れと同じ", not items.is_empty()
		and amount_sum == int(rec.get("purchases", -1)) and items.keys().any(func(k): return str(k).begins_with("prep:")), "%d / %s" % [amount_sum, str(rec.get("purchases"))])
	var stock: Dictionary = rec.get("closing_stock", {})
	var value_ok := not stock.is_empty()
	for id in stock:
		var entry: Dictionary = stock[id]
		value_ok = value_ok and int(entry["value"]) == roundi(PlaySession.unit_price_of(str(id)) * (int(entry["fresh"]) + int(entry["damaged"])))
	c.check("日次ログ closing_stock：品目ごとの個数・新鮮と傷の内訳・評価額（＝単価×個数）", value_ok and PlaySession.stock_value_of(stock) > 0, str(stock).left(200))
	c.check("単価は市場のいちばん大きい袋の 値段÷個数（モツ10・海老18・濃縮だし16）", is_equal_approx(PlaySession.unit_price_of("offal"), 10.0)
		and is_equal_approx(PlaySession.unit_price_of("shrimp"), 18.0) and is_equal_approx(PlaySession.unit_price_of("dashi"), 16.0))
	var log_text := FileAccess.get_file_as_string(BalanceLog.path) if FileAccess.file_exists(BalanceLog.path) else ""
	var last_line := ""
	for line in log_text.split("\n"):
		if line.strip_edges() != "":
			last_line = line
	var parsed = JSON.parse_string(last_line) if last_line != "" else null
	c.check("BALANCE_LOG（jsonl）にも purchase_items・closing_stock（追加のみ）", parsed is Dictionary and (parsed as Dictionary).has("purchase_items") and (parsed as Dictionary).has("closing_stock"), last_line.left(100))

	# --- 4. 結果画面の「余り在庫」 ---
	var records: Array = [{ "day": 1, "closing_stock": { "offal": { "fresh": 5, "damaged": 0, "value": 50 } } }, { "day": 2, "closing_stock": { "tofu": { "fresh": 1, "damaged": 2, "value": 24 }, "shrimp": { "fresh": 1, "damaged": 0, "value": 18 } } }]
	var summary := Result.summarize(records, GameState.ledger, GameState.money)
	c.check("結果画面の成績：「余り在庫 ¥xxx（評価額。目標には含めない）」＝最終日の閉店時の在庫の評価額", int(summary["closing_stock_value"]) == 42
		and Result.format_report(summary).contains("余り在庫 ¥42（評価額。目標には含めない）"), Result.format_report(summary))
	c.check("余り在庫は目標（現金＋修繕）に入らない", int(summary["cash_plus_repair"]) == GameState.money + int(summary["repair_paid"]))
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
