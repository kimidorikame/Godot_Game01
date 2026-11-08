extends RefCounted
## UI準備Q：3枠の上の見出し「いまの椀(3枠)」をやめ、提供ボタンの上の鍋の小表示は消した（2か所に出さない）。
## UI準備S：鍋の行「鍋 残11杯 / 濃さ3」の文字をやめ、3枠の右の鍋の小さな絵（UiPotGauge）にした。量＝残りの杯数（容量に対する割合）、
## 色＝濃さ（薄い→濃い。0は水のような色）、濃さが適正の外（0・1・5）なら縁を注意色。数字は出さない（正確な値は鍋タブ）。
## 対象：鍋の絵の位置・量・色・注意／「鍋 残…」の文字が無い／大きい椀の絵を広げた（提供ボタンの位置は今のまま）／
## 3枠の椀の中身の文字が、入れる・取り消すで変わる・3つまで／モブの団体の確認が出ている間は大きい椀の絵を隠す。
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


## node の下にある、見えている Label のうち、文が「鍋 残」で始まるもの（UI準備Sで無くした）。
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

	# --- 1. 鍋の小さな絵は3枠の右（同じ段）。「鍋 残…」の文字は無い ---
	var root := _open_root(t, ["officer"], { "nam_prik_pao": 9, "offal": 9, "coconut_milk": 9, "tofu": 9 })
	var s: PlaySession = root.session
	var top: UiKaitenTopping = root.pane_kaiten.topping
	var gauge: UiPotGauge = top.get_node("%PotGauge")
	var penalty: Control = top.get_node("%Penalty")
	var slots_rect: Rect2 = top.get_node("%Slots").get_global_rect()
	var gauge_rect := gauge.get_global_rect()
	c.check("鍋の絵は3枠の右・同じ段（3枠と重ならない）", gauge.is_visible_in_tree() and gauge_rect.position.x >= slots_rect.end.x
		and gauge_rect.position.y <= slots_rect.position.y + 0.5 and gauge_rect.end.y >= slots_rect.end.y - 0.5, "%s / %s" % [str(gauge_rect), str(slots_rect)])
	c.check("鍋の絵は好物の行の下・案内文の上", gauge_rect.position.y >= top.get_node("%FavoriteRow").get_global_rect().end.y - 0.5
		and gauge_rect.end.y <= penalty.get_global_rect().position.y + 0.5)
	var has_caption := false
	for child in top.get_children():
		if child is Label and (child as Label).text.begins_with("いまの椀"):
			has_caption = true
	c.check("見出し「いまの椀(3枠)」の文字は無い（3枠そのものは残す）", not has_caption and top.get_node("%Slots").is_visible_in_tree())
	c.check("「鍋 残…」の文字はどこにも無い（鍋の行・提供の上の小表示とも）", _pot_labels(top, []).is_empty() and not top.has_node("%PotLine")
		and not top.has_node("%PotMini"))
	var serve_y: float = top.get_node("%ServeButton").get_global_rect().position.y
	var art: Control = top.get_node("BowlArt")
	c.check("大きい椀の絵は上へ広げた（高さ177。下端は提供ボタンの10上）・提供ボタンの位置は今のまま (852,595)",
		absf(art.size.y - 177.0) < 1.0 and absf(serve_y - art.get_global_rect().end.y - 10.0) < 1.0
			and top.get_node("%ServeButton").get_global_position().distance_to(Vector2(852, 595)) < 1.0, str(art.get_global_rect()))
	c.check("案内文は今のまま（空の椀：「味付けと具を選んでください」）",
		(penalty as RichTextLabel).get_parsed_text() == "味付けと具を選んでください")

	# --- 2. 量＝残りの杯数（容量に対する割合）・色＝濃さ・適正の外は縁を注意色 ---
	var capacity := Rules.pot_capacity()
	c.check("残り999杯（容量%d を超える）：満杯" % capacity, gauge.exists and is_equal_approx(gauge.fill_ratio, 1.0), str(gauge.fill_ratio))
	var ratios := []
	for remaining in [capacity, capacity / 2, 1, 0]:
		GameState.soup["remaining_servings"] = remaining
		s.notify_changed()
		ratios.append(gauge.fill_ratio)
	c.check("量：満杯 → 半分 → 1杯（少しだけ）→ 0（空）", is_equal_approx(ratios[0], 1.0) and absf(ratios[1] - float(capacity / 2) / capacity) < 0.001
		and ratios[2] > 0.0 and ratios[2] < 0.2 and ratios[3] == 0.0, str(ratios))
	c.check("割合の計算：容量を超えたら1・容量が分からなければ残りがあれば1", UiPotGauge.ratio_for(30, 12) == 1.0 and UiPotGauge.ratio_for(3, 0) == 1.0
		and UiPotGauge.ratio_for(0, 0) == 0.0)
	GameState.soup["remaining_servings"] = 999
	var colors := {}
	var warns := {}
	for value in [0, 1, 2, 3, 4, 5]:
		GameState.soup["strength"] = value
		s.notify_changed()
		colors[value] = gauge.fill_color
		warns[value] = gauge.warn
	var darker := true
	for value in [2, 3, 4, 5]:
		darker = darker and (colors[value] as Color).get_luminance() < (colors[value - 1] as Color).get_luminance()
	c.check("色＝濃さ：濃さ1→5で濃い色になる", darker, str(colors))
	c.check("濃さ0（出せない）は水のような色（ほかと違う）", (colors[0] as Color).is_equal_approx(UiPotGauge.WATERY) and not (colors[1] as Color).is_equal_approx(UiPotGauge.WATERY))
	c.check("縁の注意色は適正の外（0・1・5）だけ（鍋タブ・案内文と同じ線引き）", warns[0] and warns[1] and warns[5] and not warns[2] and not warns[3] and not warns[4], str(warns))
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
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	var grid: GridContainer = top.get_node("%Grid")
	_press(grid.get_child(0).get_node("MainButton"))   # 肉団子（具材の1つ目）
	_press(top.get_node("%Tabs").get_child(0))   # 調味料（UI準備S：調味料が先）
	_press(grid.get_child(0).get_node("MainButton"))   # ナムプリ
	c.check("モブ：確認の前は大きい椀の絵が見え、3枠は「肉団子・ナムプリ」", _bowl_shown(top) and top.bowl_text() == "肉団子・ナムプリ", top.bowl_text())
	_press(top.get_node("%ServeButton"))
	c.check("団体の確認が出ている間は、大きい椀の絵は隠れる（確認がいちばん上）",
		top.get_node("%GroupBox").is_visible_in_tree() and not _bowl_shown(top))
	c.check("団体の確認の間も鍋の絵は上に出たまま", top.get_node("%PotGauge").is_visible_in_tree())
	_press(top.get_node("%GroupServe"))
	_press(root.pane_kaiten.get_node("%ToppingTab"))
	c.check("確認を閉じる → 大きい椀の絵は隠れたままにならない", not top.get_node("%GroupBox").is_visible_in_tree()
		and top.get_node("BowlArt").visible)
	root.queue_free()

	return c.finish()
