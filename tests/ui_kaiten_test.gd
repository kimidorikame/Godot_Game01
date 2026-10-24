extends RefCounted
## 本番UI（UI準備B③）：開店の操作エリア（鍋／トッピングのタブ・団体の確認・鍋が尽きた保留）の検証。
## 対象：シーンの寸法（寸法表 KAITEN_UI_LAYOUT §2〜§4、4px以内。ボタンは始点と幅）、鍋⇄トッピングの自動・手の切り替え、
## 椀の枠の傷んだ印（bowl_view の additions_damaged）・減点の予告・短縮名、具材ボタン（本体＝新鮮・右端＝傷んだ側）、
## 提供・廃棄・断る・聞き直す・いつもの・保存、モブの団体の確認、鍋が尽きた保留（営業を続ける・閉店）、閉店する。
## どれもボタンの pressed だけで操作する（押せないボタンは押さない）。

const TOL := 4.0


func _near(a: Rect2, b: Rect2, tol: float = TOL) -> bool:
	return absf(a.position.x - b.position.x) <= tol and absf(a.position.y - b.position.y) <= tol \
		and absf(a.size.x - b.size.x) <= tol and absf(a.size.y - b.size.y) <= tol


func _at(node: Control, pos: Vector2, width: float) -> bool:
	return node.get_global_position().distance_to(pos) <= TOL and absf(node.size.x - width) <= TOL


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


## 傷んだ在庫を足す（購入日を2日前にしたバッチ＝3日目で傷み）。
func _add_damaged(item: String, count: int) -> void:
	GameState.inventory[item] = int(GameState.inventory.get(item, 0)) + count
	var batches: Array = GameState.perishable_batches.get(item, [])
	batches.push_front({ "day": GameState.day_count - 2, "count": count, "unit_price": 8 })
	GameState.perishable_batches[item] = batches


## 本番UIのルートを起動し、開店（OPEN）で客を1人ずつ接客する客キューにして、最初の入力待ちまで会話を進める。
func _open_root(t: SceneTree, customers: Array, stock: Dictionary, damaged: Dictionary = {}, soup_remaining: int = 999,
		strength: int = 3) -> UiGameRoot:
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
	GameState.set_soup("bone_broth", ["meaty"], soup_remaining, strength, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	s.load_current_customer()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	_sort(root)
	return root


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. シーン・短縮名 ---
	for path in ["res://scenes/ui/ingredient_button.tscn", "res://scenes/ui/kaiten_pot.tscn", "res://scenes/ui/kaiten_topping.tscn",
			"res://scenes/ui/pane_kaiten.tscn"]:
		var packed: PackedScene = load(path)
		var inst = packed.instantiate() if packed != null else null
		c.check("%s を読み込める" % path.get_file(), inst != null)
		if inst != null:
			inst.free()
	c.check("短縮名：ナムプリ・ココナッツ・浮き袋（表に無い品目は本名）",
		UiLabels.short_name("nam_prik_pao") == "ナムプリ" and UiLabels.short_name("coconut_milk") == "ココナッツ"
			and UiLabels.short_name("fish_maw") == "浮き袋" and UiLabels.short_name("soup_base") == Ingredients.name_for("soup_base"))
	var all_ids := ["nam_prik_pao", "coconut_milk", "pickled_lime", "bitter_melon", "herbal_sauce", "offal", "meat_ball", "tofu",
		"broken_wrapper", "winter_melon", "cartilage", "tendon_meat", "dried_wood_ear", "rice_noodle", "shrimp", "clam", "fish_maw"]
	var ordered := true
	for i in range(all_ids.size()):
		ordered = ordered and UiLabels.item_order(all_ids[i]) == i
	c.check("短縮名の表は17品目・品目の定義順（調味料5・具材12）", ordered and Ingredients._TAGS.keys() == all_ids)

	# --- 2. 開店：新人警官のADJUST（傷んだ豆腐の在庫あり）---
	var root := _open_root(t, ["officer"], { "nam_prik_pao": 9, "offal": 9, "coconut_milk": 9, "tofu": 9 }, { "tofu": 2 })
	var s: PlaySession = root.session
	var pane: UiPaneKaiten = root.pane_kaiten
	var top: UiKaitenTopping = pane.topping
	var pot: UiKaitenPot = pane.pot
	c.check("開店中は右の枠が開店の操作エリア", pane.visible and not root.pane_morning.visible)
	c.check("注文を受けたら（ADJUST）自動でトッピング", top.is_adjusting() and top.visible and not pot.visible)
	c.check("タブ：鍋 (838,26)・トッピング (1046,26)、幅208",
		_at(pane.get_node("%PotTab"), Vector2(838, 26), 208) and _at(pane.get_node("%ToppingTab"), Vector2(1046, 26), 208))
	c.check("選ばれているタブ（トッピング）に下線", absf(pane.get_node("%Underline").position.x - 210.0) < 0.5)
	var rects := { "%UsualRow": Rect2(852, 86, 303, 28), "%TodayRow": Rect2(852, 120, 303, 28), "%Slots/Slot1": Rect2(852, 179, 125, 48),
		"%Slots/Slot3": Rect2(1114, 179, 125, 48), "BowlArt": Rect2(852, 442, 388, 119) }
	for path in rects:
		c.check("トッピング：%s の位置と大きさ（寸法表どおり）" % path, _near(top.get_node(path).get_global_rect(), rects[path]),
			str(top.get_node(path).get_global_rect()))
	var grid: GridContainer = top.get_node("%Grid")
	c.check("具材ボタン：(852,296) 93×42、間隔6で4列",
		_near(grid.get_child(0).get_global_rect(), Rect2(852, 296, 93, 42)) and _near(grid.get_child(1).get_global_rect(), Rect2(951, 296, 93, 42))
			and grid.columns == 4, str(grid.get_child(1).get_global_rect()))
	c.check("聞き直す (1165,86)・幅75／提供 (852,595)・幅388", _at(top.get_node("%ReaskButton"), Vector2(1165, 86), 75)
		and _at(top.get_node("%ServeButton"), Vector2(852, 595), 388))
	var bottoms := ["%UsualButton", "%SaveButton", "%DiscardButton", "%DeclineButton"]
	var bottoms_ok := true
	for i in range(bottoms.size()):
		bottoms_ok = bottoms_ok and _at(top.get_node(bottoms[i]), Vector2(852 + i * 99, 646), 93)
	c.check("いつもの／保存／廃棄／断る：(852,646) から 93幅・間隔6", bottoms_ok)
	c.check("注文カード：いつもの・今日（名前あり客）、聞き直せる", top.get_node("%UsualRow").visible and top.get_node("%TodayRow").visible
		and not (top.get_node("%ReaskButton") as Button).disabled)
	var tabs: HBoxContainer = top.get_node("%Tabs")
	c.check("分類タブ：具材が先・調味料が後、最初に開くのは具材", tabs.get_child(0).text.begins_with("具材")
		and tabs.get_child(1).text.begins_with("調味料") and tabs.get_child(0).theme_type_variation == &"ButtonCategoryOn")
	var first: UiIngredientButton = grid.get_child(0)
	c.check("具材のタブの1つ目はモツ（定義順）・短縮名と「×在庫数」・傷んだ在庫の無い品目は右端を出さない",
		first.get_node("MainButton/Name").text == "モツ" and first.get_node("MainButton/Count").text == "×9"
			and not first.get_node("DamagedButton").visible)
	var tofu: UiIngredientButton = grid.get_child(1)
	c.check("豆腐：「×9」と右端の「傷 2」（押せる）", tofu.get_node("MainButton/Name").text == "豆腐"
		and tofu.get_node("DamagedButton").visible and tofu.get_node("DamagedButton").text == "傷\n2"
		and not (tofu.get_node("DamagedButton") as Button).disabled)
	c.check("空の椀：減点の予告は「提供できない（味・具）」（注意色）、提供は押せない",
		top.get_node("%Penalty").get_parsed_text() == "このままでは提供できません: 味の素材が無い・具が無い"
			and top.get_node("%Penalty").text.begins_with("[color=#ff8a7a]")
			and (top.get_node("%ServeButton") as Button).disabled, top.get_node("%Penalty").text)

	# 具材：本体＝新鮮、右端＝傷んだ側
	_press(tofu.get_node("DamagedButton"))
	var bowl := s.bowl_view()
	c.check("右端「傷」を押す → select_ingredient(豆腐, 傷んだ側)：傷んだ在庫が減り、椀の印が付く",
		bowl["additions"] == ["tofu"] and bowl["additions_damaged"] == [true] and GameState.damaged_count("tofu") == 1)
	c.check("椀の枠：「豆腐(傷)」・注意色の枠", top.get_node("%Slots/Slot1/Label").text == "豆腐(傷)"
		and top.get_node("%Slots/Slot1").theme_type_variation == &"PanelSlotDamaged")
	_press(tabs.get_child(1))
	c.check("分類タブを押すと調味料の一覧（ナムプリ・ココナッツ）", grid.get_child(0).get_node("MainButton/Name").text == "ナムプリ"
		and tabs.get_child(1).theme_type_variation == &"ButtonCategoryOn")
	_press(grid.get_child(0).get_node("MainButton"))
	bowl = s.bowl_view()
	c.check("本体を押す → 新鮮な側（印は false）", bowl["additions"] == ["tofu", "nam_prik_pao"] and bowl["additions_damaged"] == [true, false])
	c.check("減点の予告：「傷んだ豆腐で1段階下がります。」", top.get_node("%Penalty").get_parsed_text() == "減点の予告: 傷んだ豆腐で1段階下がります。",
		top.get_node("%Penalty").text)
	c.check("提供できる椀になったら、提供を押せる", not (top.get_node("%ServeButton") as Button).disabled)
	GameState.soup["strength"] = GameState.STRENGTH_MIN
	s.notify_changed()
	c.check("濃さ1：減点の予告に「濃さ1・傷んだ豆腐」。椀を作っている最中は鍋を触れない（今の挙動）ので、手当ては出さず理由だけ",
		not s.can_touch_pot() and top.get_node("%Penalty").get_parsed_text() == "減点の予告: 濃さ1・傷んだ豆腐で1段階下がります。",
		top.get_node("%Penalty").text)
	c.check("トッピング中に鍋の手当てが要る（濃さ1）ので、鍋タブに「●」", pane.get_node("%PotDot").visible)
	c.check("鍋の小表示：「鍋 残999杯 / 濃さ1」", top.get_node("%PotMini").text == "鍋 残999杯 / 濃さ1")

	# 手でタブを切り替える（椀の中身は保持）
	_press(pane.get_node("%PotTab"))
	c.check("鍋タブを押すと鍋の画面（椀の中身はそのまま）", pot.visible and not top.visible and s.bowl_view()["additions"].size() == 2)
	c.check("鍋：濃さは注意色・注意文「濃さ1は評価が1段階下がります」", pot.get_node("%StrengthValue").theme_type_variation == &"LabelPriceWarn"
		and pot.get_node("%StrengthNote").visible and pot.get_node("%StrengthNote").text == "濃さ1は評価が1段階下がります")
	c.check("鍋：だし (1060,227) 86×96・水 (1154,227) 86×96・鍋の絵 (852,334) 388×346",
		_near(pot.get_node("%DashiButton").get_global_rect(), Rect2(1060, 227, 86, 96))
			and _near(pot.get_node("%WaterButton").get_global_rect(), Rect2(1154, 227, 86, 96))
			and _near(pot.get_node("PotArt").get_global_rect(), Rect2(852, 334, 388, 346)))
	c.check("椀を作っている最中（鍋は足りている）は、だし・水を押せない（今の挙動のまま）",
		(pot.get_node("%DashiButton") as Button).disabled and (pot.get_node("%WaterButton") as Button).disabled)
	c.check("鍋タブを見ている間は「●」を出さない", not pane.get_node("%PotDot").visible)
	_press(pane.get_node("%ToppingTab"))
	c.check("トッピングタブで戻れる", top.visible and not pot.visible)
	GameState.soup["strength"] = 3
	_press(top.get_node("%ServeButton"))
	c.check("提供 → complete_input：判定へ進み、自動で鍋タブ", not top.is_adjusting() and pot.visible)

	# 判定後：保存（枠→名前）
	var guard := 0
	while not s.can_save_recipe() and s.can_next_event() and guard < 10:
		guard += 1
		root.left.advance()
	_press(pane.get_node("%ToppingTab"))
	c.check("判定後、トッピングに手で戻ると「保存」を押せる", s.can_save_recipe() and not (top.get_node("%SaveButton") as Button).disabled)
	_press(top.get_node("%SaveButton"))
	var menu: GridContainer = top.get_node("%RecipeButtons")
	c.check("保存 → 枠を選ぶメニュー（大きい椀の位置）", top.get_node("%RecipeMenu").visible and s.recipe_save_view()["stage"] == "slot"
		and _near(top.get_node("%RecipeMenu").get_global_rect(), Rect2(852, 442, 388, 119)))
	_press(menu.get_child(0))
	c.check("枠1を押す → 名前を選ぶ", s.recipe_save_view()["stage"] == "name" and top.get_node("%RecipeCaption").text == "名前を選ぶ")
	var picked_name: String = menu.get_child(0).text
	_press(menu.get_child(0))
	c.check("名前を押す → 保存レシピに入る", GameState.saved_recipes.size() == 1 and str(GameState.saved_recipes[0]["name"]) == picked_name
		and not top.get_node("%RecipeMenu").visible)
	# 減点の予告の手当て：今すぐ足せるときだけ（依頼書 §3.2）。判定のあと（鍋を触れる）で、理由のコードを与えて確かめる
	var extreme_min := { "blockers": [], "penalties": [{ "code": "STRENGTH_EXTREME", "value": GameState.STRENGTH_MIN }] }
	var extreme_max := { "blockers": [], "penalties": [{ "code": "STRENGTH_EXTREME", "value": GameState.STRENGTH_MAX }] }
	GameState.soup["strength"] = GameState.STRENGTH_MIN
	GameState.dashi_units = 1
	c.check("濃さ最小・だしを今すぐ足せる（can_touch_pot・can_add_dashi）→ 強調色で「鍋タブでだし +2」",
		s.can_touch_pot() and GameState.can_add_dashi()
			and top.penalty_bbcode(s.bowl_view(), extreme_min).ends_with("　[color=#e8a33d]鍋タブでだし +2[/color]"),
		top.penalty_bbcode(s.bowl_view(), extreme_min))
	GameState.dashi_units = 0
	c.check("濃さ最小・だしが無い → 理由だけ", not GameState.can_add_dashi()
		and top.penalty_bbcode(s.bowl_view(), extreme_min).ends_with("1段階下がります。[/color]"), top.penalty_bbcode(s.bowl_view(), extreme_min))
	GameState.soup["strength"] = GameState.STRENGTH_MAX
	GameState.soup["remaining_servings"] = 5
	c.check("濃さ最大・水を今すぐ足せる（can_touch_pot・can_add_water）→ 強調色で「鍋タブで水」",
		s.can_touch_pot() and GameState.can_add_water()
			and top.penalty_bbcode(s.bowl_view(), extreme_max).ends_with("　[color=#e8a33d]鍋タブで水[/color]"),
		top.penalty_bbcode(s.bowl_view(), extreme_max))
	GameState.soup["remaining_servings"] = 999
	c.check("濃さ最大・水を足せない（残りが多い）→ 理由だけ", not GameState.can_add_water()
		and top.penalty_bbcode(s.bowl_view(), extreme_max).ends_with("1段階下がります。[/color]"), top.penalty_bbcode(s.bowl_view(), extreme_max))
	GameState.soup["strength"] = 3
	guard = 0
	while s.can_next_event() and not s.flow.is_runner_done() and guard < 30:
		guard += 1
		root.left.advance()
	_sort(root)
	c.check("客を全員さばいて列が終わると「閉店する」", pot.visible and pot.get_node("%CloseNightButton").visible
		and _at(pot.get_node("%CloseNightButton"), Vector2(852, 634), 388))
	_press(pot.get_node("%CloseNightButton"))
	c.check("「閉店する」→ flow.advance_phase で閉店（CLOSE）へ", GameState.phase == GameState.Phase.CLOSE)
	root.queue_free()

	# --- 3. いつもの（保存レシピ）・廃棄・断る ---
	var saved_recipes := GameState.saved_recipes.duplicate(true)
	root = _open_root(t, ["officer"], { "nam_prik_pao": 9, "offal": 9, "coconut_milk": 9, "tofu": 9 })
	s = root.session
	top = root.pane_kaiten.topping
	GameState.saved_recipes = [{ "name": "試しの一杯", "ingredients": ["nam_prik_pao", "offal"] }]
	s.notify_changed()
	c.check("椀が空で保存レシピがあれば「いつもの」を押せる", not (top.get_node("%UsualButton") as Button).disabled)
	_press(top.get_node("%UsualButton"))
	menu = top.get_node("%RecipeButtons")
	c.check("いつもの → 保存レシピの一覧（短縮名で中身）", top.get_node("%RecipeMenu").visible
		and menu.get_child(0).text == "試しの一杯（ナムプリ・モツ）", menu.get_child(0).text)
	_press(menu.get_child(0))
	c.check("レシピを押す → apply_recipe（具材ボタンを順に押したのと同じ）・メニューは閉じる",
		s.bowl_view()["additions"] == ["nam_prik_pao", "offal"] and not top.get_node("%RecipeMenu").visible)
	var discards := s.bowl_discard_count
	_press(top.get_node("%DiscardButton"))
	c.check("廃棄 → discard_bowl：椀が空に戻る", s.bowl_view()["additions"].is_empty() and s.bowl_discard_count == discards + 1)
	_press(top.get_node("%DeclineButton"))
	c.check("断る → decline_customer：判定せずに先へ進む（椀は作っていない）", not top.is_adjusting())
	GameState.saved_recipes = saved_recipes
	root.queue_free()

	# --- 4. モブの団体の確認（モブの人数は today_plan に入れてから客を読む）---
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
	s.notify_changed()
	guard = 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	c.check("モブ：注文カード・聞き直す・断るは出さない（断るは団体の確認で）", not top.get_node("%UsualRow").visible
		and not top.get_node("%ReaskButton").visible and (top.get_node("%DeclineButton") as Button).disabled)
	grid = top.get_node("%Grid")
	_press(grid.get_child(0).get_node("MainButton"))   # 肉団子（具材の1つ目）
	_press(top.get_node("%Tabs").get_child(1))
	_press(grid.get_child(0).get_node("MainButton"))   # ナムプリ
	_press(top.get_node("%ServeButton"))
	var group_box: Control = top.get_node("%GroupBox")
	c.check("モブの提供 → 団体の確認（大きい椀の位置）：注文4・出せる3", group_box.visible and s.pending_group_choice
		and top.get_node("%GroupText").text == "注文は4人分。いまの鍋と具材で出せるのは3人分。"
		and _near(group_box.get_global_rect(), Rect2(852, 442, 388, 119)), top.get_node("%GroupText").text)
	c.check("「3人分を提供」「残り1人に挑戦」「注文を断る」", top.get_node("%GroupServe").text == "3人分を提供"
		and top.get_node("%GroupRetry").visible and top.get_node("%GroupRetry").text == "残り1人に挑戦"
		and not (top.get_node("%GroupDecline") as Button).disabled)
	c.check("団体の確認の間は、具材・提供は押せない", (top.get_node("%ServeButton") as Button).disabled
		and (grid.get_child(0).get_node("MainButton") as Button).disabled)
	var money := GameState.money
	_press(top.get_node("%GroupServe"))
	c.check("「3人分を提供」→ group_serve：確認が閉じて先へ進む", not group_box.is_visible_in_tree() and not s.pending_group_choice)
	guard = 0
	while GameState.money == money and s.can_next_event() and guard < 10:
		guard += 1
		root.left.advance()
	c.check("判定で3人分の売上が入る", GameState.money == money + 3 * GameState.PRICE_PER_SERVING)
	root.queue_free()

	# --- 5. 鍋が尽きた保留（営業を続ける・閉店）---
	root = _open_root(t, ["officer"], { "nam_prik_pao": 9, "offal": 9 })
	s = root.session
	pane = root.pane_kaiten
	top = pane.topping
	pot = pane.pot
	grid = top.get_node("%Grid")
	_press(grid.get_child(0).get_node("MainButton"))   # モツ
	_press(top.get_node("%Tabs").get_child(1))
	_press(grid.get_child(0).get_node("MainButton"))   # ナムプリ
	_press(top.get_node("%ServeButton"))
	GameState.soup["remaining_servings"] = 0   # 判定（REACT）の前に鍋が尽きた
	guard = 0
	while not s.is_shortage_pending() and s.can_next_event() and s.flow.runner.current() != null \
			and str(s.flow.runner.current().get("type", "")) != "REACT" and guard < 10:
		guard += 1
		root.left.advance()
	c.check("鍋が尽きた保留：自動で鍋タブ・保留の箱・「営業を続ける」はまだ押せない・「閉店」は押せる",
		s.is_shortage_pending() and pot.visible and pot.get_node("%ShortageBox").visible
			and (pot.get_node("%ResumeButton") as Button).disabled and not (pot.get_node("%CloseButton") as Button).disabled)
	c.check("保留の間は水を押せる（鍋を作り直す）", not (pot.get_node("%WaterButton") as Button).disabled)
	_press(pot.get_node("%WaterButton"))
	c.check("水を足すと残りが増え、「営業を続ける」を押せる（残り≥注文・濃さ≠0）", int(s.pot_view()["remaining"]) >= s.current_servings()
		and not (pot.get_node("%ResumeButton") as Button).disabled)
	money = GameState.money
	_press(pot.get_node("%ResumeButton"))
	c.check("「営業を続ける」→ resume_after_shortage：提供される（売上が入る）・保留の箱が消える",
		not s.is_shortage_pending() and GameState.money > money and not pot.get_node("%ShortageBox").visible)
	root.queue_free()

	root = _open_root(t, ["officer"], { "nam_prik_pao": 9, "offal": 9 })
	s = root.session
	pot = root.pane_kaiten.pot
	top = root.pane_kaiten.topping
	grid = top.get_node("%Grid")
	_press(grid.get_child(0).get_node("MainButton"))
	_press(top.get_node("%Tabs").get_child(1))
	_press(grid.get_child(0).get_node("MainButton"))
	_press(top.get_node("%ServeButton"))
	GameState.soup["remaining_servings"] = 0
	root.left.advance()
	_press(pot.get_node("%CloseButton"))
	c.check("「閉店」→ close_shop：閉店（CLOSE）へ", GameState.phase == GameState.Phase.CLOSE)
	root.queue_free()
	return c.finish()
