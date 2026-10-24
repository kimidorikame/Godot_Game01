extends Control
class_name UiGameRoot
## 本番UIのルート（1280×720）。PlaySession を子に1つ持ち、changed で全体を描き直す。
## phase_entering で、表示だけの状態（スマホの開閉・タブ・鍋⇄トッピングの手動切り替え・ページ）を捨てる。
## 描き直しの最後に record_visible_event() を呼ぶ（会話ログ・既読。PLAY_SESSION_API §1）。
## 部品は bind_session(session) を1回、refresh() を描き直しのたびに受ける（引数なし）。

@onready var session: PlaySession = %Session
@onready var left: UiLeftSide = %LeftSide


func _ready() -> void:
	left.bind_session(session)
	session.phase_entering.connect(_on_phase_entering)
	session.changed.connect(_redraw)
	session.start()
	_redraw()


func _redraw() -> void:
	left.refresh()
	session.record_visible_event()


func _on_phase_entering(_phase: int) -> void:
	left.reset_ui_state()


## 会話を進めるキー：Enter・Space（左クリックは会話枠が受ける）。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
		left.advance()
		get_viewport().set_input_as_handled()
