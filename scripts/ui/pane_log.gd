extends Panel
class_name UiPaneLog
## 右の枠：会話ログ（ログのアイコンで開く。plan Q4：スマホのタブには入れない）。寸法表に無いので、右の枠の共通の形
## （見出しの帯・中身の余白14・一番下の補助ボタン）で出す。中身は talk_log_entries()（今日の分、上から古い順）。
## 話し手のいる行は「名前：本文」、地の文は薄い色。開いたときは一番下（新しい行）を見せる。

signal close_requested()

var session: PlaySession = null
var _shown_count := -1

@onready var _header: Control = %Header
@onready var _scroll: ScrollContainer = %Scroll
@onready var _content: VBoxContainer = %Content
@onready var _close: Button = %CloseButton


func _ready() -> void:
	_close.pressed.connect(func(): close_requested.emit())


func bind_session(s: PlaySession) -> void:
	session = s


func reset_ui_state() -> void:
	_shown_count = -1


func refresh() -> void:
	if session == null:
		return
	UiParts.set_header(_header, "会話ログ", "Day %d" % GameState.day_count)
	var entries := session.talk_log_entries()
	if entries.size() == _shown_count:
		return
	_shown_count = entries.size()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		_add("まだ何もない", &"LabelDim")
	for entry in entries:
		var speaker := str(entry.get("speaker", ""))
		if speaker != "":
			_add("%s：%s" % [speaker, str(entry["text"])], &"LabelPhoneBody")
		else:
			_add(str(entry["text"]), &"LabelLogNarration")
	_scroll_to_end.call_deferred()


func _add(text: String, variation: StringName) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(380, 0)
	_content.add_child(label)


func _scroll_to_end() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
