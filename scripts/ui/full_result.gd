extends Control
class_name UiFullResult
## 全面：結果（最終日のあと）。寸法表 SCREENS_UI_LAYOUT §8。3ページ（1 成績／2 目標／3 物語）の中身は
## 現行の結果画面と同じ（RESULT の列の3つの文＝Result.format_report／format_goals／format_story）。
## ページのタブ・「次へ」は表示だけの状態。3ページ目に出口（exits()）：もう一度（Day1の朝から）→ run_again()、
## 最後の朝から → last_morning()、新しい周 → new_run()。「タイトルへ」はタイトル画面（フェーズ6）まで押せない。
## UI準備AE（週の終わり）：結果の画面に入ったとき、まず「夜湯」のタイトルを1枚だけ出す（暗い地に文字だけ。音・絵は無い）。
## 押す（クリック・決定のキー）と結果の3ページへ。表示だけの状態（title_open。フェーズに入るたびに reset_ui_state で戻す）。

const TITLES := ["1 成績", "2 目標", "3 物語"]

var session: PlaySession = null
var page := 0
## 表示だけの状態：週の終わりのタイトル（「夜湯」）を出しているか（UI準備AE）。
var title_open := true
var _title_card: ColorRect = null

@onready var _tabs: Control = %Tabs
@onready var _underline: ColorRect = %Underline
@onready var _body: Label = %Body
@onready var _scroll: ScrollContainer = %BodyScroll
@onready var _exits: HBoxContainer = %Exits
@onready var _run_again: Button = %RunAgainButton
@onready var _last_morning: Button = %LastMorningButton
@onready var _new_run: Button = %NewRunButton
@onready var _title: Button = %TitleButton
@onready var _next: Button = %NextButton


func _ready() -> void:
	for i in range(_tabs.get_child_count()):
		(_tabs.get_child(i) as Button).pressed.connect(_set_page.bind(i))
	_next.pressed.connect(func(): _set_page(mini(page + 1, TITLES.size() - 1)))
	_run_again.pressed.connect(func(): session.run_again())
	_last_morning.pressed.connect(func(): session.last_morning())
	_new_run.pressed.connect(func(): session.new_run())
	_title_card = _make_title_card()


## 週の終わりのタイトル（UI準備AE）：画面いっぱいの暗い地に「夜湯」。押すと閉じる（_close_title）。
func _make_title_card() -> ColorRect:
	var card := ColorRect.new()
	card.name = "TitleCard"
	card.color = Color(0.03, 0.035, 0.05, 1.0)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_title_input)
	add_child(card)
	var title := Label.new()
	title.name = "TitleText"
	title.text = "夜湯"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.add_theme_font_size_override(&"font_size", 96)
	title.add_theme_color_override(&"font_color", Color(0.93, 0.9, 0.84, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)
	return card


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_close_title()


func _unhandled_input(event: InputEvent) -> void:
	if visible and title_open and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_close_title()


## タイトルを閉じて、結果の1ページ目へ。
func _close_title() -> void:
	title_open = false
	refresh()


func bind_session(s: PlaySession) -> void:
	session = s


func reset_ui_state() -> void:
	page = 0
	title_open = true


func refresh() -> void:
	if session == null:
		return
	if _title_card != null:
		_title_card.visible = title_open
	var texts: Array = []
	if session.flow.runner != null:
		for ev in session.flow.runner.events:
			if ev is Dictionary and str(ev.get("type", "")) == "TEXT":
				texts.append(str(ev.get("text", "")))
	page = clampi(page, 0, TITLES.size() - 1)
	for i in range(_tabs.get_child_count()):
		var tab: Button = _tabs.get_child(i)
		tab.text = TITLES[i]
		tab.theme_type_variation = &"ButtonTabOn" if i == page else &"ButtonTab"
	_underline.position.x = (_tabs.get_child(page) as Control).position.x
	_body.text = str(texts[page]) if page < texts.size() else ""
	var exits := session.exits()
	var last := page == TITLES.size() - 1
	_exits.visible = last and bool(exits["available"])
	_run_again.disabled = not bool(exits["can_run_again"])
	_last_morning.disabled = not bool(exits["can_last_morning"])
	_new_run.disabled = not bool(exits["can_new_run"])
	_next.disabled = last
	_title.disabled = true   # タイトル画面はフェーズ6


func _set_page(index: int) -> void:
	page = index
	_scroll.scroll_vertical = 0
	refresh()
