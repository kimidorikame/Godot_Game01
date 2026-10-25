extends Panel
class_name UiPaneBuyShop
## 右の枠：購入（ほかの店）。寸法表 SCREENS_UI_LAYOUT §6。いま入っている店は session.market_shop。
## 商品の行 → buy_item（UIの集計を通す）。「この店で買った」はUIの集計（plan Q10）。「店を出る」（旧「店選びへ戻る」）→ leave_shop()。

var session: PlaySession = null
var tally: UiShopTally = null

@onready var _header: Control = %Header
@onready var _budget: Control = %Budget
@onready var _goods: UiGoodsList = %Goods
@onready var _bought_box: Control = %BoughtBox
@onready var _bought_list: Label = %BoughtList
@onready var _back: Button = %BackButton


func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	_goods.buy.connect(_on_buy)


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null or session.market_shop == "":
		return
	var shop := session.market_shop
	var label := ""
	for stall in session.market_stalls():
		if str(stall["id"]) == shop:
			label = str(stall["label"])
	UiParts.set_header(_header, UiLabels.shop_name(shop, label), label)
	UiParts.set_budget(_budget, session.budget())
	_goods.show_goods(session.shop_view(shop), true)
	var entries: Array = tally.entries(shop) if tally != null else []
	_bought_box.visible = not entries.is_empty()
	var parts: Array = []
	for entry in entries:
		parts.append("%s ¥%d" % [str(entry["label"]), int(entry["price"])])
	_bought_list.text = "・".join(parts)


func _on_buy(good: Dictionary) -> void:
	tally.buy(session, session.market_shop, good)


func _on_back_pressed() -> void:
	session.leave_shop()
