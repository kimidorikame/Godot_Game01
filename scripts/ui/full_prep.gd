extends Control
class_name UiFullPrep
## 全面：仕込み（市場を出たあと）。寸法表 SCREENS_UI_LAYOUT §8。左側の会話・上部の数字・アイコンは出さない。
## 中央に「仕込み中」・「鍋の素 中・11杯・濃さ3」・進み具合の点3つ。点は市場を出たあとの3つのEvent
## （市場を出た → 仕込む → 鍋ができた）に対応し、クリック（Enter・Space）で next_event() を呼ぶたびに1つずつ点く。
## 列を読み終えたら「開店する」→ flow.advance_phase()。

signal advance_requested()

var session: PlaySession = null

@onready var _detail: Label = %Detail
@onready var _dots: Control = %Dots
@onready var _open: Button = %OpenButton


func _ready() -> void:
	_open.pressed.connect(_on_open_pressed)
	gui_input.connect(_on_gui_input)


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	var base := session.today_base()
	var pot := session.pot_view()
	var strength := int(pot["strength"]) if bool(pot["exists"]) else 3
	_detail.text = "鍋の素 %s・%d杯・濃さ%d" % [str(base["label"]).replace("仕込み", ""), int(base["servings"]), strength]
	var lit := lit_dots()
	for i in range(_dots.get_child_count()):
		(_dots.get_child(i) as ColorRect).color = get_theme_color(&"accent" if i < lit else &"line", &"UiPalette")
	_open.visible = session.flow.is_runner_done()


## 点いている点の数（0〜3）：市場（MARKET）から何Event進んだか。列を読み終えたら3。
func lit_dots() -> int:
	var runner := session.flow.runner
	if runner == null:
		return 0
	if runner.status == EventRunner.Status.DONE:
		return _dots.get_child_count()
	for i in range(runner.events.size()):
		var ev = runner.events[i]
		if ev is Dictionary and str(ev.get("type", "")) == "MARKET":
			return clampi(runner.index - i, 0, _dots.get_child_count())
	return 0


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance_requested.emit()
		accept_event()


func _on_open_pressed() -> void:
	if session.flow.is_runner_done():
		session.flow.advance_phase()
