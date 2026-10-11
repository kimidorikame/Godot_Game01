extends RefCounted
## F7 朝の保存と同じ朝からの再挑戦（フェーズ4-1・DESIGN.md 10.8.7）の検証。
## 対象：GameState.to_dict()/from_dict()、MorningSave（封筒・検証）、WAKEの順序
## （DayPlanを先に作り、運営費を引く前に朝の辞書化。払えなかった朝は記録しない）、
## DebugPanel.retry_from_morning()（同じDayPlanへ戻る・build()を呼ばない）。
##
## 抽選は「保存したtoday_planをそのまま戻す」方式なので、客・需要・組は同一。
## 反応文の2択（reaction_variant）は演出の乱数で、再挑戦では変わりうる（ここでは見ない）。


func _setup(t: SceneTree, money: int, day: int = 1):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がその場で_set_runner_for_phase(WAKE)を呼ぶ
	return panel


func _count(category: String) -> int:
	var n := 0
	for row in GameState.ledger:
		if int(row.get("day", -1)) == GameState.day_count and str(row.get("category", "")) == category:
			n += 1
	return n


func _customers(plan: Dictionary) -> Array:
	var ids := []
	for slot in plan.get("slots", []):
		ids.append_array(slot.get("customers", []))
	return ids


## 全項目を既定値以外にしておく（to_dict/from_dictの保存漏れを見つけるため）。
func _fill_every_field() -> void:
	GameState.reset_for_new_game()
	GameState.day_count = 4
	GameState.money = 321
	GameState.reputation = 47
	GameState.inventory = { "tofu": 3, "meat_ball": 2, "herbal_sauce": 4 }
	GameState.perishable_batches = {
		"tofu": [{ "day": 3, "count": 2, "unit_price": 8 }, { "day": 4, "count": 1, "unit_price": 9 }],
		"meat_ball": [{ "day": 4, "count": 2, "unit_price": 8 }],
	}
	GameState.rumors = ["噂その1"]
	GameState.dashi_units = 2
	GameState.known_favorites = { "granny": true, "delivery_man": true }
	GameState.ledger = [
		{ "day": 3, "phase": "OPEN", "category": "sale", "amount": 45, "item": "granny",
			"count": 1, "unit_price": 0, "ref": "" },
		{ "day": 4, "phase": "WAKE", "category": "daily_cost", "amount": -65, "item": "",
			"count": 0, "unit_price": 0, "ref": "" },
	]
	GameState.today_plan = {
		"day": 4, "demand_center": 11,
		"slots": [{ "name": "夕方", "customers": ["delivery_man", "mob#0"] },
			{ "name": "夜", "customers": ["granny"] }],
		"mob_instances": { "mob#0": { "type": "dock_workers", "count": 2 } },
	}
	GameState.day_records = [
		{ "day": 1, "served_cups": 9, "regular_great": 1, "quality_counts": { "GOOD": 8, "GREAT": 1 } },
		{ "day": 2, "served_cups": 10, "regular_great": 0, "quality_counts": { "GOOD": 10 } },
	]


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 保存漏れの検出：GameStateのインスタンス変数は、保存対象か保存しない項目の
	#    どちらかに必ず載っている（F5「来店記録」などを足したとき、分類し忘れると落ちる） ---
	var declared := []
	for prop in GameState.get_script().get_script_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var name := str(prop["name"])
			if name != name.to_upper():   # static var（設定値。PRICE_PER_SERVING等）は大文字
				declared.append(name)
	var classified: Array = GameState.SAVED_FIELDS + GameState.TRANSIENT_FIELDS
	var unclassified := declared.filter(func(n): return not classified.has(n))
	c.check("GameStateの全インスタンス変数が保存対象／保存しない項目のどちらかに載っている",
		unclassified.is_empty(), str(unclassified))
	var missing := classified.filter(func(n): return not declared.has(n))
	c.check("保存対象・保存しない項目に、存在しない変数名が無い", missing.is_empty(), str(missing))
	var both := GameState.SAVED_FIELDS.filter(func(n): return GameState.TRANSIENT_FIELDS.has(n))
	c.check("保存対象と保存しない項目が重ならない", both.is_empty(), str(both))


	# --- 2. to_dict→from_dictで全保存項目が一致する。日ごとの使い捨ては朝の初期値へ戻る ---
	_fill_every_field()
	var expect := {}
	for field in GameState.SAVED_FIELDS:
		var v = GameState.get(field)
		expect[field] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	var d := GameState.to_dict()
	c.check("to_dictのキーは保存対象と同じ",
		d.keys().size() == GameState.SAVED_FIELDS.size()
			and GameState.SAVED_FIELDS.all(func(f): return d.has(f)), str(d.keys()))
	GameState.set_soup("pork", ["meaty"], 5)
	GameState.served.append({ "customer": "granny" })
	GameState.rent_paid_today = true
	GameState.phase = GameState.Phase.OPEN
	GameState.reset_for_new_game()   # 別の状態へ
	GameState.from_dict(d)
	for field in GameState.SAVED_FIELDS:
		c.check("from_dictで%sが元と一致する" % field, GameState.get(field) == expect[field],
			"%s != %s" % [str(GameState.get(field)), str(expect[field])])
	c.check("from_dict後のphaseはWAKE", GameState.phase == GameState.Phase.WAKE)
	c.check("from_dict後は鍋・提供記録・場所代済みが朝の初期値",
		GameState.soup == null and GameState.served.is_empty() and not GameState.rent_paid_today)

	# --- 3. 辞書は深いコピー（保存後の変更が辞書を、復元後の変更が辞書を書き換えない） ---
	_fill_every_field()
	var snap := GameState.to_dict()
	GameState.inventory["extra"] = 1
	GameState.perishable_batches["tofu"][0]["count"] = 99
	GameState.ledger.append({ "day": 4, "category": "market", "amount": -10 })
	GameState.today_plan["slots"][0]["name"] = "書き換え"
	c.check("to_dict後のプレイ中の変更が辞書へ入らない",
		not snap["inventory"].has("extra") and int(snap["perishable_batches"]["tofu"][0]["count"]) == 2
			and snap["ledger"].size() == 2 and str(snap["today_plan"]["slots"][0]["name"]) == "夕方")
	GameState.from_dict(snap)
	GameState.inventory["again"] = 1
	GameState.today_plan["slots"][0]["name"] = "また書き換え"
	GameState.ledger.clear()
	c.check("from_dict後のプレイ中の変更が辞書へ入らない",
		not snap["inventory"].has("again") and snap["ledger"].size() == 2
			and str(snap["today_plan"]["slots"][0]["name"]) == "夕方")

	# --- 4. 封筒：capture→is_valid。壊れた・古い・別キャンペーンの封筒は弾く ---
	_fill_every_field()
	var env := MorningSave.capture("前日の一言")
	c.check("captureした封筒はis_valid", MorningSave.is_valid(env))
	c.check("封筒にdayとcampaignが入る",
		int(env["day"]) == 4 and str(env["campaign"]) == Rules.campaign_id())
	c.check("Dictionary以外はis_validでfalse（例外にならない）",
		not MorningSave.is_valid(null) and not MorningSave.is_valid("x") and not MorningSave.is_valid([]))
	var bad := env.duplicate(true)
	bad["version"] = 99
	c.check("版違いはfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["campaign"] = "week21"
	c.check("別キャンペーンはfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"].erase("ledger")
	c.check("保存項目の欠けはfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["money"] = 321.0   # JSON経由で起きる型の落とし穴（整数がfloatになる）
	c.check("整数がfloatになった封筒はfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["inventory"]["tofu"] = 3.0
	c.check("在庫の個数がfloatならfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["today_plan"].erase("slots")
	c.check("DayPlanの形が壊れていればfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["day_records"] = [1, 2]
	c.check("day_recordsの行が辞書でなければfalse", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"].erase("day_records")
	c.check("day_recordsの欠けはfalse（版1のセーブ相当）", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["day"] = 5
	c.check("dayとstate.day_countの不一致はfalse", not MorningSave.is_valid(bad))

	# --- 5. WAKEの順序：DayPlanを作る→運営費を引く前に辞書化→払えた朝だけ記録 ---
	var panel = _setup(t, 300, 1)
	var rec: Dictionary = GameState.latest_morning()
	c.check("WAKEが成功すると朝が1件記録される", GameState.morning_snapshots.size() == 1 and not rec.is_empty())
	c.check("朝の辞書の所持金は運営費を引く前（300）",
		int(rec["state"]["money"]) == 300 and GameState.money == 300 - GameState.DAILY_OPERATING_COST,
		str(rec["state"]["money"]))
	c.check("朝の辞書の帳簿には、その朝のdaily_cost・reserveがまだ入っていない",
		not rec["state"]["ledger"].any(func(r): return str(r["category"]) in ["daily_cost", "reserve"]))
	c.check("朝の辞書にはその日のDayPlanが入っている",
		not rec["state"]["today_plan"]["slots"].is_empty()
			and int(rec["state"]["today_plan"]["day"]) == 1
			and rec["state"]["today_plan"]["slots"] == GameState.today_plan["slots"])
	c.check("朝の辞書は封筒として有効", MorningSave.is_valid(rec))

	# 運営費が払えない朝（Day2）：ゲームオーバーになり、その朝は記録されない。DayPlanは残る
	GameState.money = 50
	GameState.day_count = 2
	panel._set_runner_for_phase(GameState.Phase.WAKE)
	c.check("運営費が払えないWAKEはゲームオーバーになる", GameState.phase == GameState.Phase.GAME_OVER)
	c.check("払えなかった朝は記録されない（Day1の朝だけが残る）",
		GameState.morning_snapshots.size() == 1 and GameState.morning_snapshots.has(1))
	c.check("払えなかった朝でも所持金は変わらない", GameState.money == 50)
	c.check("ゲームオーバー時のtoday_planは今日のDayPlanを持つ（従来は空）",
		int(GameState.today_plan.get("day", -1)) == 2
			and not (GameState.today_plan.get("slots", []) as Array).is_empty())

	# --- 6. 運営費不足のゲームオーバーから、前日（最後に記録された）の朝へ戻る ---
	c.check("ゲームオーバーでは仮ボタンが押せる",
		not panel._btn_retry.disabled, "disabled=%s" % str(panel._btn_retry.disabled))
	var before_plan: Dictionary = (rec["state"]["today_plan"] as Dictionary).duplicate(true)
	var ok: bool = panel.retry_from_morning()
	c.check("retry_from_morningはtrueを返す", ok)
	c.check("戻った先の日・フェーズはDay1のWAKE",
		GameState.day_count == 1 and GameState.phase == GameState.Phase.WAKE)
	c.check("戻った朝の所持金は朝の値から運営費だけ引かれている（WAKEからやり直し）",
		GameState.money == 300 - GameState.DAILY_OPERATING_COST, str(GameState.money))
	c.check("戻った朝のDayPlanは保存したものと同一（slots・mob_instances・demand_center）",
		GameState.today_plan["slots"] == before_plan["slots"]
			and GameState.today_plan["mob_instances"] == before_plan["mob_instances"]
			and int(GameState.today_plan["demand_center"]) == int(before_plan["demand_center"])
			and int(GameState.today_plan["day"]) == 1)
	c.check("戻った朝のdaily_costとreserveは1回だけ（二重に引かれない）",
		_count("daily_cost") == 1 and _count("reserve") == 1,
		"daily=%d reserve=%d" % [_count("daily_cost"), _count("reserve")])
	c.check("戻した後のWAKEのrunnerが組まれている",
		panel.flow.runner != null and panel.flow.runner.current().has("type"))
	c.check("戻した朝も記録が1件のまま（同じ日は置き換え）", GameState.morning_snapshots.size() == 1)
	c.check("戻った朝では仮ボタンは押せない（GAME_OVERではない）", panel._btn_retry.disabled)

	# --- 7. build()を再実行しない：封筒のslotsを目印に書き換え、戻した後も残っていること ---
	var panel2 = _setup(t, 300, 3)
	GameState.reputation = 50
	panel2._set_runner_for_phase(GameState.Phase.WAKE)   # 評判を変えたのでもう一度Day3の朝を記録
	var day3: Dictionary = GameState.morning_snapshots[3]
	day3["state"]["today_plan"]["slots"][0]["name"] = "SENTINEL"
	var customers_before := _customers(day3["state"]["today_plan"])
	GameState.money = 0
	GameState.inventory["probe"] = 1
	GameState.today_plan["slots"] = []
	panel2._game_over("テスト用ゲームオーバー")
	var ok2: bool = panel2.retry_from_morning()
	c.check("Day3の朝へ戻れる", ok2 and GameState.day_count == 3)
	c.check("DayPlanner.build()は再実行されない（目印が残る）",
		str(GameState.today_plan["slots"][0]["name"]) == "SENTINEL")
	c.check("戻った朝で実際に来る客の並びは保存時と同一",
		_customers(GameState.today_plan) == customers_before)
	c.check("戻した朝には、ゲームオーバー前の変更（所持金0・追加在庫）が残っていない",
		GameState.money != 0 and not GameState.inventory.has("probe"))

	# --- 8. 日中のゲームオーバー（Day1の場所代）：その日の朝へ戻る。2回続けて戻っても同じ ---
	var panel3 = _setup(t, 600, 1)
	var morning_money := 600
	GameState.money = 10
	GameState.inventory["probe"] = 5
	Ledger.record("market", -30)
	panel3._game_over("所持金が足りない。")
	for round in [1, 2]:
		c.check("ゲームオーバー（%d回目）からDay1の朝へ戻れる" % round, panel3.retry_from_morning())
		c.check("%d回目：所持金が朝の値＋運営費後に戻る" % round,
			GameState.money == morning_money - GameState.DAILY_OPERATING_COST, str(GameState.money))
		c.check("%d回目：日中の変更（在庫・market記帳）が消えている" % round,
			not GameState.inventory.has("probe") and _count("market") == 0)
		GameState.money = 10
		panel3._game_over("所持金が足りない。")

	# --- 9. 前日成績の一言も、戻った朝の先頭に再表示される ---
	var panel4 = _setup(t, 600, 2)
	panel4._last_day_summary_text = "昨日の成績の一言"
	panel4._set_runner_for_phase(GameState.Phase.WAKE)
	c.check("朝の先頭に前日の一言が出る",
		str(panel4.flow.runner.current().get("text", "")) == "昨日の成績の一言")
	panel4._game_over("テスト")
	panel4.retry_from_morning()
	c.check("戻った朝の先頭にも前日の一言が出る",
		str(panel4.flow.runner.current().get("text", "")) == "昨日の成績の一言")
	c.check("一言は一度だけ消費される（保存した封筒には残る）",
		panel4._last_day_summary_text == "" and
			str(GameState.latest_morning()["panel"]["day_summary_text"]) == "昨日の成績の一言")

	# --- 10. 戻る先が無い／封筒が壊れていれば何もしない ---
	var panel5 = _setup(t, 600, 1)
	GameState.morning_snapshots.clear()
	GameState.money = 123
	c.check("朝の記録が無ければretry_from_morningはfalse", not panel5.retry_from_morning())
	c.check("戻る先が無ければ状態は変わらない", GameState.money == 123)
	GameState.morning_snapshots[1] = { "version": 99 }
	c.check("壊れた封筒ならretry_from_morningはfalse", not panel5.retry_from_morning())
	c.check("壊れた封筒では状態は変わらない", GameState.money == 123)

	# --- 10b. 4-2：再挑戦で1日の記録（day_records）が二重に数えられない ---
	var panel7 = _setup(t, 600, 1)
	c.check("朝のday_recordsは空（Day1の朝）", GameState.day_records.is_empty())
	panel7._on_day_ending()   # Day1の終わりの記録
	c.check("Day1の終わりに1件入る", GameState.day_records.size() == 1)
	GameState.money = 5
	panel7._game_over("テスト")
	panel7.retry_from_morning()   # Day1の朝へ戻る（記録は朝の値＝空）
	c.check("Day1の朝へ戻ると、Day1の記録は戻る（空）", GameState.day_records.is_empty())
	panel7._on_day_ending()
	c.check("やり直してもう一度終わらせても1件のまま（二重に数えない）",
		GameState.day_records.size() == 1 and int(GameState.day_records[0]["day"]) == 1)

	# --- 11. reset_for_new_gameで朝の記録は消える（結果画面の「もう一度」は4-2で別途保持する） ---
	var panel6 = _setup(t, 600, 1)
	c.check("朝の記録がある", not GameState.morning_snapshots.is_empty())
	GameState.reset_for_new_game()
	c.check("reset_for_new_gameは朝の記録を消す", GameState.morning_snapshots.is_empty())

	# --- 12. from_dictは復元した日より後の朝の記録を捨てる ---
	_fill_every_field()
	GameState.record_morning({ "day": 2 })
	GameState.record_morning({ "day": 4 })
	GameState.record_morning({ "day": 6 })
	var d4 := GameState.to_dict()
	GameState.from_dict(d4)
	c.check("復元した日（4）より後の記録（6）は捨てられ、それ以前は残る",
		GameState.morning_snapshots.has(2) and GameState.morning_snapshots.has(4)
			and not GameState.morning_snapshots.has(6))

	GameState.reset_for_new_game()
	for p in [panel, panel2, panel3, panel4, panel5, panel6, panel7]:
		if is_instance_valid(p):
			p.free()
	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
