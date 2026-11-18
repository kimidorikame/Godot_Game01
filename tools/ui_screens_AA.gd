# 中身AA（4日目の取り込み）と、中身Z2 の続き（ニカ 23:00 の短くした説明）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AA.gd    → planning/ui_screens_AA/
# 撮るもの：3日目のタイムラインのニカの 23:00（写真の枠に収まる）・4日目の朝のDM・ニュースの一覧と1本目の本文・張姐（仕込む量を選んだあと）・梁伯・
# リンの注文（米麺の話）・タイムライン（21:25 がリンの接客の前は見えず、あとで見える）・四組目の運転手（予備の一言→予備の注文の文→予備の退店の文。ログで）・
# 阿強のロードバイクの写真の場面・ターニャ婆の高台の話・ホテルの夜番。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。四組目の晩を見せるため、撮影の道具の中だけで4日目の計画に運転手の組を足す
# （宵の口に運転手が1組も無ければ2組、あれば1組。明け方にホテルの夜番が無ければ1組。ゲームのデータは変えない）。
# 足した組の分まで鍋が持つよう、4日目の開店のときに鍋の残りを10杯足す（同じく撮影の道具の中だけ）。
extends SceneTree

var out_dir := "res://planning/ui_screens_AA"
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

	# 3日目：ニカのあとのタイムライン（23:00 の動画の説明が枠に収まる）
	await _until(func(): return text_is.call("夜番「売れたよ、まったく。作業灯と延長コードを、まとめて買ってった。旧倉庫で使うんだと」"), 20000)
	ui.open_phone("sns")
	await _shot("01_day3_timeline_video", "3日目の夜半：ニカの 23:00（「［動画：車列。運転席の窓ごしに弁当箱。顔は分からない］」が写真の枠に収まる）")
	ui.close_overlay()
	# 4日目の朝：DM・ニュース
	await _until(func(): return gs.day_count == 4 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 12000)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 120:
		guard += 1
		ui.left.advance()
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("02_day4_dm_list", "4日目の朝：DMの相手の一覧（張姐・リン・阿強・ターニャ婆。常連3人の来店予告は無い）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("03_day4_news_list", "4日目の朝：ニュースの一覧（4日目の4本）")
	load("res://tests/ui_autoplay.gd").press(phone.get_node("%Content").get_node("NewsRow_d4_old_warehouse"))
	await _shot("04_day4_news_first", "4日目の1本目の本文（5段落）")
	ui.close_overlay()
	# 四組目の晩にする（撮影の道具の中だけ）
	_add_fourth_group()
	await _until(func(): return text_is.call("張姐「受け取ったね？」"))
	await _shot("05_zhang_after_tier", "4日目の市場：張姐（仕込む量を選んだあと）")
	await _until(func(): return text_is.call("梁伯「ただ、顔を知らん者ばかりだ。知らん者ばかり。この水場で、名前も知らん者に水を出すのは久しぶりだよ」"))
	await _shot("06_liang", "4日目の市場を出るとき：梁伯")
	await _until(func(): return gs.phase == gs.Phase.OPEN and gs.soup != null)
	gs.soup["remaining_servings"] = int(gs.soup["remaining_servings"]) + 10   # 撮影の道具の中だけ：足した組の分まで鍋を持たせる
	await _until(func(): return text_is.call("リン「はい。それでお願いします。あの、米の麺は、今日はありますか」"))
	await _shot("07_lin_order", "4日目の宵の口：リンの注文（米麺の話）")
	ui.open_phone("sns")
	await _shot("08_timeline_before_lin", "4日目の宵の口・リンの接客中：タイムライン（リンの 21:25 はまだ見えない）")
	ui.close_overlay()
	await _until(func(): return gs.phase == gs.Phase.OPEN and s.open != null and str(s.open.current_customer()) != "officer")
	ui.open_phone("sns")
	await _shot("09_timeline_after_lin", "4日目の宵の口・リンのあと：タイムライン（21:25 が見える）")
	ui.close_overlay()
	await _until(func(): return text_is.call("運転手「ごちそうさん。椅子が動かないと、ゆっくり噛めるな」"))
	ui.left.toggle_log()
	await _shot("10_fourth_group_driver", "四組目の運転手（会話ログ）：予備の一言 → 予備の注文の文 → 予備の退店の文")
	ui.left.toggle_log()
	await _until(func(): return text_is.call("阿強「違う。欲しい方。ロードバイク」"))
	await _shot("11_achang_roadbike", "4日目の夜半：阿強のロードバイクの写真の場面")
	await _until(func(): return text_is.call("ターニャ婆「上の空き駐車場、柵が付いたね」"))
	await _shot("12_granny_hilltop", "4日目の明け方：ターニャ婆の高台の話")
	await _until(func(): return text_is.call("夜番「今日は座って食べるよ。フロントは機械に任せてきた」"))
	await _shot("13_hotel_night", "4日目の明け方：港のホテルの夜番")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# 中身AA のスクリーンショット（tools/ui_screens_AA.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


## 4日目の計画に、宵の口の運転手の組（同じ晩の2組目）と、明け方のホテルの夜番を足す（撮影の道具の中だけ）。
func _add_fourth_group() -> void:
	if not _has_type("long_haul_driver"):
		_add_group("宵の口", "mob#8", "long_haul_driver")
	_add_group("宵の口", "mob#9", "long_haul_driver")
	if not _has_type("laundry_night"):
		_add_group("明け方", "mob#10", "laundry_night")


func _has_type(type_id: String) -> bool:
	var instances: Dictionary = gs.today_plan["mob_instances"]
	for key in instances:
		if str(instances[key]["type"]) == type_id:
			return true
	return false


func _add_group(slot_name: String, iid: String, type_id: String) -> void:
	gs.today_plan["mob_instances"][iid] = { "type": type_id, "count": 1 }
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
