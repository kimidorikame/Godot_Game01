# UI準備Y（名乗ったあとの名前・市場の会話の画面）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_Y.gd    → planning/ui_screens_Y/
# 撮るもの：2日目の市場の会話中の右の枠（店の画面が出ていない）・会話のあとの店選び・2日目のリンの退店後の連絡先のカード・
# リンが差出人の朝のDM一覧（3日目の朝に新人警官のDMが届いていなければ4日目の朝）・結果画面。遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。
extends SceneTree

var out_dir := "res://planning/ui_screens_Y"
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

	await _until(func(): return text_is.call("警官「搬入口を探しています。地図では、この先を右なんですが」"))
	await _shot("01_day2_market_talk_pane", "2日目の市場：新人警官の会話のあいだ（右の枠は市場の画面。張記の画面・店の一覧は出ない）")
	await _until(func(): return s.is_in_market())
	await _shot("02_day2_market_after_talk", "2日目の市場：会話が終わって市場に着いた（いつもどおり店を選べる）")
	await _until(func(): return text_is.call("店主「仕事が終わってから言いな」"))
	# 退店のあと（来店の記録が付くのは退店のとき）：次の客に移るまで進める
	await _until(func(): return s.open != null and s.open.has_more() and str(s.open.current_customer()) != "officer")
	# 2日目は新人警官からのDMが無い（連絡先のカードはDMの相手の画面にだけ出る）ので、同じ中身の客メモ（タブの無い画面）で見る
	ui.open_phone("sns")
	phone.tab = "notes"
	phone.open_note("officer")
	await _shot("03_day2_rin_note", "2日目：リンの退店のあとの客メモ（連絡先のカードと同じ中身。表示名「%s」）" % memory.display_name("officer"))
	ui.close_overlay()
	var dm_day := 0
	for day in [3, 4, 5, 6, 7]:
		await _until(func(): return gs.day_count == day and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 12000)
		var guard := 0
		while not s.flow.is_runner_done() and guard < 60:
			guard += 1
			ui.left.advance()
		if s.dm_threads().any(func(th): return str(th["key"]) == "customer:officer"):
			dm_day = day
			break
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("04_dm_list_rin", "%d日目の朝：DMの相手の一覧（新人警官のDMの差出人は「%s」）" % [dm_day, memory.display_name("officer")])
	phone.open_dm_thread("customer:officer")
	await _shot("05_rin_contact_card", "%d日目の朝：リンのDMと連絡先のカード" % dm_day)
	ui.close_overlay()
	await _until(func(): return ui.full_result.visible, 40000)
	ui.full_result._set_page(2)
	await _shot("06_result_story", "結果画面の「物語」（店に来た常連・好物を知った客の名前はリン）")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備Y のスクリーンショット（tools/ui_screens_Y.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
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
