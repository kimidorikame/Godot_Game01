extends RefCounted
class_name Sns
## SNSのタイムライン（スマホのSNSタブ。UI準備R・試しの実装）。静的クラスで状態は持たない（読むだけ・乱数なし）。
## データは data/sns/<id>.json（id は Rules.sns()＝week7.json の "sns"。DM・ニュースと同じ置き方）。
##
## データ形：
##   accounts.<id> … { name（表示名）, handle（@〜）, icon:{ color（"#rrggbb"）, text（1文字か記号）}, profile, kind:"main|alt"（表／裏）,
##                    owner（書き手用。客の id か "town"。画面に出さない）}
##   posts … [ { id, account, day, time（"HH:MM"）, text, photo（任意。写真の説明の文字）, reply_to（任意。元の投稿の id）,
##              requires（任意。{ met:<客id> }＝その客の初来店の日の閉店のあとから）, truth（任意。書き手用。画面に出さない）, provisional } ]
## アカウントの持ち主は画面に出さない（どれが誰のアカウントかはプレイヤーが推理する）。DMの差出人とも結びつけない。
## いいね・拡散・表示回数などの数字は持たない。
##
## 見える時刻（UI準備R2）：前の日までの投稿は全部見える。今日の投稿は、ゲームの中の今の時刻（場面ごとの上限 limit）までのものだけ見える：
##   朝（目覚め〜朝の成績）＝09:59／市場・準備＝17:59／営業の宵の口＝21:59・夜半＝翌00:59・明け方＝翌04:59／閉店のあと＝その日の全部（翌04:59まで）。
## 夜中 00:00〜04:59 はその日の24時以降（その日の夜の続き）として数える（limit も同じ数え方。翌00:59＝24:59）。並びも同じ考え方。

static var data_dir := "res://data/sns/"
static var _cache: Dictionary = {}
static var _loaded_id := ""

const KINDS := ["main", "alt"]
const MORNING_FROM := 5 * 60   # 05:00（これより前は、その日の24時以降として数える）
## 場面ごとの、今日の投稿が見える時刻の上限（その日の 00:00 からの分。夜中は24時以降）。UI準備R2。
const LIMIT_MORNING := 9 * 60 + 59      # 朝（目覚め〜朝の成績）：09:59
const LIMIT_MARKET := 17 * 60 + 59      # 市場・準備：17:59
const LIMIT_EVENING := 21 * 60 + 59     # 営業の宵の口：21:59
const LIMIT_MIDNIGHT := 24 * 60 + 59    # 営業の夜半：翌 00:59
const LIMIT_DAY_END := 28 * 60 + 59     # 営業の明け方・閉店のあと：翌 04:59（その日の投稿すべて）


static func clear_cache() -> void:
	_cache = {}
	_loaded_id = ""


## 今のキャンペーンのタイムラインのデータ全体。無い・読めないときは空辞書。
static func data() -> Dictionary:
	var id := Rules.sns()
	if _loaded_id != id or _cache.is_empty():
		_cache = {}
		var path := data_dir + id + ".json"
		if id != "" and FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_cache = parsed
		_loaded_id = id
	return _cache


static func accounts(source: Dictionary = {}) -> Dictionary:
	var d: Dictionary = source if not source.is_empty() else data()
	var a = d.get("accounts", {})
	return a if a is Dictionary else {}


static func posts(source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var p = d.get("posts", [])
	return p if p is Array else []


## "HH:MM" を分に（形が違えば -1）。
static func minutes(time: String) -> int:
	var parts := time.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var h := int(parts[0])
	var m := int(parts[1])
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m


## その日の中の時刻（分）。夜中 00:00〜04:59 はその日の24時以降として数える（02:15 → 26:15）。
static func day_minutes(time: String) -> int:
	var t := maxi(minutes(time), 0)
	return t + 24 * 60 if t < MORNING_FROM else t


## 並びの値（大きいほど新しい）。夜中 00:00〜04:59 はその日の24時以降として数える。
static func order_value(day: int, time: String) -> int:
	return day * 10000 + day_minutes(time)


## その客の初来店の日（来店記録。会っていなければ -1）。
static func first_met_day(customer_id: String) -> int:
	var visits := CustomerMemory.visits_of(customer_id)
	return int((visits[0] as Dictionary).get("day", -1)) if not visits.is_empty() else -1


## 投稿が見えるか。today＝今日、limit＝今日の投稿が見える時刻の上限（場面ごと。LIMIT_*）。前の日までの投稿は全部見える。
## met（その客に会ったあと）は、初来店の日の閉店のあと（limit が LIMIT_DAY_END）から。
static func is_visible(post: Dictionary, today: int, limit: int = LIMIT_DAY_END) -> bool:
	var day := int(post.get("day", 0))
	if day > today or (day == today and day_minutes(str(post.get("time", ""))) > limit):
		return false
	var requires = post.get("requires", {})
	if requires is Dictionary and (requires as Dictionary).has("met"):
		var met := first_met_day(str(requires["met"]))
		if met < 0 or not (met < today or (met == today and limit >= LIMIT_DAY_END)):
			return false
	return true


## 見えている投稿を、画面の形にまとめる：[{ day, posts:[ 投稿＋{ account（アカウントの辞書）, replies:[返信…] } ] }]。
## 新しい日が上。同じ日の中は新しい時刻が上。返信は元の投稿のすぐ下に古い順（元の投稿が見えていないときは出さない）。
static func timeline(today: int, limit: int = LIMIT_DAY_END, source: Dictionary = {}) -> Array:
	var accts := accounts(source)
	var tops := []
	var replies := {}   # 元の投稿の id -> [返信]
	for post in posts(source):
		if not (post is Dictionary) or not is_visible(post, today, limit):
			continue
		var item: Dictionary = (post as Dictionary).duplicate(true)
		item["account_data"] = (accts.get(str(item.get("account", "")), {}) as Dictionary).duplicate(true)
		var parent := str(item.get("reply_to", ""))
		if parent != "":
			(replies.get_or_add(parent, []) as Array).append(item)
		else:
			tops.append(item)
	tops.sort_custom(func(a, b): return order_value(int(a["day"]), str(a["time"])) > order_value(int(b["day"]), str(b["time"])))
	var sections := []
	for item in tops:
		var list: Array = replies.get(str(item["id"]), [])
		list.sort_custom(func(a, b): return order_value(int(a["day"]), str(a["time"])) < order_value(int(b["day"]), str(b["time"])))
		item["replies"] = list
		if sections.is_empty() or int((sections[sections.size() - 1] as Dictionary)["day"]) != int(item["day"]):
			sections.append({ "day": int(item["day"]), "posts": [] })
		((sections[sections.size() - 1] as Dictionary)["posts"] as Array).append(item)
	return sections


## 見えている投稿の id（返信を含む。未読の数・既読に使う）。
static func visible_ids(today: int, limit: int = LIMIT_DAY_END, source: Dictionary = {}) -> Array:
	var out := []
	for section in timeline(today, limit, source):
		for item in section["posts"]:
			out.append(str(item["id"]))
			for reply in item["replies"]:
				out.append(str(reply["id"]))
	return out


## データの形の検査（データのテストが使う）。問題の説明の配列（空なら問題なし）。
static func problems(source: Dictionary = {}) -> Array:
	var d: Dictionary = source if not source.is_empty() else data()
	var found := []
	if d.is_empty():
		return ["SNSのデータが読めない"]
	var accts = d.get("accounts", {})
	if not (accts is Dictionary):
		return ["accounts が辞書でない"]
	var handles := {}
	for id in accts:
		var a = accts[id]
		var where := "accounts.%s" % str(id)
		if not (a is Dictionary):
			found.append(where + " が辞書でない")
			continue
		for key in ["name", "handle"]:
			if not (a.get(key) is String) or str(a[key]) == "":
				found.append("%s に %s が無い" % [where, key])
		var handle := str(a.get("handle", ""))
		if handle != "" and not handle.begins_with("@"):
			found.append("%s の handle が @ で始まらない" % where)
		if handles.has(handle):
			found.append("%s の handle %s が %s と重複" % [where, handle, str(handles[handle])])
		handles[handle] = str(id)
		var icon = a.get("icon", {})
		if not (icon is Dictionary) or not Color.html_is_valid(str((icon as Dictionary).get("color", ""))) or str((icon as Dictionary).get("text", "")) == "":
			found.append(where + " の icon（color・text）が正しくない")
		if not KINDS.has(str(a.get("kind", ""))):
			found.append(where + " の kind が main／alt でない")
		var owner := str(a.get("owner", ""))
		if owner != "town" and not FileAccess.file_exists("res://data/customers/%s.json" % owner):
			found.append("%s の owner %s が客でも town でもない" % [where, owner])
		if not (a.get("profile", "") is String):
			found.append(where + " の profile が文字列でない")
	var list = d.get("posts", [])
	if not (list is Array):
		return found + ["posts が配列でない"]
	var by_id := {}
	for post in list:
		if post is Dictionary and str((post as Dictionary).get("id", "")) != "":
			if by_id.has(str(post["id"])):
				found.append("投稿の id %s が重複" % str(post["id"]))
			by_id[str(post["id"])] = post
	for post in list:
		if not (post is Dictionary):
			found.append("投稿の要素が辞書でない")
			continue
		var id := str(post.get("id", ""))
		var where := "posts.%s" % id
		if id == "":
			found.append("投稿に id が無い")
		if not (accts as Dictionary).has(str(post.get("account", ""))):
			found.append("%s：アカウント %s が無い" % [where, str(post.get("account", ""))])
		var day := int(post.get("day", 0)) if (post.get("day") is int or post.get("day") is float) else 0
		if day < 1 or day > Rules.final_day():
			found.append("%s：day が 1〜%d でない" % [where, Rules.final_day()])
		if minutes(str(post.get("time", ""))) < 0:
			found.append("%s：time が HH:MM でない" % where)
		var text := str(post.get("text", ""))
		if not (post.get("text") is String) or text == "":
			found.append(where + "：本文が空")
		for tag in TagWords.all_tags():
			if text.contains(str(tag)):
				found.append("%s：本文に内部の札の名前 %s がある" % [where, str(tag)])
		if post.has("photo") and (not (post["photo"] is String) or str(post["photo"]) == ""):
			found.append(where + "：photo が空でない文字列でない")
		if post.has("reply_to"):
			var parent = by_id.get(str(post["reply_to"]), null)
			if parent == null:
				found.append("%s：返信先 %s が無い" % [where, str(post["reply_to"])])
			elif (parent as Dictionary).has("reply_to"):
				found.append("%s：返信先 %s も返信（返信への返信は持たない）" % [where, str(post["reply_to"])])
			elif order_value(day, str(post.get("time", ""))) < order_value(int(parent.get("day", 0)), str(parent.get("time", ""))):
				found.append("%s：返信が元の投稿 %s より前の時刻" % [where, str(post["reply_to"])])
		var requires = post.get("requires", {})
		if not (requires is Dictionary):
			found.append(where + "：requires が辞書でない")
		else:
			for key in requires:
				if str(key) != "met":
					found.append("%s：requires のキー %s は使えない（met だけ）" % [where, str(key)])
				elif not FileAccess.file_exists("res://data/customers/%s.json" % str(requires[key])):
					found.append("%s：requires.met の客 %s が無い" % [where, str(requires[key])])
	return found
