# 中身U1（1日目の本番の文）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_U1.gd    → planning/ui_screens_U1/
# 撮るもの：ニュースの一覧（Day1 の朝）・朝の市場の会話（水場）・阿強の注文の場面・反応の場面・タイムライン（Day2 の朝）。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。台本は BAD が多いので、撮るあいだだけ BAD も定価にする。
# あわせて、Day1 に会話枠へ出した文を全部見て、
#   ・会話枠の1ページ（30字×3行）に入りきらず、ページ送りになる文（long_lines）
#   ・文字が枠に入りきらないラベル・ボタン（名前の札など）
# を overflow.txt に書き出す。セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

var out_dir := "res://planning/ui_screens_U1"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []
var long_lines: Array = []
var _seen_lines := {}


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
	var text_is := func(t: String): return str(s.current_line().get("speaker_name", "")) + str(s.current_line().get("text", "")) == t

	# 1. Day1 の朝：スマホのニュース（一覧。4本）
	await _shot("05_news_list_day1", "ニュースの一覧（Day1 の朝。1日目_ニュース.md の4本）")
	# 2. 朝の市場の会話（水場の梁伯。水道代の行の手前）
	await _until(func(): return text_is.call("梁伯「役に立ったろ。……で、今月の水道代。五十」"))
	await _shot("01_morning_water_stall", "朝の昼市場の会話：共同水場の梁伯（水道代の話。このあと「梁伯（水道代）」の行で払う）")
	# 3. 阿強の注文の場面
	await _until(func(): return text_is.call("阿強「肉。腹に力が入るやつ。あと豆腐、多めな」"))
	await _shot("02_akiang_order", "阿強の注文（1杯目：「一番赤いやつ」のあと「肉。…あと豆腐、多めな」）")
	# 4. 反応の場面（阿強の1杯目）
	await _until(func(): return str(s.current_line().get("type", "")) == "REACT" and str(s.current_line().get("text", "")) != "")
	await _shot("03_akiang_reaction", "反応（阿強の1杯目。判定の結果の1行だけ。結果＝%s）" % str(s.open.current_bowl.get("result", "")))
	# 5. Day2 の朝まで（Day1 の文を全部見る）→ タイムライン
	await _until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE)
	ui.open_phone("sns")
	await _shot("04_timeline_day2_top", "タイムライン（Day2 の朝。Day1 の投稿8件の上のほう）")
	var scroll: ScrollContainer = ui.pane_phone.get_node("%Scroll")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _shot("04_timeline_day2_bottom", "タイムライン（Day2 の朝。下まで送ったところ）")
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


## 台本で1手ずつ進める（cond が真になるまで）。進むたびに、会話枠に出た文を見る（ページ送り・枠からのはみ出し）。
func _until(cond: Callable, limit: int = 4000) -> void:
	var n := 0
	while not cond.call() and n < limit:
		n += 1
		await process_frame
		_look_at_dialogue()
		if play.step() == "":
			break
	await process_frame
	_look_at_dialogue()
	if not cond.call():
		push_error("状態に届かなかった（%d手）" % n)


func _look_at_dialogue() -> void:
	if gs.day_count != 1:
		return
	var line: Dictionary = ui.session.current_line()
	var text := str(line.get("text", ""))
	if text == "" or str(line.get("part", "")) == "news":
		return
	var full := str(line.get("speaker_name", "")) + text
	if _seen_lines.has(full):
		return
	_seen_lines[full] = true
	var pages: Array = ui.left.paginate(text)
	if pages.size() > 1:
		long_lines.append("%dページ（%d字）: %s" % [pages.size(), text.length(), full])
	_collect_overflow("Day1の会話", ui.left)


func _shot(file_name: String, title: String) -> void:
	for i in range(4):
		await process_frame
	var path := "%s/%s.png" % [out_dir, file_name]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	shots.append("%s.png  %s" % [file_name, title])
	_collect_overflow(file_name, ui)


## 文字が枠に入りきらないもの：1行のラベル・ボタンは幅、折り返すラベルは高さを見る（切って「…」にしているものは除く）。
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


func _write_overflow() -> void:
	var lines := PackedStringArray(["# 中身U1（1日目の本番の文）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_U1.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
	shots.sort()
	lines.append_array(PackedStringArray(shots))
	lines.append("")
	lines.append("## Day1 に会話枠へ出した文：%d種類。1ページ（30字×3行）に入りきらずページ送りになる文（%d件）" % [_seen_lines.size(), long_lines.size()])
	lines.append_array(PackedStringArray(long_lines))
	lines.append("")
	lines.append("## 入りきらない箇所（%d件）" % overflow.size())
	var unique := {}
	for line in overflow:
		unique[line] = true
	lines.append_array(PackedStringArray(unique.keys()))
	var f := FileAccess.open("%s/overflow.txt" % out_dir, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
