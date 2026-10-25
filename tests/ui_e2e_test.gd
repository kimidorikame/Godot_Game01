extends RefCounted
## 本番UI（UI準備B⑤）の通しテスト：Day1の朝から最終日の結果画面まで、UIのボタンと会話枠のクリックだけで進める
## （台本 tests/ui_autoplay.gd。DebugPanel は使わない）。あわせて、スマホ（タブ・閉じる・開店中の入れ替え）と
## 会話ログ、メインシーンが game_root.tscn であることを確かめる。

const MAX_STEPS := 6000


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	c.check("メインシーンは本番UI（scenes/game_root.tscn）", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/game_root.tscn")
	c.check("DebugPanel は別のシーンとして残っている（エディタで開ける）", load("res://scenes/debug_panel.tscn") != null)

	# --- 1. Day1の朝 → 最終日の結果（UIだけ）---
	GameState.reset_for_new_game()
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
	c.check("主な操作を一通り使った（スマホを見る・鍋の素・市場を出る・開店する・提供・閉店する・次の日へ）",
		actions.has("スマホを見る") and actions.has("鍋の素（1）") and actions.has("市場を出る")
			and actions.has("開店する") and actions.has("提供") and actions.has("閉店する") and actions.has("次の日へ"), str(actions))
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
	c.check("タブ SNS／ニュース／レシピ：(838,54) から1つ幅139",
		tabs.get_child(0).get_global_position().is_equal_approx(Vector2(838, 54)) and absf(tabs.get_child(0).size.x - 139.0) < 0.5
			and tabs.get_child(1).get_global_position().is_equal_approx(Vector2(977, 54)) and tabs.get_child(2).text == "レシピ")
	c.check("「閉じる」(852,640)・幅388", phone.get_node("%CloseButton").get_global_position().is_equal_approx(Vector2(852, 640))
		and absf(phone.get_node("%CloseButton").size.x - 388.0) < 0.5)
	AutoplayPress.press(tabs.get_child(0))
	c.check("SNS：Cで DM に替えるまで「まだ新着はありません」（客足予報は出さない）", phone.tab == "sns"
		and phone.get_node("%Content").get_child_count() == 1 and phone.get_node("%Content").get_child(0).text == "まだ新着はありません")
	AutoplayPress.press(tabs.get_child(2))
	var recipe_texts: Array = []
	for label in phone.get_node("%Content").get_children():
		recipe_texts.append(label.text)
	c.check("レシピ：保存したレシピの枠（空き）と、いつもの", phone.tab == "recipe" and recipe_texts.has("保存したレシピ")
		and recipe_texts.has("枠1（空き）") and recipe_texts.has("いつもの"), str(recipe_texts))
	AutoplayPress.press(tabs.get_child(1))
	c.check("ニュース：phone_news() の見出しが出る（無ければ「まだありません」）", phone.tab == "news" and phone.get_node("%Content").get_child_count() >= 1)
	AutoplayPress.press(phone.get_node("%CloseButton"))
	c.check("「閉じる」で朝の画面に戻る", root.overlay == "" and root.pane_morning.visible)
	AutoplayPress.press(root.left.get_node("%PhoneIcon"))
	c.check("スマホのアイコンで開き（右の枠と入れ替わる）、前に開いたタブのまま", root.pane_phone.visible and not root.pane_morning.visible
		and phone.tab == "news")
	AutoplayPress.press(root.left.get_node("%PhoneIcon"))
	c.check("もう一度アイコンを押すと閉じる", root.overlay == "" and root.pane_morning.visible)
	AutoplayPress.press(root.left.get_node("%LogIcon"))
	var log_pane: UiPaneLog = root.pane_log
	c.check("ログのアイコン：右の枠に会話ログ（今日の会話の行）", log_pane.visible and log_pane.get_node("%Header/Title").text == "会話ログ"
		and log_pane.get_node("%Content").get_child_count() == s.talk_log_entries().size() and s.talk_log_entries().size() >= 1)
	AutoplayPress.press(log_pane.get_node("%CloseButton"))
	c.check("ログの「閉じる」で戻る", root.overlay == "" and root.pane_morning.visible)
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
	return c.finish()


class AutoplayPress:
	static func press(button: BaseButton) -> bool:
		if button == null or button.disabled or not button.is_visible_in_tree():
			return false
		button.pressed.emit()
		return true
