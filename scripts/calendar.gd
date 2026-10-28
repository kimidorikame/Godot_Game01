extends RefCounted
class_name Calendar
## ゲーム内の日付と時刻の表示（UI準備G0）。表示の形を1か所で作る（スマホのDM・ニュースが使う）。
## 今は「Day3」「Day3 05:40」の仮の形。のちにゲーム内の開始日をデータ（data/campaigns/week7.json の start_date など）で決めたら、
## label() だけを月日（例：「10/27」）を返すように差し替えれば、DM・ニュースの表示がすべて月日に変わる
## （日番号 day は 1 始まり。月日にするときは 開始日＋(day−1) 日）。呼び出し側は日の形式を知らない。


## 日の表示（仮：「Day3」）。
static func label(day: int) -> String:
	return "Day%d" % day


## 時刻の表示（2桁にそろえる：「5:40」→「05:40」）。形が違う文字列（「5時」など）はそのまま返す。
static func time_text(time: String) -> String:
	var parts := time.split(":")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return "%02d:%02d" % [int(parts[0]), int(parts[1])]
	return time


## 日付＋時刻の表示（仮：「Day3 05:40」）。
static func stamp(day: int, time: String) -> String:
	return "%s %s" % [label(day), time_text(time)]
