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
##   days.<日> … { news:[{ id, headline, body[], must_info[], provisional, after_event?, time? }],
##                 events:[{ id, at, lines[], must_info[], provisional }] }
##   at … "wake"（朝のニュースの後）／時間帯名（その時間帯の最初の客の前）／"close"（閉店の語りの前）
##   速報（UI準備AC）… ニュースの項目に after_event:<その日の共通イベントの id> と time:"HH:MM" を持つもの。その日は、その共通イベントを
##         再生したあとから一覧に出る（次の日からは条件なし）。朝の語り（morning_events）には出さない。must_info は持たない。
##         時刻は SNS と同じ数え方（00:00〜04:59 はその日の24時以降）。一覧では、その日の朝の記事より上に、時刻の新しい順。
##   共通イベントの lines（UI準備AC）… 文字列の行（「名前「セリフ」」なら会話枠に名前の札が付く）のほかに、
##         条件付きの行のまとまり（{ if:{ fact｜not_fact｜mob_served｜not_mob_served … }, lines:[…] }。ScheduleData.condition_problems）・
##         { show_dm:<その日のDMの id> }（差出人と本文〔写真があれば説明の文字〕を会話枠に出す。出したら既読）・
##         { show_news:<その日のニュースの id> }（見出しを会話枠に出す。速報は「速報：」、朝の記事は「ニュース：」）を置ける。

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


## その日のニュース・共通イベント。{ news: [], events: [] }（無い日・形が不正は空）。DMは scripts/dm.gd
## （data/dm/<id>.json。UI準備C③で、ニュースのデータの dm 欄からSNSタブのDMへ移した）。
static func day_entry(day: int, source: Dictionary = {}) -> Dictionary:
	var d: Dictionary = source if not source.is_empty() else data()
	var days = d.get("days", {})
	var entry := { "news": [], "events": [] }
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


## 朝（WAKE）に必ず差す、その日のニュースの TEXT イベント（part:"news"）。見出し→本文の順。ニュースの無い日は
## 空配列＝従来の起床の列と同一。状態を読むだけ（日番号からデータを引く）。DMは朝の語りに出さない（SNSタブ）。
## 表示だけで、ゲームの数値には触れない。
static func morning_events(day: int, source: Dictionary = {}) -> Array:
	var events := []
	var entry := day_entry(day, source)
	for item in entry["news"]:
		if is_flash(item):
			continue   # 速報（UI準備AC）は朝の語りに出さない
		if str(item.get("headline", "")) != "":
			events.append({ "type": "TEXT", "text": "ニュース：%s" % str(item["headline"]), "part": "news" })
		if item.get("body") is Array:
			for line in item["body"]:
				if line is String and line != "":
					events.append({ "type": "TEXT", "text": line, "part": "news" })
	return events


## --- 共通イベント（客の抽選に依存しない、その日の出来事）。TEXTだけで、ゲームの数値には触れない ---

## 共通イベント1件の TEXT イベント（part:"common_event"・event_id付き）。day＝その共通イベントの日（既定は今日）。
## UI準備AC：条件付きの行は今の状態で開く（CustomerMemory.resolve_lines。モブの条件 mob_served も）。show_dm は差出人と本文の1行
## （dm_id 付き。会話枠に出たら既読にする＝PlaySession.record_visible_event）、show_news は見出しの1行（news_id 付き）。
static func event_lines(item: Dictionary, day: int = -1) -> Array:
	var events := []
	var d := day if day > 0 else GameState.day_count
	var eid := str(item.get("id", ""))
	if not (item.get("lines") is Array):
		return events
	for line in CustomerMemory.resolve_lines(_with_day(item["lines"], d), ""):
		if line is String and line != "":
			events.append({ "type": "TEXT", "text": line, "part": "common_event", "event_id": eid })
		elif line is Dictionary and (line as Dictionary).has("show_dm"):
			var dm := Dm.item_by_id(d, str(line["show_dm"]))
			if not dm.is_empty():
				events.append({ "type": "TEXT", "text": Dm.shown_line(dm), "part": "common_event", "event_id": eid, "dm_id": str(dm["id"]) })
		elif line is Dictionary and (line as Dictionary).has("show_news"):
			var news := news_by_id(d, str(line["show_news"]))
			if not news.is_empty():
				events.append({ "type": "TEXT", "text": "%s：%s" % ["速報" if is_flash(news) else "ニュース", str(news.get("headline", ""))],
					"part": "common_event", "event_id": eid, "news_id": str(news["id"]) })
	return events


## 共通イベントの行の配列の写しで、モブの条件（mob_served・not_mob_served）に day が無いものへ、その共通イベントの日を入れる
## （過ぎた日の出来事をスマホで読み返すときも、その日の晩の状態で選ぶため）。
static func _with_day(lines: Array, day: int) -> Array:
	var out := []
	for line in lines:
		if ScheduleData.is_condition_group(line):
			var cond: Dictionary = (line[ScheduleData.CONDITION_KEY] as Dictionary).duplicate()
			if ScheduleData.MOB_CONDITION_KINDS.any(func(k): return cond.has(k)) and not cond.has("day"):
				cond["day"] = day
			out.append({ ScheduleData.CONDITION_KEY: cond, "lines": _with_day(line["lines"], day) })
		else:
			out.append(line)
	return out


## 共通イベント1件の、画面に出る文（event_lines の本文）。スマホのニュースタブの「出来事」に使う。
static func event_texts(item: Dictionary, day: int) -> Array:
	return event_lines(item, day).map(func(ev): return str(ev["text"]))


## 速報か（UI準備AC：after_event を持つニュースの項目）。
static func is_flash(item) -> bool:
	return item is Dictionary and str((item as Dictionary).get("after_event", "")) != ""


## その日のニュースの項目（無ければ空辞書）。
static func news_by_id(day: int, id: String, source: Dictionary = {}) -> Dictionary:
	for item in day_entry(day, source)["news"]:
		if str(item.get("id", "")) == id:
			return item
	return {}


## その日のニュースのうち、今見えているもの（UI準備AC）。過ぎた日は全部。今日は、朝の記事と、after_event の共通イベントを
## 再生した（played_ids にある）速報。並びは、速報（時刻の新しい順）→ 朝の記事（データの順）。
static func visible_news(day: int, today: int, played_ids: Array = [], source: Dictionary = {}) -> Array:
	var flash := []
	var morning := []
	for item in day_entry(day, source)["news"]:
		if is_flash(item):
			if day < today or played_ids.has(str(item["after_event"])):
				flash.append(item)
		else:
			morning.append(item)
	flash.sort_custom(func(a, b): return Sns.day_minutes(str(a.get("time", ""))) > Sns.day_minutes(str(b.get("time", ""))))
	return flash + morning


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
		for item in visible_news(day, today, played_ids, source):
			section.append("・%s%s%s" % ["［速報 %s］" % str(item.get("time", "")) if is_flash(item) else "", _provisional_mark(item), str(item.get("headline", ""))])
			if item.get("body") is Array:
				for line in item["body"]:
					section.append("　%s" % str(line))
		for item in entry["events"]:
			if day < today or played_ids.has(str(item.get("id", ""))):
				for line in event_texts(item, day):
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
			if item.has("after_event") or item.has("time"):
				# 速報（UI準備AC）：その日の共通イベントの後に出る。時刻あり・必須情報なし
				if event_by_id(day, str(item.get("after_event", "")), d).is_empty():
					found.append("Day%d %s の after_event %s がその日の共通イベントに無い" % [day, nid, str(item.get("after_event", ""))])
				if Sns.minutes(str(item.get("time", ""))) < 0:
					found.append("Day%d %s の time が HH:MM でない" % [day, nid])
				if not (item.get("must_info", []) is Array) or not (item.get("must_info", []) as Array).is_empty():
					found.append("Day%d %s：速報に must_info は付けない" % [day, nid])
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
			found.append_array(_event_line_problems(item.get("lines", []), "Day%d %s" % [day, eid], day, d, true))
			found.append_array(_must_info_problems(item.get("must_info", []), known, "Day%d %s" % [day, eid], day))
	# 担保：全 id がニュースまたは共通イベントに現れ、日がカタログと一致する
	var delivered := delivered_days(d)
	for id in known:
		if not delivered.has(id):
			found.append("必須情報 %s がニュースにも共通イベントにも無い（客だけでは担保にならない）" % id)
		elif (delivered[id] as Array).size() != 1 or int((delivered[id] as Array)[0]) != int(known[id]):
			found.append("必須情報 %s が現れる日 %s がカタログの day %d と一致しない" % [id, str(delivered[id]), int(known[id])])
	return found


## 共通イベントの lines の形（UI準備AC）：空でない文字列・条件付きの行のまとまり（入れ子も）・{ show_dm }（その日のDMにある id）・
## { show_news }（その日のニュースにある id）。top は一番外の配列（空を許さない）。
static func _event_line_problems(lines, where: String, day: int, source: Dictionary, top: bool) -> Array:
	var found := []
	if not (lines is Array) or (top and (lines as Array).is_empty()):
		return ["%s の lines が空でない配列でない" % where]
	for line in lines:
		if line is String:
			if line == "":
				found.append("%s の lines に空の行がある" % where)
		elif ScheduleData.is_condition_group(line):
			found.append_array(ScheduleData.condition_problems(line[ScheduleData.CONDITION_KEY], where))
			found.append_array(_event_line_problems(line["lines"], where, day, source, false))
		elif line is Dictionary and (line as Dictionary).size() == 1 and (line as Dictionary).has("show_dm"):
			if Dm.item_by_id(day, str(line["show_dm"])).is_empty():
				found.append("%s の show_dm %s がその日のDMに無い" % [where, str(line["show_dm"])])
		elif line is Dictionary and (line as Dictionary).size() == 1 and (line as Dictionary).has("show_news"):
			if news_by_id(day, str(line["show_news"]), source).is_empty():
				found.append("%s の show_news %s がその日のニュースに無い" % [where, str(line["show_news"])])
		else:
			found.append("%s の lines に、文字列・条件付きの行・show_dm・show_news でない要素がある" % where)
	return found


static func _must_info_problems(ids, known: Dictionary, where: String, day: int) -> Array:
	var found := []
	if not (ids is Array):
		return ["%s の must_info が配列でない" % where]
	for id in ids:
		if not (id is String) or not known.has(id):
			found.append("%s の must_info %s がカタログに無い" % [where, str(id)])
	return found
