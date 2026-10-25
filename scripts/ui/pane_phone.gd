extends Panel
class_name UiPanePhone
## 右の枠：スマホ（右の枠・開店中は操作エリアと入れ替わる。重ね表示はしない）。寸法表 SCREENS_UI_LAYOUT §3。
## タブは SNS／ニュース／レシピ。SNS は C で DM に替えるまで「まだ新着はありません」の仮表示（客足予報は出さない）。
## ニュース＝phone_news() のニュース（日付・見出し・本文）、レシピ＝phone_recipes()（保存したレシピと、客ごとの「いつもの」）。
## 品名は本名（短縮名は開店の操作エリアだけ）。「閉じる」で元の画面に戻る（開店中は「閉じる(鍋・トッピングに戻る)」）。

signal close_requested()

const TABS := ["sns", "news", "recipe"]

var session: PlaySession = null
## 表示だけの状態：開いているタブ。
var tab := "news"

@onready var _top_right: Label = %TopRight
@onready var _tabs: Control = %Tabs
@onready var _underline: ColorRect = %Underline
@onready var _scroll: ScrollContainer = %Scroll
@onready var _content: VBoxContainer = %Content
@onready var _close: Button = %CloseButton


func _ready() -> void:
	for i in range(_tabs.get_child_count()):
		(_tabs.get_child(i) as Button).pressed.connect(_on_tab_pressed.bind(TABS[i]))
	_close.pressed.connect(func(): close_requested.emit())


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	var info := session.day_info()
	var slot := str(info["slot_name"])
	_top_right.text = "Day %d%s" % [int(info["day"]), ("・" + slot) if slot != "" else ""]
	var index := TABS.find(tab)
	for i in range(_tabs.get_child_count()):
		(_tabs.get_child(i) as Button).theme_type_variation = &"ButtonTabOn" if i == index else &"ButtonTab"
	_underline.position.x = (_tabs.get_child(index) as Control).position.x
	_close.text = "閉じる(鍋・トッピングに戻る)" if GameState.phase == GameState.Phase.OPEN else "閉じる"
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match tab:
		"sns":
			_add("まだ新着はありません", &"LabelDim")
		"news":
			_fill_news()
		"recipe":
			_fill_recipes()


func _add(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(380, 0)
	_content.add_child(label)
	return label


func _fill_news() -> void:
	var count := 0
	for section in session.phone_news():
		if (section["news"] as Array).is_empty():
			continue
		_add("Day %d%s" % [int(section["day"]), "（今日）" if bool(section["is_today"]) else ""], &"LabelSub")
		for item in section["news"]:
			_add(str(item["headline"]), &"LabelPhoneHeadline")
			for line in item["body"]:
				_add(str(line), &"LabelPhoneBody")
			count += 1
	if count == 0:
		_add("ニュースはまだありません", &"LabelDim")


func _fill_recipes() -> void:
	var recipes := session.phone_recipes()
	_add("保存したレシピ", &"LabelSub")
	for slot in recipes["slots"]:
		if str(slot["name"]) == "":
			_add("枠%d（空き）" % (int(slot["index"]) + 1), &"LabelDim")
		else:
			_add("枠%d %s：%s" % [int(slot["index"]) + 1, str(slot["name"]), _names(slot["ingredients"])], &"LabelPhoneBody")
	_add("いつもの", &"LabelSub")
	if (recipes["usual"] as Array).is_empty():
		_add("まだありません", &"LabelDim")
	for item in recipes["usual"]:
		_add("%s：%s" % [session.log_speaker(str(item["customer"])), _names(item["ingredients"])], &"LabelPhoneBody")


static func _names(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(Ingredients.name_for(str(id)))
	return "・".join(names)


func _on_tab_pressed(next_tab: String) -> void:
	tab = next_tab
	_scroll.scroll_vertical = 0
	refresh()
