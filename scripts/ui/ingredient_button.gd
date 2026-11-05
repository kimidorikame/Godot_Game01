extends Control
class_name UiIngredientButton
## 開店のトッピングの具材ボタン（126×66。UI準備P：文字を大きくして、横4列→3列・1ページ6個にした）。寸法表 KAITEN_UI_LAYOUT §4・§5-2。
## 本体（名前の短縮名と「×在庫数」）を押す＝傷んでいない側。右上の「傷N」（31×42）を押す＝傷んだ側。
## 傷んだ在庫が無いときは右上の部分を出さない（ボタンの数・位置は変わらない）。
## 下の段に、その材料のタグの言葉の札（UI準備F）。
## 椀に入っている具材は、名前の右に「×」の印（強調色の丸。もう一度押すと取り消せる。UI準備P。以前は名前の頭の「✓」）。

signal main_pressed()
signal damaged_pressed()

@onready var _main: Button = $MainButton
@onready var _name: Label = $MainButton/Name
@onready var _count: Label = $MainButton/Count
@onready var _remove_mark: Label = $MainButton/RemoveMark
@onready var _damaged: Button = $DamagedButton
@onready var _chips: HBoxContainer = $MainButton/Chips


func _ready() -> void:
	_main.pressed.connect(func(): main_pressed.emit())
	_damaged.pressed.connect(func(): damaged_pressed.emit())


## in_bowl：椀に入っている（名前の右に「×」の印。もう一度押すと取り消す。UI準備D・D-3、印は UI準備P）。
func show_item(item_id: String, fresh: int, damaged: int, main_enabled: bool, damaged_enabled: bool, in_bowl: bool = false) -> void:
	_name.text = UiLabels.short_name(item_id)
	_remove_mark.visible = in_bowl
	UiTagChips.fill(_chips, Ingredients.tags_for(item_id), true)   # その材料のタグの言葉の札（全部。UI準備F）
	_count.text = "×%d" % fresh
	_main.disabled = not main_enabled
	_damaged.visible = damaged > 0
	_count.offset_right = 90.0 if damaged > 0 else 120.0   # 右上の「傷N」があるときは、その左で右寄せ
	_damaged.text = "傷\n%d" % damaged
	_damaged.disabled = not damaged_enabled
