extends RefCounted
## 日次ログ（user://balance_log.jsonl）の再挑戦での二重記録（システム整理A・F2）の検証。
## 方式：行は消さず、各行に run_id（周回の識別子）と attempt（その周の何回目の挑戦か）を足す。
## 既存キーは変えない。周回の累計（GameState.day_records）は朝の辞書に入っていて再挑戦で戻るので
## 二重にならない（ファイルだけの問題）。書き出し先はテスト専用のファイルへ差し替える。

const LOG_PATH := "user://balance_log_retry_test.jsonl"


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var saved_path := BalanceLog.path
	BalanceLog.path = LOG_PATH
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.remove_absolute(LOG_PATH)

	# --- 1. run_id：新しい周ごとに変わり、同じ周では変わらない・起動時刻とプロセスidを含む ---
	BalanceLog.begin_run()
	var first_id := BalanceLog.run_id
	BalanceLog.begin_run()
	c.check("begin_run()のたびに別のrun_id（同じミリ秒でも衝突しない）・attemptは1",
		BalanceLog.run_id != first_id and BalanceLog.attempt == 1, "%s / %s" % [first_id, BalanceLog.run_id])
	var id_parts: PackedStringArray = BalanceLog.run_id.split("-")
	c.check("run_idは「起動時刻(ms)-プロセスid-連番」（連番だけではない）",
		id_parts.size() == 3 and int(id_parts[0]) > 1700000000000 and int(id_parts[1]) == OS.get_process_id(),
		BalanceLog.run_id)

	# --- 2. 1日目を終え、朝（Day1）から再挑戦して同じ日をもう一度終える ---
	var before_reset := BalanceLog.run_id
	GameState.reset_for_new_game()
	var run_a := BalanceLog.run_id
	c.check("reset_for_new_game()で新しい周のrun_idになる", run_a != before_reset and run_a != "")
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	panel._on_day_ending()
	c.check("Day1を終えるとログは1行・attempt=1・run_id入り",
		BalanceLog.read_all().size() == 1 and int(BalanceLog.read_all()[0]["attempt"]) == 1
			and str(BalanceLog.read_all()[0]["run_id"]) == run_a)
	c.check("（前提）累計day_recordsは1件", GameState.day_records.size() == 1)

	c.check("朝（Day1）から再挑戦できる", panel.retry_from_morning(1) and GameState.day_count == 1)
	c.check("再挑戦で累計は朝の値（空）に戻る＝ファイルと違って二重にならない", GameState.day_records.is_empty())
	c.check("再挑戦でattemptが進み、run_idは同じ", BalanceLog.attempt == 2 and BalanceLog.run_id == run_a)
	panel._on_day_ending()
	var rows := BalanceLog.read_all()
	c.check("同じ日をやり直すと、同じdayの行がattempt違いで2行（行は消えない）",
		rows.size() == 2 and int(rows[0]["day"]) == 1 and int(rows[1]["day"]) == 1
			and int(rows[0]["attempt"]) == 1 and int(rows[1]["attempt"]) == 2
			and rows[0]["run_id"] == rows[1]["run_id"], str(rows))
	c.check("再挑戦後も累計は1件（二重に数えない）", GameState.day_records.size() == 1)
	c.check("既存キーは変わらない（同じ朝から始めたので朝の現金・評判は同じ）",
		rows[0]["opening_money"] == rows[1]["opening_money"]
			and rows[0]["opening_reputation"] == rows[1]["opening_reputation"]
			and rows[0].has("spend_by_category") and rows[1].has("regular_visits"))
	var latest := BalanceLog.latest_per_day(rows, run_a)
	c.check("集計側：同じrun_idの同じdayは最後（attempt最大）の1行になる",
		latest.size() == 1 and int(latest[0]["attempt"]) == 2, str(latest))

	# --- 3. 結果画面からの再挑戦（Day1の朝へ・最後の朝へ）も同じ周の次の挑戦になる ---
	panel._on_run_again_pressed()
	c.check("[もう一度]も同じ周の次の挑戦（attempt=3）", BalanceLog.attempt == 3 and BalanceLog.run_id == run_a)
	c.check("戻れない再挑戦（記録の無い日）はattemptを進めない",
		not panel.retry_from_morning(9) and BalanceLog.attempt == 3)

	# --- 4. 新しい周・続きから：run_idが新しくなり、attemptは1に戻る ---
	panel._on_new_run_pressed()
	var run_b := BalanceLog.run_id
	c.check("[新しい周]でrun_idが新しくなりattemptは1", run_b != run_a and BalanceLog.attempt == 1)
	panel._on_day_ending()
	rows = BalanceLog.read_all()
	c.check("新しい周の行は別のrun_idで、前の周の行と混ざらない",
		rows.size() == 3 and str(rows[2]["run_id"]) == run_b and int(rows[2]["attempt"]) == 1
			and BalanceLog.latest_per_day(rows, run_a).size() == 1
			and BalanceLog.latest_per_day(rows, run_b).size() == 1)
	panel.session.pending_continue = GameState.morning_of(1).duplicate(true)
	panel.retry_from_morning(1)   # attempt=2にしておく
	c.check("（前提）attemptが2", BalanceLog.attempt == 2)
	panel.session.pending_continue = GameState.morning_of(1).duplicate(true)
	panel._on_continue_pressed()
	c.check("[続きから]は別の周：run_idが新しくなりattemptは1に戻る",
		BalanceLog.run_id != run_b and BalanceLog.attempt == 1, BalanceLog.run_id)

	# --- 5. 後始末 ---
	DirAccess.remove_absolute(LOG_PATH)
	BalanceLog.path = saved_path
	GameState.reset_for_new_game()
	if is_instance_valid(panel):
		panel.free()
	return c.finish()
