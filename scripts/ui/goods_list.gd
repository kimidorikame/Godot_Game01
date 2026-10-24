extends VBoxContainer
class_name UiGoodsList
## 購入画面の商品の行を、shop_view() の件数だけ並べる（行の形は scenes/ui/goods_row.tscn）。
## 押された行の商品（そのときの shop_view() の1件）を buy で知らせる。

signal buy(good: Dictionary)

const ROW_PATH := "res://scenes/ui/goods_row.tscn"

var _goods: Array = []


func show_goods(goods: Array, can_buy: bool) -> void:
	_goods = goods
	while get_child_count() < goods.size():
		var row: UiGoodsRow = (load(ROW_PATH) as PackedScene).instantiate()
		add_child(row)
		row.buy_pressed.connect(_on_row_buy.bind(get_child_count() - 1))
	for i in range(get_child_count()):
		var row: UiGoodsRow = get_child(i)
		row.visible = i < goods.size()
		if i < goods.size():
			row.show_good(goods[i], can_buy)


func _on_row_buy(index: int) -> void:
	if index < _goods.size():
		buy.emit(_goods[index])
