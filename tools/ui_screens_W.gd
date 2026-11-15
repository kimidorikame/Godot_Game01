# 中身W（改訂版の来店の予定とモブの職種表）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_W.gd    → planning/ui_screens_W/
# 撮るもの：2日目の夜半の共同洗濯場の夜番（モブの名前の札）・2日目の明け方のセティヤ（名前の札）・3日目の夜半のニカの初来店。
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd）。撮るあいだだけ BAD も定価にする（日を進めるため）。
extends SceneTree

var out_dir := "res://planning/ui_screens_W"
var gs
var ui
var play
var shots: Array = []


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
	# 開店中で、その時間帯の客の挨拶（GREET）が出ている
	var greet_of := func(day: int, slot: String, who: Callable) -> bool:
		if gs.day_count != day or s.open == null or s.open.current_slot_name() != slot:
			return false
		var line: Dictionary = s.current_line()
		return str(line.get("type", "")) == "GREET" and who.call(str(line.get("speaker", "")))
	var mob_type := func(id: String) -> String:
		return str(gs.today_plan.get("mob_instances", {}).get(id, {}).get("type", "")) if id.begins_with("mob#") else ""

	await _until(func(): return greet_of.call(2, "夜半", func(id): return mob_type.call(id) == "laundry_night"))
	await _shot("01_day2_yahan_laundry", "2日目の夜半：共同洗濯場の夜番（名前の札）")
	await _until(func(): return greet_of.call(2, "明け方", func(id): return id == "hooker"))
	await _shot("02_day2_akegata_setiya", "2日目の明け方：セティヤ（名前の札）")
	await _until(func(): return greet_of.call(3, "夜半", func(id): return id == "streamer"), 20000)
	await _shot("03_day3_yahan_nika_first", "3日目の夜半：ニカ（配信者）の初来店")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# 中身W のスクリーンショット（tools/ui_screens_W.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _until(cond: Callable, limit: int = 12000) -> void:
	var n := 0
	while not cond.call() and n < limit:
		n += 1
		await process_frame
		if play.step() == "":
			break
	if not cond.call():
		push_error("状態に届かなかった（%d手）" % n)


func _shot(file_name: String, title: String) -> void:
	for i in range(4):
		await process_frame
	var plate := str(ui.left._name_label.text)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, file_name]))
	shots.append("%s.png  %s（Day%d・%s・名前の札「%s」）" % [file_name, title, gs.day_count, ui.session.open.current_slot_name(), plate])
