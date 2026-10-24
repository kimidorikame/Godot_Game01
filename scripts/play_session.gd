extends Node
class_name PlaySession
## 遊びの進行を持つ共有部品（UI準備A。DESIGN.md「設計上の確定事項」最後の項目の分離）。
##
## DebugPanel（検証用）と本番UIが、**同じゲーム処理を1か所から使う**ための部品。画面（ノード・ボタン・
## ラベル）には一切触れない。UIは「操作を呼ぶ」「問いを読む」「changed を受けて描き直す」だけにする。
## FlowController と同じく、画面のシーンの子ノードとして持つ（autoload にはしない）。FlowController は
## この部品が自分で作って持つ（画面のシーンは PlaySession を1つ持てば足りる）。
##
## 移行中（UI準備A）：処理は DebugPanel から塊ごとに移している。移した操作は、末尾で changed を出す
## （今の DebugPanel の _refresh() と同じ考え方。UIは changed を受けて全体を描き直す）。
## 通知の粒度は1本（changed）。種類ごとのシグナルは作らない。

## 状態が変わったことをUIへ知らせる。各操作の末尾で1回出す（途中の経過では出さない）。
signal changed()

## フェーズの一方向遷移と、フェーズ内の Event 再生（runner）を持つ。
var flow: FlowController = null


func _init() -> void:
	flow = FlowController.new()
	flow.name = "FlowController"
	add_child(flow)


## 状態が変わったことを知らせる（UIは全体を描き直す）。
func notify_changed() -> void:
	changed.emit()


# --- 状態（ゲームの意味を持つもの） ---

## 市場で今どの店の中にいるか（例: "produce"）。空文字なら市場のトップ（店の選択）にいる。
## 仕込みに入るたびにリセットする（_set_runner_for_phase）。
var market_shop := ""
## 水場（水道代）にもう寄ったか。仕込みに入るたびにリセットする。
var market_visited_water := false
## ゲームオーバーの理由の文。_set_runner_for_phase(GAME_OVER) が読んで消費する（一度きり）。
var game_over_reason := ""


# --- 予算（共通） ---

## 予算の3つ：残金・確保（まだ払っていない請求）・使える現金。
func budget() -> Dictionary:
	return { "money": GameState.money, "reserved": Ledger.pending_bills_today(), "usable": Ledger.usable_cash() }


# --- 市場・仕込み（UI準備A②） ---

## 市場の店の一覧：[{ id, label, enabled }]。市場の画面（MARKET）にいるときだけ入っている（開いているかは
## 仕込みに入った瞬間に固定された値＝Day1Events._market_options）。市場にいなければ空。
func market_stalls() -> Array:
	var cur = _current_event()
	if cur is Dictionary and str(cur.get("type", "")) == "MARKET":
		return (cur.get("options", []) as Array).duplicate(true)
	return []


## 店名から、その店の商品リストを引く。未実装の店は空配列。
static func shop_goods(shop: String) -> Array:
	match shop:
		"produce":
			return Day1Events.produce_goods()
		"meat_wholesale":
			return Day1Events.meat_wholesale_goods()
		"dry_goods":
			return Day1Events.dry_goods_goods()
		"tofu_noodles":
			return Day1Events.tofu_noodles_goods()
		"seafood":
			return Day1Events.seafood_goods()
		"scraps":
			return Day1Events.scraps_goods()
		_:
			return []


## 店の商品を、画面が使う形で返す（文面は作らない）。
## [{ id, item, label, price, count, unit_price, fresh, damaged, affordable, kind }]
##   count／unit_price：購入1回で増える個数と単価（個数を持たない商品＝だしは 0）。
##   fresh／damaged：その品目の在庫の新鮮／傷んだ数（だしは濃縮だしの手持ち数を fresh に入れ、damaged は 0）。
##   kind："seasoning"（味付け）／"topping"（具）／""（どちらでもない。だしなど）。
func shop_view(shop: String) -> Array:
	var out: Array = []
	for good in shop_goods(shop):
		var id := str(good.get("id", ""))
		var item := str(good.get("item", ""))
		var price := int(good.get("price", 0))
		var count := int(good.get("count", 0)) if good.has("count") else 0
		var kind := ""
		var fresh := 0
		var damaged := 0
		if item == "":
			if id == "dashi":
				fresh = GameState.dashi_units
		else:
			fresh = GameState.fresh_count(item)
			damaged = GameState.damaged_count(item)
			if Ingredients.is_topping(item):
				kind = "topping"
			elif Ingredients.is_flavor(item):
				kind = "seasoning"
		out.append({ "id": id, "item": item, "label": str(good.get("label", id)), "price": price,
			"count": count, "unit_price": (int(price / count) if count > 0 else price),
			"fresh": fresh, "damaged": damaged, "affordable": GameState.money >= price, "kind": kind })
	return out


## 仕込み3段階：[{ id, label, servings, price, affordable }]。段階の選択（PREP_TIER）にいるときはその
## Event の選択肢、いなければ設定の3段階。
func prep_tiers() -> Array:
	var tiers: Array = Day1Events.prep_tier_options()
	var cur = _current_event()
	if cur is Dictionary and str(cur.get("type", "")) == "PREP_TIER":
		tiers = cur.get("options", [])
	var out: Array = []
	for tier in tiers:
		var price := int(tier.get("price", 0))
		out.append({ "id": str(tier.get("id", "")), "label": str(tier.get("label", "")),
			"servings": int(tier.get("servings", 0)), "price": price, "affordable": GameState.money >= price })
	return out


## 今日、鍋の素（仕込みの段階）をもう買ったか。帳簿の "prep" が今日あるかで見る（買うと一度きり）。
func prep_tier_paid() -> bool:
	return int(Ledger.spend_by_category_today().get("prep", 0)) > 0


## いま MARKET が現在の Event か（options を持つ WAITING_INPUT の一種）。
func is_in_market() -> bool:
	var cur = _current_event()
	return cur is Dictionary and cur.get("type", "") == "MARKET"


## いま PREP_TIER（仕込み3段階の選択）が現在の Event か。
func is_in_prep_tier() -> bool:
	var cur = _current_event()
	return cur is Dictionary and cur.get("type", "") == "PREP_TIER"


## 市場を出られるか。訪問済み・未訪問に関わらず、市場の画面にいれば常に出られる（水汲み忘れで詰まらせない）。
func can_exit_market() -> bool:
	return is_in_market()


## 市場の店を選ぶ（店の中へ入る）。EventRunner には触れない。
func select_stall(id: String) -> void:
	match id:
		"produce", "meat_wholesale", "dry_goods", "tofu_noodles", "seafood", "scraps":
			market_shop = id
		_:
			pass
	changed.emit()


## 店の商品を買う。店を出ずその場に留まる（何度でも買える）。所持金が足りなければ何もしない。
func buy_item(shop: String, id: String) -> void:
	for good in shop_goods(shop):
		if str(good.get("id", "")) == id:
			var price: int = int(good.get("price", 0))
			if id == "dashi":
				if GameState.money >= price:
					GameState.apply_money(-price)
					GameState.buy_dashi()
					Ledger.record("dashi", -price, "dashi", 1, price)
			elif GameState.money >= price:
				var item = good.get("item", id)
				var count: int = int(good.get("count", 1))
				var unit_price: int = int(price / count) if count > 0 else price
				GameState.apply_money(-price)
				GameState.add_inventory(item, count, unit_price)
				Ledger.record("market", -price, str(item), count, unit_price)
			break
	changed.emit()


## 仕込みの段階を選ぶ（支払って、残りの仕込みの列をその場で組み直す）。所持金が足りなければ何もしない。
## 差し替え後の列の先頭は効果の無いTEXT（EventRunner の仕様で先頭は適用されない）。
func choose_prep_tier(tier_id: String) -> void:
	var tier := Day1Events.prep_tier_by_id(tier_id)
	var price: int = int(tier.get("price", 0))
	if GameState.money < price:
		return
	GameState.apply_money(-price)
	Ledger.record("prep", -price, tier_id, 0, price)
	flow.set_runner(Day1Events.prep_after_tier_events(tier, false))
	changed.emit()


## [市場に戻る]（店から出る）。EventRunner には触れない。
func leave_shop() -> void:
	market_shop = ""
	changed.emit()


## 水場を訪れる（水道代の支払いのみ。[市場を出る]で自動で1回だけ呼ばれる）。徴収日だけ払う。
## 水道代が払えずゲームオーバーになったら false（呼び出し元は先へ進めないこと）。
func visit_water_stall() -> bool:
	if GameState.is_collection_day():
		if not pay_or_game_over(GameState.WATER_PRICE, "water"):
			return false
		# WAKEで水道代も確保に含めてあるので、実際に払ったこの瞬間にreleaseする。
		Ledger.record("release", GameState.WATER_PRICE)
	market_visited_water = true
	return true


## [市場を出る]の前半：水場に未訪問なら自動で訪れて水道代を払う。払えずゲームオーバーなら false
## （先へ進めない）。**UI準備A②の暫定**：true のとき、呼び出し側（DebugPanel）が続けて
## 「入力完了して先へ進む」を行う。その処理（Eventの受け側）を移す③で、ここへ吸収する。
func exit_market() -> bool:
	if not market_visited_water:
		if not visit_water_stall():
			return false
	return true


# --- 支払いとゲームオーバー ---

## 義務的な支払い（水道代・場所代・運営費）。払えれば true。払えなければ支払いを実行せず
## （所持金はマイナスにならない）ゲームオーバーにして false を返す。
## category（"daily_cost"/"water"/"rent"/"kit"）を渡すと、払えたときだけ帳簿に記帳する
## （義務的な支払いの共有入口なので、記帳もここに一本化する）。省略（""）は記帳しない。
func pay_or_game_over(amount: int, category: String = "") -> bool:
	if GameState.try_pay(amount):
		if category != "":
			Ledger.record(category, -amount)
		return true
	game_over("所持金が足りない。支払えない（必要 ¥%d／所持 ¥%d）。" % [amount, GameState.money])
	return false


## ゲームオーバーにする（理由を持ち越して GAME_OVER へ）。
func game_over(reason: String) -> void:
	game_over_reason = reason
	flow.force_phase(GameState.Phase.GAME_OVER)


# --- 内部 ---

## いまの Event（runner が無ければ null）。
func _current_event() -> Variant:
	if flow.runner == null:
		return null
	return flow.runner.current()
