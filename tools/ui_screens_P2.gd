# 本番UI（UI準備P2：市場の行の「手持ち3（傷1）→ 9」・スマホの持ち物の「×3 → 9」・鍋のボタンの文の注意色）の before／after の
# スクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_P2.gd -- after    → planning/ui_screens_P2/after/
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_P2.gd -- before   → planning/ui_screens_P2/before/（P2 の前のコミットで撮る）
# 台本（tests/ui_autoplay.gd）で Day2 の市場まで進める。傷んだ豆腐・所持金・だし・鍋の濃さは撮るための仮の値（題に書く）。
# 文字が枠に入りきらない箇所を overflow.txt に書き出す。
extends SceneTree

var out_dir := "res://planning/ui_screens_P2/after"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	out_dir = "res://planning/ui_screens_P2/%s" % (args[0] if not args.is_empty() else "after")
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
	gs.money += 300   # 撮るための仮の所持金
	play.press(ui.pane_morning.get_node("%PrimaryButton"))
	_until(func(): return ui.pane_buy_meat.visible and s.is_in_prep_tier())
	play.press(ui.pane_buy_meat.get_node("%Tiers").get_child(1))
	play.press(ui.pane_buy_meat.get_node("%ConfirmButton"))
	play.press(ui.pane_buy_meat.get_node("%BackButton"))
	_until(func(): return ui.pane_market.visible)
	_add_damaged("tofu", 1)   # 撮るための仮の在庫：傷んだ豆腐1
	play.press(ui.pane_market.get_node("%Stalls").get_child(3))
	var goods = ui.pane_buy_shop.get_node("%Goods")
	play.press(goods.get_child(0).get_node("BuyButton"))
	play.press(goods.get_child(0).get_node("BuyButton"))
	play.press(goods.get_child(1).get_node("BuyButton"))
	await _shot("01_market_damaged_cart", "市場の行（豆腐麺房。仮の傷んだ豆腐1。豆腐2回・米麺1回をかごへ）")
	play.click(ui.left.get_node("%PhoneIcon"))
	ui.pane_phone._on_tab_pressed("inventory")
	await _shot("02_phone_inventory_cart", "スマホの持ち物（豆腐麺房でかごに入れたまま）")
	play.press(ui.pane_phone.get_node("%CloseButton"))
	play.press(ui.pane_buy_shop.get_node("%BackButton"))
	play.press(ui.pane_market.get_node("%ExitButton"))
	var top = ui.pane_kaiten.topping
	_until(func(): return gs.phase == gs.Phase.OPEN and top.visible and top.is_adjusting())
	gs.dashi_units = 2   # 撮るための仮の値（だしを押せる）
	play.press(ui.pane_kaiten.get_node("%PotTab"))
	await _pot(s, 3, 8, "03_pot_strength3", "鍋（濃さ3・残り8杯・だし2。仮の値。だしは3→5＝濃い側、水は3→1＝薄い側）")
	await _pot(s, 1, 8, "04_pot_strength1", "鍋（濃さ1。だしは1→3＝適正の内。水は押せない）")
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


func _pot(s, strength: int, remaining: int, file_name: String, title: String) -> void:
	gs.soup["strength"] = strength
	gs.soup["remaining_servings"] = remaining
	s.notify_changed()
	await _shot(file_name, title)


## 傷んだ在庫を足す（購入日を2日前にしたバッチ＝3日目で傷み）。tests/ui_kaiten_test.gd と同じ。
func _add_damaged(item: String, count: int) -> void:
	gs.inventory[item] = int(gs.inventory.get(item, 0)) + count
	var batches: Array = gs.perishable_batches.get(item, [])
	batches.push_front({ "day": gs.day_count - 2, "count": count, "unit_price": 8 })
	gs.perishable_batches[item] = batches


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
	var lines := PackedStringArray(["# 本番UI（UI準備P2）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_P2.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
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
