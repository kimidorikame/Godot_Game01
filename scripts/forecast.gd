extends RefCounted
class_name Forecast
## 朝の一画面・予報（3-7・DESIGN.md 10.4）の集計処理。状態は持たない静的クラスで、
## GameState.today_plan（WAKEでDayPlanner.build()が確定した計画）と
## GameState.inventory（今の在庫）から計算するだけ。表示文字列の組み立て
## （_format_tonight_memo）はDebugPanel側に残し、ここは数値・辞書を返す。
##
## 予報の精度（DESIGN.md 10.4）：
##   exact（Day1）  … 実際の計画から完全公開（配達員の3杯の内訳も）。
##   range（Day2〜）… 常連は基本注文（その日のcustomer_data）、モブは種類の一覧
##                    （重複除去・人数や組数は出さない）、総杯数は需要の中心±幅。
##                    「今日の頼み」はまだデータが無く、会話で判明するので出さない。
## 必要数の集計は、客ごとのcustomer_events()のREACT（servings・wanted_tags）を走査する
## （Day1Events._customer_total_servings()と同じ流儀。配達員Day1の3杯目の
## wanted_tagsなどを別の定数に重複させずに済む）。

## 表示順（味の軸→具の軸。Ingredients.gdのコメントの並び）。
const TAG_ORDER := ["HOT", "MELLOW", "SOUR", "BITTER", "SAVORY",
	"POWER", "GENTLE", "FILLING", "BITE", "TREAT"]


## "exact"（Day1。day_overridesのforecastが"exact"）か"range"（それ以外）。
static func mode() -> String:
	if str(Rules.day_overrides(GameState.day_count).get("forecast", "")) == "exact":
		return "exact"
	return str(Rules.forecast().get("total", "range"))


static func _slots() -> Array:
	return GameState.today_plan.get("slots", [])


## 客1人（1組）の注文を[{tags, servings}]で返す（customer_events()のREACTを走査）。
## 配達員のDay1は3件（本人2杯＋持ち帰り1杯）になる。
static func orders_of(customer_id: String) -> Array:
	var orders := []
	for ev in Day1Events.customer_events(customer_id):
		if str(ev.get("type", "")) == "REACT":
			orders.append({ "tags": (ev.get("wanted_tags", []) as Array).duplicate(),
				"servings": int(ev.get("servings", 1)) })
	return orders


static func _mob_type_of(customer_id: String) -> String:
	var inst: Dictionary = GameState.today_plan.get("mob_instances", {}).get(customer_id, {})
	return str(inst.get("type", ""))


## 今夜のplanに出るモブの種類id（重複除去・planの並び順）。
static func mob_types() -> Array:
	var types := []
	for slot in _slots():
		for cid in slot.get("customers", []):
			var t := _mob_type_of(str(cid))
			if t != "" and not types.has(t):
				types.append(t)
	return types


## その枠に出るモブの種類id（重複除去）。
static func mob_types_in_slot(slot: Dictionary) -> Array:
	var types := []
	for cid in slot.get("customers", []):
		var t := _mob_type_of(str(cid))
		if t != "" and not types.has(t):
			types.append(t)
	return types


## 名前あり客（モブ以外）の合計杯数。
static func regular_cups() -> int:
	var total := 0
	for slot in _slots():
		for cid in slot.get("customers", []):
			if _mob_type_of(str(cid)) != "":
				continue
			for order in orders_of(str(cid)):
				total += int(order["servings"])
	return total


## 実際のplanの総杯数（名前あり客＋モブ）。exact日の「確定の総杯数」。
static func actual_cups() -> int:
	var total := 0
	for slot in _slots():
		for cid in slot.get("customers", []):
			for order in orders_of(str(cid)):
				total += int(order["servings"])
	return total


## 総杯数の表示用 {exact: bool, low: int, high: int}。rangeは実際に引いた値ではなく
## today_plan["demand_center"]（WAKEで保存した中心）±range_widthを基準にする。
static func total() -> Dictionary:
	if mode() == "exact":
		var n := actual_cups()
		return { "exact": true, "low": n, "high": n }
	var center: int = int(GameState.today_plan.get("demand_center", -1))
	if center < 0:
		center = GameState.demand_center_today()
	var width: int = int(Rules.forecast().get("range_width", 1))
	return { "exact": false, "low": center - width, "high": center + width }


static func _add_tags(into: Dictionary, tags: Array, count: int) -> void:
	for tag in tags:
		into[str(tag)] = int(into.get(str(tag), 0)) + count


## 実際のplanから出したタグ別必要数（exact日用。モブも実際の人数ぶん）。
static func required_exact() -> Dictionary:
	var req := {}
	for slot in _slots():
		for cid in slot.get("customers", []):
			for order in orders_of(str(cid)):
				_add_tags(req, order["tags"], int(order["servings"]))
	return req


## 範囲日の推定：名前あり客は基本注文から正確に、モブは「mob_cups杯をplanに出る
## 種類へ均等に割り振る」推定で出す（実際の組の人数配分は使わない＝人数・組数が漏れ
## ない。DESIGN.md 10.4）。
static func required_estimated(mob_cups: int) -> Dictionary:
	var req := {}
	for slot in _slots():
		for cid in slot.get("customers", []):
			if _mob_type_of(str(cid)) != "":
				continue
			for order in orders_of(str(cid)):
				_add_tags(req, order["tags"], int(order["servings"]))
	var types := mob_types()
	if types.is_empty() or mob_cups <= 0:
		return req
	var base: int = mob_cups / types.size()
	var extra: int = mob_cups % types.size()
	for i in range(types.size()):
		var cups: int = base + (1 if i < extra else 0)
		var tags: Array = ScheduleData.mob_data(str(types[i])).get("wanted_tags", [])
		_add_tags(req, tags, cups)
	return req


## 予報の案。exact日は[確定]の1案、range日は[平均案（中心）, 上限案（中心+幅）]の2案。
## 各案 {label, required}。
static func cases() -> Array:
	if mode() == "exact":
		return [{ "label": "確定", "required": required_exact() }]
	var t := total()
	var center: int = (int(t["low"]) + int(t["high"])) / 2
	var reg := regular_cups()
	return [
		{ "label": "平均案", "required": required_estimated(maxi(center - reg, 0)) },
		{ "label": "上限案", "required": required_estimated(maxi(int(t["high"]) - reg, 0)) },
	]


## 今の在庫のタグ別個数（Ingredients.tags_for()でタグ換算。傷み・鮮度は区別せず
## 1個＝1個と数える目安。複数タグを持つ品目は各タグに1個ずつ数える）。
static func supply_tags() -> Dictionary:
	var supply := {}
	for item in GameState.inventory:
		_add_tags(supply, Ingredients.tags_for(str(item)), int(GameState.inventory[item]))
	return supply


## 必要数に対する不足のタグだけ {tag: あと◯個} で返す（タグ単位の個数比較。
## 1杯の注文が味＋具の組み合わせでできる点までは見ない目安）。
static func shortages(required: Dictionary) -> Dictionary:
	var supply := supply_tags()
	var short := {}
	for tag in required:
		var lack: int = int(required[tag]) - int(supply.get(tag, 0))
		if lack > 0:
			short[tag] = lack
	return short


## {tag: n} を表示順で「HOT4 POWER4」のように並べる（0のタグは出さない）。
static func format_tags(tag_counts: Dictionary) -> String:
	var parts := PackedStringArray()
	for tag in TAG_ORDER:
		var n: int = int(tag_counts.get(tag, 0))
		if n > 0:
			parts.append("%s%d" % [tag, n])
	return " ".join(parts)
