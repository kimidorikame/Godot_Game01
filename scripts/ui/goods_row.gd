extends Panel
class_name UiGoodsRow
## 購入画面の商品の行（388×61）。寸法表 SCREENS_UI_LAYOUT §6。
## 1行目：品名・タグの言葉の札（味と具で色が2系統）・「腐る」。2行目：「3個 / 単価8 / 在庫4(新鮮3・傷1)」。右に価格と「買う」。
## 中身は shop_view() の1件。押せるかは呼び出し側が決める（買えない＝所持金不足は品名と価格を薄くする）。

signal buy_pressed()   # 「かごに入れる」が押された

@onready var _name: Label = $Tags/Name
@onready var _tags: HBoxContainer = $Tags
@onready var _rot: Label = $Tags/Rot
@onready var _detail: Label = $Detail
@onready var _price: Label = $Price
@onready var _buy: Button = $BuyButton


func _ready() -> void:
	_buy.pressed.connect(func(): buy_pressed.emit())


func _add_chips(item: String, compact: bool) -> void:
	for tag in Ingredients.tags_for(item):
		_tags.add_child(UiTagChips.make(str(tag), compact))


func show_good(good: Dictionary, can_buy: bool) -> void:
	var item := str(good["item"])
	_name.text = str(good["label"])
	for child in _tags.get_children():
		if child != _rot and child != _name:
			_tags.remove_child(child)
			child.queue_free()
	_rot.visible = item != "" and Ingredients.is_perishable(item)
	if item != "":
		# タグの言葉の札（味と具で色が2系統。UI準備F）。品名が長くて「腐る」まで1行に入らない行だけ、同じ色・形の小さい版にする。
		_add_chips(item, false)
		_tags.move_child(_rot, -1)   # 並び：品名・タグ…・「腐る」
		if _tags.get_combined_minimum_size().x > _tags.offset_right - _tags.offset_left:
			for child in _tags.get_children():
				if child != _rot and child != _name:
					_tags.remove_child(child)
					child.queue_free()
			_add_chips(item, true)
	_tags.move_child(_rot, -1)
	if int(good["count"]) > 0:
		_detail.text = "%d個 / 単価%d / 在庫%d(新鮮%d・傷%d)" % [int(good["count"]), int(good["unit_price"]),
			int(good["fresh"]) + int(good["damaged"]), int(good["fresh"]), int(good["damaged"])]
	else:
		_detail.text = "手持ち%d" % int(good["fresh"])
	_price.text = "¥%d" % int(good["price"])
	var affordable := bool(good["affordable"])
	var dim := Color(1, 1, 1, 1) if affordable else Color(1, 1, 1, 0.45)
	_name.modulate = dim
	_price.modulate = dim
	_buy.disabled = not (can_buy and affordable)
