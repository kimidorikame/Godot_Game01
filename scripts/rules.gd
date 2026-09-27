extends RefCounted
class_name Rules
## キャンペーン設定（F1・DESIGN.md 10.8.1）。`ScheduleData`と同じ「データだけを持つ
## ファイル」の位置づけで、`data/campaigns/<id>.json`を静的にキャッシュして読む。
##
## 3-1時点では経済値（economy）と仕込み段階（prep_tiers）だけを実際に読みに来る側
## （`GameState`・`Day1Events`）がある。bills/day_overrides/market_open_from_day/
## forecast/goals/regular_schedule/newsは、3-2以降の手順で使い始めるまで「読み取り口
## だけ用意しておく」宣言的な値（DESIGN.md 10.8.1のJSON例をそのまま持つ）。
##
## week7.jsonのdata_overrides."1".mobsはcount:2（3-5でDay1を9杯化した後の目標値）で
## 書かれており、3-1〜3-4の間の実際の挙動（DAY1_MOB_COUNT=4等）とは一致しない。
## day_overridesは3-1では誰も読まないため実害はない（3-5着手時にDay1の実装をこの値に
## 合わせて9杯化する）。

const _CAMPAIGNS_DIR := "res://data/campaigns/"

static var _campaign_id := "week7"
static var _cache: Dictionary = {}
static var _loaded := false


## JSON読み込みの共通処理（ScheduleData._load_jsonと同じ形）。
static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Rules: file not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Rules: failed to open: %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Rules: invalid JSON: %s" % path)
		return {}
	return parsed


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_cache = _load_json(_CAMPAIGNS_DIR + _campaign_id + ".json")
	_loaded = true


static func _economy() -> Dictionary:
	_ensure_loaded()
	return _cache.get("economy", {})


## 読み込むキャンペーンを切り替える（21日版・難度違いを見据えた入口。7日版では未使用）。
static func set_campaign(id: String) -> void:
	_campaign_id = id
	_loaded = false


## テスト用：キャッシュを空にする（week7.jsonを書き換えてから読み直したいときに使う。
## 通常のゲーム実行では呼ばない。ScheduleData.clear_cacheと同じ役割）。
static func clear_cache() -> void:
	_campaign_id = "week7"
	_cache = {}
	_loaded = false


# --- economy（3-1で実際に使用開始） ---

static func price_per_serving() -> int:
	return int(_economy().get("price_per_serving", 45))


static func daily_operating_cost() -> int:
	return int(_economy().get("daily_operating_cost", 80))


static func dashi_price() -> int:
	return int(_economy().get("dashi_price", 16))


static func water_doses() -> int:
	return int(_economy().get("water_doses", 2))


static func demand_table() -> Array:
	return _economy().get("demand_table", []).duplicate(true)


## [[servings, price], ...]の生の数値ペア（表示名は持たない。Day1Events._build_prep_tiers
## がid/labelを重ねて既存のPREP_TIERSの形に組み立て直す）。
static func prep_tiers() -> Array:
	return _economy().get("prep_tiers", []).duplicate(true)


static func initial_money() -> int:
	return int(_economy().get("initial_money", 600))


static func initial_reputation() -> int:
	return int(_economy().get("initial_reputation", 30))


## 評判の翌朝確定：reputation = 現在値*(1-reputation_weight) + 当夜品質*reputation_weight。
## 3-1では宣言のみ（settle_reputation()の書き換えは対象外。値は現行の0.3と一致）。
static func reputation_weight() -> float:
	return float(_economy().get("reputation_weight", 0.3))


## 減点の重ね掛け（濃さ1/5と傷んだ具材、両方に該当するとき2段階下げるか）。
## 3-1では宣言のみ（Judge v2を実装する3-3で使い始める）。
static func penalty_stacking() -> bool:
	return bool(_economy().get("penalty_stacking", false))


static func pot_capacity() -> int:
	return int(_economy().get("pot_capacity", 14))


static func final_day() -> int:
	_ensure_loaded()
	return int(_cache.get("final_day", 7))


## 3-1では宣言のみ（is_collection_day()等の置き換えは3-5で行う）。
static func bills() -> Array:
	_ensure_loaded()
	return _cache.get("bills", []).duplicate(true)


## 3-1では宣言のみ（total_demand_today()等の日番号直書きの置き換えは3-2/3-5で行う）。
static func day_overrides(day: int) -> Dictionary:
	_ensure_loaded()
	return _cache.get("day_overrides", {}).get(str(day), {})


## 3-1では宣言のみ（day1_events.gdのday2_unlocked判定の置き換えは10.9対応の各手順で行う）。
static func market_open_from_day() -> int:
	_ensure_loaded()
	return int(_cache.get("market_open_from_day", 2))


## 3-1では宣言のみ（朝の一画面・予報の幅を実装する3-7で使い始める）。
static func forecast() -> Dictionary:
	_ensure_loaded()
	return _cache.get("forecast", {}).duplicate(true)


## 3-1では宣言のみ（結果画面を実装する4-2で使い始める）。
static func goals() -> Dictionary:
	_ensure_loaded()
	return _cache.get("goals", {}).duplicate(true)


## 3-1では宣言のみ（常連の固定日程を分離する4-3で使い始める）。
static func regular_schedule() -> String:
	_ensure_loaded()
	return str(_cache.get("regular_schedule", ""))


## 3-1では宣言のみ（日別ニュースを実装する4-6で使い始める）。
static func news() -> String:
	_ensure_loaded()
	return str(_cache.get("news", ""))
