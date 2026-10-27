extends RefCounted
## タグを言葉で表示（UI準備F）の検証。表示だけの変更なので、ここでは
##   ・言葉の対応表（data/tag_words.json）：10タグすべてに言葉がある／重複しない／内部名と違う／軸（味・具）が Ingredients と合う
##   ・全材料のタグに言葉がある（材料を足してタグの言葉を忘れると失敗する）
##   ・表示に内部名（HOT 等）が残っていない：札（UiTagChips）・具材ボタン・椀の枠・市場の商品の行・「いつもの」「今日」の欄
##   ・対応表を直すと、全部の札が変わる（データ1つ）
## を見る。内部名そのもの（Judge・SaleRule・保存・ログ・自動試遊）は変えていないので、ここでは見ない（既存のスイートが見る）。

const ALL_TAGS := ["MELLOW", "HOT", "SOUR", "BITTER", "SAVORY", "FILLING", "POWER", "GENTLE", "BITE", "TREAT"]


func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)


## 子孫の Label の文字を全部集める（札・名前・数など。内部名が混ざっていないかを見る）。
func _all_texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for child in node.get_children():
		_all_texts(child, out)
	return out


func _has_internal(texts: Array) -> String:
	for text in texts:
		for tag in ALL_TAGS:
			if str(text).contains(tag):
				return "%s ← %s" % [tag, text]
	return ""


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	TagWords.clear_cache()

	# --- 1. 対応表 ---
	var all := TagWords.all_tags()
	c.check("対応表のタグは10個で、内部名は仕様どおり（味5・具5）", all.size() == 10 and all.all(func(tag): return ALL_TAGS.has(tag)), str(all))
	var missing: Array = []
	var words: Array = []
	for tag in ALL_TAGS:
		var word := TagWords.word(tag)
		if word == "" or word == tag:
			missing.append(tag)
		words.append(word)
	c.check("10タグすべてに言葉がある（空・内部名のままではない）", missing.is_empty(), str(missing))
	var unique := {}
	for word in words:
		unique[word] = true
	c.check("言葉は重複しない", unique.size() == 10, str(words))
	c.check("言葉の仮案どおり（味：まろやか・辛い・酸っぱい・苦い・うましお／具：腹もち・スタミナ・やさしい・歯ごたえ・ごちそう）",
		words == ["まろやか", "辛い", "酸っぱい", "苦い", "うましお", "腹もち", "スタミナ", "やさしい", "歯ごたえ", "ごちそう"], str(words))
	var flavor_ok := true
	for tag in Ingredients._FLAVOR_TAGS:
		flavor_ok = flavor_ok and TagWords.kind(tag) == "flavor"
	for tag in Ingredients._TOPPING_TAGS:
		flavor_ok = flavor_ok and TagWords.kind(tag) == "topping"
	c.check("軸（味＝flavor・具＝topping）は Ingredients の味タグ・具タグと同じ分け方", flavor_ok)
	c.check("知らないタグは内部名のまま返す（空にしない）・軸は空", TagWords.word("XYZ") == "XYZ" and TagWords.kind("XYZ") == "")
	c.check("joined：辛い・スタミナ", TagWords.joined(["HOT", "POWER"]) == "辛い・スタミナ" and TagWords.joined([]) == "")

	# --- 2. 全材料のタグに言葉がある ---
	var bad_ing: Array = []
	var multi: Array = []
	for id in Ingredients._TAGS:
		var tags: Array = Ingredients.tags_for(str(id))
		if tags.is_empty():
			bad_ing.append(id)
		if tags.size() > 1:
			multi.append(id)
		for tag in tags:
			if TagWords.kind(str(tag)) == "" or TagWords.word(str(tag)) == str(tag):
				bad_ing.append("%s:%s" % [id, tag])
	c.check("全材料（%d品）のタグに言葉がある" % Ingredients._TAGS.size(), bad_ing.is_empty() and Ingredients._TAGS.size() == 17, str(bad_ing))
	c.check("タグが複数ある材料は tendon_meat だけ（POWER・BITE）", multi == ["tendon_meat"] and Ingredients.tags_for("tendon_meat") == ["POWER", "BITE"], str(multi))

	# --- 3. 札（UiTagChips）---
	var chip := UiTagChips.make("HOT")
	c.check("味の札：言葉・味の色の見た目", chip.text == "辛い" and chip.theme_type_variation == &"LabelTagFlavor")
	var chip2 := UiTagChips.make("POWER")
	c.check("具の札：言葉・具の色の見た目（味と別の系統）", chip2.text == "スタミナ" and chip2.theme_type_variation == &"LabelTagTopping")
	var small := UiTagChips.make("SOUR", true)
	var small2 := UiTagChips.make("TREAT", true)
	c.check("狭い所用の札：同じ軸の色・小さい版", small.theme_type_variation == &"LabelTagFlavorSmall" and small2.theme_type_variation == &"LabelTagToppingSmall")
	var theme: Theme = load("res://resources/ui_theme.tres")
	var kinds_ok := true
	for v in ["LabelTagFlavor", "LabelTagTopping", "LabelTagFlavorSmall", "LabelTagToppingSmall"]:
		kinds_ok = kinds_ok and theme.get_type_list().has(v)
	c.check("テーマに札の4種（味・具 × 通常・小）がある", kinds_ok)
	var flavor_color: Color = theme.get_color("font_color", "LabelTagFlavor")
	var topping_color: Color = theme.get_color("font_color", "LabelTagTopping")
	c.check("味の札と具の札は色が違う（2系統）・通常と小は同じ色", not flavor_color.is_equal_approx(topping_color)
		and flavor_color.is_equal_approx(theme.get_color("font_color", "LabelTagFlavorSmall"))
		and topping_color.is_equal_approx(theme.get_color("font_color", "LabelTagToppingSmall")))
	var box := HBoxContainer.new()
	t.root.add_child(box)
	UiTagChips.fill(box, ["POWER", "BITE"])
	c.check("fill：その並びの札だけになる（2つ）・もう一度 fill すると入れ替わる", box.get_child_count() == 2)
	UiTagChips.fill(box, [])
	c.check("fill：空なら札なし", box.get_children().filter(func(n): return not n.is_queued_for_deletion()).is_empty())
	box.queue_free()

	# --- 4. 市場の商品の行 ---
	var row: UiGoodsRow = load("res://scenes/ui/goods_row.tscn").instantiate()
	row.theme = theme
	t.root.add_child(row)
	row.show_good({ "item": "tendon_meat", "label": Ingredients.name_for("tendon_meat"), "count": 1, "unit_price": 12, "fresh": 0, "damaged": 0,
		"price": 12, "affordable": true }, true)
	_sort(row)
	var row_texts := _all_texts(row)
	c.check("商品の行（腱肉）：タグの言葉が2つ（スタミナ・歯ごたえ）出る・内部名は出ない",
		row_texts.has("スタミナ") and row_texts.has("歯ごたえ") and _has_internal(row_texts) == "", str(row_texts))
	row.queue_free()
	# 品名が長い行（ココナッツミルク＋まろやか＋腐る など）も、全材料で、品名・札・「腐る」が1行（横）におさまる
	# （横だけ見る：headless は文字の高さが実機と違う。実機の見た目は画面の写真で確かめた）
	var worst := ""
	for id in Ingredients._TAGS:
		var r_row: UiGoodsRow = load("res://scenes/ui/goods_row.tscn").instantiate()
		r_row.theme = theme   # 本番と同じテーマ（無いと文字が16pxになって幅が変わる）
		t.root.add_child(r_row)
		r_row.show_good({ "item": str(id), "label": Ingredients.name_for(str(id)), "count": 1, "unit_price": 12, "fresh": 0, "damaged": 0,
			"price": 120, "affordable": true }, true)
		_sort(r_row)
		var tags_box: HBoxContainer = r_row.get_node("Tags")
		var price_x: float = (r_row.get_node("Price") as Label).get_global_rect().end.x - (r_row.get_node("Price") as Label).get_minimum_size().x
		for child in tags_box.get_children():
			if child is Control and (child as Control).visible:
				var cr: Rect2 = (child as Control).get_global_rect()
				if cr.end.x > tags_box.get_global_rect().end.x + 1.0 or cr.end.x > price_x - 2.0:
					worst = "%s: %s 右端 %d（枠の右端 %d・価格の左端 %d）" % [id, str((child as Label).text), cr.end.x, tags_box.get_global_rect().end.x, price_x]
		r_row.queue_free()
	c.check("商品の行：全材料で、品名・札・「腐る」が横におさまり、価格（3桁）にかからない", worst == "", worst)
	var row2: UiGoodsRow = load("res://scenes/ui/goods_row.tscn").instantiate()
	t.root.add_child(row2)
	row2.show_good({ "item": "", "label": "水", "count": 1, "unit_price": 1, "fresh": 0, "damaged": 0, "price": 1, "affordable": true }, true)
	c.check("材料でない商品（水など）には札が出ない", _all_texts(row2).filter(func(s): return ["辛い", "スタミナ"].has(s)).is_empty())
	row2.queue_free()

	# --- 5. 具材ボタン ---
	var all_ok := true
	var shown := ""
	for id in Ingredients._TAGS:
		var button: UiIngredientButton = load("res://scenes/ui/ingredient_button.tscn").instantiate()
		t.root.add_child(button)
		button.show_item(str(id), 2, 0, true, false)
		var texts := _all_texts(button)
		var want: Array = TagWords.words(Ingredients.tags_for(str(id)))
		var got: Array = (button.get_node("MainButton/Chips") as Node).get_children().map(func(n): return (n as Label).text)
		if got != want or _has_internal(texts) != "":
			all_ok = false
			shown = "%s: %s / %s" % [id, str(got), str(texts)]
		button.queue_free()
	c.check("具材ボタン：全材料で、そのタグの言葉の札が全部出る・内部名は出ない", all_ok, shown)

	# --- 6. 椀の枠・「いつもの」「今日」の欄（本番のルート）---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["offal", "nam_prik_pao", "tendon_meat", "tofu"]:
		GameState.add_inventory(id, 4)
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
	var top: UiKaitenTopping = root.pane_kaiten.topping
	c.check("開店の操作エリア（トッピング）を取れた", top != null)
	if top != null:
		top.refresh()
		_sort(top)
		var order_chips: Array = []
		for path in ["%UsualChips", "%TodayChips"]:
			for ch in (top.get_node(path) as Node).get_children():
				order_chips.append((ch as Label).text)
		var card: Dictionary = s.order_card_view()
		var expect: Array = []
		if bool(card.get("usual_known", false)):
			expect.append_array(TagWords.words(card["base"]))
		if bool(card.get("today_known", false)):
			expect.append_array(TagWords.words(card["today"]))
		c.check("「いつもの」「今日」の欄：札は言葉（card の base・today と同じ並び）・内部名は出ない",
			order_chips == expect and _has_internal(_all_texts(top)) == "", "%s / %s" % [str(order_chips), str(expect)])
		# 椀に入れて、枠の札を見る
		var pressed := false
		var grid: GridContainer = top.get_node("%Grid")
		for b in grid.get_children():
			var ib: UiIngredientButton = b
			if ib.visible and ib.get_node("MainButton/Name").text.contains(UiLabels.short_name("tendon_meat")):
				pressed = true
				(ib.get_node("MainButton") as Button).pressed.emit()
		if pressed:
			top.refresh()
			_sort(top)
			var slot1_chips: Array = []
			for ch in (top.get_node("%Slots/Slot1/Chips") as Node).get_children():
				if not ch.is_queued_for_deletion():
					slot1_chips.append((ch as Label).text)
			c.check("椀の枠：入れた材料のタグの言葉（腱肉＝スタミナ・歯ごたえ）が出る", slot1_chips == ["スタミナ", "歯ごたえ"], str(slot1_chips))
			c.check("椀の枠・具材ボタンを含め、内部名は出ない", _has_internal(_all_texts(top)) == "", _has_internal(_all_texts(top)))
		else:
			c.check("腱肉の具材ボタンが見つかった", false)
		# 全ページを回って、どの具材ボタンの札もおさまっている
		var fits := true
		var detail := ""
		for page in range(top.get_node("%Tabs").get_child_count()):
			var tab_button: Button = top.get_node("%Tabs").get_child(page)
			if not tab_button.visible:
				continue
			tab_button.pressed.emit()
			top.refresh()
			_sort(top)
			for b in grid.get_children():
				var ib: UiIngredientButton = b
				if not ib.visible:
					continue
				var rect: Rect2 = ib.get_global_rect()
				for ch in ib.get_node("MainButton/Chips").get_children():
					var r: Rect2 = (ch as Control).get_global_rect()
					if r.position.x < rect.position.x - 1.0 or r.end.x > rect.end.x + 1.0:   # 横だけ見る（headless は文字の高さが実機と違う）
						fits = false
						detail = "%s %s %s" % [ib.get_node("MainButton/Name").text, str((ch as Label).text), str((ch as Control).get_global_rect())]
		c.check("具材ボタン：札はボタンの中（横）におさまる（全ページ）", fits, detail)
	root.queue_free()

	# --- 7. 対応表を直すと全部の札が変わる ---
	TagWords._cache = { "flavor": { "HOT": "ピリ辛" }, "topping": { "POWER": "元気" } }
	c.check("対応表（データ）を差し替えると、札の言葉が変わる", UiTagChips.make("HOT").text == "ピリ辛" and UiTagChips.make("POWER", true).text == "元気"
		and TagWords.joined(["HOT", "POWER"]) == "ピリ辛・元気")
	TagWords.clear_cache()
	c.check("読み直すと元の対応表に戻る（ファイルが正）", TagWords.word("HOT") == "辛い")

	return c.finish()
