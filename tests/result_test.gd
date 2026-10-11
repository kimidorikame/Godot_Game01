extends RefCounted
## 結果の集計と目標判定（フェーズ4-2コミット①・DESIGN.md 10.6）の検証。
## 対象：Result.regular_stats / repair_paid / summarize / judge_goals と、
## GameState.day_records（record_day・保存・リセット）。手計算できる小さな例で確かめる。


func _rec(day: int, planned: int, served: int, judged: int, counts: Dictionary,
		reg_cups: int, reg_great: int, reg_good_plus: int, spoiled: int,
		visits: Array, closing: int, closed_early: bool = false) -> Dictionary:
	return {
		"day": day, "planned_cups": planned, "served_cups": served,
		"unserved_cups": planned - served, "judged_planned_cups": judged,
		"quality_counts": counts, "regular_cups": reg_cups, "regular_great": reg_great,
		"regular_good_plus": reg_good_plus, "spoiled_value": spoiled,
		"spoiled_items": { "tofu": { "count": 2, "value": spoiled } } if spoiled > 0 else {},
		"regular_visits": visits, "closing_money": closing, "closed_early": closed_early,
		"opening_reputation": 30 + day, "closing_reputation": 31 + day,
	}


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 常連の集計（名前あり客だけ。団体mob#は除く。discardedは数えない） ---
	var served := [
		{ "customer": "granny", "sale": 90, "servings": 2, "results": { "GREAT": 1, "GOOD": 1 } },
		{ "customer": "mob#0", "sale": 135, "servings": 3, "results": { "GREAT": 3 } },
		{ "customer": "delivery_man", "sale": 45, "servings": 1, "result": "GOOD" },
		{ "customer": "thug", "sale": 0, "servings": 1, "results": { "OK": 1 }, "discarded": true },
		{ "customer": "granny", "sale": 45, "servings": 1, "results": { "BAD": 1 } },
	]
	var st := Result.regular_stats(served)
	c.check("常連の杯数は団体・廃棄を除いて2+1+1=4", int(st["cups"]) == 4, str(st))
	c.check("常連GREATは1杯（団体の3杯は数えない）", int(st["great"]) == 1, str(st))
	c.check("常連GOOD以上は GREAT1+GOOD1+GOOD1=3杯", int(st["good_plus"]) == 3, str(st))
	c.check("来た常連のidは重複なし・来店順（団体・廃棄は除く）",
		st["visits"] == ["granny", "delivery_man"], str(st["visits"]))
	var empty := Result.regular_stats([])
	c.check("提供が空なら全て0", int(empty["cups"]) == 0 and (empty["visits"] as Array).is_empty())
	c.check("is_regularは団体(mob#始まり)以外", Result.is_regular("granny") and not Result.is_regular("mob#3"))

	# --- 2. 修繕額（fundカテゴリの支出を正の値で） ---
	var ledger := [
		{ "category": "sale", "amount": 45 },
		{ "category": "fund", "amount": -50 },
		{ "category": "market", "amount": -20 },
		{ "category": "fund", "amount": -30 },
	]
	c.check("修繕額はfundの支出の合計（80）", Result.repair_paid(ledger) == 80)
	c.check("fundが無ければ0", Result.repair_paid([{ "category": "sale", "amount": 45 }]) == 0)

	# --- 3. 集計（手計算）。2日分：計画10→提供8、計画12→提供12 ---
	var recs := [
		_rec(1, 10, 8, 9, { "GREAT": 1, "GOOD": 5, "OK": 2, "BAD": 0 }, 3, 1, 3, 0, ["granny"], 400),
		_rec(2, 12, 12, 12, { "GREAT": 2, "GOOD": 7, "OK": 3, "BAD": 0 }, 4, 2, 4, 24,
			["granny", "thug"], 700, true),
	]
	var s := Result.summarize(recs, ledger, 700)
	c.check("日数は2", int(s["days"]) == 2)
	c.check("現金＋修繕額＝700+80=780", int(s["cash"]) == 700 and int(s["repair_paid"]) == 80
		and int(s["cash_plus_repair"]) == 780, str(s))
	c.check("提供8+12=20・未提供2+0=2・計画22",
		int(s["served_cups"]) == 20 and int(s["unserved_cups"]) == 2 and int(s["planned_cups"]) == 22)
	c.check("GOOD以上は(1+5)+(2+7)=15杯・評価対象9+12=21→15/21",
		int(s["good_plus_cups"]) == 15 and int(s["judged_cups"]) == 21
			and absf(float(s["good_rate"]) - 15.0 / 21.0) < 0.000001, str(s["good_rate"]))
	c.check("常連GREAT 1+2=3・GOOD以上3+4=7・常連杯数7",
		int(s["regular_great"]) == 3 and int(s["regular_good_plus"]) == 7 and int(s["regular_cups"]) == 7)
	c.check("廃棄額0+24=24・品目数2", int(s["spoiled_value"]) == 24 and int(s["spoiled_units"]) == 2)
	c.check("早期閉店は1夜", int(s["early_close_days"]) == 1)
	c.check("評判は1日目の開始31→最終日の終了33",
		int(s["reputation_start"]) == 31 and int(s["reputation_end"]) == 33, str(s))
	c.check("来店した常連の日数（granny2・thug1）",
		int((s["regular_visit_days"] as Dictionary)["granny"]) == 2
			and int((s["regular_visit_days"] as Dictionary)["thug"]) == 1)
	c.check("日ごとの現金", s["cash_by_day"] == [400, 700])
	var none := Result.summarize([], [], 600)
	c.check("記録が空でも落ちない（日数0・率0・現金600）",
		int(none["days"]) == 0 and float(none["good_rate"]) == 0.0 and int(none["cash_plus_repair"]) == 600)

	# --- 4. 目標判定の境界（ちょうど達成／1足りない） ---
	var goals := { "cash_standard": 1500, "cash_challenge": 1600, "good_rate": 0.85, "regular_great": 8 }
	var base := { "days": 7, "cash_plus_repair": 1500, "good_plus_cups": 85, "judged_cups": 100,
		"good_rate": 0.85, "regular_great": 8 }
	var r := Result.judge_goals(base, goals, 7)
	c.check("目標は5項目（完走・標準・挑戦・料理・常連）の順",
		r.size() == 5 and r.map(func(x): return x["id"]) == ["complete", "cash_standard",
			"cash_challenge", "good_rate", "regular_great"])
	c.check("ちょうど：完走・標準・料理・常連は達成、挑戦（1600）は未達",
		r[0]["achieved"] and r[1]["achieved"] and not r[2]["achieved"] and r[3]["achieved"] and r[4]["achieved"])
	var just := base.duplicate()
	just["cash_plus_repair"] = 1600
	c.check("現金1600ちょうどで挑戦も達成", Result.judge_goals(just, goals, 7)[2]["achieved"])
	var short := base.duplicate()
	short["cash_plus_repair"] = 1499
	short["good_plus_cups"] = 84
	short["regular_great"] = 7
	short["days"] = 6
	var rs := Result.judge_goals(short, goals, 7)
	c.check("1足りない：完走・標準・料理・常連がすべて未達",
		not rs[0]["achieved"] and not rs[1]["achieved"] and not rs[3]["achieved"] and not rs[4]["achieved"])
	var repaired := base.duplicate()
	repaired["cash_plus_repair"] = 1500   # 現金1400＋修繕額100でも合計で判定する
	c.check("修繕額が加わった合計でも標準は達成", Result.judge_goals(repaired, goals, 7)[1]["achieved"])
	var no_judged := base.duplicate()
	no_judged["judged_cups"] = 0
	no_judged["good_plus_cups"] = 0
	no_judged["good_rate"] = 0.0
	c.check("評価対象が0なら料理は未達（0割りで達成にならない）",
		not Result.judge_goals(no_judged, goals, 7)[3]["achieved"])

	# --- 5. GameState.day_records：record_day・リセット・保存 ---
	GameState.reset_for_new_game()
	GameState.record_day({ "day": 1, "served_cups": 5 })
	GameState.record_day({ "day": 2, "served_cups": 6 })
	c.check("record_dayで日ごとに1件ずつ溜まる", GameState.day_records.size() == 2)
	GameState.record_day({ "day": 2, "served_cups": 99 })
	c.check("同じ日の記録は置き換わる（二重に数えない）",
		GameState.day_records.size() == 2 and int(GameState.day_records[1]["served_cups"]) == 99)
	var src := { "day": 3, "served_cups": 1, "quality_counts": { "GOOD": 1 } }
	GameState.record_day(src)
	src["quality_counts"]["GOOD"] = 50
	c.check("record_dayは深いコピー（元の辞書の変更が入らない）",
		int(GameState.day_records[2]["quality_counts"]["GOOD"]) == 1)
	var d := GameState.to_dict()
	GameState.reset_for_new_game()
	c.check("reset_for_new_gameで記録が消える", GameState.day_records.is_empty())
	GameState.from_dict(d)
	c.check("to_dict→from_dictで記録が保たれる",
		GameState.day_records.size() == 3 and int(GameState.day_records[0]["day"]) == 1)
	GameState.reset_for_new_game()

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
