# 中身X（2日目の本番の文）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_X.gd    → planning/ui_screens_X/
# 撮るもの：朝のDM（レックス・阿強・張姐）・ニュースの一覧・張姐・新人警官（市場）・タイムライン（準備中＝リンの14:10）・レックスの注文の札（今日の頼み）・
# 新人警官の名前が「リン」に変わったところ・洗濯場の夜番（2杯以上の晩の1行）・セティヤの来店・3日目の朝のタイムライン（2日目の26件）。
# あわせて、文字が枠に入りきらないラベル・ボタン（overflow）を shots.txt に書く。遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。
extends SceneTree

var out_dir := "res://planning/ui_screens_X"
var gs
var ui
var play
var shots: Array = []
var overflow: Array = []


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
	var cust := func(): return str(s.open.current_customer()) if s.open != null and s.open.has_more() else ""

	# 2日目の朝：DM（相手ごとの一覧）・ニュースの一覧
	await _until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 60:
		guard += 1
		ui.left.advance()
	ui.open_phone("sns")
	phone.show_dm_list()
	await _shot("01_day2_dm_list", "2日目の朝：DMの相手ごとの一覧（レックス・阿強・張姐・予告）")
	phone.open_dm_thread("customer:thug")
	await _shot("02_day2_dm_rex", "2日目の朝：レックスのDM（4:40・4:42）")
	ui.close_overlay()
	ui.open_phone("news")
	await _shot("03_day2_news_list", "2日目の朝：ニュースの一覧（2日目の4本）")
	ui.close_overlay()
	# 市場：張姐 → 新人警官 → 市場（タイムラインにリンの 14:10）
	await _until(func(): return text_is.call("張姐「検問。港の手前で、一台ずつ荷札を読んでるんだって。うちの運転手、骨の箱を三回数え直されたってさ。骨だよ？」"))
	await _shot("04_day2_zhang", "2日目の市場：張姐（仕込む量の前）")
	await _until(func(): return text_is.call("警官「すみません。この市場の方ですか」"))
	await _shot("05_day2_officer_market", "2日目の市場：新人警官（出汁のあと・買い物の前。名前の札「警官」）")
	await _until(func(): return s.is_in_market())
	ui.open_phone("sns")
	phone.show_timeline()
	await _scroll_to_post(phone, "Post_d2_lin_alt_1410")
	await _shot("06_day2_timeline_market", "2日目の準備中：タイムライン（リンの 14:10 が見える。市場の会話のあと）")
	ui.close_overlay()
	# 営業：レックスの注文の札・リンの名前・洗濯場の夜番・セティヤ
	await _until(func(): return text_is.call("リン「はい。おやすみなさい」"))
	await _shot("07_day2_rin_name", "2日目の宵の口：会計のあとの「リンです」のあとから名前の札が「リン」")
	await _until(func(): return gs.day_count == 2 and s.is_choosing_ingredients() and cust.call() == "thug")
	if not ui.pane_kaiten.topping.visible:
		play.press(ui.pane_kaiten.get_node("%ToppingTab"))
	await _shot("08_day2_rex_order_card", "2日目の夜半：レックスの椀を作るところ（UI準備Sで注文の札の欄は画面から外した。好物の行だけ）")
	await _until(func(): return text_is.call("レックス「今日は通りを回ったんだがよ。検問で三回止められた」"))
	ui.open_phone("sns")
	phone.show_dm_list()
	phone.open_dm_thread("customer:thug")
	await _shot("08b_day2_rex_contact_after", "2日目の夜半：レックスに出したあとの連絡先のカード（前回の注文＝今日の頼み まろやか・スタミナ）")
	ui.close_overlay()
	ui.left.toggle_log()
	await _shot("08c_day2_rex_log", "2日目の夜半：会話ログ（レックスの注文の台詞と反応）")
	ui.left.close_log()
	await _until(func(): return str(s.current_line().get("speaker_name", "")) == "夜番" and str(s.current_line().get("text", "")).contains("相方の分も"))
	await _shot("09_day2_laundry_two_cups", "2日目の夜半：共同洗濯場の夜番（2杯以上の組だけの1行）")
	ui.open_phone("sns")
	phone.show_dm_list()
	phone.open_dm_thread("customer:thug")
	await _shot("09b_day2_rex_contact_left", "2日目の夜半：レックスが帰ったあとの連絡先のカード（前回の注文＝今日の頼み）")
	ui.close_overlay()
	await _until(func(): return text_is.call("セティヤ「上がり。港のお客がね、今夜はみんな早いの。いつもなら、もう一本って粘る人たちが」"))
	await _shot("10_day2_setiya", "2日目の明け方：セティヤの来店（名前の札「セティヤ」）")
	# 3日目の朝：タイムライン（2日目の26件）
	await _until(func(): return gs.day_count == 3 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible, 12000)
	guard = 0
	while not s.flow.is_runner_done() and guard < 60:
		guard += 1
		ui.left.advance()
	ui.open_phone("sns")
	var sns_script = load("res://scripts/sns.gd")   # クラス名で参照しない（autoload より先に読み込まれて止まらないように）
	var day2_ids: Array = (sns_script.visible_ids(3, sns_script.LIMIT_MORNING) as Array).filter(func(id): return str(id).begins_with("d2_"))
	await _shot("11_day3_timeline_top", "3日目の朝：タイムラインの上（2日目の投稿 %d 件が見える）" % day2_ids.size())
	await _scroll_to_post(phone, "Post_d2_lin_alt_1410")
	await _shot("12_day3_timeline_lin_1410", "3日目の朝：タイムラインを下へ（2日目の昼の投稿）")
	print("UI_SCREENS_DONE %d" % shots.size())
	var lines := PackedStringArray(["# 中身X のスクリーンショット（tools/ui_screens_X.gd が書き出す）"])
	lines.append_array(PackedStringArray(shots))
	lines.append("")
	lines.append("## 文字が枠に入りきらない箇所（%d件）" % overflow.size())
	var unique := {}
	for line in overflow:
		unique[line] = true
	lines.append_array(PackedStringArray(unique.keys()))
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


func _scroll_to_post(phone, post_name: String) -> void:
	for i in range(4):
		await process_frame
	var content: Control = phone.get_node("%Content")
	var post := content.get_node_or_null(post_name)
	if post == null:
		push_error("投稿が無い：%s" % post_name)
		return
	(phone.get_node("%Scroll") as ScrollContainer).scroll_vertical = int((post as Control).position.y) - 40


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
	_collect_overflow(file_name, ui)


## 文字が枠に入りきらないもの：1行のラベル・ボタンは幅、折り返すラベルは高さを見る（切って「…」にしているもの・入れ物の中のものは除く）。
func _collect_overflow(file_name: String, node: Node) -> void:
	for child in node.get_children():
		_collect_overflow(file_name, child)
	if not (node is Control) or not (node as Control).is_visible_in_tree():
		return
	if node is Label:
		var label: Label = node
		if label.text == "" or label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			return
		var need: Vector2 = label.get_minimum_size()
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and need.x > label.size.x + 1.0:
			overflow.append("%s: %s 「%s」 幅 %d が必要（枠 %d）" % [file_name, ui.get_path_to(label), label.text.replace("\n", "／"), need.x, label.size.x])
		elif label.autowrap_mode != TextServer.AUTOWRAP_OFF and need.y > label.size.y + 1.0 and not (label.get_parent() is Container):
			overflow.append("%s: %s 「%s」 高さ %d が必要（枠 %d）" % [file_name, ui.get_path_to(label), label.text.replace("\n", "／"), need.y, label.size.y])
	elif node is Button:
		var button: Button = node
		if button.text != "" and not button.clip_text and button.get_minimum_size().x > button.size.x + 1.0:
			overflow.append("%s: %s 「%s」 幅 %d が必要（枠 %d）" % [file_name, ui.get_path_to(button), button.text.replace("\n", "／"),
				button.get_minimum_size().x, button.size.x])
