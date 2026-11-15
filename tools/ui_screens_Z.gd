# 中身Z（3日目の取り込み）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_Z.gd    → planning/ui_screens_Z/
# 撮るもの：3日目の朝のDM一覧・ニュースの一覧・張姐（伝票の話）・梁伯・阿強の容器の場面・阿強の依頼元の場面・ニカ（名乗る前の「客」と、名乗ったあと）・
# セティヤの注文・雑貨屋の夜番・タイムライン（ニカの 23:00 が接客の前は見えず、あとで見える）・デバッグ画面の朝の見込み（検証用。ニカがどう出るか）。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd。1日目の阿強の3杯目は出す）。
extends SceneTree

var out_dir := "res://planning/ui_screens_Z"
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
	var memory = load("res://scripts/customer_memory.gd")   # クラス名で参照しない（autoload より先に読み込まれて止まらないように）
	var text_is := func(t: String): return str(s.current_line().get("speaker_name", "")) + str(s.current_line().get("text", "")) == t

	await _until(func(): return gs.day_count == 3 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 20000)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 60:
		guard += 1
		ui.left.advance()
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("01_day3_dm_list", "3日目の朝：DMの相手の一覧（張姐・阿強・セティヤ。阿強・セティヤの来店予告は出ない）")
	phone.open_dm_thread("customer:delivery_man")
	await _shot("02_day3_dm_achang", "3日目の朝：阿強のDM（1日目の3杯目を出した道＝容器の文）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("03_day3_news_list", "3日目の朝：ニュースの一覧（3日目の4本）")
	ui.close_overlay()
	await _until(func(): return text_is.call("張姐「それがね。骨を運んできた車、いつもの運転手なのに、伝票の判子が違うのよ。『曜』なんとか聯運。見たことある？」"))
	await _shot("04_zhang_slip", "3日目の市場：張姐の伝票の話")
	await _until(func(): return text_is.call("梁伯「昨夜の数字だ。旧倉庫側の蛇口で、ずいぶん水が出とる」"))
	await _shot("05_liang_water", "3日目の市場を出るとき：梁伯（払い方は今までどおり。市場を出るときにまとめて払った）")
	await _until(func(): return text_is.call("阿強「先にこれ。容器、帰ってきたよ」"))
	await _shot("06_achang_container", "3日目の宵の口：阿強の容器の場面（1日目の3杯目を出した道）")
	await _until(func(): return text_is.call("阿強「一覧には出てんだけど。依頼元の名前、初めて見る。『曜海聯運』？」"))
	await _shot("07_achang_client", "3日目の宵の口：阿強の依頼元の場面")
	await _until(func(): return gs.phase == gs.Phase.OPEN and s.open != null and str(s.open.current_customer()) == "streamer")
	ui.open_phone("sns")
	await _shot("08_timeline_before_nika", "3日目の夜半・ニカの接客の前：タイムライン（ニカの 23:00 はまだ見えない。見えている3日目の投稿 %d件）" % _visible_today(s))
	ui.close_overlay()
	await _until(func(): return text_is.call("客「あ、先に聞いていい？　湯気だけ撮りたいんだけど。私、配信やってて」"))
	await _shot("09_nika_before_name", "3日目の夜半：名乗る前のニカ（会話の名前は「客」・表示名は「%s」）" % memory.display_name("streamer"))
	await _until(func(): return text_is.call("ニカ「分かった。目の録画、いまは切ってる。撮る前に、もう一回言うね」"))
	await _shot("10_nika_after_name", "3日目の夜半：名乗ったあとのニカ（会話の名前は「ニカ」・表示名は「%s」）" % memory.display_name("streamer"))
	await _until(func(): return text_is.call("夜番「売れたよ、まったく。作業灯と延長コードを、まとめて買ってった。旧倉庫で使うんだと」"))
	await _shot("11_store_clerk", "3日目の夜半：雑貨屋の夜番")
	ui.open_phone("sns")
	await _shot("12_timeline_after_nika", "3日目の夜半・ニカの接客のあと：タイムライン（ニカの 23:00 が見える。見えている3日目の投稿 %d件）" % _visible_today(s))
	ui.close_overlay()
	await _until(func(): return text_is.call("セティヤ「苦いのより、まろやかなのがいい。表を回って汗をかいたら、今度は雨で冷えちゃった」"))
	await _shot("13_setiya_order", "3日目の明け方：セティヤの注文（今日の頼み まろやか＋ごちそう）")
	await _until(func(): return gs.day_count == 4 and gs.phase == gs.Phase.WAKE, 12000)
	ui.queue_free()
	await process_frame
	# デバッグ画面（検証用）の朝の見込み：3日目の朝、まだ会っていないニカがどう出るか（本番の画面には今夜の客の一覧は無い）
	gs.reset_for_new_game()
	gs.day_count = 3
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	root.add_child(panel)
	panel._on_phone_pressed()
	panel._on_phone_tab_selected("sns")
	var memo := FileAccess.open("%s/14_debug_forecast_day3.txt" % out_dir, FileAccess.WRITE)
	memo.store_string(str(panel._format_tonight_memo()) + "
")
	memo.close()
	await _shot("14_debug_forecast_day3", "デバッグ画面（検証用）の3日目の朝の見込み：まだ会っていないニカは「%s」で、いつもの注文の札が出る" % memory.display_name("streamer"))
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# 中身Z のスクリーンショット（tools/ui_screens_Z.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _visible_today(s) -> int:
	var sns = load("res://scripts/sns.gd")
	var n := 0
	for id in sns.call("visible_ids", gs.day_count, s.timeline_limit(), {}, s.market_talks_done(), s.visits_done_today()):
		if str(id).begins_with("d%d_" % gs.day_count):
			n += 1
	return n


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
