extends Control
class_name UiLeftSide
## 本番UIの左側（共通）：上部の日・時間帯、所持金・評判、立ち絵枠、名前の札、会話枠、選択肢、
## スマホ・ログのアイコン、既読スキップ。鍋でもトッピングでも位置は動かさない（寸法表 KAITEN_UI_LAYOUT §1）。
## 会話を進めるクリックは、左の列のどこでも受ける（背面の ClickArea＝820×720。キャラ表示エリアと会話枠を含む）。スマホ・ログ・既読スキップの
## ボタン、右の枠は受けない（上に重なるボタンが先に受ける）。ログ（LogBox）は会話枠が上へ伸びた形で、開いているあいだのクリックは進めずに閉じる。
## ゲームの判定は持たない。PlaySession の問い（current_line・current_choices・day_info など）を読んで描き、
## 会話を進める操作だけを PlaySession へ送る。親（game_root）が bind_session() を1回、refresh() を changed のたびに呼ぶ。

signal phone_requested()
## 入力待ち（WAIT_INPUT。朝の「スマホを見る。」）で会話を進めようとした。ルートが、スマホを開いていれば入力を終える。
signal wait_input_clicked()

const CHARS_PER_LINE := 30    # 会話枠：1行30字（全角。半角は0.5字）
const LINES_PER_PAGE := 3     # ×3行。入りきらない文は枠内でページ送り
const SLOT_SHORT := { "宵の口": "宵", "夜半": "夜半", "明け方": "明" }
const SILENT_TYPES := ["ADD_ITEM"]   # 画面に出す文が無いEvent（会話枠が空になる）。会話を進めるときに続けて進める
const SUMMARY_LINE := "昨夜の成績を確かめた。"   # part:"day_summary" の行は、会話枠にはこの1行だけを出す（中身は右の枠）

var session: PlaySession = null
var _pages: Array = []
var _page := 0
var _key := ""
## 直前に出していた行の本文。列が終わって現在の行が無くなったとき、これを残す（区切りで捨てる）。
var _last_text := ""
## 会話ログ（LogBox）を開いているか。表示だけの状態で、区切り（phase_entering）で閉じる。
var _log_open := false

@onready var _day_label: Label = %DayLabel
@onready var _screen_name: Label = %ScreenName
@onready var _time_gauge: Control = %TimeGauge
@onready var _money_label: Label = %MoneyLabel
@onready var _reputation_label: Label = %ReputationLabel
@onready var _portrait: Control = %Portrait
@onready var _choices: VBoxContainer = %Choices
@onready var _phone_icon: Button = %PhoneIcon
@onready var _phone_badge: Label = %PhoneBadge
@onready var _log_icon: Button = %LogIcon
@onready var _name_plate: Control = %NamePlate
@onready var _name_label: Label = %NameLabel
@onready var _dialogue_box: Control = %DialogueBox
@onready var _dialogue_text: Label = %DialogueText
@onready var _page_mark: Label = %PageMark
@onready var _skip_button: Button = %SkipButton
@onready var _click_area: Control = %ClickArea
@onready var _log_box: UiLogBox = %LogBox


func _ready() -> void:
	_phone_icon.pressed.connect(func(): phone_requested.emit())
	_log_icon.pressed.connect(toggle_log)
	_skip_button.pressed.connect(_on_skip_pressed)
	_dialogue_box.gui_input.connect(_on_dialogue_input)
	_click_area.gui_input.connect(_on_dialogue_input)


func bind_session(s: PlaySession) -> void:
	session = s


## 会話の文を、30字×3行のページに分ける（全角1字＝1、半角＝0.5。\n は改行）。1ページの行は3つまで。
## 文字の幅はフォントに依らず数える（24px の全角30字＝720px）ので、ヘッドレスのテストでも同じに動く。
static func paginate(text: String, chars_per_line: int = CHARS_PER_LINE, lines_per_page: int = LINES_PER_PAGE) -> Array:
	var lines: Array = []
	for raw in text.split("\n"):
		var current := ""
		var width := 0.0
		for ch in raw:
			var w := 0.5 if ch.unicode_at(0) < 0x100 else 1.0
			if width + w > float(chars_per_line):
				lines.append(current)
				current = ""
				width = 0.0
			current += ch
			width += w
		lines.append(current)
	var pages: Array = []
	var i := 0
	while i < lines.size():
		pages.append("\n".join(lines.slice(i, i + lines_per_page)))
		i += lines_per_page
	if pages.is_empty():
		pages.append("")
	return pages


## 会話枠に出す内容：{ speaker（客id。地の文は ""）, text }。聞き直しの再表示があるときはそれを優先する。
func _display() -> Dictionary:
	if session.reask_customer_id != "" and session.adjust_customer_id() == session.reask_customer_id \
			and not session.reask_lines.is_empty():
		var lines: Array = []
		for l in session.reask_lines:
			lines.append(str(l))
		return { "speaker": session.reask_customer_id, "text": "\n".join(lines) }
	var line := session.current_line()
	if line.is_empty():
		# 列を読み終えた画面（閉店など）：会話枠を空にせず、最後に出した行を残す（話し手の枠は出さない）
		return { "speaker": "", "text": _last_text, "retained": true }
	var text := str(line.get("text", ""))
	if str(line.get("part", "")) == "day_summary":
		text = SUMMARY_LINE
	_last_text = text
	return { "speaker": str(line.get("speaker", "")), "text": text }


## スマホのボタンの未読の印（SNSの未読の●と数）。数の取り方は SNS タブ内と同じ（session.dm_unread_count）。
## SNS タブを表示して読んだ扱いになったとき（pane_phone の dms_read）にも、親が呼ぶ。
func refresh_phone_badge() -> void:
	if session == null:
		return
	var unread := session.dm_unread_count()
	_phone_badge.text = "●%d" % unread if unread > 0 else ""


func refresh() -> void:
	if session == null:
		return
	refresh_phone_badge()
	var info := session.day_info()
	_day_label.text = "Day %d" % int(info["day"])
	_money_label.text = "¥%d" % int(info["money"])
	_reputation_label.text = "評判 %d・客足 %s" % [int(info["reputation"]), UiLabels.demand_word(int(info["reputation"]))]
	_refresh_time(info)
	var shown := _display()
	var speaker := str(shown["speaker"])
	_portrait.visible = speaker != "" or _customer_present(info)
	_name_plate.visible = speaker != ""
	_name_label.text = session.log_speaker(speaker) if speaker != "" else ""
	# 残している行は、列の位置が進んでも同じ行なので、ページを戻さない
	var run_index := -2 if shown.has("retained") else (session.flow.runner.index if session.flow.runner != null else -1)
	var key := "%d|%d|%s" % [int(info["phase"]), run_index, str(shown["text"])]
	if key != _key:
		_key = key
		_pages = paginate(str(shown["text"]))
		_page = 0
	_show_page()
	_refresh_choices()
	_skip_button.disabled = not session.can_skip_step()
	# 既読スキップは会話枠の右下に重なる。押せないあいだはクリックを受けず、下の会話枠に通す（押せない枠が会話のクリックを塞がない）
	_skip_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if _skip_button.disabled else Control.MOUSE_FILTER_STOP
	_log_box.visible = _log_open
	if _log_open:
		_log_box.refresh(session)


## 開店中、いま客がそこにいるか（立ち絵の枠を出す）。語りの行でも、客が店にいる間は枠を残す。
func _customer_present(info: Dictionary) -> bool:
	return str(info["phase_name"]) == "OPEN" and session.open != null and session.open.current_customer() != null


func _show_page() -> void:
	_dialogue_text.text = str(_pages[_page])
	var more := _page < _pages.size() - 1
	_page_mark.text = "▼続く" if more else "▼"
	_page_mark.visible = _dialogue_text.text != ""


## 上部：開店中だけ時間帯ゲージ（宵／夜半／明）、それ以外は画面名（朝／市場／閉店）。
func _refresh_time(info: Dictionary) -> void:
	var in_open := str(info["phase_name"]) == "OPEN" and session.open != null
	_time_gauge.visible = in_open
	_screen_name.visible = not in_open
	if in_open:
		var schedule: Array = session.open.schedule
		for i in range(_time_gauge.get_child_count()):
			var slot_ui: Control = _time_gauge.get_child(i)
			slot_ui.visible = i < schedule.size()
			if i < schedule.size():
				var name_text := str(schedule[i].get("name", ""))
				var on := i == int(info["slot_index"])
				var name_node: Label = slot_ui.get_node("Name")
				name_node.text = str(SLOT_SHORT.get(name_text, name_text))
				name_node.theme_type_variation = &"" if on else &"LabelDim"
				(slot_ui.get_node("Bar") as ColorRect).color = get_theme_color(&"accent", &"UiPalette") if on \
					else get_theme_color(&"line", &"UiPalette")
	else:
		match str(info["phase_name"]):
			"WAKE":
				_screen_name.text = "朝"
			"PREP":
				_screen_name.text = "市場"
			"CLOSE":
				_screen_name.text = "閉店"
			_:
				_screen_name.text = ""


func _refresh_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	var data := session.current_choices()
	if data.is_empty():
		return
	for option in data["options"]:
		var button := Button.new()
		button.theme_type_variation = &"ButtonChoice"
		button.text = str(option["label"])
		button.custom_minimum_size = Vector2(400, 52)
		button.focus_mode = Control.FOCUS_NONE   # Space・Enter は会話を進めるのに使う（ボタンに取られない）
		button.pressed.connect(session.choose_story_option.bind(str(data["choice_id"]), str(option["id"])))
		_choices.add_child(button)


## 会話を進める（会話枠のクリック・Enter・Space）。ページが残っていれば先にページを送り、
## 残っていなければ PlaySession の次のEventへ（can_next_event のとき）。入力待ち（WAIT_INPUT）では
## wait_input_clicked を出すだけ（入力を終えるかはルートが決める）。
func advance() -> void:
	if session == null:
		return
	if _page < _pages.size() - 1:
		_page += 1
		_show_page()
		return
	if session.is_waiting_input() and str(session.current_line().get("type", "")) == EventRunner.TYPE_WAIT_INPUT:
		wait_input_clicked.emit()
		return
	if session.can_next_event():
		session.next_event()
		_skip_silent_events()


## 画面に出す文が無い、進行だけのEvent（初日セットの受け取り＝ADD_ITEM）か。会話枠が空のまま何度もクリックさせない。
func _is_silent(line: Dictionary) -> bool:
	return SILENT_TYPES.has(str(line.get("type", ""))) and str(line.get("text", "")) == ""


## 会話を進めたあと、現在のEventが画面に出す文の無いものなら、続けて進める（Eventは1つずつ順に反映される。
## 進める条件はクリックと同じ can_next_event）。出す文のあるEventか、選択・入力待ちで止まる。
func _skip_silent_events() -> void:
	var guard := 0
	while guard < 64 and session.can_next_event() and _is_silent(session.current_line()):
		guard += 1
		session.next_event()


## 区切り（phase_entering）で、表示だけの状態を捨てる。
func reset_ui_state() -> void:
	_log_open = false
	_log_box.visible = false
	_log_box.reset()
	_key = ""
	_page = 0
	_last_text = ""


func _on_skip_pressed() -> void:
	if session != null:
		session.skip_read()


## 左の列のクリック（キャラ表示エリア・会話枠）：会話を進める。ログを開いているあいだは、進めずにログを閉じる。
func _on_dialogue_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _log_open:
			close_log()
		else:
			advance()
		accept_event()


## 描き直しの最後に（会話ログへ今の行を記録したあと）、開いているログへ新しい行を足す。
func refresh_log() -> void:
	if _log_open and session != null:
		_log_box.refresh(session)


func is_log_open() -> bool:
	return _log_open


## 「ログ」のアイコン：開く／閉じる（もう一度押すと閉じる）。右の枠は触らない。
func toggle_log() -> void:
	if _log_open:
		close_log()
		return
	_log_open = true
	_log_box.reset()
	refresh()


func close_log() -> void:
	_log_open = false
	refresh()
