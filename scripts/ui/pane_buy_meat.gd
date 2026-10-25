extends Panel
class_name UiPaneBuyMeat
## 右の枠：購入（食肉仲卸＝張記）。寸法表 SCREENS_UI_LAYOUT §5。市場に入って最初に開く。
## 鍋の素の3段階は、段階の選択（PREP_TIER）にいるときだけ選べる。カードを押すと「選択中」になる（選び直しできる。まだ買わない）。
## 「購入確定」で choose_prep_tier(id) を1回呼んで買う。追加購入の商品の行はDay2から（市場の開く日から）、鍋の素を買ったあとから
## 「かごに入れる」ができ、「購入確定」で入れた順に buy_item する（UIの集計を通す）。「使える」（残金−支払い予定）は、選んだ鍋の素とかごの
## 分を引いた額で見せ、それを超えるものは選べない・かごに入れられない（理由を出す）。
## 「購入して店を出る」＝買ってから出る。「店を出る」（旧「店選びへ」。plan Q9）：市場（MARKET）の前は、会話を進めるのと同じ
## （鍋の素を買うまで押せない）。かごや選択中の鍋の素があるときは「買わずに店を出る」。市場の中で張記に入っているときは leave_shop()。

signal advance_requested()

const SHOP := "meat_wholesale"

var session: PlaySession = null
var tally: UiShopTally = null
var cart: UiShopCart = null

@onready var _header: Control = %Header
@onready var _budget: Control = %Budget
@onready var _tiers: Control = %Tiers
@onready var _goods_scroll: Control = %GoodsScroll
@onready var _goods: UiGoodsList = %Goods
@onready var _warn: Label = %WarnNote
@onready var _back: Button = %BackButton
@onready var _cart_box: UiCartBox = %CartBox
@onready var _reason: Label = %ReasonLabel
@onready var _confirm: Button = %ConfirmButton
@onready var _exit_buy: Button = %ExitBuyButton


func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	_goods.buy.connect(_on_buy)
	_confirm.pressed.connect(_on_confirm.bind(false))
	_exit_buy.pressed.connect(_on_confirm.bind(true))
	_cart_box.undo_pressed.connect(_on_undo)
	_cart_box.clear_pressed.connect(_on_clear)
	for i in range(_tiers.get_child_count()):
		(_tiers.get_child(i) as Button).pressed.connect(_on_tier_pressed.bind(i))


func bind_session(s: PlaySession) -> void:
	session = s


## 選んでいる鍋の素（まだ買っていない）の価格。段階を選ぶ場面でなければ 0。
func _tier_pending() -> int:
	return cart.selected_tier_price if cart != null and session.is_in_prep_tier() and cart.selected_tier != "" else 0


func _pending() -> int:
	return (cart.total(SHOP) if cart != null else 0) + _tier_pending()


func refresh() -> void:
	if session == null:
		return
	var choosing := session.is_in_prep_tier()
	if not choosing and cart != null:
		cart.clear_tier()   # 買った（または段階を選ぶ場面ではない）なら、選択は持たない
	UiParts.set_header(_header, UiLabels.shop_name(SHOP, "食肉仲卸"), "食肉仲卸")
	var pending := _pending()
	UiParts.set_budget(_budget, session.budget(), pending)
	var tiers := session.prep_tiers()
	var base := session.today_base()
	var limit := session.purchase_limit()
	for i in range(_tiers.get_child_count()):
		var card: UiTierCard = _tiers.get_child(i)
		card.visible = i < tiers.size()
		if i < tiers.size():
			var tier: Dictionary = tiers[i]
			var picked := choosing and cart != null and cart.selected_tier == str(tier["id"])
			card.show_tier(tier, bool(base["paid"]) and str(base["tier_id"]) == str(tier["id"]),
				choosing and int(tier["price"]) <= limit, picked)
	var paid := session.prep_tier_paid()
	var goods_open := GameState.day_count >= Rules.market_open_from_day()
	_goods_scroll.visible = goods_open
	var goods := session.shop_view(SHOP)
	var remaining := limit - pending
	for good in goods:
		good["affordable"] = int(good["price"]) <= remaining
	if goods_open:
		_goods.show_goods(goods, paid)
	_warn.visible = not paid and not (choosing and cart != null and cart.selected_tier != "")
	_cart_box.visible = goods_open or choosing
	var count := cart.count(SHOP) if cart != null else 0
	var extra := ""
	if _tier_pending() > 0:
		extra = "鍋の素 %s ¥%d" % [_selected_tier_label(tiers), _tier_pending()]
	_cart_box.show_cart(cart.grouped(SHOP) if cart != null else [], pending, extra)
	var can_confirm := pending > 0 and pending <= limit
	_confirm.text = "購入確定（¥%d）" % pending if pending > 0 else "購入確定"
	_confirm.disabled = not can_confirm
	_exit_buy.disabled = not can_confirm
	_back.text = "買わずに店を出る" if pending > 0 else "店を出る"
	if session.is_in_market():
		_back.disabled = false
	else:
		_back.disabled = not (paid and session.can_next_event())
	var reason := UiParts.limit_reason(goods if goods_open else [], remaining, int(session.budget()["reserved"]))
	if reason == "" and choosing:
		var too_expensive := false
		for tier in tiers:
			too_expensive = too_expensive or int(tier["price"]) > remaining
		if too_expensive:
			reason = "使える現金は残り ¥%d。これを超える鍋の素は選べません" % maxi(remaining, 0)
	_reason.text = reason


func _selected_tier_label(tiers: Array) -> String:
	for tier in tiers:
		if cart != null and str(tier["id"]) == cart.selected_tier:
			return str(tier["label"]).replace("仕込み", "")
	return ""


func _on_tier_pressed(index: int) -> void:
	var tiers := session.prep_tiers()
	if index < tiers.size() and session.is_in_prep_tier() and cart != null \
			and int(tiers[index]["price"]) <= session.purchase_limit():
		cart.select_tier(str(tiers[index]["id"]), int(tiers[index]["price"]))
		session.notify_changed()


func _on_buy(good: Dictionary) -> void:
	if session.prep_tier_paid() and cart != null and int(good["price"]) <= session.purchase_limit() - _pending():
		cart.add(SHOP, good)
		session.notify_changed()


func _on_undo() -> void:
	cart.remove_last(SHOP)
	session.notify_changed()


func _on_clear() -> void:
	cart.clear(SHOP)
	cart.clear_tier()
	session.notify_changed()


## 購入確定：選んだ鍋の素を買い（choose_prep_tier）、かごの商品を入れた順に買う。leave なら続けて店を出る。
func _on_confirm(leave: bool) -> void:
	var pending := _pending()
	if pending <= 0 or pending > session.purchase_limit():
		return
	var tier_id := cart.selected_tier if session.is_in_prep_tier() else ""
	cart.clear_tier()
	if tier_id != "":
		session.choose_prep_tier(tier_id)
	if session.prep_tier_paid():
		for line in cart.take(SHOP):
			tally.buy(session, SHOP, line)
	if leave:
		_leave()
	else:
		session.notify_changed()


func _leave() -> void:
	if session.is_in_market():
		session.leave_shop()
	elif session.can_next_event():
		advance_requested.emit()


func _on_back_pressed() -> void:
	if cart != null:
		cart.clear(SHOP)
		cart.clear_tier()
	if session.is_in_market():
		session.leave_shop()
	elif session.prep_tier_paid() and session.can_next_event():
		advance_requested.emit()
	else:
		session.notify_changed()
