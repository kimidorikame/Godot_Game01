extends RefCounted
class_name News
## 日別ニュース・DM・共通イベントと、本筋の必須情報（9項目）のカタログ（システム整理D。
## DESIGN.md 10.5.5・10.10の4-6。SEVEN_DAY_OUTLINE.md §11）。データは data/news/<id>.json
## （idは Rules.news()＝week7.json の "news"）。静的クラスで状態は持たない（読むだけ・乱数なし）。
##
## 必須情報は「客の会話に頼らず」届く：担保の根拠は、朝のニュースと共通イベントだけ。場面データの
## must_info は補強（印）で、ここのカタログに無い id は弾く。日番号はデータが指す（コードには書かない。
## Rules.day_overrides・bills[].days と同じ流儀）。文面は仮案で、各項目の "provisional": true を
## 外して差し替えるだけでよい。
##
## データ形：
##   must_info … [{ id, day, label }, …]  カタログ（9項目。dayは届く日）
##   days.<日> … { news:[{ id, headline, body[], must_info[], provisional }],
##                 dm:[{ from, text, provisional }],
##                 events:[{ id, at, lines[], must_info[], provisional }] }
##   at … "wake"（朝のニュースの後）／時間帯名（その時間帯の最初の客の前）／"close"（閉店の語りの前）

static var data_dir := "res://data/news/"
static var _cache: Dictionary = {}
static var _loaded_id := ""


## 読み込み結果を捨てる（テストが data_dir やキャンペーンを切り替えた後に呼ぶ）。
static func clear_cache() -> void:
	_cache = {}
	_loaded_id = ""


## 今のキャンペーンのニュースのデータ全体。無い・読めないときは空辞書。
static func data() -> Dictionary:
	var id := Rules.news()
	if _loaded_id != id or _cache.is_empty():
		_cache = {}
		var path := data_dir + id + ".json"
		if id != "" and FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_cache = parsed
		_loaded_id = id
	return _cache


## 必須情報のカタログ [{ id, day, label }]。形の整ったものだけ。無ければ空配列。
static func catalog(source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var result := []
	var raw = d.get("must_info", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary and (item as Dictionary).get("id") is String \
					and str(item["id"]) != "" and _is_whole_number((item as Dictionary).get("day")):
				result.append({ "id": str(item["id"]), "day": int(item["day"]), "label": str(item.get("label", "")) })
	return result


## その日のニュース・DM・共通イベント。{ news: [], dm: [], events: [] }（無い日・形が不正は空）。
static func day_entry(day: int, source: Dictionary = {}) -> Dictionary:
	var d: Dictionary = source if not source.is_empty() else data()
	var days = d.get("days", {})
	var entry := { "news": [], "dm": [], "events": [] }
	if days is Dictionary and (days as Dictionary).get(str(day)) is Dictionary:
		for key in entry:
			var raw = (days[str(day)] as Dictionary).get(key, [])
			if raw is Array:
				for item in raw:
					if item is Dictionary:
						entry[key].append((item as Dictionary).duplicate(true))
	return entry


## 必須情報の id → それが現れる（ニュースの must_info／共通イベントの must_info）日の配列。
## 客の場面（episode.must_info）は数えない：担保の根拠は客に依存しないニュースと共通イベントだけ。
static func delivered_days(source: Dictionary = {}) -> Dictionary:
	var d: Dictionary = source if not source.is_empty() else data()
	var result := {}
	var days = d.get("days", {})
	if not (days is Dictionary):
		return result
	for day_key in days:
		if not (days[day_key] is Dictionary):
			continue
		for kind in ["news", "events"]:
			var items = (days[day_key] as Dictionary).get(kind, [])
			if not (items is Array):
				continue
			for item in items:
				if item is Dictionary and (item as Dictionary).get("must_info") is Array:
					for id in item["must_info"]:
						if id is String:
							if not result.has(id):
								result[id] = []
							if not (result[id] as Array).has(int(str(day_key))):
								(result[id] as Array).append(int(str(day_key)))
	return result


## 場面データの must_info の id が、カタログに無ければ問題として返す（未知の識別子を弾く）。
## 場面の形そのものの検査は ScheduleData.scene_problems()。
static func scene_problems(ep: Dictionary, source: Dictionary = {}) -> Array:
	var problems := []
	var known := {}
	for entry in catalog(source):
		known[entry["id"]] = true
	var ids = ep.get("must_info", [])
	if ids is Array:
		for id in ids:
			if not (id is String) or not known.has(id):
				problems.append("場面の must_info %s が必須情報のカタログに無い" % str(id))
	return problems


## 朝（WAKE）に必ず差す、その日のニュースとDMの TEXT イベント（part:"news"）。見出し→本文の順、続けて
## DM。ニュースもDMも無い日は空配列＝従来の起床の列と同一。状態を読むだけ（日番号からデータを引く）。
## 表示だけで、ゲームの数値には触れない。
static func morning_events(day: int, source: Dictionary = {}) -> Array:
	var events := []
	var entry := day_entry(day, source)
	for item in entry["news"]:
		if str(item.get("headline", "")) != "":
			events.append({ "type": "TEXT", "text": "ニュース：%s" % str(item["headline"]), "part": "news" })
		if item.get("body") is Array:
			for line in item["body"]:
				if line is String and line != "":
					events.append({ "type": "TEXT", "text": line, "part": "news" })
	for item in entry["dm"]:
		if str(item.get("text", "")) != "":
			events.append({ "type": "TEXT", "text": "DM（%s）：%s" % [str(item.get("from", "")), str(item["text"])],
				"part": "news" })
	return events


## --- 共通イベント（客の抽選に依存しない、その日の出来事）。TEXTだけで、ゲームの数値には触れない ---

## 共通イベント1件の TEXT イベント（part:"common_event"・event_id付き）。
static func event_lines(item: Dictionary) -> Array:
	var events := []
	if item.get("lines") is Array:
		for line in item["lines"]:
			if line is String and line != "":
				events.append({ "type": "TEXT", "text": line, "part": "common_event", "event_id": str(item.get("id", "")) })
	return events


## その日の共通イベントのうち、まだ再生していないもの（played_ids に無いもの）を、データの並び順
## （＝時系列）で返す。at を指定すれば、その at のものだけ。
static func pending_events(day: int, played_ids: Array, at: String = "", source: Dictionary = {}) -> Array:
	var items := []
	for item in day_entry(day, source)["events"]:
		if played_ids.has(str(item.get("id", ""))):
			continue
		if at != "" and str(item.get("at", "")) != at:
			continue
		items.append(item)
	return items


## 共通イベントの id → その日の項目（無ければ空辞書）。
static func event_by_id(day: int, id: String, source: Dictionary = {}) -> Dictionary:
	for item in day_entry(day, source)["events"]:
		if str(item.get("id", "")) == id:
			return item
	return {}


## ニュースタブ（スマホ）の本文（仮表示）。今日と、その周で既に過ぎた日の分だけ（未来の日は見せない）。
## 新しい日が上。ニュースとDMは別の見出し。過ぎた日の共通イベントは出来事として載せ、今日の分は
## 再生済み（played_ids）のものだけ。既読は持たない（保存する状態を増やさない）。
static func tab_text(today: int, played_ids: Array = [], source: Dictionary = {}) -> String:
	var lines := PackedStringArray()
	for day in range(today, 0, -1):
		var entry := day_entry(day, source)
		var section := PackedStringArray()
		for item in entry["news"]:
			section.append("・%s%s" % [_provisional_mark(item), str(item.get("headline", ""))])
			if item.get("body") is Array:
				for line in item["body"]:
					section.append("　%s" % str(line))
		for item in entry["dm"]:
			section.append("DM（%s）：%s%s" % [str(item.get("from", "")), _provisional_mark(item), str(item.get("text", ""))])
		for item in entry["events"]:
			if day < today or played_ids.has(str(item.get("id", ""))):
				if item.get("lines") is Array:
					for line in item["lines"]:
						section.append("出来事：%s%s" % [_provisional_mark(item), str(line)])
		if not section.is_empty():
			lines.append("◆%s◆" % ("今日（Day%d）" % day if day == today else "Day%d" % day))
			lines.append_array(section)
	if lines.is_empty():
		return "ニュース：まだ届いていません"
	return "\n".join(lines)


static func _provisional_mark(item) -> String:
	return "【仮】" if item is Dictionary and bool(item.get("provisional", false)) else ""


static func _is_whole_number(value) -> bool:
	return value is int or (value is float and float(value) == floorf(float(value)))


static func _is_line_list(value, allow_empty: bool) -> bool:
	if not (value is Array):
		return false
	if (value as Array).is_empty():
		return allow_empty
	for line in value:
		if not (line is String) or line == "":
			return false
	return true


## 共通イベントの at に使える値："wake"・"close"・日程にある時間帯名。
static func allowed_at() -> Array:
	var allowed := ["wake", "close"]
	for day in range(1, Rules.final_day() + 1):
		for slot in ScheduleData.regular_slots(day):
			var name := str(slot.get("slot", ""))
			if name != "" and not allowed.has(name):
				allowed.append(name)
	return allowed


## ニュースのデータ全体の形と、必須情報の担保の検査（データ検証テストが使う）。問題の説明の
## 配列を返す（空なら問題なし）。担保：カタログの全 id が、ニュースまたは共通イベントに現れ、
## 現れる日がカタログの day と一致する（客・モブ・評判に依存する経路を根拠にしない）。
static func problems(source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var found := []
	if d.is_empty():
		return ["ニュースのデータが読めない"]
	# カタログ
	var known := {}
	var raw_catalog = d.get("must_info", [])
	if not (raw_catalog is Array) or (raw_catalog as Array).is_empty():
		found.append("must_info（カタログ）が無い")
	else:
		for item in raw_catalog:
			if not (item is Dictionary) or not ((item as Dictionary).get("id") is String) \
					or str(item["id"]) == "" or not _is_whole_number((item as Dictionary).get("day")) \
					or int(item["day"]) < 1 or int(item["day"]) > Rules.final_day():
				found.append("カタログの要素に id / day（1〜最終日）が無い")
				continue
			if known.has(str(item["id"])):
				found.append("カタログの id %s が重複" % str(item["id"]))
			known[str(item["id"])] = int(item["day"])
	# 日ごと
	var days = d.get("days", {})
	if not (days is Dictionary):
		return found + ["days が辞書でない"]
	var allowed := allowed_at()
	var seen_ids := {}
	for day_key in days:
		var day := int(str(day_key)) if str(day_key).is_valid_int() else -1
		if day < 1 or day > Rules.final_day():
			found.append("days のキー %s が日（1〜最終日）でない" % str(day_key))
			continue
		var entry = days[day_key]
		if not (entry is Dictionary):
			found.append("Day%d が辞書でない" % day)
			continue
		for item in (entry as Dictionary).get("news", []):
			if not (item is Dictionary):
				found.append("Day%d のニュースの要素が辞書でない" % day)
				continue
			var nid := str(item.get("id", ""))
			if nid == "" or seen_ids.has(nid):
				found.append("Day%d のニュースの id %s が空か重複" % [day, nid])
			seen_ids[nid] = true
			if not (item.get("headline") is String) or str(item["headline"]) == "":
				found.append("Day%d %s に headline が無い" % [day, nid])
			if not _is_line_list(item.get("body", []), true):
				found.append("Day%d %s の body が文字列の配列でない" % [day, nid])
			found.append_array(_must_info_problems(item.get("must_info", []), known, "Day%d %s" % [day, nid], day))
		for item in (entry as Dictionary).get("dm", []):
			if not (item is Dictionary) or not (item.get("from") is String) or str(item["from"]) == "" \
					or not (item.get("text") is String) or str(item["text"]) == "":
				found.append("Day%d の DM に from / text が無い" % day)
		for item in (entry as Dictionary).get("events", []):
			if not (item is Dictionary):
				found.append("Day%d の共通イベントの要素が辞書でない" % day)
				continue
			var eid := str(item.get("id", ""))
			if eid == "" or seen_ids.has(eid):
				found.append("Day%d の共通イベントの id %s が空か重複" % [day, eid])
			seen_ids[eid] = true
			if not allowed.has(item.get("at")):
				found.append("Day%d %s の at %s が wake／close／時間帯名でない" % [day, eid, str(item.get("at"))])
			if not _is_line_list(item.get("lines", []), false):
				found.append("Day%d %s の lines が空でない文字列の配列でない" % [day, eid])
			found.append_array(_must_info_problems(item.get("must_info", []), known, "Day%d %s" % [day, eid], day))
	# 担保：全 id がニュースまたは共通イベントに現れ、日がカタログと一致する
	var delivered := delivered_days(d)
	for id in known:
		if not delivered.has(id):
			found.append("必須情報 %s がニュースにも共通イベントにも無い（客だけでは担保にならない）" % id)
		elif (delivered[id] as Array).size() != 1 or int((delivered[id] as Array)[0]) != int(known[id]):
			found.append("必須情報 %s が現れる日 %s がカタログの day %d と一致しない" % [id, str(delivered[id]), int(known[id])])
	return found


static func _must_info_problems(ids, known: Dictionary, where: String, day: int) -> Array:
	var found := []
	if not (ids is Array):
		return ["%s の must_info が配列でない" % where]
	for id in ids:
		if not (id is String) or not known.has(id):
			found.append("%s の must_info %s がカタログに無い" % [where, str(id)])
	return found
