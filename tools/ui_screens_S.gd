# 本番UI（UI準備S：トッピングの配置の整理〔好物の行・3枠と鍋の絵・調味料が先のタブ・下の段〕）の before／after のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_S.gd -- after    → planning/ui_screens_S/after/
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。台本は BAD が多いので、撮るあいだだけ BAD も定価にする（最終日まで進むため）。
# あわせて、文字が枠に入りきらないラベル・ボタンを overflow.txt に書き出す。
# セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

var out_dir := "res://planning/ui_screens_S/after"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "after"
	out_dir = "res://planning/ui_screens_S/%s" % mode
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
	var cust := func(): return str(s.open.current_customer()) if s.open != null and s.open.has_more() else ""

	var top = ui.pane_kaiten.topping
	# 1. 最初の椀を作る前（Day1。好物をまだ知らない客＝「—」・空の椀・鍋は満杯に近い）
	_until(func(): return s.is_choosing_ingredients() and cust.call() != "" and not gs.known_favorite_ids().has(cust.call()))
	if not top.visible:
		play.press(ui.pane_kaiten.get_node("%ToppingTab"))
	await _shot("01_topping_empty", "トッピング：椀を作る前（好物を知らない客は「—」・鍋の絵）")
	# 2. 椀に入れたところ（調味料・具材を1つずつ。撮ったら取り消す）
	var options: Array = s.ingredient_options()
	var picked: Array = []
	for kind in ["seasoning", "topping"]:
		for o in options:
			if str(o["kind"]) == kind and bool(o["can_pick"]) and not bool(o["damaged"]):
				s.toggle_ingredient(str(o["id"]), false)
				picked.append(str(o["id"]))
				break
	await _shot("02_topping_bowl", "トッピング：椀に調味料と具材を入れたところ")
	for id in picked:
		s.toggle_ingredient(id, false)
	# 3. 鍋の絵：残りが少ない・濃さ1（縁が注意色）／濃さ5 → 撮ったら戻す
	var saved_remaining := int(gs.soup["remaining_servings"])
	var saved_strength := int(gs.soup["strength"])
	gs.soup["remaining_servings"] = 3
	gs.soup["strength"] = 1
	s.notify_changed()
	await _shot("03_pot_low_thin", "鍋の絵：残り少ない・濃さ1（薄い色・縁が注意色）")
	gs.soup["remaining_servings"] = int(int(s.pot_view()["capacity"]) / 2)
	gs.soup["strength"] = 5
	s.notify_changed()
	await _shot("04_pot_half_thick", "鍋の絵：半分・濃さ5（濃い色・縁が注意色）")
	gs.soup["remaining_servings"] = saved_remaining
	gs.soup["strength"] = saved_strength
	s.notify_changed()
	# 4. 好物を知った客（来店の最初から材料名）
	_until(func(): return gs.day_count >= 2 and s.is_choosing_ingredients() and cust.call() != "" and gs.known_favorite_ids().has(cust.call()), Callable(), 8000)
	if not top.visible:
		play.press(ui.pane_kaiten.get_node("%ToppingTab"))
	await _shot("05_topping_favorite", "トッピング：好物を知った客（Day%d・%s）" % [gs.day_count, cust.call()])
	# 5. 腱肉（タグ2つ）を椀に入れたところ（枠の幅100に札2枚。撮るために在庫を足す）
	gs.add_inventory("tendon_meat", 2)
	s.notify_changed()
	s.toggle_ingredient("tendon_meat", false)
	await _shot("06_slot_two_tags", "椀の枠：腱肉（札2枚：スタミナ・歯ごたえ）")
	s.toggle_ingredient("tendon_meat", false)
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


func _finish_morning_talk(s) -> void:
	var guard := 0
	while not s.flow.is_runner_done() and guard < 60:
		guard += 1
		ui.left.advance()


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
	var lines := PackedStringArray(["# 本番UI（UI準備S）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_S.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
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
