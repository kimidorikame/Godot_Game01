extends Panel
class_name UiPanePhone
## 右の枠：スマホ（右の枠・開店中は操作エリアと入れ替わる。重ね表示はしない）。寸法表 SCREENS_UI_LAYOUT §3。
## タブは SNS／ニュース／持ち物／客（レシピタブは無くして、持ち物に置き換えた。UI準備I2・I3）。客タブは店主のメモ帳（一覧→詳細。UI準備O2）。SNS＝phone_dm()（常連・市場の顔なじみなどからのDM。新しい順。客足予報は出さない）。
## 未読のDMがあれば SNS タブに数（注意色）を、未読のニュースがあればニュースタブに数を出し、そのタブを表示した時点で読んだ扱いにする
## （mark_dms_read・mark_news_read）。
## 表示中の一覧では、開いた時点で未読だった行に左の注意色の線を残す（スマホを閉じるまで）。
## ニュース＝phone_news() のニュース。一覧（日付と見出し。新しい日が上）→行を押すと詳細（見出し・日付・本文の全部）→「戻る」で一覧（UI準備O）。
## 品名は本名（短縮名は開店の操作エリアだけ）。「閉じる」で元の画面に戻る（開店中は「閉じる(鍋・トッピングに戻る)」）。

signal close_requested()
## SNS・ニュースのタブを表示して、未読を読んだ扱いにしたとき（スマホのボタンの未読の印を消すため）。
signal unread_cleared()

const TABS := ["sns", "news", "inventory", "notes"]

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
@onready var _news_badge: Label = %NewsBadge
@onready var _notes_badge: Label = %NotesBadge

## このスマホを開いてから、未読として見せたDMのid（行の左に線を残す）。閉じる・区切りで捨てる。
var _fresh := {}
## このスマホを開いてから、未読として見せたニュースのid（見出しの頭に●を残す）。
var _fresh_news := {}
## 表示だけの状態：詳細を開いているニュースのid（"" なら一覧。UI準備O）。タブを替える・閉じる・区切りで一覧に戻す。
var news_open := ""
## 表示だけの状態：詳細を開いている客（名前あり客の id／モブは "mob:<種類>"。"" なら一覧。UI準備O2）。ニュースと同じく一覧に戻す。
var notes_open := ""
## 詳細を開いた時点で「新」だったメモの行の id（その詳細を開いているあいだ、描き直しても印を残す。開き直す・閉じる・区切りで捨てる）。
var _fresh_memo := {}


func _ready() -> void:
	for i in range(TABS.size()):
		(_tabs.get_child(i) as Button).pressed.connect(_on_tab_pressed.bind(TABS[i]))
	_close.pressed.connect(func(): close_requested.emit())


func bind_session(s: PlaySession) -> void:
	session = s


## 区切り・閉じるで、表示だけの状態を捨てる。
func reset_ui_state() -> void:
	_fresh = {}
	_fresh_news = {}
	news_open = ""
	notes_open = ""
	_fresh_memo = {}


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
	_underline.size.x = (_tabs.get_child(index) as Control).size.x
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
		"inventory":
			UiInventoryList.fill(_content, session.inventory_view())
		"notes":
			_fill_notes()


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
		unread_cleared.emit()


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
	var time := Label.new()
	time.text = Calendar.stamp(int(item.get("day", GameState.day_count)), str(item["time"]))   # 「Day3 05:40」（日付は届いた日。形は Calendar）
	time.theme_type_variation = &"LabelCaption"
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time.position = Vector2(262, 6)
	time.size = Vector2(114, 22)
	row.add_child(time)
	if unread:
		var bar := ColorRect.new()
		bar.color = get_theme_color(&"warn", &"UiPalette")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(0, 0)
		bar.size = Vector2(4, row.custom_minimum_size.y)
		row.add_child(bar)


func _fill_news() -> void:
	var unread_before := session.news_unread_count()
	var sections := session.phone_news()
	for section in sections:
		for item in section["news"]:
			if bool(item["unread"]):
				_fresh_news[str(item["id"])] = true
			if str(item["id"]) == news_open:
				_fill_news_detail(item, section)
				return
	news_open = ""
	var count := 0
	for section in sections:
		for item in section["news"]:
			_add_news_row(item, section)
			count += 1
	if count == 0:
		_add("ニュースはまだありません", &"LabelDim")
	session.mark_news_read()   # 表示した時点で既読にする
	if unread_before > 0:
		unread_cleared.emit()


## ニュースの日付（「Day3（今日）」。形は Calendar）。
func _news_date(section: Dictionary) -> String:
	return "%s%s" % [Calendar.label(int(section["day"])), "（今日）" if bool(section["is_today"]) else ""]


## ニュースの一覧の1行（388幅のボタン）：日付・見出し（折り返す）。押すと詳細へ。未読だった行は見出しの頭に●。
func _add_news_row(item: Dictionary, section: Dictionary) -> void:
	var row := Button.new()
	row.name = "NewsRow_%s" % str(item["id"])
	row.theme_type_variation = &"ButtonRow"
	row.focus_mode = Control.FOCUS_NONE
	_content.add_child(row)   # 先に木へ入れる（見出しの高さを、テーマのフォントで測るため）
	var date := Label.new()
	date.text = _news_date(section)
	date.theme_type_variation = &"LabelCaption"
	date.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date.position = Vector2(12, 4)
	date.size = Vector2(340, 20)
	row.add_child(date)
	var headline := Label.new()
	headline.text = ("● " if _fresh_news.has(str(item["id"])) else "") + str(item["headline"])
	headline.theme_type_variation = &"LabelPhoneHeadline"
	headline.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	headline.position = Vector2(12, 26)
	row.add_child(headline)
	var font := headline.get_theme_font(&"font")
	var height := font.get_multiline_string_size(headline.text, HORIZONTAL_ALIGNMENT_LEFT, 340.0, headline.get_theme_font_size(&"font_size"),
		-1, TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_MANDATORY).y
	headline.custom_minimum_size = Vector2(340, height)
	headline.size = Vector2(340, height)
	var arrow := Label.new()
	arrow.text = "›"
	arrow.theme_type_variation = &"LabelSub"
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.position = Vector2(364, 4)
	arrow.size = Vector2(16, 20)
	row.add_child(arrow)
	row.custom_minimum_size = Vector2(388, maxf(56.0, 34.0 + height))
	row.pressed.connect(open_news.bind(str(item["id"])))


## ニュースの詳細：「戻る」・見出し・日付・本文（body の全部。長ければ縦に送れる）。
func _fill_news_detail(item: Dictionary, section: Dictionary) -> void:
	var back := Button.new()
	back.name = "NewsBack"
	back.text = "‹ 戻る"
	back.theme_type_variation = &"ButtonSmall"
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(close_news)
	_content.add_child(back)
	_add(str(item["headline"]), &"LabelPhoneHeadline").name = "NewsHeadline"
	_add(_news_date(section), &"LabelCaption").name = "NewsDate"
	for line in item["body"]:
		_add(str(line), &"LabelPhoneBody")


## ニュースの詳細を開く（一覧の行を押したとき）。表示だけの状態。
func open_news(id: String) -> void:
	news_open = id
	_scroll.scroll_vertical = 0
	refresh()


## ニュースの詳細から一覧へ戻る。
func close_news() -> void:
	news_open = ""
	_scroll.scroll_vertical = 0
	refresh()


## 客タブ＝店主のメモ帳（UI準備G・O2）。一覧は名前だけ（名前あり客を先、モブを後。それぞれ出会った順）→行を押すと詳細→「戻る」で一覧。
## 一覧を表示した時点で、新しいメモの●を消す（mark_memos_seen）。まだ詳細で見ていないメモがある客の行には「新」。
func _fill_notes() -> void:
	var notes := session.phone_notes()
	if notes_open != "":
		for item in notes["regulars"]:
			if str(item["id"]) == notes_open:
				_fill_regular_detail(item)
				return
		for item in notes["mobs"]:
			if "mob:" + str(item["type"]) == notes_open:
				_fill_mob_detail(item)
				return
		notes_open = ""
	if (notes["regulars"] as Array).is_empty() and (notes["mobs"] as Array).is_empty():
		_add("まだ会った客はいません", &"LabelDim")
	if not (notes["regulars"] as Array).is_empty():
		_add("名前あり客", &"LabelSub")
		for item in notes["regulars"]:
			_add_name_row(str(item["id"]), str(item["name"]), not (item["memo_new"] as Array).is_empty())
	if not (notes["mobs"] as Array).is_empty():
		_add("モブ", &"LabelSub")
		for item in notes["mobs"]:
			_add_name_row("mob:" + str(item["type"]), str(item["name"]), false)
	var unread_before := session.memo_unread_count()
	session.mark_memos_seen()   # 客タブを表示した時点で●を消す（ニュースと同じ）
	if unread_before > 0:
		unread_cleared.emit()


## 一覧の1行（388幅のボタン）：名前（と、まだ見ていないメモがあれば「新」）。押すと詳細へ。
func _add_name_row(key: String, title: String, has_new: bool) -> void:
	var row := Button.new()
	row.name = "NoteRow_%s" % key.replace(":", "_")
	row.theme_type_variation = &"ButtonRow"
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(388, 40)
	_content.add_child(row)
	var name_label := Label.new()
	name_label.text = title
	name_label.theme_type_variation = &"LabelShop"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.position = Vector2(12, 6)
	name_label.size = Vector2(290, 28)
	row.add_child(name_label)
	if has_new:
		var mark := Label.new()
		mark.name = "NewMark"
		mark.text = "新"
		mark.theme_type_variation = &"LabelWarnSmall"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.position = Vector2(320, 10)
		mark.size = Vector2(36, 20)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(mark)
	var arrow := Label.new()
	arrow.text = "›"
	arrow.theme_type_variation = &"LabelSub"
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.position = Vector2(364, 8)
	arrow.size = Vector2(16, 24)
	row.add_child(arrow)
	row.pressed.connect(open_note.bind(key))


## 詳細の頭：「‹ 戻る」と名前。
func _add_detail_head(title: String) -> void:
	var back := Button.new()
	back.name = "NoteBack"
	back.text = "‹ 戻る"
	back.theme_type_variation = &"ButtonSmall"
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(close_note)
	_content.add_child(back)
	_add(title, &"LabelPhoneHeadline").name = "NoteName"


## 見出し（「いつもの」など）と札の1行。
func _add_tag_line(caption: String, tags: Array) -> void:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	_content.add_child(line)
	var head := Label.new()
	head.text = caption
	head.theme_type_variation = &"LabelCaption"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size = Vector2(60, 0)
	line.add_child(head)
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 4)
	line.add_child(chips)
	UiTagChips.fill(chips, tags)


## 名前あり客の詳細：上＝いつもの（基本の注文の札）・来た日・好物（知った客だけ）・前回の材料／下＝足したメモ（日付付き・古い順。「新」の印）。
func _fill_regular_detail(item: Dictionary) -> void:
	_add_detail_head(str(item["name"]))
	_add_tag_line("いつもの", item["tags"])
	_add("来た日　" + "・".join(PackedStringArray((item["days"] as Array).map(func(d): return Calendar.label(int(d))))), &"LabelSub")
	if bool(item["favorite_known"]):
		_add("好物　" + str(item["favorite"]), &"LabelSub")
	if not (item["usual_ingredients"] as Array).is_empty():
		_add("前回　" + "・".join(PackedStringArray(item["usual_ingredients"])), &"LabelSub")
	var rule := ColorRect.new()
	rule.color = get_theme_color(&"line", &"UiPalette")
	rule.custom_minimum_size = Vector2(380, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(rule)
	_add("メモ", &"LabelCaption")
	var memo: Array = item["memo"]
	if memo.is_empty():
		_add("まだ何も書いていない", &"LabelDim")
	for line in memo:
		_add_memo_line(line, _fresh_memo.has(str(line["id"])))


## メモの1行：日付・（新）・文（長ければ折り返す）。
func _add_memo_line(line: Dictionary, is_new: bool) -> void:
	var row := HBoxContainer.new()
	row.name = "Memo_%d" % _content.get_child_count()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	var date := Label.new()
	date.text = Calendar.label(int(line["day"]))
	date.theme_type_variation = &"LabelCaption"
	date.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date.custom_minimum_size = Vector2(44, 0)
	row.add_child(date)
	var mark := Label.new()
	mark.name = "NewMark"
	mark.text = "新" if is_new else ""
	mark.theme_type_variation = &"LabelWarnSmall"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.custom_minimum_size = Vector2(20, 0)
	row.add_child(mark)
	var text := Label.new()
	text.name = "Text"
	text.text = str(line["text"])
	text.theme_type_variation = &"LabelPhoneBody"
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.custom_minimum_size = Vector2(304, 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)


## モブの詳細：好みの札だけ（モブのメモは今は無い）。
func _fill_mob_detail(item: Dictionary) -> void:
	_add_detail_head(str(item["name"]))
	_add_tag_line("好み", item["tags"])


## 客の詳細を開く（一覧の行を押したとき）。名前あり客は、開いた時点で「新」だった行を覚えてから既読にする。
func open_note(key: String) -> void:
	notes_open = key
	_fresh_memo = {}   # 開くたびに取り直す（前に見た行には付けない）
	if not key.begins_with("mob:"):
		for id in session.memo_new_ids(key):
			_fresh_memo[str(id)] = true
		session.mark_memos_read(key)
	_scroll.scroll_vertical = 0
	refresh()


## 客の詳細から一覧へ戻る。
func close_note() -> void:
	notes_open = ""
	_scroll.scroll_vertical = 0
	refresh()


## SNSタブ・ニュースタブの未読の数（注意色の丸）。そのタブを表示しているあいだは読んだ扱いなので出さない。
func _refresh_badge() -> void:
	var dm_unread := session.dm_unread_count() if tab != "sns" else 0
	_badge.text = "●%d" % dm_unread if dm_unread > 0 else ""
	var news_unread := session.news_unread_count() if tab != "news" else 0
	_news_badge.text = "●%d" % news_unread if news_unread > 0 else ""
	var notes_unread := session.memo_unread_count() if tab != "notes" else 0
	_notes_badge.text = "●%d" % notes_unread if notes_unread > 0 else ""


func _on_tab_pressed(next_tab: String) -> void:
	tab = next_tab
	news_open = ""
	notes_open = ""
	_scroll.scroll_vertical = 0
	refresh()
