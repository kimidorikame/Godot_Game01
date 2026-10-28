extends RefCounted
## DMの日付表示（UI準備G0。表示だけ）。「Day3 05:40」の形（日付＋2桁の時刻）。日付の文字列は Calendar の1か所で作る。
## 対象：Calendar の形式（日・時刻・合わせた形）／スマホのDMの行（過去日のDMは届いた日の日付・来店予告も同じ形）／ニュースの日付の見出し／
## 既読の印（id）と本文・差出人は変えない。


func _label_texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_label_texts(child, out)
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	c.check("日の表示は「Day3」", Calendar.label(3) == "Day3" and Calendar.label(12) == "Day12")
	c.check("時刻は2桁にそろえる（5:40→05:40・6:05→06:05・10:30のまま）", Calendar.time_text("5:40") == "05:40" and Calendar.time_text("6:05") == "06:05"
		and Calendar.time_text("10:30") == "10:30" and Calendar.time_text("05:40") == "05:40")
	c.check("形が違う時刻はそのまま返す", Calendar.time_text("明け方") == "明け方")
	c.check("日付＋時刻は「Day3 05:40」", Calendar.stamp(3, "5:40") == "Day3 05:40")

	# --- スマホのDM（過去日・来店予告）---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.day_count = 3
	GameState.today_plan = { "day": 3, "slots": [{ "name": "宵の口", "customers": ["officer", "mob#0"], "regular_id": "officer", "episode_id": "", "today_request": {} },
		{ "name": "夜半", "customers": ["thug"], "regular_id": "thug", "episode_id": "", "today_request": {} }],
		"mob_instances": { "mob#0": { "type": "dock_workers", "count": 2 } }, "demand_center": 9 }
	GameState.customer_memory["officer"] = { "favorite_known": false, "facts": {}, "seen_episodes": [],
		"visits": [{ "day": 2, "slot": "宵の口", "served": 1, "grade": "GOOD", "grades": ["GOOD"], "ingredients": [], "episode_id": "" }] }
	var items := s.phone_dm()
	var before_ids: Array = items.map(func(x): return str(x["id"]))
	var phone: UiPanePhone = root.pane_phone
	phone.tab = "sns"
	phone.refresh()
	var texts := _label_texts(phone.get_node("%Content"))
	var stamps := texts.filter(func(x): return RegEx.create_from_string("^Day[0-9]+ [0-9]{2}:[0-9]{2}$").search(str(x)) != null)
	c.check("DMの一覧：どの行も「Day3 05:40」の形（日付＋2桁の時刻）", stamps.size() == items.size() and not items.is_empty(), "%d/%d %s" % [stamps.size(), items.size(), str(texts.slice(0, 8))])
	var past_ok := true
	var preview_ok := false
	for item in items:
		var want := Calendar.stamp(int(item["day"]), str(item["time"]))
		past_ok = past_ok and texts.has(want)
		if bool(item.get("preview", false)):
			preview_ok = preview_ok or texts.has(want)
	c.check("過去日のDMは、届いた日の日付で出る（Day2のDMは Day2、今日のDMは Day3）", past_ok and items.any(func(x): return int(x["day"]) == 2) and items.any(func(x): return int(x["day"]) == 3))
	c.check("来店予告のDMも同じ形（日付＋2桁の時刻）", preview_ok)
	c.check("本文・差出人・既読の印（id）は変わらない（id は preview_d＜日＞＜主語＞・d2_market など）",
		before_ids.any(func(x): return str(x).begins_with("preview_d3_")) and before_ids.has("d2_market") and not texts.any(func(x): return str(x).contains("{")))

	# --- ニュースの日付の見出し ---
	phone.tab = "news"
	phone.refresh()
	var news_texts := _label_texts(phone.get_node("%Content"))
	c.check("ニュースの日付の見出しは「Day3（今日）」（Calendar の形。ニュースに時刻は出ない）", news_texts.has("Day3（今日）") or news_texts.has("Day2"), str(news_texts.slice(0, 5)))
	root.queue_free()
	ReadState.reset(ReadState.path)   # SNSタブを開いて既読にしたぶんを捨てる（後のスイートの未読の数に影響させない）
	GameState.reset_for_new_game()
	return c.finish()
