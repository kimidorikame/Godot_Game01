extends Panel
class_name UiPanePhone
## 右の枠：スマホ（右の枠・開店中は操作エリアと入れ替わる。重ね表示はしない）。寸法表 SCREENS_UI_LAYOUT §3。
## タブは SNS／ニュース／レシピ。SNS＝phone_dm()（常連・市場の顔なじみなどからのDM。新しい順。客足予報は出さない）。
## 未読のDMがあれば SNS タブに数（注意色）を出し、SNS タブを表示した時点で読んだ扱いにする（mark_dms_read）。
## 表示中の一覧では、開いた時点で未読だった行に左の注意色の線を残す（スマホを閉じるまで）。
## ニュース＝phone_news() のニュース（日付・見出し・本文）、レシピ＝phone_recipes()（保存したレシピと、客ごとの「いつもの」）。
## 品名は本名（短縮名は開店の操作エリアだけ）。「閉じる」で元の画面に戻る（開店中は「閉じる(鍋・トッピングに戻る)」）。

signal close_requested()
## SNS タブを表示して、未読のDMを読んだ扱いにしたとき（スマホのボタンの未読の印を消すため）。
signal dms_read()

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
@onready var _badge: Label = %SnsBadge

## このスマホを開いてから、未読として見せたDMのid（行の左に線を残す）。閉じる・区切りで捨てる。
var _fresh := {}


func _ready() -> void:
	for i in range(TABS.size()):
		(_tabs.get_child(i) as Button).pressed.connect(_on_tab_pressed.bind(TABS[i]))
	_close.pressed.connect(func(): close_requested.emit())


func bind_session(s: PlaySession) -> void:
	session = s


## 区切り・閉じるで、表示だけの状態を捨てる。
func reset_ui_state() -> void:
	_fresh = {}


func refresh() -> void:
	if session == null:
		return
	var info := session.day_info()
	var slot := str(info["slot_name"])
	_top_right.text = "Day %d%s" % [int(info["day"]), ("・" + slot) if slot != "" else ""]
	var index := TABS.find(tab)
	for i in range(TABS.size()):
		(_tabs.get_child(i) as Button).theme_type_variation = &"ButtonTabOn" if i == index else &"ButtonTab"
	_underline.position.x = (_tabs.get_child(index) as Control).position.x
	_close.text = "閉じる(鍋・トッピングに戻る)" if GameState.phase == GameState.Phase.OPEN else "閉じる"
	_refresh_badge()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match tab:
		"sns":
			_fill_sns()
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


## DMの一覧（新しい順）。1件 388×65：丸い顔・名前・常連の印・時刻・本文。未読は左に注意色の線。
func _fill_sns() -> void:
	var items := session.phone_dm()
	if items.is_empty():
		_add("まだ新着はありません", &"LabelDim")
		return
	for item in items:
		if bool(item["unread"]):
			_fresh[str(item["id"])] = true
	for item in items:
		_add_dm_row(item, _fresh.has(str(item["id"])))
	var unread_before := session.dm_unread_count()
	session.mark_dms_read()   # 表示した時点で既読にする
	if unread_before > 0:
		dms_read.emit()


func _add_dm_row(item: Dictionary, unread: bool) -> void:
	var row := Panel.new()
	row.theme_type_variation = &"PanelBox"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(row)   # 先に木へ入れる（文字の高さを、テーマのフォントで測るため）
	var text := Label.new()
	text.text = str(item["text"])
	text.theme_type_variation = &"LabelPhoneBody"
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.position = Vector2(62, 30)
	text.size = Vector2(316, 0)
	row.add_child(text)
	# 本文が2行以上に折り返すときは、行を高くする（1行なら寸法表どおり 388×65）
	var font := text.get_theme_font(&"font")
	var text_height := font.get_multiline_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, 316.0, text.get_theme_font_size(&"font_size"),
		-1, TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_MANDATORY).y
	text.custom_minimum_size = Vector2(316, text_height)
	row.custom_minimum_size = Vector2(388, maxf(65.0, 36.0 + text_height))
	# 丸い顔（仮の絵）
	var face := Panel.new()
	var face_style := StyleBoxFlat.new()
	face_style.bg_color = get_theme_color(&"portrait", &"UiPalette")
	face_style.set_corner_radius_all(20)
	face.add_theme_stylebox_override("panel", face_style)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2(14, 12)
	face.size = Vector2(40, 40)
	row.add_child(face)
	var from_label := Label.new()
	from_label.text = str(item["from"])
	from_label.theme_type_variation = &"LabelShop"
	from_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	from_label.position = Vector2(62, 4)
	from_label.size = Vector2(190, 26)
	row.add_child(from_label)
	if str(item["from_kind"]) != "npc":
		var mark := Label.new()
		mark.text = "常連"
		mark.theme_type_variation = &"LabelTag"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.position = Vector2(62 + minf(from_label.get_minimum_size().x, 190.0) + 6.0, 8)
		row.add_child(mark)
	var time := Label.new()
	time.text = str(item["time"])
	time.theme_type_variation = &"LabelCaption"
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time.position = Vector2(300, 6)
	time.size = Vector2(76, 22)
	row.add_child(time)
	if unread:
		var bar := ColorRect.new()
		bar.color = get_theme_color(&"warn", &"UiPalette")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(0, 0)
		bar.size = Vector2(4, row.custom_minimum_size.y)
		row.add_child(bar)


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


## SNSタブの未読の数（注意色の丸）。SNSタブを表示しているあいだは読んだ扱いなので出さない。
func _refresh_badge() -> void:
	var unread := session.dm_unread_count() if tab != "sns" else 0
	_badge.text = "●%d" % unread if unread > 0 else ""


func _on_tab_pressed(next_tab: String) -> void:
	tab = next_tab
	_scroll.scroll_vertical = 0
	refresh()
