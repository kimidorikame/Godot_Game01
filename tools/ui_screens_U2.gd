# 中身U2（1日目の市場の流れと払うタイミング）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_U2.gd    → planning/ui_screens_U2/
# 撮るもの：張記（仕込む量を選ぶところ）・市場を出たあとの店主の一言・梁伯のあとの所持金・レックスのあとの所持金。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。台本は BAD が多いので、撮るあいだだけ BAD も定価にする。
# あわせて、Day1 に会話枠へ出した文を全部見て、
#   ・会話枠の1ページ（30字×3行）に入りきらず、ページ送りになる文（long_lines）
#   ・文字が枠に入りきらないラベル・ボタン（名前の札など）
# を overflow.txt に書き出す。セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

var out_dir := "res://planning/ui_screens_U2"

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

	var money := func(): return "所持金 ¥%d" % gs.money
	# 1. 張記：仕込む量（鍋の素）を選ぶところ（張姐の「今日はどれ位仕込む？」の行）
	await _until(func(): return s.is_in_prep_tier())
	await _shot("01_zhang_choose_tier", "張記：張姐の「今日はどれ位仕込む？」の行で、仕込む量（鍋の素）を選ぶ（%s。初日セットは朝に引いた）" % money.call())
	# 2. 「市場を出る」のあとの店主の一言
	await _until(func(): return text_is.call("店主「炭屋と水場も寄らないとな」"))
	await _shot("02_after_market_exit", "「市場を出る」のあとの店主の一言（%s。出汁代は仕込む量を選んで買った時点で払った）" % money.call())
	# 3. 梁伯のあとの所持金（水代・水道代を払った行）
	await _until(func(): return text_is.call("梁伯（水道代）"))
	await _shot("03_after_water_stall", "梁伯の会話のあと：「梁伯（水代）」「梁伯（水道代）」の行で払った（%s）" % money.call())
	# 4. レックスのあとの所持金（退店のあと場所代）
	await _until(func(): return text_is.call("レックス（場所代）"))
	await _shot("04_after_rex", "レックスの会話が終わったあと（退店のあと）：「レックス（場所代）」の行で払った（%s）" % money.call())
	# Day1 の残りの文も見る（会話枠からはみ出す文の確かめ）
	await _until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE)
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
	var lines := PackedStringArray(["# 中身U2（1日目の市場の流れと払うタイミング）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_U2.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
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
