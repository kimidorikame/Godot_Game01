extends Control
class_name UiKaitenTopping
## 開店の操作エリア：トッピング。寸法表 KAITEN_UI_LAYOUT §4・§5。
## 注文カード（order_card_view。「前回」「今日」）と[聞き直す]（reask）、鍋の行（pot_view。「鍋 残11杯 / 濃さ3」。濃さ0・1・5は数字を注意色）、
## 案内文と減点の予告（sale_hint）、分類タブ（具材が先・調味料が後。1タブ6個まで）、具材ボタン（本体＝新鮮、右上＝傷んだ側。
## select_ingredient）、いまの椀の3枠（bowl_view。傷んだ具材は注意色の枠で「豆腐(傷)」）、提供（complete_input）、
## いつもの／レシピ保存｜一杯を捨てる／断る（捨てる・断るは区切り線の右。UI準備P）。
## UI準備Q：3枠の上の見出し「いまの椀(3枠)」の文字を鍋の行に替え、提供の上の鍋の小表示は消した（2か所に出さない）。
## 空いた分だけ大きい椀の絵（16,418）を下へ広げた（提供ボタンの位置は今のまま）。
## 「いつもの」と「保存」の中身・モブの団体の確認は、大きい椀の絵の位置に重ねて出し、出ている間は椀の絵を隠す（plan Q14）。
## 短縮名を使うのはこの画面だけ（UiLabels.short_name）。

const PER_TAB := 6   # 1ページの具材ボタン（UI準備P：文字を大きくして3列×2段。以前は4列×2段の8個）。超えたら「具材1」「具材2」…
## 味・具が欠ける以外の、提供できない理由（味・具の欠けは案内文で出す。UI準備P）。
const BLOCKER_TEXT := { "STRENGTH_ZERO": "濃さ0", "SHORT_SERVINGS": "鍋が足りない" }

var session: PlaySession = null

## 表示だけの状態：開いている分類タブ（{kind, page}）、「いつもの」の中身を開いているか、タブを決めた客。
var _tab := { "kind": "topping", "page": 0 }
var _menu_open := false
var _tab_customer := ""

@onready var _usual_row: Control = %UsualRow
@onready var _usual_tags: Label = %UsualTags
@onready var _today_row: Control = %TodayRow
@onready var _today_tags: Label = %TodayTags
@onready var _usual_chips: HBoxContainer = %UsualChips
@onready var _today_chips: HBoxContainer = %TodayChips
@onready var _reask: Button = %ReaskButton
@onready var _favorite: Label = %FavoriteLabel
@onready var _slots: Control = %Slots
@onready var _bowl_art: Control = $BowlArt
@onready var _pot_line: Control = %PotLine
@onready var _pot_text: Label = %PotText
@onready var _pot_strength: Label = %PotStrength
@onready var _penalty: RichTextLabel = %Penalty
@onready var _tabs: HBoxContainer = %Tabs
@onready var _grid: GridContainer = %Grid
@onready var _group_box: Control = %GroupBox
@onready var _group_text: Label = %GroupText
@onready var _group_serve: Button = %GroupServe
@onready var _group_retry: Button = %GroupRetry
@onready var _group_decline: Button = %GroupDecline
@onready var _menu: Control = %RecipeMenu
@onready var _menu_caption: Label = %RecipeCaption
@onready var _menu_buttons: GridContainer = %RecipeButtons
@onready var _serve: Button = %ServeButton
@onready var _usual: Button = %UsualButton
@onready var _save: Button = %SaveButton
@onready var _discard: Button = %DiscardButton
@onready var _decline: Button = %DeclineButton

var _items: Array = []   # いまのタブに並べている品目 [{ id, fresh, damaged, main, dmg }]


func _ready() -> void:
	_reask.pressed.connect(func(): session.reask())
	_serve.pressed.connect(_on_serve_pressed)
	_usual.pressed.connect(_on_usual_pressed)
	_save.pressed.connect(func(): session.start_recipe_save())
	_discard.pressed.connect(func(): session.discard_bowl())
	_decline.pressed.connect(func(): session.decline_customer())
	_group_serve.pressed.connect(_on_group_serve)
	_group_retry.pressed.connect(_on_group_retry)
	_group_decline.pressed.connect(_on_group_decline)
	for i in range(_grid.get_child_count()):
		var button: UiIngredientButton = _grid.get_child(i)
		button.main_pressed.connect(_on_item_pressed.bind(i, false))
		button.damaged_pressed.connect(_on_item_pressed.bind(i, true))


func bind_session(s: PlaySession) -> void:
	session = s


func reset_ui_state() -> void:
	_tab = { "kind": "topping", "page": 0 }
	_menu_open = false
	_tab_customer = ""


## 椀を作っている最中（ADJUST の入力待ち）か。
func is_adjusting() -> bool:
	return session != null and str(session.current_line().get("type", "")) == "ADJUST" and session.is_waiting_input()


func refresh() -> void:
	if session == null:
		return
	var bowl := session.bowl_view()
	var customer := str(bowl.get("customer", ""))
	if customer != _tab_customer:
		# 客が替わったら、分類タブは具材（最初に開くのは具材）に戻し、中身のメニューを閉じる
		_tab_customer = customer
		_tab = { "kind": "topping", "page": 0 }
		_menu_open = false
	var adjusting := is_adjusting()
	var group := session.mob_group_choice()
	_refresh_order_card()
	_refresh_bowl(bowl)
	_refresh_penalty(bowl)
	_refresh_items(adjusting and group.is_empty())
	_refresh_pot_line(session.pot_view())
	_serve.disabled = not (adjusting and group.is_empty() and session.can_complete_input())
	var empty_bowl := (bowl.get("additions", []) as Array).is_empty()
	var recipes := session.recipe_adjust_buttons()
	_usual.disabled = not (adjusting and group.is_empty() and empty_bowl and not recipes.is_empty())
	var save_view := session.recipe_save_view()
	_save.disabled = not bool(save_view.get("can_save", false)) or str(save_view.get("stage", "")) != ""
	_discard.disabled = not (adjusting and group.is_empty() and session.can_discard())
	_decline.disabled = not (adjusting and group.is_empty() and session.can_decline())
	if not (adjusting and empty_bowl):
		_menu_open = false
	_refresh_overlay(group, recipes, save_view)


## 「前回」「今日」の欄は常に出す（空白の隙間を作らない。UI準備O2で「いつもの」を「前回」に替えた）。その下に「好物」の1行（知った名前あり客だけ。UI準備R）。「前回」は来店の最初から入る（初来店・モブは空白）。
## 「今日」は来店の会話が終わった時点（その杯の ADJUST）で入り、それまでは「？」を薄い色で出す（order_card_view の last_known・today_known）。
## [聞き直す]は、聞き直せる会話があるとき（名前あり客・1杯の場面のADJUST中）だけ出す。
func _refresh_order_card() -> void:
	var card := session.order_card_view()
	_usual_row.visible = true
	_today_row.visible = true
	var today_known := bool(card.get("today_known", false))
	# 文字（_usual_tags・_today_tags）は、タグの言葉をつないだ形で持つ（札が出ていないときの「？」・空白もここ）。
	# タグがあるときは文字を隠して、言葉の札（UiTagChips。材料側と同じ見た目）を出す。
	var last_tags: Array = card["last"] if bool(card.get("last_known", false)) else []
	var today_tags: Array = card["today"] if today_known else []
	_usual_tags.text = TagWords.joined(last_tags)
	_today_tags.text = TagWords.joined(today_tags) if today_known else "？"
	UiTagChips.fill(_usual_chips, last_tags)
	UiTagChips.fill(_today_chips, today_tags)
	_usual_tags.visible = last_tags.is_empty()
	_today_tags.visible = today_tags.is_empty()
	_usual_tags.modulate = Color(1, 1, 1, 1.0)
	# 好物（UI準備R）：知った名前あり客だけ。知らない客・モブは行ごと出さない
	_favorite.text = "好物　" + str(card.get("favorite", "")) if str(card.get("favorite", "")) != "" else ""
	_favorite.visible = _favorite.text != ""
	_today_tags.modulate = Color(1, 1, 1, 1.0) if _today_tags.text != "？" else Color(1, 1, 1, 0.4)
	_reask.visible = session.can_reask()
	_reask.disabled = not session.can_reask()


## 鍋の行（UI準備Q）：「鍋 残11杯 / 濃さ3」。濃さが適正の外（0・1・5＝提供できない・減点の側）なら、濃さの数字だけ注意色（鍋タブの目盛りと同じ考え）。
## 鍋が無いときは行ごと隠す。
func _refresh_pot_line(pot: Dictionary) -> void:
	_pot_line.visible = bool(pot.get("exists", false))
	if not _pot_line.visible:
		return
	var strength := int(pot.get("strength", 0))
	_pot_text.text = "鍋 残%d杯 / 濃さ" % int(pot.get("remaining", 0))
	_pot_strength.text = str(strength)
	if strength_outside_fit(strength, pot):
		_pot_strength.add_theme_color_override(&"font_color", get_theme_color(&"warn", &"UiPalette"))
	else:
		_pot_strength.remove_theme_color_override(&"font_color")


## 適正の外か（0以下・1・5）。鍋タブ（UiKaitenPot._outside_fit）と同じ線引き。
static func strength_outside_fit(value: int, pot: Dictionary) -> bool:
	return value <= int(pot.get("strength_floor", GameState.STRENGTH_HARD_FLOOR)) \
		or value == int(pot.get("strength_min", GameState.STRENGTH_MIN)) or value == int(pot.get("strength_max", GameState.STRENGTH_MAX))


func _refresh_bowl(bowl: Dictionary) -> void:
	var additions: Array = bowl.get("additions", [])
	var damaged: Array = bowl.get("additions_damaged", [])
	for i in range(_slots.get_child_count()):
		var slot: Panel = _slots.get_child(i)
		var label: Label = slot.get_node("Label")
		if i < additions.size():
			var is_damaged := i < damaged.size() and bool(damaged[i])
			label.text = UiLabels.short_name(str(additions[i])) + ("(傷)" if is_damaged else "")
			UiTagChips.fill(slot.get_node("Chips"), Ingredients.tags_for(str(additions[i])), true)   # その材料のタグの言葉の札（UI準備F）
			slot.theme_type_variation = &"PanelSlotDamaged" if is_damaged else &"PanelSlot"
			label.theme_type_variation = &"LabelSlotWarn" if is_damaged else &"LabelSlot"
		else:
			label.text = ""
			UiTagChips.fill(slot.get_node("Chips"), [], true)
			slot.theme_type_variation = &"PanelSlotEmpty"


## いまの椀の文（テスト・確認用）：3枠に入っている順に「短縮名(傷)」を「・」でつなぐ。空なら ""。
func bowl_text() -> String:
	var names: Array = []
	for slot in _slots.get_children():
		var text := str((slot.get_node("Label") as Label).text)
		if text != "":
			names.append(text)
	return "・".join(names)


## 案内文と減点の予告（寸法表 §5-3。UI準備P で状態ごとに分けた）。文と色だけを決め、判定・減点の計算は sale_hint の理由コードのまま。
##   味・具が欠けている：まだ選んでいない分類は「味付けと具を選んでください」「味付けを選んでください」「具を選んでください」（ふつうの文字色）。
##     その分類の在庫が1つも無い（選べない）ときだけ「味付けの在庫がありません」「具の在庫がありません」（注意色）。
##   ほかの提供できない理由（濃さ0・鍋が足りない）：「このままでは提供できません: …」（注意色）。
##   傷んだ具材だけ：「傷んだ豆腐を使用中：評価が1段階下がります」（注意色）。濃さ（と傷み）：今までどおり「減点の予告: …で1段階下がります。」（注意色）。
##   濃さが理由なら続けて鍋タブでの手当て（強調色）。手当ては今すぐ足せるときだけ出す（依頼書 §3.2）：濃さが最小なら「鍋タブでだし +2」
##   （can_touch_pot と can_add_dashi）、最大なら「鍋タブで水」（can_touch_pot と can_add_water）。足せないときは理由だけ。
##   減点が無いときは薄い色で「いまのところ減点なし」。注意色は、損や問題があるときだけ。
func _refresh_penalty(bowl: Dictionary) -> void:
	_penalty.text = penalty_bbcode(bowl, session.sale_hint())


## 案内文と減点の予告の文（BBCode）。表示の文面だけを作る（判定は sale_hint の理由コード）。
func penalty_bbcode(bowl: Dictionary, hint: Dictionary) -> String:
	if bowl.is_empty():
		return ""
	var warn := "#" + get_theme_color(&"warn", &"UiPalette").to_html(false)
	var accent := "#" + get_theme_color(&"accent", &"UiPalette").to_html(false)
	var neutral := "#" + get_theme_color(&"text", &"UiPalette").to_html(false)
	var pot := session.pot_view()
	var can_dashi: bool = session.can_touch_pot() and bool(pot.get("can_add_dashi", false))
	var can_water: bool = session.can_touch_pot() and bool(pot.get("can_add_water", false))
	var blockers: Array = hint["blockers"]
	var parts: Array = []   # 色付きの文をつなぐ（全角の空白で区切る）
	var tip := ""
	if not blockers.is_empty():
		var need_flavor := blockers.has(SaleRule.NO_FLAVOR)
		var need_topping := blockers.has(SaleRule.NO_TOPPING)
		if need_flavor or need_topping:
			var no_flavor := need_flavor and not _has_stock(true)
			var no_topping := need_topping and not _has_stock(false)
			if no_flavor and no_topping:
				parts.append("[color=%s]味付けと具の在庫がありません[/color]" % warn)
			elif no_flavor:
				parts.append("[color=%s]味付けの在庫がありません[/color]" % warn)
			elif no_topping:
				parts.append("[color=%s]具の在庫がありません[/color]" % warn)
			var pick_flavor := need_flavor and not no_flavor
			var pick_topping := need_topping and not no_topping
			if pick_flavor and pick_topping:
				parts.append("[color=%s]味付けと具を選んでください[/color]" % neutral)
			elif pick_flavor:
				parts.append("[color=%s]味付けを選んでください[/color]" % neutral)
			elif pick_topping:
				parts.append("[color=%s]具を選んでください[/color]" % neutral)
		var other: Array = []
		for code in blockers:
			if BLOCKER_TEXT.has(str(code)):
				other.append(str(BLOCKER_TEXT[str(code)]))
		if not other.is_empty():
			parts.append("[color=%s]このままでは提供できません: %s[/color]" % [warn, "・".join(other)])
		if blockers.has(SaleRule.STRENGTH_ZERO) and can_dashi:
			tip = "鍋タブでだし +2"
		elif blockers.has(SaleRule.SHORT_SERVINGS) and can_water:
			tip = "鍋タブで水 +2杯"
	else:
		var strength_value := -1
		var spoiled := false
		for penalty in hint["penalties"]:
			match str(penalty["code"]):
				"STRENGTH_EXTREME":
					strength_value = int(penalty["value"])
					if strength_value <= GameState.STRENGTH_MIN:
						tip = "鍋タブでだし +2" if can_dashi else ""
					else:
						tip = "鍋タブで水" if can_water else ""
				"SPOILED":
					spoiled = true
		if strength_value < 0 and not spoiled:
			return "減点の予告: いまのところ減点なし"
		if strength_value < 0:
			parts.append("[color=%s]%sを使用中：評価が1段階下がります[/color]" % [warn, "・".join(_spoiled_names(bowl))])
		else:
			var reasons: Array = ["濃さ%d" % strength_value]
			if spoiled:
				reasons.append_array(_spoiled_names(bowl))
			parts.append("[color=%s]減点の予告: %sで1段階下がります。[/color]" % [warn, "・".join(reasons)])
	var text := "　".join(parts)
	if tip != "":
		text += "　[color=%s]%s[/color]" % [accent, tip]
	return text


## その分類（味付け＝true／具＝false）の材料を、いまの椀に入れられるか（選択肢に在庫が1つ以上あるか、もう椀に入っているもの）。
## 「〇〇の在庫がありません」を出すかどうかだけに使う（表示だけ）。
func _has_stock(flavor: bool) -> bool:
	for option in session.ingredient_options():
		var id := str(option["id"])
		var match_kind := Ingredients.is_flavor(id) if flavor else Ingredients.is_topping(id)
		if match_kind and (int(option["count"]) >= 1 or bool(option["in_bowl"])):
			return true
	return false


## 椀に入っている傷んだ具材の名前（「傷んだ豆腐」）。品目ごとの印が無い椀は「傷んだ具材」。
static func _spoiled_names(bowl: Dictionary) -> Array:
	var names: Array = []
	var additions: Array = bowl.get("additions", [])
	var damaged: Array = bowl.get("additions_damaged", [])
	for i in range(mini(additions.size(), damaged.size())):
		if bool(damaged[i]):
			var name := "傷んだ%s" % UiLabels.short_name(str(additions[i]))
			if not names.has(name):
				names.append(name)
	if names.is_empty():
		names.append("傷んだ具材")
	return names


## 分類タブと具材ボタン。椀を作っている最中は ingredient_options()（その客の選択肢）、それ以外は今の在庫を押せない形で出す。
func _refresh_items(can_pick: bool) -> void:
	var by_id := {}
	var options := session.ingredient_options()
	if not options.is_empty():
		for option in options:
			var id := str(option["id"])
			var entry: Dictionary = by_id.get(id, { "id": id, "kind": str(option["kind"]), "fresh": int(option["fresh"]),
				"damaged": int(option["damaged_stock"]), "main": false, "dmg": false, "in_bowl": bool(option["in_bowl"]) })
			# 椀に入っている具材は、もう一度押すと取り消せる（在庫が0になっていても押せる）
			var pressable: bool = can_pick and (bool(option["can_pick"]) or bool(option["in_bowl"]))
			if bool(option["damaged"]):
				entry["dmg"] = pressable
			else:
				entry["main"] = pressable
			by_id[id] = entry
	else:
		for id in GameState.inventory:
			if str(id) == "soup_base" or GameState.fresh_count(str(id)) + GameState.damaged_count(str(id)) <= 0:
				continue
			by_id[str(id)] = { "id": str(id), "kind": "topping" if Ingredients.is_topping(str(id)) else "seasoning",
				"fresh": GameState.fresh_count(str(id)), "damaged": GameState.damaged_count(str(id)), "main": false, "dmg": false }
	var groups := { "topping": [], "seasoning": [] }
	var ids := by_id.keys()
	ids.sort_custom(func(a, b): return UiLabels.item_order(str(a)) < UiLabels.item_order(str(b)))
	for id in ids:
		(groups[by_id[id]["kind"]] as Array).append(by_id[id])
	# 分類タブ：具材が先、調味料が後。1ページ（PER_TAB）を超えたら「具材1」「具材2」…
	var tabs: Array = []
	for kind in ["topping", "seasoning"]:
		var items: Array = groups[kind]
		var pages := maxi(ceili(float(items.size()) / PER_TAB), 1)
		for page in range(pages):
			var title := "具材" if kind == "topping" else "調味料"
			if pages > 1:
				title += str(page + 1)
			tabs.append({ "kind": kind, "page": page, "title": title,
				"count": items.slice(page * PER_TAB, (page + 1) * PER_TAB).size() })
	var current := 0
	for i in range(tabs.size()):
		if tabs[i]["kind"] == _tab["kind"] and tabs[i]["page"] == _tab["page"]:
			current = i
	_tab = { "kind": tabs[current]["kind"], "page": tabs[current]["page"] }
	_refresh_tab_buttons(tabs, current)
	var shown: Array = (groups[_tab["kind"]] as Array).slice(int(_tab["page"]) * PER_TAB, (int(_tab["page"]) + 1) * PER_TAB)
	_items = shown
	for i in range(_grid.get_child_count()):
		var button: UiIngredientButton = _grid.get_child(i)
		button.visible = i < shown.size()
		if i < shown.size():
			var item: Dictionary = shown[i]
			button.show_item(str(item["id"]), int(item["fresh"]), int(item["damaged"]), bool(item["main"]), bool(item["dmg"]),
				bool(item.get("in_bowl", false)))


func _refresh_tab_buttons(tabs: Array, current: int) -> void:
	while _tabs.get_child_count() < tabs.size():
		var button := Button.new()
		button.theme_type_variation = &"ButtonCategory"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(71, 30)
		button.pressed.connect(_on_tab_pressed.bind(_tabs.get_child_count()))
		_tabs.add_child(button)
	for i in range(_tabs.get_child_count()):
		var button: Button = _tabs.get_child(i)
		button.visible = i < tabs.size()
		if i < tabs.size():
			button.text = "%s %d" % [tabs[i]["title"], int(tabs[i]["count"])]
			button.set_meta("tab", { "kind": tabs[i]["kind"], "page": tabs[i]["page"] })
			button.theme_type_variation = &"ButtonCategoryOn" if i == current else &"ButtonCategory"


## 大きい椀の絵の位置に重ねて出すもの：モブの団体の確認＞保存の段階＞「いつもの」の中身＞大きい椀の絵（どれか1つ。重ねたものが出ている間は椀の絵を隠す）。
func _refresh_overlay(group: Dictionary, recipes: Array, save_view: Dictionary) -> void:
	_group_box.visible = not group.is_empty()
	if not group.is_empty():
		var achievable := int(group["achievable"])
		_group_text.text = "注文は%d人分。いまの鍋と具材で出せるのは%d人分。" % [int(group["ordered"]), achievable]
		_group_serve.text = "%d人分を提供" % achievable
		_group_serve.disabled = not bool(group["can_serve"])
		_group_retry.visible = bool(group["can_retry"])
		_group_retry.text = "残り%d人に挑戦" % int(group["remaining"])
	var stage := str(save_view.get("stage", ""))
	var show_save := group.is_empty() and bool(save_view.get("can_save", false)) and stage != ""
	var show_menu := group.is_empty() and not show_save and _menu_open
	_menu.visible = show_save or show_menu
	_bowl_art.visible = not (_group_box.visible or _menu.visible)
	if show_save:
		_fill_save_menu(save_view)
	elif show_menu:
		_fill_recipe_menu(recipes)


func _menu_button(index: int, text: String, enabled: bool, action: Callable) -> void:
	var button: Button
	if index < _menu_buttons.get_child_count():
		button = _menu_buttons.get_child(index)
	else:
		button = Button.new()
		button.theme_type_variation = &"ButtonSmall"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(118, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		_menu_buttons.add_child(button)
	for c in button.pressed.get_connections():
		button.pressed.disconnect(c["callable"])
	button.pressed.connect(action)
	button.text = text
	button.disabled = not enabled
	button.visible = true


func _hide_menu_buttons_from(index: int) -> void:
	for i in range(index, _menu_buttons.get_child_count()):
		_menu_buttons.get_child(i).visible = false


## 「いつもの」の中身：いつもの（その客の直近）と保存レシピ。押す → apply_recipe（具材ボタンを順に押したのと同じ）。
func _fill_recipe_menu(recipes: Array) -> void:
	_menu_caption.text = "いつもの・保存したレシピ"
	var i := 0
	for recipe in recipes:
		var names: Array = []
		for id in recipe["ingredients"]:
			names.append(UiLabels.short_name(str(id)))
		_menu_button(i, "%s（%s）" % [str(recipe["name"]), "・".join(names)], bool(recipe["can_apply"]),
			session.apply_recipe.bind(recipe["ingredients"]))
		i += 1
	_menu_button(i, "閉じる", true, _close_menu)
	_hide_menu_buttons_from(i + 1)


## 保存の段階：枠を選ぶ → 名前を選ぶ（やめるは cancel_recipe_save）。
func _fill_save_menu(view: Dictionary) -> void:
	var i := 0
	if str(view["stage"]) == "slot":
		_menu_caption.text = "どの枠に保存する？"
		for slot in view["slots"]:
			var name := str(slot["name"])
			_menu_button(i, "枠%d %s" % [int(slot["index"]) + 1, name if name != "" else "（空き）"], bool(slot["selectable"]),
				session.select_recipe_slot.bind(int(slot["index"])))
			i += 1
	else:
		_menu_caption.text = "名前を選ぶ"
		for name in view["names"]:
			_menu_button(i, str(name), true, session.select_recipe_name.bind(str(name)))
			i += 1
	_menu_button(i, "やめる", true, session.cancel_recipe_save)
	_hide_menu_buttons_from(i + 1)


func _close_menu() -> void:
	_menu_open = false
	refresh()


func _on_usual_pressed() -> void:
	_menu_open = not _menu_open
	refresh()


func _on_tab_pressed(index: int) -> void:
	if index < _tabs.get_child_count():
		_tab = (_tabs.get_child(index) as Button).get_meta("tab")
		refresh()


func _on_item_pressed(index: int, damaged: bool) -> void:
	if index < _items.size():
		session.toggle_ingredient(str(_items[index]["id"]), damaged)   # 椀に無ければ入れ、あれば取り消す


func _on_serve_pressed() -> void:
	if session.can_complete_input():
		session.complete_input()


func _on_group_serve() -> void:
	var group := session.mob_group_choice()
	if not group.is_empty() and bool(group["can_serve"]):
		session.group_serve(int(group["achievable"]), int(group["ordered"]))


func _on_group_retry() -> void:
	var group := session.mob_group_choice()
	if not group.is_empty() and bool(group["can_retry"]):
		session.group_retry(int(group["achievable"]), int(group["ordered"]))


func _on_group_decline() -> void:
	var group := session.mob_group_choice()
	if not group.is_empty():
		session.group_decline(int(group["ordered"]))
