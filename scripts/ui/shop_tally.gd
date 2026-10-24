extends RefCounted
class_name UiShopTally
## 市場の「この店で買ったもの」「¥24 使った」の、UIだけの集計（plan Q10）。
## 表示だけで、保存しない。帳簿には店のidが無いので、買うボタンを押して所持金が減った分をここで数える。
## ルートが1つ持ち、仕込み（PREP）に入るたびに clear() する。

var _entries: Dictionary = {}   # 店のid → [{ label, price }]


func clear() -> void:
	_entries = {}


func record(shop: String, label: String, price: int) -> void:
	if not _entries.has(shop):
		_entries[shop] = []
	(_entries[shop] as Array).append({ "label": label, "price": price })


func entries(shop: String) -> Array:
	return (_entries.get(shop, []) as Array).duplicate(true)


func spent(shop: String) -> int:
	var total := 0
	for entry in _entries.get(shop, []):
		total += int(entry["price"])
	return total


## 店で商品を買う。買えるとき（buy_item と同じ条件：所持金が価格以上）だけ、先に記録してから買う
## （buy_item が出す changed で描き直すときに、もう記録に入っているように）。
func buy(session: PlaySession, shop: String, good: Dictionary) -> void:
	if GameState.money >= int(good["price"]):
		record(shop, str(good["label"]), int(good["price"]))
	session.buy_item(shop, str(good["id"]))
