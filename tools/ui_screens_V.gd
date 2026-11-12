# UI準備V（会話ログの上限・行頭禁則・アイコンの文字の色）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_V.gd    → planning/ui_screens_V/
# 撮るもの：閉店時のスマホのログ（1日目の朝の市場の会話まで戻ったところ）、2日目の朝のタイムライン（同伴まで二時間 16:40・
# パーツ相談室 16:25・葉っぱの番 09:40 と、「パ」「片」のアイコン）。セーブ・既読・日次ログは user://ui_screens_* に書く。
extends SceneTree

var out_dir := "res://planning/ui_screens_V"
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
	var talk_log = load("res://scripts/talk_log.gd")
	# 1. 閉店時のログ（一番上＝朝の市場の会話まで戻す）
	await _until(func(): return gs.phase == gs.Phase.CLOSE)
	ui.left.toggle_log()
	for i in range(4):
		await process_frame
	var log_scroll: ScrollContainer = ui.left.get_node("%LogScroll")
	await _shot("01_log_close_bottom", "閉店時のログ（開いたところ＝一番下。ログは %d 行）" % talk_log.get("entries").size())
	log_scroll.scroll_vertical = 0
	await _shot("02_log_close_top", "閉店時のログを一番上まで戻したところ（1日目の朝の市場＝張姐の会話から読める）")
	ui.left.close_log()
	# 2. 2日目の朝のタイムライン
	await _until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE)
	ui.open_phone("sns")
	for i in range(4):
		await process_frame
	var content: VBoxContainer = ui.pane_phone.get_node("%Content")
	var scroll: ScrollContainer = ui.pane_phone.get_node("%Scroll")
	scroll.scroll_vertical = int((content.get_node("Post_d1_anne_life_1650") as Control).position.y)
	await _shot("03_posts_1640_1625", "同伴まで二時間 16:40・パーツ相談室 16:25（行の頭に句読点が来ない）と「パ」のアイコン（暗い文字）")
	scroll.scroll_vertical = int((content.get_node("Post_d1_ayu_0940") as Control).position.y) - 20
	await _shot("04_posts_0940_icons", "葉っぱの番 09:40（行の頭に句読点が来ない）と「片」「窓」「拾」などのアイコン（明るい地は暗い文字）")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備V のスクリーンショット（tools/ui_screens_V.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _until(cond: Callable, limit: int = 5000) -> void:
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
