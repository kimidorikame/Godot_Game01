# UI準備AJ・中身AJ（具を選んでいる間、客が注文を言った行を会話枠に出す）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_AJ.gd    → planning/ui_screens_AJ/
# 撮るもの：1日目の安宿の夜勤受付（2ページの1ページ目と2ページ目）、2日目の警官（店主の行が入る場面）、3日目のニカ。
# どれも撮影の道具の中で、その日のその場面を組み立てて撮る（鍋は上限14杯の中で入れる。ゲームのデータは変えない）。
extends SceneTree

var out_dir := "res://planning/ui_screens_AJ"
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
	# 1日目の安宿の夜勤受付（モブ1組・2ページ）
	var ui = await _open(1, ["mob#0"], { "mob#0": { "type": "inn_clerk", "count": 1 } })
	_to_adjust(ui.session)
	ui.left.refresh()
	await _shot("01_inn_clerk_d1_page1", "1日目の安宿の夜勤受付：具を選ぶ間の注文の行（1ページ目）")
	ui.left.advance()
	await _shot("02_inn_clerk_d1_page2", "1日目の安宿の夜勤受付：会話枠のクリックで2ページ目（列は進まない）")
	ui.queue_free()
	await _frames(2)
	# 2日目の警官（店主の行が入る場面）
	ui = await _open(2, ["officer"], {})
	_to_adjust(ui.session)
	ui.left.refresh()
	await _shot("03_officer_d2", "2日目の警官：店主の行（「酸っぱい汁。あと、ちゃんと噛めるもの」）が入る注文の行")
	ui.queue_free()
	await _frames(2)
	# 3日目のニカ（2ページ）
	ui = await _open(3, ["streamer"], {})
	_to_adjust(ui.session)
	ui.left.refresh()
	await _shot("04_streamer_d3_page1", "3日目のニカ：注文の行（1ページ目）")
	ui.left.advance()
	await _shot("05_streamer_d3_page2", "3日目のニカ：2ページ目")
	ui.queue_free()
	await _frames(2)
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備AJ・中身AJ のスクリーンショット（tools/ui_screens_AJ.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _open(day: int, customers: Array, mob: Dictionary):
	gs.reset_for_new_game()
	gs.day_count = day
	var ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	ui.full_prep.auto_advance = false
	await _frames(2)
	var s = ui.session
	gs.inventory.clear()
	gs.perishable_batches.clear()
	for id in ["coconut_milk", "tofu", "nam_prik_pao", "meat_ball", "pickled_lime", "cartilage"]:
		gs.add_inventory(id, 6, 8)
	gs.set_soup("bone_broth", ["meaty"], 14, 3, 2)
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
