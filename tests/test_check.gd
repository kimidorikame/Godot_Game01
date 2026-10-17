extends RefCounted
class_name TestCheck
## 各テストスイート共通のチェック・集計ヘルパー（headlessテストの使い捨てスクリプトで
## 毎回コピペしていたものを1箇所に集約）。使い方は各スイートの run() を参照。

# 最後まで走り切った（finish()を呼んだ）スイートの数。run_tests.gdが、スイートの実行前後で
# これが増えたかを見て、途中でエラーが起きて打ち切られたスイートを失敗として数える
# （GDScriptは実行中のエラーでその関数だけを打ち切り、戻り値は既定の0になる＝そのままだと
# 途中で落ちたスイートが「失敗0」に見える）。
static var completed_runs := 0

var fails := 0
var checks := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  ok   ", label)
	else:
		fails += 1
		print("  FAIL ", label, "  ", detail)


## スイートの最後に `return c.finish()`：集計を表示し、走り切ったことを記録して、失敗数を返す。
func finish() -> int:
	print("失敗数: ", fails, " / ", checks, "件")
	completed_runs += 1
	return fails
