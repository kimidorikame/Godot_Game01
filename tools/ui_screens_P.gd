# 本番UI（UI準備P：判断に使う文字の大きさ・椀の案内文・取り消しと廃棄・仕入れの「手持ち → 購入後」）の before／after の
# スクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_P.gd -- after    → planning/ui_screens_P/after/
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_P.gd -- before   → planning/ui_screens_P/before/（P の前のコミットで撮る）
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd。ボタンと会話枠のクリックだけ）。撮るための仮の在庫は、題に「仮」と書く。
# あわせて、文字が枠に入りきらないラベル・ボタン・横並び（札の列など）を overflow.txt に書き出す。
# セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

var out_dir := "res://planning/ui_screens_P/after"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	out_dir = "res://planning/ui_screens_P/%s" % (args[0] if not args.is_empty() else "after")
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

	# Day2 の朝 → 張記（鍋の素「中」を買い、モツをかごへ）
	_until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 40:
		guard += 1
		ui.left.advance()
	gs.money += 300   # 撮るための仮の所持金（かごに何品も入れるため）
	play.press(ui.pane_morning.get_node("%PrimaryButton"))
	_until(func(): return ui.pane_buy_meat.visible and s.is_in_prep_tier())
	play.press(ui.pane_buy_meat.get_node("%Tiers").get_child(1))
	play.press(ui.pane_buy_meat.get_node("%ConfirmButton"))
	var meat_goods = ui.pane_buy_meat.get_node("%Goods")
	play.press(meat_goods.get_child(0).get_node("BuyButton"))
	play.press(meat_goods.get_child(0).get_node("BuyButton"))
	await _shot("01_buy_meat_cart", "市場の商品一覧（張記。モツを2回かごに入れたところ）")
	play.press(ui.pane_buy_meat.get_node("%ConfirmButton"))
	await _shot("02_buy_meat_bought", "市場の商品一覧（張記。購入確定のあと＝かごが空。手持ちに入った）")
	play.press(ui.pane_buy_meat.get_node("%BackButton"))
	_until(func(): return ui.pane_market.visible)
	# 豆腐麺房：豆腐2回・米麺1回をかごへ
	play.press(ui.pane_market.get_node("%Stalls").get_child(3))
	var goods = ui.pane_buy_shop.get_node("%Goods")
	play.press(goods.get_child(0).get_node("BuyButton"))
	play.press(goods.get_child(0).get_node("BuyButton"))
	play.press(goods.get_child(1).get_node("BuyButton"))
	await _shot("03_buy_shop_cart", "市場の商品一覧（福生豆腐麺房。豆腐2回・米麺1回をかごに入れたところ）")
	play.click(ui.left.get_node("%PhoneIcon"))
	ui.pane_phone._on_tab_pressed("inventory")
	await _shot("04_phone_inventory_cart", "スマホの持ち物（豆腐麺房でかごに入れたまま開いた）")
	play.press(ui.pane_phone.get_node("%CloseButton"))
	play.press(ui.pane_buy_shop.get_node("%ConfirmButton"))
	await _shot("05_buy_shop_bought", "市場の商品一覧（豆腐麺房。購入確定のあと）")
	play.click(ui.left.get_node("%PhoneIcon"))
	ui.pane_phone._on_tab_pressed("inventory")
	await _shot("06_phone_inventory_bought", "スマホの持ち物（購入確定のあと＝かごは空）")
	play.press(ui.pane_phone.get_node("%CloseButton"))
	play.press(ui.pane_buy_shop.get_node("%BackButton"))
	# 撮るための仮の在庫（市場を出る前に足す＝椀の選択肢は注文の時点の在庫で決まる）：具材12品すべて（ページ送りを見る）・傷んだ豆腐2
	for id in ["offal", "meat_ball", "tofu", "broken_wrapper", "winter_melon", "cartilage", "tendon_meat", "dried_wood_ear",
			"rice_noodle", "shrimp", "clam", "fish_maw", "nam_prik_pao", "coconut_milk", "pickled_lime", "bitter_melon", "herbal_sauce"]:
		if gs.fresh_count(id) <= 0:
			gs.add_inventory(id, 3)
	_add_damaged("tofu", 2)
	play.press(ui.pane_market.get_node("%ExitButton"))

	# 開店：最初の椀の入力待ち
	var top = ui.pane_kaiten.topping
	_until(func(): return gs.phase == gs.Phase.OPEN and top.visible and top.is_adjusting())
	ui.pane_kaiten._on_tab_pressed("topping")
	s.notify_changed()
	await _shot("07_topping_empty", "夜の具材選び（空の椀。仮の在庫：具材12品・傷んだ豆腐2）")
	var tabs = top.get_node("%Tabs")
	if tabs.get_child_count() > 1 and tabs.get_child(1).visible and str(tabs.get_child(1).text).begins_with("具材"):
		play.press(tabs.get_child(1))
		await _shot("08_topping_page2", "夜の具材選び（具材の2ページ目）")
		play.press(tabs.get_child(0))
	var grid = top.get_node("%Grid")
	play.press(grid.get_child(0).get_node("MainButton"))
	await _shot("09_topping_one", "夜の具材選び（具を1つ入れた＝味付けがまだ）")
	for i in range(grid.get_child_count()):
		var item = grid.get_child(i)
		if item.visible and item.get_node("DamagedButton").visible and not item.get_node("DamagedButton").disabled:
			play.press(item.get_node("DamagedButton"))
			break
	for tab in tabs.get_children():
		if tab.visible and str(tab.text).begins_with("調味料"):
			play.press(tab)
			break
	play.press(grid.get_child(0).get_node("MainButton"))
	await _shot("10_topping_damaged", "夜の具材選び（具・傷んだ豆腐・味付けを入れた＝傷みの減点）")
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


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
	var lines := PackedStringArray(["# 本番UI（UI準備P）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_P.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
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
