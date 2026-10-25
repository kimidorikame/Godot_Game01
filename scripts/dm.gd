extends RefCounted
class_name Dm
## 常連などからのDM（SNSタブ。UI準備C③。DESIGN.md 10.4）。静的クラスで状態は持たない（読むだけ・乱数なし）。
## データは data/dm/<id>.json（idは Rules.dm()＝week7.json の "dm"。ニュースと同じ置き方）。
##
## データ形：
##   hints … { many:{ demand_word }, few:{ demand_word } }  匂わせの向きと、条件に使う客足の言葉
##   days.<日> … [ { id, from, from_kind:"customer|mob|npc", requires, time, text, hint:"many|few|none", provisional } ]
##   requires … { customer:<客id> }（その客に初めて提供した翌日から）／{ mob_type:<種類>, nights:<夜数> }（同じ種類のモブに
##              nights 夜提供した翌日から）／無し（市場の顔なじみなど客でない差出人。条件なし）
##
## DMが「その日に届くか」は、その日の朝の時点の状態で決まる関数（保存する状態を増やさない）：
##   ・requires を満たす（名前あり客は customer_memory の来店記録、モブは日次ログの mob_types_served から数える）。
##   ・hint の向きが、その日の需要の中心と矛盾しない（many＝中心が「多め」の行の中心以上／few＝「少ない」の行の中心以下。
##     数値は需要表と ui_labels.json の客足の言葉から読む。直書きしない）。
## 条件が後から満たされても、過去の日のDMは届かない（その日の朝の状態で決まるため）。
## DMには必須情報（must_info）を置かない（10.5.5。必須はニュースと共通イベントだけ）。

static var data_dir := "res://data/dm/"
static var _cache: Dictionary = {}
static var _loaded_id := ""

const KINDS := ["customer", "mob", "npc"]
const HINTS := ["many", "few", "none"]


static func clear_cache() -> void:
	_cache = {}
	_loaded_id = ""


## 今のキャンペーンのDMのデータ全体。無い・読めないときは空辞書。
static func data() -> Dictionary:
	var id := Rules.dm()
	if _loaded_id != id or _cache.is_empty():
		_cache = {}
		var path := data_dir + id + ".json"
		if id != "" and FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_cache = parsed
		_loaded_id = id
	return _cache


## その日のDMの候補（条件を見ない。形の整ったものだけ）。
static func items_for_day(day: int, source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var days = d.get("days", {})
	var out := []
	if days is Dictionary and (days as Dictionary).get(str(day)) is Array:
		for item in days[str(day)]:
			if item is Dictionary:
				out.append((item as Dictionary).duplicate(true))
	return out


## 匂わせの向きと需要の中心が矛盾しないか。none は常に可。many＝中心が「多め」の行の中心以上、few＝「少ない」の行の中心以下。
## center が -1（その日の中心が分からない）なら many・few は不可。
static func hint_allows(hint: String, center: int, source: Dictionary = {}) -> bool:
	if hint == "none" or hint == "":
		return true
	if center < 0:
		return false
	var d: Dictionary = source if not source.is_empty() else data()
	var word := str(((d.get("hints", {}) as Dictionary).get(hint, {}) as Dictionary).get("demand_word", ""))
	var edge := UiLabels.demand_row_center(word)
	if edge < 0:
		return false
	return center >= edge if hint == "many" else center <= edge


## その日の需要の中心。固定需要の日（Day1）はその値、今日は朝に確定した today_plan の中心、過ぎた日は日次ログの
## その朝の評判から需要表で引く。分からなければ -1。
static func center_of_day(day: int) -> int:
	var overrides := Rules.day_overrides(day)
	if overrides.has("fixed_demand"):
		return int(overrides["fixed_demand"])
	if day == GameState.day_count:
		if int(GameState.today_plan.get("day", -1)) == day and int(GameState.today_plan.get("demand_center", -1)) >= 0:
			return int(GameState.today_plan["demand_center"])
		return GameState.demand_center_today()
	for record in GameState.day_records:
		if record is Dictionary and int(record.get("day", -1)) == day and record.has("opening_reputation"):
			return _center_for_reputation(int(record["opening_reputation"]))
	return -1


static func _center_for_reputation(reputation: int) -> int:
	var table: Array = Rules.demand_table()
	for row in table:
		if reputation >= int((row as Array)[0]):
			return int((row as Array)[1])
	return int((table.back() as Array)[1]) if not table.is_empty() else -1


## 名前あり客に初めて提供した日（来店記録で served>0 の最初の日）。まだなら 9999。
static func first_served_day(customer_id: String) -> int:
	var first := 9999
	var memory: Dictionary = GameState.customer_memory.get(customer_id, {})
	for visit in memory.get("visits", []):
		if visit is Dictionary and int(visit.get("served", 0)) > 0:
			first = mini(first, int(visit.get("day", 9999)))
	return first


## day より前の夜に、その種類のモブへ提供した夜の数（日次ログの mob_types_served から数える）。
static func mob_nights_before(mob_type: String, day: int) -> int:
	var nights := 0
	for record in GameState.day_records:
		if record is Dictionary and int(record.get("day", 0)) < day and (record.get("mob_types_served", []) as Array).has(mob_type):
			nights += 1
	return nights


## requires を day の朝に満たしているか。
static func requires_met(requires: Dictionary, day: int) -> bool:
	if requires.is_empty():
		return true
	if requires.has("customer"):
		return first_served_day(str(requires["customer"])) < day
	if requires.has("mob_type"):
		return mob_nights_before(str(requires["mob_type"]), day) >= int(requires.get("nights", 1))
	return false


## その日の朝に届いているDM（条件を満たしたもの。データの並び順）。
static func delivered_for_day(day: int, source: Dictionary = {}) -> Array:
	var out := []
	var center := center_of_day(day)
	for item in items_for_day(day, source):
		if requires_met(item.get("requires", {}), day) and hint_allows(str(item.get("hint", "none")), center, source):
			out.append(item)
	return out


## 今日までに届いたDM（新しい日が上。同じ日は時刻の遅い方が上）。[{ id, day, from, from_kind, time, text, hint, provisional }]
static func inbox(today: int, source: Dictionary = {}) -> Array:
	var out := []
	for day in range(1, today + 1):
		for item in delivered_for_day(day, source):
			item["day"] = day
			out.append(item)
	out.sort_custom(func(a, b):
		if int(a["day"]) != int(b["day"]):
			return int(a["day"]) > int(b["day"])
		return str(a.get("time", "")) > str(b.get("time", "")))
	return out


## DMのデータ全体の形の検査（データのテストが使う）。問題の説明の配列（空なら問題なし）。
static func problems(source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var found := []
	if d.is_empty():
		return ["DMのデータが読めない"]
	var hints = d.get("hints", {})
	for key in ["many", "few"]:
		if not (hints is Dictionary) or not ((hints as Dictionary).get(key) is Dictionary):
			found.append("hints.%s が無い" % key)
		elif UiLabels.demand_row_center(str(((hints as Dictionary)[key] as Dictionary).get("demand_word", ""))) < 0:
			found.append("hints.%s の demand_word が客足の言葉に無い" % key)
	var days = d.get("days", {})
	if not (days is Dictionary):
		return found + ["days が辞書でない"]
	var seen := {}
	for day_key in days:
		var day := int(str(day_key)) if str(day_key).is_valid_int() else -1
		if day < 1 or day > Rules.final_day():
			found.append("days のキー %s が日（1〜最終日）でない" % str(day_key))
			continue
		if not (days[day_key] is Array):
			found.append("Day%d が配列でない" % day)
			continue
		for item in days[day_key]:
			if not (item is Dictionary):
				found.append("Day%d のDMの要素が辞書でない" % day)
				continue
			var id := str(item.get("id", ""))
			if id == "" or seen.has(id):
				found.append("Day%d のDMの id %s が空か重複" % [day, id])
			seen[id] = true
			for key in ["from", "text", "time"]:
				if not (item.get(key) is String) or str(item[key]) == "":
					found.append("Day%d %s に %s が無い" % [day, id, key])
			if not KINDS.has(str(item.get("from_kind", ""))):
				found.append("Day%d %s の from_kind が customer／mob／npc でない" % [day, id])
			if not HINTS.has(str(item.get("hint", ""))):
				found.append("Day%d %s の hint が many／few／none でない" % [day, id])
			if item.has("must_info"):
				found.append("Day%d %s に must_info がある（必須情報はDMに置かない。10.5.5）" % [day, id])
			found.append_array(_requires_problems(item, day))
	return found


static func _requires_problems(item: Dictionary, day: int) -> Array:
	var found := []
	var kind := str(item.get("from_kind", ""))
	var requires = item.get("requires", {})
	var where := "Day%d %s" % [day, str(item.get("id", ""))]
	if not (requires is Dictionary):
		return [where + " の requires が辞書でない"]
	var r: Dictionary = requires
	if kind == "npc" and not r.is_empty():
		found.append(where + "：客でない差出人（npc）に requires がある（条件なしで届く）")
	if kind == "customer":
		if not r.has("customer") or not FileAccess.file_exists("res://data/customers/%s.json" % str(r["customer"])):
			found.append(where + "：customer の requires に、存在する客のidが無い")
	if kind == "mob":
		if not r.has("mob_type") or not FileAccess.file_exists("res://data/mobs/%s.json" % str(r["mob_type"])):
			found.append(where + "：mob の requires に、存在するモブの種類が無い")
		elif not (r.get("nights") is int or r.get("nights") is float) or int(r["nights"]) < 1:
			found.append(where + "：mob の requires に nights（1以上）が無い")
	return found
