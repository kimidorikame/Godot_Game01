extends RefCounted
## 具だくさんのチップ（UI準備L）。具の材料が2種類（違う材料）入っていて、評価（減点で下がったあとの評価）が GOOD 以上の丼に、1杯ごとにチップ +10
## （data/campaigns/week7.json の economy.hearty_tip。0 で無効）。味1・具1のチップ（GOOD +5・GREAT +10）・評判の式・判定・乱数は変えない。
## 対象：規則（具2種類＋GOOD・GREAT で +10／OK 以下・同じ材料2つ・札2つの材料1つ・値0 は対象外）／提供の記録と反応の文／
## 日次ログ（day_records・BALANCE_LOG）の hearty_tips・hearty_cups／結果画面の「うち具だくさん」の1行。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. データ ---
	Rules.clear_cache()
	c.check("規則データ：economy.hearty_tip＝10", Rules.hearty_tip() == 10, str(Rules.hearty_tip()))
	c.check("ゲーム本体の既定値は規則データと同じ（試遊は既定で 0 に差し替える）", GameState.HEARTY_TIP == 10)
	c.check("味1・具1のチップは変えない（GREAT +10・GOOD +5）", Rules.tips() == { "GREAT": 10, "GOOD": 5 })

	# --- 2. 規則（判定 Judge の評価から） ---
	var soup := { "strength": 3, "remaining_servings": 10 }
	var two := ["herbal_sauce", "rice_noodle", "dried_wood_ear"]   # 味1・具2種類（米麺 FILLING・乾燥きくらげ BITE）
	var order := { "wanted_tags": ["SAVORY", "FILLING"], "favorite": "" }
	var good := str(Judge.grade({ "additions": two }, soup, order)["grade"])
	c.check("具2種類＋GOOD：具だくさん +10（チップは GOOD 5＋10＝15）", good == "GOOD" and GameState.hearty_tip_for(good, 1, two) == 10
		and GameState.tip_for(good, 1) + GameState.hearty_tip_for(good, 1, two) == 15, good)
	var great := str(Judge.grade({ "additions": two }, soup, { "wanted_tags": ["SAVORY", "FILLING"], "favorite": "dried_wood_ear" })["grade"])
	c.check("具2種類＋GREAT：具だくさん +10（チップは GREAT 10＋10＝20）", great == "GREAT" and GameState.hearty_tip_for(great, 1, two) == 10
		and GameState.tip_for(great, 1) + GameState.hearty_tip_for(great, 1, two) == 20, great)
	var spoiled := str(Judge.grade({ "additions": two, "used_spoiled": true }, soup, order)["grade"])
	c.check("具2種類でも、傷みで OK に下がった丼には足さない（下がったあとの評価で決める）", spoiled == "OK" and GameState.hearty_tip_for(spoiled, 1, two) == 0, spoiled)
	var thin := str(Judge.grade({ "additions": two }, { "strength": GameState.STRENGTH_MIN, "remaining_servings": 10 }, order)["grade"])
	c.check("具2種類でも、薄さで OK に下がった丼には足さない", thin == "OK" and GameState.hearty_tip_for(thin, 1, two) == 0, thin)
	var one_match := str(Judge.grade({ "additions": two }, soup, { "wanted_tags": ["HOT", "FILLING"], "favorite": "" })["grade"])
	c.check("具2種類＋OK（一致1つ）：0", one_match == "OK" and GameState.hearty_tip_for(one_match, 1, two) == 0 and GameState.hearty_tip_for("BAD", 1, two) == 0, one_match)
	var same := ["herbal_sauce", "rice_noodle", "rice_noodle"]
	c.check("同じ材料を2つ（米麺×2）は具2種類に数えない：0", str(Judge.grade({ "additions": same }, soup, order)["grade"]) == "GOOD"
		and Ingredients.topping_kinds(same) == 1 and GameState.hearty_tip_for("GOOD", 1, same) == 0)
	var tendon := ["nam_prik_pao", "tendon_meat"]   # 牛すじ＝札が2つ（POWER・BITE）の材料1つ
	c.check("札が2つある材料1つ（牛すじ）は具1種類：0", Ingredients.topping_kinds(tendon) == 1 and GameState.hearty_tip_for("GOOD", 1, tendon) == 0)
	c.check("味の材料は具に数えない（調味料2つ＋具1つ＝具1種類）", Ingredients.topping_kinds(["herbal_sauce", "nam_prik_pao", "rice_noodle"]) == 1)
	c.check("味1・具1の丼：0（チップは GOOD 5・GREAT 10 のまま）", GameState.hearty_tip_for("GREAT", 1, ["herbal_sauce", "rice_noodle"]) == 0)
	c.check("杯数ぶん（団体3杯）：30", GameState.hearty_tip_for("GOOD", 3, two) == 30)
	GameState.HEARTY_TIP = 0
	c.check("値 0 で無効（具2種類＋GREAT でも 0）", GameState.hearty_tip_for("GREAT", 1, two) == 0 and GameState.hearty_tip_for("GOOD", 3, two) == 0)
	GameState.HEARTY_TIP = Rules.hearty_tip()

	# --- 3. 通しで遊ぶ（Day1）：2つ目の具を入れて提供し、記録・日次ログ・結果画面の合計が合うか ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var reacts := 0
	var rule_ok := true
	var hearty_line := ""
	var last_key := ""
	var served_seen: Array = []
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		_add_second_topping(s)
		play.step()
		var line := s.current_line()
		if str(line.get("type", "")) == "REACT" and s.open != null and not s.declined_now:
			var key := "%d|%d|%d" % [GameState.day_count, s.open.slot_index, s.open.index]
			if key != last_key:
				last_key = key
				reacts += 1
				# 提供直後の椀（次の客が来るまで残る）：具2種類で GOOD 以上 ⇔ 上乗せあり（1杯 10 の倍数）
				var bowl: Dictionary = s.open.current_bowl
				var grade := str(bowl.get("result", ""))
				var want: bool = (grade == "GOOD" or grade == "GREAT") and Ingredients.topping_kinds(bowl.get("additions", [])) >= 2
				if want != (s.last_serve_hearty > 0) or s.last_serve_hearty % 10 != 0:
					rule_ok = false
				if s.last_serve_hearty > 0 and hearty_line == "":
					hearty_line = str(line["text"])
		if GameState.phase == GameState.Phase.CLOSE and served_seen.is_empty():
			served_seen = GameState.served.duplicate(true)   # 日が変わると空になるので、閉店の時点で読む
	var rec: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	var hearty_sum := 0
	var hearty_cups := 0
	var records_ok := true
	for served in served_seen:
		if bool(served.get("discarded", false)) or int(served.get("servings", 0)) <= 0:
			continue
		var h := int(served.get("hearty_tip", 0))
		hearty_sum += h
		hearty_cups += int(served.get("hearty_cups", 0))
		var results: Dictionary = (served.get("results", {}) as Dictionary).duplicate()
		var single := str(served.get("result", ""))
		if single != "":
			results = { single: int(served["servings"]) }
		var base_tip := 0
		for grade in results:
			base_tip += GameState.tip_for(str(grade), int(results[grade]))
		if h != 10 * int(served.get("hearty_cups", 0)) or int(served.get("tip", 0)) != base_tip + h \
				or int(served.get("sale", 0)) - int(served.get("tip", 0)) != int(served["servings"]) * GameState.PRICE_PER_SERVING:
			records_ok = false
	c.check("Day1を遊べた（具2種類で GOOD 以上の杯がある）", reacts > 0 and not served_seen.is_empty() and hearty_sum > 0, "反応%d回・具だくさん ¥%d" % [reacts, hearty_sum])
	c.check("提供ごと：具2種類で GOOD 以上のときだけ上乗せ（1杯 10）", rule_ok)
	c.check("提供の記録：チップ＝評価のチップ＋具だくさん・売上－チップ＝定価×杯数", records_ok)
	c.check("提供の直後の文に「具だくさん +¥10」を分けて出す", hearty_line.contains("具だくさん +¥") and hearty_line.contains("　+¥"), hearty_line)
	c.check("日次ログ（day_records）：hearty_tips・hearty_cups＝提供の記録の合計（チップ tips に含む）", int(rec.get("hearty_tips", -1)) == hearty_sum
		and int(rec.get("hearty_cups", -1)) == hearty_cups and int(rec.get("tips", 0)) >= hearty_sum, "%s / %d" % [str(rec.get("hearty_tips")), hearty_sum])
	var log_text := FileAccess.get_file_as_string(BalanceLog.path) if FileAccess.file_exists(BalanceLog.path) else ""
	var last_line := ""
	for l in log_text.split("\n"):
		if l.strip_edges() != "":
			last_line = l
	var parsed = JSON.parse_string(last_line) if last_line != "" else null
	c.check("日次ログ（BALANCE_LOG の jsonl）にも hearty_tips・hearty_cups", parsed is Dictionary and int((parsed as Dictionary).get("hearty_tips", -1)) == hearty_sum
		and int((parsed as Dictionary).get("hearty_cups", -1)) == hearty_cups, last_line.left(120))
	var summary := Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
	var report := Result.format_report(summary)
	c.check("結果画面：チップ合計の下に「うち具だくさん ¥xx（x杯）」（日次ログの合計と同じ）", int(summary["hearty_tips"]) == hearty_sum and int(summary["hearty_cups"]) == hearty_cups
		and report.contains("チップ合計: ¥%d　仕入れ合計: ¥%d\n　うち具だくさん ¥%d（%d杯）" % [int(summary["tips"]), int(summary["purchases"]), hearty_sum, hearty_cups]), report)
	var envelope: Dictionary = MorningSave.capture("")
	GameState.day_records = []
	MorningSave.apply(envelope)
	c.check("保存・復元（朝の封筒）：hearty_tips が戻る（保存の版は変えない）", int(Result.summarize(GameState.day_records, GameState.ledger, GameState.money)["hearty_tips"]) == hearty_sum)
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()


## 椀を作っている途中で、味と具が1つずつ入っていれば、手持ちの別の具を1つ足す（2つ目の具。在庫が杯数ぶんあるものだけ）。
func _add_second_topping(s: PlaySession) -> void:
	if s.open == null or not s.is_choosing_ingredients():
		return
	var additions: Array = s.open.current_bowl.get("additions", [])
	var has_flavor := false
	for id in additions:
		has_flavor = has_flavor or Ingredients.is_flavor(str(id))
	if not has_flavor or additions.size() >= OpenController.MAX_ADDITIONS or Ingredients.topping_kinds(additions) != 1:
		return
	var ids: Array = GameState.inventory.keys()
	ids.sort()
	for id in ids:
		if Ingredients.is_topping(str(id)) and not additions.has(id) and GameState.fresh_count(str(id)) >= s.current_servings():
			s.select_ingredient(str(id))
			return
