extends RefCounted
class_name UiLabels
## 本番UIの表示だけの名前（data/ui/ui_labels.json）。ゲームの判定・保存には使わない。

const PATH := "res://data/ui/ui_labels.json"

static var _cache: Dictionary = {}


static func _data() -> Dictionary:
	if _cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cache = parsed if parsed is Dictionary else { "shops": {} }
	return _cache


## 店のid → 店名（張記肉類加工など）。表に無ければ fallback（market_stalls() の短いラベル）。
static func shop_name(shop_id: String, fallback: String = "") -> String:
	return str((_data().get("shops", {}) as Dictionary).get(shop_id, fallback))


## 店の扱う品（商品のラベルを「・」でつなぐ。小口の重複は除く）。
static func shop_wares(shop_id: String) -> String:
	var names: Array = []
	for good in PlaySession.shop_goods(shop_id):
		var item := str(good.get("item", ""))
		var label := Ingredients.name_for(item) if item != "" else str(good.get("label", ""))
		if not names.has(label):
			names.append(label)
	return "・".join(names)
