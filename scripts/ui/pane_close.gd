extends Panel
class_name UiPaneClose
## 右の枠：閉店（今夜の結果と修繕基金）。寸法表 SCREENS_UI_LAYOUT §7。
## 今夜の結果は tonight_result()（足りなかった杯数の内訳はCで足す。Bでは合計だけ）。
## 修繕基金は fund_view()：閉店の語りを読み終えるまでは押せない（現行どおり）。対象の行 → select_fund_target(id)、
## 「+10 積む」「+30 積む」→ contribute_fund(n)（steps[].can）。
## 「次の日へ」：閉店の列を読み終えたら → flow.advance_phase() を2回（CLOSE→NEXT_DAY→WAKE。最終日は RESULT）。

const GRADES := ["GREAT", "GOOD", "OK", "BAD"]

var session: PlaySession = null

@onready var _header: Control = %Header
@onready var _sales_value: Label = %SalesValue
@onready var _served_label: Label = %ServedLabel
@onready var _short_label: Label = %ShortLabel
@onready var _grades: Control = %Grades
@onready var _fund_box: Control = %FundBox
@onready var _targets: VBoxContainer = %Targets
@onready var _fund_info: Label = %FundInfo
@onready var _fund_wait: Label = %FundWait
@onready var _steps: HBoxContainer = %Steps
@onready var _next: Button = %NextButton


func _ready() -> void:
	_next.pressed.connect(_on_next_pressed)
	for i in range(_targets.get_child_count()):
		(_targets.get_child(i) as Button).pressed.connect(_on_target_pressed.bind(i))
	for i in range(_steps.get_child_count()):
		(_steps.get_child(i) as Button).pressed.connect(_on_step_pressed.bind(i))


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	UiParts.set_header(_header, "今夜の結果", "Day %d" % GameState.day_count)
	var result := session.tonight_result()
	_sales_value.text = "¥%d" % int(result["sales"])
	_served_label.text = "提供 %d杯 / 注文%d杯" % [int(result["served_cups"]), int(result["ordered_cups"])]
	# 足りなかった杯数と内訳（素材・鍋・断った。UI準備C③）
	_short_label.text = UiParts.unserved_text(int(result["unserved_cups"]), PlaySession.unserved_display(result))
	_short_label.visible = int(result["unserved_cups"]) > 0
	var counts: Dictionary = result["grades"]
	for grade in GRADES:
		(_grades.get_node(grade + "/Count") as Label).text = str(int(counts.get(grade, 0)))
	_refresh_fund()
	var done := session.flow.is_runner_done()
	_next.disabled = not done
	_next.text = "結果を見る" if GameState.is_final_day() else "次の日へ"


func _refresh_fund() -> void:
	_fund_box.visible = RepairFund.enabled()
	if not _fund_box.visible:
		return
	var view := session.fund_view()
	var available := bool(view["available"])
	_fund_wait.visible = not available
	_targets.visible = available
	_fund_info.visible = available
	_steps.visible = available
	if not available:
		return
	var targets: Array = view["targets"]
	for i in range(_targets.get_child_count()):
		var row: Button = _targets.get_child(i)
		row.visible = i < targets.size()
		if i >= targets.size():
			continue
		var target: Dictionary = targets[i]
		var state := "%d/%d" % [int(target["paid"]), int(target["price"])]
		if bool(target["repaired"]):
			state = "修繕済み"
		elif bool(target["locked"]):
			state = "未解放"
		(row.get_node("Mark") as Label).text = "▶" if bool(target["selected"]) else ""
		(row.get_node("Name") as Label).text = str(target["label"])
		(row.get_node("State") as Label).text = state
		var selected := bool(target["selected"])
		(row.get_node("Name") as Label).theme_type_variation = &"LabelAccentBody" if selected else &"LabelBody"
		(row.get_node("State") as Label).theme_type_variation = &"LabelGoodBody" if bool(target["repaired"]) \
			else (&"LabelAccentBody" if selected else &"LabelSub")
		row.disabled = bool(target["repaired"]) or bool(target["locked"])
	var info := "今夜 ¥%d／1晩の上限 ¥%d・今日積める上限 ¥%d" % [int(view["paid_tonight"]), int(view["nightly_max"]),
		int(view["max_contribution"])]
	if str(view["notice"]) != "":
		info = str(view["notice"])
	_fund_info.text = info
	var steps: Array = view["steps"]
	for i in range(_steps.get_child_count()):
		var button: Button = _steps.get_child(i)
		button.visible = i < steps.size()
		if i < steps.size():
			button.text = "+%d 積む" % int(steps[i]["amount"])
			button.disabled = not bool(steps[i]["can"])


func _on_target_pressed(index: int) -> void:
	var view := session.fund_view()
	if bool(view["available"]) and index < (view["targets"] as Array).size():
		session.select_fund_target(str(view["targets"][index]["id"]))


func _on_step_pressed(index: int) -> void:
	var view := session.fund_view()
	if bool(view["available"]) and index < (view["steps"] as Array).size() and bool(view["steps"][index]["can"]):
		session.contribute_fund(int(view["steps"][index]["amount"]))


## 「次の日へ」：CLOSE→NEXT_DAY→WAKE（最終日は RESULT）。積まずに押せば「積まない」。
func _on_next_pressed() -> void:
	if not session.flow.is_runner_done():
		return
	session.flow.advance_phase()
	if GameState.phase == GameState.Phase.NEXT_DAY:
		session.flow.advance_phase()
