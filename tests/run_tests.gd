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

func _initialize() -> void:
	await process_frame
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
	for path in suite_paths:
		print("== ", path, " ==")
		var suite = load(path).new()
		total_fails += suite.run(self)

	print("合計失敗数: ", total_fails)
	quit(1 if total_fails > 0 else 0)
