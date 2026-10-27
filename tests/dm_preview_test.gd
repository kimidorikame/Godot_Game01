extends RefCounted
## 来店予告DM（UI準備E）。その夜に来る予定の客・モブの種類を、朝のDMで知らせる。
## 対象：データの形（problems）／予告が today_plan と一致（いない客・種類は出ない）／上限と選び方（モブ最大2→名前あり客で上限3まで・
## 空いた分は名前あり客・好みが分かっている客を先・日付で回す・既存DMと同じ差出人は外す）／Day1 は出さない／読んでも乱数の順番が変わらない／
## 過去の日の再現（日次ログの planned_*）・旧セーブ／再挑戦・続きから（朝の封筒）で同じ内容／本文に数字・「客足」がない・{hint} が言葉になる／
## 未読の数に数える／日の終わりに planned_* が日次ログに入る。


func _plan(day: int, regulars: Array, mobs: Array) -> void:
	var slots: Array = []
	var instances := {}
	var seq := 0
	var names := ["宵の口", "夜半", "明け方"]
	for i in range(regulars.size()):
		var customers: Array = [regulars[i]]
		if i < mobs.size():
			var iid := "mob#%d" % seq
			seq += 1
			instances[iid] = { "type": mobs[i], "count": 2 }
			customers.append(iid)
		slots.append({ "name": names[i % 3], "customers": customers, "regular_id": regulars[i], "episode_id": "", "today_request": {} })
	GameState.today_plan = { "day": day, "slots": slots, "mob_instances": instances, "demand_center": 9 }


func _subjects(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if bool(item.get("preview", false)):
			out.append(str(item["subject"]))
	return out


func _visited(customer: String, day: int) -> void:
	GameState.customer_memory[customer] = { "favorite_known": false, "facts": {}, "seen_episodes": [],
		"visits": [{ "day": day, "slot": "宵の口", "served": 1, "grade": "GOOD", "grades": ["GOOD"], "ingredients": [], "episode_id": "" }] }


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Dm.clear_cache()
	c.check("データの形（previews を含む）に問題がない", Dm.problems().is_empty(), str(Dm.problems()))
	var cfg := Dm.previews_config()
	c.check("設定：上限3・モブ最大2・Day2から（データで変えられる）", int(cfg["max_per_morning"]) == 3 and int(cfg["mob_max"]) == 2 and int(cfg["first_day"]) == 2)

	# --- 1. 選び方 ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	_plan(3, ["hooker", "granny", "officer"], ["dock_workers", "inn_clerk", "market_porter"])
	var items := Dm.preview_items(3, [])
	var subs := _subjects(items)
	var mob_pick := ["dock_workers", "inn_clerk", "market_porter"]
	c.check("上限3件・モブ2件が先・次に名前あり客1件", subs.size() == 3 and mob_pick.has(subs[0]) and mob_pick.has(subs[1]) and not mob_pick.has(subs[2]), str(subs))
	c.check("モブは (日番号＋件目) % 候補数：Day3 は 0番目（dock_workers）と 1番目（inn_clerk）", subs[0] == mob_pick[3 % 3] and subs[1] == mob_pick[(3 + 1) % 3], str(subs))
	c.check("名前あり客は計画にいる客だけ", ["hooker", "granny", "officer"].has(subs[2]))
	c.check("予告は today_plan にいる客・種類だけ（全員は教えない）", subs.all(func(x): return ["hooker", "granny", "officer", "dock_workers", "inn_clerk", "market_porter"].has(x)))
	_plan(3, ["hooker", "granny", "officer"], ["dock_workers"])
	subs = _subjects(Dm.preview_items(3, []))
	c.check("モブが1種類の日：モブ1件＋名前あり客で上限3まで（空いた分を埋める）", subs.size() == 3 and subs[0] == "dock_workers", str(subs))
	_plan(3, ["hooker", "granny", "officer"], [])
	subs = _subjects(Dm.preview_items(3, []))
	c.check("モブが無い日：名前あり客3件", subs.size() == 3 and not subs.has("dock_workers"), str(subs))
	_plan(3, ["hooker"], [])
	c.check("計画が小さい日：計画にいる分だけ（嘘を足さない）", _subjects(Dm.preview_items(3, [])) == ["hooker"])
	# 好みが分かっている客を先に
	_plan(3, ["hooker", "granny", "officer"], ["dock_workers", "inn_clerk", "market_porter"])
	_visited("officer", 2)
	subs = _subjects(Dm.preview_items(3, []))
	c.check("名前あり客は、すでに来たことがある客（好みが分かっている）を先に", subs[2] == "officer", str(subs))
	GameState.customer_memory.clear()
	# 上限をデータで変える
	var source: Dictionary = Dm.data().duplicate(true)
	source["previews"]["max_per_morning"] = 1
	c.check("上限をデータで変えられる（1件）", _subjects(Dm.preview_items(3, [], source)).size() == 1)
	source["previews"]["max_per_morning"] = 5
	source["previews"]["mob_max"] = 3
	c.check("上限5・モブ最大3：モブ3＋名前あり客2", _subjects(Dm.preview_items(3, [], source)).size() == 5)
	# 既存DMと同じ差出人は外す
	GameState.reset_for_new_game()
	GameState.day_count = 2
	_plan(2, ["officer", "delivery_man", "thug"], ["dock_workers", "inn_clerk"])
	_visited("delivery_man", 1)
	var inbox := Dm.inbox(2)
	var existing_delivery := inbox.any(func(x): return str(x["id"]) == "d2_delivery_man")
	subs = _subjects(inbox)
	c.check("同じ朝に既存DM（Day2の配達員）が届くなら、配達員の予告は出さない", existing_delivery and not subs.has("delivery_man"), str(subs))
	c.check("Day2：予告も届く（モブ2件＋名前あり客1件）", subs.size() == 3, str(subs))
	# Day1
	GameState.reset_for_new_game()
	_plan(1, ["delivery_man", "thug", "granny"], ["dock_workers", "inn_clerk"])
	c.check("Day1 は予告を出さない（市場が閉まっていて固定の編成）", _subjects(Dm.inbox(1)).is_empty())

	# --- 2. 乱数の順番が変わらない ---
	GameState.reset_for_new_game()
	GameState.day_count = 4
	_plan(4, ["streamer", "hooker", "delivery_man"], ["security_guard", "market_porter"])
	seed(12345)
	var expected_a := randi()
	var expected_b := randf()
	seed(12345)
	Dm.inbox(4)
	Dm.delivered_for_day(4)
	Dm.preview_items(4, [])
	var got_a := randi()
	var got_b := randf()
	c.check("予告を読んでも、乱数の順番が変わらない", got_a == expected_a and is_equal_approx(got_b, expected_b))
	var first := Dm.inbox(4)
	c.check("同じ状態なら何度読んでも同じ（日付で決める）", JSON.stringify(first) == JSON.stringify(Dm.inbox(4)))

	# --- 3. 過去の日の再現・旧セーブ ---
	var day4_items := Dm.preview_items(4, [])
	var rec := { "day": 4, "opening_reputation": 40, "mob_types_served": [], "planned_regulars": Dm.plan_regulars(GameState.today_plan),
		"planned_mob_types": Dm.plan_mob_types(GameState.today_plan) }
	GameState.day_records = [rec]
	GameState.day_count = 5
	_plan(5, ["thug", "officer", "granny"], ["inn_clerk"])
	var past := Dm.preview_items(4, [])
	c.check("過去の日（Day4）の予告は、日次ログの planned_* から同じ内容で出る（計画は作り直されている）", JSON.stringify(past) == JSON.stringify(day4_items) and not past.is_empty())
	c.check("スマホの一覧にも、過去の日の予告が日付つきで残る", Dm.inbox(5).any(func(x): return str(x["id"]).begins_with("preview_d4_") and int(x["day"]) == 4))
	GameState.day_records = [{ "day": 4, "opening_reputation": 40, "mob_types_served": [] }]
	var old := Dm.preview_items(4, [])
	c.check("旧セーブ（planned_* が無い日）：モブの予告は出さず、名前あり客は日程データから", old.all(func(x): return str(x["from_kind"]) == "customer") and not old.is_empty(), str(_subjects(old)))

	# --- 4. 再挑戦・続きから（朝の封筒）で同じ内容 ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	_plan(3, ["hooker", "granny", "officer"], ["dock_workers", "inn_clerk"])
	var before := JSON.stringify(Dm.inbox(3))
	var envelope: Dictionary = MorningSave.capture("")
	_plan(3, ["thug"], [])
	GameState.day_count = 6
	MorningSave.apply(envelope)
	c.check("朝の封筒に戻すと（再挑戦・続きから）、同じ朝は同じ予告", JSON.stringify(Dm.inbox(3)) == before and not before.is_empty())

	# --- 5. 本文 ---
	var texts_ok := true
	var detail := ""
	GameState.reset_for_new_game()
	GameState.day_count = 2
	_plan(2, ["officer", "thug", "granny"], ["dock_workers", "inn_clerk"])
	for item in Dm.preview_items(2, []):
		var text := str(item["text"])
		if text == "" or text.contains("{") or text.contains("客足") or RegEx.create_from_string("[0-9０-９]").search(text) != null:
			texts_ok = false
			detail = text
	c.check("本文に数字・「客足」・置き換えのこり（{hint}）がない", texts_ok, detail)
	var pool: Dictionary = Dm.previews_config()["pools"]["dock_workers"]
	var one := Dm.preview_text(pool, "dock_workers", 2)
	c.check("モブの本文の {hint} は、好み2つのうち1つの言葉（tag_words.json）になる", one.contains(TagWords.word(str(pool["tag_hint"]))), one)
	var many: Dictionary = pool.duplicate(true)
	many["texts"] = ["A", "B", "C"]
	c.check("同じ客・種類に複数の文があるとき、日付で決める（同じ日・同じ主語なら同じ文・日が変われば変わりうる）",
		Dm.preview_text(many, "x", 2) == Dm.preview_text(many, "x", 2) and ["A", "B", "C"].has(Dm.preview_text(many, "x", 3)))
	# 検査が働く
	var bad: Dictionary = Dm.data().duplicate(true)
	bad["previews"]["pools"]["thug"]["tag_hint"] = "HOT"
	bad["previews"]["pools"]["inn_clerk"]["tag_hint"] = "HOT"
	bad["previews"]["pools"]["officer"]["texts"] = ["今夜3人で寄る予定です"]
	bad["previews"]["pools"]["granny"]["texts"] = ["今夜の客足は多め"]
	var problems := Dm.preview_problems(bad)
	c.check("検査：名前あり客の tag_hint・好みでない tag_hint・数字・「客足」を弾く", problems.size() >= 5, str(problems))

	# --- 6. 未読の数・日次ログ ---
	GameState.reset_for_new_game()
	var s := PlaySession.new()
	t.root.add_child(s)
	s.start()
	GameState.day_count = 2
	_plan(2, ["officer", "thug", "granny"], ["dock_workers", "inn_clerk"])
	var unread := s.dm_unread_count()
	c.check("来店予告も未読の数に数える（スマホの●・SNSタブの数）", unread == Dm.inbox(2).size() and unread >= 3 and s.phone_dm().any(func(x): return bool(x.get("preview", false)) and bool(x["unread"])))
	s.mark_dms_read()
	c.check("開いて読んだ扱いにすると、数が消える（既読は id で持つ）", s.dm_unread_count() == 0)
	s.free()

	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		play.step()
	var record1: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	c.check("日の終わりに、日次ログへ planned_regulars・planned_mob_types が入る（Day1の固定の編成）",
		record1.get("planned_regulars", []) == ["delivery_man", "thug", "granny"] and record1.get("planned_mob_types", []) == ["dock_workers", "inn_clerk"], str(record1))
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
