extends RefCounted
## UI準備AC：6日目（火事の日）の仕組みの検証（文は仮。本番の文は中身AD）。
##   1. 条件付きの行のモブの条件（mob_served・not_mob_served。今日／day 付き）。共通イベントの行と場面の行の両方
##   2. 出来事のあとのDM（after_event）・速報（ニュースの after_event・time）・投稿（requires.after_event）：場面の前は見えず、あとで見える。次の日も見える
##   3. 接客のあとのDM（after_visit。差し込んだデータで。7日目に使う形）
##   4. DMの受信箱の並び（朝のDMは時刻のまま、夜のDMは 00:00〜04:59 をその日の24時以降。「7:10」「10:05」「23:50」「02:18」「04:55」）
##   5. 共通イベントの show_dm・show_news：会話枠に出る行の形と、出したDMが既読になること
##   6. データの検査（壊れた形を弾く）


func _ids(items: Array) -> Array:
	return items.map(func(x): return str(x["id"]))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	News.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	ScheduleData.clear_cache()
	ReadState.reset("user://test_read_fire_day.json")

	# --- 1. モブの条件 ---
	GameState.reset_for_new_game()
	GameState.day_count = 6
	GameState.today_plan = { "day": 6, "slots": [], "mob_instances": { "mob#0": { "type": "security_guard", "count": 2 }, "mob#1": { "type": "dock_workers", "count": 1 } } }
	var served := { "mob_served": "security_guard" }
	var not_served := { "not_mob_served": "security_guard" }
	c.check("今夜まだ出していない：mob_served は偽・not_mob_served は真", not CustomerMemory.condition_met(served, "") and CustomerMemory.condition_met(not_served, ""))
	GameState.served.append({ "customer": "mob#1", "servings": 1 })
	c.check("ほかの種類（港湾労働者）に出しても、夜勤警備員の条件は変わらない", not CustomerMemory.condition_met(served, ""))
	GameState.served.append({ "customer": "mob#0", "servings": 2 })
	c.check("今夜、夜勤警備員に出した：mob_served は真・not_mob_served は偽", CustomerMemory.condition_met(served, "") and not CustomerMemory.condition_met(not_served, ""))
	var fire_lines := News.event_texts(News.event_by_id(6, "d6_fire"), 6)
	c.check("火災の場面：夜勤警備員に出した晩は「……さっきの飯、持って帰ったばかりだぞ」の行（来なかった晩の行は出ない）",
		fire_lines.has("店主「……さっきの飯、持って帰ったばかりだぞ」") and not fire_lines.has("店主「……阿強、今夜はどこの門だ」"), str(fire_lines))
	GameState.served = [{ "customer": "mob#0", "servings": 0, "declined": true }]
	var fire_lines2 := News.event_texts(News.event_by_id(6, "d6_fire"), 6)
	c.check("断った（0杯）晩は出していない扱い：「……阿強、今夜はどこの門だ」の行", fire_lines2.has("店主「……阿強、今夜はどこの門だ」")
		and not fire_lines2.has("店主「……さっきの飯、持って帰ったばかりだぞ」"), str(fire_lines2))
	# day 付き（7日目のリンの場面で使う形）：過ぎた日は日次ログの mob_types_served
	GameState.day_count = 7
	GameState.day_records = [{ "day": 6, "mob_types_served": ["security_guard"] }, { "day": 5, "mob_types_served": ["dock_workers"] }]
	c.check("day 付き：6日目に夜勤警備員に出した（日次ログ）・5日目には出していない",
		CustomerMemory.condition_met({ "mob_served": "security_guard", "day": 6 }, "") and not CustomerMemory.condition_met({ "mob_served": "security_guard", "day": 5 }, "")
			and CustomerMemory.condition_met({ "not_mob_served": "security_guard", "day": 5 }, ""))
	var scene_lines := CustomerMemory.resolve_lines(["リン「a」", { "if": { "mob_served": "security_guard", "day": 6 }, "lines": ["リン「b」"] },
		{ "if": { "not_mob_served": "security_guard", "day": 6 }, "lines": ["リン「c」"] }], "officer")
	c.check("場面の行でも使える（条件付きの行のまとまり）", scene_lines == ["リン「a」", "リン「b」"], str(scene_lines))
	c.check("過ぎた日の出来事を読み返すときは、その日の晩の状態で選ぶ（6日目の火災の場面を7日目に）",
		News.event_texts(News.event_by_id(6, "d6_fire"), 6).has("店主「……さっきの飯、持って帰ったばかりだぞ」"))
	c.check("条件の形の検査：mob_served・day は通り、未知の種類・customer との組み合わせ・day の範囲外・fact に day は弾く",
		ScheduleData.condition_problems({ "mob_served": "security_guard", "day": 6 }, "x").is_empty()
			and ScheduleData.condition_problems({ "not_mob_served": "dock_workers" }, "x").is_empty()
			and not ScheduleData.condition_problems({ "mob_served": "no_such_mob" }, "x").is_empty()
			and not ScheduleData.condition_problems({ "mob_served": "security_guard", "customer": "officer" }, "x").is_empty()
			and not ScheduleData.condition_problems({ "mob_served": "security_guard", "day": 9 }, "x").is_empty()
			and not ScheduleData.condition_problems({ "fact": "x", "day": 6 }, "x").is_empty())

	# --- 2. 出来事のあとのDM・速報・投稿 ---
	GameState.reset_for_new_game()
	GameState.day_count = 6
	var night_ids := ["d6_zhang_0218", "d6_liang_0226", "d6_dock_0305", "d6_zhang_0455"]
	var before_ids := _ids(Dm.inbox(6))
	c.check("場面の前：火事のあとのDMは届いていない（朝のDMは届いている）", not night_ids.any(func(id): return before_ids.has(id)) and before_ids.has("d6_market"), str(before_ids))
	var after_fire := _ids(Dm.inbox(6, {}, ["d6_fire", "d6_fire_news"]))
	c.check("火災の場面のあと：張姐 02:18・梁伯 02:26 が届く（03:05 は明け方の始め d6_dawn のあと、04:55 は閉店の前 d6_close のあと）",
		after_fire.has("d6_zhang_0218") and after_fire.has("d6_liang_0226") and not after_fire.has("d6_dock_0305") and not after_fire.has("d6_zhang_0455"), str(after_fire))
	var all_played := _ids(Dm.inbox(6, {}, ["d6_fire", "d6_fire_news", "d6_dawn", "d6_close"]))
	c.check("4件とも再生したあと：夜のDM（会っていない客の分を除く）が新しい順に届き、そのあとに朝のDM（04:55 → 03:40 → 03:12 → 03:05 → 02:26 → 02:20 → 02:18 → 朝の 6:35）",
		all_played.slice(0, 8) == ["d6_zhang_0455", "d6_hai_0340", "d6_dock_0312", "d6_dock_0305", "d6_liang_0226", "d6_zhang_0220", "d6_zhang_0218", "d6_market"], str(all_played))
	GameState.day_count = 7
	var day7_inbox := Dm.inbox(7).filter(func(x): return int(x["day"]) == 6)
	c.check("次の日（7日目）：6日目の夜のDMは条件なしに残る", night_ids.all(func(id): return _ids(day7_inbox).has(id)))
	GameState.day_count = 6
	var morning6 := _ids(News.visible_news(6, 6, []))
	c.check("速報：場面の前は一覧に無く、火災の場面のあとは朝の記事より上に、時刻の新しい順（02:55 → 02:12）で出る。次の日は条件なし",
		not morning6.has("d6_flash_fire") and morning6.size() == 4
			and _ids(News.visible_news(6, 6, ["d6_fire"])) == ["d6_flash_fire"] + morning6
			and _ids(News.visible_news(6, 6, ["d6_fire", "d6_dawn"])) == ["d6_flash_closure", "d6_flash_fire"] + morning6
			and _ids(News.visible_news(6, 7, [])) == ["d6_flash_closure", "d6_flash_fire"] + morning6)
	c.check("速報は朝の語り（morning_events）に出ない・must_info を持たない",
		not News.morning_events(6).any(func(e): return str(e["text"]).contains("速報")) and (News.news_by_id(6, "d6_flash_fire")["must_info"] as Array).is_empty())
	var after_posts: Array = Sns.posts().filter(func(x): return int(x["day"]) == 6 and (x.get("requires", {}) as Dictionary).has("after_event")).map(func(x): return str(x["id"]))
	var vis_before := Sns.visible_ids(6, Sns.LIMIT_DAY_END)
	var vis_after := Sns.visible_ids(6, Sns.LIMIT_DAY_END, {}, [], [], ["d6_fire"])
	c.check("投稿：火事のあとの %d 件は、明け方の時刻でも場面の前は見えず、場面のあとは見える。次の日は条件なし" % after_posts.size(),
		after_posts.size() == 14 and not after_posts.any(func(id): return vis_before.has(id)) and after_posts.all(func(id): return vis_after.has(id))
			and after_posts.all(func(id): return Sns.visible_ids(7, Sns.LIMIT_MORNING).has(id)))
	c.check("投稿：場面のあとでも、見える時刻の決まりはそのまま（夜半の上限 00:59 では 02:23 以降は見えない）",
		not after_posts.any(func(id): return Sns.visible_ids(6, Sns.LIMIT_MIDNIGHT, {}, [], [], ["d6_fire"]).has(id)))

	# --- 3. 接客のあとのDM（after_visit。差し込んだデータで） ---
	var custom: Dictionary = Dm.data().duplicate(true)
	(custom["days"]["7"] as Array).append({ "id": "d7_dock_after_nika", "from": "港湾労働者", "from_kind": "npc", "time": "01:10", "after_visit": "streamer",
		"text": "x", "hint": "none", "provisional": true })
	GameState.day_count = 7
	c.check("after_visit：その客の接客が済む前は届かず、済んだら届く。形の検査も通る",
		not _ids(Dm.inbox(7, custom)).has("d7_dock_after_nika") and _ids(Dm.inbox(7, custom, [], ["streamer"])).has("d7_dock_after_nika")
			and Dm.problems(custom).is_empty(), str(Dm.problems(custom)))
	GameState.day_count = 8
	var next_unmet := _ids(Dm.inbox(7, custom)).has("d7_dock_after_nika")
	GameState.customer_memory["streamer"] = { "favorite_known": false, "visits": [{ "day": 7, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	c.check("after_visit：次の日は、その日にその客が来ていれば届き、来ていなければ届かない（来店記録で決める。UI準備AF）",
		_ids(Dm.inbox(7, custom)).has("d7_dock_after_nika") and not next_unmet)
	GameState.customer_memory.erase("streamer")

	# --- 4. 受信箱の並び ---
	var order_data: Dictionary = Dm.data().duplicate(true)
	order_data["days"]["6"] = [
		{ "id": "m0710", "from": "a", "from_kind": "npc", "time": "7:10", "text": "x", "hint": "none", "provisional": true },
		{ "id": "m1005", "from": "b", "from_kind": "npc", "time": "10:05", "text": "x", "hint": "none", "provisional": true },
		{ "id": "n2350", "from": "c", "from_kind": "npc", "time": "23:50", "after_event": "d6_fire", "text": "x", "hint": "none", "provisional": true },
		{ "id": "n0218", "from": "d", "from_kind": "npc", "time": "02:18", "after_event": "d6_fire", "text": "x", "hint": "none", "provisional": true },
		{ "id": "n0455", "from": "e", "from_kind": "npc", "time": "04:55", "after_event": "d6_fire", "text": "x", "hint": "none", "provisional": true }]
	GameState.day_count = 6
	var today_ids := Dm.inbox(6, order_data, ["d6_fire"]).filter(func(x): return int(x["day"]) == 6 and not bool(x.get("preview", false))).map(func(x): return str(x["id"]))
	c.check("受信箱の並び：その日の時刻順（新しい順）＝ 04:55 → 02:18 → 23:50 → 10:05 → 7:10（文字で比べると 7:10 が 10:05 より新しくなっていた）",
		today_ids == ["n0455", "n0218", "n2350", "m1005", "m0710"], str(today_ids))
	c.check("相手ごとの並びの値も同じ数え方（夜のDMの 02:18 は同じ日の 23:50 より新しい・朝の 4:45 は 7:10 より古い）",
		PlaySession._dm_order({ "day": 6, "time": "02:18", "night": true }) > PlaySession._dm_order({ "day": 6, "time": "23:50", "night": true })
			and PlaySession._dm_order({ "day": 6, "time": "4:45" }) < PlaySession._dm_order({ "day": 6, "time": "7:10" }))

	# --- 5. show_dm・show_news ---
	GameState.reset_for_new_game()
	GameState.day_count = 6
	var news_ev := News.event_lines(News.event_by_id(6, "d6_fire_news"), 6)
	c.check("show_news：速報の見出しの1行（「速報：…」・news_id 付き）。show_dm：差出人の名前の札と本文の1行（dm_id 付き）",
		str(news_ev[0]["text"]) == "速報：" + str(News.news_by_id(6, "d6_flash_fire")["headline"]) and str(news_ev[0]["news_id"]) == "d6_flash_fire"
			and str(news_ev[2]["dm_id"]) == "d6_zhang_0218" and PlaySession.split_speaker(str(news_ev[2]["text"]))["name"] == "張姐", str(news_ev))
	var dawn_ev := News.event_lines(News.event_by_id(6, "d6_dawn"), 6)
	var forward: Dictionary = dawn_ev.filter(func(e): return str(e.get("dm_id", "")) == "d6_dock_0305")[0]
	c.check("転送（03:05）：本文のあとに写真の説明（［写真：…］）も会話枠に出る", str(forward["text"]).contains("［写真：") and str(forward["text"]).begins_with("港湾労働者「"))
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	panel.session.flow.force_phase(GameState.Phase.CLOSE)   # 客0人の晩：火災の場面から閉店の前まで、閉店の前に取り戻す
	var dm_keys := ["d6_zhang_0218", "d6_zhang_0220", "d6_dock_0305", "d6_dock_0312", "d6_zhang_0455"]
	c.check("（前提）場面を再生した：夜のDMが届いて、未読（会話枠に出す前）", dm_keys.all(func(id): return _ids(panel.session.dm_inbox()).has(id))
		and dm_keys.all(func(id): return not ReadState.is_read(panel.session._dm_read_key({ "id": id }))))
	var unread_before: int = panel.session.dm_unread_count()
	var guard := 0
	while panel.session.flow.runner != null and not panel.session.flow.is_runner_done() and guard < 80:
		guard += 1
		panel.session.record_visible_event()
		panel.session.flow.runner.advance()
	c.check("会話枠に出した DM（張姐 02:18・02:20・転送 03:05・03:12・張姐 04:55）は既読になる。出していない梁伯 02:26 は未読のまま",
		dm_keys.all(func(id): return ReadState.is_read(panel.session._dm_read_key({ "id": id })))
			and not ReadState.is_read(panel.session._dm_read_key({ "id": "d6_liang_0226" })) and panel.session.dm_unread_count() == unread_before - 5)
	var phone_news: Array = panel.session.phone_news()
	c.check("スマホのニュース：今日の欄の先頭に速報2本（flash・時刻 02:55 → 02:12）",
		bool(phone_news[0]["news"][0]["flash"]) and str(phone_news[0]["news"][0]["time"]) == "02:55" and str(phone_news[0]["news"][1]["time"]) == "02:12")
	panel.free()

	# --- 6. データの検査 ---
	c.check("本番のデータ（ニュース・DM・タイムライン）に問題が無い", News.problems().is_empty() and Dm.problems().is_empty() and Sns.problems().is_empty(),
		str(News.problems()) + str(Dm.problems()) + str(Sns.problems()))
	var bad_news: Dictionary = News.data().duplicate(true)
	(bad_news["days"]["6"]["events"][1]["lines"] as Array).append({ "show_dm": "no_such_dm" })
	for item in bad_news["days"]["6"]["news"]:
		if str(item["id"]) == "d6_flash_fire":
			(item as Dictionary)["must_info"] = ["warehouse_fire"]
	(bad_news["days"]["6"]["events"][0]["lines"] as Array).append({ "show_photo": "x" })
	var news_problems := News.problems(bad_news)
	c.check("ニュースの検査：無い DM の show_dm・速報の must_info・知らない形の行を弾く",
		news_problems.any(func(x): return str(x).contains("no_such_dm")) and news_problems.any(func(x): return str(x).contains("速報に must_info"))
			and news_problems.any(func(x): return str(x).contains("show_news でない要素")), str(news_problems))
	var bad_dm: Dictionary = Dm.data().duplicate(true)
	(bad_dm["days"]["6"] as Array).append({ "id": "bad1", "from": "x", "from_kind": "npc", "time": "25:00", "after_event": "no_such_event", "text": "x", "hint": "none" })
	var dm_problems := Dm.problems(bad_dm)
	c.check("DMの検査：無い共通イベントの after_event・時刻の形を弾く", dm_problems.any(func(x): return str(x).contains("no_such_event")) and dm_problems.any(func(x): return str(x).contains("time")), str(dm_problems))
	var bad_sns: Dictionary = Sns.data().duplicate(true)
	(bad_sns["posts"] as Array).append({ "id": "bad_post", "account": "east_news", "day": 6, "time": "03:00", "text": "x", "requires": { "after_event": "no_such_event" }, "provisional": true })
	c.check("タイムラインの検査：無い共通イベントの requires.after_event を弾く", Sns.problems(bad_sns).any(func(x): return str(x).contains("no_such_event")))

	News.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()
