# UI準備AH・中身AH（濃さ・傷みで評価が下がったときの理由の一言）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AH.gd    → planning/ui_screens_AH/
# 撮るもの：1日目の阿強の1杯目（ナムプリックパオ＋肉団子・濃さ5）の反応と濃いの一言、モブ1組（3日目の安宿の夜勤受付・濃さ1）の反応と薄いの一言。
# どれも撮影の道具の中で、その日のその場面を組み立てて撮る（鍋は上限14杯の中で入れる。ゲームのデータは変えない）。
extends SceneTree

var out_dir := "res://planning/ui_screens_AH"
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
	# 1日目の阿強の1杯目（濃さ5）
	var ui = await _open(1, ["delivery_man"], 5, {})
	var s = ui.session
	_to_adjust(s)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	s.next_event()   # REACT
	await _shot("01_akiang_cup1_react", "1日目の阿強の1杯目（ナムプリックパオ＋肉団子・濃さ5）：反応は減点の前の評価の文")
	s.next_event()   # 濃いの一言
	await _shot("02_akiang_cup1_strong", "1日目の阿強の1杯目：そのあとに濃いの一言")
	ui.queue_free()
	await _frames(2)
	# モブ1組（3日目の安宿の夜勤受付・濃さ1）
	ui = await _open(3, ["mob#0"], 1, { "mob#0": { "type": "inn_clerk", "count": 1 } })
	s = ui.session
	_to_adjust(s)
	s.select_ingredient("coconut_milk")
	s.select_ingredient("tofu")
	s.group_serve(1, 1)
	s.next_event()   # REACT
	await _shot("03_mob_inn_react", "モブ1組（3日目の安宿の夜勤受付・濃さ1）：反応は減点の前の評価の文")
	s.next_event()   # 薄いの一言
	await _shot("04_mob_inn_weak", "モブ1組：そのあとに薄いの一言（組で1行）")
	ui.queue_free()
	await _frames(2)
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備AH・中身AH のスクリーンショット（tools/ui_screens_AH.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _open(day: int, customers: Array, strength: int, mob: Dictionary):
	gs.reset_for_new_game()
	gs.day_count = day
	var ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	ui.full_prep.auto_advance = false
	await _frames(2)
	var s = ui.session
	gs.inventory.clear()
	gs.perishable_batches.clear()
	for id in ["coconut_milk", "tofu", "nam_prik_pao", "meat_ball"]:
		gs.add_inventory(id, 6, 8)
	gs.set_soup("bone_broth", ["meaty"], 14, strength, 2)
	gs.phase = gs.Phase.OPEN
	for id in mob:
		gs.today_plan["mob_instances"][id] = mob[id]
	s.open = load("res://scripts/open_controller.gd").new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	ui.close_overlay()
	return ui


func _to_adjust(s) -> void:
	var guard := 0
	while not s.is_choosing_ingredients() and guard < 120:
		guard += 1
		s.next_event()


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(file_name: String, title: String) -> void:
	for i in range(5):
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, file_name]))
	shots.append("%s.png  %s" % [file_name, title])
