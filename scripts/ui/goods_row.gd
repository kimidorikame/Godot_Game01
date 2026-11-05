extends Panel
class_name UiGoodsRow
## 購入画面の商品の行（388×61）。寸法表 SCREENS_UI_LAYOUT §6。
## 1行目：品名・タグの言葉の札（味と具で色が2系統）・「腐る」。2行目：手持ち（使える分＝新鮮＋傷）と、傷んだ分があれば続けて「（傷N）」（注意色。UI準備P2）、
## かごに入れた分があれば「→ 購入後」（強調色。購入後＝手持ち＋かごに入れた分。同じ品目の別の商品〔モツの小口など〕の分も合わせる。UI準備P）。
## 例：「手持ち3 → 9」「手持ち3（傷1）→ 9」。2行目は間隔0の横並びで、区切りの空白は文字に持たせる。
## 右の列：価格と、その下に「3個 / 単価8」。右端に「かごに入れる」。
## UI準備P：札・「腐る」・手持ちの文字を大きくした。1行目に入りきらない行は、まず「腐る」を2行目の後ろへ回し、
## それでも入らなければ札を同じ色・形の小さい版にする（文字は小さくしない＝並びで直す）。
## 中身は shop_view() の1件。押せるかは呼び出し側が決める（買えない＝所持金不足は品名と価格を薄くする）。

signal buy_pressed()   # 「かごに入れる」が押された

@onready var _name: Label = $Tags/Name
@onready var _tags: HBoxContainer = $Tags
@onready var _rot: Label = $Tags/Rot
@onready var _stock: HBoxContainer = $Stock
@onready var _have: Label = $Stock/Have
@onready var _damaged: Label = $Stock/Damaged
@onready var _after: Label = $Stock/After
@onready var _detail: Label = $Detail
@onready var _price: Label = $Price
@onready var _buy: Button = $BuyButton


## 「腐る」を2行目に置いたときの幅（頭の空白込み）。
func _rot_width_on_line2() -> float:
	var text := _rot.text
	_rot.text = " 腐る"
	var w := _rot.get_minimum_size().x
	_rot.text = text
	return w


func _ready() -> void:
	_buy.pressed.connect(func(): buy_pressed.emit())


func _clear_chips() -> void:
	for child in _tags.get_children():
		if child != _rot and child != _name:
			_tags.remove_child(child)
			child.queue_free()


func _add_chips(item: String, compact: bool) -> void:
	for tag in Ingredients.tags_for(item):
		_tags.add_child(UiTagChips.make(str(tag), compact))
	if _rot.get_parent() == _tags:
		_tags.move_child(_rot, -1)   # 並び：品名・札…・「腐る」


## 1行目（品名・札・「腐る」）に使える幅：価格の文字の左端の少し手前まで。
func _line1_room() -> float:
	return _price.offset_right - _price.get_minimum_size().x - 4.0 - _tags.offset_left


## 2行目（手持ち・傷・→ 購入後・2行目へ回した「腐る」）に使える幅：右の「3個 / 単価8」の文字の左端の少し手前まで
## （1行目と同じ考え。個数の無い商品は価格の列の右端まで）。
func _line2_room() -> float:
	var right := _detail.offset_right - (_detail.get_minimum_size().x if _detail.text != "" else 0.0)
	return right - 4.0 - _stock.offset_left


## 「腐る」を1行目（品名・札の後ろ）か2行目（手持ちの後ろ）に置く。2行目は間隔0なので、頭に空白を付ける。
func _place_rot(on_line1: bool) -> void:
	var parent := _tags if on_line1 else _stock
	if _rot.get_parent() != parent:
		_rot.get_parent().remove_child(_rot)
		parent.add_child(_rot)
	parent.move_child(_rot, -1)
	_rot.text = "腐る" if on_line1 else " 腐る"


## in_cart：その品目をかごに入れた分の個数（UiShopCart.units_by_item。0 なら「→ 購入後」を出さない）。
func show_good(good: Dictionary, can_buy: bool, in_cart: int = 0) -> void:
	var item := str(good["item"])
	_name.text = str(good["label"])
	_price.text = "¥%d" % int(good["price"])
	# 2行目を先に決める（「腐る」を2行目へ回せるかは、2行目の幅で決まる）
	_detail.text = "%d個 / 単価%d" % [int(good["count"]), int(good["unit_price"])] if int(good["count"]) > 0 else ""
	var damaged := int(good["damaged"])
	var have := int(good["fresh"]) + damaged
	_have.text = "手持ち%d" % have
	_damaged.visible = damaged > 0
	_damaged.text = "（傷%d）" % damaged
	_after.visible = in_cart > 0
	_after.text = ("→ %d" if damaged > 0 else " → %d") % (have + in_cart)   # 「（傷1）→ 9」「手持ち3 → 9」
	_stock.move_child(_after, 2)   # 並び：手持ち・（傷）・→ 購入後（・2行目へ回した「腐る」）
	_clear_chips()
	_place_rot(true)
	_rot.visible = item != "" and Ingredients.is_perishable(item)
	if item != "":
		# タグの言葉の札（味と具で色が2系統。UI準備F）。1行目に入りきらない行は、2行目に余裕があれば「腐る」を2行目へ、
		# それでも入らなければ札を小さい版に。小さい版でも入らず「腐る」がまだ1行目なら、最後に2行目へ回す。
		_add_chips(item, false)
		if _rot.visible and _tags.get_combined_minimum_size().x > _line1_room() 				and _stock.get_combined_minimum_size().x + _rot_width_on_line2() <= _line2_room():
			_place_rot(false)
		if _tags.get_combined_minimum_size().x > _line1_room():
			_clear_chips()
			_add_chips(item, true)
		if _rot.visible and _rot.get_parent() == _tags and _tags.get_combined_minimum_size().x > _line1_room():
			_place_rot(false)
	var affordable := bool(good["affordable"])
	var dim := Color(1, 1, 1, 1) if affordable else Color(1, 1, 1, 0.45)
	_name.modulate = dim
	_price.modulate = dim
	_buy.disabled = not (can_buy and affordable)
