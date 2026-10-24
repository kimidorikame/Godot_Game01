extends Control
class_name UiGameRoot
## 本番UIのルート（1280×720）。PlaySession を子に1つ持ち、changed で全体を描き直す。
## phase_entering で、表示だけの状態（スマホの開閉・タブ・鍋⇄トッピングの手動切り替え・ページ・市場の集計）を捨てる。
## 描き直しの最後に record_visible_event() を呼ぶ（会話ログ・既読。PLAY_SESSION_API §1）。
## 部品は bind_session(session) を1回、refresh() を描き直しのたびに受ける（引数なし）。
## 右の枠は同じ位置に重ねた画面のうち、いまの状態の1つだけを出す（_right_pane）。

@onready var session: PlaySession = %Session
@onready var left: UiLeftSide = %LeftSide
@onready var pane_morning: UiPaneMorning = %PaneMorning
@onready var pane_market: UiPaneMarket = %PaneMarket
@onready var pane_buy_meat: UiPaneBuyMeat = %PaneBuyMeat
@onready var pane_buy_shop: UiPaneBuyShop = %PaneBuyShop

## 市場の「この店で買ったもの」のUIだけの集計（plan Q10）。仕込みに入るたびに捨てる。
var tally := UiShopTally.new()


func _panes() -> Array:
	return [pane_morning, pane_market, pane_buy_meat, pane_buy_shop]


func _ready() -> void:
	left.bind_session(session)
	for pane in _panes():
		pane.bind_session(session)
	pane_market.tally = tally
	pane_buy_meat.tally = tally
	pane_buy_shop.tally = tally
	pane_buy_meat.advance_requested.connect(left.advance)
	session.phase_entering.connect(_on_phase_entering)
	session.changed.connect(_redraw)
	session.start()
	_redraw()


func _redraw() -> void:
	left.refresh()
	var shown := _right_pane()
	for pane in _panes():
		pane.visible = pane == shown
	if shown != null:
		shown.refresh()
	session.record_visible_event()


## いま右の枠に出す画面（無ければ null）。
func _right_pane() -> Control:
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
				_:
					return pane_market   # 市場を出たあと（仕込みの全面はUI準備B④）
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
	if phase == GameState.Phase.PREP:
		tally.clear()


## 会話を進めるキー：Enter・Space（左クリックは会話枠が受ける）。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
		left.advance()
		get_viewport().set_input_as_handled()
