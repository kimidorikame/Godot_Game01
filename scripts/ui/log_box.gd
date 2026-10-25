extends Panel
class_name UiLogBox
## 会話ログ（「ログ」のアイコンで開く）。会話枠が上へ伸びて、今日の会話の行を上から古い順に並べる（右の枠は置き換えない）。
## 中身は talk_log_entries()（今日の分）。話し手のいる行は「名前：本文」、地の文は薄い色。開いたときは一番下（新しい行）を見せる。
## 開閉は LeftSide が持つ（アイコンをもう一度・枠の外のクリックで閉じる）。この枠の中のクリックは何もしない。

var _shown_count := -1

@onready var _scroll: ScrollContainer = %LogScroll
@onready var _content: VBoxContainer = %LogContent


func _ready() -> void:
	gui_input.connect(_on_gui_input)


## 開くたびに作り直す（閉じているあいだに行が増えているので）。
func reset() -> void:
	_shown_count = -1


func refresh(session: PlaySession) -> void:
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


## 表示している行の数（テスト用）。
func row_count() -> int:
	return _content.get_child_count()


func _add(text: String, variation: StringName) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(630, 0)   # 右端の「スマホ」「ログ」のボタン（x 686〜）に重ならない幅
	_content.add_child(label)


func _scroll_to_end() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
