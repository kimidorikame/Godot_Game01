extends RefCounted
class_name Ledger
## 帳簿（F4・DESIGN.md 10.8.4）。状態はGameState.ledger（周回を通して蓄積。日次では
## クリアしない＝結果画面（フェーズ4）が周回全体を集計できるようにするため。宣言は
## game_state.gd参照）。ここは記帳・集計の処理だけを持つ静的クラス（状態は持たない）。
##
## GameStateはLedgerを呼ばない（Day1Events・Ingredients等と同じく、複数の記録先を
## まとめるのは受け側＝DebugPanelの役目という既存方針に合わせる）。

## 7日版で使うカテゴリ（DESIGN.md 10.8.4）。kitは3-5（初日セット）、fundは修繕基金
## （フェーズ4）で使い始めるまで宣言のみ（week7.jsonのeconomy宣言と同じ考え方）。
const CATEGORIES := ["daily_cost", "rent", "water", "kit", "prep", "market", "dashi",
	"sale", "fund", "reserve", "release"]


## LedgerEntry { day, phase, category, amount, item, count, unit_price, ref }を1件積む。
## amountは符号付き（支出は負・収入は正）。item/count/unit_price/refは該当しない記帳では
## 既定値（""/0/0/""）のまま渡してよい。
static func record(category: String, amount: int, item: String = "", count: int = 0,
		unit_price: int = 0, ref: String = "") -> void:
	GameState.ledger.append({
		"day": GameState.day_count,
		"phase": GameState.Phase.keys()[GameState.phase],
		"category": category,
		"amount": amount,
		"item": item,
		"count": count,
		"unit_price": unit_price,
		"ref": ref,
	})


## 今日の確保額（旧pending_bills_today）。"reserve"（負額で記帳）と"release"（正額で記帳）
## の合計を反転させることで、既存の「確保→徐々に減って0になる」という表示と同じ値になる。
static func pending_bills_today() -> int:
	var total := 0
	for entry in GameState.ledger:
		if int(entry.get("day", -1)) == GameState.day_count \
				and str(entry.get("category", "")) in ["reserve", "release"]:
			total += int(entry.get("amount", 0))
	return -total


## 今日のカテゴリ別支出（前日成績v2用）。sale（収入）・reserve/release（表示専用の
## 二重計上を避けるため）は含めない。金額は正の値（見せる用）で返す。
static func spend_by_category_today() -> Dictionary:
	var result := {}
	for entry in GameState.ledger:
		var category := str(entry.get("category", ""))
		if int(entry.get("day", -1)) != GameState.day_count:
			continue
		if category == "sale" or category == "reserve" or category == "release":
			continue
		var amount := int(entry.get("amount", 0))
		if amount < 0:
			result[category] = int(result.get(category, 0)) - amount
	return result
