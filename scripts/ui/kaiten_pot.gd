extends Control
class_name UiKaitenPot
## 開店の操作エリア：鍋の状態。寸法表 KAITEN_UI_LAYOUT §3。表示だけのタブで、open_pot()/close_pot() は呼ばない。
## 残り杯数・濃さ（1・5は注意色と注意文）、だし（add_dashi）・水（add_water）。水を使えないときは説明を出さずにグレーにする。
## 鍋が尽きた保留（is_shortage_pending）：「営業を続ける」→ resume_after_shortage()（残りが今の注文以上・濃さが0でないとき。
## UIの条件）、「閉店」→ close_shop()（can_close_now）。椀を作っている最中に鍋が足りず足せるものも無いときも「閉店」を出す。
## 客を全員さばいて列が終わったら「閉店する」→ flow.advance_phase()。

var session: PlaySession = null

@onready var _remain_value: Label = %RemainValue
@onready var _remain_max: Label = %RemainMax
@onready var _bar_fill: ColorRect = %BarFill
@onready var _strength_value: Label = %StrengthValue
@onready var _scale: Control = %Scale
@onready var _strength_note: Label = %StrengthNote
@onready var _dashi: Button = %DashiButton
@onready var _water: Button = %WaterButton
@onready var _shortage: Control = %ShortageBox
@onready var _shortage_text: Label = %ShortageText
@onready var _resume: Button = %ResumeButton
@onready var _close: Button = %CloseButton
@onready var _close_night: Button = %CloseNightButton


func _ready() -> void:
	_dashi.pressed.connect(func(): session.add_dashi())
	_water.pressed.connect(func(): session.add_water())
	_resume.pressed.connect(_on_resume_pressed)
	_close.pressed.connect(func(): session.close_shop())
	_close_night.pressed.connect(func(): session.flow.advance_phase())


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	var pot := session.pot_view()
	if not bool(pot["exists"]):
		return
	var remaining := int(pot["remaining"])
	var capacity := maxi(int(pot["capacity"]), 1)
	_remain_value.text = "%d杯" % remaining
	_remain_max.text = "/%d" % capacity
	_bar_fill.size.x = 388.0 * clampf(float(remaining) / float(capacity), 0.0, 1.0)
	var strength := int(pot["strength"])
	var extreme := strength == int(pot["strength_min"]) or strength == int(pot["strength_max"])
	_strength_value.text = str(strength)
	_strength_value.theme_type_variation = &"LabelPriceWarn" if extreme or strength <= 0 else &"LabelPrice"
	for i in range(_scale.get_child_count()):
		(_scale.get_child(i) as ColorRect).color = (get_theme_color(&"warn" if extreme else &"accent", &"UiPalette") if i < strength
			else get_theme_color(&"line", &"UiPalette"))
	# 濃さ5の文言は未決（寸法表 §7）。いまは濃さ1と同じ形の仮の文。
	_strength_note.visible = extreme
	_strength_note.text = "濃さ%dは評価が1段階下がります" % strength
	var can_touch := bool(pot["can_touch"])
	(_dashi.get_node("Count") as Label).text = "残り%d" % int(pot["dashi_units"])
	_dashi.disabled = not (can_touch and bool(pot["can_add_dashi"]) and not bool(pot["locked_until_water"]))
	(_water.get_node("Count") as Label).text = "残り%d" % int(pot["water_doses_left"])
	_water.disabled = not (can_touch and bool(pot["can_add_water"]) and not bool(pot["locked_until_dashi"]))
	# 水を使えないときは、説明を出さずにグレーにするだけ（寸法表 §3）
	(_water.get_node("Effect") as Control).visible = not _water.disabled
	(_water.get_node("Effect2") as Control).visible = not _water.disabled
	var pending := session.is_shortage_pending()
	var can_close := session.can_close_now()
	_shortage.visible = pending or can_close
	if pending:
		_shortage_text.text = "鍋が尽きた。だしや水で作り直して営業を続けるか、ここで閉店する。"
	else:
		_shortage_text.text = "鍋が足りない。足せるものも、もう無い。"
	_resume.visible = pending
	_resume.disabled = not _can_resume(pot)
	_close.disabled = not can_close
	_close_night.visible = GameState.phase == GameState.Phase.OPEN and session.flow.is_runner_done() \
		and not session.flow.is_advance_blocked()


## 「営業を続ける」を押せるか（UIの条件。resume_after_shortage() 自体は再チェックしない）：
## 残りが今の注文の杯数以上で、濃さが0でない。
func _can_resume(pot: Dictionary) -> bool:
	return session.is_shortage_pending() and int(pot["remaining"]) >= session.current_servings() and int(pot["strength"]) != 0


func _on_resume_pressed() -> void:
	if _can_resume(session.pot_view()):
		session.resume_after_shortage()
