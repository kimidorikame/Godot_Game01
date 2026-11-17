# 中身Z2（1〜3日目の直し）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_Z2.gd    → planning/ui_screens_Z2/
# 撮るもの：1日目の阿強の OK（辛さは合った）・2日目の朝のホテルの夜番の予告DM・2日目のセティヤの OK（苦いは合った）・2日目の夜半のホテルの夜番・
# 3日目の朝のニュースの一覧と、いちばん長い記事の本文・3日目の夜半のタイムライン（ニカの 23:00 は「［動画：…］」）。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。OK の反応を見せるため、撮影の道具の中だけで2つの椀の具を選ぶ
# （1日目の阿強の1杯目＝ナムプリックパオ＋割れた餃子皮、2日目のセティヤ＝苦瓜〔ここで1個足す〕＋豆腐）。
extends SceneTree

var out_dir := "res://planning/ui_screens_Z2"
var gs
var ui
var play
var shots: Array = []


func _initialize() -> void:
	await process_frame
	load("res://scripts/morning_save.gd").set("save_path", "user://ui_screens_save.dat")
	load("res://scripts/morning_save.gd").call("delete_file")
	load("res://scripts/read_state.gd").call("reset", "user://ui_screens_read_state.json")
	load("res://scripts/balance_log.gd").set("path", "user://ui_screens_balance_log.jsonl")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	gs = root.get_node("GameState")
	gs.reset_for_new_game()
	gs.BAD_PRICE = gs.PRICE_PER_SERVING
	ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	ui.full_prep.auto_advance = false
	play = load("res://tests/ui_autoplay.gd").new(ui)
	var s = ui.session
	var phone = ui.pane_phone
	var news = load("res://scripts/news.gd")
	var line_starts := func(t: String): return (str(s.current_line().get("speaker_name", "")) + str(s.current_line().get("text", ""))).begins_with(t)
	var adjusting := func(customer: String, day: int):
		return gs.day_count == day and gs.phase == gs.Phase.OPEN and s.open != null and str(s.open.current_customer()) == customer \
			and s.flow.runner != null and s.flow.runner.current() is Dictionary and str(s.flow.runner.current().get("type", "")) == "ADJUST" \
			and (s.open.current_bowl.get("additions", []) as Array).is_empty()

	# 1日目：阿強の1杯目を OK に（辛い調味料＋腹もちの具＝スタミナが外れた）
	await _until(func(): return adjusting.call("delivery_man", 1))
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("broken_wrapper")
	await _until(func(): return str(s.current_line().get("type", "")) == "REACT" and s.current_reaction_text() != "")
	await _shot("01_day1_achang_ok", "1日目の阿強の1杯目：OK（辛さは合った＝スタミナが外れた）の文")
	# 2日目の朝：ホテルの夜番の予告DM
	await _until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 12000)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 60:
		guard += 1
		ui.left.advance()
	ui.open_phone("sns")
	phone.show_dm_list()
	if s.dm_threads().any(func(th): return str(th["key"]) == "mob:laundry_night"):
		phone.open_dm_thread("mob:laundry_night")
		await _shot("02_day2_dm_hotel", "2日目の朝：港のホテルの夜番の予告DM（差出人と本文）")
	else:
		await _shot("02_day2_dm_list", "2日目の朝：DMの相手の一覧（この周はホテルの夜番の予告が届かなかった）")
	ui.close_overlay()
	# 2日目の夜半：ホテルの夜番
	await _until(func(): return line_starts.call("夜番「港のホテル。フロントは機械だから"))
	await _shot("03_day2_hotel_night", "2日目の夜半：港のホテルの夜番（名前の札は「夜番」）")
	# 2日目の明け方：セティヤを OK に（苦い＋豆腐＝ごちそうが外れた）
	await _until(func(): return adjusting.call("hooker", 2))
	gs.add_inventory("bitter_melon", 1)
	s.select_ingredient("bitter_melon")
	s.select_ingredient("tofu")
	await _until(func(): return str(s.current_line().get("type", "")) == "REACT" and s.current_reaction_text() != "")
	await _shot("04_day2_setiya_ok", "2日目のセティヤ：OK（苦いは合った＝ごちそうが外れた）の文")
	# 3日目の朝：ニュースの一覧と、いちばん長い記事
	await _until(func(): return gs.day_count == 3 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 12000)
	guard = 0
	while not s.flow.is_runner_done() and guard < 80:
		guard += 1
		ui.left.advance()
	ui.open_phone("news")
	await _shot("05_news_list", "3日目の朝：ニュースの一覧（1〜3日目の12本）")
	var longest := ""
	var longest_day := 0
	var longest_len := 0
	for day in [1, 2, 3]:
		for item in news.call("day_entry", day)["news"]:
			var n := 0
			for para in item["body"]:
				n += str(para).length()
			if n > longest_len:
				longest_len = n
				longest = str(item["id"])
				longest_day = day
	load("res://tests/ui_autoplay.gd").press(phone.get_node("%Content").get_node("NewsRow_" + longest))
	await _shot("06_news_longest", "いちばん長い記事（%d日目の %s。本文 %d字）の本文（スクロールせずに全部見える）" % [longest_day, longest, longest_len])
	ui.close_overlay()
	# 3日目の夜半：ニカのあとのタイムライン（23:00 は動画）
	await _until(func(): return line_starts.call("夜番「売れたよ、まったく。"))
	ui.open_phone("sns")
	await _shot("07_timeline_video", "3日目の夜半・ニカのあと：タイムラインのニカの 23:00（「［動画：…］」）")
	ui.close_overlay()
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# 中身Z2 のスクリーンショット（tools/ui_screens_Z2.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _until(cond: Callable, limit: int = 8000) -> void:
	var n := 0
	while not cond.call() and n < limit:
		n += 1
		await process_frame
		if play.step() == "":
			break
	if not cond.call():
		push_error("状態に届かなかった（%d手）" % n)


func _shot(file_name: String, title: String) -> void:
	for i in range(4):
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, file_name]))
	shots.append("%s.png  %s" % [file_name, title])
