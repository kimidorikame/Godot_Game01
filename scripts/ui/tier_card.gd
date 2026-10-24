extends Button
class_name UiTierCard
## 鍋の素の1段階（124×119）。寸法表 SCREENS_UI_LAYOUT §5。
## 小／中／大、杯数、価格（強調色）、「濃さ3から」。買った段階は強調色の枠と「買った」。

@onready var _label: Label = $Label
@onready var _servings: Label = $Servings
@onready var _price: Label = $Price
@onready var _note: Label = $Note
@onready var _frame: Control = $BoughtFrame


func show_tier(tier: Dictionary, bought: bool, can_choose: bool) -> void:
	_label.text = str(tier["label"]).replace("仕込み", "")
	_servings.text = "%d杯" % int(tier["servings"])
	_price.text = "¥%d" % int(tier["price"])
	_note.text = "買った" if bought else "濃さ3から"
	_note.theme_type_variation = &"LabelCaptionAccent" if bought else &"LabelCaption"
	_frame.visible = bought
	disabled = not can_choose
