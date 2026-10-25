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


## 今のキャンペーンid（MorningSaveが保存の封筒に書き、読み込み時に別キャンペーンの
## 保存を弾くために使う）。
static func campaign_id() -> String:
	return _campaign_id


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


## 請求（bills）：{ id, amount, days, reserve, scene, label }。is_collection_day()（3-5）と、
## チンピラの場所代のPAY（システム整理A：scene＝その請求を取り立てる客のid）が読む。
static func bills() -> Array:
	_ensure_loaded()
	return _cache.get("bills", []).duplicate(true)


## 請求1件（idで引く）。無ければ空辞書。
static func bill(id: String) -> Dictionary:
	for b in bills():
		if str(b.get("id", "")) == id:
			return b
	return {}


## 請求の金額（idで引く）。無ければ fallback。場所代の正は week7.json の bills[].amount
## （GameState.RENT_PRICE はここから引く）。
static func bill_amount(id: String, fallback: int = 0) -> int:
	var b := bill(id)
	return int(b["amount"]) if b.has("amount") else fallback


## 「scene がこの客のidで、days に day を含む」請求（その日その客が取り立てる請求）。
## JSONの数値はfloatで読まれるので、日はintに直して比べる（GameState.is_collection_day と同じ）。
static func bills_for_scene(scene_id: String, day: int) -> Array:
	var result := []
	for b in bills():
		if str(b.get("scene", "")) != scene_id:
			continue
		for d in b.get("days", []):
			if int(d) == day:
				result.append(b)
				break
	return result


## 3-1では宣言のみ（total_demand_today()等の日番号直書きの置き換えは3-2/3-5で行う）。
static func day_overrides(day: int) -> Dictionary:
	_ensure_loaded()
	return _cache.get("day_overrides", {}).get(str(day), {})


## 市場の店が押せるようになる日（Day1の朝は店に入れず、2日目以降）。day1_events.gdの
## _market_options()が読む（システム整理Aで day_count >= 2 の直書きから置き換えた）。
static func market_open_from_day() -> int:
	_ensure_loaded()
	return int(_cache.get("market_open_from_day", 2))


## 保存レシピの枠数（フェーズ4・4-7①。RecipeBook／朝の保存の検証が読む）。
static func recipe_slots() -> int:
	_ensure_loaded()
	return int(_cache.get("recipe_slots", 3))


## 修繕基金の設定（フェーズ4・4-9。RepairFund が読む）。{ steps, in_progress_label, stages } の辞書。
## 無い・空のキャンペーンは空辞書＝機能オフ（積み立て行も表示も出ない）。値の整え方は RepairFund。
static func repair_fund() -> Dictionary:
	_ensure_loaded()
	var fund = _cache.get("repair_fund", {})
	return (fund as Dictionary).duplicate(true) if fund is Dictionary else {}


## 指定日の請求（bills）の金額の合計＝その日に払う場所代・水道代。days に指定日を含む請求だけ
## （JSONの数値はfloatで読まれるので int に直して比べる。is_collection_day と同じ）。
## 修繕基金が「翌朝に必ず払う額」を数えるのに使う（今日しか見ない is_collection_day は変えない）。
static func bills_total_on(day: int) -> int:
	var total := 0
	for b in bills():
		for d in b.get("days", []):
			if int(d) == day:
				total += int(b.get("amount", 0))
				break
	return total


## 3-1では宣言のみ（朝の一画面・予報の幅を実装する3-7で使い始める）。
static func forecast() -> Dictionary:
	_ensure_loaded()
	return _cache.get("forecast", {}).duplicate(true)


## 3-1では宣言のみ（結果画面を実装する4-2で使い始める）。
static func goals() -> Dictionary:
	_ensure_loaded()
	return _cache.get("goals", {}).duplicate(true)


## 常連の固定日程のid（4-3から使用。data/schedules/<id>.json。ScheduleData.regular_schedule_data()）。
static func regular_schedule() -> String:
	_ensure_loaded()
	return str(_cache.get("regular_schedule", ""))


## 3-1では宣言のみ（日別ニュースを実装する4-6で使い始める）。
static func news() -> String:
	_ensure_loaded()
	return str(_cache.get("news", ""))


## DMのデータのid（data/dm/<id>.json。UI準備C③。ニュースと同じ置き方）。
static func dm() -> String:
	_ensure_loaded()
	return str(_cache.get("dm", ""))
