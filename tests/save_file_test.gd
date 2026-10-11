extends RefCounted
## F7 1枠セーブ（フェーズ4-1コミット②・DESIGN.md 10.6）の検証。
## 対象：MorningSaveのファイル入出力（型の保持・壊れたファイルの扱い）と、DebugPanelの
## 「朝に書く」「起動時に続きから」「読み込んだ朝をmorning_snapshotsへ入れる」。
##
## 保存先はテスト専用のパスに差し替える（実際のセーブを壊さない。run_tests.gdも全体で
## 差し替えているが、このスイート単独でも安全なようにここでも差し替えて元へ戻す）。

const TEST_PATH := "user://save_file_test.dat"


func _setup(t: SceneTree, money: int, day: int = 1):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が起動時のセーブを読み、WAKEを組む
	return panel


## 実際の朝（Day4・評判47・在庫・帳簿・DayPlan入り）の封筒を作る。
func _sample_envelope() -> Dictionary:
	GameState.reset_for_new_game()
	GameState.day_count = 4
	GameState.money = 321
	GameState.reputation = 47
	GameState.inventory = { "tofu": 3, "meat_ball": 2 }
	GameState.perishable_batches = { "tofu": [{ "day": 3, "count": 3, "unit_price": 8 }] }
	GameState.dashi_units = 2
	GameState.known_favorites = { "granny": true }
	GameState.ledger = [{ "day": 3, "phase": "OPEN", "category": "sale", "amount": 45,
		"item": "granny", "count": 1, "unit_price": 0, "ref": "" }]
	GameState.today_plan = {
		"day": 4, "demand_center": 11,
		"slots": [{ "name": "夕方", "customers": ["delivery_man", "mob#0"] },
			{ "name": "夜", "customers": ["granny"] }],
		"mob_instances": { "mob#0": { "type": "dock_workers", "count": 2 } },
	}
	return MorningSave.capture("昨日の一言")


func _write_raw(bytes: PackedByteArray) -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var saved_path := MorningSave.save_path
	MorningSave.save_path = TEST_PATH
	MorningSave.delete_file()

	# --- 1. 書いて読む：型が保たれる（JSONだと整数がfloatになる点の回帰） ---
	var env := _sample_envelope()
	c.check("セーブが無いときhas_fileはfalse・read_fileは空", not MorningSave.has_file() and MorningSave.read_file().is_empty())
	c.check("write_fileは成功する", MorningSave.write_file(env))
	c.check("write_file後にhas_fileがtrue", MorningSave.has_file())
	c.check("一時ファイルが残らない", not FileAccess.file_exists(TEST_PATH + ".tmp"))
	var back := MorningSave.read_file()
	c.check("読んだ封筒は書いたものと一致する", back == env)
	c.check("読んだ封筒はis_valid", MorningSave.is_valid(back))
	var st: Dictionary = back["state"]
	c.check("整数が整数のまま（day_count・money・在庫の個数）",
		typeof(st["day_count"]) == TYPE_INT and typeof(st["money"]) == TYPE_INT
			and typeof(st["inventory"]["tofu"]) == TYPE_INT)
	c.check("帳簿の各行の整数・文字列が保たれる",
		typeof(st["ledger"][0]["amount"]) == TYPE_INT and typeof(st["ledger"][0]["day"]) == TYPE_INT
			and str(st["ledger"][0]["category"]) == "sale")
	c.check("バッチの購入日・単価が整数のまま",
		typeof(st["perishable_batches"]["tofu"][0]["day"]) == TYPE_INT
			and typeof(st["perishable_batches"]["tofu"][0]["unit_price"]) == TYPE_INT)
	c.check("known_favoritesの真偽値が保たれる", st["known_favorites"]["granny"] == true)
	c.check("DayPlan（slots・mob_instances・demand_center）が保たれる",
		st["today_plan"]["slots"] == env["state"]["today_plan"]["slots"]
			and typeof(st["today_plan"]["mob_instances"]["mob#0"]["count"]) == TYPE_INT
			and int(st["today_plan"]["demand_center"]) == 11)
	c.check("Array.has()が整数で働く（読み込み後のdays配列）",
		([1, 2, 3] as Array).has(int(st["today_plan"]["day"]) - 3) and typeof(st["today_plan"]["day"]) == TYPE_INT)
	c.check("前日の一言が保たれる", str(back["panel"]["day_summary_text"]) == "昨日の一言")

	# 書き直し：前のセーブを置き換える（1枠）
	var env2 := env.duplicate(true)
	env2["state"]["money"] = 999
	c.check("上書き保存が成功する", MorningSave.write_file(env2))
	c.check("上書き後は新しい内容を読む", int(MorningSave.read_file()["state"]["money"]) == 999)

	# --- 2. 読めないとき：例外なく空の辞書（新規ゲーム扱い）。ファイルは消さない ---
	_write_raw(PackedByteArray())
	c.check("空ファイルは空の辞書", MorningSave.read_file().is_empty())
	_write_raw("これはセーブではない".to_utf8_buffer())
	c.check("別の内容のファイルは空の辞書", MorningSave.read_file().is_empty())
	var magic := "YORUYUSAVE1".to_ascii_buffer()
	_write_raw(magic)
	c.check("マジックだけのファイルは空の辞書", MorningSave.read_file().is_empty())
	var good := magic + var_to_bytes(env)
	_write_raw(good.slice(0, int(good.size() * 0.5)))
	c.check("途中で切れたファイルは空の辞書", MorningSave.read_file().is_empty())
	var old := env.duplicate(true)
	old["version"] = 0
	_write_raw(magic + var_to_bytes(old))
	c.check("古い版のファイルは空の辞書", MorningSave.read_file().is_empty())
	var other := env.duplicate(true)
	other["campaign"] = "week21"
	_write_raw(magic + var_to_bytes(other))
	c.check("別キャンペーンのファイルは空の辞書", MorningSave.read_file().is_empty())
	var broken := env.duplicate(true)
	broken["state"]["money"] = 321.0
	_write_raw(magic + var_to_bytes(broken))
	c.check("型が壊れた（整数がfloat）ファイルは空の辞書", MorningSave.read_file().is_empty())
	_write_raw(magic + var_to_bytes([1, 2, 3]))
	c.check("封筒でない中身は空の辞書", MorningSave.read_file().is_empty())
	c.check("読めなくてもファイルは消されない", MorningSave.has_file())
	c.check("is_validでない封筒はwrite_fileしない（ファイルを壊さない）",
		not MorningSave.write_file({ "version": 1 }))
	MorningSave.delete_file()
	c.check("delete_file後はファイルが無い", not MorningSave.has_file())

	# --- 3. 朝のWAKEでセーブが書かれる（運営費が払えた朝だけ。書くのは運営費を引く前の辞書） ---
	var panel = _setup(t, 300, 1)
	var file_env := MorningSave.read_file()
	c.check("セーブが無い起動：最初のWAKEでファイルが書かれる", not file_env.is_empty())
	c.check("書かれた辞書は運営費を引く前（300）・Day1・DayPlan入り",
		int(file_env["state"]["money"]) == 300 and int(file_env["day"]) == 1
			and int(file_env["state"]["today_plan"]["day"]) == 1
			and not (file_env["state"]["today_plan"]["slots"] as Array).is_empty())
	c.check("書かれた辞書はGameState.morning_snapshotsの朝と同じ",
		file_env == GameState.latest_morning())
	c.check("[続きから]はセーブが無い起動では押せない", panel._btn_continue.disabled)

	# 運営費が払えない朝（Day2）：ゲームオーバー。ファイルはDay1のまま・消えない
	GameState.money = 50
	GameState.day_count = 2
	panel._set_runner_for_phase(GameState.Phase.WAKE)
	c.check("運営費が払えないとゲームオーバー", GameState.phase == GameState.Phase.GAME_OVER)
	c.check("払えなかった朝はセーブへ書かない（Day1のまま・消えない）",
		int(MorningSave.read_file().get("day", -1)) == 1)

	# --- 4. 起動時にセーブがある：[続きから]を押すまで上書きしない。読み込んだ朝が記録される ---
	var saved := _sample_envelope()
	MorningSave.write_file(saved)
	var panel2 = _setup(t, 600, 1)
	c.check("セーブがある起動では最初のWAKEでも上書きしない",
		int(MorningSave.read_file()["state"]["money"]) == 321 and int(MorningSave.read_file()["day"]) == 4)
	c.check("[続きから]が押せる", not panel2._btn_continue.disabled)
	panel2._on_continue_pressed()
	c.check("続きから：日・評判・在庫が保存した朝のもの",
		GameState.day_count == 4 and GameState.reputation == 47
			and int(GameState.inventory.get("tofu", 0)) == 3 and GameState.dashi_units == 2)
	c.check("続きから：所持金は保存した朝（321）から運営費を引いた値",
		GameState.money == 321 - GameState.DAILY_OPERATING_COST, str(GameState.money))
	c.check("続きから：DayPlanは保存したものと同一（build()を呼ばない）",
		GameState.today_plan["slots"] == saved["state"]["today_plan"]["slots"]
			and GameState.today_plan["mob_instances"] == saved["state"]["today_plan"]["mob_instances"]
			and int(GameState.today_plan["demand_center"]) == 11)
	c.check("続きから：フェーズはWAKE・[続きから]は使用済み",
		GameState.phase == GameState.Phase.WAKE and panel2._btn_continue.disabled)
	c.check("読み込んだ朝がmorning_snapshotsに入っている（起動直後のDay1の記録は無い）",
		GameState.morning_snapshots.has(4) and not GameState.morning_snapshots.has(1)
			and GameState.morning_snapshots.size() == 1)
	c.check("続きから：読み込んだ朝のdaily_costとreserveは1回だけ",
		_count_today("daily_cost") == 1 and _count_today("reserve") == 1)
	# 読み込み直後の朝で詰んだとき：読み込んだ朝へ戻れる
	GameState.money = 5
	GameState.inventory["probe"] = 1
	panel2._game_over("テスト用ゲームオーバー")
	c.check("読み込み直後でも[同じ朝からやり直す]が押せる", not panel2._btn_retry.disabled)
	c.check("読み込んだ朝へ再挑戦できる", panel2.retry_from_morning() and GameState.day_count == 4)
	c.check("再挑戦した朝は読み込んだ朝のDayPlan・所持金・在庫",
		GameState.today_plan["slots"] == saved["state"]["today_plan"]["slots"]
			and GameState.money == 321 - GameState.DAILY_OPERATING_COST
			and not GameState.inventory.has("probe"))
	c.check("続きから後は書き込みが有効（ファイルは同じ朝のまま更新される）",
		int(MorningSave.read_file()["day"]) == 4)

	# --- 5. 起動時にセーブがあり、続きからを押さず最初の朝を抜けた：新しい朝で上書きする ---
	MorningSave.write_file(_sample_envelope())
	var panel3 = _setup(t, 600, 1)
	c.check("（前提）起動直後はまだ上書きしていない", int(MorningSave.read_file()["day"]) == 4)
	panel3.flow.advance_phase()   # WAKE→PREP（最初の朝を抜ける）
	var after := MorningSave.read_file()
	c.check("最初の朝を抜けると、そのゲームのDay1の朝で上書きされる",
		int(after.get("day", -1)) == 1 and int(after["state"]["money"]) == 600, str(after.get("day")))
	c.check("上書き後は[続きから]が使えない", panel3._btn_continue.disabled)

	# --- 6. 壊れたセーブがある起動：新規ゲームとして始まり、最初の朝で上書きされる ---
	_write_raw("壊れたセーブ".to_utf8_buffer())
	var panel4 = _setup(t, 600, 1)
	c.check("壊れたセーブでは[続きから]が押せない", panel4._btn_continue.disabled)
	c.check("壊れたセーブは最初の朝で新しい朝に置き換わる",
		int(MorningSave.read_file().get("day", -1)) == 1)

	# --- 7. ゲームオーバーではセーブを消さない（最後の朝が残る＝次回の続きからが再挑戦になる） ---
	var panel5 = _setup(t, 600, 1)
	GameState.money = 10
	panel5._game_over("テスト")
	c.check("ゲームオーバー後もセーブは残る", MorningSave.has_file() and not MorningSave.read_file().is_empty())

	GameState.reset_for_new_game()
	for p in [panel, panel2, panel3, panel4, panel5]:
		if is_instance_valid(p):
			p.free()
	MorningSave.delete_file()
	MorningSave.save_path = saved_path
	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails


func _count_today(category: String) -> int:
	var n := 0
	for row in GameState.ledger:
		if int(row.get("day", -1)) == GameState.day_count and str(row.get("category", "")) == category:
			n += 1
	return n
