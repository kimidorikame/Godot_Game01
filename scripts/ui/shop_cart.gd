extends RefCounted
class_name UiShopCart
## 市場の「かご」（UI準備D・D-2）。商品の「かごに入れる」を1回押すと1セット（その商品の1回分）が入る。
## 「購入確定」まで何も買わない（所持金・在庫・帳簿は動かない）。UIだけの状態で、保存しない。
## 店ごとに持ち、買う順番は入れた順（束の並び＝使う順が、1つずつ買ったときと同じになる）。
## 張記の鍋の素（小・中・大）は、選ぶだけ（selected_tier）で、「購入確定」で買う。ルートが1つ持ち、仕込み（PREP）に入るたびに clear_all() する。

var _lines: Dictionary = {}   # 店のid → [{ id, label, price }]（入れた順）
## 選んだ鍋の素の段階id（""＝選んでいない）。まだ買っていない。
var selected_tier := ""
var selected_tier_price := 0


func clear_all() -> void:
	_lines = {}
	selected_tier = ""
	selected_tier_price = 0


func clear(shop: String) -> void:
	_lines.erase(shop)


func add(shop: String, good: Dictionary) -> void:
	if not _lines.has(shop):
		_lines[shop] = []
	(_lines[shop] as Array).append({ "id": str(good["id"]), "label": str(good["label"]), "price": int(good["price"]) })


## 1つ戻す（最後に入れたもの）。
func remove_last(shop: String) -> void:
	var lines: Array = _lines.get(shop, [])
	if not lines.is_empty():
		lines.pop_back()


func count(shop: String) -> int:
	return (_lines.get(shop, []) as Array).size()


func total(shop: String) -> int:
	var sum := 0
	for line in _lines.get(shop, []):
		sum += int(line["price"])
	return sum


## 入れた順の1行ずつ（購入確定でこの順に買う）。
func lines(shop: String) -> Array:
	return (_lines.get(shop, []) as Array).duplicate(true)


## 同じ商品をまとめた表示用：[{ id, label, qty, price }]（price は合計。最初に入れた順）。
func grouped(shop: String) -> Array:
	var out: Array = []
	for line in _lines.get(shop, []):
		var found := false
		for entry in out:
			if str(entry["id"]) == str(line["id"]):
				entry["qty"] = int(entry["qty"]) + 1
				entry["price"] = int(entry["price"]) + int(line["price"])
				found = true
				break
		if not found:
			out.append({ "id": str(line["id"]), "label": str(line["label"]), "qty": 1, "price": int(line["price"]) })
	return out


## 買う分を取り出して、かごを空にする（買うループの前に呼ぶ。描き直しで二重に数えないため）。
func take(shop: String) -> Array:
	var taken := lines(shop)
	clear(shop)
	return taken


## 取り置いている額の合計（店のかご＋選んだ鍋の素）。「使える」から引いて見せる。
func pending(shop: String) -> int:
	return total(shop) + selected_tier_price


func select_tier(tier_id: String, price: int) -> void:
	if selected_tier == tier_id:
		selected_tier = ""
		selected_tier_price = 0
	else:
		selected_tier = tier_id
		selected_tier_price = price


func clear_tier() -> void:
	selected_tier = ""
	selected_tier_price = 0
