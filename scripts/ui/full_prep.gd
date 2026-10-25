extends Control
class_name UiFullPrep
## 全面：仕込み（市場を出たあと）。寸法表 SCREENS_UI_LAYOUT §8。左側の会話・上部の数字・アイコンは出さない。
## 中央に「仕込み中」・「鍋の素 中・11杯・濃さ3」・進み具合の点3つ。点は市場を出たあとの3つのEvent
## （市場を出た → 仕込む → 鍋ができた）に対応する。クリックしなくても、約0.7秒ごとに次のEvent（next_event）へ進んで
## 1つずつ点く。画面をクリックすると、すぐ全部点く（Enter・Space は1つずつ）。列を読み終えたら「開店する」→ flow.advance_phase()。
## 既読スキップ（skip_read）は1回の操作でその場で最後まで進める（止まる条件はフェーズの切り替わりまで）ので、
## この画面を出している時点でスキップが進行中という状態は無い（待たせない）。

signal advance_requested()

## 点が1つ点くまでの秒数。
const STEP_SECONDS := 0.7

var session: PlaySession = null
## 自動で進める（テストでは false にして、tick で時間を送る）。
var auto_advance := true
var _elapsed := 0.0
var _last_lit := -1

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
	if lit != _last_lit:
		_last_lit = lit
		_elapsed = 0.0
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


func _process(delta: float) -> void:
	if auto_advance and visible and session != null:
		tick(delta)


## 時間を delta 秒進める。STEP_SECONDS たまるたびに次のEventへ（列を読み終えていれば何もしない）。
func tick(delta: float) -> void:
	if session == null or session.flow.is_runner_done():
		_elapsed = 0.0
		return
	_elapsed += delta
	if _elapsed >= STEP_SECONDS:
		_elapsed = 0.0
		advance_requested.emit()


## 全部の点をすぐ点ける（列を読み終えるまで次のEventへ進める）。
func light_all() -> void:
	var guard := 0
	while session != null and not session.flow.is_runner_done() and guard < 16:
		guard += 1
		advance_requested.emit()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		light_all()
		accept_event()


func _on_open_pressed() -> void:
	if session.flow.is_runner_done():
		session.flow.advance_phase()
