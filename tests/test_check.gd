extends RefCounted
class_name TestCheck
## 各テストスイート共通のチェック・集計ヘルパー（headlessテストの使い捨てスクリプトで
## 毎回コピペしていたものを1箇所に集約）。使い方は各スイートの run() を参照。

var fails := 0
var checks := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  ok   ", label)
	else:
		fails += 1
		print("  FAIL ", label, "  ", detail)
