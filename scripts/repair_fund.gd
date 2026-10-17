extends RefCounted
class_name RepairFund
## 修繕基金（フェーズ4・手順4-9。MVP版は4-9④で見直し）。任意の積み立てで、**修繕の対象（看板・棚・雨よけ・
## 名義）ごとに値段を持ち**、プレイヤーが積む先を選ぶ。値段に達した対象が「修繕済み」になる（見た目と営業記録＝
## 表示のみ。売上・需要・評判・料金などゲームの数値を変える効果は付けない）。7日の間に「どれか1つが直せる」
## 程度に収めるため、**1晩に積める額に上限**（nightly_max）を掛ける（最終日にも掛かる）。
##
## **累計は帳簿（fund カテゴリの支出）から導く**＝専用の保存状態は持たない（朝の保存は版6のまま。帳簿の1行
## なので、再挑戦では戻した朝より後の分が消える）。対象ごとの累計は、記帳の ref（対象id）が一致する fund の
## 合計。ref が空・未知の fund（開発中の記帳）は、合計（paid＝Result.repair_paid と同じ）には数えるが、どの
## 対象にも割り当てない。返金不可（引き出し・取り消しの操作は作らない）。目標判定は「現金＋支払済み修繕額」の
## まま（Result）＝投資しても現金目標が不利にならない。
##
## 設定は data/campaigns/<id>.json の repair_fund（Rules.repair_fund()）：
##   steps … 積む額の刻み（固定のボタン。正の整数だけ）
##   nightly_max … 1晩に積める額の合計の上限
##   targets … [{ id, label, price, note, requires:[対象id…] }]（並びが表示順）。label・note は仮の文面。
##             requires の対象がすべて修繕済みになるまで、その対象は積めない（未解放）
##   cup_material_cost … （任意）1杯の材料費の目安を固定したいときの定数。無ければ市場のデータから求める
## 刻み・1晩の上限・対象が1つも無い（または repair_fund 自体が無い）設定は機能オフ。不正な値は無視して整える。
##
## 積めるのは CLOSE の間だけ（今日の売上が入った後の「今日入れるか、明日の仕入れに回すか」の判断）。
## 積める額は、対象の残り・今夜の1晩の上限の残り・安全上限（safe_limit）の**すべて**以内。基金の操作で
## ゲームオーバーにならない（_pay_or_game_over は使わず、払えるときだけ try_pay）。


# ---------------------------------------------------------------- 設定の読み出し

## 刻み（正の整数。重複を除き昇順）。
static func steps() -> Array:
	var result := []
	var raw = Rules.repair_fund().get("steps", [])
	if raw is Array:
		for v in raw:
			if _is_positive_int(v) and not result.has(int(v)):
				result.append(int(v))
	result.sort()
	return result


## 1晩に積める額の合計の上限（正の整数。無い・不正は0＝機能オフ）。
static func nightly_max() -> int:
	var v = Rules.repair_fund().get("nightly_max", 0)
	return int(v) if _is_positive_int(v) else 0


## 修繕の対象 [{ id, label, price, note, requires }]（データの並び順）。id が空・重複、label が空、price が
## 正の整数でないものは除く。requires は存在する他の対象のidだけ残す。
static func targets() -> Array:
	var result := []
	var raw = Rules.repair_fund().get("targets", [])
	if not (raw is Array):
		return result
	var seen := {}
	for item in raw:
		if not (item is Dictionary):
			continue
		var id = (item as Dictionary).get("id")
		var label = (item as Dictionary).get("label")
		if not (id is String) or id == "" or seen.has(id) or not (label is String) or label == "" \
				or not _is_positive_int((item as Dictionary).get("price")):
			continue
		seen[id] = true
		result.append({ "id": id, "label": label, "price": int((item as Dictionary)["price"]),
			"note": str((item as Dictionary).get("note", "")), "requires_raw": (item as Dictionary).get("requires", []) })
	var ids := {}
	for t in result:
		ids[t["id"]] = true
	for t in result:
		var requires := []
		if t["requires_raw"] is Array:
			for r in t["requires_raw"]:
				if r is String and ids.has(r) and r != t["id"] and not requires.has(r):
					requires.append(r)
		t["requires"] = requires
		t.erase("requires_raw")
	return result


## 機能がオンか（刻み・1晩の上限・対象がそろっている）。
static func enabled() -> bool:
	return not steps().is_empty() and nightly_max() > 0 and not targets().is_empty()


static func _is_positive_int(v) -> bool:
	return (v is int or v is float) and float(v) == floorf(float(v)) and int(v) > 0


# ---------------------------------------------------------------- 累計と対象の状態（帳簿から導く）

static func target(id: String) -> Dictionary:
	for t in targets():
		if t["id"] == id:
			return t
	return {}


## 支払済みの修繕額（全体の累計）。帳簿の fund の合計＝Result.repair_paid と同じ計算（二重に作らない）。
## ref が空・未知の記帳も含む。
static func paid() -> int:
	return Result.repair_paid(GameState.ledger)


## 対象ごとの累計＝記帳の ref がその対象idの fund の合計（正の値）。
static func target_paid(id: String) -> int:
	var total := 0
	for entry in GameState.ledger:
		if entry is Dictionary and str(entry.get("category", "")) == "fund" and str(entry.get("ref", "")) == id:
			total -= int(entry.get("amount", 0))
	return maxi(total, 0)


## どの対象にも割り当てられない fund の合計（ref が空・未知）。
static func unassigned_paid() -> int:
	var assigned := 0
	for t in targets():
		assigned += target_paid(t["id"])
	return maxi(paid() - assigned, 0)


## 対象の残り（値段 − 累計。0未満は0）。
static func remaining(id: String) -> int:
	var t := target(id)
	return maxi(int(t.get("price", 0)) - target_paid(id), 0) if not t.is_empty() else 0


static func is_repaired(id: String) -> bool:
	var t := target(id)
	return not t.is_empty() and target_paid(id) >= int(t["price"])


## 修繕済みの対象のid（データの並び順）。
static func repaired_ids() -> Array:
	var ids := []
	for t in targets():
		if is_repaired(t["id"]):
			ids.append(t["id"])
	return ids


## 積めるようになっているか（requires の対象がすべて修繕済み）。
static func unlocked(id: String) -> bool:
	var t := target(id)
	if t.is_empty():
		return false
	for r in t["requires"]:
		if not is_repaired(r):
			return false
	return true


## 対象の状態 { id, label, price, paid, repaired, locked }。
static func target_state(id: String) -> Dictionary:
	var t := target(id)
	if t.is_empty():
		return {}
	return { "id": id, "label": t["label"], "price": t["price"], "paid": target_paid(id),
		"repaired": is_repaired(id), "locked": not unlocked(id) }


## 最初の「未修繕で積める」対象のid（積む先の既定）。無ければ空文字。
static func first_open_target() -> String:
	for t in targets():
		if not is_repaired(t["id"]) and unlocked(t["id"]):
			return t["id"]
	return ""


## 全対象が修繕済みか（積み立ての完了）。
static func complete() -> bool:
	if not enabled():
		return false
	for t in targets():
		if not is_repaired(t["id"]):
			return false
	return true


## 修繕済みの対象の名前（"・"区切り。無ければ空文字）。
static func repaired_labels() -> String:
	var names := PackedStringArray()
	for id in repaired_ids():
		names.append(str(target(id)["label"]))
	return "・".join(names)


## 各対象の進捗の文（サマリー・結果画面・状態の文で共有）。
## 例：手書きの看板 150/150 修繕済み／棚 40/200／雨よけ 0/200／屋台を自分の名義に 0/600（未解放）
static func progress_text() -> String:
	var parts := PackedStringArray()
	for t in targets():
		var s := target_state(t["id"])
		var text := "%s %d/%d" % [s["label"], s["paid"], s["price"]]
		if s["repaired"]:
			text += " 修繕済み"
		elif s["locked"]:
			text += "（未解放）"
		parts.append(text)
	return "／".join(parts)


## 修繕できた瞬間の一行（積む前→後で新しく修繕済みになった対象。label を使った固定の言い回し。note は
## 将来の差し替え用にデータへ残す）。増えていなければ空文字。
static func repaired_message(before_ids: Array, after_ids: Array) -> String:
	var names := PackedStringArray()
	for id in after_ids:
		if not before_ids.has(id):
			names.append(str(target(id).get("label", id)))
	return "修繕できた：%s" % "・".join(names) if not names.is_empty() else ""


# ---------------------------------------------------------------- 1晩の上限

## 今日（day_count）に積んだ額の合計（fund の記帳の合計）。
static func paid_tonight() -> int:
	var total := 0
	for entry in GameState.ledger:
		if entry is Dictionary and str(entry.get("category", "")) == "fund" \
				and int(entry.get("day", -1)) == GameState.day_count:
			total -= int(entry.get("amount", 0))
	return maxi(total, 0)


## 今夜あと積める額（1晩の上限 − 今夜積んだ額）。
static func nightly_remaining() -> int:
	return maxi(nightly_max() - paid_tonight(), 0)


# ---------------------------------------------------------------- 安全上限（毎日、全客に味1＋具2の椀を出せるだけ残す）

## 1杯の材料費の目安＝味1個＋具2個ぶんの素材の代表単価。市場の品目（*_goods()）の単価（price/count。濃縮だしは
## 除く）を、味の素材・具の素材それぞれの中央値で求める（価格を変えれば追従する）。data に cup_material_cost
## （正の整数）があればそれを優先する。
static func cup_material_cost() -> int:
	var fixed = Rules.repair_fund().get("cup_material_cost", 0)
	if _is_positive_int(fixed):
		return int(fixed)
	var flavors := []
	var toppings := []
	var goods := Day1Events.produce_goods() + Day1Events.meat_wholesale_goods() + Day1Events.dry_goods_goods() \
		+ Day1Events.tofu_noodles_goods() + Day1Events.seafood_goods() + Day1Events.scraps_goods()
	for good in goods:
		if not good.has("count") or int(good["count"]) <= 0:
			continue
		var unit := float(good["price"]) / float(good["count"])
		var item := str(good.get("item", good.get("id", "")))
		if Ingredients.is_topping(item):
			toppings.append(unit)
		elif Ingredients.is_flavor(item):
			flavors.append(unit)
	return int(ceilf(_median(flavors))) + 2 * int(ceilf(_median(toppings)))


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := int(sorted.size() * 0.5)
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) / 2.0


## 評判 reputation のときの総需要の中心（Rules.demand_table()。乱数を引かない）。日の固定需要
## （day_overrides.fixed_demand）があればそれ。
static func demand_center(reputation: int, day: int) -> int:
	var overrides := Rules.day_overrides(day)
	if overrides.has("fixed_demand"):
		return int(overrides["fixed_demand"])
	for row in Rules.demand_table():
		if reputation >= int(row[0]):
			return int(row[1])
	return 7


## 翌日の見込み杯数＝現在の評判で引く総需要の中心と、今日の計画の需要の中心（today_plan.demand_center）の
## 大きいほう。今日の計画の中心が無いとき（再挑戦直後など）は、評判から引く値だけを使う。
static func expected_cups_tomorrow() -> int:
	var from_reputation := demand_center(GameState.reputation, GameState.day_count + 1)
	var plan: Dictionary = GameState.today_plan
	var today_center := int(plan.get("demand_center", -1)) if int(plan.get("day", -1)) == GameState.day_count else -1
	return maxi(from_reputation, today_center)


## 見込み杯数に足りる最小の仕込み段階の価格（届く段階が無ければ最大の段階。段階が無ければ0）。
static func prep_price_for(cups: int) -> int:
	var tiers := Rules.prep_tiers()
	var price := 0
	for pair in tiers:
		if pair is Array and (pair as Array).size() >= 2:
			price = int(pair[1])
			if int(pair[0]) >= cups:
				return price
	return price


## 翌日の確保額の内訳 { operating, bills, prep, materials, expected_cups, total }。今日が最終日なら翌日が
## 無いので全部0。
static func next_day_reserve() -> Dictionary:
	if GameState.is_final_day():
		return { "operating": 0, "bills": 0, "prep": 0, "materials": 0, "expected_cups": 0, "total": 0 }
	var cups := expected_cups_tomorrow()
	var operating: int = GameState.DAILY_OPERATING_COST
	var bills := Rules.bills_total_on(GameState.day_count + 1)
	var prep := prep_price_for(cups)
	var materials := cups * cup_material_cost()
	return { "operating": operating, "bills": bills, "prep": prep, "materials": materials,
		"expected_cups": cups, "total": operating + bills + prep + materials }


## 安全上限＝使える現金（所持金−今日の確保額）から翌日の確保額（運営費・翌日の請求・翌日の仕込み・翌日の
## 材料費）を引いた額（0未満は0）。毎日、翌日に全客へ味1＋具2の椀を出せるだけを残す。最終日は翌日が無い
## ので使える現金そのもの（1晩の上限は別に掛かる）。
static func safe_limit() -> int:
	return maxi(Ledger.usable_cash() - int(next_day_reserve()["total"]), 0)


# ---------------------------------------------------------------- 積む

## その対象に今積める最大の額（対象の残り・今夜の上限の残り・安全上限の最小。刻みは考えない）。
static func max_contribution(target_id: String) -> int:
	if not enabled() or target(target_id).is_empty() or is_repaired(target_id) or not unlocked(target_id):
		return 0
	return mini(mini(remaining(target_id), nightly_remaining()), safe_limit())


## この額をこの対象に今積めるか（機能オン・CLOSE・刻みのどれか・対象が未修繕で解放済み・
## 対象の残り／今夜の上限の残り／安全上限のすべて以内）。
static func can_contribute(target_id: String, amount: int) -> bool:
	return enabled() and GameState.phase == GameState.Phase.CLOSE and steps().has(amount) \
			and amount <= max_contribution(target_id)


## 積む。積めるときだけ、所持金から払い、帳簿に fund を負額で1行（ref＝対象id）記帳して true。積めない
## とき（CLOSE でない・機能オフ・刻みに無い額・対象が不正／修繕済み／未解放・上限超え）は何も変えず false。
## 返金なし。ゲームオーバーは呼ばない（払えるときだけ try_pay）。乱数は使わない。
static func contribute(target_id: String, amount: int) -> bool:
	if not can_contribute(target_id, amount) or not GameState.try_pay(amount):
		return false
	Ledger.record("fund", -amount, "repair_fund", 0, 0, target_id)
	return true
