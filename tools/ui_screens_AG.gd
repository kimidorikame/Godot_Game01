# UI準備AG・中身AF（市場の店ごとの会話・具だくさんと断ったときの一言）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AG.gd    → planning/ui_screens_AG/
# 撮るもの：3日目の海叔・4日目のアユ・6日目のヨヨ（店を押したときの会話）、具だくさんの一言（6日目のレックス）、
# 断ったときの一言（1日目の阿強の2杯目を断った道）。どれも撮影の道具の中で、その日のその場面を組み立てて撮る（ゲームのデータは変えない）。
extends SceneTree

var out_dir := "res://planning/ui_screens_AG"
var gs
var shots: Array = []


func _initialize() -> void:
	await process_frame
	load("res://scripts/morning_save.gd").set("save_path", "user://ui_screens_save.dat")
	load("res://scripts/morning_save.gd").call("delete_file")
	load("res://scripts/read_state.gd").call("reset", "user://ui_screens_read_state.json")
	load("res://scripts/balance_log.gd").set("path", "user://ui_screens_balance_log.jsonl")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	gs = root.get_node("GameState")
	for item in [[3, "seafood", "01_day3_seafood_hai", "3日目：海隆鮮貨を押したとき（海叔）"],
			[4, "produce", "02_day4_produce_ayu", "4日目：永順青果を押したとき（アユ）"],
			[6, "scraps", "03_day6_scraps_yoyo", "6日目：半端市「拾味」を押したとき（ヨヨ）"]]:
		await _shop_shot(int(item[0]), str(item[1]), str(item[2]), str(item[3]))
	await _hearty_shot()
	await _decline_shot()
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備AG・中身AF のスクリーンショット（tools/ui_screens_AG.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _new_ui(day: int):
	gs.reset_for_new_game()
	gs.day_count = day
	var ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	ui.full_prep.auto_advance = false
	await _frames(2)
	return ui


## 市場の画面（MARKET の入力待ち）を組み立てて、店を押す。
func _shop_shot(day: int, shop: String, file_name: String, title: String) -> void:
	var ui = await _new_ui(day)
	var s = ui.session
	gs.phase = gs.Phase.PREP
	var events: Array = load("res://scripts/day1_events.gd").call("prep_after_tier_events", load("res://scripts/day1_events.gd").call("prep_tier_by_id", "medium"), false)
	s.flow.set_runner(events)
	var at := events.map(func(e): return str(e.get("type", ""))).find("MARKET")
	s.flow.runner.index = at
	s.flow.runner.status = 1   # EventRunner.Status.WAITING_INPUT
	ui.close_overlay()
	s.select_stall(shop)
	await _shot(file_name, title)
	ui.queue_free()
	await _frames(2)


## 客を1組だけ並べた開店の画面（テストの組み立てと同じ）。
func _open(day: int, customers: Array):
	var ui = await _new_ui(day)
	var s = ui.session
	gs.inventory.clear()
	gs.perishable_batches.clear()
	for id in ["coconut_milk", "tofu", "winter_melon", "nam_prik_pao", "meat_ball"]:
		gs.add_inventory(id, 6, 8)
	gs.set_soup("bone_broth", ["meaty"], 20, 3, 2)
	gs.phase = gs.Phase.OPEN
	s.open = load("res://scripts/open_controller.gd").new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	ui.close_overlay()
	return ui


func _to_adjust(s) -> void:
	var guard := 0
	while not s.is_choosing_ingredients() and guard < 120:
		guard += 1
		s.next_event()


func _hearty_shot() -> void:
	var ui = await _open(6, ["thug"])
	var s = ui.session
	_to_adjust(s)
	for id in ["coconut_milk", "tofu", "winter_melon"]:
		s.select_ingredient(id)
	s.complete_input()
	s.next_event()   # REACT
	await _shot("04_hearty_react", "具だくさん：6日目のレックスの反応（チップの「具だくさん +¥10」）")
	s.next_event()   # 具だくさんの一言
	await _shot("05_hearty_line", "具だくさん：反応のすぐあとの具だくさんの一言")
	ui.queue_free()
	await _frames(2)


func _decline_shot() -> void:
	var ui = await _open(1, ["delivery_man"])
	var s = ui.session
	_to_adjust(s)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	var guard := 0
	while guard < 60:
		guard += 1
		s.next_event()
		if s.is_choosing_ingredients():
			break
	(ui.pane_kaiten.topping.get_node("%DeclineButton") as Button).pressed.emit()   # 画面の「断る」
	await _shot("06_decline_cup2", "断ったとき：1日目の阿強の2杯目を断った道（断ったときの一言。このあと残りの杯は出ずに帰る）")
	ui.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(file_name: String, title: String) -> void:
	for i in range(5):
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, file_name]))
	shots.append("%s.png  %s" % [file_name, title])
