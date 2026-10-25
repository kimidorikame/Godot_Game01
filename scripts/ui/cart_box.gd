extends Panel
class_name UiCartBox
## 購入画面の「かご」の枠（388×86。UI準備D・D-2）。かごの中身（同じ商品はまとめて「豆腐×2 ¥48」）と合計、「1つ戻す」「全部戻す」。
## 中身は UiShopCart.grouped() の結果。ボタンは押したことを知らせるだけ（かごの操作は呼び出し側）。

signal undo_pressed()
signal clear_pressed()

@onready var _list: Label = %CartList
@onready var _total: Label = %CartTotal
@onready var _undo: Button = %UndoButton
@onready var _clear: Button = %ClearButton


func _ready() -> void:
	_undo.pressed.connect(func(): undo_pressed.emit())
	_clear.pressed.connect(func(): clear_pressed.emit())


## grouped：UiShopCart.grouped()。extra：商品以外に取り置いている行（選んだ鍋の素など。空でもよい）。
func show_cart(grouped: Array, total: int, extra: String = "") -> void:
	var parts: Array = []
	if extra != "":
		parts.append(extra)
	for entry in grouped:
		parts.append("%s×%d ¥%d" % [str(entry["label"]), int(entry["qty"]), int(entry["price"])])
	_list.text = "・".join(parts) if not parts.is_empty() else "（空）"
	_list.theme_type_variation = &"LabelSub" if not parts.is_empty() else &"LabelDim"
	_total.text = "合計 ¥%d" % total
	_undo.disabled = grouped.is_empty()
	_clear.disabled = grouped.is_empty() and extra == ""
