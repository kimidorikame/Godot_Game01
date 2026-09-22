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
const _CUSTOMERS_DIR := "res://data/customers/"
const _MOBS_DIR := "res://data/mobs/"

# 日ごとの枠構成データが無い日（Day3〜7）は "1"（Day1）へフォールバックする
# （CURRENT_SPEC.md §9-C。今回のタスクで実装するフォールバックの唯一の場所）。
const _FALLBACK_DAY := "1"

static var _day_schedule_all: Dictionary = {}
static var _day_schedule_loaded := false
static var _customer_cache: Dictionary = {}   # id(String) -> 生のJSON全体（Dictionary）
static var _mob_cache: Dictionary = {}        # id(String) -> 生のJSON全体（Dictionary）


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


## テスト用：キャッシュを空にする（JSONファイルを書き換えてから読み直したいときに使う。
## 通常のゲーム実行では呼ばない）。
static func clear_cache() -> void:
	_day_schedule_all = {}
	_day_schedule_loaded = false
	_customer_cache.clear()
	_mob_cache.clear()
