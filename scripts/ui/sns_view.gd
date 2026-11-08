extends RefCounted
class_name UiSnsView
## スマホのSNSタブの中身（UI準備R・試しの実装）：上の切り替え「タイムライン｜DM」・タイムライン・DMの一覧・DMのやりとり。
## 表示を作るだけ（開いている画面の状態は UiPanePhone、中身は PlaySession の sns_timeline・dm_threads・contact_card）。
## アカウントの持ち主・本当の意味（書き手用のデータ）は出さない。いいね・拡散・表示回数などの数字も出さない。

const WIDTH := 388.0
## 投稿の幅（右端の縦のスクロールバーに時刻が重ならないよう、一覧の幅より少し狭く）。
const POST_WIDTH := 376.0
const ICON := 36.0
const REPLY_INDENT := 40.0


## 上の切り替え「タイムライン｜DM」。DMに未読があれば、DMの横に●と数。
static func add_switch(content: VBoxContainer, mode: String, dm_unread: int, on_timeline: Callable, on_dm: Callable) -> void:
	var bar := HBoxContainer.new()
	bar.name = "SnsSwitch"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	content.add_child(bar)
	for pair in [["SwitchTimeline", "タイムライン", "timeline", on_timeline], ["SwitchDm", "DM", "dm", on_dm]]:
		var button := Button.new()
		button.name = str(pair[0])
		button.text = str(pair[1])
		button.theme_type_variation = &"ButtonCategoryOn" if mode == str(pair[2]) else &"ButtonCategory"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(120, 32)
		button.pressed.connect(pair[3])
		bar.add_child(button)
	var mark := Label.new()
	mark.name = "DmUnread"
	mark.text = "●%d" % dm_unread if dm_unread > 0 else ""
	mark.theme_type_variation = &"LabelWarnSmall"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.custom_minimum_size = Vector2(36, 0)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(mark)


## アイコン（仮）：色と1文字（または記号）の四角。
static func make_icon(color: Color, text: String, size: float = ICON) -> Panel:
	var icon := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	icon.add_theme_stylebox_override("panel", style)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(size, size)
	icon.size = Vector2(size, size)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"LabelShop"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.add_child(label)
	return icon


static func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## タイムライン：日の区切り（「Day4」）→その日の投稿（新しい時刻が上）。返信は元の投稿のすぐ下に字下げして古い順。
## fresh＝このスマホを開いた時点で未読だった投稿の id（左に注意色の線）。
static func fill_timeline(content: VBoxContainer, sections: Array, fresh: Dictionary, palette: Control) -> void:
	if sections.is_empty():
		var empty := _label("まだ投稿はありません", &"LabelDim")
		empty.custom_minimum_size = Vector2(380, 0)
		content.add_child(empty)
		return
	for section in sections:
		var head := _label(Calendar.label(int(section["day"])), &"LabelSub")
		head.name = "Day_%d" % int(section["day"])
		content.add_child(head)
		for item in section["posts"]:
			_add_post(content, item, 0.0, fresh.has(str(item["id"])), palette)
			for reply in item["replies"]:
				_add_post(content, reply, REPLY_INDENT, fresh.has(str(reply["id"])), palette)
			var line := ColorRect.new()
			line.color = palette.get_theme_color(&"line", &"UiPalette")
			line.custom_minimum_size = Vector2(WIDTH, 1)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(line)


## 投稿1件：アイコン・表示名（入りきらなければ「…」）・ID（@〜）・時刻・本文（折り返す）・写真（任意。仮の枠に説明の文字）。
static func _add_post(content: VBoxContainer, item: Dictionary, indent: float, fresh: bool, palette: Control) -> void:
	var account: Dictionary = item.get("account_data", {})
	var icon_data: Dictionary = account.get("icon", {})
	var row := HBoxContainer.new()
	row.name = "Post_%s" % str(item["id"])
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	if indent > 0.0:
		var spacer := Control.new()   # 返信の字下げ
		spacer.custom_minimum_size = Vector2(indent - 8.0, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)
	var bar := ColorRect.new()
	bar.name = "UnreadBar"
	bar.color = palette.get_theme_color(&"warn", &"UiPalette") if fresh else Color(0, 0, 0, 0)
	bar.custom_minimum_size = Vector2(3, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var icon_size := ICON if indent == 0.0 else 28.0
	var icon_box := VBoxContainer.new()
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(make_icon(Color.html(str(icon_data.get("color", "#555555"))), str(icon_data.get("text", "?")), icon_size))
	row.add_child(icon_box)
	var width := POST_WIDTH - 3.0 - indent - icon_size - 16.0
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 2)
	body.custom_minimum_size = Vector2(width, 0)
	row.add_child(body)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	head.custom_minimum_size = Vector2(width, 0)
	body.add_child(head)
	var name_label := _label(str(account.get("name", "")), &"LabelPhoneHeadline")
	name_label.name = "Name"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(24, 0)
	head.add_child(name_label)
	var handle := _label(str(account.get("handle", "")), &"LabelCaption")
	handle.name = "Handle"
	head.add_child(handle)
	var time := _label(Calendar.stamp(int(item["day"]), str(item["time"])), &"LabelCaption")
	time.name = "Time"
	head.add_child(time)
	var text := _label(str(item["text"]), &"LabelPhoneBody")
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.custom_minimum_size = Vector2(width, 0)
	body.add_child(text)
	if str(item.get("photo", "")) != "":
		var photo := Panel.new()
		photo.name = "Photo"
		photo.theme_type_variation = &"PanelSlotEmpty"
		photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		photo.custom_minimum_size = Vector2(width, 72)
		body.add_child(photo)
		var caption := _label("［写真：%s］" % str(item["photo"]), &"LabelCaption")
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		photo.add_child(caption)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)


## DMの一覧（相手ごと。最後のメッセージが新しい相手が上）：アイコン（仮）・名前・最後のメッセージの1行目・日時・未読の●。押すとやりとりへ。
static func fill_dm_list(content: VBoxContainer, threads: Array, on_open: Callable, palette: Control) -> void:
	if threads.is_empty():
		var empty := _label("まだメッセージはありません", &"LabelDim")
		empty.custom_minimum_size = Vector2(380, 0)
		content.add_child(empty)
		return
	for thread in threads:
		var row := Button.new()
		row.name = "DmRow_%s" % str(thread["key"]).replace(":", "_")
		row.theme_type_variation = &"ButtonRow"
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(WIDTH, 60)
		content.add_child(row)
		var name := str(thread["name"])
		var icon := make_icon(palette.get_theme_color(&"portrait", &"UiPalette"), name.left(1))
		icon.position = Vector2(10, 12)
		row.add_child(icon)
		var name_label := _label(name, &"LabelShop")
		name_label.name = "Name"
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.position = Vector2(56, 5)
		name_label.size = Vector2(210, 26)
		row.add_child(name_label)
		var last: Dictionary = thread["last"]
		var time := _label(Calendar.stamp(int(last["day"]), str(last["time"])), &"LabelCaption")
		time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time.position = Vector2(266, 8)
		time.size = Vector2(112, 20)
		row.add_child(time)
		var preview := _label(str(last["text"]).get_slice("\n", 0), &"LabelCaption")
		preview.name = "Preview"
		preview.clip_text = true
		preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		preview.position = Vector2(56, 32)
		preview.size = Vector2(296, 20)
		row.add_child(preview)
		if int(thread["unread"]) > 0:
			var mark := _label("●", &"LabelWarnSmall")
			mark.name = "UnreadMark"
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			mark.position = Vector2(352, 32)
			mark.size = Vector2(26, 20)
			row.add_child(mark)
		row.pressed.connect(on_open.bind(str(thread["key"])))


## DMのやりとり：「‹ 戻る」・連絡先のカード（名前あり客は 前回の注文の札・来た日・好物。ほかは名前だけ）・吹き出し（日時の区切り付き。古い順）。
static func fill_dm_thread(content: VBoxContainer, thread: Dictionary, card: Dictionary, on_back: Callable, palette: Control) -> void:
	var back := Button.new()
	back.name = "DmBack"
	back.text = "‹ 戻る"
	back.theme_type_variation = &"ButtonSmall"
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(on_back)
	content.add_child(back)
	var panel := PanelContainer.new()
	panel.name = "ContactCard"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = palette.get_theme_color(&"bg2", &"UiPalette")
	style.border_color = palette.get_theme_color(&"line", &"UiPalette")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	content.add_child(panel)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 4)
	panel.add_child(lines)
	var name := _label(str(card.get("name", thread.get("name", ""))), &"LabelPhoneHeadline")
	name.name = "CardName"
	lines.add_child(name)
	if str(card.get("customer", "")) != "":
		var order_line := HBoxContainer.new()
		order_line.name = "CardLastOrder"
		order_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		order_line.add_theme_constant_override("separation", 8)
		lines.add_child(order_line)
		var caption := _label("前回", &"LabelCaption")
		caption.custom_minimum_size = Vector2(48, 0)
		order_line.add_child(caption)
		var last_order: Array = card.get("last_order", [])
		if last_order.is_empty():
			order_line.add_child(_label("まだ無い", &"LabelDim"))
		else:
			var chips := HBoxContainer.new()
			chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chips.add_theme_constant_override("separation", 4)
			order_line.add_child(chips)
			UiTagChips.fill(chips, last_order)
		var days: Array = card.get("days", [])
		var days_label := _label("来た日　" + ("・".join(PackedStringArray(days.map(func(d): return Calendar.label(int(d))))) if not days.is_empty() else "まだ無い"), &"LabelSub")
		days_label.name = "CardDays"
		lines.add_child(days_label)
		if bool(card.get("favorite_known", false)):
			var favorite := _label("好物　" + str(card.get("favorite", "")), &"LabelSub")
			favorite.name = "CardFavorite"
			lines.add_child(favorite)
	for message in thread.get("messages", []):
		var stamp := _label(Calendar.stamp(int(message["day"]), str(message["time"])), &"LabelCaption")
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.custom_minimum_size = Vector2(WIDTH, 0)
		content.add_child(stamp)
		var bubble := PanelContainer.new()
		bubble.name = "Bubble_%s" % str(message["id"])
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var bubble_style := StyleBoxFlat.new()
		bubble_style.bg_color = palette.get_theme_color(&"button", &"UiPalette")
		bubble_style.set_corner_radius_all(10)
		bubble_style.set_content_margin_all(8)
		bubble.add_theme_stylebox_override("panel", bubble_style)
		content.add_child(bubble)
		var text := _label(str(message["text"]), &"LabelPhoneBody")
		text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		bubble.add_child(text)
		# 短い文は吹き出しを文の幅に、長い文は 300 で折り返す
		var font := text.get_theme_font(&"font")
		var width := font.get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text.get_theme_font_size(&"font_size")).x + 2.0
		text.custom_minimum_size = Vector2(minf(width, 300.0), 0)
