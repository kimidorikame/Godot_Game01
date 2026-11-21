# 中身AD（6日目＝火事の日の本番の文）と UI準備AD（会話枠の DM の印）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AD.gd    → planning/ui_screens_AD/
#   夜勤警備員が来なかった晩の店主の1行だけを撮るときは、末尾に「-- noguard」を付ける（6日目の計画から夜勤警備員の組を外す）。
# 撮るもの：張姐・梁伯・セティヤ・ニカ（公開依頼と日付）・火事の場面の始めと店主の1行（警備員が来た晩／来なかった晩）・速報の行・
# 張姐の DM の行（DM の印）・転送の行（ニカの投稿の全文）・レックス（兄貴分の電話）・清掃員・閉店の前・閉店のあとのスマホ（DM・ニュース・タイムライン）。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。撮影の道具の中だけで、5日目と6日目の朝に所持金を足し、6日目の計画に
# 夜勤警備員と夜間清掃員の組が無ければ足し（noguard のときは夜勤警備員を外し）、6日目の開店で鍋を足す。ゲームのデータは変えない。
extends SceneTree

var out_dir := "res://planning/ui_screens_AD"
var gs
var ui
var play
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var noguard := OS.get_cmdline_user_args().has("noguard")
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
	_arrange_groups(noguard)
	if noguard:
		await _until(func(): return text_is.call("店主「……阿強、今夜はどこの門だ」"), 30000)
		await _shot("06b_fire_line_no_guard", "火事の場面：夜勤警備員が来なかった晩の店主の1行")
		_finish()
		return
	await _until(func(): return text_is.call("張姐「受け取ったら、冷やす方を先にね。買い物しながら袋を振り回さないの」"))
	await _shot("01_zhang", "6日目の市場：張姐（仕込む量を選んだあと）")
	await _until(func(): return text_is.call("梁伯「使う間は動く。使わん間にどうかは、また確かめる。慌てて答えを一つにするな」"))
	await _shot("02_liang", "6日目の市場を出るとき：梁伯（慌てて答えを一つにするな）")
	await _until(func(): return gs.phase == gs.Phase.OPEN and gs.soup != null)
	gs.soup["remaining_servings"] = int(gs.soup["remaining_servings"]) + 10   # 撮影の道具の中だけ
	await _until(func(): return text_is.call("セティヤ「港のお客のツケは、当面止めることにした。受けられる先を確かめるまで」"))
	await _shot("03_setiya", "6日目の宵の口：セティヤ（ツケの話）")
	await _until(func(): return text_is.call("ニカ「うん。私が見つけた中で、この名前の依頼が最初に出てるのが、雨の日」"))
	await _shot("04_nika_dates", "6日目の夜半：ニカ（公開依頼と日付）")
	await _until(func(): return text_is.call("店主「……港の方か」"))
	await _shot("05_fire_start", "明け方の始め：火事の場面の始め")
	await _until(func(): return text_is.call("店主「……さっきの飯、持って帰ったばかりだぞ」"))
	await _shot("06a_fire_line_guard", "火事の場面：夜勤警備員が来た晩の店主の1行")
	await _until(func(): return cur_key.call("news_id", "d6_flash_fire"))
	await _shot("07_show_news", "速報の行（02:12）")
	await _until(func(): return cur_key.call("dm_id", "d6_zhang_0218"))
	await _shot("08_show_dm_zhang", "張姐の DM の行（名前の札に「（DM）」）")
	await _until(func(): return cur_key.call("dm_id", "d6_dock_0305"))
	await _shot("09_show_dm_forward", "転送の行（03:05。ニカの投稿の全文。1ページ目）")
	ui.left.advance()
	await _shot("09b_show_dm_forward_p2", "転送の行（2ページ目）")
	ui.left.advance()
	await _shot("09c_show_dm_forward_p3", "転送の行（3ページ目。写真の説明）")
	await _until(func(): return text_is.call("レックス「……端末が鳴るたびに、席を立ってた。戻ってくると、酒が減ってねえんだ」"))
	await _shot("10_rex_brother", "明け方：レックス（兄貴分）")
	await _until(func(): return text_is.call("清掃員「最初は、さすがに火まではつけんだろうと思った。中で人が働いてるんだ」"))
	await _shot("11_cleaner", "明け方：夜間清掃員（火事のあと）")
	await _until(func(): return text_is.call("店主「今日の帳面は、ここまでか」"), 12000)
	await _shot("12_before_close", "閉店の前の場面")
	await _until(func(): return cur_key.call("dm_id", "d6_zhang_0455"))
	await _until(func(): return gs.phase == gs.Phase.CLOSE and str(s.current_line().get("part", "")) != "common_event")
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("13_phone_dm", "閉店のあとのスマホ：DM の一覧（火事のあとの DM）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("14_phone_news", "閉店のあとのスマホ：ニュースの一覧（速報 02:55・02:12 が朝の記事より上）")
	ui.close_overlay()
	ui.open_phone("sns")
	phone.show_timeline()
	await _shot("15_phone_timeline", "閉店のあとのスマホ：タイムライン（火事のあとの投稿）")
	ui.close_overlay()
	_finish()


func _finish() -> void:
	print("UI_SCREENS_DONE %d" % shots.size())
	var path := "%s/shots%s.txt" % [out_dir, "_noguard" if OS.get_cmdline_user_args().has("noguard") else ""]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("# 中身AD・UI準備AD のスクリーンショット（tools/ui_screens_AD.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


## 6日目の計画の組を整える（撮影の道具の中だけ）：夜勤警備員（夜半）と夜間清掃員（明け方・2杯）の組が無ければ足す。noguard なら夜勤警備員を外す。
func _arrange_groups(noguard: bool) -> void:
	var instances: Dictionary = gs.today_plan["mob_instances"]
	var has_guard := false
	var has_cleaner := false
	for key in instances.keys():
		var type_id := str(instances[key]["type"])
		if type_id == "security_guard":
			has_guard = true
			if noguard:
				instances.erase(key)
				for slot in gs.today_plan["slots"]:
					(slot["customers"] as Array).erase(key)
		if type_id == "street_cleaners":
			has_cleaner = true
	if not has_guard and not noguard:
		_add_group("夜半", "mob#8", "security_guard", 1)
	if not has_cleaner:
		_add_group("明け方", "mob#9", "street_cleaners", 2)


func _add_group(slot_name: String, iid: String, type_id: String, count: int) -> void:
	gs.today_plan["mob_instances"][iid] = { "type": type_id, "count": count }
	for slot in gs.today_plan["slots"]:
		if str(slot["name"]) == slot_name:
			(slot["customers"] as Array).append(iid)


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
