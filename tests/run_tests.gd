extends SceneTree
## headlessテストの入口。`res://tests/*_test.gd`を全部（または引数で指定した1つだけ）
## 走らせ、失敗があれば非ゼロで終了する。
##
## 実行例（プロジェクト直下から）：
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- schedule_test
##
## 各スイートは `extends RefCounted` で `func run(t: SceneTree) -> int`（失敗数を返す）を
## 持つこと。autoload（GameStateなど）の解決を待つため、スキャン開始前に1フレーム待つ
## （既存の使い捨てハーネスと同じ理由）。
##
## 壊れたスイートで全体が止まらず、成功にも見えないようにしている：
##   - 構文エラーなどで読み込めない／インスタンス化できない／run()が無いスイートは、
##     失敗1件として数えて、残りのスイートを続ける（以前は load().new() の呼び出しが
##     エラーになり、_initialize()が途中で終わって、quit()が呼ばれず永久に止まっていた）。
##   - run() の実行中にエラー（nullへの呼び出しなど）が起きると、GDScriptはその関数だけを
##     打ち切り、戻り値は既定の0になる（例外処理は無い）。各スイートは最後に
##     `return c.finish()`（TestCheck）を呼ぶ決まりで、run()の前後で TestCheck.completed_runs
##     が増えなかったスイートは、失敗1件として数える（以前は 0 件扱いで、途中で落ちた
##     スイートが成功に見えていた）。
##   - 引数で指定したスイートが無い場合も失敗として終了する。

func _initialize() -> void:
	await process_frame
	# 1枠セーブ（MorningSave）の保存先を、全スイートで実際のセーブと別のファイルにする
	# （DebugPanelはWAKEのたびに書くので、差し替えないとテストが本物のセーブを上書きする）。
	# MorningSaveはautoload（GameState）を参照するので、この入口スクリプトのコンパイル時に
	# 解決させない（他の使い捨てハーネスと同じ理由）。実行時にloadして使う。
	var morning_save = load("res://scripts/morning_save.gd")
	morning_save.set("save_path", "user://test_save.dat")
	morning_save.call("delete_file")
	# 既読（ReadState）は、実際の user://read_state.json と別のファイルにし、メモリ上の集合を初期化する
	# （単体実行でも実際の既読を読まず・書かない）。
	var read_state = load("res://scripts/read_state.gd")
	read_state.call("reset", "user://test_read_state.json")
	if FileAccess.file_exists("user://test_read_state.json"):
		DirAccess.remove_absolute("user://test_read_state.json")
	# 日次ログ（BalanceLog）の書き出し先も、実際のログ（user://balance_log.jsonl）と別のファイルにする
	# （日の終わりごとに追記するので、差し替えないとテストが本物のログを汚す）。
	var balance_log = load("res://scripts/balance_log.gd")
	balance_log.set("path", "user://test_balance_log.jsonl")
	if FileAccess.file_exists("user://test_balance_log.jsonl"):
		DirAccess.remove_absolute("user://test_balance_log.jsonl")
	var only := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		only = args[0]

	var dir := DirAccess.open("res://tests")
	var suite_paths := []
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.ends_with("_test.gd") and (only == "" or name == only + ".gd"):
				suite_paths.append("res://tests/" + name)
			name = dir.get_next()
		dir.list_dir_end()
	suite_paths.sort()

	var total_fails := 0
	if suite_paths.is_empty():
		# 指定したスイート名に合うファイルが無い（打ち間違い）。成功にしない。
		print("失敗: 実行するスイートが見つからない（指定: ", only if only != "" else "（全部）", "）")
		total_fails += 1
	for path in suite_paths:
		print("== ", path, " ==")
		var script = load(path)
		if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
			print("  FAIL ", path, " を読み込めない（構文エラーなど。上のエラー表示を参照）")
			total_fails += 1
			continue
		var suite = script.new()
		if suite == null or not suite.has_method("run"):
			print("  FAIL ", path, " にrun()が無い")
			total_fails += 1
			continue
		var completed_before: int = TestCheck.completed_runs
		var result = suite.run(self)
		if TestCheck.completed_runs == completed_before:
			# run()が最後（c.finish()）まで届かなかった＝実行中のエラーで打ち切られた
			# （GDScriptは関数だけを打ち切り、戻り値は0になる）。上のエラー表示を参照。
			print("  FAIL ", path, " のrun()が最後まで走り切らなかった（実行中のエラーで打ち切られた）")
			total_fails += 1
			continue
		total_fails += int(result)

	morning_save.call("delete_file")
	print("合計失敗数: ", total_fails)
	quit(1 if total_fails > 0 else 0)
