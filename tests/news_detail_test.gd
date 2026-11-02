extends RefCounted
## スマホのニュースタブ：一覧→詳細（UI準備O）。一覧はその日までのニュースの日付（Calendar.label）と見出し（新しい日が上）、
## 行を押すと詳細（見出し・日付・本文の全部。縦に送れる）、「戻る」で一覧。文は data/news/week7.json の headline・body のまま。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _rows(content: Node) -> Array:
	var out := []
	for child in content.get_children():
		if str(child.name).begins_with("NewsRow_"):
			out.append(str(child.name).trim_prefix("NewsRow_"))
	return out


func _texts(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ReadState.reset("user://test_read_news_detail.json")
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var phone: UiPanePhone = root.pane_phone
	var content: VBoxContainer = phone.get_node("%Content")

	# --- 1. 一覧（Day3 の朝）---
	GameState.day_count = 3
	var unread_before := s.news_unread_count()
	root.open_phone("news")
	var rows := _rows(content)
	c.check("一覧：その日までのニュースを新しい日が上で並べる（Day4 より先は出ない）", rows == ["d3_spillover", "d2_checkpoints", "d1_strike"], str(rows))
	var d3: Dictionary = News.day_entry(3)["news"][0]
	var row3: Button = content.get_node("NewsRow_d3_spillover")
	var row1: Button = content.get_node("NewsRow_d1_strike")
	c.check("一覧の行：日付（Calendar.label。今日には「（今日）」）と見出しだけ（本文は出さない）",
		_texts(row3).has("%s（今日）" % Calendar.label(3)) and _texts(row3).any(func(x): return str(x).ends_with(str(d3["headline"])))
			and _texts(row1).has(Calendar.label(1)) and not _texts(row3).has(str(d3["body"][0])), str(_texts(row3)))
	c.check("一覧を表示した時点で既読（未読の数が 0 になる）", unread_before > 0 and s.news_unread_count() == 0, "%d→%d" % [unread_before, s.news_unread_count()])
	c.check("一覧の行の高さは見出しの行数に合わせる（最低56）", row3.custom_minimum_size.y >= 56.0 and row3.custom_minimum_size.x == 388.0)

	# --- 2. 詳細・戻る ---
	_press(row3)
	var labels := _texts(content)
	c.check("行を押すと詳細：見出し・日付・本文の全部（一覧の行は消える）", phone.news_open == "d3_spillover" and _rows(content).is_empty()
		and content.has_node("NewsBack") and (content.get_node("NewsHeadline") as Label).text == str(d3["headline"])
		and (content.get_node("NewsDate") as Label).text == "%s（今日）" % Calendar.label(3)
		and (d3["body"] as Array).all(func(line): return labels.has(str(line))), str(labels))
	_press(content.get_node("NewsBack"))
	c.check("「戻る」で一覧に戻る", phone.news_open == "" and _rows(content) == ["d3_spillover", "d2_checkpoints", "d1_strike"], str(_rows(content)))

	# --- 3. 長い本文（Day7 の d7_unresolved は4行）：縦に送れる ---
	root.close_overlay()
	GameState.day_count = 7
	root.open_phone("news")
	c.check("Day7 の一覧：7日分の見出しが全部（同じ日の2本も）", _rows(content).size() == 9 and _rows(content)[0] == "d7_official" and _rows(content)[1] == "d7_unresolved", str(_rows(content)))
	_press(content.get_node("NewsRow_d7_unresolved"))
	var long: Dictionary = News.day_entry(7)["news"][1]
	labels = _texts(content)
	var scroll: ScrollContainer = phone.get_node("%Scroll")
	c.check("本文が長くても全部出る（4行）・一覧は縦に送れる枠の中", (long["body"] as Array).size() == 4 and (long["body"] as Array).all(func(line): return labels.has(str(line)))
		and content.get_parent() == scroll and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	var body_label: Label = null
	for child in content.get_children():
		if child is Label and (child as Label).text == str(long["body"][0]):
			body_label = child
	c.check("本文は折り返す（幅380）", body_label != null and body_label.autowrap_mode != TextServer.AUTOWRAP_OFF and body_label.custom_minimum_size.x == 380.0)

	# --- 4. タブを替える・閉じると一覧に戻る ---
	var tabs: Control = phone.get_node("%Tabs")
	_press(tabs.get_child(0))
	_press(tabs.get_child(1))
	c.check("ほかのタブへ行って戻ると一覧", phone.news_open == "" and not _rows(content).is_empty())
	_press(content.get_node("NewsRow_d1_strike"))
	root.close_overlay()
	root.open_phone("news")
	c.check("閉じて開き直すと一覧", phone.news_open == "" and not _rows(content).is_empty())

	# --- 5. 朝の語りのニュース（News.morning_events）は今のまま ---
	c.check("朝の語りのニュースの列は変えない（Day3 の見出しが入る）", JSON.stringify(News.morning_events(3)).contains(str(d3["headline"])))
	root.queue_free()
	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	return c.finish()
