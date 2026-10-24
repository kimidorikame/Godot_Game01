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
## 今日はクズ野菜ベースか（所持金がベース代に満たないので端材屋へ回った日）。仕込みに入る瞬間に1回だけ決める。
var scraps_base := false


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


## 今日の鍋の素。{ paid, tier_id, label, servings, scraps }（読むだけ。本番UIの市場の店一覧に
## 「鍋の素 中11杯 買った」と出すため）。
##   paid：段階の購入（帳簿の "prep"）が今日あるか。
##   tier_id／label／servings：買った段階。買っていなければ "" ／ "" ／ 0。
##   scraps：クズ野菜ベースの日（所持金が一番安い仕込みにも満たず、端材屋へ回った日）に true。このとき
##     支払いは無く（paid は false）、鍋の素は小仕込み相当（8杯）の自動のもの。仕込みに入る前の朝は false。
func today_base() -> Dictionary:
	var tier_id := ""
	for entry in GameState.ledger:
		if int(entry.get("day", -1)) == GameState.day_count and str(entry.get("category", "")) == "prep":
			tier_id = str(entry.get("item", ""))
	var paid := tier_id != ""
	var scraps: bool = scraps_base and [GameState.Phase.PREP, GameState.Phase.OPEN, GameState.Phase.CLOSE].has(GameState.phase)
	if not paid and scraps:
		tier_id = str(Day1Events.PREP_TIERS[0].get("id", ""))
	var tier: Dictionary = {}
	if tier_id != "":
		tier = Day1Events.prep_tier_by_id(tier_id)
	return { "paid": paid, "tier_id": tier_id, "label": str(tier.get("label", "")),
		"servings": int(tier.get("servings", 0)), "scraps": scraps }


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


## [市場を出る]：水場に未訪問なら自動で訪れて水道代を払い、入力完了して先へ進む（仕込みの続きへ）。
## 訪問済み・未訪問に関わらず常に押せる（水汲み忘れで詰まらせない）。水道代が払えずゲームオーバーに
## なったら先へ進まず false（進んだら true）。
func exit_market() -> bool:
	if not market_visited_water:
		if not visit_water_stall():
			return false
	complete_input_and_advance()
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

# --- 状態（UI準備A③a）---

# OPEN の間だけ生きる客キュー管理役（STEP 6）。OPEN 以外では null。
# flow.runner は「今の客の接客 runner」に載せ替える。この open は「今何人目か」を持つだけ。
var open: OpenController = null

# 自動閉店（DESIGN.md 7.6）で CLOSE に飛ばすときだけ使う、先頭に差し込む理由テキスト。
# _set_runner_for_phase(CLOSE) が読んで消費する（読んだら空文字に戻す＝一度きり）。
var closed_early_reason := ""

# 鍋が尽きて「作り直すか閉店するか」の選択待ちのとき、保留中のREACT Eventを持つ。
# null なら選択待ちではない（DESIGN.md 7.6：条件1・2のどちらか一方だけ成立したとき）。
# 判定・売上・鍋の消費はまだ行っていない状態＝[戻る]で初めて _serve_customer() が動く。
var pending_shortage_ev = null

# 今の客の椀を何回廃棄したか（[廃棄する]で作り直すたびに+1）。客が替わる
# （load_current_customer）たびにリセットする一時状態。現在の椀自体はリセットで
# 消えてしまうので、廃棄したという事実を別に持っておかないと計器盤から見えなくなる。
var bowl_discard_count := 0

# 1人の客を複数の杯に分けて接客するとき（REACT に aggregate:true を持たせた客）の、
# 退店までの集計。空辞書なら集計中の客はいない。形は
#   { customer, sale, servings, results, pending_favorite }
# 提供記録は杯ごとではなく客1人分として退店時に1回だけ反映するため、ここに積む
# （flush_visit_tally）。鍋の消費と売上は杯ごとにその場で反映する（集計するのは
# 提供記録だけ。評判はもう杯ごと・客ごとに積まず、日次ログ全体から閉店時に
# GameState.settle_reputation()で1回だけ計算し直す＝④評判の更新）。客のrunnerが
# DONEになったとき、またはフェーズが替わるとき（途中閉店・ゲームオーバー）に
# 空にする＝二重に反映されない。
var visit_tally := {}

# 断った客のREACTを表示している間だけtrue（反応文をreactions.UNSERVEDから引くため）。新しい客・
# 再挑戦・新しい周でリセット（システム整理C1）。
var declined_now := false

# 提供できないまま閉店して退店する客の未提供版（反応・must_infoの本文）。CLOSEの先頭に一度だけ
# 積む（_closed_early_reasonと同じ「一度だけ」パターン。システム整理C1）。
var pending_close_lines: Array = []

# F3 断る操作（DESIGN.md 10.3.6）：名前あり客・配達員のADJUST中に[客を断る]を押したか。
# trueのままADJUST→SERVE→REACTへ進み、_apply_event()のREACTケースが判定・消費・売上を
# 一切発生させずに未提供として記録する（_pending_group_resultと同じ「確認結果を持ち越す」
# パターンだが、モブとは独立したフラグにして混線を避ける）。
var pending_decline := false

# [入力完了]を押して「N人分を提供／注文を断る」の確認ボタンを表示中か。
# trueの間、_update_options_row()はADJUSTの具材ボタンの代わりにこの2択を出す
# （_pot_mode/_phone_modeと同じ「専用ボタン行に差し替える」パターン）。
var pending_group_choice := false

# 確認ボタンで確定した結果（{"servings": 実際に提供する人数, "ordered": 注文人数,
# "retry_remaining": 挑戦を選んだ場合の残り人数（挑戦しないときは省略/0）}）。
# 空でなければ、_apply_event()のREACTケースがこちらを使って_serve_mob_partial()／
# _serve_mob_recipe_and_retry()へ委譲する（名前あり客・配達員のREACTは常にこれが空
# なので既存の経路のまま無影響）。
var pending_group_result := {}

# --- ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6。モブ客の団体オーダーだけが対象） ---
# モブ客のADJUST中に選んだ具材を、在庫を引かずに一時記録するリスト（{"id":String,
# "damaged":bool}の配列）。人数が確定した瞬間（_serve_mob_partial）まで在庫消費を遅らせる
# ため、「選ぶ」と「消費する」を分離する置き場所。名前あり客・配達員は使わない
# （今までどおり選んだ瞬間に消費）。
var mob_picks: Array = []

# 団体客の分割提供（最大2レシピ）：グループの元々の総注文人数（レシピ2でも変わらない。
# flush_visit_tally()でordered_servings/unserved_servingsを出すために覚えておく）。
# 新しい客をロードするたびにのみ-1へ戻す（reset_mob_group_state()には入れない。
# こちらは[廃棄する]でも呼ばれるため、レシピ2の作り直し時に元注文数を消してしまう）。
var mob_original_ordered := -1

# 今どちらのレシピを提供中か（1または2）。2に達したら「挑戦する」ボタンは出さない
# （最大2レシピの打ち止め）。mob_original_ordered と同じ理由で客のロード時にのみ1へ戻す。
var mob_recipe_number := 1

# 共通イベント（Day6の衝突・火災など。News）：その日に再生した（差し込んだ）イベントのid、と、時間帯の
# 最初の客に前置したイベントのid（時間帯の位置ごと。_load_current_customerが同じ客で何度呼ばれても
# 二重に前置せず、同じ列を組み直せるようにする）。保存しない実行時の値で、WAKE・再挑戦・新しい周で
# リセットする（システム整理D）。
var played_events: Array = []

var slot_event_ids := {}

# レシピ保存（4-7①。仮UI）：保存の段階（""＝ボタン待ち／"slot"＝枠を選ぶ／"name"＝名前を選ぶ）と選んだ枠。
# レシピ用のボタン行は _ready でコードから足す（.tscn は変えない）。
var recipe_save_stage := ""

# --- 日次ログ（BALANCE_REDESIGN_PLAN.md §8「①消費と鮮度の明確化・日次ログ」）用の
# 使い捨てカウンタ。経済数値・計算式には一切関与しない、記録専用の値。WAKEに入った瞬間
# （_set_runner_for_phase）にその日ぶんへ初期化し、FlowController.day_ending シグナル
# （NEXT_DAY→WAKE折り返しで日次リセットの前）で読み出してログへ組み立てる。
# GameStateではなくここに置く理由は_mob_count等と同じ：日をまたいで使い捨てる
# 受け側の作業変数であり、GameStateの「事実のみ・永続」という役割ではないため。
var log_opening_money := 0

var log_opening_reputation := 0

var log_planned_cups := 0          # OPEN突入時、その日の全客のREACT servingsを合算

var log_judged_planned_cups := 0   # 同上のうちjudge:false（配達員の持ち帰り等）を除いた分。

var log_water_used := 0            # [水を足す]を押した回数

var log_dashi_used := 0            # [だしを足す]を押した回数（旧_log_base_used）

var log_closed_early := false      # 鍋不足等でCLOSEへ強制遷移したか

var log_quality_counts := {}       # {"GREAT":n, "GOOD":n, "OK":n, "BAD":n, "":n(判定なし)}

var log_spoiled_items := {}        # PREP突入時のdiscard_spoiled_inventory()の結果をそのまま保持


# --- 開店（客キュー・椀・提供・Eventの受け側。UI準備A③a） ---

## いま接客中の客の Event 列を flow.runner に載せる。
## 客がいなければ空 runner（＝即 DONE）にして、OPEN を CLOSE へ進められる状態にする。
func load_current_customer() -> void:
	bowl_discard_count = 0   # 新しい客ごとにリセット（廃棄回数は客をまたがない）
	reset_mob_group_state()   # ②拒否と部分提供：客が替わるたび選択中の具材・確認状態を破棄
	mob_original_ordered = -1   # 団体客の分割提供：新しい客ごとにレシピ状態も破棄
	mob_recipe_number = 1
	pending_decline = false   # F3 断る操作：新しい客ごとにリセット
	declined_now = false
	recipe_save_stage = ""   # レシピ保存の段階も客ごとに消す
	clear_reask()   # 聞き直しの再表示も客ごとに消す
	if open != null and open.has_more():
		# モブの人数はGameState.today_plan["mob_instances"]側で客ごとに覚えているので、
		# ここでは第2引数（mob_count）を渡さない（渡しても_customer_flavor側で無視される）。
		var arriving := str(open.current_customer())
		# 来店記録（4-4b-1）：名前あり客が来た事実を残す（記録するだけ。モブは対象外）。
		CustomerMemory.arrive(arriving, open.current_slot_name(), Day1Events.episode_id_of(arriving))
		flow.set_runner(_slot_start_events() + Day1Events.customer_events(arriving))
	else:
		flow.set_runner([])


## OPEN 中、今の客の接客 runner が DONE になったら次の客をロードする。
## 全員さばき切ったら空 runner（DONE）になり、[次のPhase] で CLOSE へ進めるようになる。
## OPEN 以外・キューが空のときは何もしない。
func advance_open_queue_if_customer_done() -> void:
	if GameState.phase != GameState.Phase.OPEN or open == null:
		return
	if flow.is_runner_done() and open.has_more():
		# 退店：複数の杯に分けて接客した客の評判・提供記録を、ここで1回だけ反映する。
		flush_visit_tally()
		# 濃さメカニクス三点セット：1晩で鍋が煮詰まるのは明け方（最後の時間帯）に
		# 入った瞬間の1回だけにする（旧：時間帯が変わるたび＝1晩最大2回だった）。
		# 「新しい時間帯に入ったか」はOpenControllerが返すが、「それが最後の時間帯か」は
		# slot_index（進んだ後の値）とschedule.size()から受け側で判定する
		# （OpenController自身は「時間帯が進んだか」だけを答える薄い部品のまま無改修）。
		if open.advance_customer() and open.slot_index == open.schedule.size() - 1:
			GameState.deepen_soup()
		load_current_customer()


## [入力完了] と選択肢ボタンの共通処理：WAITING_INPUT を解除して1つ進め、
## 新 current の効果を適用し、OPEN の客キューを必要なら進めて再描画する。
func complete_input_and_advance() -> void:
	if flow.runner == null:
		return
	var before: int = flow.runner.index
	flow.runner_complete_input()
	if flow.runner.index != before:
		_apply_event(flow.runner.current())
	advance_open_queue_if_customer_done()
	changed.emit()


## [次のEvent] のハンドラ。runner を1つ進め、新しく current になった Event の効果を受ける。
## 「Event はデータ / 処理は受け側」（DESIGN.md 確定事項）の "受け側" がここ。
## EventRunner はカーソルを動かすだけで、PAY / ADD_ITEM の反映は一切しない。
func next_event() -> void:
	if flow.runner == null:
		return
	var before: int = flow.runner.index
	flow.runner_advance()
	# index が動いたときだけ適用（WAITING_INPUT で空振りした場合などは二重適用しない）。
	if flow.runner.index != before:
		_apply_event(flow.runner.current())
	advance_open_queue_if_customer_done()
	changed.emit()


## [入力完了] のハンドラ。入力待ちを解除して1つ進め、[次のEvent] と同じく新 current を適用。
## STEP 17.6: ADJUST 中も含め、常にこのボタンで進める（＝「提供」を兼ねる）。
## 具材ボタンはもう進めない（select_ingredient 側）ので、ADJUST で止まったまま
## 何度でも具材を選び、進みたくなったらこのボタンを押す、という形になる。
## ②拒否と部分提供：モブ客のADJUST中に押した最初の一回は、まだ進めず
## 「N人分を提供／注文を断る」の確認ボタンへ差し替えるだけにする（_pot_mode等と同じ
## 「専用ボタン行に差し替える」パターン）。名前あり客・配達員は今までどおり即座に進む。
## F3 SaleRule（DESIGN.md 10.3.1）：名前あり客・配達員は、味・具のどちらかが欠けた椀
## だと進めない（ボタン側（_btn_complete_input.disabled）で既に無効化済みだが、二重に
## 防ぐ。既存の_on_ingredient_selectedの在庫切れ二重チェックと同じ考え方）。
func complete_input() -> void:
	if is_in_story_choice():
		return   # 選択は選択肢のボタンで答える（[入力完了]で選ばずに飛ばせない）
	if is_current_mob_order() and not pending_group_choice:
		pending_group_choice = true
		changed.emit()
		return
	if not is_current_mob_order() and is_bowl_unsellable_in_adjust():
		return
	complete_input_and_advance()


## Event（データ）を1つ受けて、その効果を GameState に反映する「受け側」の本体。
## type を見て振り分けるだけ。処理はデータ側に持たせない（DESIGN.md 確定事項）。
##   PAY         … { amount } を apply_money(-amount) に渡す（支払い）
##   ADD_ITEM    … { item, amount } を add_inventory(item, amount) に渡す
##   REMOVE_ITEM … { item, amount } を remove_inventory(item, amount) に渡す（仕込みでの消費）
##   SET_SOUP    … { base_id, tags, servings } を set_soup() に渡す（共有鍋の作成・STEP 12/7.6）
##   REACT       … 残量が足りれば _serve_customer() で判定・評判・鍋消費・売上・記録
##                 （STEP 17.6・7.6）。足りないときは条件次第で自動閉店／選択待ち／
##                 そのまま提供に分かれる（7.6。詳細はこのcase内のコメント参照）
##   ADJUST      … new_bowl:true のときだけ、椀を新しく作り直す（同じ客の2杯目以降。
##                 前の杯の具材・評価・傷み印を持ち越さない）。それ以外は表示だけ
##   TEXT / WAIT_INPUT / GREET / SERVE / MARKET / PREP_TIER … 表示だけ。状態は動かさない
##     （ADJUST は STEP 13 で入力待ちに変わったが、椀への具材の反映は select_ingredient
##     が行う。MARKET（7.7）も同様に、水場の効果は _on_market_stall_selected /
##     _on_market_exit_pressed が行う。PREP_TIER（仕込み3段階化）も同様に、選んだ効果は
##     _on_prep_tier_selected が直接GameStateへ反映し、あわせて残りのPREP Event列を
##     flow.set_runner()で差し替える）
## 注意: index 0 の Event は「乗る前進」が無いので適用されない。Day1 の WAKE / PREP /
## 客の接客はどれも先頭が TEXT / GREET（効果なし）なので実害なし。PREP_TIER選択後に
## 差し替わる新しいEvent列も、この理由から必ず先頭をTEXTにしてある
## （Day1Events.prep_after_tier_events参照）。
func _apply_event(ev) -> void:
	if not (ev is Dictionary):
		return
	match ev.get("type", ""):
		"PAY":
			# 払えなければ実行せずゲームオーバー（水道代・場所代）。ベース代も同じ経路だが、
			# 払える所持金のときしかイベント自体が組まれない（クズ野菜ベースへ自動で切り替わる）。
			# kind:"rent"（チンピラの場所代）が実際に払えたときだけ、払い終えた印を付ける
			# （閉店直前の特別請求が二重にならないようにするため。§11「未解決」の直し方）。
			# F4 帳簿：kind:"rent"のときだけLedgerの"rent"カテゴリで記帳し、WAKE時点の
			# 確保（reserve）を「release」で決済する（旧mark_rent_paid()内のpending減算）。
			# 3-5：kind:"kit"（初日セット）はLedgerの"kit"カテゴリで記帳するだけで、
			# 場所代のような「支払い済み」フラグや確保の決済は不要（一度きりの固定購入で、
			# 未払いのまま閉店する経路が無いため）。
			var pay_kind := str(ev.get("kind", ""))
			var pay_category := "rent" if pay_kind == "rent" else ("kit" if pay_kind == "kit" else "")
			if pay_or_game_over(int(ev.get("amount", 0)), pay_category) and pay_kind == "rent":
				GameState.mark_rent_paid()
				Ledger.record("release", GameState.RENT_PRICE)
		"ADD_ITEM":
			# 3-5：初日セットの濃縮だし（idが"dashi"）は在庫ではないので、市場の購入
			# ハンドラ（_on_shop_item_selected）と同じ前例でGameState.buy_dashi()へ
			# 振り分ける。unit_priceは腐る品目のバッチ単価に使う（初期値0＝無料のまま）。
			var add_item_id := str(ev.get("item", ""))
			if add_item_id == "dashi":
				for i in range(int(ev.get("amount", 1))):
					GameState.buy_dashi()
			else:
				GameState.add_inventory(add_item_id, int(ev.get("amount", 1)), int(ev.get("unit_price", 0)))
		"REMOVE_ITEM":
			GameState.remove_inventory(ev.get("item", ""), int(ev.get("amount", 1)))
		"SCENE_END":
			# 場面が終わった：sets_facts を来店記録の facts へ書く（システム整理C2）。締めを読み終えて
			# ここに来た時だけ書く＝途中で閉店・再挑戦した場面は書かない。何度適用しても同じ値。
			var scene_facts: Dictionary = ev.get("sets_facts", {})
			for fact_key in scene_facts:
				CustomerMemory.set_fact(str(ev.get("customer", "")), str(fact_key), scene_facts[fact_key])
		"ADJUST":
			# 同じ客の2杯目以降：新しい椀へ切り替える。ADJUST は入力待ちで、具材を選べる前に
			# 「新しく current になった瞬間」に1回だけここへ来るので、必ず選ぶ前に新しくなる。
			if ev.get("new_bowl", false) and open != null:
				recipe_save_stage = ""
				open.reset_bowl()
				reset_mob_group_state()   # ②拒否と部分提供：同じ客の次の杯でも選択中の状態を破棄
		"SET_SOUP":
			# 鍋を作るのは GameState.set_soup 経由（受け側は soup を直接触らない）。
			# 7.6: servings（残量の初期値＝仕込んだ杯数）、strength（濃さ）、
			#   water_doses（今夜使える水の回数）も Event から受け取る。
			GameState.set_soup(str(ev.get("base_id", "")), ev.get("tags", []),
				int(ev.get("servings", 0)),
				int(ev.get("strength", 3)),
				int(ev.get("water_doses", 0)))
		"REACT":
			# ②拒否と部分提供：モブ客はADJUST中の確認ボタン（_on_group_serve_pressed /
			# _on_group_decline_pressed / _on_group_retry_pressed）で人数をすでに確定させて
			# いるので、_serve_mob_partial() / _serve_mob_recipe_and_retry() へ委譲する
			# （下の「残量が足りない」判定は経由しない＝鍋不足も具材不足もADJUST側の
			# 達成可能人数の計算にすでに含まれているため）。名前あり客・配達員は
			# pending_group_result が常に空なので、この分岐には入らず既存のまま。
			if not pending_group_result.is_empty():
				var result: Dictionary = pending_group_result
				pending_group_result = {}
				var retry_remaining: int = int(result.get("retry_remaining", 0))
				# 団体客の分割提供：「挑戦する」を選んだ（retry_remaining>0）ときだけ
				# レシピ2を差し込む。それ以外（通常の提供／断る／レシピ2自身の確定）は
				# 従来どおり最終レシピとして即flushする。
				if retry_remaining > 0:
					_serve_mob_recipe_and_retry(ev, int(result.get("servings", 0)), retry_remaining)
				else:
					_serve_mob_partial(ev, int(result.get("servings", 0)), int(result.get("ordered", 0)))
				return
			# F3 断る操作（DESIGN.md 10.3.6）：[客を断る]で既に確定させているので、
			# 判定・鍋消費・売上を一切発生させず未提供として記録する（モブの
			# _pending_group_resultと同じ「ADJUST側で確定済みの結果をここで反映するだけ」
			# パターン）。
			if pending_decline:
				pending_decline = false
				_serve_customer_decline(ev)
				return
			# 7.6: 提供しようとした時点で残量が servings に足りないとき、
			# 条件1（名前あり客がもう残っていない）と条件2（水が無い）の成立具合で分かれる：
			#   両方成立     → 自動的に閉店（_auto_close_kitchen。選ぶ余地が無い）
			#   それ以外     → 保留してプレイヤーに選ばせる（pending_shortage_ev。
			#                  [鍋を見る]で作り直すか[閉店]するか）
			# 「残量 ≥ servings のときだけ提供できる」ルールで、ADJUSTの[入力完了]が不足時は
			# 押せないので、通常ここには足りているときしか来ない。不足で来てしまった場合の
			# 保険として、薄めて満額で出す道は無くし、必ず保留に落とす。
			# 効果の適用自体は _serve_customer() に切り出した（[戻る]からも呼ぶ共通処理）。
			var servings := int(ev.get("servings", 1))
			var available := 0
			if GameState.soup != null:
				available = int(GameState.soup.get("remaining_servings", 0))
			if available < servings:
				var named_done := _no_named_customers_remaining()
				var resources_gone := _no_resources_left()
				if named_done and resources_gone:
					_auto_close_kitchen()
					return
				pending_shortage_ev = ev
				return
			# 濃さメカニクス三点セット：濃さ0（提供不可）のときも判定せず保留に落とす。
			# ADJUST側の[入力完了]無効化（is_strength_zero_in_adjust）で通常はここまで
			# 来ないが、残量不足の判定と同じ「保険」として一段レイヤーを重ねる（名前あり客・
			# 配達員向け。モブは_pending_group_result経由で上のreturnに引っかかるので無関係）。
			# 自動閉店には倒さない（濃縮だしがあれば[鍋を見る]で救えるため）。
			if GameState.soup != null and int(GameState.soup.get("strength", 3)) <= 0:
				pending_shortage_ev = ev
				return
			_serve_customer(ev)


## ADJUST の具材ボタンが押されたときのハンドラ（STEP 17.6 → 7.7で在庫連動）。
## 「椀へ具材を足す」のは EventRunner ではなく受け側＝ここの責務
## （DESIGN.md 9.5 STEP 13「EventRunner は味付け効果を処理しない」）。
## STEP 13/14 と違い、進めない（advanceしない）。3枠まで何度でも選べるようにするため、
## ADJUST から進むのは [入力完了]（提供）を押したときだけにする。
## 7.7: 選ぶたびに在庫を servings 分減らす（DESIGN.md 7.6「モブ客の仕様」：
## 「鍋 −人数分 / 具材 −人数分」。1つの椀で servings 人分をまとめて作る以上、
## 具材も鍋（consume_soup）と同じく人数分＝1人前の名前あり客なら1個のまま）。
## 在庫切れ（ボタン側で無効化済みだが二重に防ぐ）なら何もしない。
## フェーズ1 ステップ3：在庫を減らすのは add_to_bowl() が実際に椀へ足せたとき（戻り値
## true）だけにする。上限（3枠）に達している・椀が無いときに add_to_bowl() が
## 何もせず false を返すケースで、椀には入らないのに在庫だけ減る不具合があったため。
## 鮮度: 傷み判定は「どちらのボタンを押したか」だけで決める（damaged＝傷んだボタン）。
## 押した側の在庫が足りなくても、合計が servings 以上なら、もう一方から補って人数分まとめて
## 引く（押した側に1個以上あることはボタン側で保証。二重にここでも見る）。
## ②拒否と部分提供：有効条件を「押した側のバケツに1個以上あるか」だけに簡略化した
## （旧条件の「fresh+damaged合計がservings以上」は、名前あり客・配達員（servings常に1）に
## 対しては数学的に同値なので、この2者の挙動は変わらない。モブ（servings>1）だけが
## 「揃わなくても選べる」ようになる）。
## モブ客（is_mob）は在庫をまだ引かない。_mob_picksへ記録するだけにして、実際の消費は
## 人数が確定した瞬間（_serve_mob_partial）まで遅らせる。名前あり客・配達員は
## 今までどおり選んだ瞬間に消費する。
func select_ingredient(ingredient_id: String, damaged: bool = false) -> void:
	var own: int = GameState.damaged_count(ingredient_id) if damaged else GameState.fresh_count(ingredient_id)
	if own < 1:
		return
	var added := open != null and open.add_to_bowl(ingredient_id, damaged)
	if not added:
		changed.emit()
		return
	if is_current_mob_order():
		mob_picks.append({ "id": ingredient_id, "damaged": damaged })
	else:
		var servings := current_servings()
		if damaged:
			GameState.remove_inventory_damaged(ingredient_id, servings)
		else:
			GameState.remove_inventory_fresh(ingredient_id, servings)
	changed.emit()


## [廃棄する] のハンドラ。取り分けた一杯を無駄にしてから、**同じ客への椀を作り直す**
## （客を進めない＝EventRunnerはADJUSTに留まったまま。SERVE/REACTには一切触れない
## ので、EventRunnerの「optionsを持つEventは入力待ちで止まる」ルールは無傷）。
## 判定・売上・評判は発生しない：judge_bowlを呼んでいない＝判定自体が無いため。
## servingsは current_servings()（REACTをまだ経由せず先読みする既存の仕組み）を使う。
func discard_bowl() -> void:
	# 残量が servings に満たないときは廃棄できない（ボタン側でも無効化済みだが二重に防ぐ）。
	if open == null or is_short_now():
		return
	var servings := current_servings()
	GameState.consume_soup(servings)
	GameState.record_served({ "customer": str(open.current_customer()), "sale": 0,
		"servings": servings, "discarded": true })
	bowl_discard_count += 1
	open.reset_bowl()
	reset_mob_group_state()   # ②拒否と部分提供：作り直すので選択中の具材・確認状態も破棄
	changed.emit()


## REACT の効果を実際に適用する（判定→評判→鍋の消費→売上→記録）。
## 通常の提供（_apply_event から）と、鍋を作り直した後の [戻る]（_on_pot_back_pressed）
## の両方から呼ばれる共通処理。Event（reactions）は書き換えない
## （DESIGN.md 確定事項「Event はデータ、処理は受け側」）。
## どの反応textを見せるかは表示側 current_reaction_text() が都度選ぶ。
##
## REACT のフラグ（どちらも既定値なら従来どおり＝判定して、記録もその場で反映）：
##   judge:false     … 判定しない（judge_bowl を呼ばない）。評価も付かない杯
##                     （例：配達員の持ち帰り）。鍋の消費と売上は通常どおり
##   aggregate:true  … 鍋の消費と売上はその場で反映するが、提供記録は visit_tally に
##                     積み、退店時に客1人分として1回だけ反映する（flush_visit_tally）
## 評判は閉店時に_log_quality_countsから一括で計算し直す（④評判の更新。ここでは
## GameState.apply_reputationのような即時適用は行わない）。
func _serve_customer(ev: Dictionary) -> void:
	var sale := int(ev.get("sale", 0))
	var servings := int(ev.get("servings", 1))
	var judged: bool = bool(ev.get("judge", true))
	var aggregate: bool = bool(ev.get("aggregate", false))
	var customer_id := str(ev.get("customer", ""))
	# ③初回好物の開示 → F3 Judge v2（DESIGN.md 10.3.2）で更新：好物は「表示」こそ
	# 既知になるまで隠す（_format_bowl()のfavorite_true行・SNSタブ等）が、「判定」には
	# 初回から使う（入れていれば初回でもGREATになる）。以前はここでraw_favoriteを
	# knows_favorite()でゲートしてから判定に渡していたが、そのゲート自体を廃止した。
	var raw_favorite := str(ev.get("favorite", ""))
	var result := ""
	if judged and open != null:
		result = open.judge_bowl(ev.get("wanted_tags", []), raw_favorite)
	GameState.consume_soup(servings)
	GameState.apply_money(sale)
	# 来店記録（4-4b-1）：この杯の提供（評価・入れた具材）を、その日の来店へ追記する
	# （配達員も杯ごとにここへ来る。好物の開示の時刻は下のままで変えない）。
	if open != null:
		# 今日の頼みに応えたか：今日の頼みがある場面（REACTにbase_wanted_tagsが付く）の判定した杯だけ。
		# 実効注文のタグをすべて椀が満たした（一致数＝タグ数）なら true。濃さ・傷みの減点は見ない
		# （頼まれた中身に応えたかであって、出来の評価ではない）。無い場面はnull＝キーを入れない。
		var honored = null
		if judged and ev.has("base_wanted_tags"):
			var wanted: Array = ev.get("wanted_tags", [])
			honored = not wanted.is_empty() and int(open.current_bowl.get("match_count", 0)) >= wanted.size()
		CustomerMemory.record_serve(customer_id, open.current_slot_name(),
			Day1Events.episode_id_of(customer_id), servings, result,
			open.current_bowl.get("additions", []), honored)
	if aggregate:
		# 集計客（配達員）は「退店時」に知った扱いにする必要があるため、ここではまだ
		# mark_favorite_known() を呼ばない（呼ぶと1杯目の直後から2杯目で使えてしまう）。
		# flush_visit_tally() が退店の瞬間に1回だけ確定させる。
		_add_to_visit_tally(customer_id, judged, sale, servings, result, raw_favorite)
		return
	if judged and raw_favorite != "":
		GameState.mark_favorite_known(customer_id)
	# 日次ログ：判定結果ごとに集計する。judged=falseの杯（配達員の持ち帰り等）は
	# result=""のまま（判定なしと分かる値。指示文どおり）。
	log_quality_counts[result] = int(log_quality_counts.get(result, 0)) + servings
	GameState.record_served({ "customer": customer_id, "sale": sale,
		"servings": servings, "result": result })
	if sale > 0:
		Ledger.record("sale", sale, customer_id, servings)
	_insert_after_serve_events(ev, true, result)


## _pending_decline経由でREACTに到達したときの処理。判定（judge_bowl）を呼ばない・
## 鍋を消費しない・売上を発生させない。未提供として記録する（servings=0・declined=true・
## result=""）。①の日次計画杯数（log_planned_cups）は先読み済みのままなので、
## 未提供杯数はGameState.servedへ加算しないことで自動的に正しくなる（既存のモブの
## 「断る」と同じ考え方）。aggregate客（配達員）は退店時にまとめて1件反映する既存の
## _visit_tally経路へ0杯ぶんとして積む（_apply_mob_recipeのactual<=0分岐と同じ形）。
func _serve_customer_decline(ev: Dictionary) -> void:
	var customer_id := str(ev.get("customer", ""))
	declined_now = true   # 反応文はreactions.UNSERVEDから引く（current_reaction_text）
	# 来店記録（4-4b-1）：断りも「来た」事実として残す（served=0のまま）。
	if open != null and CustomerMemory.is_recordable(customer_id):
		CustomerMemory.ensure_visit(customer_id, open.current_slot_name(),
			Day1Events.episode_id_of(customer_id))
	if bool(ev.get("aggregate", false)):
		_add_to_visit_tally(customer_id, false, 0, 0, "", "")
		return
	GameState.record_served({ "customer": customer_id, "sale": 0,
		"servings": 0, "declined": true, "result": "" })
	_insert_after_serve_events(ev, false, "")


## 提供後の列（本文・締め。システム整理C1）を、現在位置（REACT）の直後へ差し込む。
## 列を組むのは Day1Events.after_serve_events()（状態を読むだけ）。ここは差し込むだけで、
## 料金・評判・評価・鍋・在庫には触れない。差し込み先は常にindex 2以降なので、EventRunner の
## 「index 0 の効果は適用されない」制約に当たらない（モブの2レシピ目と同じ差し込み方）。
## 場面データに該当のキーが無い（現行の21場面）・モブ・集計客（配達員の3杯列）は何も差さない。
## 既存の _customer_extra_events（警官の共通会話・場所代のPAY）は、差し込んだ列の後ろに残る。
func _insert_after_serve_events(ev: Dictionary, served: bool, grade: String) -> void:
	if flow.runner == null or bool(ev.get("is_mob", false)) or bool(ev.get("aggregate", false)):
		return
	var customer_id := str(ev.get("customer", ""))
	if not CustomerMemory.is_recordable(customer_id):
		return
	var events := Day1Events.after_serve_events(customer_id, Day1Events.episode_id_of(customer_id),
		{ "served": served, "grade": grade })
	var insert_at: int = flow.runner.index + 1
	for i in range(events.size()):
		flow.runner.events.insert(insert_at + i, events[i])


## いま接客中の客が何杯注文しているか（7.6）。REACT がまだ current でなくても見たいので、
## runner の Event 列から REACT を探して servings を読む（Event はデータなので読むだけ）。
## 探すのは「今の位置から先の最初のREACT」で、先に無ければ「直前のREACT」（react_for_now）。
## 1杯ずつ接客する客（REACTが複数ある客）でも、今の杯の値を返せる。REACTが1つだけの客は、
## どの位置でも従来と同じ値になる。
func current_servings() -> int:
	var react := react_for_now()
	if react.is_empty():
		return 0
	return int(react.get("servings", 1))


## いま見ている杯に対応するREACT Event（先の最初、無ければ直前の最後）。無ければ空辞書。
## 客のEvent列に REACT が複数ある（1杯ずつ接客する）場合に、今の杯の REACT を引くための
## 読み取り専用の探索。Event はデータなので書き換えない。
func react_for_now() -> Dictionary:
	if flow.runner == null:
		return {}
	var events: Array = flow.runner.events
	var start: int = clampi(flow.runner.index, 0, events.size())
	for i in range(start, events.size()):
		var ev = events[i]
		if ev is Dictionary and ev.get("type", "") == "REACT":
			return ev
	for i in range(start - 1, -1, -1):
		var ev = events[i]
		if ev is Dictionary and ev.get("type", "") == "REACT":
			return ev
	return {}


## いまADJUST（味を調える）で入力待ちの、名前あり客のid。モブ・配達員の3杯専用列・
## ADJUST以外・入力待ちでないときは空文字（注文カードと[聞き直す]の対象判定）。
func adjust_customer_id() -> String:
	if open == null or flow.runner == null or flow.runner.status != EventRunner.Status.WAITING_INPUT:
		return ""
	var cur = flow.runner.current()
	if not (cur is Dictionary) or str(cur.get("type", "")) != "ADJUST":
		return ""
	var customer_id := str(cur.get("customer", ""))
	if customer_id == "" or Day1Events.is_mob_customer(customer_id):
		return ""
	if Day1Events.is_multi_cup_scene(customer_id, Day1Events.episode_id_of(customer_id)):
		return ""
	return customer_id


## いま ADJUST で3枠を選んでいる最中か（options を持つ WAITING_INPUT）。
## 鍋モードに入れるかの判定に使う（調理の途中で鍋をいじらせない）。
func is_choosing_ingredients() -> bool:
	var r: EventRunner = flow.runner
	if r == null or r.status != EventRunner.Status.WAITING_INPUT:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.has("options")


## いま SERVE（[入力完了]で椀を確定した直後、まだ判定[REACT]が適用される前）か。
## フェーズ1 ステップ4：judge_bowl は REACT が適用される瞬間に鍋の濃さをその場で
## 読みに行くため、椀の中身（additions）は確定済みなのに、SERVEで足踏みしている間だけ
## 鍋を触って濃さを変えられると判定が後から変わってしまう（廃棄する・閉店はこの状態では
## 元々出せない／押せないので、塞ぐ必要があるのは鍋モードだけ）。REACT はEventが
## current になった瞬間に同じ処理内で即座に適用される実装なので、SERVEさえ塞げば
## 判定前に鍋をいじれる隙間は無くなる。
func is_awaiting_react() -> bool:
	var r: EventRunner = flow.runner
	if r == null:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.get("type", "") == "SERVE"


## いま PREP_TIER（仕込み3段階の選択）が現在の Event か。is_in_market() と同じ形。
## [次のEvent]/[入力完了] を無効化する判定に使う（抜ける経路を段階選択ボタンだけにする。
## 選ばずに素通りされると、その先のADD_ITEM/SET_SOUPが無いまま仕込みが成立しなくなる）。
## いま店主の距離感の選択（CHOICE。システム整理C2）の入力待ちか。
func is_in_story_choice() -> bool:
	var r: EventRunner = flow.runner
	if r == null:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.get("type", "") == "CHOICE"


## 選択肢のボタン（仮UI）。選んだ結果を来店記録の choices と、選択肢の set の事実（facts）へ残す。
## 選択は料金・評判・評価・鍋・在庫を変えない（記録するだけ）。最後の選択が済んだら、選んだ結果を
## 読んで締め（closing_events）を組み、現在位置の直後へ差し込んでから先へ進む。
## 現在の選択と合わない id は何もしない。
func choose_story_option(choice_id: String, option_id: String) -> void:
	if not is_in_story_choice():
		return
	var cur: Dictionary = flow.runner.current()
	if str(cur.get("choice_id", "")) != choice_id:
		return
	var customer_id := str(cur.get("customer", ""))
	var scene_id := Day1Events.episode_id_of(customer_id)
	var picked := {}
	for choice in ScheduleData.episode_choices(customer_id, scene_id):
		if str(choice["id"]) != choice_id:
			continue
		for option in choice["options"]:
			if str(option["id"]) == option_id:
				picked = option
	if picked.is_empty():
		return
	CustomerMemory.record_choice(customer_id, open.current_slot_name() if open != null else "",
		scene_id, choice_id, option_id, picked["set"])
	TalkLog.add(GameState.day_count, "choice", "", str(picked["label"]))
	var events: Array = flow.runner.events
	var more_choices: bool = flow.runner.index + 1 < events.size() \
			and str(events[flow.runner.index + 1].get("type", "")) == "CHOICE"
	if not more_choices:
		var closing := Day1Events.closing_events(customer_id, scene_id)
		for i in range(closing.size()):
			events.insert(flow.runner.index + 1 + i, closing[i])
	complete_input_and_advance()


## 集計（visit_tally）に1杯分を積む。売上と杯数は全杯を積む。
## 日次ログ：resultsに判定結果ごとの杯数も積んでおく（_flush_visit_tallyで
## _log_quality_countsへ合算し、record_servedにも残す。判定なしの杯はresult=""のまま）。
## ③初回好物の開示：raw_favoriteが空でなければ_visit_tallyへ覚えておき（既に何か
## 覚えていれば上書きしない＝配達員3杯目のfavorite無しに負けない）、退店時の
## flush_visit_tally()で1回だけ「知った」扱いにする。
## 団体客の分割提供：ordered_servings（元の総注文人数）を渡すと、積み始めた瞬間
## （visit_tally が空だったとき）だけ記録する。2レシピ目以降は既に入っている値を
## 上書きしない（レシピ2のorderedは「残り人数」であって元の総注文人数ではないため）。
## 配達員の集計（この引数を渡さない呼び出し）はキー自体が付かず、今までどおりの
## 4フィールド（customer/sale/servings/results）のまま変わらない。
func _add_to_visit_tally(customer: String, judged: bool, sale: int,
		servings: int, result: String = "", raw_favorite: String = "",
		ordered_servings: int = -1) -> void:
	if visit_tally.is_empty():
		visit_tally = { "customer": customer,
			"sale": 0, "servings": 0, "results": {}, "pending_favorite": "" }
		if ordered_servings >= 0:
			visit_tally["ordered_servings"] = ordered_servings
	visit_tally["sale"] = int(visit_tally["sale"]) + sale
	visit_tally["servings"] = int(visit_tally["servings"]) + servings
	var results: Dictionary = visit_tally["results"]
	results[result] = int(results.get(result, 0)) + servings
	if judged and raw_favorite != "":
		visit_tally["pending_favorite"] = raw_favorite


## 集計を客1人分として反映し、空にする（空なら何もしない＝何度呼んでも二重には効かない）。
## 評判は閉店時に_log_quality_countsから一括で計算し直す（④評判の更新。旧・杯ごとの
## 増減平均をここで即時適用する処理は廃止した）。提供記録は売上・杯数の合計で1件残す。
## 団体客の分割提供：_visit_tallyにordered_servingsがある（＝モブの団体オーダー由来）
## ときだけ、ordered_servings/unserved_servings/declinedも記録に足す（配達員の集計には
## このキーが付かないので、既存の4フィールド形のまま変わらない）。
func flush_visit_tally() -> void:
	if visit_tally.is_empty():
		return
	# 日次ログ：この客の杯ごとの判定結果を、その日の集計へ合算する。
	var results: Dictionary = visit_tally.get("results", {})
	for key in results:
		log_quality_counts[key] = int(log_quality_counts.get(key, 0)) + int(results[key])
	# ③初回好物の開示：退店するこの瞬間に1回だけ「知った」扱いにする（配達員は
	# これで1・2杯目の途中では判明せず、3杯すべて終えた退店時に判明する）。
	var pending_favorite := str(visit_tally.get("pending_favorite", ""))
	if pending_favorite != "":
		GameState.mark_favorite_known(str(visit_tally["customer"]))
	var record := { "customer": visit_tally["customer"],
		"sale": int(visit_tally["sale"]), "servings": int(visit_tally["servings"]),
		"results": results }
	if visit_tally.has("ordered_servings"):
		var ordered: int = int(visit_tally["ordered_servings"])
		var served: int = int(visit_tally["servings"])
		record["ordered_servings"] = ordered
		record["unserved_servings"] = maxi(ordered - served, 0)
		record["declined"] = served <= 0
	GameState.record_served(record)
	if int(record["sale"]) > 0:
		Ledger.record("sale", int(record["sale"]), str(record["customer"]), int(record["servings"]))
	visit_tally = {}


## 現在の Event が REACT のときだけ、判定結果に応じた反応textを選んで返す（STEP 16〜17.6）。
## Event（reactions）は書き換えない。判定結果（BAD/OK/GOOD/GREAT）をキーにして引くだけ。
## 各段階2パターンあり、どれを見せるかは judge_bowl() が一度だけ抽選して
## current_bowl["reaction_variant"] に記録済みのものを使う
## （ここで再抽選すると、再描画のたびに表示が変わってしまうため）。
## 判定前は result が空文字でキーに当たらないので、自動的に空文字になる。
## REACT 以外（GREET/ADJUST/SERVE など）や runner が無いときも空文字（表示に何も足さない）。
func current_reaction_text() -> String:
	var r: EventRunner = flow.runner
	if r == null or open == null:
		return ""
	var cur = r.current()
	if not (cur is Dictionary) or cur.get("type", "") != "REACT":
		return ""
	var result: String = str(open.current_bowl.get("result", ""))
	var reactions: Dictionary = cur.get("reactions", {})
	var pool: Array = reactions.get(result, [])
	if result == "" and declined_now:
		# 断った客（未提供）の反応。2パターンの抽選は判定（judge_bowl）が引くので使えない＝要素0。
		pool = reactions.get("UNSERVED", [])
	if pool.is_empty():
		return ""
	var variant: int = open.current_bowl.get("reaction_variant", 0)
	return str(pool[variant % pool.size()])


## 今の客の注文（servings）に、鍋の残量が足りないか。ADJUST中の提供・廃棄の共通ルール：
## 残量 ≥ servings のときだけ提供も廃棄もできる（取り分けられる一杯が無ければ、
## 出すことも無駄にすることもできない）。客がいない・鍋が無いときは false。
func is_short_now() -> bool:
	if open == null or GameState.soup == null:
		return false
	return int(GameState.soup.get("remaining_servings", 0)) < current_servings()


## ADJUST中（椀を作っている最中）で、鍋が足りないか。[入力完了]を止め、
## [鍋を見る]・[閉店]を出す条件に使う。
func is_short_in_adjust() -> bool:
	return is_choosing_ingredients() and is_short_now()


## 残量不足が「今まさに提供を妨げている」文脈か：ADJUST中に既に不足しているか、
## 保留中のREACT（pending_shortage_ev）がその不足で保留になっているか。
## ADJUST中の判定（is_short_in_adjust）はSERVE/REACT到達前しか見えないため、
## 保留に落ちた後（SERVEを過ぎている）も同じ問いに答えられるよう別関数にしてある。
## 水で解決できるかどうかの判定（鍋モードの入場可否）に使う。
func is_servings_short_context() -> bool:
	if is_short_in_adjust():
		return true
	if pending_shortage_ev == null or GameState.soup == null:
		return false
	return int(GameState.soup.get("remaining_servings", 0)) < int(pending_shortage_ev.get("servings", 1))


## 濃さメカニクス三点セット：鍋の濃さが実際に0（提供不可）か。文脈（ADJUST中か保留中か）を
## 問わない素の状態チェック（濃さは接客中に自然には変わらないので、どちらの文脈でも
## 同じ値になる。だしで解決できるかどうかの判定に使う）。
func is_strength_zero() -> bool:
	return GameState.soup != null and int(GameState.soup.get("strength", 3)) <= 0


## ADJUST中（椀を作っている最中）で、濃さ0（提供不可）か。残量不足（is_short_in_adjust）
## とは独立した別の条件（判定そのものが成立しない）。[入力完了]を止め、
## [鍋を見る]・[閉店]を出す条件に使う（残量不足と同じ役割）。
func is_strength_zero_in_adjust() -> bool:
	return is_choosing_ingredients() and is_strength_zero()


## F3 SaleRule（DESIGN.md 10.3.1）：ADJUST中（椀を作っている最中）で、味・具の
## どちらかの素材が欠けているか（＝このまま提供しても売れない椀か）。残量不足・濃さ0
## （既存の_is_short_in_adjust/is_strength_zero_in_adjust）とは独立した別条件として
## [入力完了]を止める。SaleRule.check()のSHORT_SERVINGS/STRENGTH_ZERO理由はここでは見ない
## （既存の2関数が別途担当しているため、二重に判定しない）。
func is_bowl_unsellable_in_adjust() -> bool:
	if not is_choosing_ingredients() or open == null:
		return false
	var reasons: Array = SaleRule.check(open.current_bowl, GameState.soup).get("reasons", [])
	return reasons.has(SaleRule.NO_FLAVOR) or reasons.has(SaleRule.NO_TOPPING)


## [閉店]を押せるか。鍋不足の保留中、「ADJUST中で残量不足、かつ水が無い」、または
## 「ADJUST中で濃さ0、かつだしが無い」（どちらも足せなければ閉店）。いずれも、その客には
## 出せなかった扱いで CLOSE へ進む。
## ②拒否と部分提供：モブ客の不足は「断る」で次の客へ進めるので、これだけを理由に
## [閉店]は出さない（名前あり客・配達員は無変更。濃さ0もモブは_mob_achievable_servings()の
## 「達成可能0」経由で断れるので同じ扱いにする）。
func can_close_now() -> bool:
	return pending_shortage_ev != null \
			or (is_short_in_adjust() and _no_resources_left() and not is_current_mob_order()) \
			or (is_strength_zero_in_adjust() and not GameState.can_add_dashi() and not is_current_mob_order())


## もう水が無いか（DESIGN.md 7.6：自動閉店・選択待ちの条件2）。
## 残量を増やせるのは水だけ（だしは濃さを上げるだけで、量は増やさない）ので、
## 不足を埋められるかの判定は水の有無だけを見る。ただし濃さが低すぎて今すぐは
## 水を出せない（can_add_water()がfalse）だけの場合、だしを先に入れれば水を
## 出せる手順が残っていることがあるため、GameState.water_reachable()で
## その手順まで含めて判定する（鍋操作不能バグの修正。単独判定のcan_add_water()
## だと、まだ回復可能な状況を「もう資源が無い」と誤判定し、詰んでいないのに
## 自動閉店・強制ゲームオーバー相当の分岐へ落としてしまっていた）。
func _no_resources_left() -> bool:
	return not GameState.water_reachable()


## 現在の客（含む）から OPEN 終了まで、名前あり客がもう出てこないか。
## 今の客自身が名前あり客なら、その客はまだ「済んでいない」ので false になる
## （＝名前あり客のREACT中に自動閉店の分岐1が成立することはない）。
func _no_named_customers_remaining() -> bool:
	if open == null:
		return true
	var customers := open.current_slot_customers()
	for i in range(open.index, customers.size()):
		if not Day1Events.is_mob_customer(customers[i]):
			return false
	for s in range(open.slot_index + 1, open.schedule.size()):
		var slot = open.schedule[s]
		if slot is Dictionary:
			for cid in slot.get("customers", []):
				if not Day1Events.is_mob_customer(cid):
					return false
	return true


## 鍋が尽きて自動的に閉店する（DESIGN.md 7.6）。判定・売上・評判・鍋の消費は
## 一切行わない（この客には出せなかった、という扱い）。反応・セリフは最小の仮テキストのみ。
## FlowController.force_phase() でゲートを通さず CLOSE へ飛ばす
## （open は _set_runner_for_phase(CLOSE) が既存の「OPEN以外ではnull」処理で片付ける）。
## _on_close_pressed と同じく、場所代が未払いならCLOSEへ飛ばす前に特別請求する。
func _auto_close_kitchen() -> void:
	var reason := reason_after_collecting_rent("（鍋が尽きた。今日はもう終いだ。）")
	if reason == "":
		return
	closed_early_reason = reason
	queue_unserved_exit()
	log_closed_early = true   # 日次ログ：鍋が尽きて自動的に閉店した
	flow.force_phase(GameState.Phase.CLOSE)


## 提供できないまま閉店して退店する客（今の接客中の名前あり客。今日の来店で served=0）の
## 未提供版を、CLOSEの先頭に積むために覚える（システム整理C1）。反応（reactions.UNSERVED）と、
## must_info を持つ場面の未提供版の本文だけ。facts は立てず、来店記録・評判・料金は変えない。
## 到着前の客（列に残っている客）は来店記録も無く、場面が始まっていないので対象外。
func queue_unserved_exit() -> void:
	pending_close_lines = []
	if open == null or not open.has_more():
		return
	var customer_id := str(open.current_customer())
	if not CustomerMemory.is_recordable(customer_id):
		return
	var visit := CustomerMemory.last_visit(customer_id)
	if visit.is_empty() or int(visit["day"]) != GameState.day_count or int(visit["served"]) > 0:
		return
	pending_close_lines = Day1Events.unserved_exit_events(customer_id, Day1Events.episode_id_of(customer_id))


## 未払いの場所代（徴収日のみ）があれば、閉店の直前に特別請求する共通処理
## （§11「未解決：閉店で場所代を避けられる」の直し方。手動閉店[_on_close_pressed]・
## 自動閉店[_auto_close_kitchen]の両方から呼ぶ）。
## 徴収日でない、またはもう払っている（GameState.rent_paid_today）ならbase_reasonを
## そのまま返す。未払いなら pay_or_game_over(RENT_PRICE) で請求し、払えなければ
## 既存の水道代・場所代と同じくゲームオーバーへ飛ばして空文字を返す（呼び出し側は
## 空文字を見てCLOSEへ進まない・base_reasonが空文字になることは無いので安全に判別できる）。
## 払えたら、その旨を一言添えた理由テキストを返す。
func reason_after_collecting_rent(base_reason: String) -> String:
	if not GameState.is_collection_day() or GameState.rent_paid_today:
		return base_reason
	if not pay_or_game_over(GameState.RENT_PRICE, "rent"):
		return ""
	GameState.mark_rent_paid()
	Ledger.record("release", GameState.RENT_PRICE)
	return base_reason + "（今月の場所代は、閉店前にきっちり払わせてもらった。）"


## 時間帯の最初の客の接客の前に置く、その時間帯（at＝時間帯名）の共通イベント（システム整理D）。
## 時間帯の位置（何番目の時間帯・客のindex 0）ごとに、前置したイベントのidを覚えておく：
## load_current_customer が同じ客で何度呼ばれても、同じ列を組み直すだけで二重にならない
## （初回に再生済みにするが、2回目以降は覚えたidから組み直す）。TEXTだけでゲームの数値には触れない。
func _slot_start_events() -> Array:
	if open == null or open.index != 0:
		return []
	var key := "%d:%d" % [open.slot_index, open.index]
	if not slot_event_ids.has(key):
		var ids := []
		for item in News.pending_events(GameState.day_count, played_events, open.current_slot_name()):
			ids.append(str(item["id"]))
			played_events.append(str(item["id"]))
		slot_event_ids[key] = ids
	var events := []
	for id in slot_event_ids[key]:
		events.append_array(News.event_lines(News.event_by_id(GameState.day_count, str(id))))
	return events


## 再生した共通イベントのid（events の event_id）を played_events へ覚える。
func mark_events_played(events: Array) -> void:
	for ev in events:
		if ev is Dictionary and ev.has("event_id") and not played_events.has(str(ev["event_id"])):
			played_events.append(str(ev["event_id"]))


## ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6）：対象はモブ客の団体オーダーだけ。
## いま見ているREACTがモブ客のものか。react_for_now()は書き換えない読み取り専用の
## 先読みなので、ADJUST中（REACT到達前）でも判定に使える。
func is_current_mob_order() -> bool:
	return bool(react_for_now().get("is_mob", false))


## 達成可能人数 = min(注文人数, 鍋の残量, 選んだ各具材のバケツ別在庫数)。
## 「新鮮2個＋傷み2個を新鮮4人分にはしない」（仕様3）＝押したバケツ単体の在庫数だけを見る
## （fresh+damagedの合算はしない）。同じ具材・同じバケツを2枠選んだ場合はその具材について
## 在庫数を選んだ回数で割る（add_to_bowlは重複を許すため。例：軟骨(新鮮)を2枠→
## 新鮮在庫8個なら軟骨に関する上限は8÷2=4人）。
## 濃さメカニクス三点セット：濃さ0（提供不可）の鍋は人数に関係なく達成可能0にする
## （具材や残量が足りていても、薄すぎる鍋では誰にも出せない。既存の「達成可能0なら
## 断るしか出せない」というモブUIにそのまま乗せるだけで、新しい分岐は増やさない）。
func mob_achievable_servings(ordered: int) -> int:
	var achievable := ordered
	if GameState.soup != null:
		achievable = mini(achievable, int(GameState.soup.get("remaining_servings", 0)))
		if int(GameState.soup.get("strength", 3)) <= 0:
			achievable = 0
	else:
		achievable = 0
	# F3 SaleRule（DESIGN.md 10.3.1）：味・具のどちらかが欠けた椀は、濃さ0と同じく
	# 達成可能0にする（既存の「達成可能0→断るしか出せない」UIをそのまま使う。
	# 新しい画面状態は増やさない）。SHORT_SERVINGS/STRENGTH_ZERO理由はこの関数が
	# 既に別に計算しているので、ここではNO_FLAVOR/NO_TOPPINGだけを見る。
	if open != null:
		var reasons: Array = SaleRule.check(open.current_bowl, GameState.soup).get("reasons", [])
		if reasons.has(SaleRule.NO_FLAVOR) or reasons.has(SaleRule.NO_TOPPING):
			achievable = 0
	var counts := {}   # "id|damaged" -> 選んだ回数
	for pick in mob_picks:
		var key: String = "%s|%s" % [pick["id"], pick["damaged"]]
		counts[key] = int(counts.get(key, 0)) + 1
	var seen := {}
	for pick in mob_picks:
		var key: String = "%s|%s" % [pick["id"], pick["damaged"]]
		if seen.has(key):
			continue
		seen[key] = true
		var avail: int = GameState.damaged_count(pick["id"]) if pick["damaged"] else GameState.fresh_count(pick["id"])
		achievable = mini(achievable, int(avail / int(counts[key])))
	return maxi(achievable, 0)


## モブ客の選択中の状態（在庫はまだ引いていない）を破棄する。客が替わる・同じ客の次の杯・
## 廃棄して作り直す、の3箇所から呼ぶ（reset_mob_group_state）。
func reset_mob_group_state() -> void:
	mob_picks = []
	pending_group_choice = false
	pending_group_result = {}


## REACT到達時、pending_group_result（確認ボタンで確定済み）があるモブ客はこちらで処理する
## （_apply_event()のREACTケースから委譲。名前あり客・配達員は_pending_group_resultが
## 常に空なので、この関数自体を通らない＝既存の_serve_customer()のみ使う）。
## actual（実際に提供する人数）が0なら「断り」＝判定・鍋消費・売上のいずれも発生させない
## （既存の[閉店]と同じ扱い。仕様7）。1以上なら、実際に消費するのはactual人分だけ
## （鍋・選んだ各具材とも）。判定（GREAT/GOOD/OK/BAD）はactualの大小に関係なく「何を
## 入れたか」だけで決まる（人数に比例させない。§2確定仕様）。
## 団体客の分割提供：記録は_visit_tallyへ積むだけにし、_log_quality_countsへの加算は
## flush_visit_tally()側に一本化する（ここで直接加算すると、2レシピ目のflush時に
## resultsから再度合算されて二重加算になるため）。
func _apply_mob_recipe(ev: Dictionary, actual: int) -> void:
	var customer := str(ev.get("customer", ""))
	if actual <= 0:
		_add_to_visit_tally(customer, false, 0, 0, "", "", mob_original_ordered)
		return
	var result := ""
	if open != null:
		result = open.judge_bowl(ev.get("wanted_tags", []), str(ev.get("favorite", "")))
	for pick in mob_picks:
		if bool(pick["damaged"]):
			GameState.remove_inventory_damaged(str(pick["id"]), actual)
		else:
			GameState.remove_inventory_fresh(str(pick["id"]), actual)
	GameState.consume_soup(actual)
	var sale: int = actual * GameState.PRICE_PER_SERVING
	GameState.apply_money(sale)
	_add_to_visit_tally(customer, true, sale, actual, result, str(ev.get("favorite", "")),
		mob_original_ordered)


## この団体客への最後（または唯一）のレシピを確定し、その場で退店集計として確定させる
## （客が変わるまで待つ通常の_flush_visit_tallyタイミングとは違い、モブは既存どおり
## REACT到達の瞬間に確定させる。visit_tally.is_empty()なら何もしない性質を使っているので、
## レシピ1回だけの団体（従来どおりの2択のみ）でも同じ関数で正しく動く）。
func _serve_mob_partial(ev: Dictionary, actual: int, ordered: int) -> void:
	_apply_mob_recipe(ev, actual)
	flush_visit_tally()


## 「挑戦する」を選んだ場合の処理：レシピ1（achievable人分）をその場で確定・積算し、
## 同じ客のrunnerへレシピ2用のADJUST→SERVE→REACTを動的に差し込む（末尾追加ではなく
## 現在位置の直後へinsertする。モブ客の接客Event列に閉店会話等の追加Eventが後ろへ
## 続く場合でも順序を壊さないため）。レシピ2のADJUSTはnew_bowl:trueにして
## _apply_event()の既存ADJUSTケースに椀のリセット・reset_mob_group_state()を任せる。
func _serve_mob_recipe_and_retry(ev: Dictionary, actual: int, remaining: int) -> void:
	_apply_mob_recipe(ev, actual)
	mob_recipe_number = 2
	mob_picks = []
	var customer: String = str(ev.get("customer", ""))
	var next_events := [
		{ "type": "ADJUST", "customer": customer, "text": "（味を調える）",
			"options": Day1Events._adjust_options(), "new_bowl": true },
		{ "type": "SERVE", "customer": customer, "text": "「はいよ、お待ち。」" },
		{ "type": "REACT", "customer": customer, "reactions": ev.get("reactions", {}),
			"wanted_tags": ev.get("wanted_tags", []), "favorite": ev.get("favorite", ""),
			"servings": remaining, "is_mob": true,
			"sale": GameState.PRICE_PER_SERVING * remaining },
	]
	var insert_at: int = flow.runner.index + 1
	for i in range(next_events.size()):
		flow.runner.events.insert(insert_at + i, next_events[i])


## [聞き直す]を押した客のid（空なら押していない）と、そのとき再表示する台詞の行。客が替わると消える。
var reask_customer_id := ""
var reask_lines: Array = []


## 聞き直しの表示を消す（客が替わる・再挑戦・新しい周）。
func clear_reask() -> void:
	reask_customer_id = ""
	reask_lines = []


## [聞き直す]：客の頼みの台詞（場面の order.reask。無ければ客の greet）を再表示する対象にする。
## 料金・評判・評価・来店記録・facts を一切変えない（読むだけ・状態は reask_* に書くだけ）。
## 何度押しても同じ。この操作を正解の印にしない（判定・記録は読まない）。
func reask() -> void:
	var customer_id := adjust_customer_id()
	if customer_id == "":
		return
	var episode_id := Day1Events.episode_id_of(customer_id)
	var episode := ScheduleData.episode_data(customer_id, episode_id)
	var order = episode.get("order", {})
	var lines: Array = []
	if order is Dictionary and (order as Dictionary).get("reask", []) is Array:
		lines = ((order as Dictionary).get("reask", []) as Array).duplicate()
	if lines.is_empty():
		lines = (episode.get("greet", []) as Array).duplicate()
	reask_customer_id = customer_id
	reask_lines = lines
	changed.emit()
