# 本番UI（UI準備O：スマホのニュースタブの一覧→詳細）の before／after のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_O.gd -- after    → planning/ui_screens_O/after/
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_O.gd -- before   → planning/ui_screens_O/before/（F の前のコミットで撮る）
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd。ボタンと会話枠のクリックだけ）。
# あわせて、文字が枠に入りきらないラベル・ボタンを overflow.txt に書き出す。
# セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

var out_dir := "res://planning/ui_screens_O/after"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	out_dir = "res://planning/ui_screens_O/%s" % (args[0] if not args.is_empty() else "after")
	load("res://scripts/morning_save.gd").set("save_path", "user://ui_screens_save.dat")
	load("res://scripts/morning_save.gd").call("delete_file")
	load("res://scripts/read_state.gd").call("reset", "user://ui_screens_read_state.json")
	load("res://scripts/balance_log.gd").set("path", "user://ui_screens_balance_log.jsonl")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	gs = root.get_node("GameState")
	gs.reset_for_new_game()
	ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	ui.full_prep.auto_advance = false
	play = load("res://tests/ui_autoplay.gd").new(ui)
	var s = ui.session

	_until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 40:
		guard += 1
		ui.left.advance()
	gs.day_count = 7   # 撮るための仮の状態（7日分のニュースが並ぶ朝）
	play.click(ui.left.get_node("%PhoneIcon"))
	ui.pane_phone._on_tab_pressed("news")
	await _shot("01_news_list", "ニュースタブの一覧（Day7 の朝の仮の状態。日付と見出しだけ・新しい日が上）")
	ui.pane_phone.open_news("d7_unresolved")
	await _shot("02_news_detail_long", "詳細（本文4行のニュース。「戻る」・見出し・日付・本文）")
	ui.pane_phone.close_news()
	ui.pane_phone.open_news("d3_spillover")
	await _shot("03_news_detail", "詳細（本文1行のニュース）")
	ui.pane_phone.close_news()
	for i in range(3):
		await process_frame   # 一覧を作り直したあと、枠の大きさが決まってから送る
	(ui.pane_phone.get_node("%Scroll") as ScrollContainer).scroll_vertical = 400
	await _shot("04_news_list_scrolled", "一覧を下へ送ったところ（Day1 まで）")
	gs.day_count = 2
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


## 台本で1手ずつ進める（cond が真になるまで）。each を渡せば、台本の代わりにそれを呼ぶ。
func _until(cond: Callable, each: Callable = Callable(), limit: int = 3000) -> void:
	var n := 0
	while not cond.call() and n < limit:
		n += 1
		if each.is_valid():
			each.call()
		elif play.step() == "":
			break
	if not cond.call():
		push_error("状態に届かなかった（%d手）" % n)


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
	var lines := PackedStringArray(["# 本番UI（UI準備O）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_O.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
	shots.sort()
	lines.append_array(PackedStringArray(shots))
	lines.append("")
	lines.append("## 入りきらない箇所（%d件）" % overflow.size())
	var unique := {}
	for line in overflow:
		unique[line] = true
	lines.append_array(PackedStringArray(unique.keys()))
	var f := FileAccess.open("%s/overflow.txt" % out_dir, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
