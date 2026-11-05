extends RefCounted
## UI準備P：夜の具材選び（開店のトッピング）の案内文と、取り消し・捨てるの見分け。
## 対象：案内文の6つの状態（文と色）、入れた具材の「×」の印（押すと外れる）、下段のボタンの文言と区切り。
## 判定・減点の計算は変えない（sale_hint の理由コードのまま。ここでは文と色だけを見る）。
## どれもボタンの pressed だけで操作する（押せないボタンは押さない）。

const NEUTRAL := "[color=#e8ebf0]"   # ふつうの文字色（UiPalette.text）
const WARN := "[color=#ff8a7a]"      # 注意色（UiPalette.warn）


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


## 傷んだ在庫を足す（購入日を2日前にしたバッチ＝3日目で傷み）。tests/ui_kaiten_test.gd と同じ。
func _add_damaged(item: String, count: int) -> void:
	GameState.inventory[item] = int(GameState.inventory.get(item, 0)) + count
	var batches: Array = GameState.perishable_batches.get(item, [])
	batches.push_front({ "day": GameState.day_count - 2, "count": count, "unit_price": 8 })
	GameState.perishable_batches[item] = batches


## 本番UIのルートを起動し、新人警官の1杯目の入力待ち（ADJUST）まで進める（tests/ui_kaiten_test.gd と同じ形）。
func _open_root(t: SceneTree, stock: Dictionary, damaged: Dictionary = {}) -> UiGameRoot:
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
	for id in damaged:
		_add_damaged(id, int(damaged[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	root.close_overlay()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	_sort(root)
	return root


## いまのタブ（kind の最初のタブを開く）で、短縮名が name の具材ボタン。
func _item(top: UiKaitenTopping, kind_title: String, name: String) -> UiIngredientButton:
	for tab in top.get_node("%Tabs").get_children():
		if (tab as Button).visible and (tab as Button).text.begins_with(kind_title):
			_press(tab)
			break
	for item in top.get_node("%Grid").get_children():
		if (item as Control).visible and str(item.get_node("MainButton/Name").text) == name:
			return item
	return null


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 何も選んでいない → 具だけ → 味だけ（中立の色）---
	var root := _open_root(t, { "nam_prik_pao": 9, "offal": 9 })
	var s: PlaySession = root.session
	var top: UiKaitenTopping = root.pane_kaiten.topping
	var penalty: RichTextLabel = top.get_node("%Penalty")
	c.check("まだ何も選んでいない：「味付けと具を選んでください」（ふつうの文字色）",
		penalty.get_parsed_text() == "味付けと具を選んでください" and penalty.text.begins_with(NEUTRAL) and not penalty.text.contains(WARN), penalty.text)
	var offal := _item(top, "具材", "モツ")
	_press(offal.get_node("MainButton"))
	c.check("具だけ入っている：「味付けを選んでください」（ふつうの文字色）",
		s.bowl_view()["additions"] == ["offal"] and penalty.get_parsed_text() == "味付けを選んでください" and penalty.text.begins_with(NEUTRAL), penalty.text)
	c.check("入れた具材のボタンに「×」の印が付く（名前はそのまま・押せる）", (offal.get_node("MainButton/RemoveMark") as Label).visible
		and offal.get_node("MainButton/Name").text == "モツ" and not (offal.get_node("MainButton") as Button).disabled)
	_press(offal.get_node("MainButton"))
	c.check("「×」の付いたボタンをもう一度押す → 椀から外れ、印が消える（動きは toggle_ingredient のまま）",
		s.bowl_view()["additions"].is_empty() and not (offal.get_node("MainButton/RemoveMark") as Label).visible
			and penalty.get_parsed_text() == "味付けと具を選んでください")
	var nam := _item(top, "調味料", "ナムプリ")
	_press(nam.get_node("MainButton"))
	c.check("味だけ入っている：「具を選んでください」（ふつうの文字色）",
		s.bowl_view()["additions"] == ["nam_prik_pao"] and penalty.get_parsed_text() == "具を選んでください" and penalty.text.begins_with(NEUTRAL), penalty.text)
	c.check("調味料のボタンにも「×」の印", (nam.get_node("MainButton/RemoveMark") as Label).visible)
	offal = _item(top, "具材", "モツ")
	_press(offal.get_node("MainButton"))
	c.check("味と具がそろって減点も無い：「減点の予告: いまのところ減点なし」（色を付けない）",
		penalty.get_parsed_text() == "減点の予告: いまのところ減点なし" and not penalty.text.contains("[color="), penalty.text)
	# 濃さの減点：今の文のまま（注意色）
	GameState.soup["strength"] = GameState.STRENGTH_MIN
	s.notify_changed()
	c.check("濃さの減点：今の文のまま「減点の予告: 濃さ1で1段階下がります。」（注意色）",
		penalty.get_parsed_text().begins_with("減点の予告: 濃さ%dで1段階下がります。" % GameState.STRENGTH_MIN) and penalty.text.begins_with(WARN), penalty.text)
	GameState.soup["strength"] = 3
	s.notify_changed()
	# 下段のボタン：文言と区切り
	c.check("下段のボタンの文言：いつもの・レシピ保存・一杯を捨てる・断る",
		top.get_node("%UsualButton").text == "いつもの" and top.get_node("%SaveButton").text == "レシピ保存"
			and top.get_node("%DiscardButton").text == "一杯を捨てる" and top.get_node("%DeclineButton").text == "断る")
	var save_end: float = top.get_node("%SaveButton").get_global_rect().end.x
	var discard_x: float = top.get_node("%DiscardButton").get_global_rect().position.x
	var usual_gap: float = top.get_node("%SaveButton").get_global_rect().position.x - top.get_node("%UsualButton").get_global_rect().end.x
	c.check("一杯を捨てる・断るは、いつもの・レシピ保存から離す（間隔がほかの倍以上・間に区切り線）",
		discard_x - save_end >= usual_gap * 2.0 and top.get_node("%BottomDivider").visible, "%d / %d" % [discard_x - save_end, usual_gap])
	var discards := s.bowl_discard_count
	_press(top.get_node("%DiscardButton"))
	c.check("一杯を捨てる：椀が空に戻る（動きは今までどおり。確認の窓は無い）",
		s.bowl_view()["additions"].is_empty() and s.bowl_discard_count == discards + 1 and top.is_adjusting())
	root.queue_free()

	# --- 2. 必要な分類の在庫が1つも無い（注意色）---
	root = _open_root(t, { "offal": 9 })
	top = root.pane_kaiten.topping
	penalty = top.get_node("%Penalty")
	c.check("味付けの在庫が無い・椀が空：「味付けの在庫がありません」（注意色）に続けて「具を選んでください」（ふつうの文字色）",
		penalty.get_parsed_text() == "味付けの在庫がありません　具を選んでください" and penalty.text.begins_with(WARN)
			and penalty.text.contains(NEUTRAL + "具を選んでください"), penalty.text)
	_press(_item(top, "具材", "モツ").get_node("MainButton"))
	c.check("味付けの在庫が無い・具は入れた：「味付けの在庫がありません」だけ（注意色）",
		penalty.get_parsed_text() == "味付けの在庫がありません" and penalty.text.begins_with(WARN) and not penalty.text.contains(NEUTRAL), penalty.text)
	root.queue_free()

	root = _open_root(t, { "nam_prik_pao": 9 })
	top = root.pane_kaiten.topping
	penalty = top.get_node("%Penalty")
	_press(_item(top, "調味料", "ナムプリ").get_node("MainButton"))
	c.check("具の在庫が無い・味は入れた：「具の在庫がありません」（注意色）",
		penalty.get_parsed_text() == "具の在庫がありません" and penalty.text.begins_with(WARN), penalty.text)
	root.queue_free()

	root = _open_root(t, {})
	top = root.pane_kaiten.topping
	penalty = top.get_node("%Penalty")
	c.check("どちらの在庫も無い：「味付けと具の在庫がありません」（注意色）",
		penalty.get_parsed_text() == "味付けと具の在庫がありません" and penalty.text.begins_with(WARN), penalty.text)
	root.queue_free()

	# --- 3. 傷んだ食材を入れた（注意色）---
	root = _open_root(t, { "nam_prik_pao": 9, "offal": 9 }, { "tofu": 2 })
	s = root.session
	top = root.pane_kaiten.topping
	penalty = top.get_node("%Penalty")
	var tofu := _item(top, "具材", "豆腐")
	_press(tofu.get_node("DamagedButton"))
	c.check("傷んだ具だけ入れた（味がまだ）：減点より先に「味付けを選んでください」（ふつうの文字色）",
		penalty.get_parsed_text() == "味付けを選んでください" and penalty.text.begins_with(NEUTRAL), penalty.text)
	c.check("傷んだ側で入れた具材にも「×」の印", (tofu.get_node("MainButton/RemoveMark") as Label).visible)
	_press(_item(top, "調味料", "ナムプリ").get_node("MainButton"))
	c.check("傷んだ食材を入れた：「傷んだ豆腐を使用中：評価が1段階下がります」（注意色）",
		penalty.get_parsed_text() == "傷んだ豆腐を使用中：評価が1段階下がります" and penalty.text.begins_with(WARN), penalty.text)
	c.check("判定・減点の計算は変えない：sale_hint の理由は傷み（SPOILED）だけ",
		s.sale_hint()["blockers"].is_empty() and s.sale_hint()["penalties"] == [{ "code": "SPOILED" }], str(s.sale_hint()))
	tofu = _item(top, "具材", "豆腐")
	_press(tofu.get_node("DamagedButton"))
	c.check("傷んだ豆腐をもう一度押す（右上の「傷」）→ 外れる：傷みの文は消えて「具を選んでください」",
		s.bowl_view()["additions"] == ["nam_prik_pao"] and penalty.get_parsed_text() == "具を選んでください", penalty.text)
	root.queue_free()
	return c.finish()
