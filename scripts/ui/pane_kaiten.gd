extends Panel
class_name UiPaneKaiten
## 右の枠：開店の操作エリア（鍋／トッピングのタブ）。寸法表 KAITEN_UI_LAYOUT §2。
## 切り替え（plan Q5・寸法表 §5-4）：注文を受けたら（ADJUST の入力待ち）自動でトッピング、それ以外（提供後・次の客・
## 鍋が尽きた保留）は自動で鍋。タブを押せば手で切り替えられ、次に自動の切り替えが起きるまで有効。椀の中身は保持する
## （鍋タブは表示だけで、open_pot()/close_pot() は呼ばない）。
## 鍋タブの「●」は、トッピングを見ている間に鍋の手当てが要るとき（濃さ1・5）だけ出す。

var session: PlaySession = null

## 表示だけの状態：手で選んだタブ（"" なら自動）と、直前の自動の判断（＋いまの客）。
var manual_tab := ""
var _last_auto := ""

@onready var _pot_tab: Button = %PotTab
@onready var _topping_tab: Button = %ToppingTab
@onready var _underline: ColorRect = %Underline
@onready var _pot_dot: Label = %PotDot
@onready var pot: UiKaitenPot = %Pot
@onready var topping: UiKaitenTopping = %Topping


func _ready() -> void:
	_pot_tab.pressed.connect(_on_tab_pressed.bind("pot"))
	_topping_tab.pressed.connect(_on_tab_pressed.bind("topping"))


func bind_session(s: PlaySession) -> void:
	session = s
	pot.bind_session(s)
	topping.bind_session(s)


func reset_ui_state() -> void:
	manual_tab = ""
	_last_auto = ""
	topping.reset_ui_state()


## いま出しているタブ（"pot"／"topping"）。自動の判断（と、いまの客）が変わったら、手の選択はそこで終わる
## （次の客が来たら自動で鍋に戻る）。
func shown_tab() -> String:
	var auto := "topping" if topping.is_adjusting() and not session.is_shortage_pending() else "pot"
	var customer = session.open.current_customer() if session.open != null else null
	var key := "%s|%s" % [auto, str(customer)]
	if key != _last_auto:
		manual_tab = ""
		_last_auto = key
	return manual_tab if manual_tab != "" else auto


func refresh() -> void:
	if session == null:
		return
	var tab := shown_tab()
	pot.visible = tab == "pot"
	topping.visible = tab == "topping"
	_underline.position.x = _pot_tab.position.x if tab == "pot" else _topping_tab.position.x
	_pot_tab.theme_type_variation = &"ButtonTabOn" if tab == "pot" else &"ButtonTab"
	_topping_tab.theme_type_variation = &"ButtonTabOn" if tab == "topping" else &"ButtonTab"
	var view := session.pot_view()
	var strength := int(view.get("strength", 3))
	_pot_dot.visible = tab == "topping" and bool(view["exists"]) \
		and (strength == int(view["strength_min"]) or strength == int(view["strength_max"]))
	if tab == "pot":
		pot.refresh()
	else:
		topping.refresh()


func _on_tab_pressed(tab: String) -> void:
	shown_tab()   # 自動の判断を先に更新してから、手の選択を入れる
	manual_tab = tab
	refresh()
