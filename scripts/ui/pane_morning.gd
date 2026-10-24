extends Panel
class_name UiPaneMorning
## 右の枠：朝（昨夜の成績）。寸法表 SCREENS_UI_LAYOUT §2。
## 中身は previous_day_record()（日次ログの1日分）・morning_cost()・budget() を読むだけ。
## 一番下の主ボタンは、朝の語りの途中は「スマホを見る」（入力待ち「スマホを見る。」なら complete_input() も呼ぶ）、
## 朝の列を読み終えたら「市場へ」（flow.advance_phase()）。
## Day1の朝は前日が無いので、成績の箱を出さない（スマホから始める。スマホはUI準備B⑤）。

signal phone_requested()

const GRADES := ["GREAT", "GOOD", "OK", "BAD"]

var session: PlaySession = null

@onready var _header: Control = %Header
@onready var _record: Control = %RecordBoxes
@onready var _no_record: Label = %NoRecord
@onready var _sales_value: Label = %SalesValue
@onready var _served_label: Label = %ServedLabel
@onready var _grades: Control = %Grades
@onready var _short_label: Label = %ShortLabel
@onready var _spoil_label: Label = %SpoilLabel
@onready var _reputation_label: Label = %ReputationLabel
@onready var _cost_label: Label = %CostLabel
@onready var _usable_label: Label = %UsableLabel
@onready var _primary: Button = %PrimaryButton


func _ready() -> void:
	_primary.pressed.connect(_on_primary_pressed)


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	var rec := session.previous_day_record()
	_record.visible = not rec.is_empty()
	_no_record.visible = rec.is_empty()
	if rec.is_empty():
		UiParts.set_header(_header, "朝", "Day %d" % GameState.day_count)
	else:
		UiParts.set_header(_header, "昨夜の成績", "Day %d" % int(rec["day"]))
		_sales_value.text = "¥%d" % int(rec.get("sale_total", 0))
		_served_label.text = "提供 %d杯 / 注文%d杯" % [int(rec.get("served_cups", 0)), int(rec.get("planned_cups", 0))]
		var counts: Dictionary = rec.get("quality_counts", {})
		for grade in GRADES:
			(_grades.get_node(grade + "/Count") as Label).text = str(int(counts.get(grade, 0)))
		# 足りなかった杯数の内訳（素材・鍋・断った）はCで足す。Bでは未提供の合計だけ。
		_short_label.text = "足りなかった %d杯" % int(rec.get("unserved_cups", 0))
		_spoil_label.text = _spoil_text(rec)
		_reputation_label.text = "評判 %d → %d" % [int(rec.get("opening_reputation", 0)), int(rec.get("closing_reputation", 0))]
	_cost_label.text = "今朝の運営費 −¥%d" % session.morning_cost()
	_usable_label.text = "使える現金 ¥%d" % int(session.budget()["usable"])
	if session.flow.is_runner_done():
		_primary.text = "市場へ"
		_primary.disabled = session.flow.is_advance_blocked()
	else:
		_primary.text = "スマホを見る"
		_primary.disabled = false


## 廃棄の品目と個数と額（前日の仕込みで捨てた分）。
static func _spoil_text(rec: Dictionary) -> String:
	var items: Dictionary = rec.get("spoiled_items", {})
	if items.is_empty():
		return "廃棄 なし"
	var parts: Array = []
	for item in items:
		parts.append("%s%d個" % [Ingredients.name_for(str(item)), int((items[item] as Dictionary).get("count", 0))])
	return "廃棄 %s（¥%d）" % ["・".join(parts), int(rec.get("spoiled_value", 0))]


func _on_primary_pressed() -> void:
	if session == null:
		return
	if session.flow.is_runner_done():
		session.flow.advance_phase()
		return
	if session.is_waiting_input() and session.can_complete_input():
		session.complete_input()
	phone_requested.emit()
