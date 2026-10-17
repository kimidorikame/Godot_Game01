extends RefCounted
class_name BalanceLog
## 日次ログ（user://balance_log.jsonl。1日の終わりに1行1JSONを追記）の書き出しと、
## どの周回の何回目の挑戦かの目印（システム整理A・F2）。
##
## 再挑戦（4-1：朝の保存から戻す）で同じ日をやり直すと、同じ日の行が増える。行を消さず、
## 各行に追加キーを足して区別する（既存キーは変えない＝互換性のため追加のみ）：
##   run_id  … 周回の識別子。新しい周（reset_for_new_game）・続きから読み込んだ周ごとに新しくなる。
##             起動時刻（ミリ秒）・プロセスid・プロセス内の連番を含み、起動し直しても衝突しない。
##   attempt … その周の中で、朝から戻した回数＋1（1から始まる）。
## 集計側は、同じ run_id の同じ day のうち attempt が最大（＝ファイルの中で最後）の行を取る。
## 周回の累計（GameState.day_records）は朝の辞書に入っていて再挑戦で戻るので、二重にならない
## （ファイルだけの問題）。run_id・attempt は保存しない実行時の値（セーブの版は上がらない）。
## 続きから読み込んだ周は、別のプロセスの続きなので run_id が新しくなり、attempt は1に戻る。
##
## 書き出し先は path。テスト・試遊は実際のログを汚さないよう別ファイルへ差し替える
## （tests/run_tests.gd・planning/playtest_*/playthroughs.gd）。

static var path := "user://balance_log.jsonl"

static var run_id := ""
static var attempt := 1
static var _seq := 0   # このプロセスで何回 begin_run() したか（同じミリ秒内の衝突を避ける）


## 新しい周の始まり。run_id を作り直し、attempt を1に戻す。
## 乱数（グローバルRNG）は使わない＝ゲームの乱数の消費順を変えない。
static func begin_run() -> void:
	_seq += 1
	run_id = "%d-%d-%d" % [int(Time.get_unix_time_from_system() * 1000.0), OS.get_process_id(), _seq]
	attempt = 1


## 朝から戻した（再挑戦）。同じ周の次の挑戦として、attempt を1つ進める。
static func note_retry() -> void:
	attempt += 1


## 1日分を1行追記する。run_id・attempt は書き出す行にだけ足す（呼び出し側の辞書は変えない。
## 同じ辞書が GameState.day_records に入り、朝の保存に載るため）。書けたら true。
static func append(log_entry: Dictionary) -> bool:
	if run_id == "":
		begin_run()
	var row := log_entry.duplicate()
	row["run_id"] = run_id
	row["attempt"] = attempt
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BALANCE_LOG: failed to open %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	f.store_line(JSON.stringify(row))
	f.close()
	return true


## ファイルの全行（パースできた行だけ）を、書かれた順に返す。ファイルが無ければ空。
static func read_all() -> Array:
	var rows: Array = []
	if not FileAccess.file_exists(path):
		return rows
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rows
	while not f.eof_reached():
		var line := f.get_line()
		if line == "":
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			rows.append(parsed)
	f.close()
	return rows


## 同じ run_id の同じ day のうち、最後（attempt が最大）の行だけを、日の順に返す
## （集計側の読み方の見本。run_id が空の行は無い前提）。
static func latest_per_day(rows: Array, for_run_id: String) -> Array:
	var by_day := {}
	for r in rows:
		if str(r.get("run_id", "")) != for_run_id:
			continue
		by_day[int(r.get("day", 0))] = r
	var days := by_day.keys()
	days.sort()
	var result: Array = []
	for d in days:
		result.append(by_day[d])
	return result
