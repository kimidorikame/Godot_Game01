extends RefCounted
class_name UiParts
## 本番UIの右の枠で共通に使う小さな部品の書き込み（見出しの帯・予算の3つ）。
## 部品のノードは各シーン（pane_*.tscn）が持ち、ここは文字を入れるだけ。


## 見出しの帯：左に画面名、右に補足。
static func set_header(header: Control, title: String, sub: String = "") -> void:
	(header.get_node("Title") as Label).text = title
	(header.get_node("Sub") as Label).text = sub


## 足りなかった杯数の1行：「足りなかった 4杯（素材 1・鍋 2・断った 1）」。内訳は0でないものだけ。内訳が無い
## （古い記録）か合計が0なら合計だけ。display は PlaySession.unserved_display() の結果。
## 「鍋」には、閉店のあと来られなかった客の分を含める（unserved_display）。
static func unserved_text(total: int, display: Dictionary) -> String:
	var text := "足りなかった %d杯" % total
	if total <= 0 or display.is_empty():
		return text
	var parts: Array = []
	for pair in [["ingredients", "素材"], ["pot", "鍋"], ["declined", "断った"]]:
		if int(display.get(pair[0], 0)) > 0:
			parts.append("%s %d" % [pair[1], int(display[pair[0]])])
	return text if parts.is_empty() else "%s（%s）" % [text, "・".join(parts)]


## 予算の3つ（残金／確保＝支払い予定／使える）。session.budget() の値を入れる。pending は、かごなど取り置いている額
## （「使える」から引いて見せる。残金・確保はそのまま。UI準備D）。
static func set_budget(row: Control, budget: Dictionary, pending: int = 0) -> void:
	(row.get_node("Money/Value") as Label).text = "¥%d" % int(budget["money"])
	(row.get_node("Reserved/Value") as Label).text = "¥%d" % int(budget["reserved"])
	(row.get_node("Usable/Value") as Label).text = "¥%d" % (int(budget["usable"]) - pending)


## 使える現金を超えて、かごに入れられない商品があるときの理由の一文（無ければ ""）。remaining はかごの分を引いた「使える」、
## reserved は支払い予定（確保）。商品は shop_view() の形（price を持つ）。
static func limit_reason(goods: Array, remaining: int, reserved: int) -> String:
	var blocked := false
	for good in goods:
		if int(good["price"]) > remaining:
			blocked = true
	if not blocked:
		return ""
	var note := "（支払い予定 ¥%d を除く）" % reserved if reserved > 0 else ""
	return "使える現金は残り ¥%d%s。これを超える商品は、かごに入れられません" % [maxi(remaining, 0), note]
