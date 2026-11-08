extends RefCounted
## 本番UI（UI準備B⑤）の通しテスト：Day1の朝から最終日の結果画面まで、UIのボタンと会話枠のクリックだけで進める
## （台本 tests/ui_autoplay.gd。DebugPanel は使わない）。あわせて、スマホ（タブ・閉じる・開店中の入れ替え）と
## 会話ログ、メインシーンが game_root.tscn であることを確かめる。

const MAX_STEPS := 6000


## 入れ物の並べ替えは次のフレームに起きるので、テストでは手で走らせる（子から順に）。
func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	c.check("メインシーンは本番UI（scenes/game_root.tscn）", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/game_root.tscn")
	c.check("DebugPanel は別のシーンとして残っている（エディタで開ける）", load("res://scenes/debug_panel.tscn") != null)

	# --- 1. Day1の朝 → 最終日の結果（UIだけ）---
	GameState.reset_for_new_game()
	# このテストは画面の流れを見る。台本（最初に見えた材料を入れるだけ）は BAD が多く、BAD の売価（UI準備N）だと
	# 最終日の前にお金が尽きるので、ここだけ BAD も定価にする（売価は tests/bad_price_decline_test.gd）。
	var data_bad_price: int = GameState.BAD_PRICE
	GameState.BAD_PRICE = GameState.PRICE_PER_SERVING
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var steps := 0
	var days_seen := {}
	var phases_seen := {}
	var actions := {}
	var reached_close_day1 := false
	while steps < MAX_STEPS:
		days_seen[GameState.day_count] = true
		phases_seen[GameState.phase] = true
		if GameState.day_count == 1 and GameState.phase == GameState.Phase.CLOSE:
			reached_close_day1 = true
		var action: String = play.step()
		if action == "":
			break
		actions[action] = int(actions.get(action, 0)) + 1
		steps += 1
	c.check("Day1の朝から閉店まで、UIの操作だけで進んだ", reached_close_day1)
	c.check("最終日の結果画面（RESULT）まで、UIの操作だけで進んだ（%d手）" % steps,
		GameState.phase == GameState.Phase.RESULT and root.full_result.visible, "phase=%d day=%d steps=%d" % [GameState.phase, GameState.day_count, steps])
	c.check("全部の日（Day1〜最終日）を通った", days_seen.size() == GameState.FINAL_DAY, str(days_seen.keys()))
	c.check("朝・仕込み・開店・閉店の各フェーズを通った", phases_seen.has(GameState.Phase.WAKE) and phases_seen.has(GameState.Phase.PREP)
		and phases_seen.has(GameState.Phase.OPEN) and phases_seen.has(GameState.Phase.CLOSE))
	c.check("主な操作を一通り使った（市場へ・鍋の素・市場を出る・開店する・提供・閉店する・次の日へ）",
		actions.has("市場へ") and actions.has("鍋の素（1）") and actions.has("市場を出る")
			and actions.has("開店する") and actions.has("提供") and actions.has("閉店する") and actions.has("次の日へ"), str(actions))
	var split_ok := true
	var split_detail := ""
	for record in GameState.day_records:
		var total: int = int(record["unserved_ingredients"]) + int(record["unserved_pot"]) + int(record["unserved_declined"]) 			+ int(record["unserved_not_arrived"])
		if total != int(record["unserved_cups"]):
			split_ok = false
			split_detail += " Day%d:%d≠%d" % [int(record["day"]), total, int(record["unserved_cups"])]
	c.check("7日分の記録すべてで、足りなかった杯数の内訳の合計が unserved_cups と同じ（UI準備C③）",
		split_ok and GameState.day_records.size() == GameState.FINAL_DAY, split_detail)
	print("  UIの通しの操作の内訳: ", actions)
	root.queue_free()

	# --- 2. スマホ・会話ログ ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	s = root.session
	var phone: UiPanePhone = root.pane_phone
	c.check("右の枠と同じ位置 (836,24) 420×672", phone.get_global_rect().is_equal_approx(Rect2(836, 24, 420, 672)))
	var tabs: Control = phone.get_node("%Tabs")
	c.check("タブ SNS／ニュース／持ち物（客タブは UI準備R で画面から外した）：(838,54) から1つ幅139",
		tabs.get_child(0).get_global_position().is_equal_approx(Vector2(838, 54)) and absf(tabs.get_child(0).size.x - 139.0) < 0.5
			and tabs.get_child(1).get_global_position().is_equal_approx(Vector2(977, 54)) and tabs.get_child(2).text == "持ち物"
			and not tabs.get_children().any(func(n): return n is Button and (n as Button).text == "客"))
	c.check("「閉じる」(852,640)・幅388", phone.get_node("%CloseButton").get_global_position().is_equal_approx(Vector2(852, 640))
		and absf(phone.get_node("%CloseButton").size.x - 388.0) < 0.5)
	# SNSタブ＝タイムライン（最初に開く）とDM（UI準備R）。Day2：Day1 の夜の投稿と、条件なしの市場の顔なじみのDMが届いている。客足予報は出さない
	var sns_unread := s.dm_unread_count() + s.timeline_unread_count()
	c.check("スマホのボタンにも、未読の●と数が出る（DM・ニュース・タイムラインの合計）", s.dm_unread_count() >= 1 and s.timeline_unread_count() >= 1
		and root.left.get_node("%PhoneBadge").text == "●%d" % s.phone_unread_count(), root.left.get_node("%PhoneBadge").text)
	AutoplayPress.press(tabs.get_child(1))
	c.check("まだSNSタブを開いていない間は、SNSタブに未読の数（DM＋タイムライン）が出る", phone.get_node("%SnsBadge").text == "●%d" % sns_unread, phone.get_node("%SnsBadge").text)
	AutoplayPress.press(tabs.get_child(0))
	var sns_content: VBoxContainer = phone.get_node("%Content")
	c.check("SNS：最初はタイムライン（上に「タイムライン｜DM」・Day1 の夜の投稿）。予報は出さない", phone.tab == "sns" and phone.sns_mode == "timeline"
		and sns_content.has_node("SnsSwitch") and sns_content.has_node("Post_d1_yoru_strike"))
	c.check("タイムラインを表示したので、その分は既読（SNSタブの数は消え、DMの未読は「DM」の切り替えに出る）", phone.get_node("%SnsBadge").text == ""
		and s.timeline_unread_count() == 0 and (sns_content.get_node("SnsSwitch/DmUnread") as Label).text == "●%d" % s.dm_unread_count())
	AutoplayPress.press(sns_content.get_node("SnsSwitch/SwitchDm"))
	var dm_row: Node = sns_content.get_node("DmRow_npc_市場の顔なじみ")
	var dm_texts: Array = []
	for node in dm_row.get_children():
		if node is Label:
			dm_texts.append(node.text)
	c.check("DMの相手の行：名前・最後のメッセージの1行目・日付と時刻・未読の●（常連の印は付けない）",
		dm_texts.has("今日は入荷が遅れてる。早めに来な") and dm_texts.has("市場の顔なじみ") and dm_texts.has("Day2 06:40") and dm_row.has_node("UnreadMark")
			and not dm_texts.has("常連"), str(dm_texts))
	var market_unread := int(s.dm_threads().filter(func(th): return str(th["key"]) == "npc:市場の顔なじみ")[0]["unread"])
	var dm_before := s.dm_unread_count()
	AutoplayPress.press(dm_row)
	var dm_after := s.dm_unread_count()
	c.check("相手を開くと吹き出しで読める・その相手のDMだけ既読になり、スマホのボタンの数もその分減る", sns_content.has_node("DmBack") and market_unread >= 1
		and dm_after == dm_before - market_unread and root.left.get_node("%PhoneBadge").text == ("●%d" % s.phone_unread_count() if s.phone_unread_count() > 0 else ""),
		root.left.get_node("%PhoneBadge").text)
	# DMが多い相手：やりとりはスクロールできる（縦のスクロール枠で、中身が枠より高くなる）
	var many_items: Array = []
	for i in range(12):
		many_items.append({ "id": "dm_many_%d" % i, "from": "市場の顔なじみ", "from_kind": "npc", "time": "6:%02d" % i,
			"text": "多い日のテスト用のDM（%d）。" % i, "hint": "none", "provisional": true })
	Dm._cache = { "id": Rules.dm(), "hints": Dm.data()["hints"], "days": { "2": many_items } }
	Dm._loaded_id = Rules.dm()
	phone.open_dm_thread("npc:市場の顔なじみ")
	var scroll: ScrollContainer = phone.get_node("%Scroll")
	_sort(root)
	var bubbles := sns_content.get_children().filter(func(n): return str(n.name).begins_with("Bubble_"))
	c.check("DMが多い相手（12通）：やりとりはスクロール枠に入っていて、中身が枠より高い（スクロールできる）",
		scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and bubbles.size() == 12
			and sns_content.get_combined_minimum_size().y > scroll.size.y,
		"%s > %s" % [str(sns_content.get_combined_minimum_size().y), str(scroll.size.y)])
	Dm.clear_cache()
	s.mark_dms_read()
	AutoplayPress.press(tabs.get_child(1))
	c.check("ニュース：phone_news() の見出しが出る（無ければ「まだありません」）", phone.tab == "news" and phone.get_node("%Content").get_child_count() >= 1)
	AutoplayPress.press(phone.get_node("%CloseButton"))
	c.check("「閉じる」で朝の画面に戻る", root.overlay == "" and root.pane_morning.visible)
	AutoplayPress.press(root.left.get_node("%PhoneIcon"))
	c.check("スマホのアイコンで開き（右の枠と入れ替わる）、前に開いたタブのまま", root.pane_phone.visible and not root.pane_morning.visible
		and phone.tab == "news")
	AutoplayPress.press(root.left.get_node("%PhoneIcon"))
	c.check("もう一度アイコンを押すと閉じる", root.overlay == "" and root.pane_morning.visible)
	# ログ：会話枠が上へ伸びて過去の行を並べる（右の枠は置き換えない）。もう一度押すと閉じる。
	var log_box: UiLogBox = root.left.get_node("%LogBox")
	var right_before: Control = root.pane_morning
	AutoplayPress.press(root.left.get_node("%LogIcon"))
	c.check("ログのアイコン：会話枠が上へ伸びて今日の会話の行が並ぶ（右の枠は朝のまま）", root.left.is_log_open() and log_box.visible
		and log_box.row_count() == s.talk_log_entries().size() and s.talk_log_entries().size() >= 1 and root.pane_morning.visible and right_before.visible
		and log_box.get_global_rect().position.y < root.left.get_node("%DialogueBox").get_global_rect().position.y)
	AutoplayPress.press(root.left.get_node("%LogIcon"))
	c.check("もう一度ログのアイコンを押すと閉じる", not root.left.is_log_open() and not log_box.visible and root.pane_morning.visible)
	# 開店中：操作エリアと入れ替わり、「閉じる(鍋・トッピングに戻る)」で戻る（椀の中身は保持）
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["nam_prik_pao", "offal"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	var grid: GridContainer = root.pane_kaiten.topping.get_node("%Grid")
	AutoplayPress.press(grid.get_child(0).get_node("MainButton"))
	AutoplayPress.press(root.left.get_node("%PhoneIcon"))
	c.check("開店中にスマホを開くと操作エリアと入れ替わり、閉じるの文言は「閉じる(鍋・トッピングに戻る)」",
		root.pane_phone.visible and not root.pane_kaiten.visible and phone.get_node("%CloseButton").text == "閉じる(鍋・トッピングに戻る)")
	AutoplayPress.press(phone.get_node("%CloseButton"))
	c.check("閉じるとトッピングに戻り、椀の中身はそのまま", root.pane_kaiten.visible and root.pane_kaiten.topping.visible
		and s.bowl_view()["additions"] == ["offal"])
	AutoplayPress.press(root.left.get_node("%PhoneIcon"))
	s.flow.force_phase(GameState.Phase.CLOSE)
	c.check("区切り（フェーズが替わる）で、スマホの開閉は捨てる", root.overlay == "" and root.pane_close.visible)
	root.queue_free()
	GameState.BAD_PRICE = data_bad_price
	return c.finish()


class AutoplayPress:
	static func press(button: BaseButton) -> bool:
		if button == null or button.disabled or not button.is_visible_in_tree():
			return false
		button.pressed.emit()
		return true
