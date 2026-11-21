# 中身AB（5日目の取り込み）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AB.gd    → planning/ui_screens_AB/
# 撮るもの：5日目の朝のDM・ニュースの一覧（5本）と3本目の本文・張姐（仕込む量を選んだあと）・梁伯・セティヤの「勘定の宛先」・
# ニカが映像の男を見せる場面（店主「……レックスのところの兄貴分だな」）・夜勤警備員・四組目の晩の夜勤警備員（予備の一言→予備の注文の文。ログで）・
# タイムライン・リンの「昼の仕入れ、どっちを回ればいい？」・リンの退店（旧倉庫の灯り）・港湾労働者（2杯以上で労働者Aが出る晩）。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。撮影の道具の中だけで、次のことをする（ゲームのデータは変えない）：
#   ・5日目の朝に所持金を足す（自動の遊び手は5日目の朝に所持金が少なく、具を買えずに全部断るため。tests/day5_script_test.gd と同じ）
#   ・5日目の計画に、夜半の夜勤警備員の2組目（四組目の晩の予備の一言）と、明け方の港湾労働者の2杯の組を足す
#   ・足した組の分まで鍋が持つよう、5日目の開店のときに鍋の残りを12杯足す
extends SceneTree

var out_dir := "res://planning/ui_screens_AB"
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

	# 5日目の朝：DM・ニュース
	await _until(func(): return gs.day_count == 5 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 40000)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 120:
		guard += 1
		ui.left.advance()
	gs.money += 500   # 撮影の道具の中だけ
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("01_day5_dm_list", "5日目の朝：DMの相手の一覧（張姐・セティヤ・ニカ・リン。常連3人の来店予告は無い）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("02_day5_news_list", "5日目の朝：ニュースの一覧（5日目の5本）")
	await _print_news_fit(phone)
	load("res://tests/ui_autoplay.gd").press(phone.get_node("%Content").get_node("NewsRow_d5_aisle_safety"))
	await _shot("03_day5_news_third", "5日目の3本目の本文（消防の注意。5段落）")
	await _print_detail_fit(phone)
	ui.close_overlay()
	_add_groups()
	await _until(func(): return text_is.call("張姐「そこまででいい。戻ってきた台車の場所を残すの。何も置いてないからって、空いてるわけじゃないんだから」"))
	await _shot("04_zhang_after_tier", "5日目の市場：張姐（仕込む量を選んだあと）")
	await _until(func(): return text_is.call("梁伯「夜中の数字が、とうとう昼を越えた。昼を越えたんだ。この水場を見てきて、初めてだよ」"))
	await _shot("05_liang", "5日目の市場を出るとき：梁伯")
	await _until(func(): return gs.phase == gs.Phase.OPEN and gs.soup != null)
	gs.soup["remaining_servings"] = int(gs.soup["remaining_servings"]) + 12   # 撮影の道具の中だけ：足した組の分まで鍋を持たせる
	await _until(func(): return text_is.call("セティヤ「前の飲み代が戻ってきたの。会社持ちの分。いつもの窓口に送ったら『もううちの勘定じゃない』って。新しい方からは、まだ返事がない」"))
	await _shot("06_setiya_bill", "5日目の宵の口：セティヤの「勘定の宛先」")
	await _until(func(): return text_is.call("店主「……レックスのところの兄貴分だな」"))
	await _shot("07_nika_brother", "5日目の夜半：ニカが映像の男を見せる場面")
	await _until(func(): return text_is.call("警備員「それより床だ。箱をどけると、下から延長の線が出てくる。踏むなと言って回るのが、見回りの半分になった」"))
	await _shot("08_guard", "5日目の夜半：夜勤警備員（1組目）")
	await _until(func(): return text_is.call("警備員「魚醤の汁に、噛みごたえのある具を。座って食ってく」"))
	ui.left.toggle_log()
	await _shot("09_fourth_group_guard", "四組目の晩の夜勤警備員（会話ログ）：予備の一言 → 予備の注文の文")
	ui.left.toggle_log()
	ui.open_phone("sns")
	await _shot("10_timeline_midnight", "5日目の夜半：タイムライン（リンの 23:35 まで見える）")
	ui.close_overlay()
	await _until(func(): return text_is.call("店主「昼の仕入れ、どっちを回ればいい？」"))
	await _shot("11_lin_route", "5日目の明け方：リン（店主から道を聞く）")
	await _until(func(): return text_is.call("リン「はい。……足しすぎて、かえって影が濃く見えます。では、失礼します」"))
	await _shot("12_lin_exit", "5日目の明け方：リンの退店（旧倉庫の灯り）")
	await _until(func(): return text_is.call("労働者A「今は椀を持っとけ。冷めるぞ」"))
	await _shot("13_dock_a", "5日目の明け方：港湾労働者（2杯以上の晩だけ労働者Aが出る。食事の終わり）")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# 中身AB のスクリーンショット（tools/ui_screens_AB.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


## ニュースの一覧に5日目の5本が収まるか（スクロールの枠の高さと中身の高さ）を出す。
func _print_news_fit(phone) -> void:
	await process_frame
	var content: Control = phone.get_node("%Content")
	var rows := []
	for child in content.get_children():
		if str(child.name).begins_with("NewsRow_d5_"):
			rows.append(child)
	var scroll := _scroll_of(content)
	var view_h: float = scroll.size.y if scroll != null else -1.0
	var bottom := 0.0
	for r in rows:
		bottom = maxf(bottom, (r as Control).position.y + (r as Control).size.y)
	print("NEWS_FIT rows=%d last_bottom=%.0f view=%.0f content=%.0f fits=%s" % [rows.size(), bottom, view_h, content.size.y, str(view_h < 0 or bottom <= view_h)])


func _print_detail_fit(phone) -> void:
	await process_frame
	var content: Control = phone.get_node("%Content")
	var scroll := _scroll_of(content)
	var view_h: float = scroll.size.y if scroll != null else -1.0
	print("NEWS_DETAIL view=%.0f content=%.0f scroll_needed=%s" % [view_h, content.size.y, str(view_h >= 0 and content.size.y > view_h)])


func _scroll_of(node: Node) -> ScrollContainer:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## 5日目の計画に、夜半の夜勤警備員の2組目（四組目の晩）と、明け方の港湾労働者の2杯の組を足す（撮影の道具の中だけ）。
func _add_groups() -> void:
	if not _has_type("security_guard"):
		_add_group("夜半", "mob#8", "security_guard", 1)
	_add_group("夜半", "mob#9", "security_guard", 1)
	var dock := _ids_of("dock_workers")
	if dock.is_empty():
		_add_group("明け方", "mob#10", "dock_workers", 2)
	else:
		for iid in dock:
			gs.today_plan["mob_instances"][iid]["count"] = maxi(2, int(gs.today_plan["mob_instances"][iid]["count"]))


func _has_type(type_id: String) -> bool:
	return not _ids_of(type_id).is_empty()


func _ids_of(type_id: String) -> Array:
	var out := []
	var instances: Dictionary = gs.today_plan["mob_instances"]
	for key in instances:
		if str(instances[key]["type"]) == type_id:
			out.append(key)
	return out


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
