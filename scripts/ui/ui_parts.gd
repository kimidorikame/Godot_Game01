extends RefCounted
class_name UiParts
## 本番UIの右の枠で共通に使う小さな部品の書き込み（見出しの帯・予算の3つ）。
## 部品のノードは各シーン（pane_*.tscn）が持ち、ここは文字を入れるだけ。


## 見出しの帯：左に画面名、右に補足。
static func set_header(header: Control, title: String, sub: String = "") -> void:
	(header.get_node("Title") as Label).text = title
	(header.get_node("Sub") as Label).text = sub


## 予算の3つ（残金／確保／使える）。session.budget() の値を入れる。
static func set_budget(row: Control, budget: Dictionary) -> void:
	(row.get_node("Money/Value") as Label).text = "¥%d" % int(budget["money"])
	(row.get_node("Reserved/Value") as Label).text = "¥%d" % int(budget["reserved"])
	(row.get_node("Usable/Value") as Label).text = "¥%d" % int(budget["usable"])
