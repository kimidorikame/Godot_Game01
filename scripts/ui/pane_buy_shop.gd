extends Panel
class_name UiPaneBuyShop
## 右の枠：購入（ほかの店）。寸法表 SCREENS_UI_LAYOUT §6。いま入っている店は session.market_shop。
## 商品の行の「かごに入れる」で、かご（UiShopCart）に1セット入る。何も買わない（所持金・在庫・帳簿は動かない）。
## 「購入確定」（店に残る）で、かごの商品を入れた順に buy_item する（UIの集計を通す）。下段は「購入確定」「店を出る」の2つ（UI準備F3）。
## 「店を出る」（旧「店選びへ戻る」。かごに何か入っていれば「買わずに店を出る」＝かごを空にして出る）→ leave_shop()。
## 「使える」（残金−支払い予定）は、かごの分を引いた額で見せる。それを超える商品はかごに入れられない（行のボタンが押せない・理由を出す）。
## 「この店で買った」はUIの集計（plan Q10）。

var session: PlaySession = null
var tally: UiShopTally = null
var cart: UiShopCart = null

@onready var _header: Control = %Header
@onready var _budget: Control = %Budget
@onready var _goods: UiGoodsList = %Goods
@onready var _bought_box: Control = %BoughtBox
@onready var _bought_list: Label = %BoughtList
@onready var _back: Button = %BackButton
@onready var _cart_box: UiCartBox = %CartBox
@onready var _reason: Label = %ReasonLabel
@onready var _final_note: Label = %FinalNote
@onready var _confirm: Button = %ConfirmButton


func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	_goods.buy.connect(_on_buy)
	_confirm.pressed.connect(_on_confirm.bind(false))
	_cart_box.undo_pressed.connect(_on_undo)
	_cart_box.fitted.connect(_on_cart_fitted)
	_cart_box.clear_pressed.connect(_on_clear)


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null or session.market_shop == "":
		return
	# 最終日の注意（UI準備I）。1行ぶん、商品の一覧の上端を下げる
	_final_note.visible = GameState.is_final_day()
	_final_note.text = UiParts.FINAL_DAY_NOTE
	(%Scroll as Control).offset_top = 142.0 if _final_note.visible else 127.0
	var shop := session.market_shop
	var label := ""
	for stall in session.market_stalls():
		if str(stall["id"]) == shop:
			label = str(stall["label"])
	UiParts.set_header(_header, UiLabels.shop_name(shop, label), label)
	var pending := cart.total(shop) if cart != null else 0
	UiParts.set_budget(_budget, session.budget(), pending)
	var goods := session.shop_view(shop)
	var remaining := session.purchase_limit() - pending
	for good in goods:
		good["affordable"] = int(good["price"]) <= remaining   # かごの分を引いた「使える」で決める
	_goods.show_goods(goods, true)
	var entries: Array = tally.entries(shop) if tally != null else []
	_bought_box.visible = not entries.is_empty()
	var parts: Array = []
	for entry in entries:
		parts.append("%s ¥%d" % [str(entry["label"]), int(entry["price"])])
	_bought_list.text = "・".join(parts)
	var count := cart.count(shop) if cart != null else 0
	_cart_box.show_cart(cart.grouped(shop) if cart != null else [], pending)
	var can_confirm := count > 0 and pending <= session.purchase_limit()
	_confirm.text = "購入確定（¥%d）" % pending if count > 0 else "購入確定"
	_confirm.disabled = not can_confirm
	_back.text = "買わずに店を出る" if count > 0 else "店を出る"
	_reason.text = UiParts.limit_reason(goods, remaining, int(session.budget()["reserved"]))
	_relayout()


func _on_buy(good: Dictionary) -> void:
	var shop := session.market_shop
	if cart != null and int(good["price"]) <= session.purchase_limit() - cart.total(shop):
		cart.add(shop, good)
		session.notify_changed()


func _on_undo() -> void:
	cart.remove_last(session.market_shop)
	session.notify_changed()


func _on_clear() -> void:
	cart.clear(session.market_shop)
	session.notify_changed()


## 購入確定：かごの商品を入れた順に買う。leave なら続けて店を出る。かごは買う前に空にする（描き直しで二重に数えない）。
func _on_confirm(leave: bool) -> void:
	var shop := session.market_shop
	if cart.count(shop) == 0 or cart.total(shop) > session.purchase_limit():
		return
	for line in cart.take(shop):
		tally.buy(session, shop, line)
	if leave:
		session.leave_shop()
	else:
		session.notify_changed()


func _on_back_pressed() -> void:
	if cart != null:
		cart.clear(session.market_shop)
	session.leave_shop()


## かごの枠の高さが変わったら、上に並ぶ商品の一覧の下端を、かごの上に合わせる（あいた高さは商品の一覧に回る）。
func _on_cart_fitted() -> void:
	_relayout()


## かごの上に、買えない理由（あれば。2行）を置き、その上までを商品の一覧にする。
func _relayout() -> void:
	var top := _cart_box.offset_top
	if _reason.text != "":
		_reason.offset_bottom = top - 4.0
		_reason.offset_top = _reason.offset_bottom - 34.0
		top = _reason.offset_top
	(%Scroll as Control).offset_bottom = top - 6.0
