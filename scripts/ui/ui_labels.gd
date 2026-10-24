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


## 品目の短縮名（開店の操作エリアの具材ボタン・椀の枠・減点の予告だけで使う）。表に無ければ本名。
static func short_name(item_id: String) -> String:
	var names: Dictionary = _data().get("short_names", {})
	return str(names.get(item_id, Ingredients.name_for(item_id)))


## 品目の並び（開店の具材の一覧。品目の定義順＝短縮名の表の並び）。表に無い品目は後ろ。
static func item_order(item_id: String) -> int:
	var keys: Array = (_data().get("short_names", {}) as Dictionary).keys()
	var i := keys.find(item_id)
	return i if i >= 0 else keys.size()


## 店の扱う品（商品のラベルを「・」でつなぐ。小口の重複は除く）。
static func shop_wares(shop_id: String) -> String:
	var names: Array = []
	for good in PlaySession.shop_goods(shop_id):
		var item := str(good.get("item", ""))
		var label := Ingredients.name_for(item) if item != "" else str(good.get("label", ""))
		if not names.has(label):
			names.append(label)
	return "・".join(names)
