# 本番UI（UI準備P-5：鍋の濃さの目盛り「出せない｜薄い｜適正｜濃い」と、だし・水を押す前の「押した後の値」）の before／after の
# スクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_P5.gd -- after    → planning/ui_screens_P5/after/
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_P5.gd -- before   → planning/ui_screens_P5/before/（P-5 の前のコミットで撮る）
# Day2 の最初の椀の入力待ちまで台本（tests/ui_autoplay.gd）で進め、鍋タブを開く。濃さ・残りは撮るための仮の値（題に書く）。
# マウスを乗せた状態は、ボタンの mouse_entered を送って作る。文字が枠に入りきらない箇所を overflow.txt に書き出す。
extends SceneTree

var out_dir := "res://planning/ui_screens_P5/after"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	out_dir = "res://planning/ui_screens_P5/%s" % (args[0] if not args.is_empty() else "after")
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
	var top = ui.pane_kaiten.topping
	_until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.OPEN and top.visible and top.is_adjusting())
	gs.dashi_units = 2   # 撮るための仮の値（だしを押せる）
	var pot = ui.pane_kaiten.pot
	var dashi = pot.get_node("%DashiButton")
	var water = pot.get_node("%WaterButton")
	play.press(ui.pane_kaiten.get_node("%PotTab"))
	await _pot(s, 3, 8, "01_strength3", "鍋タブ（濃さ3・残り8杯・だし2。仮の値）")
	dashi.mouse_entered.emit()
	await _pot(s, 3, 8, "02_hover_dashi", "だしにマウスを乗せた（濃さ3→5）")
	dashi.mouse_exited.emit()
	water.mouse_entered.emit()
	await _pot(s, 3, 8, "03_hover_water", "水にマウスを乗せた（濃さ3→1・残り8→10杯）")
	water.mouse_exited.emit()
	await _pot(s, 1, 8, "04_strength1", "濃さ1（薄い＝減点の側。水は押せない）")
	dashi.mouse_entered.emit()
	await _pot(s, 1, 8, "05_strength1_hover_dashi", "濃さ1でだしに乗せた（1→3＝適正へ戻る）")
	dashi.mouse_exited.emit()
	await _pot(s, 5, 8, "06_strength5", "濃さ5（濃い＝減点の側。だしは押せない）")
	await _pot(s, 0, 8, "07_strength0", "濃さ0（提供できない）")
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


func _pot(s, strength: int, remaining: int, file_name: String, title: String) -> void:
	gs.soup["strength"] = strength
	gs.soup["remaining_servings"] = remaining
	s.notify_changed()
	await _shot(file_name, title)


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
## UI準備P：横並び（HBoxContainer。札の列など）は、中身の最小幅が枠の幅を超えるもの（はみ出して隣に重なる）も数える。
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
		elif label.autowrap_mode == TextServer.AUTOWRAP_OFF and need.y > label.size.y + 1.0 and not (label.get_parent() is Container):
			overflow.append("%s: %s 「%s」 高さ %d が必要（枠 %d）" % [file_name, ui.get_path_to(label), label.text.replace("\n", "／"), need.y, label.size.y])
		elif label.autowrap_mode != TextServer.AUTOWRAP_OFF and need.y > label.size.y + 1.0 and not (label.get_parent() is Container):
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
	var lines := PackedStringArray(["# 本番UI（UI準備P-5）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_P5.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
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
