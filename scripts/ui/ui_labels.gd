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


## 客足の言葉（評判の横）。区切りは需要表（Rules.demand_table()＝[閾値, 中心] を閾値の降順に並べた行）から読み、
## 行の並びと言葉（demand_words。表と同じ並び＝多い順）を対応させる。日の固定需要・その日の事情は反映しない。
static func demand_word(reputation: int) -> String:
	var words: Array = _data().get("demand_words", [])
	var table: Array = Rules.demand_table()
	for i in range(table.size()):
		if reputation >= int((table[i] as Array)[0]):
			return str(words[i]) if i < words.size() else ""
	return str(words[table.size() - 1]) if table.size() - 1 < words.size() and not words.is_empty() else ""


## 客足の言葉（demand_words の1つ）に当たる需要表の行の「中心」（需要の中心の値）。DMの匂わせの条件に使う
## （「多い」＝多めの行の中心以上、「少ない」＝少ないの行の中心以下。数値はコードに直書きせず、需要表から読む）。
## 言葉が無い・表の行より言葉が多いときは -1。
static func demand_row_center(word: String) -> int:
	var words: Array = _data().get("demand_words", [])
	var table: Array = Rules.demand_table()
	var i := words.find(word)
	if i < 0 or i >= table.size():
		return -1
	return int((table[i] as Array)[1])


## 客足の言葉の数が需要表の行数と合っているか（データの検査用）。
static func demand_words_match_table() -> bool:
	return (_data().get("demand_words", []) as Array).size() == Rules.demand_table().size()


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
