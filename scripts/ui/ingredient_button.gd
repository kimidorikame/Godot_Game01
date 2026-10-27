extends Control
class_name UiIngredientButton
## 開店のトッピングの具材ボタン（93×42）。寸法表 KAITEN_UI_LAYOUT §4・§5-2。
## 本体（名前の短縮名と「×在庫数」）を押す＝傷んでいない側。右端の「傷N」（28×40）を押す＝傷んだ側。
## 傷んだ在庫が無いときは右端の部分を出さない（ボタンの数・位置は変わらない）。
## 下の段に、その材料のタグの言葉の札（UI準備F。高さを42→58にして、1ページ8個に減らした）。

signal main_pressed()
signal damaged_pressed()

@onready var _main: Button = $MainButton
@onready var _name: Label = $MainButton/Name
@onready var _count: Label = $MainButton/Count
@onready var _damaged: Button = $DamagedButton
@onready var _chips: HBoxContainer = $MainButton/Chips


func _ready() -> void:
	_main.pressed.connect(func(): main_pressed.emit())
	_damaged.pressed.connect(func(): damaged_pressed.emit())


## in_bowl：椀に入っている（名前の頭に「✓」。もう一度押すと取り消す。UI準備D・D-3）。
func show_item(item_id: String, fresh: int, damaged: int, main_enabled: bool, damaged_enabled: bool, in_bowl: bool = false) -> void:
	_name.text = ("✓" if in_bowl else "") + UiLabels.short_name(item_id)
	UiTagChips.fill(_chips, Ingredients.tags_for(item_id), true)   # その材料のタグの言葉の札（全部。UI準備F）
	_count.text = "×%d" % fresh
	_main.disabled = not main_enabled
	_damaged.visible = damaged > 0
	_damaged.text = "傷\n%d" % damaged
	_damaged.disabled = not damaged_enabled
