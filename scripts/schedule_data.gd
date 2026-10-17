extends RefCounted
class_name ScheduleData
## 日別スケジュール・客・モブのデータをJSONから読む専用ファイル（`Ingredients`と同じ
## 「データだけを持つファイル」の位置づけ。DESIGN.md「シナリオデータと処理を分離する」方針）。
##
## 読み込んだJSONは静的にキャッシュする（ファイルは日中に書き換わらない前提。
## `Ingredients`の定数キャッシュと同じ考え方。プロセスを再起動しない限りは
## 一度読めば十分＝接客のたびにディスクI/Oしない）。
##
## 常連の固定日程（4-3。data/schedules/week7_regulars.json）：
##   { "days": { "<day>": [ { "slot", "regular", "episode_id" }, ... ] } }
## モブの抽選ルール（4-3。data/schedules/mob_rules.json）：既定＋日別の上書き。
## 日番号を引く関数は regular_slots(day)・mob_rule_for(day, slot) だけで、客のデータは
## 日番号を持たない（4-4a）：
## customers/<id>.json（基本プロフィール）：{ "is_mob", "favorite", "wanted_tags" }
##   （wanted_tagsは基本注文。10.5.1「日によって変えない」。delivery_manの3杯専用列の
##   会話は _delivery_man_events() 側にGDScriptのまま残す）。
## episodes/<客>/<episode_id>.json（来店場面）：{ "id", "customer", "greet", "reactions", "servings" }
##   どの場面を引くかはDayPlanの枠（regular_id・episode_id）が持つ（Day1Events.episode_id_of）。
## mobs/<id>.json のモデル：
##   { "is_mob", "greet", "reactions", "wanted_tags" }（日をまたいで変わらない＝days無し）。

# 4-3：常連の固定日程（week7.jsonのregular_schedule＝"week7_regulars"から引く）と、
# モブの抽選ルール（既定＋日別の上書き）。DESIGN.md 10.8.1。
const _SCHEDULES_DIR := "res://data/schedules/"
const _MOB_RULES_PATH := "res://data/schedules/mob_rules.json"
# 4-4a：来店場面（episode。data/episodes/<客>/<episode_id>.json）。基本プロフィールは
# data/customers/<id>.json。
# テストは場面の置き場を差し替える（tests/fixtures/episodes/。差し替えたらclear_cache()を呼ぶ）。
static var episodes_dir := "res://data/episodes/"
const _CUSTOMERS_DIR := "res://data/customers/"
const _MOBS_DIR := "res://data/mobs/"
const _KITS_DIR := "res://data/kits/"

static var _customer_cache: Dictionary = {}   # id(String) -> 生のJSON全体（Dictionary）
static var _mob_cache: Dictionary = {}        # id(String) -> 生のJSON全体（Dictionary）
static var _kit_cache: Dictionary = {}        # id(String) -> 生のJSON全体（Dictionary）
static var _regulars_cache: Dictionary = {}   # 常連の固定日程（schedule id -> 生のJSON全体）
static var _mob_rules_cache: Dictionary = {}
static var _mob_rules_loaded := false
static var _episode_cache: Dictionary = {}    # "<客>/<episode_id>" -> 生のJSON全体（Dictionary）


## JSON読み込みの共通処理。ファイルが無い・パースに失敗した場合は空辞書を返す
## （クラッシュしない。呼び出し側は空辞書を「データ無し」として扱えばよい）。
static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ScheduleData: file not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ScheduleData: failed to open: %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("ScheduleData: invalid JSON: %s" % path)
		return {}
	return parsed


## 常連の固定日程（DESIGN.md 10.5.1・21枠）。week7.jsonのregular_schedule（schedule id）の
## data/schedules/<id>.json全体：
##   { "days": { "<day>": [ { "slot": 枠名, "regular": 客id, "episode_id": 場面id }, ... ] } }。
## 枠は辞書（後の手順で項目を足せる）。無い・読めないときは空辞書。
static func regular_schedule_data() -> Dictionary:
	var id := Rules.regular_schedule()
	if id == "":
		return {}
	if not _regulars_cache.has(id):
		_regulars_cache[id] = _load_json(_SCHEDULES_DIR + id + ".json")
	return _regulars_cache[id]


## モブの抽選ルール（data/schedules/mob_rules.json全体）：
##   { "default": { "pool": [種類id...], "slots": { 枠名: bool } },
##     "days": { "<day>": { 枠名: false | { "pool": [...] } } } }
## 既定で枠ごとの可否とプールを持ち、日別の上書きがあればそれが優先する。
static func mob_rules_data() -> Dictionary:
	if not _mob_rules_loaded:
		_mob_rules_cache = _load_json(_MOB_RULES_PATH)
		_mob_rules_loaded = true
	return _mob_rules_cache


## 指定日の常連の枠（[{ "slot": 枠名, "regular": 客id, "episode_id": 場面id }, ...]）。
## 日程の定義が無い日（Day8以降）は空の配列（客なし。Day1へのフォールバックはしない。
## 最終日は7でRESULTへ入るので、実プレイでは起きない）。
## DayPlan／customer_schedule()が直接読む口。辞書の枠なので、後の手順で項目を足せる。
static func regular_slots(day: int) -> Array:
	var days: Dictionary = regular_schedule_data().get("days", {})
	var entries: Array = days.get(str(day), [])
	return entries.duplicate(true)


## 指定日・指定枠のモブの抽選ルール：false（その枠はモブなし）または {"pool": [種類id...]}。
## mob_rules.jsonの日別の上書きがあればそれ、なければ既定（枠ごとの可否＋既定のプール）。
static func mob_rule_for(day: int, slot_name: String) -> Variant:
	var rules := mob_rules_data()
	var default_rule: Dictionary = rules.get("default", {})
	var default_pool: Array = default_rule.get("pool", [])
	var day_rules: Dictionary = (rules.get("days", {}) as Dictionary).get(str(day), {})
	if day_rules.has(slot_name):
		var rule = day_rules[slot_name]
		if rule is Dictionary:
			return (rule as Dictionary).duplicate(true)
		return { "pool": default_pool.duplicate() } if bool(rule) else false
	if bool((default_rule.get("slots", {}) as Dictionary).get(slot_name, false)):
		return { "pool": default_pool.duplicate() }
	return false


## 客の基本プロフィール（data/customers/<id>.json のトップレベル。"days"は除く）。
## name（表示名）/ is_mob / favorite / wanted_tags（基本注文。10.5.1「日によって変えない」）。
## 未知の客・ファイルが無いときは空辞書。
static func customer_profile(id: String) -> Dictionary:
	if not _customer_cache.has(id):
		_customer_cache[id] = _load_json(_CUSTOMERS_DIR + id + ".json")
	var raw: Dictionary = _customer_cache[id]
	var result := {}
	for k in raw:
		if k != "days":
			result[k] = raw[k]
	return result


## 客の表示名（data/customers/<id>.json の "name"）。システムが組み立てる文面（結果画面・
## 予告メモ）で使う。未知の客・"name"の無い／空のプロフィールはid自体を返す（クラッシュしない）。
## 場面データの文言（greet・reactions）は対象外。モブはDay1Events.mob_display_name()。
static func customer_display_name(id: String) -> String:
	var name := str(customer_profile(id).get("name", ""))
	return name if name != "" else id


## 来店場面1つのデータ（data/episodes/<客>/<episode_id>.json）：
## { "id", "customer", "greet", "reactions", "servings" }。無いときは空辞書（エラーを出さない）。
static func episode_data(customer_id: String, episode_id: String) -> Dictionary:
	if customer_id == "" or episode_id == "":
		return {}
	var key := customer_id + "/" + episode_id
	if not _episode_cache.has(key):
		var path := episodes_dir + customer_id + "/" + episode_id + ".json"
		_episode_cache[key] = _load_json(path) if FileAccess.file_exists(path) else {}
	return _episode_cache[key]


## 場面の前提（requires）。今回読むのは facts（事実の一致）と not_seen（未読）だけ
## （4-4b-2。単純な絞り込みのみ。orや式は持たない）。無ければ空辞書。
static func episode_requires(customer_id: String, episode_id: String) -> Dictionary:
	var requires = episode_data(customer_id, episode_id).get("requires", {})
	return (requires as Dictionary).duplicate(true) if requires is Dictionary else {}


## 場面の「今日の頼み」（order.today_request：{ tags, label }）。無い・形が不正なら空辞書。
## tagsは基本注文（プロフィールのwanted_tags）を上書きする実効注文（DESIGN.md 10.3.2・10.5.2）。
static func episode_today_request(customer_id: String, episode_id: String) -> Dictionary:
	var order = episode_data(customer_id, episode_id).get("order", {})
	if not (order is Dictionary):
		return {}
	var request = (order as Dictionary).get("today_request", {})
	if not (request is Dictionary) or not ((request as Dictionary).get("tags", []) is Array) \
			or ((request as Dictionary).get("tags", []) as Array).is_empty():
		return {}
	return (request as Dictionary).duplicate(true)


## 場面の「前回への2行」（callback。出し分けのキーごとの行の配列）。無ければ空辞書。
static func episode_callback(customer_id: String, episode_id: String) -> Dictionary:
	var callback = episode_data(customer_id, episode_id).get("callback", {})
	return (callback as Dictionary).duplicate(true) if callback is Dictionary else {}


## 場面の「昼の市場の会話」（market_talk。PREPの市場の前に出す行の配列）。無い・形が不正なら空配列。
## 行は文字列だけを拾う（空文字は除く）。
static func episode_market_talk(customer_id: String, episode_id: String) -> Array:
	var talk = episode_data(customer_id, episode_id).get("market_talk", [])
	var lines := []
	if talk is Array:
		for line in talk:
			if line is String and line != "":
				lines.append(line)
	return lines


## --- 提供後の場面データ（システム整理C。DESIGN.md 10.5.3・10.8.6） ---
## 場面のキー pre_order / body / body_unserved / closing / must_info は任意。無い・形が不正な
## ものは「無い」と同じに読む（空配列／空辞書。クラッシュしない）。形の検査は scene_problems()。

## 文字列の配列として読む（空文字・文字列でない要素は捨てる）。
static func _string_lines(value) -> Array:
	var lines := []
	if value is Array:
		for line in value:
			if line is String and line != "":
				lines.append(line)
	return lines


## 注文の前の行（前回の2行と注文＝greet の間に出す）。無ければ空配列。
static func episode_pre_order(customer_id: String, episode_id: String) -> Array:
	return _string_lines(episode_data(customer_id, episode_id).get("pre_order", []))


## 提供後の本文（食事中の話の行）。無ければ空配列。
static func episode_body(customer_id: String, episode_id: String) -> Array:
	return _string_lines(episode_data(customer_id, episode_id).get("body", []))


## 提供しなかったときの本文（must_info を持つ場面だけが使う未提供版）。無ければ空配列。
static func episode_body_unserved(customer_id: String, episode_id: String) -> Array:
	return _string_lines(episode_data(customer_id, episode_id).get("body_unserved", []))


## 締め。{ キー: 行の配列 }。"default" と、差分のキー（"<選択id>:<選択肢id>"・
## "request_honored:true|false"）。行の配列でないキーは捨てる。無ければ空辞書。
static func episode_closing(customer_id: String, episode_id: String) -> Dictionary:
	var closing = episode_data(customer_id, episode_id).get("closing", {})
	var result := {}
	if closing is Dictionary:
		for key in closing:
			var lines := _string_lines(closing[key])
			if key is String and not lines.is_empty():
				result[key] = lines
	return result


## 必須情報の印（SEVEN_DAY_OUTLINE §11の9項目の識別子）。印を読むだけで、9項目の管理は
## 日別ニュース（D）で扱う。印があれば、提供しなかったときも本文（未提供版）を再生する。
static func episode_must_info(customer_id: String, episode_id: String) -> Array:
	return _string_lines(episode_data(customer_id, episode_id).get("must_info", []))


const _REACTION_KEYS := ["GREAT", "GOOD", "OK", "BAD", "UNSERVED"]
const _MAX_CHOICES := 2
const _MAX_FACT_KEYS := 2


static func _is_lines(value) -> bool:
	if not (value is Array):
		return false
	for line in value:
		if not (line is String) or line == "":
			return false
	return true


## 場面データ1つの形の検査（データ検証テストと、将来の脚本の取り込みが使う）。問題の説明の
## 配列を返す（空なら問題なし）。検査するのは新しいキーと反応のキーだけ：
##   reactions … 4段階＋UNSERVED。値は文字列の配列
##   market_talk / pre_order / body / body_unserved … 空でない文字列の配列
##   choices … 最大2。各 { id, options:[2つ { id, label, set(辞書・任意) }] }。idは一意
##   sets_facts … 辞書。選択肢の set と合わせた事実のキーが重複を除いて2個まで。両方に同じキーは不可
##   closing … { default: 行の配列, <選択id>:<選択肢id> | request_honored:true|false: 行の配列 }
##   must_info … 空でない文字列の配列。must_info と body の両方があれば body_unserved が必須
static func scene_problems(ep: Dictionary) -> Array:
	var problems := []
	if ep.has("reactions"):
		var reactions = ep["reactions"]
		if not (reactions is Dictionary):
			problems.append("reactions が辞書でない")
		else:
			for key in reactions:
				if not _REACTION_KEYS.has(key):
					problems.append("reactions に未知のキー %s" % str(key))
				elif not (reactions[key] is Array):
					problems.append("reactions.%s が配列でない" % str(key))
	for key in ["market_talk", "pre_order", "body", "body_unserved", "must_info"]:
		if ep.has(key) and not _is_lines(ep[key]):
			problems.append("%s が空でない文字列の配列でない" % key)
	var choice_ids := {}
	var option_keys := {}   # "選択id:選択肢id" -> true
	var fact_keys := {}
	if ep.has("choices"):
		var choices = ep["choices"]
		if not (choices is Array):
			problems.append("choices が配列でない")
		else:
			if (choices as Array).size() > _MAX_CHOICES:
				problems.append("choices が%d個を超えている" % _MAX_CHOICES)
			for choice in choices:
				if not (choice is Dictionary) or not ((choice as Dictionary).get("id") is String) 						or str((choice as Dictionary)["id"]) == "":
					problems.append("choices の要素に id が無い")
					continue
				var cid := str(choice["id"])
				if choice_ids.has(cid):
					problems.append("choices の id %s が重複" % cid)
				choice_ids[cid] = true
				var options = (choice as Dictionary).get("options")
				if not (options is Array) or (options as Array).size() != 2:
					problems.append("choices.%s の options が2つでない" % cid)
					continue
				var seen_options := {}
				for option in options:
					if not (option is Dictionary) or not ((option as Dictionary).get("id") is String) 							or str((option as Dictionary)["id"]) == "" 							or not ((option as Dictionary).get("label") is String) 							or str((option as Dictionary)["label"]) == "":
						problems.append("choices.%s の選択肢に id / label が無い" % cid)
						continue
					var oid := str(option["id"])
					if seen_options.has(oid):
						problems.append("choices.%s の選択肢 id %s が重複" % [cid, oid])
					seen_options[oid] = true
					option_keys["%s:%s" % [cid, oid]] = true
					var set_facts = (option as Dictionary).get("set", {})
					if not (set_facts is Dictionary):
						problems.append("choices.%s.%s の set が辞書でない" % [cid, oid])
					else:
						for fact_key in set_facts:
							fact_keys[str(fact_key)] = true
	var sets_keys := {}
	if ep.has("sets_facts"):
		var sets_facts = ep["sets_facts"]
		if not (sets_facts is Dictionary):
			problems.append("sets_facts が辞書でない")
		else:
			for fact_key in sets_facts:
				if fact_keys.has(str(fact_key)):
					problems.append("事実 %s が choices の set と sets_facts の両方にある" % str(fact_key))
				sets_keys[str(fact_key)] = true
	var distinct := fact_keys.duplicate()
	distinct.merge(sets_keys)
	if distinct.size() > _MAX_FACT_KEYS:
		problems.append("事実のキーが%d個を超えている（%d個）" % [_MAX_FACT_KEYS, distinct.size()])
	if ep.has("closing"):
		var closing = ep["closing"]
		if not (closing is Dictionary):
			problems.append("closing が辞書でない")
		else:
			if not (closing as Dictionary).has("default"):
				problems.append("closing に default が無い")
			for key in closing:
				if not _is_lines(closing[key]):
					problems.append("closing.%s が空でない文字列の配列でない" % str(key))
				elif key != "default" and key != "request_honored:true" and key != "request_honored:false" 						and not option_keys.has(key):
					problems.append("closing のキー %s が choices にも request_honored にも対応しない" % str(key))
	if _is_lines(ep.get("must_info", [])) and not (ep.get("must_info", []) as Array).is_empty() 			and _is_lines(ep.get("body", [])) and not (ep.get("body", []) as Array).is_empty() 			and (not _is_lines(ep.get("body_unserved", [])) or (ep.get("body_unserved", []) as Array).is_empty()):
		problems.append("must_info と body があるのに body_unserved が無い")
	return problems


## その客の場面の候補（場面の置き場の<客>/*.jsonのid。id順）。置き場が無ければ空配列。
static func episode_candidates(customer_id: String) -> Array:
	var ids := []
	var dir := DirAccess.open(episodes_dir + customer_id)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			ids.append(name.trim_suffix(".json"))
		name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


## その客が日程（week7_regulars.json）で来る順の場面idの配列（日・枠の順）。
## 日程に無い客は空配列。日程に無い客の場面を引くとき（最後の場面）に使う。
static func customer_episode_ids(customer_id: String) -> Array:
	var days: Dictionary = regular_schedule_data().get("days", {})
	var day_keys := days.keys()
	day_keys.sort_custom(func(a, b): return int(a) < int(b))
	var ids := []
	for key in day_keys:
		for entry in days[key]:
			if str(entry.get("regular", "")) == customer_id:
				ids.append(str(entry.get("episode_id", "")))
	return ids


## モブ1種のデータ（日をまたいで変わらないのでフォールバック不要）。
static func mob_data(id: String) -> Dictionary:
	if not _mob_cache.has(id):
		_mob_cache[id] = _load_json(_MOBS_DIR + id + ".json")
	return _mob_cache[id]


## 購入セット1種のデータ（F1 day_overrides.kit・DESIGN.md 10.8.1。日をまたいで
## 変わらないのでフォールバック不要。mob_data()と同じキャッシュパターン）。
static func kit_data(id: String) -> Dictionary:
	if not _kit_cache.has(id):
		_kit_cache[id] = _load_json(_KITS_DIR + id + ".json")
	return _kit_cache[id]


## テスト用：キャッシュを空にする（JSONファイルを書き換えてから読み直したいときに使う。
## 通常のゲーム実行では呼ばない）。
static func clear_cache() -> void:
	_customer_cache.clear()
	_mob_cache.clear()
	_kit_cache.clear()
	_regulars_cache.clear()
	_mob_rules_cache = {}
	_mob_rules_loaded = false
	_episode_cache.clear()
