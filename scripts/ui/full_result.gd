extends Control
class_name UiFullResult
## 全面：結果（最終日のあと）。寸法表 SCREENS_UI_LAYOUT §8。3ページ（1 成績／2 目標／3 物語）の中身は
## 現行の結果画面と同じ（RESULT の列の3つの文＝Result.format_report／format_goals／format_story）。
## ページのタブ・「次へ」は表示だけの状態。3ページ目に出口（exits()）：もう一度（Day1の朝から）→ run_again()、
## 最後の朝から → last_morning()、新しい周 → new_run()。「タイトルへ」はタイトル画面（フェーズ6）まで押せない。

const TITLES := ["1 成績", "2 目標", "3 物語"]

var session: PlaySession = null
var page := 0

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


func bind_session(s: PlaySession) -> void:
	session = s


func reset_ui_state() -> void:
	page = 0


func refresh() -> void:
	if session == null:
		return
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
