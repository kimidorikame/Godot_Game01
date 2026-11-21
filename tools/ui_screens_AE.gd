# 中身AE（7日目＝最後の日の本番の文）と UI準備AE（訂正の印・動画の全文・週の終わりのタイトル）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AE.gd    → planning/ui_screens_AE/
# 撮るもの：朝のDM（阿強の写真）・ニュースの一覧（7日目の6本）・張姐・梁伯・タイムラインの 14:30（動画と全文）・6日目の 02:42 の「訂正あり」の印と、
# 押したあと・リン（夜勤警備員の5行がある道）・ニカの訂正の動画（3行）・事務所からの返事の場面・余分の組の人夫・ターニャ婆の瓶の場面・
# 閉店の場面・閉店のあとのスマホ（DM）・タイトル・結果の画面。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。撮影の道具の中だけで、5〜7日目の朝に所持金を足し、6日目の計画に夜勤警備員の組が
# 無ければ足し（リンの5行の道にする）、7日目の計画の夜半に人夫の2組目（余分の組）を足し、7日目の開店で鍋を足す。ゲームのデータは変えない。
extends SceneTree

var out_dir := "res://planning/ui_screens_AE"
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

	await _until(func(): return gs.day_count == 5 and gs.phase == gs.Phase.WAKE, 40000)
	gs.money += 500   # 撮影の道具の中だけ
	await _until(func(): return gs.day_count == 6 and gs.phase == gs.Phase.WAKE, 20000)
	gs.money += 500   # 撮影の道具の中だけ
	_add_group_if_missing("夜半", "mob#8", "security_guard", 1)
	await _until(func(): return gs.day_count == 7 and gs.phase == gs.Phase.WAKE, 30000)
	gs.money += 500   # 撮影の道具の中だけ
	var guard6 := false
	for record in gs.day_records:
		if int(record.get("day", -1)) == 6 and (record.get("mob_types_served", []) as Array).has("security_guard"):
			guard6 = true
	print("6日目に夜勤警備員へ出した：", guard6)
	_add_group("夜半", "mob#9", "market_porter", 1)   # 余分の組（夜半の2組目）
	# 朝のスマホ：DM（阿強の写真）とニュースの一覧
	ui.open_phone("sns")
	phone.show_dm_list()
	for thread in s.dm_threads():
		if str(thread["name"]) == "阿強":
			phone.open_dm_thread(str(thread["key"]))
	await _frames(3)
	var dm_scroll: ScrollContainer = phone.get_node("%Scroll")
	dm_scroll.scroll_vertical = int(dm_scroll.get_v_scroll_bar().max_value)   # いちばん下（7日目の4通）
	await _shot("01_morning_dm_akiang", "7日目の朝のDM：阿強（7:40 の写真つき・7:41・7:43・7:45）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("02_news_list", "7日目の朝：ニュースの一覧（7日目の6本）")
	_print_news_fit(phone)
	ui.close_overlay()
	await _until(func(): return text_is.call("張姐「分かってるならよし。アンタ、ゆうべ寝てないでしょ。夜、ちゃんと売っておいで。それから寝るのよ？」"))
	await _shot("03_zhang", "7日目の市場：張姐（仕込む量を選んだあと）")
	await _until(func(): return text_is.call("梁伯「明日は、明日の札を見る。水缶は今日も明日も、蓋を閉める」"))
	await _shot("04_liang", "7日目の市場を出るとき：梁伯（明日は、明日の札を見る）")
	await _until(func(): return gs.phase == gs.Phase.OPEN and gs.soup != null)
	gs.soup["remaining_servings"] = int(gs.soup["remaining_servings"]) + 10   # 撮影の道具の中だけ
	# 宵の口のスマホ：タイムラインの 14:30（動画と全文）・6日目の「訂正あり」の印
	ui.open_phone("sns")
	phone.show_timeline()
	await _frames(3)
	phone.scroll_to_post("d7_exposure_test_1430")
	var post: Node = phone.get_node("%Content").get_node("Post_d7_exposure_test_1430")
	var open_button: Button = post.find_child("TranscriptButton", true, false)
	open_button.button_pressed = true
	await _frames(3)
	phone.scroll_to_post("d7_exposure_test_1430")
	await _shot("05_timeline_1430_transcript", "タイムライン：7日目 14:30 のニカの訂正（動画・「動画の全文を読む」で全文6行を開いたところ）")
	open_button.button_pressed = false
	await _frames(2)
	phone.scroll_to_post("d6_exposure_test_0242")
	await _shot("06_timeline_d6_0242_mark", "タイムライン：6日目 02:42 のニカの投稿と 03:25 の追記に「訂正あり」の印（本文はそのまま）")
	var mark: Button = phone.get_node("%Content").get_node("Post_d6_exposure_test_0242").find_child("CorrectionMark", true, false)
	mark.pressed.emit()
	await _shot("07_timeline_mark_jump", "「訂正あり」の印を押したあと：7日目 14:30 の訂正の投稿へ移る")
	ui.close_overlay()
	await _until(func(): return text_is.call("リン「旧倉庫の夜番の方から、ここの店主に礼を、と言われました。昨夜、交代のときにスープを食べたそうですね」"))
	await _shot("08_lin_guard", "宵の口：リン（6日目に夜勤警備員が来ていた道の5行）")
	await _until(func(): return text_is.call("ニカ「昨夜、旧倉庫の火事について、『この人が焼かせた』と投稿しました。この言い切りは、私の誤りです。撤回します」"))
	await _shot("09_nika_video", "夜半：ニカの訂正の動画（屋台の3行の1行目）")
	await _until(func(): return text_is.call("ニカ「え、待って。事務所から。昨日の問い合わせ、返ってきた」"))
	await _shot("10_nika_office_reply", "夜半：ニカ（事務所からの返事）")
	await _until(func(): return text_is.call("人夫「辛くて腹にたまるのを。今日は座って食う。新しい集合場所、帰りだけは近かった」"))
	await _shot("11_spare_porter", "夜半：余分の組の人夫（予備の1行で注文まで）")
	await _until(func(): return text_is.call("ターニャ婆「うん。口も欠けてない。よく乾いてる」"))
	await _shot("12_granny_bottles", "明け方：ターニャ婆（初日の瓶）")
	await _until(func(): return text_is.call("店主「……箱は、またここだな」"), 12000)
	await _shot("13_close_scene", "閉店の場面（ターニャ婆のあと）")
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("14_phone_dm_after_close", "閉店のときのスマホ：DM の一覧（夜半のあとの港湾労働者 00:10・00:12）")
	ui.close_overlay()
	await _until(func(): return gs.phase == gs.Phase.RESULT, 4000)
	await _shot("15_title", "週の終わり：「夜湯」のタイトル（結果の画面の前）")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui.full_result.get_node("TitleCard").gui_input.emit(click)
	await _shot("16_result", "結果の画面（1 成績）")
	_finish()


func _print_news_fit(phone) -> void:
	var content: Control = phone.get_node("%Content")
	var scroll: Control = phone.get_node("%Scroll")
	var row: Control = content.get_node("NewsRow_d7_umbrella")
	print("NEWS_FIT 7日目の6本目の下端 %d／枠の高さ %d" % [int(row.position.y + row.size.y), int(scroll.size.y)])
	shots.append("（計測）7日目のニュースの一覧：6本目の下端 %d／枠の高さ %d" % [int(row.position.y + row.size.y), int(scroll.size.y)])


func _finish() -> void:
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# 中身AE・UI準備AE のスクリーンショット（tools/ui_screens_AE.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


## 計画の組を足す（撮影の道具の中だけ）。
func _add_group(slot_name: String, iid: String, type_id: String, count: int) -> void:
	gs.today_plan["mob_instances"][iid] = { "type": type_id, "count": count }
	for slot in gs.today_plan["slots"]:
		if str(slot["name"]) == slot_name:
			(slot["customers"] as Array).append(iid)


func _add_group_if_missing(slot_name: String, iid: String, type_id: String, count: int) -> void:
	for key in gs.today_plan["mob_instances"]:
		if str(gs.today_plan["mob_instances"][key]["type"]) == type_id:
			return
	_add_group(slot_name, iid, type_id, count)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


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
