extends RefCounted
## UI準備Q：トッピング画面の3枠の上の見出し「いまの椀(3枠)」の文字を、鍋の行「鍋 残11杯 / 濃さ3」に替えた。
## 提供ボタンの上の鍋の小表示は消し、空いた分だけ大きい椀の絵を下へ広げた（提供ボタンの位置は今のまま）。
## 対象：鍋の行が上に出て、提供の上には出ない／濃さの数字の色（適正の内＝ふつう、0・1・5＝注意色）／
## 3枠の椀の中身の文字が、入れる・取り消すで変わる・3つまで／
## 重なり表示（いつもの・レシピ保存・モブの団体の確認）が出ている間は大きい椀の絵を隠す（重なりが優先）。
## 動き（入れる・取り消す・上限・判定）は変えない。どれもボタンの pressed だけで操作する（押せないボタンは押さない）。


func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _press(button: BaseButton) -> bool:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


## 本番UIのルートを起動し、客の1杯目の入力待ち（ADJUST）まで進める（tests/ui_kaiten_test.gd と同じ形）。
func _open_root(t: SceneTree, customers: Array, stock: Dictionary, strength: int = 3) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in stock:
		GameState.add_inventory(id, int(stock[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, strength, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	root.close_overlay()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	_sort(root)
	return root


## kind の最初のタブを開き、短縮名が name の具材ボタン。
func _item(top: UiKaitenTopping, kind_title: String, name: String) -> UiIngredientButton:
	for tab in top.get_node("%Tabs").get_children():
		if (tab as Button).visible and (tab as Button).text.begins_with(kind_title):
			_press(tab)
			break
	for item in top.get_node("%Grid").get_children():
		if (item as Control).visible and str(item.get_node("MainButton/Name").text) == name:
			return item
	return null


## node の下にある、見えている Label のうち、文が「鍋 残」で始まるもの。
func _pot_labels(node: Node, out: Array) -> Array:
	for child in node.get_children():
		_pot_labels(child, out)
	if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text.begins_with("鍋 残"):
		out.append(node)
	return out


func _bowl_shown(top: UiKaitenTopping) -> bool:
	return top.get_node("BowlArt").is_visible_in_tree()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 鍋の行は上（注文カードの下・案内文の上）に1か所だけ ---
	var root := _open_root(t, ["officer"], { "nam_prik_pao": 9, "offal": 9, "coconut_milk": 9, "tofu": 9 })
	var s: PlaySession = root.session
	var top: UiKaitenTopping = root.pane_kaiten.topping
	var warn: Color = top.get_theme_color(&"warn", &"UiPalette")
	var line: Control = top.get_node("%PotLine")
	var penalty: Control = top.get_node("%Penalty")
	c.check("鍋の行：「鍋 残999杯 / 濃さ3」", line.is_visible_in_tree()
		and top.get_node("%PotText").text + top.get_node("%PotStrength").text == "鍋 残999杯 / 濃さ3")
	c.check("鍋の行は上の段：今日の欄の下・3枠の上（元の見出し「いまの椀(3枠)」の位置）",
		line.get_global_rect().position.y >= top.get_node("%TodayRow").get_global_rect().end.y
			and line.get_global_rect().position.y < top.get_node("%Slots").get_global_rect().position.y, str(line.get_global_rect()))
	var has_caption := false
	for child in top.get_children():
		if child is Label and (child as Label).text.begins_with("いまの椀"):
			has_caption = true
	c.check("見出し「いまの椀(3枠)」の文字は無い（3枠そのものは残す）", not has_caption and top.get_node("%Slots").is_visible_in_tree())
	var labels := _pot_labels(top, [])
	c.check("「鍋 残…」の文は上の1か所だけ（提供の上の小表示は無い）",
		labels.size() == 1 and labels[0] == top.get_node("%PotText") and not top.has_node("%PotMini"), str(labels.size()))
	var serve_y: float = top.get_node("%ServeButton").get_global_rect().position.y
	c.check("提供ボタンのすぐ上に鍋の行は無い（鍋の行は提供より300以上上）", serve_y - line.get_global_rect().end.y > 300.0)
	var art: Control = top.get_node("BowlArt")
	c.check("大きい椀の絵は下へ広げた（高さ143。下端は提供ボタンの10上）・提供ボタンの位置は今のまま (852,595)",
		absf(art.size.y - 143.0) < 1.0 and absf(serve_y - art.get_global_rect().end.y - 10.0) < 1.0
			and top.get_node("%ServeButton").get_global_position().distance_to(Vector2(852, 595)) < 1.0, str(art.get_global_rect()))
	c.check("案内文は今のまま（空の椀：「味付けと具を選んでください」）",
		(penalty as RichTextLabel).get_parsed_text() == "味付けと具を選んでください")

	# --- 2. 濃さの数字の色：適正（2〜4）はふつう、0・1・5は注意色（鍋タブの目盛りと同じ線引き）---
	var strength_label: Label = top.get_node("%PotStrength")
	var text_label: Label = top.get_node("%PotText")
	for value in [0, 1, 2, 3, 4, 5]:
		GameState.soup["strength"] = value
		s.notify_changed()
		var outside: bool = value <= GameState.STRENGTH_HARD_FLOOR or value == GameState.STRENGTH_MIN or value == GameState.STRENGTH_MAX
		var color := strength_label.get_theme_color(&"font_color")
		var ok := strength_label.text == str(value) and (color.is_equal_approx(warn) if outside else not color.is_equal_approx(warn))
		c.check("濃さ%d：数字は%s（「鍋 残」の文はふつうの色のまま）" % [value, "注意色" if outside else "ふつうの色"],
			ok and not text_label.get_theme_color(&"font_color").is_equal_approx(warn), str(color))
	c.check("色の線引きは鍋タブと同じ（0・1・5が外）", UiKaitenTopping.strength_outside_fit(0, s.pot_view())
		and UiKaitenTopping.strength_outside_fit(1, s.pot_view()) and UiKaitenTopping.strength_outside_fit(5, s.pot_view())
		and not UiKaitenTopping.strength_outside_fit(2, s.pot_view()) and not UiKaitenTopping.strength_outside_fit(4, s.pot_view()))
	GameState.soup["strength"] = 3
	s.notify_changed()

	# --- 3. 3枠の椀の中身の文字：入れる・取り消すで変わる、3つまで ---
	c.check("空の椀：3枠とも空", top.bowl_text() == "" and top.get_node("%Slots/Slot1/Label").text == ""
		and top.get_node("%Slots/Slot3").theme_type_variation == &"PanelSlotEmpty" and _bowl_shown(top))
	_press(_item(top, "具材", "モツ").get_node("MainButton"))
	c.check("モツを入れる → 1枠目「モツ」", top.bowl_text() == "モツ" and top.get_node("%Slots/Slot1/Label").text == "モツ"
		and top.get_node("%Slots/Slot2/Label").text == "", top.bowl_text())
	_press(_item(top, "調味料", "ナムプリ").get_node("MainButton"))
	c.check("ナムプリを入れる → 「モツ・ナムプリ」", top.bowl_text() == "モツ・ナムプリ", top.bowl_text())
	_press(_item(top, "具材", "豆腐").get_node("MainButton"))
	c.check("豆腐を入れる → 「モツ・ナムプリ・豆腐」（3つ）", top.bowl_text() == "モツ・ナムプリ・豆腐", top.bowl_text())
	var coco := _item(top, "調味料", "ココナツ")
	_press(coco.get_node("MainButton"))
	c.check("4つ目は入らない（上限3は今のまま）", s.bowl_view()["additions"].size() == 3 and top.bowl_text() == "モツ・ナムプリ・豆腐",
		top.bowl_text())
	_press(_item(top, "具材", "モツ").get_node("MainButton"))
	c.check("モツを取り消す → 「ナムプリ・豆腐」（枠が詰まる）", s.bowl_view()["additions"] == ["nam_prik_pao", "tofu"]
		and top.bowl_text() == "ナムプリ・豆腐" and top.get_node("%Slots/Slot3/Label").text == "", top.bowl_text())
	_press(top.get_node("%DiscardButton"))
	c.check("一杯を捨てる → 椀の文字は空に戻る", top.bowl_text() == "" and s.bowl_view()["additions"].is_empty())

	# --- 4. 重なり表示の優先：「いつもの」の中身が出ている間は椀を隠す ---
	GameState.saved_recipes = [{ "name": "試しの一杯", "ingredients": ["nam_prik_pao", "offal"] }]
	s.notify_changed()
	_press(top.get_node("%UsualButton"))
	c.check("いつもの を開く → 中身の一覧が出て、大きい椀の絵は隠れる", top.get_node("%RecipeMenu").is_visible_in_tree() and not _bowl_shown(top))
	var menu: GridContainer = top.get_node("%RecipeButtons")
	for b in menu.get_children():
		if (b as Button).visible and (b as Button).text == "閉じる":
			_press(b)
			break
	c.check("閉じる → 大きい椀の絵が戻る", not top.get_node("%RecipeMenu").visible and _bowl_shown(top))
	_press(top.get_node("%UsualButton"))
	_press(menu.get_child(0))
	c.check("レシピを選ぶ → 一覧は閉じ、3枠にその中身（「ナムプリ・モツ」）", not top.get_node("%RecipeMenu").visible and _bowl_shown(top)
		and top.bowl_text() == "ナムプリ・モツ", top.bowl_text())

	# --- 5. 重なり表示の優先：レシピ保存（枠を選ぶ・名前を選ぶ）の間は椀を隠す ---
	_press(top.get_node("%ServeButton"))
	var guard := 0
	while not s.can_save_recipe() and s.can_next_event() and guard < 10:
		guard += 1
		root.left.advance()
	_press(root.pane_kaiten.get_node("%ToppingTab"))
	_press(top.get_node("%SaveButton"))
	c.check("レシピ保存 → 枠を選ぶ一覧が出て、大きい椀の絵は隠れる", s.recipe_save_view()["stage"] == "slot"
		and top.get_node("%RecipeMenu").is_visible_in_tree() and not _bowl_shown(top))
	var last := menu.get_child(0)
	for b in menu.get_children():
		if (b as Button).visible and (b as Button).text == "やめる":
			last = b
	_press(last)
	c.check("やめる → 大きい椀の絵が戻る", s.recipe_save_view()["stage"] == "" and not top.get_node("%RecipeMenu").visible and _bowl_shown(top))
	GameState.saved_recipes = []
	root.queue_free()

	# --- 6. 重なり表示の優先：モブの団体の確認（いちばん上）の間は椀を隠す ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	s = root.session
	top = root.pane_kaiten.topping
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("meat_ball", 3)
	GameState.add_inventory("nam_prik_pao", 10)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	GameState.today_plan["mob_instances"]["mob_ui"] = { "type": "dock_workers", "count": 4 }
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["mob_ui"] }])
	s.load_current_customer()
	root.close_overlay()
	s.notify_changed()
	guard = 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	var grid: GridContainer = top.get_node("%Grid")
	_press(grid.get_child(0).get_node("MainButton"))   # 肉団子（具材の1つ目）
	_press(top.get_node("%Tabs").get_child(1))
	_press(grid.get_child(0).get_node("MainButton"))   # ナムプリ
	c.check("モブ：確認の前は大きい椀の絵が見え、3枠は「肉団子・ナムプリ」", _bowl_shown(top) and top.bowl_text() == "肉団子・ナムプリ", top.bowl_text())
	_press(top.get_node("%ServeButton"))
	c.check("団体の確認が出ている間は、大きい椀の絵も「いつもの」の一覧も隠れる（確認がいちばん上）",
		top.get_node("%GroupBox").is_visible_in_tree() and not _bowl_shown(top) and not top.get_node("%RecipeMenu").visible)
	c.check("団体の確認の間も鍋の行は上に出たまま", top.get_node("%PotLine").is_visible_in_tree())
	_press(top.get_node("%GroupServe"))
	_press(root.pane_kaiten.get_node("%ToppingTab"))
	c.check("確認を閉じる → 大きい椀の絵は隠れたままにならない", not top.get_node("%GroupBox").is_visible_in_tree()
		and top.get_node("BowlArt").visible)
	root.queue_free()

	return c.finish()
