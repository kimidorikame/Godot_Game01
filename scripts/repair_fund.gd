extends RefCounted
class_name RepairFund
## 修繕基金（フェーズ4・手順4-9。DESIGN.md 10.7）。任意の積み立てで、累計150／300／600で屋台の段階が
## 上がる（見た目と営業記録＝表示のみ。売上・需要・評判・料金などゲームの数値を恒久的に変える効果は
## 付けない）。**累計は帳簿（fund カテゴリの支出）から導く**＝専用の保存状態は持たない（朝の保存は
## 版6のまま。帳簿の1行なので再挑戦では戻した朝より後の分が消える）。返金不可（引き出し・取り消しの
## 操作は作らない）。目標判定は「現金＋支払済み修繕額」のまま（Result）＝投資しても現金目標が不利にならない。
##
## 設定は data/campaigns/<id>.json の repair_fund（Rules.repair_fund()）：
##   steps … 積む額の刻み（固定のボタン。正の整数だけ）
##   stages … [{ id, total, label, note }]（total は累計の境目）。label・note は仮の文面
##   in_progress_label … 最初の段階に届かないうちの呼び名（サマリー用の仮ラベル）
## **段階の境目（total）は、最小の刻み（week7 では25）の倍数にする**：刻みだけで境目ぴったりに届き、
## 最終段階（上限）までの残りも刻みで埋められるようにするため（tests/repair_fund_test.gd が検査する）。
## 刻み・段階が1つも無い（または repair_fund 自体が無い）設定は機能オフ。不正な値は無視して整える。
##
## 積めるのは CLOSE の間だけ（今日の売上が入った後の「今日入れるか、明日の仕入れに回すか」の判断）。
## 上限（safe_limit）で、積んだせいで翌朝の運営費が払えない・翌日に何も仕込めない状態を作らない。
## 基金の操作でゲームオーバーにはならない（_pay_or_game_over は使わず、払えるときだけ try_pay）。


## 刻み（正の整数。重複を除き昇順）。
static func steps() -> Array:
	var result := []
	var raw = Rules.repair_fund().get("steps", [])
	if raw is Array:
		for v in raw:
			if (v is int or v is float) and float(v) == floorf(float(v)) and int(v) > 0 and not result.has(int(v)):
				result.append(int(v))
	result.sort()
	return result


## 段階 [{ id, total, label, note }]（total が正の整数で label が空でないものだけ。total の昇順で、
## 同じ total は先のものを残す）。
static func stages() -> Array:
	var result := []
	var raw = Rules.repair_fund().get("stages", [])
	if raw is Array:
		for item in raw:
			if not (item is Dictionary):
				continue
			var total = (item as Dictionary).get("total")
			var label = (item as Dictionary).get("label")
			if (total is int or total is float) and float(total) == floorf(float(total)) and int(total) > 0 \
					and label is String and label != "":
				var exists := false
				for s in result:
					exists = exists or int(s["total"]) == int(total)
				if not exists:
					result.append({ "id": str((item as Dictionary).get("id", "")), "total": int(total),
						"label": label, "note": str((item as Dictionary).get("note", "")) })
	result.sort_custom(func(a, b): return int(a["total"]) < int(b["total"]))
	return result


## 機能がオンか（刻みと段階が1つ以上ある）。
static func enabled() -> bool:
	return not steps().is_empty() and not stages().is_empty()


## 最初の段階に届かないうちの呼び名（仮ラベル）。
static func in_progress_label() -> String:
	var label = Rules.repair_fund().get("in_progress_label", "")
	return label if label is String and label != "" else "積み立て中"


## 支払済みの修繕額（累計）。帳簿の fund の合計＝Result.repair_paid と同じ計算（二重に作らない）。
static func paid() -> int:
	return Result.repair_paid(GameState.ledger)


## 累計 paid が届いている最後の段階の番号（0起点。まだ最初の段階に届かなければ -1）。
static func stage_index(total_paid: int) -> int:
	var index := -1
	var all := stages()
	for i in range(all.size()):
		if total_paid >= int(all[i]["total"]):
			index = i
	return index


## 累計 paid の段階の辞書（届いていなければ空辞書）。
static func stage(total_paid: int) -> Dictionary:
	var index := stage_index(total_paid)
	return (stages()[index] as Dictionary).duplicate() if index >= 0 else {}


## 屋台の呼び名（届いた段階の label。最初の段階に届かなければ in_progress_label）。
static func stage_label(total_paid: int) -> String:
	var s := stage(total_paid)
	return str(s["label"]) if not s.is_empty() else in_progress_label()


## 次の段階までの残り（最終段階に届いていれば 0）。
static func remaining_to_next(total_paid: int) -> int:
	for s in stages():
		if total_paid < int(s["total"]):
			return int(s["total"]) - total_paid
	return 0


## 最終段階（これ以上積めない上限）までの残り。
static func remaining_to_cap(total_paid: int) -> int:
	var all := stages()
	if all.is_empty():
		return 0
	return maxi(int((all[all.size() - 1] as Dictionary)["total"]) - total_paid, 0)


## 最終段階に届いたか（それ以上は積めない＝無駄に現金を減らさない。表示は「完了」）。
static func complete() -> bool:
	return enabled() and remaining_to_cap(paid()) == 0


## 一番安い仕込みの価格（Rules.prep_tiers の [杯数, 価格] の最小の価格）。
static func min_prep_price() -> int:
	var lowest := -1
	for pair in Rules.prep_tiers():
		if pair is Array and (pair as Array).size() >= 2:
			var price := int(pair[1])
			if lowest < 0 or price < lowest:
				lowest = price
	return maxi(lowest, 0)


## 安全上限＝今日積める最大額。使える現金（所持金−今日の確保額）から、翌朝に必ず払う額（運営費＋翌日が
## 徴収日なら請求の合計）と、翌日の最小の仕込み額を引いた額（0未満は0）。最終日は翌日が無いので
## 使える現金そのもの（確保が無ければ所持金と同じ）。積んでも翌朝の運営費が払え、翌日に最小の仕込みが
## 買えることを保証する（基金の操作でゲームオーバーにならない）。
static func safe_limit() -> int:
	var cash := Ledger.usable_cash()
	if GameState.is_final_day():
		return maxi(cash, 0)
	var required: int = GameState.DAILY_OPERATING_COST + Rules.bills_total_on(GameState.day_count + 1)
	return maxi(cash - required - min_prep_price(), 0)


## この額を今積めるか（機能オン・CLOSE・刻みのどれか・安全上限以内・最終段階までの残り以内）。
static func can_contribute(amount: int) -> bool:
	return enabled() and GameState.phase == GameState.Phase.CLOSE and steps().has(amount) \
			and amount <= safe_limit() and amount <= remaining_to_cap(paid())


## 積む。積めるときだけ、所持金から払い、帳簿に fund を負額で1行記帳して true。積めないとき
## （CLOSE でない・機能オフ・刻みに無い額・上限超え・最終段階到達後）は何も変えず false。
## 返金なし。ゲームオーバーは呼ばない（払えるときだけ try_pay）。乱数は使わない。
static func contribute(amount: int) -> bool:
	if not can_contribute(amount) or not GameState.try_pay(amount):
		return false
	Ledger.record("fund", -amount, "repair_fund")
	return true
