extends Panel
class_name UiCartBox
## 購入画面の「かご」の枠（388幅。UI準備D・D-2。UI準備F3で小さくして、下（ボタンの上）に寄せた）。かごの中身（同じ商品はまとめて「豆腐×2 ¥48」）と合計、「1つ戻す」「全部戻す」。
## 中身は UiShopCart.grouped() の結果。ボタンは押したことを知らせるだけ（かごの操作は呼び出し側）。

signal undo_pressed()
signal clear_pressed()
signal fitted()   # 枠の高さが変わった（上端が動いた）。上に並ぶ商品の一覧の下端を合わせ直す

## 中身の行数（かごの中の一覧。折り返しも数える）に合わせて高さが伸びる：空は1行、品が入ると最大 MAX_LINES 行まで。それ以上は一覧の中で縦に送る。
## 下端は動かさず、上端が上へ伸びる。
const MAX_LINES := 3
const HEAD := 28.0     # 1行目（かご・「1つ戻す」「全部戻す」・合計）の高さ
const FOOT := 6.0

@onready var _list: Label = %CartList
@onready var _scroll: ScrollContainer = %CartScroll
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
	_list.modulate = Color(1, 1, 1, 1.0) if not parts.is_empty() else Color(1, 1, 1, 0.55)   # 空のときは薄く（大きさは中身のときと同じ＝1行）
	_total.text = "合計 ¥%d" % total
	_undo.disabled = grouped.is_empty()
	_clear.disabled = grouped.is_empty() and extra == ""
	_fit()


## 一覧の行数（折り返し込み。フォントの高さから数える＝描く前でも同じ値）に合わせて、枠の高さと一覧の高さを決める。
func _fit() -> void:
	# 型の名前を指定して引く（theme_type_variation を変えた直後は、引数なしだと前の値のまま）
	var variation := String(_list.theme_type_variation)
	var font := _list.get_theme_font("font", variation)
	var size := _list.get_theme_font_size("font_size", variation)
	var width := _list.custom_minimum_size.x
	var line_h := font.get_height(size)
	var content_h := font.get_multiline_string_size(_list.text, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND).y
	var lines := clampi(ceili(content_h / line_h - 0.3), 1, MAX_LINES)
	var list_h := ceilf(line_h * lines)
	_scroll.offset_bottom = _scroll.offset_top + list_h
	var height := HEAD + list_h + FOOT
	var bottom := offset_bottom
	custom_minimum_size.y = height
	offset_top = bottom - height
	fitted.emit()
