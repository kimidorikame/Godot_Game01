# UI準備V2（会話枠の行頭禁則・追い出し）のスクリーンショットを撮る（1280×720のPNG）。
# ウィンドウありで起動する：godot --path . --resolution 1280x720 --script res://tools/ui_screens_V2.gd    → planning/ui_screens_V2/
# 撮るもの：UI準備V の報告にあった9か所のうち2つ（阿強「…こいつが置いてあんの」」・労働者B「…班についてる！」」）。
extends SceneTree

var out_dir := "res://planning/ui_screens_V2"
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
	var text_is := func(t: String): return str(s.current_line().get("speaker_name", "")) + str(s.current_line().get("text", "")) == t
	await _until(func(): return text_is.call("阿強「俺が探してるの覚えててさ。『あったよ』って写真が来たんだよ。缶と瓶の真ん中に、こいつが置いてあんの」"))
	await _shot("01_akiang_okiteannno", "阿強「…こいつが置いてあんの」」：「の」を連れて次の行へ（行の頭に「」」が来ない）")
	await _until(func(): return text_is.call("労働者B「お、残業の明細来た。八番の荷、ちゃんとうちの班についてる！」"))
	await _shot("02_dock_b_tsuiteru", "労働者B「…班についてる！」」：「る」を連れて次の行へ（行の頭に「！」が来ない）")
	print("UI_SCREENS_DONE %d" % shots.size())
	var f := FileAccess.open("%s/shots.txt" % out_dir, FileAccess.WRITE)
	f.store_string("# UI準備V2 のスクリーンショット（tools/ui_screens_V2.gd が書き出す）\n" + "\n".join(PackedStringArray(shots)) + "\n")
	f.close()
	quit()


func _until(cond: Callable, limit: int = 5000) -> void:
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
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [out_dir, file_name]))
	shots.append("%s.png  %s" % [file_name, title])
