extends RefCounted
## スマホのSNS（UI準備R・試しの実装）：タブは SNS／ニュース／持ち物（客タブは画面に出さない）。SNSタブはタイムライン（最初に開く）と DM（相手ごと）。
## タイムラインのデータ（data/sns/week7.json）の検査・見える時刻（05:00〜17:59＝その日の朝から／18:00〜04:59＝その日の閉店のあとから）・
## met（その客の初来店の日の閉店のあとから）・並び（新しい日が上・同じ日は新しい時刻が上・夜中はその日の24時以降・返信は元の投稿の下に古い順）・
## 未読の●（SNSタブとスマホのボタン。タイムラインを開くと消える）・DMの一覧／やりとり／戻る／相手ごとの未読・連絡先のカード・朝の保存から戻したとき。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _names(content: Node, prefix: String) -> Array:
	var out := []
	for child in content.get_children():
		if str(child.name).begins_with(prefix):
			out.append(str(child.name).trim_prefix(prefix))
	return out


func _texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_texts(child, out)
	return out


func _post_ids(sections: Array) -> Array:
	var out := []
	for section in sections:
		for item in section["posts"]:
			out.append(str(item["id"]))
			for reply in item["replies"]:
				out.append("  " + str(reply["id"]))
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Sns.clear_cache()

	# --- 1. データの検査 ---
	c.check("タイムラインのデータ（仮）に問題がない", Sns.problems().is_empty(), str(Sns.problems()))
	c.check("アカウントは5件・投稿は21件（仮データ）", Sns.accounts().size() == 5 and Sns.posts().size() == 21, "%d / %d" % [Sns.accounts().size(), Sns.posts().size()])
	var base: Dictionary = Sns.data().duplicate(true)
	var bad: Dictionary = base.duplicate(true)
	(bad["posts"] as Array).append({ "id": "x1", "account": "nobody", "day": 2, "time": "10:00", "text": "あ" })
	(bad["posts"] as Array).append({ "id": "x2", "account": "dock", "day": 3, "time": "18:00", "text": "早すぎる返信", "reply_to": "d3_yoru_rain" })
	(bad["posts"] as Array).append({ "id": "x3", "account": "dock", "day": 3, "time": "20:00", "text": "あ", "reply_to": "no_such_post" })
	(bad["posts"] as Array).append({ "id": "x4", "account": "dock", "day": 3, "time": "20:00", "text": "" })
	(bad["posts"] as Array).append({ "id": "x5", "account": "dock", "day": 3, "time": "20:00", "text": "HOT が好き" })
	(bad["posts"] as Array).append({ "id": "x1", "account": "dock", "day": 3, "time": "20:00", "text": "9時に3人" })
	bad["accounts"]["dup"] = { "name": "重複", "handle": "@dock_hands", "icon": { "color": "#123456", "text": "重" }, "kind": "main", "owner": "town", "profile": "" }
	var p := Sns.problems(bad)
	c.check("検査：無いアカウント・返信先が無い・返信が元より前の時刻・本文が空・英字の札・id の重複・ID（@〜）の重複を弾く",
		p.any(func(x): return str(x).contains("nobody")) and p.any(func(x): return str(x).contains("no_such_post"))
			and p.any(func(x): return str(x).contains("x2") and str(x).contains("前の時刻")) and p.any(func(x): return str(x).contains("x4") and str(x).contains("空"))
			and p.any(func(x): return str(x).contains("HOT")) and p.any(func(x): return str(x).contains("x1") and str(x).contains("重複"))
			and p.any(func(x): return str(x).contains("@dock_hands")), str(p))
	c.check("検査：数字は使ってよい", not p.any(func(x): return str(x).contains("9時に3人")))

	# --- 2. 見える時刻・met・並び ---
	GameState.reset_for_new_game()
	var morning := { "day": 4, "time": "11:20" }
	var night := { "day": 3, "time": "18:40" }
	var late := { "day": 2, "time": "02:15" }
	c.check("05:00〜17:59 はその日の朝から（Day4 11:20 は Day4 に見える・Day3 には見えない）", Sns.is_visible(morning, 4) and not Sns.is_visible(morning, 3))
	c.check("18:00〜04:59 はその日の閉店のあと＝翌朝から（Day3 18:40 は Day3 には見えず、Day4 に見える。日の締めが済めば同じ日にも）",
		not Sns.is_visible(night, 3) and Sns.is_visible(night, 4) and Sns.is_visible(night, 3, true))
	c.check("夜中（Day2 02:15）はその日の夜の続き：Day2 には見えず、Day3 に見える", not Sns.is_visible(late, 2) and Sns.is_visible(late, 3))
	var met := { "day": 4, "time": "22:30", "requires": { "met": "streamer" } }
	c.check("met：会っていない客の条件の投稿は見えない", not Sns.is_visible(met, 6))
	var day := GameState.day_count
	GameState.day_count = 4
	CustomerMemory.arrive("streamer", "宵の口", "streamer_01")
	GameState.day_count = day
	c.check("met：その客の初来店の日（Day4）の閉店のあとから（Day5 に見える・Day4 には見えない）", Sns.is_visible(met, 5) and not Sns.is_visible(met, 4))
	var ids := _post_ids(Sns.timeline(7))
	c.check("並び（Day7 の朝）：新しい日が上・同じ日は新しい時刻が上・夜中は24時以降・返信は元の投稿のすぐ下に古い順。Day7 の夜の投稿はまだ見えない",
		ids.find("d7_yoru_apology") == 0 and ids.find("  d7_passer1_reply") == 1 and ids.find("  d7_passer2_reply") == 2
			and not ids.has("d7_yoru_tonight") and not ids.has("d7_noise_retract")
			and ids.find("d6_noise_deleted") < ids.find("d6_yoru_fire") and ids.find("d6_yoru_fire") + 1 == ids.find("  d6_passer2_reply")
			and ids.find("d5_yoru_stopped") < ids.find("d5_yoru_company") and ids.find("d5_yoru_company") < ids.find("d5_noise_shrimp")
			and ids.find("d2_yoru_hungry") < ids.find("d2_yoru_checkpoint") and ids.has("d4_yoru_ate"), str(ids))
	var sections := Sns.timeline(7)
	c.check("日の区切り：Day7 から Day1 まで、新しい日が上", sections.map(func(s): return int(s["day"])) == [7, 6, 5, 4, 3, 2, 1], str(sections.map(func(s): return int(s["day"]))))
	c.check("最終日の結果画面（日の締めのあと）なら Day7 の夜の投稿も見える", _post_ids(Sns.timeline(7, true)).has("d7_noise_retract"))
	GameState.reset_for_new_game()

	# --- 3. 画面：タブ・タイムライン・●（Day2 の朝まで遊ぶ） ---
	ReadState.reset("user://test_read_sns.json")
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while not (GameState.day_count == 2 and GameState.phase == GameState.Phase.WAKE) and guard < 3000:
		guard += 1
		play.step()
	var envelope: Dictionary = MorningSave.capture("")
	var phone: UiPanePhone = root.pane_phone
	var tabs: Control = phone.get_node("%Tabs")
	var tab_texts := []
	for child in tabs.get_children():
		if child is Button:
			tab_texts.append((child as Button).text)
	c.check("タブは3つ（SNS／ニュース／持ち物）・客タブは無い", tab_texts == ["SNS", "ニュース", "持ち物"], str(tab_texts))
	var unread_before := s.timeline_unread_count()
	c.check("Day2 の朝：Day1 の夜の投稿が見えていて、未読（スマホのボタンの数に入る）", unread_before == 1 and s.phone_unread_count() >= unread_before + s.dm_unread_count(), "%d" % unread_before)
	root.open_phone("news")
	var sns_badge := (phone.get_node("%SnsBadge") as Label).text
	c.check("SNSタブの●＝タイムラインの新しい投稿＋未読のDM", sns_badge == "●%d" % (unread_before + s.dm_unread_count()), sns_badge)
	_press(tabs.get_child(0))
	var content: VBoxContainer = phone.get_node("%Content")
	c.check("SNSタブを開くと、いつもタイムライン（上に「タイムライン｜DM」）", phone.sns_mode == "timeline" and content.has_node("SnsSwitch")
		and content.has_node("Post_d1_yoru_strike") and content.has_node("Day_1"), str(_names(content, "")))
	var post: Node = content.get_node("Post_d1_yoru_strike")
	var post_texts := _texts(post)
	c.check("投稿：表示名・ID（@〜）・時刻（Day1 23:10）・本文。持ち主は出さない", post_texts.has("夜歩きカメラ") and post_texts.has("@yoru_cam_09") and post_texts.has("Day1 23:10")
		and not post_texts.any(func(x): return str(x).contains("streamer") or str(x).contains("配信者")), str(post_texts))
	c.check("タイムラインを開いたら●が消える（未読 0）・開いた時点で未読だった投稿には左の線", s.timeline_unread_count() == 0
		and (post.get_node("UnreadBar") as ColorRect).color.a > 0.0)
	c.check("その日より先の投稿は出ない（Day2 の朝は Day1 の分だけ）", _names(content, "Post_") == ["d1_yoru_strike"], str(_names(content, "Post_")))

	# --- 4. DM：相手ごとの一覧・やりとり・戻る・相手ごとの未読・連絡先のカード ---
	var threads := s.dm_threads()
	var keys: Array = threads.map(func(th): return str(th["key"]))
	c.check("DMは相手ごと（配達員＝名前あり客／市場の顔なじみ＝客でない差出人）", keys.has("customer:delivery_man") and keys.has("npc:市場の顔なじみ"), str(keys))
	var orders: Array = threads.map(func(th): return int(th["last"]["day"]) * 10000 + Sns.minutes(str(th["last"]["time"])))
	var sorted_orders := orders.duplicate()
	sorted_orders.sort()
	sorted_orders.reverse()
	c.check("相手の並び：最後のメッセージが新しい相手が上（DMの朝の時刻〔04:45 など〕はその日の朝として並べる）", orders == sorted_orders, str(orders))
	var dm_total := s.dm_unread_count()
	_press(content.get_node("SnsSwitch/SwitchDm"))
	c.check("「DM」に切り替えると相手の一覧（未読のある相手に●・DMの切り替えに未読の数）", phone.sns_mode == "dm" and content.has_node("DmRow_customer_delivery_man")
		and content.has_node("DmRow_customer_delivery_man/UnreadMark") and (content.get_node("SnsSwitch/DmUnread") as Label).text == "●%d" % dm_total, str(_names(content, "DmRow_")))
	c.check("一覧を見ただけでは読んだ扱いにならない", s.dm_unread_count() == dm_total)
	var dm_thread: Dictionary = threads.filter(func(th): return str(th["key"]) == "customer:delivery_man")[0]
	var npc_unread := int(threads.filter(func(th): return str(th["key"]) == "npc:市場の顔なじみ")[0]["unread"])
	_press(content.get_node("DmRow_customer_delivery_man"))
	var thread_texts := _texts(content)
	c.check("相手を押すとやりとり（吹き出し・日時の区切り）。その相手の未読だけ消える", phone.dm_open == "customer:delivery_man" and content.has_node("DmBack")
		and (dm_thread["messages"] as Array).all(func(m): return thread_texts.has(str(m["text"])) and thread_texts.has(Calendar.stamp(int(m["day"]), str(m["time"]))))
		and s.dm_unread_count() == dm_total - int(dm_thread["unread"]), str(thread_texts))
	var card: Node = content.get_node("ContactCard")
	var card_texts := _texts(card)
	c.check("連絡先のカード（名前あり客）：名前・前回の注文の札（辛い・スタミナ）・来た日（Day1）・好物（知った客だけ）", card_texts.has("配達員") and card_texts.has("辛い")
		and card_texts.has("スタミナ") and card_texts.has("来た日　Day1") and (card_texts.has("好物　" + Ingredients.name_for("tofu")) == GameState.knows_favorite("delivery_man")), str(card_texts))
	_press(content.get_node("DmBack"))
	c.check("「戻る」で相手の一覧・配達員の●は消えている", phone.dm_open == "" and content.has_node("DmRow_customer_delivery_man") and not content.has_node("DmRow_customer_delivery_man/UnreadMark"))
	_press(content.get_node("DmRow_npc_市場の顔なじみ"))
	c.check("客でない相手のカードは名前だけ", _texts(content.get_node("ContactCard")) == ["市場の顔なじみ"], str(_texts(content.get_node("ContactCard"))))
	_press(content.get_node("SnsSwitch/SwitchTimeline"))
	c.check("上の切り替えでタイムラインにも戻れる", phone.sns_mode == "timeline" and content.has_node("Post_d1_yoru_strike"))
	root.close_overlay()

	# --- 5. 朝の保存から戻したとき（既読は保存とは別に持つ。見える投稿はその朝の日で決まる） ---
	MorningSave.apply(envelope)
	c.check("朝の保存から戻す：その朝に見える投稿だけ・一度読んだ投稿とDMは読んだまま（●は戻らない）", s.timeline_unread_count() == 0
		and Sns.visible_ids(GameState.day_count) == ["d1_yoru_strike"] and s.dm_unread_count() == dm_total - int(dm_thread["unread"]) - npc_unread)
	root.queue_free()
	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	return c.finish()
