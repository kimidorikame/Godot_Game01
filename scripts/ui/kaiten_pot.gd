extends Control
class_name UiKaitenPot
## 開店の操作エリア：鍋の状態。寸法表 KAITEN_UI_LAYOUT §3。表示だけのタブで、open_pot()/close_pot() は呼ばない。
## 残り杯数・濃さ（1・5は注意色と注意文。0は「提供できません」）、だし（add_dashi）・水（add_water）。水を使えないときは説明を出さずにグレーにする。
## 濃さの目盛り（UI準備P-5）：「出せない（0）｜薄い（1）｜適正（2〜4）｜濃い（5）」の6区画と、今の位置の▲（塗りつぶしの棒はやめた）。
## だし・水のボタンの中は、押せるとき「濃さ3→5」「濃さ3→1」「残り8→10杯」（押した後の値。pot_view の after_dashi・after_water）。
## 押した後の濃さが適正の外（0・1・5）になるときは「濃さ3→5」を注意色にする（マウスを乗せた△と同じ考え。タッチ操作でも分かるように。UI準備P2）。
## ボタンにマウスを乗せている間は、目盛りに押した後の位置を△で出す（減点の側に入るなら注意色）。どれも表示だけ。
## 鍋が尽きた保留（is_shortage_pending）：「営業を続ける」→ resume_after_shortage()（残りが今の注文以上・濃さが0でないとき。
## UIの条件）、「閉店」→ close_shop()（can_close_now）。椀を作っている最中に鍋が足りず足せるものも無いときも「閉店」を出す。
## 客を全員さばいて列が終わったら「閉店する」→ flow.advance_phase()。

var session: PlaySession = null

@onready var _remain_value: Label = %RemainValue
@onready var _remain_max: Label = %RemainMax
@onready var _bar_fill: ColorRect = %BarFill
@onready var _strength_value: Label = %StrengthValue
@onready var _gauge: Control = %Gauge
@onready var _marker: Label = %Marker
@onready var _preview_mark: Label = %Preview
@onready var _strength_note: Label = %StrengthNote
@onready var _dashi: Button = %DashiButton
@onready var _water: Button = %WaterButton
@onready var _shortage: Control = %ShortageBox
@onready var _shortage_text: Label = %ShortageText
@onready var _resume: Button = %ResumeButton
@onready var _close: Button = %CloseButton
@onready var _close_night: Button = %CloseNightButton

const GAUGE_STEP := 65.0   # 目盛りの1区画の間隔（幅63＋隙間2）。区画 i は濃さ i（0〜5）
## 表示だけの状態：マウスを乗せているボタン（"dashi"／"water"／""）。目盛りに押した後の位置を出す。
var _hover := ""


func _ready() -> void:
	_dashi.pressed.connect(func(): session.add_dashi())
	_water.pressed.connect(func(): session.add_water())
	_resume.pressed.connect(_on_resume_pressed)
	_close.pressed.connect(func(): session.close_shop())
	_close_night.pressed.connect(func(): session.flow.advance_phase())
	_dashi.mouse_entered.connect(_set_hover.bind("dashi"))
	_dashi.mouse_exited.connect(_set_hover.bind(""))
	_water.mouse_entered.connect(_set_hover.bind("water"))
	_water.mouse_exited.connect(_set_hover.bind(""))


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
	# 濃さ5の文言は未決（寸法表 §7）。いまは濃さ1と同じ形の仮の文。濃さ0は提供できない（UI準備P-5で文を足した）。
	_strength_note.visible = extreme or strength <= int(pot["strength_floor"])
	_strength_note.text = "濃さ%dでは提供できません" % strength if strength <= int(pot["strength_floor"]) 		else "濃さ%dは評価が1段階下がります" % strength
	var can_touch := bool(pot["can_touch"])
	(_dashi.get_node("Count") as Label).text = "残り%d" % int(pot["dashi_units"])
	_dashi.disabled = not (can_touch and bool(pot["can_add_dashi"]) and not bool(pot["locked_until_water"]))
	(_water.get_node("Count") as Label).text = "残り%d" % int(pot["water_doses_left"])
	_water.disabled = not (can_touch and bool(pot["can_add_water"]) and not bool(pot["locked_until_dashi"]))
	# 押せるときは押した後の値（「濃さ3→5」）。押せないだしは固定の文、押せない水は説明を出さずにグレーにするだけ（寸法表 §3）
	var after_dashi: Dictionary = pot["after_dashi"]
	var after_water: Dictionary = pot["after_water"]
	(_dashi.get_node("Effect") as Label).text = "濃さ%d→%d" % [strength, int(after_dashi["strength"])] if not _dashi.disabled 		else "濃さ +%d" % GameState.DASHI_STRENGTH_DELTA
	(_water.get_node("Effect") as Label).text = "濃さ%d→%d" % [strength, int(after_water["strength"])]
	(_water.get_node("Effect2") as Label).text = "残り%d→%d杯" % [remaining, int(after_water["remaining"])]
	(_water.get_node("Effect") as Control).visible = not _water.disabled
	(_water.get_node("Effect2") as Control).visible = not _water.disabled
	_tint_effect(_dashi.get_node("Effect"), not _dashi.disabled, int(after_dashi["strength"]), pot)
	_tint_effect(_water.get_node("Effect"), not _water.disabled, int(after_water["strength"]), pot)
	_refresh_gauge(pot)
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


## 濃さの目盛り：区画の色（出せない＝濃い注意色・薄い／濃い＝薄い注意色・適正＝薄い良い色）、今の位置の▲、
## マウスを乗せたボタン（押せるときだけ）の押した後の位置の△（押した後が1・5・0なら注意色）。
func _refresh_gauge(pot: Dictionary) -> void:
	var warn := get_theme_color(&"warn", &"UiPalette")
	var good := get_theme_color(&"good", &"UiPalette")
	var lo := int(pot["strength_min"])
	var hi := int(pot["strength_max"])
	var floor_value := int(pot["strength_floor"])
	for i in range(floor_value, hi + 1):
		var cell: ColorRect = _gauge.get_node("Cell%d" % i)
		if i <= floor_value:
			cell.color = Color(warn, 0.35)
		elif i == lo or i == hi:
			cell.color = Color(warn, 0.16)
		else:
			cell.color = Color(good, 0.16)
	var strength := int(pot["strength"])
	_place_mark(_marker, strength, _mark_color(strength, pot))
	var preview := -999
	if _hover == "dashi" and not _dashi.disabled:
		preview = int((pot["after_dashi"] as Dictionary)["strength"])
	elif _hover == "water" and not _water.disabled:
		preview = int((pot["after_water"] as Dictionary)["strength"])
	_preview_mark.visible = preview != -999
	if _preview_mark.visible:
		_place_mark(_preview_mark, preview, _mark_color(preview, pot))
		_preview_mark.modulate = Color(1, 1, 1, 0.75)


## ボタンの中の「濃さ3→5」の色：押せて、押した後が適正の外（0・1・5）なら注意色。それ以外は型（LabelSub）の色のまま。
func _tint_effect(label: Label, enabled: bool, after: int, pot: Dictionary) -> void:
	if enabled and _outside_fit(after, pot):
		label.add_theme_color_override(&"font_color", get_theme_color(&"warn", &"UiPalette"))
	else:
		label.remove_theme_color_override(&"font_color")


## 適正の外か（0以下・1・5。提供できない・減点の側）。
func _outside_fit(value: int, pot: Dictionary) -> bool:
	return value <= int(pot["strength_floor"]) or value == int(pot["strength_min"]) or value == int(pot["strength_max"])


## 印の色：0・1・5（提供できない・減点の側）は注意色、2〜4は強調色。
func _mark_color(value: int, pot: Dictionary) -> Color:
	return get_theme_color(&"warn" if _outside_fit(value, pot) else &"accent", &"UiPalette")


## 印を、濃さ value の区画の真ん中の下に置く（範囲の外は端の区画）。
func _place_mark(mark: Label, value: int, color: Color) -> void:
	var i := clampi(value, 0, 5)
	mark.position.x = i * GAUGE_STEP + 31.5 - mark.size.x / 2.0
	mark.add_theme_color_override(&"font_color", color)
	mark.set_meta("value", i)


func _set_hover(which: String) -> void:
	_hover = which
	refresh()


## 「営業を続ける」を押せるか（UIの条件。resume_after_shortage() 自体は再チェックしない）：
## 残りが今の注文の杯数以上で、濃さが0でない。
func _can_resume(pot: Dictionary) -> bool:
	return session.is_shortage_pending() and int(pot["remaining"]) >= session.current_servings() and int(pot["strength"]) != 0


func _on_resume_pressed() -> void:
	if _can_resume(session.pot_view()):
		session.resume_after_shortage()
