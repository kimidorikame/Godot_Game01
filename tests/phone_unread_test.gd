extends RefCounted
## スマホの未読（UI準備D）：ボタンの●は、DMとニュースの未読の合計。ニュースタブにも●。タブを表示した時点で既読。
## 朝の会話枠にはニュースとスマホの入力待ちを出さない（ニュースはスマホで読む）ので、必須情報（must_info）を持つニュースが
## 未読のまま「市場へ」に進める（ゲートは付けない）。この事実も確かめる。
## 既読は ReadState（保存とは別のファイル。idで持つ）。ここでは専用のパスで空から始め、終わったらテスト共通のパスへ戻す。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ReadState.reset("user://test_read_unread.json")

	# --- 1. PlaySession：ニュースの未読・既読・必須情報 ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var s := PlaySession.new()
	t.root.add_child(s)
	var news_total := 0
	for section in s.phone_news():
		news_total += (section["news"] as Array).size()
	c.check("Day3：今日までのニュースが3件（Day1・2・3の各1件）で、すべてid・未読つき", news_total == 3
		and s.phone_news().all(func(sec): return (sec["news"] as Array).all(func(n): return str(n["id"]) != "" and bool(n["unread"]))))
	c.check("ニュースの未読の数＝3、スマホの未読の合計＝DM＋ニュース", s.news_unread_count() == 3
		and s.phone_unread_count() == s.dm_unread_count() + s.news_unread_count(), "%d/%d" % [s.news_unread_count(), s.dm_unread_count()])
	c.check("必須情報を持つ未読のニュース（3件）を数えられる", (s.unread_must_info_news() as Array).size() == 3, str(s.unread_must_info_news()))
	s.mark_news_read()
	c.check("mark_news_read() でニュースは全部既読（DMは変わらない）", s.news_unread_count() == 0 and s.unread_must_info_news().is_empty()
		and s.phone_unread_count() == s.dm_unread_count())
	c.check("既読はidで持つ（もう一度呼んでも増減しない・phone_news の unread が全部 false）",
		s.phone_news().all(func(sec): return (sec["news"] as Array).all(func(n): return not bool(n["unread"]))))
	s.free()

	# --- 2. 画面：ボタンの●・タブの●・開いた時点で既読 ---
	ReadState.reset("user://test_read_unread.json")
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.day_records.append({ "day": 2 })   # 前日の記録がある朝（Day1の朝は前日が無いので、スマホから始まる）
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var session: PlaySession = root.session
	var badge: Label = root.left.get_node("%PhoneBadge")
	var expected_total := session.dm_unread_count() + session.news_unread_count()
	c.check("スマホのボタンの●は、DMとニュースの未読の合計", expected_total >= 3 and badge.text == "●%d" % expected_total, badge.text)
	var phone: UiPanePhone = root.pane_phone
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%PhoneIcon"))
	c.check("スマホを開く（最初に見せるのはニュースのタブ）", root.overlay == "phone" and phone.visible and phone.tab == "news")
	var tabs: Control = phone.get_node("%Tabs")
	var news_badge: Label = phone.get_node("%NewsBadge")
	var sns_badge: Label = phone.get_node("%SnsBadge")
	c.check("ニュースタブを表示した時点で、ニュースは既読（ニュースタブの●は出ない）", session.news_unread_count() == 0 and news_badge.text == "")
	var dm_left := session.dm_unread_count()
	c.check("ボタンの●は、残りのDMの数だけになる", badge.text == ("●%d" % dm_left if dm_left > 0 else ""), badge.text)
	c.check("SNSタブの●（未読のDM）が出ている", dm_left == 0 or sns_badge.text == "●%d" % dm_left, sns_badge.text)
	var headline_marked := false
	for label in phone.get_node("%Content").get_children():
		headline_marked = headline_marked or (label as Label).text.begins_with("● ")
	c.check("開いた時点で未読だったニュースの見出しには ● が付く（スマホを閉じるまで）", headline_marked)
	load("res://tests/ui_autoplay.gd").press(tabs.get_child(0))
	c.check("SNSタブを表示した時点で、DMも既読（ボタンの●が消える）", session.dm_unread_count() == 0 and badge.text == "")
	load("res://tests/ui_autoplay.gd").press(phone.get_node("%CloseButton"))
	load("res://tests/ui_autoplay.gd").press(root.left.get_node("%PhoneIcon"))
	load("res://tests/ui_autoplay.gd").press(tabs.get_child(1))
	var marked_again := false
	for label in phone.get_node("%Content").get_children():
		marked_again = marked_again or (label as Label).text.begins_with("● ")
	c.check("スマホを開き直すと、見出しの ● は消えている（もう既読）", not marked_again)
	root.queue_free()

	# --- 3. 朝の会話枠にニュースは出ない → 必須情報のニュースが未読のまま「市場へ」に進める（ゲートなし）---
	ReadState.reset("user://test_read_unread.json")
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.day_records.append({ "day": 1 })
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	session = root.session
	var guard := 0
	var shown: Array = []
	while not session.flow.is_runner_done() and guard < 40:
		guard += 1
		root.left.advance()
		shown.append(str(root.left.get_node("%DialogueText").text))
	var primary: Button = root.pane_morning.get_node("%PrimaryButton")
	c.check("Day2の朝の語りを読み終えた（会話枠にニュースの行は出ていない）", session.flow.is_runner_done()
		and not shown.any(func(x): return str(x).contains("ニュース：")), str(shown))
	c.check("このとき必須情報を持つニュース（Day1・Day2の分）は未読のまま", (session.unread_must_info_news() as Array).size() == 2
		and session.news_unread_count() == 2, str(session.unread_must_info_news()))
	c.check("「市場へ」は押せる（未読の必須情報ニュースでも止めない）", primary.text == "市場へ" and not primary.disabled)
	load("res://tests/ui_autoplay.gd").press(primary)
	c.check("そのまま仕込み（PREP）へ進める", GameState.phase == GameState.Phase.PREP and session.news_unread_count() == 2)
	root.queue_free()

	ReadState.reset("user://test_read_state.json")
	GameState.reset_for_new_game()
	return c.finish()
