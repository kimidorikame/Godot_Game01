# 本番UI（UI準備Q：トッピング画面の3枠の上の見出し「いまの椀(3枠)」の文字を鍋の行に替え、提供の上の鍋の小表示を消して大きい椀の絵を広げた）の before／after の
# スクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_Q.gd -- after    → planning/ui_screens_Q/after/
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_Q.gd -- before   → planning/ui_screens_Q/before/（Q の前のコミットで撮る）
# tests/ui_kaiten_test.gd と同じ形で、新人警官の1杯目の入力待ち（ADJUST）を作る。在庫・鍋の濃さ・保存レシピは撮るための仮の値（題に書く）。
# 文字が枠に入りきらない箇所を overflow.txt に書き出す。
extends SceneTree

var out_dir := "res://planning/ui_screens_Q/after"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	out_dir = "res://planning/ui_screens_Q/%s" % (args[0] if not args.is_empty() else "after")
	load("res://scripts/morning_save.gd").set("save_path", "user://ui_screens_save.dat")
	load("res://scripts/morning_save.gd").call("delete_file")
	load("res://scripts/read_state.gd").call("reset", "user://ui_screens_read_state.json")
	load("res://scripts/balance_log.gd").set("path", "user://ui_screens_balance_log.jsonl")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	gs = root.get_node("GameState")
	gs.reset_for_new_game()
	gs.day_count = 2
	gs.reputation = 65
	ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	var s = ui.session
	gs.inventory.clear()
	gs.perishable_batches.clear()
	for id in ["nam_prik_pao", "offal", "tofu", "coconut_milk"]:
		gs.add_inventory(id, 9)
	gs.set_soup("bone_broth", ["meaty"], 11, 3, 2)
	gs.phase = gs.Phase.OPEN
	s.open = load("res://scripts/open_controller.gd").new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	ui.close_overlay()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == 0 and guard < 40:   # EventRunner.Status.PLAYING
		guard += 1
		ui.left.advance()
	var top = ui.pane_kaiten.topping
	await _shot("01_empty_bowl", "空の椀（新人警官。鍋 残11杯・濃さ3。仮の在庫：ナムプリ・モツ・豆腐・ココナツ各9）")
	_pick(top, "調味料", "ナムプリ")
	_pick(top, "具材", "モツ")
	await _shot("02_flavor1_topping1", "味1・具1（ナムプリ・モツ）")
	_pick(top, "具材", "豆腐")
	await _shot("03_flavor1_topping2", "味1・具2（ナムプリ・モツ・豆腐）")
	gs.soup["strength"] = 5
	s.notify_changed()
	await _shot("04_strength5", "濃さ5（仮の値。味1・具2のまま）")
	gs.soup["strength"] = 3
	_press(top.get_node("%DiscardButton"))
	gs.saved_recipes = [{ "name": "試しの一杯", "ingredients": ["nam_prik_pao", "offal"] }]
	s.notify_changed()
	_press(top.get_node("%UsualButton"))
	await _shot("05_usual_open", "「いつもの」を開いたとき（一杯を捨てて空の椀に戻し、仮の保存レシピ「試しの一杯」を1つ）")
	gs.saved_recipes = []
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


func _press(button) -> bool:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


## kind_title の最初のタブを開き、短縮名が name の具材ボタンの本体を押す。
func _pick(top, kind_title: String, name: String) -> void:
	for tab in top.get_node("%Tabs").get_children():
		if tab.visible and tab.text.begins_with(kind_title):
			_press(tab)
			break
	for item in top.get_node("%Grid").get_children():
		if item.visible and str(item.get_node("MainButton/Name").text) == name:
			_press(item.get_node("MainButton"))
			return
	push_error("具材ボタンが無い：%s" % name)


func _shot(file_name: String, title: String) -> void:
	for i in range(4):
		await process_frame
	var path := "%s/%s.png" % [out_dir, file_name]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	shots.append("%s.png  %s" % [file_name, title])
	_collect_overflow(file_name, ui)


## 文字が枠に入りきらないもの：1行のラベル・ボタンは幅、折り返すラベルは高さを見る（切って「…」にしているものは除く）。
## 横並び（HBoxContainer。札の列・鍋の行など）は、中身の最小幅が枠の幅を超えるもの（はみ出して隣に重なる）も数える。tools/ui_screens_P2.gd と同じ。
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
		elif need.y > label.size.y + 1.0 and not (label.get_parent() is Container):
			overflow.append("%s: %s 「%s」 高さ %d が必要（枠 %d）" % [file_name, ui.get_path_to(label), label.text.replace("\n", "／"), need.y, label.size.y])
	elif node is Button:
		var button: Button = node
		if button.text != "" and not button.clip_text and button.get_minimum_size().x > button.size.x + 1.0:
			overflow.append("%s: %s 「%s」 幅 %d が必要（枠 %d）" % [file_name, ui.get_path_to(button), button.text.replace("\n", "／"),
				button.get_minimum_size().x, button.size.x])
	elif node is HBoxContainer and not (node.get_parent() is Container):
		var box: HBoxContainer = node
		var need_x: float = box.get_combined_minimum_size().x
		if box.get_child_count() > 0 and need_x > box.size.x + 1.0:
			var words: Array = []
			for child in box.get_children():
				if child is Label and (child as Control).visible:
					words.append((child as Label).text)
			overflow.append("%s: %s 横並び「%s」 幅 %d が必要（枠 %d）" % [file_name, ui.get_path_to(box), "・".join(words), need_x, box.size.x])


func _write_overflow() -> void:
	var lines := PackedStringArray(["# 本番UI（UI準備Q）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_Q.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
	shots.sort()
	lines.append_array(PackedStringArray(shots))
	lines.append("")
	var unique := {}
	for line in overflow:
		unique[line] = true
	lines.append("## 入りきらない箇所（%d件）" % unique.size())
	lines.append_array(PackedStringArray(unique.keys()))
	var f := FileAccess.open("%s/overflow.txt" % out_dir, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
