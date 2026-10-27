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

## 状態が変わったことをUIへ知らせる。各操作の末尾で出す。runner の再生位置が動いたとき（差し替えなど）にも出る。
## UIは出るたびに全体を描き直すだけなので、1回の操作で複数回出てもよい（回数に意味は持たせない）。
signal changed()

## フェーズごとの Event 列を組む直前に出す。UIが、表示だけの状態（スマホの開閉・タブなど）を捨てる合図
## （それらはゲームの状態ではないので session は持たない。DebugPanelが受けて捨てる）。
signal phase_entering(phase: int)

# 判定結果 → 評点（BALANCE_REDESIGN_PLAN.md§5「評判・需要・日程」）。名前あり客・モブの区別はなく、
# どの客でも共通の得点表を使う。評判は閉店時に quality_score() の結果をまとめて
# GameState.settle_reputation() へ渡す1回だけの処理（杯ごとの即時加算はしない）。
const REPUTATION_SCORE := { "GREAT": 100, "GOOD": 75, "OK": 35, "BAD": 0 }

const SKIP_READ_LIMIT := 200   # 暴走防止：1回のスキップで進めるイベント数の上限

## フェーズの一方向遷移と、フェーズ内の Event 再生（runner）を持つ。
var flow: FlowController = null


func _init() -> void:
	flow = FlowController.new()
	flow.name = "FlowController"
	add_child(flow)
	# 日の終わり（NEXT_DAY→WAKEの折り返し。日次リセットの前）：その日の集計を確定して記録する。
	# 本番UIでも自動で走るよう、session が自分で受ける（UIは結線しない）。
	flow.day_ending.connect(on_day_ending)


## 状態が変わったことを知らせる（UIは全体を描き直す）。
func notify_changed() -> void:
	changed.emit()


## 画面が準備できたら1回呼ぶ（DebugPanel は _ready、本番UIもシーンの起動時に）。
## 起動時のセーブ（[続きから]の候補）を読み、初日の初期在庫を積み、いまのフェーズの Event 列を組んでから、
## フェーズの遷移・runner の更新・新しい周の合図を受け始める（この順＝最初の組み立ては通知なしで行う）。
func start() -> void:
	# 1枠セーブ：最初の朝のWAKE処理より前に、起動時のセーブを読んでおく。
	pending_continue = MorningSave.read_file()
	save_armed = pending_continue.is_empty()
	seed_initial_inventory()
	set_runner_for_phase(GameState.phase)
	# 最終日の翌朝の巻き戻し後に、初期在庫を積み直す（reset → 積み直し → phase_changed の順）。
	flow.game_restarted.connect(seed_initial_inventory)
	flow.phase_changed.connect(on_phase_changed)       # フェーズが変わった → Event 列を組み直して知らせる
	flow.runner_updated.connect(changed.emit)           # runner の再生位置が動いた → 知らせる


## 木から外れる（終了）とき、既読を書き出す（変更が無ければ書かない）。
func _exit_tree() -> void:
	ReadState.flush()


# --- 状態（ゲームの意味を持つもの） ---

## 市場で今どの店の中にいるか（例: "produce"）。空文字なら市場のトップ（店の選択）にいる。
## 仕込みに入るたびにリセットする（_set_runner_for_phase）。
var market_shop := ""
## 水場（水道代）にもう寄ったか。仕込みに入るたびにリセットする。
var market_visited_water := false
## ゲームオーバーの理由の文。_set_runner_for_phase(GAME_OVER) が読んで消費する（一度きり）。
var game_over_reason := ""
## ゲームオーバーの種類と額（UI準備B④。表示だけ）。払えなかった支払いの { kind（帳簿のカテゴリ。"daily_cost"／"water"／
## "rent"／"kit"／""＝その他）, amount（必要額）, money（そのときの所持金）, day, phase（どのフェーズで詰んだか） }。
## pay_or_game_over が詰んだときに入れ、再挑戦・新しい周・続きから（reset_transient_state）で消す。読むのは game_over_info()。
var game_over_detail := {}
## 今日はクズ野菜ベースか（所持金がベース代に満たないので端材屋へ回った日）。仕込みに入る瞬間に1回だけ決める。
var scraps_base := false


# --- 予算（共通） ---

## 予算：残金（所持金そのもの）・支払い予定（reserved。まだ払っていない請求＝日々の運営費〔水と炭〕と徴収日の場所代・水道代）・使える現金（残金−支払い予定）。
## operating は、そのうち日々の運営費（水と炭）の分。
func budget() -> Dictionary:
	return { "money": GameState.money, "reserved": Ledger.pending_bills_today(), "usable": Ledger.usable_cash(),
		"operating": operating_cost_pending() }


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
			"fresh": fresh, "damaged": damaged, "affordable": price <= purchase_limit(), "kind": kind })
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
			"servings": int(tier.get("servings", 0)), "price": price, "affordable": price <= purchase_limit() })
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
			if purchase_block_reason(price) != "":
				break   # 使える現金（残金−支払い予定）を超える購入は受けない
			if id == "dashi":
				GameState.apply_money(-price)
				GameState.buy_dashi()
				Ledger.record("dashi", -price, "dashi", 1, price)
			else:
				var item = good.get("item", id)
				var count: int = int(good.get("count", 1))
				var unit_price: int = int(price / count) if count > 0 else price
				GameState.apply_money(-price)
				GameState.add_inventory(item, count, unit_price)
				Ledger.record("market", -price, str(item), count, unit_price)
			break
	changed.emit()


## 買える額の上限：使える現金（残金−支払い予定）。買い物（市場の商品・鍋の素）はこれを超えて買えない。
func purchase_limit() -> int:
	return Ledger.usable_cash()


## 価格 price の購入を受けられない理由（買えるなら ""）。pending は、画面のかごの合計など、すでに取り置いた額。
## 使える現金（残金−支払い予定）で判断する＝確保した請求（場所代・水道代・運営費）に手を付けて買えない。
func purchase_block_reason(price: int, pending: int = 0) -> String:
	var limit := purchase_limit() - pending
	if price <= limit:
		return ""
	return "使える現金（残金−支払い予定）は ¥%d。¥%d は買えない" % [maxi(limit, 0), price]


## 仕込みの段階を選ぶ（支払って、残りの仕込みの列をその場で組み直す）。使える現金（残金−支払い予定）が足りなければ何もしない。
## 差し替え後の列の先頭は効果の無いTEXT（EventRunner の仕様で先頭は適用されない）。
func choose_prep_tier(tier_id: String) -> void:
	var tier := Day1Events.prep_tier_by_id(tier_id)
	var price: int = int(tier.get("price", 0))
	if purchase_block_reason(price) != "":
		return   # 使える現金（残金−支払い予定）を超える購入は受けない
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


## [市場を出る]：水場に未訪問なら自動で訪れて水道代（徴収日だけ）を払い、日々の運営費（水と炭）を引いて、入力完了して先へ進む（仕込みの続きへ）。
## 訪問済み・未訪問に関わらず常に押せる（水汲み忘れで詰まらせない）。水道代が払えずゲームオーバーに
## なったら先へ進まず false（進んだら true）。
func exit_market() -> bool:
	if not market_visited_water:
		if not visit_water_stall():
			return false
	# 日々の運営費（水と炭）：市場を出るときに引く（「水を汲み、炭を買った」。UI準備D・D-4）。払えなければゲームオーバー。
	if not pay_operating_cost():
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
	game_over_detail = { "kind": category, "amount": amount, "money": GameState.money, "day": GameState.day_count,
		"phase": GameState.phase }
	game_over("所持金が足りない。支払えない（必要 ¥%d／所持 ¥%d）。" % [amount, GameState.money])
	return false


## 払えるかだけを見る（払わない）。払えれば true。払えなければ pay_or_game_over と同じ内容でゲームオーバーにして false。
## 朝の日々の運営費（引くのは市場を出るとき）に使う＝ゲームオーバーの判定は今までどおり朝。
func check_or_game_over(amount: int, category: String = "") -> bool:
	if GameState.money >= amount:
		return true
	game_over_detail = { "kind": category, "amount": amount, "money": GameState.money, "day": GameState.day_count,
		"phase": GameState.phase }
	game_over("所持金が足りない。支払えない（必要 ¥%d／所持 ¥%d）。" % [amount, GameState.money])
	return false


## まだ引いていない日々の運営費（水と炭）。朝に確保（ref:"operating"）し、引いたとき解く。帳簿から読む（今日の分だけ）。
func operating_cost_pending() -> int:
	var total := 0
	for entry in GameState.ledger:
		if int(entry.get("day", -1)) == GameState.day_count and str(entry.get("ref", "")) == "operating" \
				and str(entry.get("category", "")) in ["reserve", "release"]:
			total += int(entry.get("amount", 0))
	return -total


## 日々の運営費（水と炭）を引く（まだ引いていなければ）。払えなければゲームオーバーで false。引いたら帳簿の確保を解く。
func pay_operating_cost() -> bool:
	var pending := operating_cost_pending()
	if pending <= 0:
		return true
	if not pay_or_game_over(pending, "daily_cost"):
		return false
	Ledger.record("release", pending, "", 0, 0, "operating")
	return true


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

# 足りなかった杯数の理由別（UI準備C③。記録だけで、ゲームの結果には関与しない）。判断の瞬間に積む：
# "ingredients"＝素材が足りなくて出せなかった／"pot"＝鍋（残量・濃さ）で出せなかった（閉店で打ち切った客を含む）／
# "declined"＝出せたのに断った。閉店のあと来られなかった客の分は積まず、日の終わりに「出せなかった合計−この3つ」
# として unserved_not_arrived に出す（unserved_breakdown）。WAKE・OPEN突入でリセット。
var log_unserved := { "ingredients": 0, "pot": 0, "declined": 0 }
## [客を断る]を押した時点の理由（pending_decline と同じ寿命。_serve_customer_decline が積む）。
var pending_decline_reason := "declined"


# --- 足りなかった杯数の理由別（UI準備C③。記録だけ） ---

## 理由別の記録へ cups 杯を足す。理由が空・杯数が0以下なら何もしない。
func _add_unserved(reason: String, cups: int) -> void:
	if cups <= 0 or reason == "":
		return
	var key := reason if log_unserved.has(reason) else "declined"
	log_unserved[key] = int(log_unserved[key]) + cups


## 今の椀を作ったまま[客を断る]を押したときの理由。鍋（残量・濃さ0）で出せない＝"pot"。味・具の素材が欠けていて、
## 手元の在庫に味か具の素材が1つも無い＝"ingredients"。それ以外（出せたのに断った、在庫はあるのに椀を作らなかった）＝"declined"。
func _bowl_block_reason() -> String:
	if open == null:
		return "declined"
	var reasons: Array = SaleRule.check(open.current_bowl, GameState.soup, { "servings": current_servings() }).get("reasons", [])
	if reasons.has(SaleRule.SHORT_SERVINGS) or reasons.has(SaleRule.STRENGTH_ZERO):
		return "pot"
	if reasons.has(SaleRule.NO_FLAVOR) or reasons.has(SaleRule.NO_TOPPING):
		return "ingredients" if _stock_lacks_flavor_or_topping() else "declined"
	return "declined"


## 手元の在庫（新鮮・傷んだ）に、味の素材か具の素材が1つも無いか。
func _stock_lacks_flavor_or_topping() -> bool:
	var has_flavor := false
	var has_topping := false
	for id in GameState.inventory:
		if str(id) == "soup_base" or GameState.fresh_count(id) + GameState.damaged_count(id) <= 0:
			continue
		has_flavor = has_flavor or Ingredients.is_flavor(str(id))
		has_topping = has_topping or Ingredients.is_topping(str(id))
	return not (has_flavor and has_topping)


## モブの団体：注文 ordered 人に対して actual 人しか出さない（0＝断る）ときの、出せなかった分の理由。
## 出し切るなら空。出せる人数が1以上なのに断った＝"declined"。出せなかった場合は、出せる人数を決めた制約で分ける
## （濃さ0＝鍋／味・具が欠けた椀＝素材［在庫に素材があるのに作らなかったなら断った］／鍋の残量と具材の在庫の小さい方。同じなら鍋）。
func _mob_shortfall_reason(ordered: int, actual: int) -> String:
	if actual >= ordered:
		return ""
	if actual <= 0 and mob_achievable_servings(ordered) >= 1:
		return "declined"
	if GameState.soup == null or int(GameState.soup.get("strength", 3)) <= 0:
		return "pot"
	if open != null:
		var reasons: Array = SaleRule.check(open.current_bowl, GameState.soup).get("reasons", [])
		if reasons.has(SaleRule.NO_FLAVOR) or reasons.has(SaleRule.NO_TOPPING):
			return "ingredients" if _stock_lacks_flavor_or_topping() else "declined"
	return "pot" if int(GameState.soup.get("remaining_servings", 0)) <= _mob_ingredient_limit(ordered) else "ingredients"


## 選んだ具材のバケツ別の在庫から決まる、出せる人数の上限（mob_achievable_servings の具材の項と同じ数え方）。選んでいなければ ordered。
func _mob_ingredient_limit(ordered: int) -> int:
	var limit := ordered
	var counts := {}
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
		limit = mini(limit, int(avail / int(counts[key])))
	return limit


## 今の客（いまの接客の runner の現在位置から先）に、まだ出していない注文の杯数。閉店で打ち切るときの、その客の分。
func _cups_left_for_current_customer() -> int:
	if flow.runner == null:
		return 0
	var total := 0
	for i in range(maxi(flow.runner.index, 0), flow.runner.events.size()):
		var ev = flow.runner.events[i]
		if ev is Dictionary and str(ev.get("type", "")) == "REACT":
			total += int(ev.get("servings", 0))
	return total


## 今夜の足りなかった杯数の内訳（キーは日次ログと同じ）。理由別の記録に無い分（閉店のあと来られなかった客）は
## unserved_not_arrived（出せなかった合計−理由別の合計）。4つの合計は unserved_cups と同じ。
func unserved_breakdown() -> Dictionary:
	var unserved := maxi(log_planned_cups - int(tonight_totals()["served_cups"]), 0)
	var tracked := int(log_unserved["ingredients"]) + int(log_unserved["pot"]) + int(log_unserved["declined"])
	return { "unserved_cups": unserved, "unserved_ingredients": int(log_unserved["ingredients"]),
		"unserved_pot": int(log_unserved["pot"]), "unserved_declined": int(log_unserved["declined"]),
		"unserved_not_arrived": maxi(unserved - tracked, 0) }


## その夜に1杯以上提供したモブの種類（重複なし・並びは種類idの順）。モブの客は instance id（"mob#N"）で記録されるので、
## 今夜の計画（today_plan の mob_instances）から種類を引く。
func mob_types_served_tonight() -> Array:
	var types := []
	var instances: Dictionary = GameState.today_plan.get("mob_instances", {})
	for record in GameState.served:
		if not (record is Dictionary) or bool(record.get("discarded", false)) or int(record.get("servings", 0)) <= 0:
			continue
		var customer := str(record.get("customer", ""))
		if not Day1Events.is_mob_customer(customer):
			continue
		var type_id := str((instances.get(customer, {}) as Dictionary).get("type", ""))
		if type_id != "" and not types.has(type_id):
			types.append(type_id)
	types.sort()
	return types


## 画面に出す内訳（素材が足りない／鍋が足りない／断った）。閉店のあと来られなかった客の分は「鍋が足りない」に含める。
## 内訳のキーが無い古い記録（C③より前のセーブ）は空の辞書。record は日次ログの1日分か tonight_result() の結果。
static func unserved_display(record: Dictionary) -> Dictionary:
	if not record.has("unserved_pot"):
		return {}
	return { "ingredients": int(record.get("unserved_ingredients", 0)),
		"pot": int(record.get("unserved_pot", 0)) + int(record.get("unserved_not_arrived", 0)),
		"declined": int(record.get("unserved_declined", 0)) }


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
					_serve_mob_partial(ev, int(result.get("servings", 0)), int(result.get("ordered", 0)),
						str(result.get("reason", "")))
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
		_sync_bowl_takes()
		bowl_takes.append(GameState.take_inventory(ingredient_id, servings, damaged))
	changed.emit()


## 椀の具材ごとに、在庫から引いた中身（束・個数）。追加の取り消しで同じ束へ戻すための記録（表示用の状態で保存しない）。
## additions と同じ並び。椀が替わったら（current_bowl が別の辞書になったら）捨てる。団体客（モブ）は在庫をまだ引かないので持たない。
var bowl_takes: Array = []
var _takes_bowl: Variant = null


func _sync_bowl_takes() -> void:
	if open == null:
		return
	if not is_same(_takes_bowl, open.current_bowl):
		_takes_bowl = open.current_bowl
		bowl_takes = []


## 椀の具材ボタン：椀に無ければ入れる（select_ingredient）、すでに入っていれば取り消す（椀から外し、在庫を戻す。UI準備D・D-3）。
## 傷んだ側・新鮮な側のどちらのボタンでも、同じ品目が椀にあれば取り消す＝同じ具材を2個は入れられない。
func toggle_ingredient(ingredient_id: String, damaged: bool = false) -> void:
	if open == null:
		return
	var index := (open.current_bowl.get("additions", []) as Array).rfind(ingredient_id)
	if index >= 0:
		cancel_ingredient(index)
	else:
		select_ingredient(ingredient_id, damaged)


## 椀の index 番目の具材を取り消す（椀を作っている最中だけ）。引いた在庫を元の束へ戻す。団体客は確定まで在庫を引かないので、選びの記録だけ外す。
func cancel_ingredient(index: int) -> void:
	if open == null or not is_choosing_ingredients():
		return
	var additions: Array = open.current_bowl.get("additions", [])
	if index < 0 or index >= additions.size():
		return
	var ingredient_id := str(additions[index])
	if is_current_mob_order():
		for i in range(mob_picks.size() - 1, -1, -1):
			if str(mob_picks[i]["id"]) == ingredient_id:
				mob_picks.remove_at(i)
				break
	else:
		_sync_bowl_takes()
		if bowl_takes.size() != additions.size():
			return   # 引いた中身を覚えていない具材（通常は無い）は取り消さない
		GameState.restore_inventory(ingredient_id, bowl_takes[index])
		bowl_takes.remove_at(index)
	open.remove_from_bowl(index)
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
	_add_unserved(pending_decline_reason, int(ev.get("servings", 1)))
	pending_decline_reason = "declined"
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


## いま店主の距離感の選択（CHOICE。システム整理C2）の入力待ちか。
## [次のEvent]/[入力完了] を無効化する判定に使う（選択は選択肢のボタンで答える）。
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
	_add_unserved("pot", _cups_left_for_current_customer())
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
func _serve_mob_partial(ev: Dictionary, actual: int, ordered: int, reason: String = "") -> void:
	_add_unserved(reason, maxi(ordered - actual, 0))   # 出せなかった分（この団体の最後のレシピ）の理由別の記録
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

# --- 状態（UI準備A③b）---

# [鍋を見る] の操作モード中か（DESIGN.md 7.6）。
# EventRunner には一切触れない＝ index も status も動かさない。表示と操作対象を
# 切り替えるだけなので、会話は止まったまま鍋をいじって戻れる。
var pot_open := false

# 鍋モードに入った時点で鍋が空（残量0以下）だった場合、水を入れるまでの間だけ true。
# open_pot() で毎回リセットする。
var pot_water_added := false

# 鍋モードに入った時点で濃さ0（提供不可）だった場合、濃縮だしを入れるまでの間だけ true。
# pot_water_added と同じ形（濃さメカニクス三点セット）。open_pot() で毎回リセットする。
var pot_dashi_added := false


# --- 鍋・団体・断る（UI準備A③b） ---

## [鍋を見る] のハンドラ（7.6）。モードに入るだけで、EventRunner には触れない。
## 鍋モードに入るたびに「水を入れたか」「だしを入れたか」をリセットする
## （pot_locked_until_water / pot_locked_until_dashi 用）。
func open_pot() -> void:
	pot_open = true
	pot_water_added = false
	pot_dashi_added = false
	changed.emit()


## 鍋モードを抜ける（会話へ戻る。EventRunner には触れない）。保留中の客の処理は含まない
## （鍋が尽きて選択待ちだった客は、resume_after_shortage() か close_shop() で決める）。
## 本番UIでは、鍋タブから別のタブへ切り替えたときに呼ぶ（表示の切り替えに対応）。
func close_pot() -> void:
	pot_open = false
	changed.emit()


## 鍋が尽きて保留中の客に、「営業を続ける」を選ぶ（7.6）。保留中のREACTをここで初めて適用して提供する。
## 作り直しが実際に足りているかは再チェックしない（一度決めたら、その結果のまま提供する）。
## 鍋モードの出入りとは独立した操作（DebugPanelの[戻る]は、モードを抜けてからこれを呼ぶだけ。本番UIの
## 鍋⇄トッピングは表示の切り替えだけで[戻る]に当たる操作が無いので、これを「営業を続ける」ボタンから呼ぶ）。
## 保留が無ければ何もしない。
func resume_after_shortage() -> void:
	if pending_shortage_ev == null:
		return
	var ev = pending_shortage_ev
	pending_shortage_ev = null
	_serve_customer(ev)
	changed.emit()


## 鍋が尽きて、「営業を続ける」か「閉店」かの選択待ちの客がいるか（pending_shortage_ev が入っている間）。
## このとき、次のEvent・入力完了は押せない（can_next_event／can_complete_input が false）。
func is_shortage_pending() -> bool:
	return pending_shortage_ev != null


## [閉店] のハンドラ（7.6）。鍋が尽きて選択待ちのとき、またはADJUST中に鍋が足りず水も
## 無いときだけ押せる（can_close_now）。保留中のREACTは適用しない（この客には出せなかった
## 扱い）。理由テキストを添えてCLOSEへ飛ばす。評判・売上の扱いは変えない。
## 場所代が未払いなら、CLOSEへ飛ばす前に特別請求する（§11「未解決」の直し方の実装。
## _reason_after_collecting_rent参照）。払えずゲームオーバーになったらCLOSEへは進まない。
func close_shop() -> void:
	if not can_close_now():
		return
	var reason := reason_after_collecting_rent("（今日はここで店じまいにする。）")
	if reason == "":
		return
	_add_unserved("pot", _cups_left_for_current_customer())   # 閉店で打ち切った今の客の分（鍋が足りない）
	pending_shortage_ev = null
	pot_open = false
	closed_early_reason = reason
	queue_unserved_exit()
	log_closed_early = true   # 日次ログ：鍋不足で名前あり客を最後まで回せなかった
	flow.force_phase(GameState.Phase.CLOSE)
	changed.emit()


## 鍋モードの [水を足す] / [だしを足す]。効果は GameState の入口にまとめてある
## （残量・濃さ・資源が同時に動くので、受け側から分けて呼べないようにしている）。
func add_water() -> void:
	GameState.add_water()
	pot_water_added = true
	log_water_used += 1   # 日次ログ：水を足した回数
	changed.emit()


func add_dashi() -> void:
	GameState.add_dashi()
	pot_dashi_added = true
	log_dashi_used += 1   # 日次ログ：だしを足した回数
	changed.emit()


## 鍋モードに入った時点で鍋が空（残量0以下）だった場合、水を入れる（pot_water_added）
## までの間だけ true（DESIGN.md 7.6：だしだけ入れても煮出す水が無く意味をなさない）。
## "どうやって鍋モードに入ったか" ではなく "残量が実際に空かどうか" で判定するので、
## 選択待ち経由でも普段の任意タイミングでの訪問でも同じルールが自然にかかる。
func pot_locked_until_water() -> bool:
	if pot_water_added:
		return false
	if GameState.soup == null or int(GameState.soup.get("remaining_servings", 0)) > 0:
		return false
	# 鍋操作不能バグの修正：残量0でも、濃さが低すぎて「今すぐは」水を出せない
	# （can_add_water()がfalse）場合はロックしない。ロックしたままだと、
	# だしボタンも「水待ちロック中」を理由に塞がれ、濃さを上げる唯一の手段である
	# だしすら使えなくなり、詰んでしまう（濃さが上がって初めて水が出せるように
	# なる、という順序を考慮できていなかった）。水が今すぐ出せる状態でだけ
	# 「まず水を」の順序を強制する。
	return GameState.can_add_water()


## 濃さメカニクス三点セット：鍋モードに入った時点で濃さ0（提供不可）だった場合、
## 濃縮だしを入れる（pot_dashi_added）までの間だけ true。pot_locked_until_water() と
## 同じ形（"どうやって入ったか"ではなく"濃さが実際に0かどうか"で判定）。
func pot_locked_until_dashi() -> bool:
	if pot_dashi_added:
		return false
	return GameState.soup != null and int(GameState.soup.get("strength", 3)) <= 0


## 「N人分を提供」ボタン。人数を確定してADJUST→SERVEへ進める（実際の消費・判定・売上・
## 評判・記録はREACT到達時の_serve_mob_partial()で行う。Event（データ）はここでは
## 一切書き換えない）。レシピ1のときだけ元注文数を覚える（レシピ2ではordered自体が
## 「残り人数」になるため、_mob_original_orderedを上書きしない）。
func group_serve(n: int, ordered: int) -> void:
	if mob_recipe_number == 1:
		mob_original_ordered = ordered
	pending_group_result = { "servings": n, "ordered": ordered, "reason": _mob_shortfall_reason(ordered, n) }
	pending_group_choice = false
	complete_input_and_advance()


## 「注文を断る」ボタン。人数0で確定させる（_serve_mob_partial側で「断り」として扱う）。
func group_decline(ordered: int) -> void:
	if mob_recipe_number == 1:
		mob_original_ordered = ordered
	pending_group_result = { "servings": 0, "ordered": ordered, "reason": _mob_shortfall_reason(ordered, 0) }
	pending_group_choice = false
	complete_input_and_advance()


## 「残り◯人に別の具材で挑戦する」ボタン（団体客の分割提供：最大2レシピ）。達成可能分
## （achievable）はこの場で確定・提供し、残り（ordered-achievable）人ぶんを2レシピ目の
## ADJUSTへ回す。mob_recipe_number==1のときしか出さないボタンなので、ここに来る時点で
## 必ずレシピ1（_serve_mob_recipe_and_retry側でレシピ番号を2へ進める）。
func group_retry(achievable: int, ordered: int) -> void:
	if mob_recipe_number == 1:
		mob_original_ordered = ordered
	pending_group_result = { "servings": achievable, "ordered": ordered,
		"retry_remaining": ordered - achievable }
	pending_group_choice = false
	complete_input_and_advance()


## [客を断る]のハンドラ（F3・DESIGN.md 10.3.6）。名前あり客・配達員のADJUST中、いつでも
## 押せる（達成可能かどうかを問わない。モブの「注文を断る」は既に無条件で選べるので対象外＝
## is_current_mob_order()のときはこのボタン自体を出さない）。判定・鍋消費・売上を一切
## 発生させず、_pending_group_serveと同じ「ADJUST側で確定させてREACT到達時に反映する」
## パターンでSERVE→REACTへ進める。
func decline_customer() -> void:
	pending_decline = true
	pending_decline_reason = _bowl_block_reason()
	complete_input_and_advance()


# --- 押せるか・団体の確認（問い。UI準備A③b） ---
# どれも「ゲームの状態として押せるか」だけを返す。スマホを開いている間の無効化など、表示だけの状態は
# UI側で足す（DebugPanelは `or _phone_mode` を足している）。

## 鍋を触れるか（鍋モードに入れるか）。鍋が無い・もう鍋モード中・判定待ち（SERVE）・ゲームオーバー・足せるものが無い、
## のときは false。残量不足を埋められるのは水（だし経由を含む）、濃さ0を埋められるのはだしだけで、独立に見る。
## UI準備C④（DESIGN.md 7.6）：椀を作っている最中（ADJUST）も、足りているときを含めて鍋を触れる（以前は、残量不足か濃さ0の
## ときだけだった）。濃さは判定の瞬間（REACT）に読むので、椀を作る途中に手当てしても判定は正しい。SERVE中（椀を確定して
## から判定まで）は、判定の前に濃さを変えられないよう、今までどおり触れない。
func can_touch_pot() -> bool:
	var servings_short := is_servings_short_context()
	var strength_zero := is_strength_zero()
	var nothing_to_add: bool
	if servings_short or strength_zero:
		var can_fix_servings := servings_short and GameState.water_reachable()
		var can_fix_strength := strength_zero and GameState.can_add_dashi()
		nothing_to_add = not can_fix_servings and not can_fix_strength
	else:
		nothing_to_add = not GameState.can_add_water() and not GameState.can_add_dashi()
	return not (GameState.soup == null or pot_open \
			or is_awaiting_react() \
			or GameState.phase == GameState.Phase.GAME_OVER or nothing_to_add)


## 次のEventへ進めるか（会話を進める）。鍋モード中・鍋不足の選択待ち・市場・仕込みの段階選択・
## 物語の選択・団体の確認の間は false。
func can_next_event() -> bool:
	return not (pot_open or pending_shortage_ev != null \
			or is_in_market() or is_in_prep_tier() or is_in_story_choice() or pending_group_choice)


## 入力完了（提供）できるか。can_next_event の条件に加えて、鍋不足・濃さ0・具や味が欠けた椀のADJUSTでは
## 名前あり客は塞ぐ（モブは達成可能人数の計算に含めるので塞がない）。
func can_complete_input() -> bool:
	return not (pot_open or pending_shortage_ev != null \
			or is_in_market() or is_in_prep_tier() or is_in_story_choice() or pending_group_choice \
			or (is_short_in_adjust() and not is_current_mob_order()) \
			or (is_strength_zero_in_adjust() and not is_current_mob_order()) \
			or (is_bowl_unsellable_in_adjust() and not is_current_mob_order()))


## 廃棄（椀を作り直す）できるか。鍋の残量が客の注文に満たないときは、無駄にできる一杯が無いので false。
func can_discard() -> bool:
	return not is_short_now()


## 客を断れるか。名前あり客・配達員だけ（モブは団体の確認の「注文を断る」で断る）。
func can_decline() -> bool:
	return not is_current_mob_order()


## 聞き直せるか（名前あり客のADJUST中。モブと3杯専用列は不可）。
func can_reask() -> bool:
	return adjust_customer_id() != ""


## モブの団体の確認（入力完了を押したあとの「N人分を提供／注文を断る／残りに挑戦」）の中身。
## 確認中でなければ空。{ ordered, achievable, remaining, recipe_number, can_serve, can_retry }
##   achievable：今の鍋・具材で出せる人数（毎回計算し直す＝鍋に寄り道して水を足したあとも最新）。
##   can_serve：achievable が1以上。can_retry：レシピ1で、出せる人数が注文に満たないとき（最大2レシピ）。
## 「注文を断る」は常に選べる（group_decline）。
func mob_group_choice() -> Dictionary:
	if not pending_group_choice:
		return {}
	var ordered := int(react_for_now().get("servings", 0))
	var achievable := mob_achievable_servings(ordered)
	return { "ordered": ordered, "achievable": achievable, "remaining": ordered - achievable,
		"recipe_number": mob_recipe_number, "can_serve": achievable >= 1,
		"can_retry": mob_recipe_number == 1 and achievable < ordered }

# --- 状態（UI準備A③c）---

# 前日の営業成績（翌朝のWAKE先頭で一度だけ見せる一言サマリー）。_game_over_reasonと
# 同じ「一度だけ消費するテキスト」の形。on_day_ending()（day_ending。NEXT_DAY→WAKEの
# 折り返し直前に発火）で組み立て、次にWAKEのrunnerを組むときに読んで空文字へ戻す。
var last_day_summary_text := ""

# 修繕基金（4-9。RepairFund）：段階が上がった瞬間の一行（CLOSEの間だけ出す。runnerのイベントではない）。
var fund_notice := ""

# 積む先の対象のid（選択は実行時のみ・保存しない）。空・修繕済み・未解放なら既定（最初の未修繕の対象）を使う。
var fund_target := ""


# --- 閉店・日次ログ・基金（UI準備A④） ---

## 日次ログの本体（FlowController.day_ending。NEXT_DAY→WAKEの折り返しで、日次リセットの
## 前に発火する）。GameStateがまだその日の値のうちに集計を確定し、コンソールとファイルへ
## 出す。④評判の更新（BALANCE_REDESIGN_PLAN.md§5）：ここで初めて、当夜品質Qから
## GameState.settle_reputation()を1回だけ呼んで評判を確定させる（OPEN中は動かさない）。
func on_day_ending() -> void:
	ReadState.flush()   # 既読は日の終わりに書き出す（1行ごとには書かない）
	var totals := tonight_totals()
	var served_cups := int(totals["served_cups"])
	var sale_total := int(totals["sale_total"])
	var unserved_cups: int = maxi(log_planned_cups - served_cups, 0)
	var spoiled_value := spoiled_value(log_spoiled_items)
	var quality := quality_score(log_quality_counts, log_judged_planned_cups)
	# 4-2：常連（名前あり客）への提供の杯数・GREAT・GOOD以上と、その日に来た常連のid。
	# 結果画面の「常連GREAT」「客との間に残ったこと」の元になる（Result.regular_stats）。
	var regulars := Result.regular_stats(GameState.served)
	GameState.settle_reputation(quality)
	var log_entry := {
		"day": GameState.day_count,
		"opening_money": log_opening_money, "closing_money": GameState.money,
		"opening_reputation": log_opening_reputation, "closing_reputation": GameState.reputation,
		"planned_cups": log_planned_cups, "served_cups": served_cups,
		"unserved_cups": unserved_cups, "sale_total": sale_total,
		"quality_counts": log_quality_counts.duplicate(),
		"judged_planned_cups": log_judged_planned_cups, "quality": quality,
		"spoiled_items": log_spoiled_items.duplicate(),
		"spoiled_value": spoiled_value,
		"water_used": log_water_used, "dashi_used": log_dashi_used,
		"closed_early": log_closed_early,
		# F4 前日成績v2（DESIGN.md 10.8.4）：Ledgerから初めて出せるようになった追加情報。
		# 既存キーは1つも変更していない（balance_log.jsonlの互換性を保つため、追加のみ）。
		"spend_by_category": Ledger.spend_by_category_today(),
		# 4-2 結果画面用（追加のみ）：常連の杯数・GREAT・GOOD以上・来店した常連のid。
		"regular_cups": int(regulars["cups"]), "regular_great": int(regulars["great"]),
		"regular_good_plus": int(regulars["good_plus"]),
		"regular_visits": regulars["visits"],
	}
	# UI準備C③：足りなかった杯数の内訳（追加のみ。既存のキーは変えない）。4つの合計は unserved_cups と同じ。
	var breakdown := unserved_breakdown()
	for key in ["unserved_ingredients", "unserved_pot", "unserved_declined", "unserved_not_arrived"]:
		log_entry[key] = int(breakdown[key])
	# UI準備C③：その夜に1杯以上提供したモブの種類（DMの出す条件「同じ種類のモブに2夜提供」の元。保存は day_records に入る）
	log_entry["mob_types_served"] = mob_types_served_tonight()
	# UI準備E：その夜に来る予定だった名前あり客・モブの種類（来店予告DMを過去の日も同じ内容で出すため。計画は翌朝に作り直されて残らない。追加のみ）
	log_entry["planned_regulars"] = Dm.plan_regulars(GameState.today_plan)
	log_entry["planned_mob_types"] = Dm.plan_mob_types(GameState.today_plan)
	print("BALANCE_LOG: day=%d money=%d→%d rep=%d→%d(Q=%.1f) cups=%d/%d(計画%d) 売上=%d 廃棄額=%d 水%d/だし%d 早期閉店=%s 評価=%s" % [
		log_entry["day"], log_entry["opening_money"], log_entry["closing_money"],
		log_entry["opening_reputation"], log_entry["closing_reputation"], quality,
		served_cups, unserved_cups, log_planned_cups, sale_total, spoiled_value,
		log_water_used, log_dashi_used, str(log_closed_early), str(log_quality_counts)])
	BalanceLog.append(log_entry)
	# 4-2：1日の記録を周回の累計へ足す（結果画面の集計元。朝の辞書に入るので、再挑戦・
	# 続きからで戻した朝より後の日は持たない）。
	GameState.record_day(log_entry)
	# 日次の成績表示（③）：今日作ったlog_entryをそのまま人間向けの文にして、次のWAKE（別日）の先頭で一度だけ見せる。ここでのdebug_panel.gd内のローカル変数ではなくlog_entryの値だけを使うのは、日次ログファイルJSONと完全に同じ内容にして、二重の集計ロジックを作らないため。
	last_day_summary_text = format_day_summary(log_entry)


## 日次の成績表示（③）：on_day_ending()が組み立てたlog_entry（opening/closingの所持金・評判、
## 提供杯数、売上、品質内訳、廃棄額、水・だし回数、早期閉店）を、プレイヤー向けの
## 日本語一言サマリーへ整形する。日内ログファイルJSONと同じlog_entryだけを参照し、新しい集計はしない。
func format_day_summary(log_entry: Dictionary) -> String:
	var money_diff: int = int(log_entry["closing_money"]) - int(log_entry["opening_money"])
	var counts: Dictionary = log_entry["quality_counts"]
	var lines := PackedStringArray([
		"◆前日（Day%d）の成績◆" % int(log_entry["day"]),
		"所持金: %d → %d（%s%d）" % [
			int(log_entry["opening_money"]), int(log_entry["closing_money"]),
			"+" if money_diff >= 0 else "", money_diff],
		"評判: %d → %d" % [
			int(log_entry["opening_reputation"]), int(log_entry["closing_reputation"])],
		"提供: %d/%d杯（未提供%d杯）　売上: %d" % [
			int(log_entry["served_cups"]), int(log_entry["planned_cups"]),
			int(log_entry["unserved_cups"]), int(log_entry["sale_total"])],
		"品質: GREAT%d GOOD%d OK%d BAD%d（Q=%.1f）" % [
			int(counts.get("GREAT", 0)), int(counts.get("GOOD", 0)),
			int(counts.get("OK", 0)), int(counts.get("BAD", 0)), float(log_entry["quality"])],
		"廃棄額: %d　水%d回／だし%d回" % [
			int(log_entry["spoiled_value"]), int(log_entry["water_used"]), int(log_entry["dashi_used"])],
	])
	# F4 前日成績v2：Ledgerのカテゴリ別支出をそのまま並べる（新しい集計はしない。
	# spend_by_categoryはLedger.spend_by_category_today()の結果をそのまま持つ）。
	var spend_line := _format_spend_by_category(log_entry.get("spend_by_category", {}))
	if spend_line != "":
		lines.append(spend_line)
	# 修繕基金（4-9）：基金を積んだ日だけ、屋台の段階を1行足す（積まなかった日の文面は従来と同一）。
	if RepairFund.enabled() and int((log_entry.get("spend_by_category", {}) as Dictionary).get("fund", 0)) > 0:
		lines.append("屋台: %s" % RepairFund.progress_text())
	if bool(log_entry.get("closed_early", false)):
		lines.append("（鍋が尽きて早めに閉店した）")
	return "\n".join(lines)


## F4 前日成績v2：Ledger.spend_by_category_today()の結果を「運営費80／場所代90」の
## ような1行にする。固定の並び順で、支出が無かったカテゴリ（0または未記帳）は出さない。
## 全カテゴリ0（何も支出が無い日）なら空文字を返す（_format_day_summary側で行を足さない）。
func _format_spend_by_category(spend: Dictionary) -> String:
	const CATEGORY_LABELS := {
		"daily_cost": "運営費", "rent": "場所代", "water": "水道代",
		"kit": "初日セット", "prep": "仕込み", "market": "市場", "dashi": "だし",
		"fund": "修繕基金",
	}
	var parts := PackedStringArray()
	for category in ["daily_cost", "rent", "water", "kit", "prep", "market", "dashi", "fund"]:
		var amount: int = int(spend.get(category, 0))
		if amount > 0:
			parts.append("%s%d" % [CATEGORY_LABELS[category], amount])
	if parts.is_empty():
		return ""
	return "支出内訳: %s" % "／".join(parts)


## discard_spoiled_inventory()が返す各品目の"value"（ロットごとに実際に払った単価×個数の
## 合計。①具材の購入単位でGameStateが計算するようになった）をそのまま足し合わせるだけ。
## 概算はしない（パック購入と小口購入で単価が違っても、GameStateが記録した実額を使う）。
func spoiled_value(spoiled_items: Dictionary) -> int:
	var total := 0
	for item in spoiled_items:
		total += int(spoiled_items[item].get("value", 0))
	return total


## 当夜品質Q（BALANCE_REDESIGN_PLAN.md§5）＝判定した杯の得点合計 ÷ 朝に確定した
## 判定対象杯数（judge:falseの杯は数えない。judged_plannedはOPEN開始時に先読みした
## log_judged_planned_cups）。未提供の杯（部分提供の残り・早期閉店で届かなかった杯）は
## 得点0のまま分母にだけ残る（quality_countsに積まれないため。指示文どおり、未提供への
## 別の固定減点は重ねない）。judged_plannedが0（判定対象の杯が1つも無い日。実際には
## 起こらない想定だがガードする）ならQは0とみなす。
func quality_score(counts: Dictionary, judged_planned: int) -> float:
	if judged_planned <= 0:
		return 0.0
	var total := 0
	for key in REPUTATION_SCORE:
		total += int(REPUTATION_SCORE[key]) * int(counts.get(key, 0))
	return float(total) / float(judged_planned)


## 積む先を切り替える（実行時のみ。保存しない）。修繕済み・未解放・存在しない対象は選べない。
func select_fund_target(target_id: String) -> void:
	if fund_row_available() and not RepairFund.target(target_id).is_empty() and not RepairFund.is_repaired(target_id) \
			and RepairFund.unlocked(target_id):
		fund_target = target_id
	changed.emit()


## 積む。段階が上がったら、label を使った一行を覚えて CLOSE の間だけ表示する。
## ゲームオーバーにはならない（RepairFund.contribute は払えるときだけ払う）。
func contribute_fund(amount: int) -> void:
	if not fund_row_available():
		return
	var before := RepairFund.repaired_ids()
	if RepairFund.contribute(fund_selected(), amount):
		var message := RepairFund.repaired_message(before, RepairFund.repaired_ids())
		if message != "":
			fund_notice = message
	changed.emit()


## いま積む先の対象のid：選んだ対象（未修繕で解放済み）、無効なら最初の未修繕の対象。
func fund_selected() -> String:
	if fund_target != "" and not RepairFund.target(fund_target).is_empty() and not RepairFund.is_repaired(fund_target) \
			and RepairFund.unlocked(fund_target):
		return fund_target
	return RepairFund.first_open_target()


# --- 閉店・日次ログ・基金の問い（UI準備A④。R3：閉店・朝・修繕基金） ---

## 今夜ここまでの提供の合計：{ served_cups（提供した杯数）, sale_total（売上） }。
## 廃棄した杯（discarded）は数えない。日の終わりの集計（on_day_ending）と閉店の画面が同じ値を使う。
func tonight_totals() -> Dictionary:
	var served_cups := 0
	var sale_total := 0
	for record in GameState.served:
		if record is Dictionary and not bool(record.get("discarded", false)):
			served_cups += int(record.get("servings", 0))
			sale_total += int(record.get("sale", 0))
	return { "served_cups": served_cups, "sale_total": sale_total }


## 閉店の「今夜の結果」：{ ordered_cups（朝に確定した注文杯数）, served_cups, unserved_cups, grades（評価の内訳）, sales }。
## 値は日次ログの1日分（on_day_ending が作る log_entry）と同じ元から読む（新しい集計はしない）。
## 未提供の内訳は unserved_ingredients・unserved_pot・unserved_declined・unserved_not_arrived（UI準備C③。画面は unserved_display）。
func tonight_result() -> Dictionary:
	var totals := tonight_totals()
	var served_cups := int(totals["served_cups"])
	var result := { "ordered_cups": log_planned_cups, "served_cups": served_cups,
		"unserved_cups": maxi(log_planned_cups - served_cups, 0),
		"grades": log_quality_counts.duplicate(), "sales": int(totals["sale_total"]) }
	var breakdown := unserved_breakdown()
	for key in ["unserved_ingredients", "unserved_pot", "unserved_declined", "unserved_not_arrived"]:
		result[key] = int(breakdown[key])
	return result


## 朝に見せる前日成績：日次ログの1日分（on_day_ending が作る log_entry と同じキー）。
## 今日より前の日の記録のうち最後のもの。無ければ空（Day1の朝など）。
func previous_day_record() -> Dictionary:
	var last := {}
	for record in GameState.day_records:
		if record is Dictionary and int(record.get("day", 0)) < GameState.day_count:
			last = record
	return (last as Dictionary).duplicate(true)


## 修繕基金の積み立てを今出せるか：機能オン・CLOSE・語りを読み終えた後（runner が DONE）。
## スマホを開いている間は出さない、というUIの状態はここに含めない（DebugPanelが足す）。
func fund_row_available() -> bool:
	return RepairFund.enabled() and GameState.phase == GameState.Phase.CLOSE and flow.runner != null \
			and flow.is_runner_done()


## 修繕基金の画面用の中身：
##   { available, complete, targets[{id,label,paid,price,repaired,locked,selected}], selected,
##     paid_tonight, nightly_max, max_contribution（選んだ対象へ今日積める上限）,
##     steps[{amount,can}]（積める刻みと、いま積めるか）, notice（段階が上がった一行）, reserve（安全上限の根拠） }
## available が false（積み立ての画面ではない）のときは available だけ false の辞書。
func fund_view() -> Dictionary:
	if not fund_row_available():
		return { "available": false }
	var selected := fund_selected()
	var targets: Array = []
	for t in RepairFund.targets():
		var st := RepairFund.target_state(t["id"])
		targets.append({ "id": str(t["id"]), "label": str(st["label"]), "paid": int(st["paid"]), "price": int(st["price"]),
			"repaired": bool(st["repaired"]), "locked": bool(st["locked"]), "selected": str(t["id"]) == selected })
	var steps: Array = []
	for step in RepairFund.steps():
		steps.append({ "amount": int(step), "can": RepairFund.can_contribute(selected, step) })
	return { "available": true, "complete": RepairFund.complete(), "targets": targets, "selected": selected,
		"paid_tonight": RepairFund.paid_tonight(), "nightly_max": RepairFund.nightly_max(),
		"max_contribution": RepairFund.max_contribution(selected), "steps": steps,
		"notice": fund_notice, "reserve": RepairFund.next_day_reserve() }


## 減点の理由コード（開店のトッピング画面の「このままでは提供できません／1段階下がります」の元）。
## まだ判定していない椀について、文ではなく理由のコードと数値だけを返す（文面はUI側が決める）。
##   blockers：提供できない理由（SaleRule のコード：NO_FLAVOR・NO_TOPPING・STRENGTH_ZERO・SHORT_SERVINGS）。
##   penalties：提供はできるが1段階下がる見込みの理由。{ code:"STRENGTH_EXTREME", value:濃さ }（濃さが最小か最大）、
##     { code:"SPOILED" }（傷んだ具材を使っている）。提供できない理由（味・具が欠ける）があるときは空。
## 椀が無いとき（接客中でない）は両方とも空。
func sale_hint() -> Dictionary:
	var out := { "blockers": [], "penalties": [] }
	if open == null or not open.current_bowl.has("customer_id"):
		return out
	var reasons: Array = SaleRule.check(open.current_bowl, GameState.soup).get("reasons", [])
	out["blockers"] = reasons.duplicate()
	if reasons.has(SaleRule.NO_FLAVOR) or reasons.has(SaleRule.NO_TOPPING):
		return out
	var strength := int(GameState.soup.get("strength", 3)) if GameState.soup != null else 3
	if strength == GameState.STRENGTH_MIN or strength == GameState.STRENGTH_MAX:
		out["penalties"].append({ "code": "STRENGTH_EXTREME", "value": strength })
	if bool(open.current_bowl.get("used_spoiled", false)):
		out["penalties"].append({ "code": "SPOILED" })
	return out

# --- 状態（UI準備A③d）---

# F7 1枠セーブ（フェーズ4-1コミット②・DESIGN.md 10.6）。朝の保存ファイル（MorningSave）へ
# 書いてよいか。起動時に有効なセーブがあれば、[続きから]を押すか最初の朝を抜けるまで
# false（起動した瞬間のDay1の朝で上書きして、続きから選べなくなるのを防ぐ）。
var save_armed := true

# 起動時に読めたセーブの封筒（[続きから]で戻す先）。無い・読めない・使用済みなら空。
var pending_continue := {}

# F7 同じ朝への復元（再挑戦・セーブ読み込み）の直後のWAKEで、保存してあるDayPlanを
# そのまま使うための一度きりの印（set_runner_for_phase(WAKE)が読んで消費する。
# _game_over_reasonと同じ「一度だけ」パターン。「今日のplanがあれば作らない」判定に
# しないのは、同じ日にWAKEを繰り返し通る既存の経路・テストで引き直しが止まらないため）。
var plan_restored := false

# デバッグ用：今夜のモブ人数の強制指定（-1＝自動）。Day2-7ダミーデータ・モブ抽選独立化で、
# Day1Events.customer_schedule()へそのまま渡す値になった（枠ごとに種類も人数も独立抽選する
# ため、-1以外なら全モブ枠の人数だけを一律で上書きする。種類はそれでも枠ごとにばらつく）。
# OPENに入る瞬間に読まれるので、変えるなら OPEN に入る前（WAKE・PREP中）に押すこと。
# GameState には持たせない（本番の挙動・データには関係しない、この計器盤だけの検証用の上書き）。
var debug_mob_count := -1

# 会話ログ（4-7②。TalkLog）：すでに記録した位置（日・フェーズ・時間帯・客のindex・イベントのindex・本文）。
# load_current_customer が同じ客で何度呼ばれても・再描画しても二重に記録しないための印。保存しない。
var logged_positions := {}


# --- 朝・再挑戦・続きから・結果・フェーズの組み立て（UI準備A⑤） ---

## フェーズごとの Event 列を runner に差し込む。
## STEP 3: WAKE / STEP 4: PREP / STEP 6: OPEN（客キュー）/ STEP 9: CLOSE。
## NEXT_DAY は空のまま（日次処理は FlowController.advance_phase の折り返し側）。
## 新フェーズを実装するときは、ここに elif を1本足して対応する events を返す。
func set_runner_for_phase(phase: int) -> void:
	# 途中閉店・ゲームオーバー（force_phase）でも、そこまでに提供した杯の評判と提供記録を
	# 失わないよう、客キューを捨てる前に集計を反映する（空なら何もしない）。
	flush_visit_tally()
	open = null   # OPEN 以外では客キューを持たない
	# 7.6: 鍋の選択待ち・鍋モードも OPEN 以外には持ち越さない（防御的リセット）。
	pending_shortage_ev = null
	pot_open = false
	pot_water_added = false
	pot_dashi_added = false
	fund_notice = ""
	fund_target = ""
	# 7.7: 市場の水場訪問フラグ・店の中にいるかも PREP に入るたびリセットする。
	market_visited_water = false
	market_shop = ""
	# 表示だけの状態（スマホの開閉・タブなど）もフェーズをまたいで持ち越さない（防御的リセット）。
	# それはUIの状態なので、ここでは知らせるだけ（DebugPanelが phase_entering を受けて捨てる）。
	phase_entering.emit(phase)
	if phase == GameState.Phase.WAKE:
		TalkLog.clear()   # 会話ログは今日の分だけ（朝へ戻したら空から）
		logged_positions = {}
		played_events = []   # 共通イベントはその日ごと（朝へ戻したら最初から再生し直す）
		slot_event_ids = {}
		# 日次ログ：その日の開始時点として、所持金・評判を記録し、当日ぶんのカウンタを
		# 初期化する（前日の day_ending 発火はもう終わっている＝直前のログには影響しない）。
		# opening_moneyは日々の運営費を引く前の値（その日入ってきた素の所持金）にする。
		log_opening_money = GameState.money
		log_opening_reputation = GameState.reputation
		log_planned_cups = 0
		log_judged_planned_cups = 0
		log_unserved = { "ingredients": 0, "pot": 0, "declined": 0 }
		log_water_used = 0
		log_dashi_used = 0
		log_closed_early = false
		log_quality_counts = { "GREAT": 0, "GOOD": 0, "OK": 0, "BAD": 0, "": 0 }
		log_spoiled_items = {}
		# F7 朝の保存（DESIGN.md 10.8.7）：今日のDayPlanを先に確定させてから、運営費を引く
		# 前の状態を「朝の辞書」にする（運営費の支払いは乱数を引かないので、build()を
		# 先に呼んでも抽選結果・乱数の消費順は従来と変わらない）。再挑戦・セーブ読み込みで
		# 戻った朝（plan_restored）は保存してあるDayPlanをそのまま使い、build()を呼ばない
		# ＝抽選を引き直す手段にしない。
		if plan_restored:
			plan_restored = false
		else:
			DayPlanner.build(debug_mob_count)
		var morning := MorningSave.capture(last_day_summary_text)
		# 日々の運営費（場所代・水道代の再編＋日々の運営費）：WAKEに入った瞬間に必ず1回
		# 直接支払う。wake_events()側にPAY Eventとして置かないのは、WAKEが
		# _phase_can_skip=true（[次のPhase]でrunnerを消化せず進める）なので、Event列に
		# 頼ると支払いを毎回スキップできてしまうため（visit_water_stall()と同じ
		# 「Eventを介さず直接コードで払う」方式に揃える）。
		# 支払えずゲームオーバーになったら、force_phase(GAME_OVER)が既に
		# set_runner_for_phase(GAME_OVER)を呼んでrunnerを組んでいるので、ここで
		# wake_events()のrunnerに上書きしないよう即returnする。
		# UI準備D・D-4：日々の運営費（水と炭）は、朝は払えるかだけを見る（払えなければ今までどおり朝のゲームオーバー）。
		# 実際に引くのは市場を出るとき（exit_market。市場を通らないときは OPEN に入るとき）。それまでは「支払い予定」として確保する。
		if not check_or_game_over(GameState.DAILY_OPERATING_COST, "daily_cost"):
			return
		# 運営費が払える朝だけ記録する（払えずゲームオーバーになった朝へ戻っても、同じ
		# 不足で必ず詰むため。戻れる最後の朝＝GameState.latest_morning()は前日の朝になる）。
		GameState.record_morning(morning)
		# 1枠セーブ：記録と同じ朝の辞書を書く（運営費が払えた朝だけ。読み込んだ朝が
		# 運営費で詰むことは無い）。
		if save_armed:
			MorningSave.write_file(morning)
		# F4 帳簿：今日まだ払っていない請求を「確保」として記帳する（旧GameState.
		# set_pending_bills_for_today()。3-5（DESIGN.md 10.3.5）で徴収日は場所代に加え水道代ぶんも
		# 確保対象に含めた＝実際の支払いタイミングは変えていない。水道代は水場訪問時、場所代は
		# 場所代の支払い時に払い、その瞬間にreleaseする。Ledger.pending_bills_today()がこの記帳から
		# 確保額を計算し直す）。日々の運営費は、市場を出るとき（払ったとき）に確保を解く。
		# 日々の運営費（水と炭）も、市場を出るときに引くまで確保する（ref:"operating"。operating_cost_pending で読める）。
		Ledger.record("reserve", -GameState.DAILY_OPERATING_COST, "", 0, 0, "operating")
		var reserve_amount := 0
		if GameState.is_collection_day():
			reserve_amount = GameState.RENT_PRICE + GameState.WATER_PRICE
		if reserve_amount > 0:
			Ledger.record("reserve", -reserve_amount)
		# 予告（②）：今夜の客の並びは上のDayPlanner.build()で1回だけ確定させ、OPENでは
		# （デバッグの一律上書き中を除き）これを使い回す。以前はOPENに入る瞬間まで客層も
		# 人数も分からなかった＝プレイヤーが仕込み量を勘で決めるしかなかった詰みポイントの
		# 一つだったため、スマホの「SNS」タブ（_format_tonight_memo）で見せられる
		# ようにする。F2 DayPlan（DESIGN.md 10.8.2）：GameState.today_planへ確定させる
		# のはDayPlanner.build()の役目（F7でbuild()の呼び出しは運営費の前へ移した）。
		# 前日の成績（③）：day_ending（NEXT_DAY→WAKEの折り返し）で既に組み立て済みの
		# 一言サマリーがあれば、今日の起床イベントの先頭に差し込む（読んだら消費する。
		# closed_early_reason/_game_over_reasonと同じ「一度だけ」パターン）。
		var wake_ev := Day1Events.wake_events()
		mark_events_played(wake_ev)
		if last_day_summary_text != "":
			# part:"day_summary"：本番UIは会話枠に1行だけ出し、中身は右の枠（昨夜の成績）に構造で出す（UI準備B Q11）。
			# 会話ログ・既読の正本はこの文のまま。
			wake_ev = [{ "type": "TEXT", "text": last_day_summary_text, "part": "day_summary" }] + wake_ev
			last_day_summary_text = ""
		flow.set_runner(wake_ev)
	elif phase == GameState.Phase.PREP:
		# 具材の腐敗: PREPに入る瞬間に1回だけ、腐りきった在庫（4日目以降）を消して、
		# 捨てた品目を先頭の一言テキストで知らせる（市場で買い足しても救われない簡易版）。
		# クズ野菜ベース: 所持金が一番安い仕込み（PREP_TIERS[0]）にも満たなければ、
		# 3段階から選ばせず食肉仲卸ではなく端材屋へ回る（自動）。
		# まだ引いていない運営費（水と炭）を除いた現金で決める（運営費を朝に引いていた頃と同じ判定。UI準備D・D-4）。
		scraps_base = GameState.money - operating_cost_pending() < int(Day1Events.PREP_TIERS[0].get("price", 0))
		var spoiled := GameState.discard_spoiled_inventory()
		log_spoiled_items = spoiled   # 日次ログ用に保持（廃棄額の概算に使う）
		flow.set_runner(Day1Events.prep_events(spoiled, scraps_base))
	elif phase == GameState.Phase.OPEN:
		# 準備を終えて開店するとき、日々の運営費（水と炭）をまだ引いていなければ引く（通常は市場を出るときに引いている）。
		if not pay_operating_cost():
			return
		# 客ループは OpenController に隔離（DESIGN.md 4章）。中身の再生は客ごとの runner。
		# モブの種類・人数は枠ごとにcustomer_schedule()が内部で独立抽選するので、ここでは
		# デバッグ用の一律上書き値（debug_mob_count。-1=自動）をそのまま渡すだけでよい。
		# 予告（②）：通常はWAKEで確定させたGameState.today_plan["slots"]をそのまま使う
		# （客層・人数を開店直前に変えない＝SNSタブで見せた内容と実際の客入りを一致させる）。
		# デバッグの一律上書き中（debug_mob_count>=0）は、ボタンの「次にOPENに入る
		# ときから効く」という既存の挙動を保つため、ここで引き直す（QAの便宜。
		# SNSタブの表示が直前の内容と食い違う可能性があるのは元からデバッグ専用機能
		# なので許容する）。today_plan["slots"]が空（テスト等でWAKEを経由せずOPENへ直接
		# 遷移した場合の防御）のときも同様に引き直す＝WAKEを通らなくても従来どおり
		# 動く（この保険はデバッグ上書きが無い自動抽選でも効くので、テストからの
		# 直接呼び出しでcustomer_schedule()が空振りする心配は無い）。
		if debug_mob_count >= 0 or GameState.today_plan.get("slots", []).is_empty():
			DayPlanner.build(debug_mob_count)
		open = OpenController.new(GameState.today_plan.get("slots", []))
		# 日次ログ：その日の計画杯数（提供できたか否かに関わらず）を、実際の接客より前に
		# 先読みして合算する。customer_events()はGameState.day_countとJSONキャッシュを
		# 読むだけの副作用なし関数なので、ここで呼んでも以後の本編の進行に影響しない。
		# _log_judged_planned_cupsは同時に、judge:falseの杯（配達員の持ち帰り等）を除いた
		# 分も積む（④評判の更新：当夜品質Qの分母。判定対象ではない杯をQから除外するため）。
		log_planned_cups = 0
		log_judged_planned_cups = 0
		log_unserved = { "ingredients": 0, "pot": 0, "declined": 0 }
		for slot in open.schedule:
			for customer_id in slot.get("customers", []):
				for ev in Day1Events.customer_events(str(customer_id)):
					if ev.get("type", "") == "REACT":
						var ev_servings := int(ev.get("servings", 0))
						log_planned_cups += ev_servings
						if bool(ev.get("judge", true)):
							log_judged_planned_cups += ev_servings
		load_current_customer()
	elif phase == GameState.Phase.CLOSE:
		# 7.6: 自動閉店（鍋が尽きた）で来たときだけ、理由テキストを先頭に差し込む。
		# 読んだら消費する（次に通常経路でCLOSEへ来たときに残っていないように）。
		var events := Day1Events.close_events()
		# 営業中に届かなかった共通イベント（早仕舞いなど）を、閉店の語りの前に取り戻す
		# （必須情報を客・営業の長さに依存させない）。時系列（データの並び順）で、再生済みは出さない。
		var overdue := []
		for item in News.pending_events(GameState.day_count, played_events):
			overdue.append_array(News.event_lines(item))
		mark_events_played(overdue)
		events = overdue + events
		# 提供できないまま退店した客の未提供版（理由テキストの次・共通イベントの前）。
		events = pending_close_lines + events
		pending_close_lines = []
		if closed_early_reason != "":
			events = [{ "type": "TEXT", "text": closed_early_reason }] + events
			closed_early_reason = ""
		flow.set_runner(events)
	elif phase == GameState.Phase.GAME_OVER:
		# 最小実装：理由と「（ゲームオーバー）」を出すだけ。以後フェーズは進まない
		# （FlowController.advance_phase が止める）。演出・タイトルへの導線・復帰は対象外。
		flow.set_runner([
			{ "type": "TEXT", "text": game_over_reason },
			{ "type": "TEXT", "text": "（ゲームオーバー）" },
		])
		game_over_reason = ""
	elif phase == GameState.Phase.RESULT:
		ReadState.flush()   # 結果画面でも既読を書き出す
		# 結果画面（4-2・DESIGN.md 10.6）：成績・目標・仮の物語欄の3ブロック。集計は
		# GameState.day_records（周回の累計）と帳簿から導く（Result）。選択肢はResultRow。
		var summary := Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
		var goal_results := Result.judge_goals(summary, Rules.goals(), Rules.final_day())
		flow.set_runner([
			{ "type": "TEXT", "text": Result.format_report(summary) },
			{ "type": "TEXT", "text": Result.format_goals(goal_results) },
			{ "type": "TEXT", "text": Result.format_story(summary, GameState.known_favorite_ids()) },
		])
	else:
		flow.set_runner([])   # NEXT_DAY など未実装フェーズ（空 runner ＝即 DONE）


func on_phase_changed(phase: int) -> void:
	set_runner_for_phase(phase)
	arm_save_after_first_morning(phase)
	changed.emit()


## 起動時にセーブがあったとき、最初の朝（WAKE）を抜けた時点で書き込みを有効にする
## （[続きから]を押さずに新規ゲームを進めた＝上書きしてよい）。この時点で、いまの
## 朝の記録を1枠セーブへ書く（この後の朝は、WAKEが通常どおり書く）。ゲームオーバーで
## 最初の朝を抜けた場合は何も書かない（記録が無い）。
func arm_save_after_first_morning(phase: int) -> void:
	if save_armed or phase == GameState.Phase.WAKE or phase == GameState.Phase.GAME_OVER:
		return
	save_armed = true
	pending_continue = {}
	var morning := GameState.latest_morning()
	if not morning.is_empty():
		MorningSave.write_file(morning)


## Day1開始時の初期在庫を積む（DESIGN.md 7.7）。ゲーム開始時（_ready）と、最終日の翌朝の
## 新規ゲームへの巻き戻し後（game_restarted）の両方から呼ぶ。
## is_empty()でガード＝シーン再読み込み等で二度走っても二重に積まない。
## 巻き戻しでは day_count が1に戻った後に呼ばれるので、購入日別のバッチも1日目で記録される。
func seed_initial_inventory() -> void:
	if not GameState.inventory.is_empty():
		return
	var starting: Dictionary = Day1Events.initial_inventory()
	for id in starting:
		GameState.add_inventory(id, int(starting[id]))


## F7 同じ朝からの再挑戦（DESIGN.md 10.6・10.8.7）。戻れる最後の朝（GameState.latest_morning()）
## へ状態を戻し、WAKEからやり直す。戻した朝の客・需要（DayPlan）は保存したものと同じで、
## build()は呼ばない（抽選を引き直す手段にしない）。運営費が払えずゲームオーバーになった
## ときは、その朝は記録されていないので前日の朝へ戻る。戻る先が無い／封筒が壊れていれば
## 何もせず false を返す（呼び出し側が新規ゲーム等を決める）。
## 4-2（結果画面）の再挑戦も、この関数を呼ぶ。dayを指定すると、その日の朝へ戻る
## （「もう一度＝Day1の朝から」はday=1。戻した日より後の朝の記録は、from_dictが捨てる
## ＝戻した直後に詰んでも、再挑戦が後ろの日の朝へ飛ばない）。
func retry_from_morning(day: int = -1) -> bool:
	var morning := GameState.latest_morning() if day < 0 else GameState.morning_of(day)
	if morning.is_empty() or not MorningSave.is_valid(morning):
		return false
	restore_morning(morning)
	BalanceLog.note_retry()   # 同じ周の次の挑戦（日次ログの行を区別する）
	return true


## 封筒の朝へ戻す共通処理（再挑戦・セーブ読み込み）。GameState側はfrom_dict、画面側は
## 保存しない状態（接客の途中経過・一度きりの文）を捨て、前日成績の一言だけ戻す。
func restore_morning(morning: Dictionary) -> void:
	reset_transient_state()
	MorningSave.apply(morning)
	last_day_summary_text = str((morning["panel"] as Dictionary)["day_summary_text"])
	plan_restored = true
	flow.force_phase(GameState.Phase.WAKE)


## 画面側の保存しない状態を捨てる（再挑戦・セーブ読み込み・新しい周の共通処理）。
## 戻す／初期化する前に、途中の客・集計を捨てる（_set_runner_for_phase冒頭の
## flush_visit_tally()が古い接客を今の状態へ書き込まないようにするため）。
func reset_transient_state() -> void:
	visit_tally = {}
	reset_mob_group_state()
	pending_decline = false
	declined_now = false
	pending_close_lines = []
	played_events = []
	slot_event_ids = {}
	recipe_save_stage = ""
	fund_notice = ""
	fund_target = ""
	logged_positions = {}
	TalkLog.clear()
	mob_original_ordered = -1
	mob_recipe_number = 1
	bowl_discard_count = 0
	closed_early_reason = ""
	game_over_reason = ""
	game_over_detail = {}
	clear_reask()


func retry() -> void:
	retry_from_morning()


## 結果画面：もう一度（Day1の朝から）。Day1の朝の記録（morning_snapshots[1]）へ戻す。
## 累計（day_records）もDay1の朝の値（空）に戻る。Day1の客・需要は同じで、2日目以降は
## 評判次第で抽選が変わる。[続きから]で始めた周はDay1の記録が無いので、RESULTでは押せない。
## GAME_OVERでは押せて、Day1の記録が無いときは[新しい周]と同じ動作にする（出口を塞がない）。
func run_again() -> void:
	if GameState.phase == GameState.Phase.GAME_OVER and not GameState.morning_snapshots.has(1):
		new_run()
		return
	retry_from_morning(1)


## 結果画面：最後の朝（最終日の朝）からやり直す。累計は最終日の朝の値に戻る。
func last_morning() -> void:
	retry_from_morning()


## 結果画面：新しい周。reset_for_new_game()＋game_restartedの後、Day1のWAKEから始める
## （従来の最終日の翌朝の挙動と同じ状態。朝の記録・累計もクリアされ、保存も新しい周の
## Day1の朝で上書きされる）。
func new_run() -> void:
	reset_transient_state()
	GameState.reset_for_new_game()
	last_day_summary_text = ""
	plan_restored = false
	flow.game_restarted.emit()
	flow.force_phase(GameState.Phase.WAKE)


## 起動時に読めたセーブの朝へ戻る。いまの（起動直後の）ゲームの朝の記録は捨て、
## 読み込んだ朝をGameState.morning_snapshotsへ入れる（読み込んだ朝で詰んだときの
## 戻り先になる。retry_from_morning()がこの記録を使う）。
func continue_game() -> void:
	if pending_continue.is_empty():
		return
	var morning := pending_continue
	pending_continue = {}
	save_armed = true
	GameState.morning_snapshots.clear()
	GameState.record_morning(morning)
	restore_morning(morning)
	BalanceLog.begin_run()   # 続きから読み込んだ周は別の周（日次ログのrun_idを新しくする）

# --- 状態（UI準備A③e）---

# 既読スキップ（4-7③。ReadState）：直近に新しく見えた行が、それまで未読だったか（スキップの停止条件）。
# [既読スキップ]の仮ボタンは _ready でコードから足す（.tscn は変えない）。
var last_shown_unread := false

var recipe_save_slot := -1


# --- スマホ・レシピ・会話ログ・既読スキップ（UI準備A⑥） ---

## いま見えているイベントを、まだ記録していなければ会話ログへ1行足す。_refresh の末尾から呼ぶ＝
## どの操作（ハンドラ直呼びを含む）でも、新しく current になった行（index 0 を含む）が漏れない。
## 同じ位置・同じ本文は1回だけ（logged_positions）。REACT は判定後に決まる反応文が空でなくなってから、
## current_reaction_text() が読む（reaction_variant は判定時に固定済みの値で、ここでは抽選しない）。
func record_visible_event() -> void:
	if flow.runner == null:
		return
	var ev = flow.runner.current()
	if not (ev is Dictionary):
		return
	var kind := "narration"
	var speaker := ""
	var text := str(ev.get("text", ""))
	match str(ev.get("type", "")):
		"GREET":
			kind = "talk"
			speaker = log_speaker(str(ev.get("customer", "")))
		"SERVE":
			kind = "serve"
		"REACT":
			kind = "reaction"
			speaker = log_speaker(str(ev.get("customer", "")))
			text = current_reaction_text()
		"TEXT":
			if str(ev.get("part", "")) == "news":
				kind = "news"
	# 朝の会話枠にはニュースとスマホの入力待ちを出さない（ニュースはスマホで読む）ので、会話ログにも載せない
	if kind == "news" or str(ev.get("type", "")) == EventRunner.TYPE_WAIT_INPUT:
		text = ""
	if text == "":
		last_shown_unread = false   # 本文の無いイベント（効果のみ・入力待ち・反応なしのREACT）は未読の行ではない
		return
	var slot_index := -1
	var customer_index := -1
	if open != null:
		slot_index = open.slot_index
		customer_index = open.index
	var key := "%d|%d|%d|%d|%d|%s" % [GameState.day_count, GameState.phase, slot_index, customer_index,
		flow.runner.index, text]
	if logged_positions.has(key):
		return
	logged_positions[key] = true
	TalkLog.add(GameState.day_count, kind, speaker, text)
	# 既読（ReadState）：見えた行を既読にする。それまで未読だったかをスキップの停止条件として覚える。
	var read_key := ReadState.line_key(kind, speaker, str(ev.get("part", "")), text)
	last_shown_unread = not ReadState.is_read(read_key)
	ReadState.mark(read_key)


## スキップの1歩を進められるか：[次のEvent]が押せて、再生中（入力待ちでない）で、その客・そのフェーズの
## 最後のイベントではない（客やフェーズの切り替わりをまたぐ前で止まる）。
func can_skip_step() -> bool:
	if flow.runner == null or not can_next_event() or flow.runner.status != EventRunner.Status.PLAYING:
		return false
	if GameState.phase == GameState.Phase.GAME_OVER or GameState.phase == GameState.Phase.RESULT:
		return false
	return flow.runner.index < flow.runner.events.size() - 1


## [既読スキップ]：[次のEvent]を、止まる条件に達するまで繰り返す。**効果の適用は [次のEvent] と同一の
## 経路**（next_event）を1イベントにつき1回だけ通す＝会計・来店記録・事実・評判は1回だけ
## 適用される（別の経路は作らない）。止まる条件：入力待ち（ADJUST・CHOICE・MARKET・PREP_TIER・WAIT_INPUT
## など。選択は決して飛ばさない）／直前に見えた行が未読（その行で止まる）／客・フェーズの切り替わり／
## 鍋不足の保留など[次のEvent]が押せない状態／SKIP_READ_LIMIT 回。進めたイベント数を返す。
func skip_read() -> int:
	var steps := 0
	var start_runner = flow.runner
	var start_phase: int = GameState.phase
	while steps < SKIP_READ_LIMIT and can_skip_step():
		next_event()
		record_visible_event()   # 見えた行の記録（画面の描き直しに頼らない。同じ行は1回だけ）
		steps += 1
		if last_shown_unread or flow.runner != start_runner or GameState.phase != start_phase:
			break
	return steps


## ログの話し手（表示名。モブは種類の名前）。
func log_speaker(customer_id: String) -> String:
	if customer_id == "":
		return ""
	if Day1Events.is_mob_customer(customer_id):
		var inst: Dictionary = GameState.today_plan.get("mob_instances", {}).get(customer_id, {})
		return Day1Events.mob_display_name(str(inst.get("type", "")))
	return ScheduleData.customer_display_name(customer_id)


## ADJUST 中の名前あり客（モブの団体注文は対象外）の客id。それ以外は空文字。
func recipe_adjust_customer() -> String:
	if open == null or flow.runner == null or GameState.phase != GameState.Phase.OPEN \
			or flow.runner.status != EventRunner.Status.WAITING_INPUT or pot_open \
			or pending_group_choice or pending_shortage_ev != null:
		return ""
	var cur = flow.runner.current()
	if not (cur is Dictionary) or str(cur.get("type", "")) != "ADJUST":
		return ""
	var customer_id := str(cur.get("customer", ""))
	if not CustomerMemory.is_recordable(customer_id) or is_current_mob_order():
		return ""
	return customer_id


## レシピ／「いつもの」のボタン。**具材ボタンを順に押したのと同じ処理**（select_ingredient）で
## 1つずつ椀に足す＝在庫・鮮度の確認と消費は省略しない。全部出せると確かめてから適用する
## （途中で止まって一部だけ入る状態を作らない）。傷んだ側は自動では使わない。椀が空のときだけ。
func apply_recipe(ingredients: Array) -> void:
	var customer_id := recipe_adjust_customer()
	if customer_id == "" or not (open.current_bowl.get("additions", []) as Array).is_empty():
		return
	if not RecipeBook.can_apply(ingredients, current_servings()):
		return
	for id in ingredients:
		select_ingredient(str(id), false)


## 今、今作った椀をレシピに保存できるか：OPEN で、名前あり客の判定済みの椀（提供後。複数杯の各杯を含む）
## が残っていて、追加が1つ以上ある間。**その客の最後の行まで**押せる（次の杯の椀・次の客で消える）。
func can_save_recipe() -> bool:
	if open == null or flow.runner == null or GameState.phase != GameState.Phase.OPEN:
		return false
	var customer = open.current_customer()
	if customer == null or not CustomerMemory.is_recordable(str(customer)):
		return false
	var bowl: Dictionary = open.current_bowl
	return str(bowl.get("result", "")) != "" and not (bowl.get("additions", []) as Array).is_empty()


func start_recipe_save() -> void:
	if can_save_recipe():
		recipe_save_stage = "slot"
	changed.emit()


func select_recipe_slot(slot: int) -> void:
	if can_save_recipe() and slot >= 0 and slot < RecipeBook.slot_count() and slot <= GameState.saved_recipes.size():
		recipe_save_slot = slot
		recipe_save_stage = "name"
	changed.emit()


func select_recipe_name(recipe_name: String) -> void:
	if can_save_recipe() and recipe_save_stage == "name":
		RecipeBook.save(recipe_save_slot, recipe_name, open.current_bowl["additions"])
	recipe_save_stage = ""
	changed.emit()


func cancel_recipe_save() -> void:
	recipe_save_stage = ""
	changed.emit()


# --- スマホ・レシピ・会話ログの問い（UI準備A⑥。R3：スマホ／開店のレシピ） ---

## ADJUST 中の「いつもの」（その客の直近の料理）と保存レシピのボタンの中身（椀が空のときだけ。前回の評価は持たない）。
## [{ kind:"usual"|"saved", name, ingredients（品目id）, missing（足りない品目id＝新鮮な在庫のみ）, can_apply }]
## ボタンを押すときは apply_recipe(ingredients)。名前の付け方（「いつもの（…）」）はUI側で決める。
func recipe_adjust_buttons() -> Array:
	var out: Array = []
	var customer_id := recipe_adjust_customer()
	if customer_id == "" or not (open.current_bowl.get("additions", []) as Array).is_empty():
		return out
	var servings := current_servings()
	var usual := RecipeBook.usual_for(customer_id)
	if not usual.is_empty():
		out.append({ "kind": "usual", "name": "いつもの", "ingredients": usual.duplicate(),
			"missing": RecipeBook.shortage(usual, servings), "can_apply": RecipeBook.can_apply(usual, servings) })
	for recipe in GameState.saved_recipes:
		out.append({ "kind": "saved", "name": str(recipe["name"]), "ingredients": (recipe["ingredients"] as Array).duplicate(),
			"missing": RecipeBook.shortage(recipe["ingredients"], servings),
			"can_apply": RecipeBook.can_apply(recipe["ingredients"], servings) })
	return out


## 提供後の「レシピを保存」の中身。{ can_save, stage（""＝ボタン待ち／"slot"＝枠を選ぶ／"name"＝名前を選ぶ）,
##   ingredients（保存する椀の具材）, slots[{index, name（空きなら ""）, selectable}], names[名前の候補] }
## can_save が false のときは can_save だけ。段階は start_recipe_save → select_recipe_slot → select_recipe_name
## （やめるは cancel_recipe_save）。
func recipe_save_view() -> Dictionary:
	if not can_save_recipe():
		return { "can_save": false }
	var slots: Array = []
	for i in range(RecipeBook.slot_count()):
		slots.append({ "index": i, "name": (str(GameState.saved_recipes[i]["name"]) if i < GameState.saved_recipes.size() else ""),
			"selectable": i <= GameState.saved_recipes.size() })
	var names: Array = []
	for item in RecipeBook.names_ordered(open.bowl_addition_tags()):
		names.append(str(item["name"]))
	return { "can_save": true, "stage": recipe_save_stage, "ingredients": (open.current_bowl["additions"] as Array).duplicate(),
		"slots": slots, "names": names }


## スマホのレシピタブ：保存レシピ（枠ごと）と、客ごとの「いつもの」。
## { slots[{index, name, tags, ingredients}（空き枠は name が ""・tags と ingredients は空）], usual[{customer, ingredients}] }
func phone_recipes() -> Dictionary:
	var slots: Array = []
	for i in range(RecipeBook.slot_count()):
		if i < GameState.saved_recipes.size():
			var recipe: Dictionary = GameState.saved_recipes[i]
			slots.append({ "index": i, "name": str(recipe["name"]), "tags": RecipeBook.tags_of(recipe["ingredients"]),
				"ingredients": (recipe["ingredients"] as Array).duplicate() })
		else:
			slots.append({ "index": i, "name": "", "tags": [], "ingredients": [] })
	var usual: Array = []
	for customer_id in GameState.customer_memory:
		var ingredients := RecipeBook.usual_for(str(customer_id))
		if not ingredients.is_empty():
			usual.append({ "customer": str(customer_id), "ingredients": ingredients.duplicate() })
	return { "slots": slots, "usual": usual }


## スマホのニュースタブ：今日と、その周で既に過ぎた日の分だけ（未来の日は見せない）。新しい日が上。
## [{ day, is_today, news[{id, headline, body[], must_info[], provisional, unread}], events[{lines[], provisional}] }]（DMは phone_dm()）。
## unread は ReadState（保存とは別のファイル。idで持つ）。
## 過ぎた日の共通イベントは出来事として載せ、今日の分は再生済み（played_events）のものだけ。中身が空の日は出さない。
func phone_news() -> Array:
	var out: Array = []
	var today := GameState.day_count
	for day in range(today, 0, -1):
		var entry := News.day_entry(day)
		var section := { "day": day, "is_today": day == today, "news": [], "events": [] }
		for item in entry["news"]:
			section["news"].append({ "id": str(item.get("id", "")), "headline": str(item.get("headline", "")),
				"body": (item.get("body", []) as Array).duplicate() if item.get("body") is Array else [],
				"must_info": (item.get("must_info", []) as Array).duplicate() if item.get("must_info") is Array else [],
				"provisional": bool(item.get("provisional", false)),
				"unread": not ReadState.is_read(_news_read_key(str(item.get("id", "")))) })
		for item in entry["events"]:
			if day < today or played_events.has(str(item.get("id", ""))):
				if item.get("lines") is Array:
					section["events"].append({ "lines": (item["lines"] as Array).duplicate(),
						"provisional": bool(item.get("provisional", false)) })
		if not (section["news"].is_empty() and section["events"].is_empty()):
			out.append(section)
	return out


## スマホのSNSタブ：今日までに届いたDM（新しい順）。[{ id, day, from, from_kind, time, text, hint, provisional, unread }]
## 届く条件は Dm（名前あり客に初めて提供した翌日から／同じ種類のモブに2夜提供した翌日から／客でない差出人は条件なし。
## 匂わせの向きは需要の中心と矛盾しない日だけ）。未読は ReadState（保存とは別のファイル）で持つ。
func phone_dm() -> Array:
	var out := Dm.inbox(GameState.day_count)
	for item in out:
		item["unread"] = not ReadState.is_read(_dm_read_key(item))
	return out


## 未読のDMの数（スマホのSNSタブに出す）。
func dm_unread_count() -> int:
	var n := 0
	for item in Dm.inbox(GameState.day_count):
		if not ReadState.is_read(_dm_read_key(item)):
			n += 1
	return n


## いま届いているDMを、読んだ扱いにする（SNSタブを開いて表示した時点で呼ぶ）。
func mark_dms_read() -> void:
	for item in Dm.inbox(GameState.day_count):
		ReadState.mark(_dm_read_key(item))


## 未読のニュースの数（スマホのニュースタブに出す）。今日と過ぎた日のニュースで、まだ表示していないもの。
func news_unread_count() -> int:
	var n := 0
	for section in phone_news():
		for item in section["news"]:
			if bool(item["unread"]):
				n += 1
	return n


## 未読のニュースのうち、必須情報（must_info）を持つものの id。朝の会話枠にはニュースを出さないので、
## 「市場へ」の時点で必須情報のニュースが未読のまま進めることがある（ゲートは付けない）。
func unread_must_info_news() -> Array:
	var ids: Array = []
	for section in phone_news():
		for item in section["news"]:
			if bool(item["unread"]) and not (item["must_info"] as Array).is_empty():
				ids.append(str(item["id"]))
	return ids


## いま届いているニュースを、読んだ扱いにする（ニュースタブを開いて表示した時点で呼ぶ）。
func mark_news_read() -> void:
	for section in phone_news():
		for item in section["news"]:
			ReadState.mark(_news_read_key(str(item["id"])))


## スマホのボタンの未読の数：DMとニュースの合計。
func phone_unread_count() -> int:
	return dm_unread_count() + news_unread_count()


func _news_read_key(id: String) -> String:
	return ReadState.line_key("news", "", id, id)   # 文が差し替わっても既読は変えない（idで持つ）


func _dm_read_key(item: Dictionary) -> String:
	return ReadState.line_key("dm", "", str(item["id"]), str(item["id"]))   # 文が差し替わっても既読は変えない（idで持つ）


## スマホのログタブ：今日の会話ログ（上から古い順）。[{ day, kind, speaker, text }]。実行時の記録のみ（保存しない）。
func talk_log_entries() -> Array:
	return TalkLog.entries.duplicate(true)



# --- 画面の共通・開店の鍋とトッピング・朝の問い（UI準備A⑥。R3の残り。読むだけ） ---

## 画面の上部・共通：{ day, phase（GameState.Phase の値）, phase_name, slot_name（時間帯の名前。開店中のみ）,
##   slot_index／customer_index（開店中のみ。それ以外は -1）, money, reputation }
func day_info() -> Dictionary:
	var slot_name := ""
	var slot_index := -1
	var customer_index := -1
	if open != null:
		slot_index = open.slot_index
		customer_index = open.index
		slot_name = open.current_slot_name()
	return { "day": GameState.day_count, "phase": GameState.phase, "phase_name": str(GameState.Phase.keys()[GameState.phase]),
		"slot_name": slot_name, "slot_index": slot_index, "customer_index": customer_index,
		"money": GameState.money, "reputation": GameState.reputation }


## いま表示すべき文：{ type（Event の種類）, speaker（話し手の客id。地の文・店主は ""）, text, part（"news" など） }。
## REACT は判定後に決まる反応文（判定前は空）。runner が無い・Event が無いときは空。
func current_line() -> Dictionary:
	var ev = _current_event()
	if not (ev is Dictionary):
		return {}
	var type := str(ev.get("type", ""))
	var speaker := ""
	var text := str(ev.get("text", ""))
	if type == "GREET" or type == "REACT":
		speaker = str(ev.get("customer", ""))
	if type == "REACT":
		text = current_reaction_text()
	return { "type": type, "speaker": speaker, "text": text, "part": str(ev.get("part", "")) }


## 入力待ち（WAITING_INPUT）か。
func is_waiting_input() -> bool:
	return flow.runner != null and flow.runner.status == EventRunner.Status.WAITING_INPUT


## 店主の距離感の選択（CHOICE）の選択肢：{ choice_id, options[{id, label}] }。選択中でなければ空。
## 選ぶときは choose_story_option(choice_id, option_id)。
func current_choices() -> Dictionary:
	var cur = _current_event()
	if not (cur is Dictionary) or str(cur.get("type", "")) != "CHOICE":
		return {}
	var options: Array = []
	for option in cur.get("options", []):
		options.append({ "id": str(option.get("id", "")), "label": str(option.get("label", "")) })
	return { "choice_id": str(cur.get("choice_id", "")), "options": options }


## 開店の鍋：{ exists, remaining（残り杯数）, capacity（鍋の上限）, strength（濃さ）, strength_min, strength_max,
##   can_add_water, water_doses_left（今夜あと何回水を足せるか）, can_add_dashi, dashi_units（だしの残り数）,
##   can_touch（鍋を触れるか）, pot_open, shortage_pending, locked_until_water, locked_until_dashi }
## 鍋がまだ無い（仕込み前）ときは exists だけ false。
func pot_view() -> Dictionary:
	if GameState.soup == null:
		return { "exists": false }
	return { "exists": true, "remaining": int(GameState.soup.get("remaining_servings", 0)), "capacity": Rules.pot_capacity(),
		"strength": int(GameState.soup.get("strength", 3)), "strength_min": GameState.STRENGTH_MIN, "strength_max": GameState.STRENGTH_MAX,
		"can_add_water": GameState.can_add_water(), "water_doses_left": int(GameState.soup.get("water_doses", 0)),
		"can_add_dashi": GameState.can_add_dashi(), "dashi_units": GameState.dashi_units,
		"can_touch": can_touch_pot(), "pot_open": pot_open, "shortage_pending": is_shortage_pending(),
		"locked_until_water": pot_locked_until_water(), "locked_until_dashi": pot_locked_until_dashi() }


## 注文カード（その客の『いつもの』と『今日の頼み』）。開店中は常に出す（客がいなければ空）。表示だけで、判定・乱数・保存には触れない。
## { customer, base[タグ]（いつもの）, today[タグ]（今日の頼み。無い＝いつもどおりは空）, label,
##   usual_known（「いつもの」が分かっているか）, today_known（今日の頼みが分かっているか）, can_reask }
## 分かる時点（UI準備D・D-5）：客が注文を言う会話の最後の行（その杯の ADJUST の直前の GREET。無ければ ADJUST）を表示した時点。
##   ・「今日」：その行を出した時点で、頼み（無ければ「いつもどおり」）が分かる。提供のあとではない。
##   ・「いつもの」：同じ時点で分かる。名前あり客は、前の日に来たことがあれば（今日より前の来店記録がある）最初から分かっている
##     ＝次に同じ客が来たときは埋まった状態で出る。保存する状態は増やさない（来店記録から読む）。好物を知った状態（favorite_known）は使わない。
##   ・それより前（前回への一言など）と、客がいないあいだは、分かっていない（画面は「？」）。
## 複数杯の場面（配達員の3杯）は杯ごと（持ち帰りの頼みは、2杯目のあとの会話の最後の行で分かる）。モブの団体も同じ形（いつもの＝モブの注文のタグ。今日はいつもどおり）。
func order_card_view() -> Dictionary:
	if open == null or flow.runner == null or GameState.phase != GameState.Phase.OPEN or not open.has_more():
		return {}
	var current_customer = open.current_customer()
	if current_customer == null or str(current_customer) == "":
		return {}
	var customer_id := str(current_customer)
	var events: Array = flow.runner.events
	var index: int = flow.runner.index
	var current = flow.runner.current()
	var current_type := str(current.get("type", "")) if current is Dictionary else ""
	# いま見ている杯の ADJUST：注文を言う行・ADJUST・提供・反応のあいだは、直前の（今の杯の）ADJUST。それ以外（会話の行）は次の ADJUST。
	var adjust_index := -1
	if current_type == "ADJUST" or current_type == "SERVE" or current_type == "REACT":
		for i in range(mini(index, events.size() - 1), -1, -1):
			if events[i] is Dictionary and str(events[i].get("type", "")) == "ADJUST":
				adjust_index = i
				break
	else:
		for i in range(index, events.size()):
			if events[i] is Dictionary and str(events[i].get("type", "")) == "ADJUST":
				adjust_index = i
				break
	var card := { "customer": customer_id, "base": [], "today": [], "label": "", "usual_known": false, "today_known": false,
		"can_reask": can_reask() }
	if adjust_index < 0:
		return card
	var effective: Array = []
	for i in range(adjust_index + 1, events.size()):
		if events[i] is Dictionary and str(events[i].get("type", "")) == "REACT":
			effective = (events[i].get("wanted_tags", []) as Array).duplicate()
			break
	var is_mob := Day1Events.is_mob_customer(customer_id)
	var profile := {} if is_mob else ScheduleData.customer_profile(customer_id)   # モブのインスタンスidにはプロフィールが無い
	var named := not profile.is_empty() and not bool(profile.get("is_mob", false))
	var base: Array = (profile.get("wanted_tags", []) as Array).duplicate() if named else effective.duplicate()
	card["base"] = base
	card["today"] = effective.duplicate() if named and effective != base else []
	if named and not Day1Events.is_multi_cup_scene(customer_id, Day1Events.episode_id_of(customer_id)):
		card["label"] = str(Day1Events.order_card(customer_id).get("label", ""))
	var order_line := adjust_index
	if adjust_index > 0 and events[adjust_index - 1] is Dictionary and str(events[adjust_index - 1].get("type", "")) == "GREET":
		order_line = adjust_index - 1
	card["today_known"] = index >= order_line
	card["usual_known"] = bool(card["today_known"]) or (named and not CustomerMemory.previous_visit(customer_id).is_empty())
	return card


## 椀の中身：{ customer, additions[品目id], additions_damaged[additions と同じ並びで、傷んだ側から入れたか],
##   max_additions, used_spoiled（傷んだ具材を使ったか）, result（判定。判定前は ""）, discard_count（この客での廃棄回数）,
##   tags（最終タグ）, addition_tags }
## 接客中でなければ空。
func bowl_view() -> Dictionary:
	if open == null or not open.current_bowl.has("customer_id"):
		return {}
	var bowl: Dictionary = open.current_bowl
	return { "customer": str(bowl["customer_id"]), "additions": (bowl.get("additions", []) as Array).duplicate(),
		"additions_damaged": (bowl.get("additions_damaged", []) as Array).duplicate(),
		"max_additions": OpenController.MAX_ADDITIONS, "used_spoiled": bool(bowl.get("used_spoiled", false)),
		"result": str(bowl.get("result", "")), "discard_count": bowl_discard_count,
		"tags": open.bowl_final_tags(), "addition_tags": open.bowl_addition_tags() }


## 選べる品目の一覧（ADJUST 中）：[{ id, label, damaged（この選択肢は傷んだ側か）, kind（"seasoning"／"topping"）,
##   tags, fresh（新鮮の在庫）, damaged_stock（傷んだ在庫）, count（この選択肢の側の在庫）, can_pick }]
## can_pick は在庫があり、椀が上限（3つ）に達しておらず、まだ椀に入っていないとき。in_bowl は椀に入っている（もう一度押すと取り消せる）。
## 押すときは toggle_ingredient(id, damaged)（椀に無ければ入れ、あれば取り消す。select_ingredient は入れるだけ）。
## ADJUST で入力待ちでなければ空。
func ingredient_options() -> Array:
	var out: Array = []
	var cur = _current_event()
	if not (cur is Dictionary) or str(cur.get("type", "")) != "ADJUST" or not is_waiting_input() or not cur.has("options"):
		return out
	var at_cap := false
	if open != null:
		at_cap = (open.current_bowl.get("additions", []) as Array).size() >= OpenController.MAX_ADDITIONS
	for option in cur["options"]:
		var id := str(option.get("id", ""))
		var damaged := bool(option.get("damaged", false))
		var own: int = GameState.damaged_count(id) if damaged else GameState.fresh_count(id)
		var in_bowl := open != null and (open.current_bowl.get("additions", []) as Array).has(id)
		out.append({ "id": id, "label": str(option.get("label", id)), "damaged": damaged,
			"kind": "topping" if Ingredients.is_topping(id) else "seasoning", "tags": Ingredients.tags_for(id),
			"fresh": GameState.fresh_count(id), "damaged_stock": GameState.damaged_count(id), "count": own,
			"can_pick": not at_cap and own >= 1 and not in_bowl, "in_bowl": in_bowl })
	return out


## 今日もう払った運営費（帳簿の "daily_cost" の今日の合計。市場を出るとき以降に出る。朝はまだ0＝払う予定は operating_cost_pending）。
func morning_cost() -> int:
	return int(Ledger.spend_by_category_today().get("daily_cost", 0))


## ゲームオーバーの中身（UI準備B④。表示だけ）：{ available（GAME_OVER で、詰んだ支払いの記録があるか）, kind, amount, money, day, phase }。
## kind は帳簿のカテゴリ（"daily_cost"＝運営費／"water"＝水道代／"rent"＝場所代／"kit"＝初日セット／""＝その他）。文面はUI側で決める。
func game_over_info() -> Dictionary:
	if GameState.phase != GameState.Phase.GAME_OVER or game_over_detail.is_empty():
		return { "available": false }
	var out := game_over_detail.duplicate()
	out["available"] = true
	return out


## 結果画面・ゲームオーバーの出口：{ available（RESULT か GAME_OVER か）, can_retry（同じ朝から＝直近の朝。GAME_OVER で記録があるとき）,
##   can_last_morning（直近の朝からやり直せる＝記録がある）, can_run_again（Day1の朝から。RESULT は Day1 の記録があるとき、
##   GAME_OVER は常に）, run_again_is_new_run（GAME_OVER で Day1 の記録が無い＝押すと新しい周と同じ動作）, can_new_run, can_continue（起動時に
##   読めたセーブがある＝[続きから]）}。押すときは retry／last_morning／run_again／new_run／continue_game。
## スマホを開いている間の無効化など、表示だけの状態は含めない。
func exits() -> Dictionary:
	var in_result := GameState.phase == GameState.Phase.RESULT
	var in_over := GameState.phase == GameState.Phase.GAME_OVER
	var has_day1 := GameState.morning_snapshots.has(1)
	var has_any := not GameState.morning_snapshots.is_empty()
	return { "available": in_result or in_over, "can_retry": in_over and has_any,
		"can_last_morning": (in_result or in_over) and has_any, "can_run_again": in_over or (in_result and has_day1),
		"run_again_is_new_run": in_over and not has_day1, "can_new_run": in_result or in_over,
		"can_continue": not pending_continue.is_empty() }


## 結果画面の中身：{ summary（Result.summarize＝成績の集計）, goals（Result.judge_goals＝目標の判定。完走・標準・挑戦・料理・常連の順）}。
## 文面（Result.format_*）はUI側で決める。周回の累計（day_records）と帳簿から導く。
func result_view() -> Dictionary:
	var summary := Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
	return { "summary": summary, "goals": Result.judge_goals(summary, Rules.goals(), Rules.final_day()) }
