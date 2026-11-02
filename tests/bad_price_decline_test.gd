extends RefCounted
## BAD の売価と、断った杯の評判の点（UI準備N）。BAD の杯は 20円（economy.bad_price。材料は減る・チップは 0）、GREAT・GOOD・OK は 45円のまま。
## プレイヤーが「断る」を選んだ杯（unserved_declined）は、当夜品質Qの平均に 5点（economy.declined_score）で入る（材料は減らない）。
## 鍋切れ・素材不足で出せなかった杯・来られなかった客の杯は 0点のまま。評判の式そのもの・判定・乱数は変えない。


func _units() -> int:
	var total := 0
	for id in GameState.inventory:
		total += GameState.fresh_count(str(id)) + GameState.damaged_count(str(id))
	return total


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. データ・売価・点の計算 ---
	Rules.clear_cache()
	c.check("規則データ：economy.bad_price＝20・economy.declined_score＝5（定価は45のまま）",
		Rules.bad_price() == 20 and Rules.declined_score() == 5 and Rules.price_per_serving() == 45)
	c.check("ゲーム本体の既定値は規則データと同じ（試遊は既定で BAD＝定価・断った杯＝0点に差し替える）",
		GameState.BAD_PRICE == 20 and GameState.DECLINED_SCORE == 5)
	c.check("売価：BAD は 20円・GREAT・GOOD・OK は 45円（杯数ぶん）", GameState.price_for("BAD", 1) == 20 and GameState.price_for("BAD", 3) == 60
		and GameState.price_for("GREAT", 1) == 45 and GameState.price_for("GOOD", 2) == 90 and GameState.price_for("OK", 1) == 45 and GameState.price_for("", 1) == 45)
	c.check("BAD のチップは 0 のまま", GameState.tip_for("BAD", 1) == 0)
	var probe: PlaySession = load("res://scripts/play_session.gd").new()
	c.check("断った杯は 1杯 5点で Q の平均に入る（GOOD1杯＋断った1杯／予定3杯 ＝ 80÷3）",
		is_equal_approx(probe.quality_score({ "GOOD": 1 }, 3, 1), 80.0 / 3.0) and is_equal_approx(probe.quality_score({ "GOOD": 1 }, 3), 75.0 / 3.0))
	probe.log_unserved = { "ingredients": 2, "pot": 1, "declined": 0 }
	c.check("素材不足・鍋切れで出せなかった杯は、断った杯に数えない（0点）", probe.declined_judged_cups() == 0)
	probe.log_unserved = { "ingredients": 2, "pot": 1, "declined": 2 }
	probe.log_declined_unjudged = 1
	c.check("断った杯のうち判定しない杯（judge:false）は点を付けない（Q の分母と揃える）", probe.declined_judged_cups() == 1)
	probe.free()
	GameState.BAD_PRICE = 45
	GameState.DECLINED_SCORE = 0
	var old := load("res://scripts/play_session.gd").new() as PlaySession
	c.check("値を 45 と 0 に戻すと今までと同じ（BAD も 45円・断った杯は 0点）", GameState.price_for("BAD", 2) == 90
		and is_equal_approx(old.quality_score({ "GOOD": 1, "BAD": 1 }, 4, 2), old.quality_score({ "GOOD": 1, "BAD": 1 }, 4)))
	old.free()
	GameState.BAD_PRICE = Rules.bad_price()
	GameState.DECLINED_SCORE = Rules.declined_score()

	# --- 2. 通しで遊ぶ（Day1）：BAD の提供と、名前あり客を1人断る ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var last_key := ""
	var start_units := -1
	var start_money := 0
	var start_key := ""
	var bad_seen := 0
	var bad_ok := true
	var bad_line := ""
	var other_ok := true
	var declined_key := ""
	var declined_cups := 0
	var declined_units_ok := false
	var declined_money_ok := false
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		var key := "%d|%d" % [s.open.slot_index, s.open.index] if s.open != null else ""
		if s.open != null and s.is_choosing_ingredients() and (s.open.current_bowl.get("additions", []) as Array).is_empty() and start_key != key:
			start_key = key
			start_units = _units()
			start_money = GameState.money
			# 名前あり客を1人だけ、何も入れずに断る（出せる在庫はある＝「断った」）
			if declined_key == "" and s.can_decline() and not s.is_current_mob_order():
				declined_key = key
				declined_cups = s.current_servings()
				s.decline_customer()
		play.step()
		var line := s.current_line()
		if str(line.get("type", "")) != "REACT" or s.open == null or key != start_key or last_key == key:
			continue
		last_key = key
		if key == declined_key:
			declined_units_ok = _units() == start_units
			declined_money_ok = GameState.money == start_money
			continue
		if s.declined_now:
			continue
		var bowl: Dictionary = s.open.current_bowl
		var grade := str(bowl.get("result", ""))
		var used := start_units - _units()
		var got := GameState.money - start_money
		if grade == "BAD":
			bad_seen += 1
			var cups := int(s.last_serve_bad_sale / 20)
			if cups < 1 or s.last_serve_bad_sale != 20 * cups or got != 20 * cups or used != (bowl.get("additions", []) as Array).size() * cups:
				bad_ok = false
			if bad_line == "":
				bad_line = str(line["text"])
		elif grade in ["GREAT", "GOOD", "OK"]:
			if s.last_serve_bad_sale != 0 or (got - s.last_serve_tip) % 45 != 0 or got - s.last_serve_tip <= 0:
				other_ok = false
	var rec: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	var counts: Dictionary = rec.get("quality_counts", {})
	c.check("Day1を遊べた（BAD の杯があり、名前あり客を1人断った）", bad_seen > 0 and declined_key != "", "BAD %d回・断った %s" % [bad_seen, declined_key])
	c.check("BAD の杯：売上は 20円×杯数（チップ 0）・材料は入れた分だけ減る", bad_ok)
	c.check("BAD を出したときの反応の文に「売上 ¥20」を添える", bad_line.contains("売上 ¥20"), bad_line)
	c.check("GREAT・GOOD・OK の杯：売上は 45円×杯数（＋チップ）", other_ok)
	c.check("断った杯：材料は減らない・売上は 0", declined_units_ok and declined_money_ok)
	var expected_sale: int = (int(rec.get("served_cups", 0)) - int(counts.get("BAD", 0))) * 45 + int(counts.get("BAD", 0)) * 20 + int(rec.get("tips", 0))
	c.check("日の売上（昨夜の成績・夜の結果）は BAD を 20円で数えた合計", int(rec.get("sale_total", -1)) == expected_sale, "%s / %d" % [str(rec.get("sale_total")), expected_sale])
	var pane_morning: UiPaneMorning = root.pane_morning
	pane_morning.refresh()
	c.check("朝の「昨夜の成績」の売上も同じ値", pane_morning.get_node("%SalesValue").text == "¥%d" % expected_sale, pane_morning.get_node("%SalesValue").text)
	var base_total := 0
	for grade in PlaySession.REPUTATION_SCORE:
		base_total += int(PlaySession.REPUTATION_SCORE[grade]) * int(counts.get(grade, 0))
	var judged := int(rec.get("judged_planned_cups", 0))
	c.check("日次ログ：断った杯は unserved_declined（素材・鍋とは別）", int(rec.get("unserved_declined", 0)) == declined_cups and declined_cups > 0,
		"%s / %d" % [str(rec.get("unserved_declined")), declined_cups])
	c.check("当夜品質Q＝（評価の点＋断った杯×5）÷予定杯数（素材不足・鍋切れ・来られなかった杯は 0点）",
		judged > 0 and is_equal_approx(float(rec.get("quality", -1.0)), float(base_total + 5 * int(rec.get("unserved_declined", 0))) / float(judged)),
		"%s / %s" % [str(rec.get("quality")), str(float(base_total + 5 * int(rec.get("unserved_declined", 0))) / float(maxi(judged, 1)))])
	c.check("評判の式はそのまま（次の評判＝評判×0.7＋Q×0.3 の丸め。GameState.settle_reputation）",
		int(rec.get("closing_reputation", -1)) == roundi(float(rec.get("opening_reputation", 0)) * 0.7 + float(rec.get("quality", 0.0)) * 0.3),
		"%s→%s Q=%s" % [str(rec.get("opening_reputation")), str(rec.get("closing_reputation")), str(rec.get("quality"))])
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
