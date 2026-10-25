extends Control
class_name UiGameRoot
## 本番UIのルート（1280×720）。PlaySession を子に1つ持ち、changed で全体を描き直す。
## phase_entering で、表示だけの状態（スマホの開閉・タブ・鍋⇄トッピングの手動切り替え・ページ・市場の集計）を捨てる。
## 描き直しの最後に record_visible_event() を呼ぶ（会話ログ・既読。PLAY_SESSION_API §1）。
## 部品は bind_session(session) を1回、refresh() を描き直しのたびに受ける（引数なし）。
## 右の枠は同じ位置に重ねた画面のうち、いまの状態の1つだけを出す（_right_pane）。
## 全面（仕込み・結果・ゲームオーバー）が出ている間は、左側と右の枠を隠す（_full_screen）。
## スマホは右の枠（開店中は操作エリア）と入れ替わる（overlay。表示だけの状態）。会話ログは会話枠が上へ伸びる形（LeftSide が持つ。右の枠は触らない）。Day1の朝は前日が無いので、
## 右の枠を出さずにスマホから始める。朝の入力待ち「スマホを見る。」は、スマホを開くと終わる（開いている間の会話のクリックでも）。

@onready var session: PlaySession = %Session
@onready var left: UiLeftSide = %LeftSide
@onready var pane_morning: UiPaneMorning = %PaneMorning
@onready var pane_market: UiPaneMarket = %PaneMarket
@onready var pane_buy_meat: UiPaneBuyMeat = %PaneBuyMeat
@onready var pane_buy_shop: UiPaneBuyShop = %PaneBuyShop
@onready var pane_kaiten: UiPaneKaiten = %PaneKaiten
@onready var pane_close: UiPaneClose = %PaneClose
@onready var pane_phone: UiPanePhone = %PanePhone
@onready var right_pane: Control = %RightPane
@onready var full_prep: UiFullPrep = %FullPrep
@onready var full_result: UiFullResult = %FullResult
@onready var full_gameover: UiFullGameOver = %FullGameOver

## 市場の「この店で買ったもの」のUIだけの集計（plan Q10）。仕込みに入るたびに捨てる。
var tally := UiShopTally.new()
## 右の枠と入れ替えて出しているもの（""／"phone"）。表示だけの状態で、区切り（phase_entering）で捨てる。
var overlay := ""


func _panes() -> Array:
	return [pane_morning, pane_market, pane_buy_meat, pane_buy_shop, pane_kaiten, pane_close, pane_phone]


func _fulls() -> Array:
	return [full_prep, full_result, full_gameover]


func _ready() -> void:
	left.bind_session(session)
	for pane in _panes() + _fulls():
		pane.bind_session(session)
	pane_market.tally = tally
	pane_buy_meat.tally = tally
	pane_buy_shop.tally = tally
	pane_buy_meat.advance_requested.connect(left.advance)
	full_prep.advance_requested.connect(left.advance)
	left.phone_requested.connect(_on_phone_icon)
	left.wait_input_clicked.connect(_on_wait_input_clicked)
	pane_morning.phone_requested.connect(open_phone.bind("news"))
	pane_phone.close_requested.connect(close_overlay)
	pane_phone.dms_read.connect(left.refresh_phone_badge)
	session.phase_entering.connect(_on_phase_entering)
	session.changed.connect(_redraw)
	session.start()
	_redraw()


func _redraw() -> void:
	var full := _full_screen()
	for screen in _fulls():
		screen.visible = screen == full
	left.visible = full == null
	right_pane.visible = full == null
	if full != null:
		full.refresh()
	left.refresh()
	var shown := _right_pane() if full == null else null
	for pane in _panes():
		pane.visible = pane == shown
	if shown != null:
		shown.refresh()
	session.record_visible_event()
	left.refresh_log()


## いま出す全面（無ければ null）：市場を出たあとの仕込み・結果・ゲームオーバー。
func _full_screen() -> Control:
	match GameState.phase:
		GameState.Phase.PREP:
			return full_prep if _market_stage() == "after" else null
		GameState.Phase.RESULT:
			return full_result
		GameState.Phase.GAME_OVER:
			return full_gameover
	return null


## いま右の枠に出す画面（無ければ null）。スマホを開いていれば、それが右の枠（開店中は操作エリア）と入れ替わる。
func _right_pane() -> Control:
	if overlay == "phone":
		return pane_phone
	match GameState.phase:
		GameState.Phase.WAKE:
			return pane_morning
		GameState.Phase.PREP:
			match _market_stage():
				"in":
					if session.market_shop == "":
						return pane_market
					if session.market_shop == UiPaneBuyMeat.SHOP:
						return pane_buy_meat
					return pane_buy_shop
				"before":
					# 所持金が鍋の素に満たない日は、張記の画面を出さない（端材屋のクズ野菜ベースが自動で決まる）
					return pane_market if session.today_base()["scraps"] else pane_buy_meat
		GameState.Phase.OPEN:
			return pane_kaiten
		GameState.Phase.CLOSE:
			return pane_close
	return null


## 仕込み（PREP）の列のどこにいるか："before"（市場＝MARKET の前。段階の選択と語り）／"in"（市場の画面）／
## "after"（市場を出たあと）。段階を選ぶ前の列には MARKET が無い（段階を選ぶと列が組み直される）。
func _market_stage() -> String:
	if session.is_in_market():
		return "in"
	var runner := session.flow.runner
	if runner == null:
		return "before"
	for i in range(runner.events.size()):
		var ev = runner.events[i]
		if ev is Dictionary and str(ev.get("type", "")) == "MARKET":
			return "before" if runner.index < i else "after"
	return "before"


func _on_phase_entering(phase: int) -> void:
	left.reset_ui_state()
	pane_kaiten.reset_ui_state()
	full_result.reset_ui_state()
	pane_phone.reset_ui_state()
	overlay = ""
	if phase == GameState.Phase.WAKE and session.previous_day_record().is_empty():
		# Day1の朝（前日が無い）は、右の枠を出さずにスマホから始める（ニュース）
		overlay = "phone"
		pane_phone.tab = "news"
	if phase == GameState.Phase.PREP:
		tally.clear()


## スマホを開く（tab を開く）。朝の入力待ち「スマホを見る。」にいれば、開くと同時に入力を終える。
func open_phone(tab: String = "news") -> void:
	overlay = "phone"
	pane_phone.tab = tab
	if _waiting_phone_input():
		session.complete_input()   # changed で描き直す
	else:
		_redraw()


func close_overlay() -> void:
	overlay = ""
	pane_phone.reset_ui_state()
	_redraw()


## 朝の入力待ち「スマホを見る。」（WAIT_INPUT）にいて、入力を終えられるか。
func _waiting_phone_input() -> bool:
	return GameState.phase == GameState.Phase.WAKE and session.is_waiting_input() \
		and str(session.current_line().get("type", "")) == EventRunner.TYPE_WAIT_INPUT and session.can_complete_input()


func _on_phone_icon() -> void:
	if overlay == "phone":
		close_overlay()
	else:
		open_phone(pane_phone.tab)


## 入力待ちで会話を進めようとした：スマホを開いていれば入力を終える（開いていなければ何もしない＝「スマホを見る」を押す）。
func _on_wait_input_clicked() -> void:
	if overlay == "phone" and _waiting_phone_input():
		session.complete_input()


## 会話を進めるキー：Enter・Space（左クリックは会話枠が受ける）。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
		left.advance()
		get_viewport().set_input_as_handled()
