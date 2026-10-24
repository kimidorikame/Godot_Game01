extends Panel
class_name UiPaneBuyMeat
## 右の枠：購入（食肉仲卸＝張記）。寸法表 SCREENS_UI_LAYOUT §5。市場に入って最初に開く。
## 鍋の素の3段階は、段階の選択（PREP_TIER）にいるときだけ押せる → choose_prep_tier(id)。
## 追加購入の商品の行はDay2から（市場の開く日から）、鍋の素を買ったあとから押せる → buy_item（UIの集計を通す）。
## 「店選びへ」（plan Q9）：市場（MARKET）の前は、会話を進めるのと同じ（鍋の素を買うまで押せない）。
## 市場の中で張記に入っているときは leave_shop()。

signal advance_requested()

const SHOP := "meat_wholesale"

var session: PlaySession = null
var tally: UiShopTally = null

@onready var _header: Control = %Header
@onready var _budget: Control = %Budget
@onready var _tiers: Control = %Tiers
@onready var _goods_scroll: Control = %GoodsScroll
@onready var _goods: UiGoodsList = %Goods
@onready var _warn: Label = %WarnNote
@onready var _back: Button = %BackButton


func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	_goods.buy.connect(_on_buy)
	for i in range(_tiers.get_child_count()):
		(_tiers.get_child(i) as Button).pressed.connect(_on_tier_pressed.bind(i))


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	UiParts.set_header(_header, UiLabels.shop_name(SHOP, "食肉仲卸"), "食肉仲卸")
	UiParts.set_budget(_budget, session.budget())
	var tiers := session.prep_tiers()
	var base := session.today_base()
	var choosing := session.is_in_prep_tier()
	for i in range(_tiers.get_child_count()):
		var card: UiTierCard = _tiers.get_child(i)
		card.visible = i < tiers.size()
		if i < tiers.size():
			var tier: Dictionary = tiers[i]
			card.show_tier(tier, bool(base["paid"]) and str(base["tier_id"]) == str(tier["id"]),
				choosing and bool(tier["affordable"]))
	var paid := session.prep_tier_paid()
	_goods_scroll.visible = GameState.day_count >= Rules.market_open_from_day()
	if _goods_scroll.visible:
		_goods.show_goods(session.shop_view(SHOP), paid)
	_warn.visible = not paid
	if session.is_in_market():
		_back.disabled = false
	else:
		_back.disabled = not (paid and session.can_next_event())


func _on_tier_pressed(index: int) -> void:
	var tiers := session.prep_tiers()
	if index < tiers.size() and session.is_in_prep_tier():
		session.choose_prep_tier(str(tiers[index]["id"]))


func _on_buy(good: Dictionary) -> void:
	if session.prep_tier_paid():
		tally.buy(session, SHOP, good)


func _on_back_pressed() -> void:
	if session.is_in_market():
		session.leave_shop()
	elif session.prep_tier_paid() and session.can_next_event():
		advance_requested.emit()
