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
const _EPISODES_DIR := "res://data/episodes/"
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
## is_mob / favorite / wanted_tags（基本注文。10.5.1「日によって変えない」）。
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


## 来店場面1つのデータ（data/episodes/<客>/<episode_id>.json）：
## { "id", "customer", "greet", "reactions", "servings" }。無いときは空辞書（エラーを出さない）。
static func episode_data(customer_id: String, episode_id: String) -> Dictionary:
	if customer_id == "" or episode_id == "":
		return {}
	var key := customer_id + "/" + episode_id
	if not _episode_cache.has(key):
		var path := _EPISODES_DIR + customer_id + "/" + episode_id + ".json"
		_episode_cache[key] = _load_json(path) if FileAccess.file_exists(path) else {}
	return _episode_cache[key]


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
