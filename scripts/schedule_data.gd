extends RefCounted
class_name ScheduleData
## 日別スケジュール・客・モブのデータをJSONから読む専用ファイル（`Ingredients`と同じ
## 「データだけを持つファイル」の位置づけ。DESIGN.md「シナリオデータと処理を分離する」方針）。
##
## 読み込んだJSONは静的にキャッシュする（ファイルは日中に書き換わらない前提。
## `Ingredients`の定数キャッシュと同じ考え方。プロセスを再起動しない限りは
## 一度読めば十分＝接客のたびにディスクI/Oしない）。
##
## day_schedule.json のモデル（CURRENT_SPEC.md §9-C）：
##   { "<day>": { "slots": [ { "name", "main" or "main_pool", "mob": bool }, ... ] } }
## customers/<id>.json のモデル：
##   { "is_mob", "favorite", "days": { "<day>": { "greet", "wanted_tags", "reactions", "servings" } } }
##   delivery_man.json だけ例外的に "days" を持たない最小限（is_mob/favoriteのみ。
##   会話配列は _delivery_man_events() 側にGDScriptのまま残す）。
## mobs/<id>.json のモデル：
##   { "is_mob", "greet", "reactions", "wanted_tags" }（日をまたいで変わらない＝days無し）。

const _DAY_SCHEDULE_PATH := "res://data/day_schedule.json"
# 4-3：常連の固定日程（week7.jsonのregular_schedule＝"week7_regulars"から引く）と、
# モブの抽選ルール（既定＋日別の上書き）。DESIGN.md 10.8.1。
const _SCHEDULES_DIR := "res://data/schedules/"
const _MOB_RULES_PATH := "res://data/schedules/mob_rules.json"
const _CUSTOMERS_DIR := "res://data/customers/"
const _MOBS_DIR := "res://data/mobs/"
const _KITS_DIR := "res://data/kits/"

# 日ごとの枠構成データが無い日（Day3〜7）は "1"（Day1）へフォールバックする
# （CURRENT_SPEC.md §9-C。今回のタスクで実装するフォールバックの唯一の場所）。
const _FALLBACK_DAY := "1"

static var _day_schedule_all: Dictionary = {}
static var _day_schedule_loaded := false
static var _customer_cache: Dictionary = {}   # id(String) -> 生のJSON全体（Dictionary）
static var _mob_cache: Dictionary = {}        # id(String) -> 生のJSON全体（Dictionary）
static var _kit_cache: Dictionary = {}        # id(String) -> 生のJSON全体（Dictionary）
static var _regulars_cache: Dictionary = {}   # 常連の固定日程（schedule id -> 生のJSON全体）
static var _mob_rules_cache: Dictionary = {}
static var _mob_rules_loaded := false


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


## 指定日の枠構成（{"slots": [...]}）。day_schedule.json に無い日は"1"（Day1）へ
## フォールバックする（Day3〜7はこれで現状のDay1固定並びと同じ見た目になる）。
static func day_schedule(day: int) -> Dictionary:
	if not _day_schedule_loaded:
		_day_schedule_all = _load_json(_DAY_SCHEDULE_PATH)
		_day_schedule_loaded = true
	var key := str(day)
	if _day_schedule_all.has(key):
		return _day_schedule_all[key]
	return _day_schedule_all.get(_FALLBACK_DAY, {})


## 常連の固定日程（DESIGN.md 10.5.1・21枠）。week7.jsonのregular_schedule（schedule id）の
## data/schedules/<id>.json全体：{ "days": { "<day>": [ { "slot": 枠名, "regular": 客id }, ... ] } }。
## 枠は辞書（後の手順で episode_id などを足せる）。無い・読めないときは空辞書。
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


## 常連の固定日程とモブの抽選ルールから、指定日の枠構成を、旧day_schedule.jsonと同じ形
## （{"slots": [ { "name", "main", "mob" }, ... ]}）で組み立てる（4-3の互換層。
## customer_schedule()・Forecast・DayPlannerを変えないため。4-4でDayPlanが常連の日程を
## 直接読む形になったら、この関数とday_schedule()の旧経路ごと消す）。
## 日程の定義が無い日（Day8以降）は、常連もモブ規則も"1"（Day1）へフォールバックする。
## モブの値は、false（その枠はモブなし）または {"pool": [...]}（その枠で抽選する種類）。
static func compose_day_schedule(day: int) -> Dictionary:
	var days: Dictionary = regular_schedule_data().get("days", {})
	var key := str(day)
	if not days.has(key):
		key = _FALLBACK_DAY
	var rules := mob_rules_data()
	var default_rule: Dictionary = rules.get("default", {})
	var default_pool: Array = default_rule.get("pool", [])
	var default_slots: Dictionary = default_rule.get("slots", {})
	var day_rules: Dictionary = (rules.get("days", {}) as Dictionary).get(key, {})
	var slots := []
	for entry in days.get(key, []):
		var slot_name := str(entry.get("slot", ""))
		var mob = false
		if day_rules.has(slot_name):
			var rule = day_rules[slot_name]
			if rule is Dictionary:
				mob = (rule as Dictionary).duplicate(true)
			elif bool(rule):
				mob = { "pool": default_pool.duplicate() }
		elif bool(default_slots.get(slot_name, false)):
			mob = { "pool": default_pool.duplicate() }
		slots.append({ "name": slot_name, "main": str(entry.get("regular", "")), "mob": mob })
	return { "slots": slots }


## 客1人ぶんのデータ。トップレベル（is_mob/favoriteなど。"days"を除く）と、その日の内容
## （days[day]）をマージして返す。該当日が無ければ、その客データの中で"1"（1日目）へ
## フォールバックする（day_schedule.json側のフォールバックとは別に、客データ自身も
## 独立してフォールバックする。例：Day3でチンピラが再登場しても、thug.jsonに"3"が
## 無ければ"1"の会話を使う）。
## "days"を持たない客（delivery_manの最小限JSON。is_mob/favorite/wanted_tagsを
## トップレベルに直接持つ）は、そのままトップレベルの内容だけを返す（greet/reactions/
## servingsは持たない＝呼び出し側は_delivery_man_events()で別途組み立てる）。
static func customer_data(id: String, day: int) -> Dictionary:
	if not _customer_cache.has(id):
		_customer_cache[id] = _load_json(_CUSTOMERS_DIR + id + ".json")
	var raw: Dictionary = _customer_cache[id]
	if raw.is_empty():
		return {}
	var result := {}
	for k in raw:
		if k != "days":
			result[k] = raw[k]
	var days: Dictionary = raw.get("days", {})
	if not days.is_empty():
		var key := str(day)
		var day_data: Dictionary = days.get(key, days.get(_FALLBACK_DAY, {}))
		for k in day_data:
			result[k] = day_data[k]
	return result


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
	_day_schedule_all = {}
	_day_schedule_loaded = false
	_customer_cache.clear()
	_mob_cache.clear()
	_kit_cache.clear()
	_regulars_cache.clear()
	_mob_rules_cache = {}
	_mob_rules_loaded = false
