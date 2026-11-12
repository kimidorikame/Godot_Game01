extends RefCounted
## UI準備V：行頭禁則（タイムラインの投稿・DM・ニュース・会話ログの折り返し）とアイコンの文字の色、会話ログの上限。
##   1. 折り返しは AUTOWRAP_WORD_SMART（ICU の改行規則）：「。」「、」「」」「）」「！」「？」「ー」を行の頭に置かない。
##      報告にあった3つの投稿（同伴まで二時間 16:40・パーツ相談室 16:25・葉っぱの番 09:40）を、画面と同じフォント・大きさ・幅で折り返して確かめる。
##   2. アイコンの文字の色は、地の明るさで選ぶ（白い文字のコントラスト比が 3.0 に届かない明るい地は暗い文字）。
##   3. 会話ログの上限は 3000 行（1日分が収まる）。

const HEAD_NG := "。、」）！？ー"


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


## Label と同じ折り返し（autowrap の WORD_SMART）で、行の頭に来る文字を集める。
func _bad_heads(label: Label, width: float) -> Array:
	var ts := TextServerManager.get_primary_interface()
	var font := label.get_theme_font(&"font")
	var size := label.get_theme_font_size(&"font_size")
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, label.text, font.get_rids(), size)
	var flags := TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE | TextServer.BREAK_MANDATORY
	var breaks := ts.shaped_text_get_line_breaks(rid, width, 0, flags)
	var bad := []
	for i in range(0, breaks.size(), 2):
		var start := int(breaks[i])
		if start > 0 and HEAD_NG.contains(label.text.substr(start, 1)):
			bad.append(label.text.substr(start, 8))
	ts.free_rid(rid)
	return bad


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()

	# --- 3. 会話ログの上限 ---
	c.check("会話ログの上限は3000行（1日目だけで300行を超えるので、1日分が収まる）", TalkLog.MAX_LINES >= 3000)

	# --- 2. アイコンの文字の色 ---
	var dark := UiSnsView.ICON_TEXT_DARK
	var light := UiSnsView.ICON_TEXT_LIGHT
	c.check("白・薄い色・黄の地は暗い文字（「パ」「片」の白 #d8d8d8 も）",
		UiSnsView.icon_text_color(Color("#d8d8d8")) == dark and UiSnsView.icon_text_color(Color("#ffffff")) == dark
			and UiSnsView.icon_text_color(Color("#d9b23a")) == dark and UiSnsView.icon_text_color(Color("#8fc98a")) == dark)
	c.check("濃い色・中くらいの灰の地は白い文字のまま（紺・灰・赤紫・黒・灰青・赤）",
		UiSnsView.icon_text_color(Color("#2f4a7a")) == light and UiSnsView.icon_text_color(Color("#7a808a")) == light
			and UiSnsView.icon_text_color(Color("#b0407a")) == light and UiSnsView.icon_text_color(Color("#2a2a2e")) == light
			and UiSnsView.icon_text_color(Color("#6b7f95")) == light and UiSnsView.icon_text_color(Color("#c0463a")) == light)
	var icon := UiSnsView.make_icon(Color("#d8d8d8"), "パ")
	var icon_label: Label = icon.get_child(0)
	c.check("make_icon は地の色に合わせて文字の色を付ける", icon_label.get_theme_color(&"font_color") == dark)
	icon.free()

	# --- 1. 行頭禁則：本番の画面（Day2 の朝のタイムライン） ---
	ReadState.reset("user://test_read_kinsoku.json")
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.open_phone("sns")
	var phone: UiPanePhone = root.pane_phone
	var content: VBoxContainer = phone.get_node("%Content")
	var all_smart := true
	var bad_all := {}
	for id in ["d1_two_hours_1640", "d1_parts_consult_1625", "d1_ayu_0940"]:
		c.check("（前提）投稿 %s がタイムラインにある" % id, content.has_node("Post_%s" % id))
		if not content.has_node("Post_%s" % id):
			continue
		var text: Label = content.get_node("Post_%s" % id).find_child("Text", true, false)
		all_smart = all_smart and text.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART
		var bad := _bad_heads(text, text.custom_minimum_size.x)
		if not bad.is_empty():
			bad_all[id] = bad
		# 前の折り返し（どこでも切る）なら、この幅で行の頭に句読点が来ていたこと（直したことの確かめ）
	c.check("投稿の本文は WORD_SMART で折り返す", all_smart)
	c.check("3つの投稿（同伴まで二時間 16:40・パーツ相談室 16:25・葉っぱの番 09:40）は、画面の幅で折り返しても行の頭に句読点などが来ない",
		bad_all.is_empty(), str(bad_all))
	var posts_smart := true
	for row in content.get_children():
		if str(row.name).begins_with("Post_"):
			var text: Label = row.find_child("Text", true, false)
			posts_smart = posts_smart and text != null and text.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART \
				and _bad_heads(text, text.custom_minimum_size.x).is_empty()
	c.check("タイムラインのどの投稿も、行の頭に句読点などが来ない", posts_smart)
	# ニュース：一覧の見出しと詳細の本文
	_press(phone.get_node("%Tabs").get_child(1))
	var headlines := content.get_children().filter(func(n): return str(n.name).begins_with("NewsRow_"))
	var news_smart := not headlines.is_empty()
	for row in headlines:
		for l in row.get_children():
			if l is Label and (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
				news_smart = news_smart and (l as Label).autowrap_mode == TextServer.AUTOWRAP_WORD_SMART
	_press(headlines[0])
	var body_labels := content.get_children().filter(func(n): return n is Label and (n as Label).autowrap_mode != TextServer.AUTOWRAP_OFF)
	c.check("ニュースの見出しと本文も WORD_SMART", news_smart and not body_labels.is_empty()
		and body_labels.all(func(l): return (l as Label).autowrap_mode == TextServer.AUTOWRAP_WORD_SMART))
	root.close_overlay()
	# 会話ログ
	TalkLog.clear()
	TalkLog.add(2, "talk", "阿強", "「地図開いたら、また正面口に戻されたんだけど」")
	root.left.toggle_log()
	var log_content: VBoxContainer = root.left.get_node("%LogContent")
	c.check("会話ログの行も WORD_SMART", log_content.get_child_count() > 0
		and log_content.get_children().all(func(l): return (l as Label).autowrap_mode == TextServer.AUTOWRAP_WORD_SMART))
	root.left.close_log()
	root.queue_free()

	TalkLog.clear()
	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()
