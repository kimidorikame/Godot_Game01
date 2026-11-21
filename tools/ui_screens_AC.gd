# UI準備AC（6日目＝火事の日の仕組み。文は仮）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AC.gd    → planning/ui_screens_AC/
# 撮るもの：火事の場面の始め（明け方の最初の客の前）・show_news の行・show_dm（転送）の行・明け方の始めのスマホ（DM の未読の印・
# ニュースの速報の印・火事のあとの投稿）・閉店の前の場面。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。撮影の道具の中だけで、5日目と6日目の朝に所持金を足し、6日目の開店で鍋を足す
# （自動の遊び手は所持金が少なく具を買えないため・鍋が尽きて早仕舞いすると、明け方の始めの場面が閉店の前にまとめて出るため）。ゲームのデータは変えない。
extends SceneTree

var out_dir := "res://planning/ui_screens_AC"
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
	var text_is := func(t: String): return str(s.current_line().get("speaker_name", "")) + str(s.current_line().get("text", "")) == t
	var cur_key := func(key: String, value: String): return s.flow.runner != null and s.flow.runner.current() is Dictionary and str((s.flow.runner.current() as Dictionary).get(key, "")) == value

	await _until(func(): return gs.day_count == 5 and gs.phase == gs.Phase.WAKE, 40000)
	gs.money += 500   # 撮影の道具の中だけ
	await _until(func(): return gs.day_count == 6 and gs.phase == gs.Phase.WAKE, 20000)
	gs.money += 500   # 撮影の道具の中だけ
	await _until(func(): return gs.phase == gs.Phase.OPEN and gs.soup != null)
	gs.soup["remaining_servings"] = int(gs.soup["remaining_servings"]) + 8   # 撮影の道具の中だけ
	await _until(func(): return text_is.call("店主「……港の方か」"), 12000)
	print("AC_SLOT %s served_mobs=%s" % [s.open.current_slot_name() if s.open != null else "-", str(load("res://scripts/day1_events.gd").mob_types_served_on(6))])
	await _shot("01_fire_start", "6日目・明け方の最初の客の前：火事の場面の始め（店主「……港の方か」）")
	await _until(func(): return cur_key.call("news_id", "d6_flash_fire"))
	await _shot("02_show_news", "火事の場面：show_news の行（速報の見出しを会話枠に出す）")
	await _until(func(): return cur_key.call("dm_id", "d6_dock_0305"))
	await _shot("03_show_dm_forward", "明け方の始め：show_dm の行（港湾労働者からの転送 03:05。本文と写真の説明。出したら既読）")
	await _until(func(): return gs.phase == gs.Phase.OPEN and s.open != null and str(s.open.current_slot_name()) == "明け方" and str(s.current_line().get("part", "")) != "common_event")
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("04_phone_dm", "明け方の始めのスマホ：DM（火事のあとの張姐・梁伯に未読の印。会話枠に出した転送は既読）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("05_phone_news", "明け方の始めのスマホ：ニュース（今日の欄の先頭に速報 02:12）")
	ui.close_overlay()
	ui.open_phone("sns")
	phone.show_timeline()
	await _shot("06_phone_timeline", "明け方の始めのスマホ：タイムライン（火事のあとの投稿 02:23・02:50・04:30）")
	ui.close_overlay()
	await _until(func(): return text_is.call("店主「今日の帳面は、ここまでか」"), 12000)
	await _shot("07_before_close", "閉店の前の場面（at:close）")
	await _until(func(): return cur_key.call("dm_id", "d6_zhang_0455"))
	await _shot("08_close_dm", "閉店の前：show_dm の行（張姐 04:55）")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備AC のスクリーンショット（tools/ui_screens_AC.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
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
