extends RefCounted
## 複数杯の場面（cups。システム整理E-①。DESIGN.md 10.8.6・10.9）の検証。
## 同じ客へ複数の杯を1杯ずつ会話の合間に出す場面を、場面データの cups で表す。読み口
## （ScheduleData.episode_cups）、形の検査（scene_problems）、Event列の組み立て（_cups_events）、
## 1杯の場面だけの機能（提供後の列・注文カード・[聞き直す]）が出ないこと、杯数の先読みと予報。
## E-①の時点では配達員の旧3杯列（delivery_man_01）はそのまま（E-②でデータへ移す）。
## 場面データはキャッシュへ注入する。

const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]


func _cups_scene(extra: Dictionary = {}) -> Dictionary:
	var ep := { "id": "multi_x", "customer": "thug", "greet": ["来店1", "来店2"],
		"cups": [
			{ "reactions": { "GREAT": ["R1:GREAT"], "GOOD": ["R1:GOOD"], "OK": ["R1:OK"], "BAD": ["R1:BAD"] },
				"after_talk": ["1杯目のあと"] },
			{ "tags": ["HOT", "POWER"], "adjust": "（2杯目を調える）", "serve": "（2杯目を置く）",
				"reactions": { "GOOD": ["R2:GOOD"] }, "after_talk": ["2杯目のあと", "もう1行"] },
			{ "tags": ["MELLOW", "GENTLE"], "favorite": false, "adjust": "（持ち帰り用）", "serve": "（袋へ入れる）",
				"reactions": {}, "after_talk": ["退店"] },
		] }
	ep.merge(extra, true)
	return ep


func _types(events: Array) -> Array:
	var out := []
	for ev in events:
		out.append(str(ev["type"]))
	return out


func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	GameState.day_count = 2

	# --- 1. 読み口：2杯以上で形の整ったときだけ。無い・不正は「複数杯の場面ではない」 ---
	ScheduleData._episode_cache["thug/multi_x"] = _cups_scene()
	var cups := ScheduleData.episode_cups("thug", "multi_x")
	c.check("3杯の cups が読める（指定のあったキーだけを持つ）",
		cups.size() == 3 and not (cups[0] as Dictionary).has("tags") and (cups[1] as Dictionary)["tags"] == ["HOT", "POWER"]
			and (cups[2] as Dictionary)["favorite"] == false and (cups[0] as Dictionary)["after_talk"] == ["1杯目のあと"])
	c.check("実データ：cups を持つのは delivery_man_01（3杯）だけ。他の場面は持たない",
		ScheduleData.episode_cups("delivery_man", "delivery_man_01").size() == 3
			and ScheduleData.episode_cups("thug", "thug_01").is_empty()
			and ScheduleData.episode_cups("delivery_man", "delivery_man_02").is_empty())
	ScheduleData._episode_cache["thug/multi_one"] = _cups_scene({ "cups": [ { "after_talk": ["x"] } ] })
	c.check("1杯の cups は複数杯の場面ではない", ScheduleData.episode_cups("thug", "multi_one").is_empty())
	ScheduleData._episode_cache["thug/multi_bad"] = _cups_scene({ "cups": [ {}, { "tags": "HOT" } ] })
	c.check("形の不正な杯があれば複数杯の場面ではない（部分的に読まない）", ScheduleData.episode_cups("thug", "multi_bad").is_empty())
	ScheduleData._episode_cache["thug/multi_str"] = _cups_scene({ "cups": "x" })
	c.check("cups が配列でなければ複数杯の場面ではない", ScheduleData.episode_cups("thug", "multi_str").is_empty())
	c.check("is_multi_cup_scene：cups のある場面は true、1杯の場面は false",
		Day1Events.is_multi_cup_scene("thug", "multi_x") and not Day1Events.is_multi_cup_scene("thug", "thug_01")
			and not Day1Events.is_multi_cup_scene("thug", "multi_one"))
	c.check("is_multi_cup_scene：delivery_man_01 は true、delivery_man_02〜04 は false（通常の1杯）",
		Day1Events.is_multi_cup_scene("delivery_man", "delivery_man_01")
			and not Day1Events.is_multi_cup_scene("delivery_man", "delivery_man_02")
			and not Day1Events.is_multi_cup_scene("delivery_man", "delivery_man_04"))

	# --- 2. 形の検査（scene_problems） ---
	c.check("正しい複数杯の場面は問題なし", ScheduleData.scene_problems(_cups_scene()).is_empty(),
		str(ScheduleData.scene_problems(_cups_scene())))
	c.check("servings が杯数と一致していれば問題なし", ScheduleData.scene_problems(_cups_scene({ "servings": 3 })).is_empty())
	c.check("requires・market_talk・must_info は使える", ScheduleData.scene_problems(_cups_scene({
		"requires": { "not_seen": true }, "market_talk": ["昼"], "must_info": ["night_removal"] })).is_empty())
	var bad_cases := {
		"1杯の cups": { "cups": [ {} ] },
		"cups が配列でない": { "cups": {} },
		"杯が辞書でない": { "cups": [ {}, 5 ] },
		"杯の未知のキー": { "cups": [ {}, { "taggs": ["HOT"] } ] },
		"tags が空": { "cups": [ {}, { "tags": [] } ] },
		"tags が文字列の配列でない": { "cups": [ {}, { "tags": [1] } ] },
		"favorite が真偽値でない": { "cups": [ {}, { "favorite": "no" } ] },
		"adjust が空文字": { "cups": [ {}, { "adjust": "" } ] },
		"serve が文字列でない": { "cups": [ {}, { "serve": 3 } ] },
		"reactions の未知のキー": { "cups": [ {}, { "reactions": { "FINE": ["a"] } } ] },
		"reactions の値が配列でない": { "cups": [ {}, { "reactions": { "GOOD": "a" } } ] },
		"after_talk が文字列でない": { "cups": [ {}, { "after_talk": "a" } ] },
		"servings が杯数と食い違う": { "servings": 2 },
		"場面直下の reactions": { "reactions": { "GOOD": ["a"] } },
		"order（今日の頼み）": { "order": { "today_request": { "tags": ["HOT"] } } },
		"callback": { "callback": { "first": ["a"] } },
		"pre_order": { "pre_order": ["a"] },
		"body": { "body": ["a"] },
		"body_unserved": { "body_unserved": ["a"] },
		"choices": { "choices": [] },
		"closing": { "closing": { "default": ["a"] } },
		"sets_facts": { "sets_facts": { "a": true } },
	}
	for label in bad_cases:
		var problems := ScheduleData.scene_problems(_cups_scene(bad_cases[label]))
		c.check("検査が弾く：" + label, not problems.is_empty())
	c.check("使えないキーのメッセージは「複数杯の場面（cups）では使えない」と分かる",
		str(ScheduleData.scene_problems(_cups_scene({ "body": ["a"] }))).contains("複数杯の場面（cups）では使えないキー body"))
	c.check("1杯の場面（cupsなし）の検査は変わらない：reactions・body は引き続き使える",
		ScheduleData.scene_problems({ "id": "a", "customer": "thug", "greet": ["g"], "servings": 1,
			"reactions": { "GOOD": ["a"] }, "body": ["b"] }).is_empty())

	# --- 3. Event列の組み立て：形・new_bowl・aggregate・既定値・好物なし・反応なし・退店会話 ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var events := Day1Events.customer_events("thug", 0, "multi_x")
	c.check("列の形：GREET×2 → (ADJUST → SERVE → REACT → 会話)×3",
		_types(events) == ["GREET", "GREET", "ADJUST", "SERVE", "REACT", "GREET",
			"ADJUST", "SERVE", "REACT", "GREET", "GREET", "ADJUST", "SERVE", "REACT", "GREET"], str(_types(events)))
	c.check("来店の会話は場面の greet", events[0]["text"] == "来店1" and events[1]["text"] == "来店2" and events[0]["customer"] == "thug")
	c.check("ADJUST の new_bowl は2杯目以降にだけ付く",
		not events[2].has("new_bowl") and events[6]["new_bowl"] == true and events[11]["new_bowl"] == true)
	c.check("ADJUST・SERVE の text：省略は既定文、指定はその文",
		events[2]["text"] == "（味を調える）" and events[3]["text"] == "「はいよ、お待ち。」"
			and events[6]["text"] == "（2杯目を調える）" and events[7]["text"] == "（2杯目を置く）"
			and events[11]["text"] == "（持ち帰り用）" and events[12]["text"] == "（袋へ入れる）")
	c.check("ADJUST は同じ選択肢（_adjust_options）", events[2]["options"] == Day1Events._adjust_options()
		and events[6]["options"] == events[2]["options"])
	var reacts := events.filter(func(e): return e["type"] == "REACT")
	var all_aggregate := true
	var all_one := true
	for r in reacts:
		all_aggregate = all_aggregate and r["aggregate"] == true and r["is_mob"] == false
		all_one = all_one and r["servings"] == 1 and r["sale"] == GameState.PRICE_PER_SERVING
	c.check("全 REACT に aggregate:true・is_mob:false・servings:1・sale＝1杯の売上", reacts.size() == 3 and all_aggregate and all_one)
	c.check("要求タグ：省略＝プロフィール（MELLOW/GENTLE）、指定＝その杯だけ",
		reacts[0]["wanted_tags"] == ["MELLOW", "GENTLE"] and reacts[1]["wanted_tags"] == ["HOT", "POWER"]
			and reacts[2]["wanted_tags"] == ["MELLOW", "GENTLE"])
	c.check("好物：省略＝プロフィール（meat_ball）、false の杯は favorite のキー自体が無い",
		reacts[0]["favorite"] == "meat_ball" and reacts[1]["favorite"] == "meat_ball" and not reacts[2].has("favorite"))
	c.check("反応：杯ごとの reactions。省略または空は空辞書（反応を出さない）",
		reacts[0]["reactions"]["GREAT"] == ["R1:GREAT"] and reacts[1]["reactions"] == { "GOOD": ["R2:GOOD"] }
			and reacts[2]["reactions"] == {})
	c.check("各杯のあとの会話：その杯の after_talk（最後の杯の分が退店の会話）",
		events[5]["text"] == "1杯目のあと" and events[9]["text"] == "2杯目のあと" and events[10]["text"] == "もう1行"
			and events[14]["text"] == "退店" and events.size() == 15)
	c.check("何度呼んでも同じ列（状態を読むだけ）", _norm(Day1Events.customer_events("thug", 0, "multi_x")) == _norm(events))
	events[4]["reactions"]["GREAT"].append("x")
	c.check("組んだ列を書き換えても場面データは変わらない（深いコピー）",
		ScheduleData.episode_cups("thug", "multi_x")[0]["reactions"]["GREAT"] == ["R1:GREAT"])

	# --- 4. 1杯の場面だけの機能は出ない（提供後の列・閉店で退店する客の未提供版・締め） ---
	ScheduleData._episode_cache["thug/multi_x"] = _cups_scene({ "body": ["本文"], "closing": { "default": ["締め"] },
		"must_info": ["night_removal"], "body_unserved": ["未提供"] })
	c.check("複数杯の場面には本文・締め・未提供版を差さない（キーが書かれていても空）",
		Day1Events.after_serve_events("thug", "multi_x", { "served": true }).is_empty()
			and Day1Events.after_serve_events("thug", "multi_x", { "served": false }).is_empty()
			and Day1Events.closing_events("thug", "multi_x").is_empty()
			and Day1Events.unserved_exit_events("thug", "multi_x").is_empty())
	ScheduleData._episode_cache["thug/multi_x"] = _cups_scene()

	# --- 5. 杯数の先読み・朝の予報：cups から組んだ列でも合計と注文が出る ---
	ScheduleData._episode_cache["thug/thug_02"] = _cups_scene({ "id": "thug_02" })   # Day2のチンピラの場面
	GameState.reset_for_new_game()
	GameState.day_count = 2
	c.check("_customer_total_servings は cups の数（3杯）", Day1Events._customer_total_servings("thug", "thug_02") == 3)
	var orders := Forecast.orders_of("thug")
	c.check("Forecast.orders_of：杯ごとの注文タグと杯数（基本注文の2杯＋指定の1杯）",
		orders.size() == 3 and orders[0]["tags"] == ["MELLOW", "GENTLE"] and orders[1]["tags"] == ["HOT", "POWER"]
			and orders[2]["servings"] == 1, str(orders))
	c.check("注文カードの対象外（_adjust_customer_id の判定になる複数杯の場面）",
		Day1Events.is_multi_cup_scene("thug", Day1Events.episode_id_of("thug")))

	# --- 6. 受け側（DebugPanel）は変えずに通る：2杯の通し・注文カードと[聞き直す]が出ない ---
	ScheduleData._episode_cache["thug/thug_02"] = _cups_scene({ "id": "thug_02", "cups": [
		{ "reactions": { "GREAT": ["R1:GREAT"], "GOOD": ["R1:GOOD"], "OK": ["R1:OK"], "BAD": ["R1:BAD"] },
			"after_talk": ["1杯目のあと"] },
		{ "tags": ["HOT", "POWER"], "reactions": {}, "after_talk": ["退店"] } ] })
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": ["thug", "granny"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	var money_before: int = GameState.money
	panel._load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()
	c.check("1杯目のADJUST：注文カードと[聞き直す]の対象外", panel._adjust_customer_id() == "")
	panel._on_ingredient_selected("coconut_milk")
	panel._on_ingredient_selected("tofu")
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()   # REACT（1杯目）
	c.check("1杯目の反応は杯の reactions（GOOD）", panel._current_reaction_text() == "R1:GOOD", panel._current_reaction_text())
	c.check("提供後の列（本文・選択）は差し込まれない（aggregate）", not str(panel.flow.runner.events).contains("\"part\""))
	panel._on_next_event_pressed()   # 1杯目のあと
	guard = 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 20:
		guard += 1
		panel._on_next_event_pressed()
	c.check("2杯目のADJUST：椀は新しくなり（new_bowl）、注文カードの対象外のまま",
		(panel._open.current_bowl.get("additions", []) as Array).is_empty() and panel._adjust_customer_id() == "")
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("offal")
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()   # REACT（2杯目）
	c.check("2杯目は反応なし（reactions 空）", panel._current_reaction_text() == "")
	c.check("2杯の売上がその場で入る（aggregate）", GameState.money == money_before + 2 * GameState.PRICE_PER_SERVING)
	c.check("来店記録に2杯ぶんの提供（served=2）", int(CustomerMemory.last_visit("thug")["served"]) == 2
		and (CustomerMemory.last_visit("thug")["grades"] as Array).size() == 2)
	panel.free()

	# --- 7. 配達員のDay1（delivery_man_01）：cups から組んだ列が4-3の記録と完全に同一 ---
	# 記録（tests/fixtures/customer_events_4_3.json）と、キーの有無まで含めて厳密に照合する
	# （JSONを通した形にそろえ、辞書の値とキー集合が一致。3杯目の REACT に favorite が付かないことも）。
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	GameState.day_count = 1
	GameState.add_inventory("nam_prik_pao", 2)   # 記録時と同じ固定の在庫（ADJUSTのoptionsが在庫から組まれる）
	GameState.add_inventory("tofu", 1)
	GameState.add_inventory("herbal_sauce", 1)
	var recorded = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/customer_events_4_3.json"))
	var recorded_events: Array = recorded["1"]["delivery_man"]
	var now_events: Array = _norm(Day1Events.customer_events("delivery_man"))
	c.check("（前提）Day1の配達員は複数杯の場面（delivery_man_01）", Day1Events.episode_id_of("delivery_man") == "delivery_man_01"
		and Day1Events.is_multi_cup_scene("delivery_man", "delivery_man_01"))
	c.check("イベント数が記録と同じ（%d）" % recorded_events.size(), now_events.size() == recorded_events.size())
	var same_all := now_events == recorded_events
	c.check("Day1の配達員のEvent列が記録と完全に一致（値の一致）", same_all)
	var keys_same := true
	for i in range(mini(now_events.size(), recorded_events.size())):
		var a: Array = (now_events[i] as Dictionary).keys()
		var b: Array = (recorded_events[i] as Dictionary).keys()
		a.sort()
		b.sort()
		keys_same = keys_same and a == b
	c.check("各イベントのキー集合も記録と一致（キーの過不足なし）", keys_same)
	var recorded_reacts := recorded_events.filter(func(e): return e["type"] == "REACT")
	var now_reacts := now_events.filter(func(e): return e["type"] == "REACT")
	c.check("3杯目のREACTに favorite が付かない（記録と同じ）。1・2杯目は付く（tofu）",
		recorded_reacts.size() == 3 and now_reacts.size() == 3 and not (now_reacts[2] as Dictionary).has("favorite")
			and now_reacts[0]["favorite"] == "tofu" and now_reacts[1]["favorite"] == "tofu"
			and (now_reacts[2] as Dictionary).keys().size() == (recorded_reacts[2] as Dictionary).keys().size())
	c.check("3杯目の注文は直書きだった MELLOW/GENTLE のまま・反応は空辞書",
		now_reacts[2]["wanted_tags"] == ["MELLOW", "GENTLE"] and now_reacts[2]["reactions"] == {})
	c.check("1・2杯目の要求タグはプロフィール（HOT/POWER）で、反応は各結果1パターンのまま",
		now_reacts[0]["wanted_tags"] == ["HOT", "POWER"] and now_reacts[1]["wanted_tags"] == ["HOT", "POWER"]
			and (now_reacts[0]["reactions"]["GOOD"] as Array).size() == 1 and (now_reacts[1]["reactions"]["GREAT"] as Array).size() == 1)
	c.check("Day1の杯数の先読み：配達員3杯・Day1の予報の注文は3件",
		Day1Events._customer_total_servings("delivery_man", "delivery_man_01") == 3 and Forecast.orders_of("delivery_man").size() == 3)
	c.check("提供後の列・未提供版・締めは配達員の3杯には差さない",
		Day1Events.after_serve_events("delivery_man", "delivery_man_01", { "served": true }).is_empty()
			and Day1Events.unserved_exit_events("delivery_man", "delivery_man_01").is_empty()
			and Day1Events.closing_events("delivery_man", "delivery_man_01").is_empty())
	var legacy_panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(legacy_panel)
	GameState.phase = GameState.Phase.OPEN
	legacy_panel._open = OpenController.new([{ "name": "宵の口", "customers": ["delivery_man"] }])
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	legacy_panel._load_current_customer()
	guard = 0
	while legacy_panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		legacy_panel._on_next_event_pressed()
	c.check("Day1の配達員のADJUST：注文カードと[聞き直す]の対象外（_adjust_customer_id）",
		str(legacy_panel.flow.runner.current()["type"]) == "ADJUST" and legacy_panel._adjust_customer_id() == "")
	legacy_panel.free()

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
