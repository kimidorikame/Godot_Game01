extends RefCounted
class_name Result
## 結果の集計と目標判定（フェーズ4-2・DESIGN.md 10.6）。画面（DebugPanel）から分離した
## 純粋な静的関数だけを持つ（状態を持たない。単体でテストできる）。
##
## 入力は、GameState.day_records（1日ごとの記録＝DebugPanelが組むlog_entry）・
## GameState.ledger（帳簿）・所持金。GameStateは読まない（呼び出し側が渡す）。
## 目標は表示だけで、ゲーム状態には影響させない（未達でも物語や続きのプレイを失わない）。
##
## 定義（3-8の自動試遊と同じ）：
##   - GOOD以上率 ＝ Σ(GOOD＋GREAT) ÷ Σ評価対象需要（judged_planned_cups。未提供も分母に残す）
##   - 常連GREAT   ＝ 名前あり客（customerが"mob#"で始まらない）への提供でGREATだった「杯数」
##   - 未提供      ＝ Σ(計画杯数 − 提供杯数)
##   - 廃棄        ＝ Σ廃棄額（PREPで腐りきった在庫を捨てた実額。品目数も併記）
##   - 現金＋修繕額 ＝ 所持金 ＋ 帳簿のfundカテゴリの支出合計（修繕基金は4-9。今は常に0）


## 団体客（モブ）の提供記録のcustomerは"mob#"で始まる。それ以外が「名前あり客（常連）」。
static func is_regular(customer_id) -> bool:
	return not str(customer_id).begins_with("mob#")


## 提供記録（GameState.served）から、その日の常連の実績を集計する。廃棄した椀の記録
## （discarded）は数えない。results（評価→杯数の辞書）と、単独のresultの両方を見る。
## 戻り値：{ "cups", "great", "good_plus", "visits": [customer_id, ...]（重複なし・来店順） }
static func regular_stats(served: Array) -> Dictionary:
	var cups := 0
	var great := 0
	var good_plus := 0
	var visits := []
	for rec in served:
		if not (rec is Dictionary) or bool(rec.get("discarded", false)):
			continue
		var customer := str(rec.get("customer", ""))
		if not is_regular(customer):
			continue
		var servings := int(rec.get("servings", 0))
		cups += servings
		var grades: Dictionary = (rec.get("results", {}) as Dictionary).duplicate()
		var single := str(rec.get("result", ""))
		if single != "":
			grades[single] = int(grades.get(single, 0)) + servings
		great += int(grades.get("GREAT", 0))
		good_plus += int(grades.get("GREAT", 0)) + int(grades.get("GOOD", 0))
		if servings > 0 and not visits.has(customer):
			visits.append(customer)
	return { "cups": cups, "great": great, "good_plus": good_plus, "visits": visits }


## 支払済みの修繕額。帳簿のfundカテゴリの支出（負額）の合計を正の値で返す
## （4-9で操作ができても、この形のまま使える）。
static func repair_paid(ledger: Array) -> int:
	var total := 0
	for entry in ledger:
		if entry is Dictionary and str(entry.get("category", "")) == "fund":
			total -= int(entry.get("amount", 0))
	return maxi(total, 0)


## 周回全体の成績。day_recordsは日ごとの記録（log_entry）の配列。
static func summarize(day_records: Array, ledger: Array, money: int) -> Dictionary:
	var planned := 0
	var served := 0
	var unserved := 0
	var judged := 0
	var good_plus := 0
	var reg_cups := 0
	var reg_great := 0
	var reg_good_plus := 0
	var spoiled_value := 0
	var spoiled_units := 0
	var tips := 0
	var early_close := 0
	var visit_days := {}
	var cash_by_day := []
	for rec in day_records:
		if not (rec is Dictionary):
			continue
		planned += int(rec.get("planned_cups", 0))
		served += int(rec.get("served_cups", 0))
		unserved += int(rec.get("unserved_cups", 0))
		judged += int(rec.get("judged_planned_cups", 0))
		var counts: Dictionary = rec.get("quality_counts", {})
		good_plus += int(counts.get("GREAT", 0)) + int(counts.get("GOOD", 0))
		reg_cups += int(rec.get("regular_cups", 0))
		reg_great += int(rec.get("regular_great", 0))
		reg_good_plus += int(rec.get("regular_good_plus", 0))
		spoiled_value += int(rec.get("spoiled_value", 0))
		tips += int(rec.get("tips", 0))
		var items: Dictionary = rec.get("spoiled_items", {})
		for id in items:
			var item = items[id]
			spoiled_units += int((item as Dictionary).get("count", 0)) if item is Dictionary else int(item)
		if bool(rec.get("closed_early", false)):
			early_close += 1
		for id in rec.get("regular_visits", []):
			visit_days[str(id)] = int(visit_days.get(str(id), 0)) + 1
		cash_by_day.append(int(rec.get("closing_money", 0)))
	var repair := repair_paid(ledger)
	var first: Dictionary = day_records[0] if not day_records.is_empty() else {}
	var last: Dictionary = day_records[day_records.size() - 1] if not day_records.is_empty() else {}
	return {
		"days": day_records.size(),
		"cash": money, "repair_paid": repair, "cash_plus_repair": money + repair,
		"planned_cups": planned, "served_cups": served, "unserved_cups": unserved,
		"judged_cups": judged, "good_plus_cups": good_plus,
		"good_rate": float(good_plus) / float(judged) if judged > 0 else 0.0,
		"regular_cups": reg_cups, "regular_great": reg_great, "regular_good_plus": reg_good_plus,
		"spoiled_value": spoiled_value, "spoiled_units": spoiled_units, "tips": tips,
		"early_close_days": early_close,
		"reputation_start": int(first.get("opening_reputation", 0)),
		"reputation_end": int(last.get("closing_reputation", 0)),
		"regular_visit_days": visit_days,
		"cash_by_day": cash_by_day,
	}


## 店の成績ブロック（結果画面の1枚目）。数値はsummarize()の値をそのまま並べる。
static func format_report(s: Dictionary) -> String:
	var lines := PackedStringArray([
		"◆結果：店の成績（%d日間）◆" % int(s.get("days", 0)),
		"現金: %d ＋ 支払済み修繕額: %d ＝ %d" % [
			int(s.get("cash", 0)), int(s.get("repair_paid", 0)), int(s.get("cash_plus_repair", 0))],
		"GOOD以上率: %.1f%%（GOOD以上 %d杯／評価対象 %d杯。未提供も分母に残す）" % [
			float(s.get("good_rate", 0.0)) * 100.0, int(s.get("good_plus_cups", 0)),
			int(s.get("judged_cups", 0))],
		"常連GREAT: %d杯（常連への提供 %d杯のうち）" % [
			int(s.get("regular_great", 0)), int(s.get("regular_cups", 0))],
		"未提供: %d杯（計画 %d杯・提供 %d杯）" % [
			int(s.get("unserved_cups", 0)), int(s.get("planned_cups", 0)), int(s.get("served_cups", 0))],
		"チップ合計: ¥%d" % int(s.get("tips", 0)),
		"廃棄: ¥%d（%d個）　早期閉店: %d夜" % [
			int(s.get("spoiled_value", 0)), int(s.get("spoiled_units", 0)),
			int(s.get("early_close_days", 0))],
	])
	# 修繕基金（4-9）：累計が1以上のときだけ、屋台の段階を現金の行の次に足す（累計0は従来と同一）。
	var repair := int(s.get("repair_paid", 0))
	if repair >= 1 and RepairFund.enabled():
		lines.insert(2, "屋台: %s" % RepairFund.progress_text())
	return "\n".join(lines)


## 目標ブロック（結果画面の2枚目）。judge_goals()の結果を並べる。表示のみ。
static func format_goals(results: Array) -> String:
	var lines := PackedStringArray(["◆目標（表示のみ。未達でも物語や続きのプレイは失われない）◆"])
	for r in results:
		var value := ""
		if str(r.get("id", "")) == "good_rate":
			value = "（%.1f%%）" % (float(r.get("value", 0.0)) * 100.0)
		else:
			value = "（%d）" % int(r.get("value", 0))
		lines.append("%s %s %s" % ["【達成】" if bool(r.get("achieved", false)) else "【未達】",
			str(r.get("label", "")), value])
	return "\n".join(lines)


## 物語の欄（結果画面の3枚目：街で起きたこと／客との間に残ったこと）。**成績の数値
## （GOOD率・杯数・現金・廃棄）は出さない**（DESIGN.md 10.6：料理成績を人間関係の善悪や
## 真エンド条件にしない）。4-2では今あるデータだけの最小の仮の文で、本文は後の手順
## （4-4〜4-8：来店記録・場面データ）で入る。known_favorite_idsは好物を知った客のid（知った順）。
static func format_story(s: Dictionary, known_favorite_ids: Array) -> String:
	var rep_start := int(s.get("reputation_start", 0))
	var rep_end := int(s.get("reputation_end", 0))
	var rep_text := "評判は変わらなかった。"
	if rep_end > rep_start:
		rep_text = "評判は上がった。"
	elif rep_end < rep_start:
		rep_text = "評判は下がった。"
	var early_text := "鍋が尽きて早めに店を閉めた夜があった。" \
		if int(s.get("early_close_days", 0)) > 0 else "鍋が尽きて早く閉めた夜は無かった。"
	var known_text := "まだ誰の好物も知らない。"
	if not known_favorite_ids.is_empty():
		var ids := PackedStringArray()
		for id in known_favorite_ids:
			ids.append(ScheduleData.customer_display_name(str(id)))
		known_text = "好物を知った客: %s" % "、".join(ids)
	var visit_days: Dictionary = s.get("regular_visit_days", {})
	var visit_text := "店に来た常連はいなかった。"
	if not visit_days.is_empty():
		var parts := PackedStringArray()
		for id in visit_days:
			parts.append("%s（%d日）" % [ScheduleData.customer_display_name(str(id)), int(visit_days[id])])
		visit_text = "店に来た常連: %s" % "、".join(parts)
	return "\n".join(PackedStringArray([
		"◆街で起きたこと◆",
		rep_text,
		early_text,
		"（出来事の本文は、場面データができる後の手順で入る）",
		"◆客との間に残ったこと◆",
		known_text,
		visit_text,
		"（客との場面の本文は、場面データができる後の手順で入る）",
	]))


## 目標の判定（表示用。ゲーム状態には影響させない）。goalsはRules.goals()の形
## （cash_standard / cash_challenge / good_rate / regular_great）。final_dayは完走の日数。
## 戻り値：[{ id, label, achieved, value, target }, ...] を 完走・標準・挑戦・料理・常連 の順で。
static func judge_goals(summary: Dictionary, goals: Dictionary, final_day: int) -> Array:
	var cash_total := int(summary.get("cash_plus_repair", 0))
	var good_rate := float(summary.get("good_rate", 0.0))
	var judged := int(summary.get("judged_cups", 0))
	var good_plus := int(summary.get("good_plus_cups", 0))
	var great := int(summary.get("regular_great", 0))
	var days := int(summary.get("days", 0))
	var cash_standard := int(goals.get("cash_standard", 0))
	var cash_challenge := int(goals.get("cash_challenge", 0))
	var rate_target := float(goals.get("good_rate", 0.0))
	var great_target := int(goals.get("regular_great", 0))
	return [
		{ "id": "complete", "label": "完走（%d日営業）" % final_day,
			"achieved": days >= final_day, "value": days, "target": final_day },
		{ "id": "cash_standard", "label": "標準：現金＋修繕額 %d以上" % cash_standard,
			"achieved": cash_total >= cash_standard, "value": cash_total, "target": cash_standard },
		{ "id": "cash_challenge", "label": "挑戦：現金＋修繕額 %d以上" % cash_challenge,
			"achieved": cash_total >= cash_challenge, "value": cash_total, "target": cash_challenge },
		{ "id": "good_rate", "label": "料理：全需要の%d%%以上にGOOD以上" % roundi(rate_target * 100.0),
			# 浮動小数の境界（ちょうど85%）を取りこぼさないよう、杯数同士で比べる。
			"achieved": judged > 0 and float(good_plus) >= rate_target * float(judged) - 0.000001,
			"value": good_rate, "target": rate_target },
		{ "id": "regular_great", "label": "常連：GREAT %d杯以上" % great_target,
			"achieved": great >= great_target, "value": great, "target": great_target },
	]
