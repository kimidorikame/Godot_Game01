extends RefCounted
## チップ（UI準備H2）。提供した杯の評価に応じて、定価（全評価で同じ）に加えて受け取る：GREAT +10・GOOD +5・OK 0・BAD 0（data/campaigns/week7.json の economy.tips）。
## 評判の増減・判定・SaleRule は変えない。対象：データと受け取り額（評価ごと・杯数ぶん）／定価はそのまま（BAD も受け取る）／日の合計（売上に含み、うちチップを別に持つ）／
## 日次ログ（day_records・BALANCE_LOG）に tips／保存・復元（朝の封筒）／表示（夜の結果・昨夜の成績・結果画面の成績・提供直後の文）／値をデータで変えられる。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. データと受け取り額 ---
	Rules.clear_cache()
	var tips := Rules.tips()
	c.check("規則データ：GREAT +10・GOOD +5（OK・BAD は書かない＝0）", tips == { "GREAT": 10, "GOOD": 5 }, str(tips))
	c.check("ゲーム本体の既定値は規則データと同じ（試遊は既定で 0 に差し替える）", GameState.TIPS == tips)
	c.check("定価は45のまま・全評価で同じ", GameState.PRICE_PER_SERVING == 45)
	c.check("評価ごとの受け取り額：GREAT 10・GOOD 5・OK 0・BAD 0・評価なし 0", GameState.tip_for("GREAT", 1) == 10 and GameState.tip_for("GOOD", 1) == 5
		and GameState.tip_for("OK", 1) == 0 and GameState.tip_for("BAD", 1) == 0 and GameState.tip_for("", 1) == 0)
	c.check("杯数ぶん（団体・複数杯）：GOOD 3杯＝15・GREAT 2杯＝20・0杯＝0", GameState.tip_for("GOOD", 3) == 15 and GameState.tip_for("GREAT", 2) == 20 and GameState.tip_for("GREAT", 0) == 0)
	var saved: Dictionary = GameState.TIPS
	GameState.TIPS = { "GOOD": 7 }
	c.check("値はデータで変えられる（GOOD 7・GREAT なし）", GameState.tip_for("GOOD", 2) == 14 and GameState.tip_for("GREAT", 2) == 0)
	GameState.TIPS = {}
	c.check("チップなし（空）なら全評価 0＝定価だけ", GameState.tip_for("GREAT", 5) == 0)
	GameState.TIPS = saved

	# --- 2. 通しで遊ぶ（Day1）：受け取り・日の合計・日次ログ・表示 ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var shown_tip_line := ""
	var tip_seen := 0
	var close_label_ok := false
	var records_ok := true
	var records_seen := 0
	var bad_or_ok_seen := false
	var records_checked := false
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		play.step()
		var line := s.current_line()
		if str(line.get("type", "")) == "REACT" and s.last_serve_tip > 0 and shown_tip_line == "":
			shown_tip_line = str(line["text"])
			tip_seen = s.last_serve_tip
		if GameState.phase == GameState.Phase.CLOSE and not records_checked:
			records_checked = true
			for served in GameState.served:
				var servings := int(served.get("servings", 0))
				if servings <= 0:
					continue
				records_seen += 1
				var results: Dictionary = served.get("results", {})
				var single := str(served.get("result", ""))
				if single != "":
					results = { single: servings }
				var want_tip := 0
				for grade in results:
					want_tip += GameState.tip_for(str(grade), int(results[grade]))
					bad_or_ok_seen = bad_or_ok_seen or grade == "BAD" or grade == "OK"
				if int(served.get("sale", 0)) - int(served.get("tip", 0)) != servings * 45 or int(served.get("tip", 0)) != want_tip:
					records_ok = false
		if GameState.phase == GameState.Phase.CLOSE and root.pane_close.visible and not close_label_ok:
			var shown_tips: int = int(s.tonight_result()["tips"])
			close_label_ok = (root.pane_close.get_node("%TipLabel").visible == (shown_tips > 0)) \
				and (shown_tips == 0 or root.pane_close.get_node("%TipLabel").text == "うちチップ ¥%d" % shown_tips) \
				and root.pane_close.get_node("%SalesValue").text == "¥%d" % int(s.tonight_result()["sales"])
	var rec: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	var counts: Dictionary = rec.get("quality_counts", {})
	var expected_tips: int = int(counts.get("GREAT", 0)) * 10 + int(counts.get("GOOD", 0)) * 5
	c.check("Day1を遊べた（評価のある杯がある）", not rec.is_empty() and int(counts.get("GREAT", 0)) + int(counts.get("GOOD", 0)) + int(counts.get("OK", 0)) + int(counts.get("BAD", 0)) > 0, str(counts))
	c.check("日の合計：チップ＝GREAT×10＋GOOD×5（日次ログ day_records の tips）", int(rec.get("tips", -1)) == expected_tips and expected_tips > 0, "%s / %s" % [str(rec.get("tips")), str(expected_tips)])
	c.check("売上（sale_total）は定価×提供杯数＋チップ（チップを含む）", int(rec.get("sale_total", 0)) == int(rec.get("served_cups", 0)) * 45 + expected_tips,
		"%s / %s" % [str(rec.get("sale_total")), str(int(rec.get("served_cups", 0)) * 45 + expected_tips)])
	c.check("どの提供記録も、売上－チップ＝定価×杯数（BAD・OK も定価は受け取る。チップは GREAT・GOOD の杯だけ）", records_ok and records_seen > 0 and bad_or_ok_seen, "%d件" % records_seen)
	c.check("夜の結果の画面：売上の横に「うちチップ ¥xx」（チップがあるときだけ）・売上はチップ込み", close_label_ok)
	c.check("提供の直後の文に「+¥5」「+¥10」を添える（チップが出たときだけ）", shown_tip_line.ends_with("+¥%d" % tip_seen) and tip_seen in [5, 10], shown_tip_line)
	# 日次ログ（BALANCE_LOG の jsonl）にも tips
	var log_text := FileAccess.get_file_as_string(BalanceLog.path) if FileAccess.file_exists(BalanceLog.path) else ""
	var last_line := ""
	for line in log_text.split("\n"):
		if line.strip_edges() != "":
			last_line = line
	var parsed = JSON.parse_string(last_line) if last_line != "" else null
	c.check("日次ログ（BALANCE_LOG）に tips が入る", parsed is Dictionary and int((parsed as Dictionary).get("tips", -1)) == expected_tips, last_line.left(120))
	# Day2の朝：昨夜の成績
	var pane_morning: UiPaneMorning = root.pane_morning
	pane_morning.refresh()
	c.check("朝の「昨夜の成績」：売上の横に「うちチップ ¥%d」" % expected_tips, pane_morning.get_node("%TipLabel").visible
		and pane_morning.get_node("%TipLabel").text == "うちチップ ¥%d" % expected_tips and pane_morning.get_node("%SalesValue").text == "¥%d" % int(rec["sale_total"]))
	c.check("前日成績の文にも「（うちチップ n）」が出る", s.format_day_summary(rec).contains("（うちチップ %d）" % expected_tips), s.format_day_summary(rec))

	# --- 3. 結果画面の成績・保存と復元 ---
	var summary := Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
	c.check("結果画面の成績：チップ合計の1行（summarize の tips・format_report）", int(summary["tips"]) == expected_tips and Result.format_report(summary).contains("チップ合計: ¥%d" % expected_tips))
	var envelope: Dictionary = MorningSave.capture("")
	GameState.day_records = []
	MorningSave.apply(envelope)
	var restored: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	c.check("保存・復元（朝の封筒）：日次ログの tips が戻る（再挑戦・続きから）", int(restored.get("tips", -1)) == expected_tips and int(Result.summarize(GameState.day_records, GameState.ledger, GameState.money)["tips"]) == expected_tips)

	# --- 4. 評判・定価は変えない ---
	var same_quality := Dictionary(counts)
	c.check("評判の式は変わらない（品質＝評価の点数の平均。チップは入らない）",
		is_equal_approx(s.quality_score(same_quality, int(rec.get("judged_planned_cups", 1))), float(rec.get("quality", -1.0))))
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
