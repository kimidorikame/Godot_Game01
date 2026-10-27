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
##
## 来店予告（UI準備E）：その夜に来る予定の客・モブの種類を、朝のDMで知らせる。本当のことだけ（その夜の計画 today_plan にいる客・種類だけ）。
## 「寄る予定」の形で、来ると約束しない。数字と「客足」は本文に入れない。データは同じファイルの previews：
##   previews … { max_per_morning, mob_max, first_day, pools:{ <客id|モブの種類>:{ from, from_kind, time, texts[], tag_hint, provisional } } }
##   本文の {hint} は、tag_hint（その種類の好みの2つのうち1つ。モブだけ。名前あり客は ""）の言葉（data/tag_words.json）に置き換える。
## 選び方（乱数なし。日付で回す）：モブの種類を先に最大 mob_max 件→名前あり客で上限（max_per_morning）まで。モブが mob_max に満たない日は、空いた分を名前あり客で埋める。
##   ・モブ：その夜の計画の並び（重複なし）から (日番号＋件目) % 候補数。
##   ・名前あり客：今日より前に来たことがある客（好みが分かっている客）を先に、同じ条件の中では日付で回す。
##   ・同じ朝に届く既存DMの差出人（requires の客・モブ、同じ from）は候補から外す。
## 過去の日は、日次ログ（day_records）の planned_regulars・planned_mob_types から再現する（計画は翌朝に作り直されて残らないため）。
## 日次ログに無い日（旧セーブ）は、名前あり客は日程データから、モブは出さない。

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


## その日の朝に届いているDM（条件を満たしたもの。データの並び順。最後に来店予告）。
static func delivered_for_day(day: int, source: Dictionary = {}) -> Array:
	var out := []
	var center := center_of_day(day)
	for item in items_for_day(day, source):
		if requires_met(item.get("requires", {}), day) and hint_allows(str(item.get("hint", "none")), center, source):
			out.append(item)
	out.append_array(preview_items(day, out, source))
	return out


## 計画（today_plan）の名前あり客（枠の並び。重複なし）。
static func plan_regulars(plan: Dictionary) -> Array:
	var out := []
	for slot in plan.get("slots", []):
		var id := str((slot as Dictionary).get("regular_id", ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


## 計画（today_plan）のモブの種類（計画の並び。重複なし）。
static func plan_mob_types(plan: Dictionary) -> Array:
	var out := []
	var instances: Dictionary = plan.get("mob_instances", {})
	for key in instances:
		var type_id := str((instances[key] as Dictionary).get("type", ""))
		if type_id != "" and not out.has(type_id):
			out.append(type_id)
	return out


## その日の「予定だった」名前あり客・モブの種類。{ regulars:[], mobs:[], known:bool }。known＝モブの種類まで分かるか。
## 日次ログ（その日が終わっている）→今日の計画→日程データ（旧セーブの名前あり客だけ）の順に読む。
static func planned_for_day(day: int) -> Dictionary:
	for record in GameState.day_records:
		if record is Dictionary and int(record.get("day", -1)) == day and record.has("planned_regulars"):
			return { "regulars": (record["planned_regulars"] as Array).duplicate(), "mobs": (record.get("planned_mob_types", []) as Array).duplicate(), "known": true }
	if int(GameState.today_plan.get("day", -1)) == day:
		return { "regulars": plan_regulars(GameState.today_plan), "mobs": plan_mob_types(GameState.today_plan), "known": true }
	var regulars := []
	for entry in ScheduleData.regular_slots(day):
		var id := str((entry as Dictionary).get("regular", ""))
		if id != "" and not regulars.has(id):
			regulars.append(id)
	return { "regulars": regulars, "mobs": [], "known": false }


## 来店予告の設定（previews）。無ければ空辞書。
static func previews_config(source: Dictionary = {}) -> Dictionary:
	var d: Dictionary = source if not source.is_empty() else data()
	var p = d.get("previews", {})
	return p if p is Dictionary else {}


## 今日より前に来たことがある名前あり客か（好みが分かっている＝初来店の挨拶で知った）。
static func regular_known_before(customer_id: String, day: int) -> bool:
	for visit in CustomerMemory.visits_of(customer_id):
		if visit is Dictionary and int(visit.get("day", 9999)) < day:
			return true
	return false


## day を先頭にして一周回した並び（日付で回す。乱数なし）。
static func _rotated(list: Array, offset: int) -> Array:
	var out := []
	if list.is_empty():
		return out
	for i in range(list.size()):
		out.append(list[(offset + i) % list.size()])
	return out


## 予告1通の本文（同じ客・種類に複数の言い回しがあるときは、日番号と主語idで決める。乱数なし）。
static func preview_text(pool: Dictionary, subject: String, day: int) -> String:
	var texts: Array = pool.get("texts", [])
	if texts.is_empty():
		return ""
	var text := str(texts[absi(("%d|%s" % [day, subject]).hash()) % texts.size()])
	var hint := str(pool.get("tag_hint", ""))
	return text.replace("{hint}", TagWords.word(hint) if hint != "" else "")


## その日の朝の来店予告（上限・選び方は上の説明）。existing＝同じ朝に届く既存DM（同じ差出人を候補から外す）。
static func preview_items(day: int, existing: Array, source: Dictionary = {}) -> Array:
	var cfg := previews_config(source)
	if cfg.is_empty() or day < int(cfg.get("first_day", 2)):
		return []
	var pools: Dictionary = cfg.get("pools", {})
	var planned := planned_for_day(day)
	var blocked := {}   # 既存DMの主語（客・モブの種類）と差出人名
	for item in existing:
		var requires: Dictionary = item.get("requires", {})
		for key in ["customer", "mob_type"]:
			if requires.has(key):
				blocked[str(requires[key])] = true
		blocked["from:" + str(item.get("from", ""))] = true
	var mobs := []
	for type_id in planned["mobs"]:
		var pool: Dictionary = pools.get(str(type_id), {})
		if not pool.is_empty() and not blocked.has(str(type_id)) and not blocked.has("from:" + str(pool.get("from", ""))):
			mobs.append(str(type_id))
	var max_total := int(cfg.get("max_per_morning", 3))
	var mob_count := mini(mini(int(cfg.get("mob_max", 2)), mobs.size()), max_total)
	var known := []
	var unknown := []
	for id in planned["regulars"]:
		var pool: Dictionary = pools.get(str(id), {})
		if pool.is_empty() or blocked.has(str(id)) or blocked.has("from:" + str(pool.get("from", ""))):
			continue
		if regular_known_before(str(id), day):
			known.append(str(id))
		else:
			unknown.append(str(id))
	var picked_regulars := _rotated(known, day) + _rotated(unknown, day)
	var regular_count := mini(max_total - mob_count, picked_regulars.size())
	var subjects := []
	for i in range(mob_count):
		subjects.append([str(mobs[(day + i) % mobs.size()]), "mob"])
	for i in range(regular_count):
		subjects.append([str(picked_regulars[i]), "customer"])
	var out := []
	for pair in subjects:
		var pool: Dictionary = pools[pair[0]]
		out.append({ "id": "preview_d%d_%s" % [day, pair[0]], "from": str(pool.get("from", "")), "from_kind": str(pool.get("from_kind", pair[1])),
			"time": str(pool.get("time", "5:00")), "text": preview_text(pool, pair[0], day), "hint": "none",
			"provisional": bool(pool.get("provisional", true)), "preview": true, "subject": pair[0] })
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
	found.append_array(preview_problems(d))
	return found


## モブの種類の好み（data/mobs/<種類>.json の wanted_tags）。
static func mob_wanted_tags(type_id: String) -> Array:
	var path := "res://data/mobs/%s.json" % type_id
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return ((parsed as Dictionary).get("wanted_tags", []) as Array).duplicate() if parsed is Dictionary else []


## 来店予告（previews）の形の検査。previews が無いデータは問題なし（予告を出さない）。
static func preview_problems(d: Dictionary) -> Array:
	var found := []
	if not d.has("previews"):
		return found
	var cfg = d["previews"]
	if not (cfg is Dictionary):
		return ["previews が辞書でない"]
	for key in ["max_per_morning", "mob_max", "first_day"]:
		if not (cfg.get(key) is int or cfg.get(key) is float) or int(cfg[key]) < 0:
			found.append("previews.%s が0以上の整数でない" % key)
	var pools = cfg.get("pools", {})
	if not (pools is Dictionary):
		return found + ["previews.pools が辞書でない"]
	var digits := RegEx.new()
	digits.compile("[0-9０-９]")
	var expected := {}
	for path in DirAccess.get_files_at("res://data/customers/"):
		if path.ends_with(".json"):
			expected[path.get_basename()] = "customer"
	for path in DirAccess.get_files_at("res://data/mobs/"):
		if path.ends_with(".json"):
			expected[path.get_basename()] = "mob"
	for id in expected:
		if not (pools as Dictionary).has(id):
			found.append("previews.pools に %s（%s）が無い" % [id, expected[id]])
	for id in pools:
		var pool = pools[id]
		var where := "previews.pools.%s" % str(id)
		if not (pool is Dictionary):
			found.append(where + " が辞書でない")
			continue
		if not expected.has(str(id)):
			found.append(where + "：存在しない客・モブの種類")
			continue
		for key in ["from", "time"]:
			if not (pool.get(key) is String) or str(pool[key]) == "":
				found.append("%s に %s が無い" % [where, key])
		if str(pool.get("from_kind", "")) != expected[str(id)]:
			found.append(where + "：from_kind が " + expected[str(id)] + " でない")
		var hint := str(pool.get("tag_hint", ""))
		if expected[str(id)] == "customer" and hint != "":
			found.append(where + "：名前あり客に tag_hint がある（好みは初来店の挨拶で知る仕様）")
		if expected[str(id)] == "mob":
			var wanted: Array = mob_wanted_tags(str(id))
			if hint != "" and not wanted.has(hint):
				found.append("%s：tag_hint %s が、その種類の好み %s のどれでもない" % [where, hint, str(wanted)])
			if hint != "" and TagWords.kind(hint) == "":
				found.append(where + "：tag_hint の言葉が tag_words.json に無い")
		var texts = pool.get("texts", [])
		if not (texts is Array) or (texts as Array).is_empty():
			found.append(where + " の texts が空")
			continue
		for text in texts:
			if not (text is String) or str(text) == "":
				found.append(where + " の本文が空")
				continue
			if digits.search(str(text)) != null:
				found.append("%s：本文に数字がある「%s」" % [where, str(text)])
			if str(text).contains("客足"):
				found.append("%s：本文に「客足」がある「%s」" % [where, str(text)])
			if str(text).contains("{hint}") != (hint != ""):
				found.append("%s：{hint} と tag_hint の有無が合わない「%s」" % [where, str(text)])
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
