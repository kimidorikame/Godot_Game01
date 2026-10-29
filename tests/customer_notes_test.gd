extends RefCounted
## 客ノート（スマホの「客」タブ。UI準備G）。出会った客の好みを見返す。
## 対象：載る条件（会っていない客・種類は載せない／名前あり客は注文を言う行を見てから）／並び（名前あり客が先・モブが後・それぞれ出会った順）／
## 来た日・好物（知った客だけ）・札2枚／モブは断った団体も載る（日次ログの mob_types_met）・旧セーブは mob_types_served で代用／
## 画面（札は言葉・内部名なし）／再挑戦・続きから（朝の封筒）／市場でスマホを開いて閉じてもかごが消えない／DMの行は差出人の種類によらず同じ見た目（UI準備I。「常連」の印なし）。


func _label_texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_label_texts(child, out)
	return out


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 会う前は空・モブの記録（断った団体も数える）・旧セーブ ---
	GameState.reset_for_new_game()
	var s0 := PlaySession.new()
	t.root.add_child(s0)
	s0.start()
	c.check("まだ誰にも会っていない朝は、載せるものがない", (s0.phone_notes()["regulars"] as Array).is_empty() and (s0.phone_notes()["mobs"] as Array).is_empty())
	GameState.today_plan = { "day": 3, "slots": [], "mob_instances": { "mob#0": { "type": "inn_clerk", "count": 2 }, "mob#1": { "type": "dock_workers", "count": 2 } }, "demand_center": 9 }
	GameState.served = [{ "customer": "mob#0", "sale": 0, "servings": 0, "declined": true, "result": "" }]
	c.check("モブは注文を受けた時点から：断った団体（提供0杯）の種類も数える", s0.mob_types_met_tonight() == ["inn_clerk"], str(s0.mob_types_met_tonight()))
	GameState.day_records = [{ "day": 1, "mob_types_served": ["dock_workers"] }, { "day": 2, "mob_types_met": ["inn_clerk", "market_porter"], "mob_types_served": ["inn_clerk"] }]
	GameState.served = []
	var mob_types: Array = (s0.phone_notes()["mobs"] as Array).map(func(m): return str(m["type"]))
	c.check("旧セーブ（mob_types_met が無い日）は提供した種類（mob_types_served）で代用・出会った順・重複なし", mob_types == ["dock_workers", "inn_clerk", "market_porter"], str(mob_types))
	GameState.day_count = 5
	GameState.customer_memory["thug"] = { "favorite_known": true, "facts": {}, "seen_episodes": [], "visits": [
		{ "day": 1, "slot": "夜半", "served": 1, "grade": "GOOD", "grades": ["GOOD"], "ingredients": [], "episode_id": "" },
		{ "day": 2, "slot": "明け方", "served": 1, "grade": "GOOD", "grades": ["GOOD"], "ingredients": [], "episode_id": "" },
		{ "day": 4, "slot": "宵の口", "served": 0, "grade": "", "grades": [], "ingredients": [], "episode_id": "" }] }
	var thug_note: Dictionary = (s0.phone_notes()["regulars"] as Array)[0]
	c.check("来た日は、来店記録の日を小さい順に全部（提供しなかった日も「来た」日）。好物を知った客は材料名が出る",
		thug_note["days"] == [1, 2, 4] and thug_note["favorite_known"] and str(thug_note["favorite"]) != "", str(thug_note))
	s0.free()

	# --- 2. 通しで遊ぶ（Day1）：載る条件・並び・好物 ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var invariant_ok := true
	var detail := ""
	var first_regular_step := -1
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 3000:
		guard += 1
		play.step()
		var notes := s.phone_notes()
		var card := s.order_card_view()
		var current := str(card.get("customer", ""))
		for item in notes["regulars"]:
			if str(item["id"]) == current and not bool(card.get("usual_known", false)):
				invariant_ok = false
				detail = "%s が注文を言う前に載った" % current
			if first_regular_step < 0:
				first_regular_step = guard
	c.check("名前あり客は、注文を言う行を見る前には載らない（見るまで「いつもの」は分からない）", invariant_ok and first_regular_step > 0, detail)
	var notes := s.phone_notes()
	var ids: Array = (notes["regulars"] as Array).map(func(r): return str(r["id"]))
	c.check("Day1のあと：名前あり客は出会った順（配達員→チンピラ→老婆）・モブも出会った順（港湾労働者→安宿の夜勤受付）",
		ids == ["delivery_man", "thug", "granny"] and (notes["mobs"] as Array).map(func(m): return str(m["type"])) == ["dock_workers", "inn_clerk"], str(ids))
	var first: Dictionary = notes["regulars"][0]
	c.check("名前あり客：名前・いつもの（2つ）・来た日（Day1）", str(first["name"]) == "配達員" and first["tags"] == ["HOT", "POWER"] and first["days"] == [1])
	var fav_ok := true
	for r in notes["regulars"]:
		fav_ok = fav_ok and bool(r["favorite_known"]) == GameState.knows_favorite(str(r["id"]))
		if bool(r["favorite_known"]):
			fav_ok = fav_ok and str(r["favorite"]) == Ingredients.name_for(str(ScheduleData.customer_profile(str(r["id"])).get("favorite", "")))
		else:
			fav_ok = fav_ok and str(r["favorite"]) == ""
	c.check("好物の材料名は、好物を知った客だけに出る", fav_ok)
	var mob_first: Dictionary = notes["mobs"][0]
	c.check("モブ：種類名と好み（その種類の注文のタグ・札2枚）", str(mob_first["name"]) == "港湾労働者" and mob_first["tags"] == Dm.mob_wanted_tags("dock_workers") and (mob_first["tags"] as Array).size() == 2)
	var record1: Dictionary = GameState.day_records[0] if not GameState.day_records.is_empty() else {}
	c.check("日の終わりに日次ログへ mob_types_met が入る（Day1の固定の編成）", record1.get("mob_types_met", []) == ["dock_workers", "inn_clerk"], str(record1.get("mob_types_met")))

	# --- 3. 画面 ---
	var phone: UiPanePhone = root.pane_phone
	phone.tab = "notes"
	phone.refresh()
	var texts := _label_texts(phone.get_node("%Content"))
	var tabs: Control = phone.get_node("%Tabs")
	c.check("タブは4つ（SNS／ニュース／レシピ／客）・客タブを開いた", tabs.get_child_count() >= 4 and (tabs.get_child(3) as Button).text == "客" and texts.has("名前あり客") and texts.has("モブ"), str(texts.slice(0, 6)))
	c.check("画面：名前・来た日（Day1）・札は言葉（辛い・スタミナ）・内部名は出ない", texts.has("配達員") and texts.has("Day1") and texts.has("辛い") and texts.has("スタミナ")
		and not texts.any(func(x): return str(x).contains("HOT") or str(x).contains("POWER")), str(texts))
	c.check("並び：名前あり客の見出し→名前あり客→モブの見出し→モブ", texts.find("名前あり客") < texts.find("配達員") and texts.find("配達員") < texts.find("モブ") and texts.find("モブ") < texts.find("港湾労働者"))
	var many_days: Dictionary = (notes["regulars"][0] as Dictionary).duplicate(true)
	many_days["days"] = [1, 2, 4]
	var days_text := "・".join(PackedStringArray((many_days["days"] as Array).map(func(d): return Calendar.label(int(d)))))
	c.check("来た日は「Day1・Day2・Day4」と並べる", days_text == "Day1・Day2・Day4")

	# --- 4. 市場でスマホを開いて閉じても、かごが消えない ---
	guard = 0
	while not (GameState.day_count == 2 and root.pane_market.visible) and guard < 500:
		guard += 1
		play.step()
	GameState.money = 1000
	s.notify_changed()
	var stalls: Control = root.pane_market.get_node("%Stalls")
	_press(stalls.get_child(3))
	var shop: UiPaneBuyShop = root.pane_buy_shop
	var goods: UiGoodsList = shop.get_node("%Goods")
	_press(goods.get_child(0).get_node("BuyButton"))
	_press(goods.get_child(1).get_node("BuyButton"))
	var in_cart: int = root.cart.count(s.market_shop)
	root.open_phone("notes")
	var opened := phone.visible and not shop.visible
	root.close_overlay()
	c.check("買い物の最中にスマホ（客タブ）を開ける・閉じると同じ店に戻り、かごは消えない",
		opened and shop.visible and s.market_shop == "tofu_noodles" and in_cart == 2 and root.cart.count(s.market_shop) == 2, "%s %s %d" % [str(opened), s.market_shop, root.cart.count(s.market_shop)])

	# --- 5. 再挑戦・続きから ---
	var before := JSON.stringify(s.phone_notes())
	var envelope: Dictionary = MorningSave.capture("")
	GameState.day_records = []
	MorningSave.apply(envelope)
	c.check("朝の封筒に戻すと、同じ客ノート", JSON.stringify(s.phone_notes()) == before and not (s.phone_notes()["mobs"] as Array).is_empty())

	# --- 6. 来店予告のモブの差出人に「常連」の印を付けない ---
	GameState.reset_for_new_game()
	GameState.day_count = 4
	GameState.day_records = [{ "day": 1, "mob_types_served": ["dock_workers"] }, { "day": 2, "mob_types_served": ["dock_workers"] }, { "day": 3, "mob_types_served": [] }]
	GameState.today_plan = { "day": 4, "slots": [{ "name": "宵の口", "customers": ["streamer", "mob#0"], "regular_id": "streamer", "episode_id": "", "today_request": {} }],
		"mob_instances": { "mob#0": { "type": "inn_clerk", "count": 2 } }, "demand_center": 9 }
	phone.tab = "sns"
	phone.refresh()
	var shapes := {}
	var mark_seen := false
	var rows_seen := 0
	for row in phone.get_node("%Content").get_children():
		var row_texts := _label_texts(row)
		var kind := ""
		if row_texts.has("港湾労働者の組") or row_texts.has("安宿の夜勤受付"):
			kind = "mob"
		elif row_texts.has("配信者"):
			kind = "customer"
		elif row_texts.has("市場の顔なじみ"):
			kind = "npc"
		if kind == "":
			continue
		rows_seen += 1
		mark_seen = mark_seen or row_texts.has("常連")
		# 見た目の構成（子の数・ラベルの数・色つきの部品の数）が、差出人の種類によらず同じ
		var labels := 0
		var colored := 0
		for child in row.get_children():
			labels += 1 if child is Label else 0
			colored += 1 if child is ColorRect else 0
		shapes[kind] = "%d/%d/%d" % [row.get_child_count(), labels, colored]
	var same_shape := true
	for kind in shapes:
		same_shape = same_shape and shapes[kind] == shapes.values()[0]
	c.check("DMの行は、差出人が名前あり客・モブの組・市場の顔なじみのどれでも同じ見た目（「常連」の印なし・構成が同じ）", not mark_seen and same_shape and rows_seen >= 3, "%s rows %d" % [str(shapes), rows_seen])
	ReadState.reset(ReadState.path)
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
