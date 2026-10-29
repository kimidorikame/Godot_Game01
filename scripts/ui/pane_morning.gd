extends Panel
class_name UiPaneMorning
## 右の枠：朝（昨夜の成績）。寸法表 SCREENS_UI_LAYOUT §2。
## 中身は previous_day_record()（日次ログの1日分）・operating_cost_pending()・budget() を読むだけ。
## 一番下の主ボタンは「市場へ」だけ（flow.advance_phase()）。朝の列を読み終えるまでは押せない。
## 「スマホを見る」ボタンは無い（ニュースとDMはスマホのボタンで読む。朝の会話枠にも出さない。UI準備D）。
## Day1の朝は前日が無いので、成績の箱を出さない（スマホから始める。スマホはUI準備B⑤）。

const GRADES := ["GREAT", "GOOD", "OK", "BAD"]

var session: PlaySession = null

@onready var _header: Control = %Header
@onready var _record: Control = %RecordBoxes
@onready var _no_record: Label = %NoRecord
@onready var _sales_value: Label = %SalesValue
@onready var _tip_label: Label = %TipLabel
@onready var _served_label: Label = %ServedLabel
@onready var _grades: Control = %Grades
@onready var _short_label: Label = %ShortLabel
@onready var _spoil_label: Label = %SpoilLabel
@onready var _balance_caption: Label = %Caption
@onready var _purchase_label: Label = %PurchaseLabel
@onready var _balance_label: Label = %BalanceLabel
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
		_tip_label.visible = int(rec.get("tips", 0)) > 0
		_tip_label.text = "うちチップ ¥%d" % int(rec.get("tips", 0))
		_served_label.text = "提供 %d杯 / 注文%d杯" % [int(rec.get("served_cups", 0)), int(rec.get("planned_cups", 0))]
		var counts: Dictionary = rec.get("quality_counts", {})
		for grade in GRADES:
			(_grades.get_node(grade + "/Count") as Label).text = str(int(counts.get(grade, 0)))
		# 足りなかった杯数と内訳（素材・鍋・断った。UI準備C③）。内訳が無い古い記録は合計だけ
		_short_label.text = UiParts.unserved_text(int(rec.get("unserved_cups", 0)), PlaySession.unserved_display(rec))
		_spoil_label.text = _spoil_text(rec)
		# 昨日の仕入れと収支（UI準備I）：収支＝売上（チップ込み）− 仕入れ − 運営費。Day1は場所代・水道代も引くので、別に添える
		var spend: Dictionary = rec.get("spend_by_category", {})
		var purchases := int(rec.get("purchases", PlaySession.purchases_from(spend)))
		var balance := int(rec.get("sale_total", 0)) - purchases - int(spend.get("daily_cost", 0))
		var bills := int(spend.get("rent", 0)) + int(spend.get("water", 0))
		_purchase_label.text = "昨日の仕入れ ¥%d" % purchases
		_balance_label.text = "昨日の収支 %s¥%d（売上 − 仕入れ − 運営費）" % ["+" if balance >= 0 else "−", absi(balance)]
		_balance_caption.text = "昨日のお金の出入り%s" % ("　（ほかに場所代・水道代 ¥%d）" % bills if bills > 0 else "")
		_reputation_label.text = "評判 %d → %d" % [int(rec.get("opening_reputation", 0)), int(rec.get("closing_reputation", 0))]
	_cost_label.text = "水と炭（運営費） ¥%d　市場を出るときに払う" % session.operating_cost_pending() if session.operating_cost_pending() > 0 \
		else "水と炭（運営費） −¥%d　払った" % session.morning_cost()
	_usable_label.text = "使える現金 ¥%d" % int(session.budget()["usable"])
	_primary.text = "市場へ"
	_primary.disabled = not session.flow.is_runner_done() or session.flow.is_advance_blocked()


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
	if session != null and session.flow.is_runner_done():
		session.flow.advance_phase()
