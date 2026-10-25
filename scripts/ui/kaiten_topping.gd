extends Control
class_name UiKaitenTopping
## 開店の操作エリア：トッピング。寸法表 KAITEN_UI_LAYOUT §4・§5。
## 注文カード（order_card_view）と[聞き直す]（reask）、いまの椀（bowl_view。傷んだ具材は注意色の枠で「豆腐(傷)」）、
## 減点の予告（sale_hint）、分類タブ（具材が先・調味料が後。1タブ12個まで）、具材ボタン（本体＝新鮮、右端＝傷んだ側。
## select_ingredient）、鍋の小表示、提供（complete_input）、いつもの／保存／廃棄／断る。
## 「いつもの」と「保存」の中身・モブの団体の確認は、大きい椀の絵の位置（16,418）に出す（plan Q14）。
## 短縮名を使うのはこの画面だけ（UiLabels.short_name）。

const PER_TAB := 12
const BLOCKER_TEXT := { "NO_FLAVOR": "味の素材が無い", "NO_TOPPING": "具が無い", "STRENGTH_ZERO": "濃さ0",
	"SHORT_SERVINGS": "鍋が足りない" }

var session: PlaySession = null

## 表示だけの状態：開いている分類タブ（{kind, page}）、「いつもの」の中身を開いているか、タブを決めた客。
var _tab := { "kind": "topping", "page": 0 }
var _menu_open := false
var _tab_customer := ""

@onready var _usual_row: Control = %UsualRow
@onready var _usual_tags: Label = %UsualTags
@onready var _today_row: Control = %TodayRow
@onready var _today_tags: Label = %TodayTags
@onready var _reask: Button = %ReaskButton
@onready var _slots: Control = %Slots
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
@onready var _pot_mini: Label = %PotMini
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
	var pot := session.pot_view()
	_pot_mini.text = "鍋 残%d杯 / 濃さ%d" % [int(pot.get("remaining", 0)), int(pot.get("strength", 0))] if bool(pot["exists"]) else ""
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


## 「いつもの」「今日」の欄は常に出す（空白の隙間を作らない）。まだ分からないうちは「？」を薄い色で出し、会話で注文を言う行を出した時点で
## 中身が入る（order_card_view の usual_known・today_known）。[聞き直す]は、聞き直せる会話があるとき（名前あり客・1杯の場面のADJUST中）だけ出す。
func _refresh_order_card() -> void:
	var card := session.order_card_view()
	_usual_row.visible = true
	_today_row.visible = true
	var usual_known := bool(card.get("usual_known", false))
	var today_known := bool(card.get("today_known", false))
	_usual_tags.text = "・".join(card["base"]) if usual_known and not (card["base"] as Array).is_empty() else "？"
	if today_known:
		_today_tags.text = "・".join(card["today"]) if not (card["today"] as Array).is_empty() else "いつもどおり"
	else:
		_today_tags.text = "？"
	_usual_tags.modulate = Color(1, 1, 1, 1.0) if _usual_tags.text != "？" else Color(1, 1, 1, 0.4)
	_today_tags.modulate = Color(1, 1, 1, 1.0) if _today_tags.text != "？" else Color(1, 1, 1, 0.4)
	_reask.visible = session.can_reask()
	_reask.disabled = not session.can_reask()


func _refresh_bowl(bowl: Dictionary) -> void:
	var additions: Array = bowl.get("additions", [])
	var damaged: Array = bowl.get("additions_damaged", [])
	for i in range(_slots.get_child_count()):
		var slot: Panel = _slots.get_child(i)
		var label: Label = slot.get_node("Label")
		if i < additions.size():
			var is_damaged := i < damaged.size() and bool(damaged[i])
			label.text = UiLabels.short_name(str(additions[i])) + ("(傷)" if is_damaged else "")
			slot.theme_type_variation = &"PanelSlotDamaged" if is_damaged else &"PanelSlot"
			label.theme_type_variation = &"LabelSlotWarn" if is_damaged else &"LabelSlot"
		else:
			label.text = ""
			slot.theme_type_variation = &"PanelSlotEmpty"


## 減点の予告（寸法表 §5-3）：理由をつないで1行。濃さが理由なら続けて鍋タブでの手当て（強調色）。
## 手当ては今すぐ足せるときだけ出す（依頼書 §3.2）：濃さが最小なら「鍋タブでだし +2」（can_touch_pot と can_add_dashi）、
## 最大なら「鍋タブで水」（can_touch_pot と can_add_water）。足せないときは理由だけ。
## 提供できない理由があるときは、それを注意色で出す。減点が無いときは薄い色で「いまのところ減点なし」。
func _refresh_penalty(bowl: Dictionary) -> void:
	_penalty.text = penalty_bbcode(bowl, session.sale_hint())


## 減点の予告の文（BBCode）。表示の文面だけを作る（判定は sale_hint の理由コード）。
func penalty_bbcode(bowl: Dictionary, hint: Dictionary) -> String:
	if bowl.is_empty():
		return ""
	var warn := "#" + get_theme_color(&"warn", &"UiPalette").to_html(false)
	var accent := "#" + get_theme_color(&"accent", &"UiPalette").to_html(false)
	var pot := session.pot_view()
	var can_dashi: bool = session.can_touch_pot() and bool(pot.get("can_add_dashi", false))
	var can_water: bool = session.can_touch_pot() and bool(pot.get("can_add_water", false))
	var blockers: Array = hint["blockers"]
	var text := ""
	var tip := ""
	if not blockers.is_empty():
		var parts: Array = []
		for code in blockers:
			parts.append(str(BLOCKER_TEXT.get(str(code), str(code))))
		text = "[color=%s]このままでは提供できません: %s[/color]" % [warn, "・".join(parts)]
		if blockers.has("STRENGTH_ZERO") and can_dashi:
			tip = "鍋タブでだし +2"
		elif blockers.has("SHORT_SERVINGS") and can_water:
			tip = "鍋タブで水 +2杯"
	else:
		var reasons: Array = []
		for penalty in hint["penalties"]:
			match str(penalty["code"]):
				"STRENGTH_EXTREME":
					reasons.append("濃さ%d" % int(penalty["value"]))
					if int(penalty["value"]) <= GameState.STRENGTH_MIN:
						tip = "鍋タブでだし +2" if can_dashi else ""
					else:
						tip = "鍋タブで水" if can_water else ""
				"SPOILED":
					reasons.append_array(_spoiled_names(bowl))
		if reasons.is_empty():
			return "減点の予告: いまのところ減点なし"
		text = "[color=%s]減点の予告: %sで1段階下がります。[/color]" % [warn, "・".join(reasons)]
	if tip != "":
		text += "　[color=%s]%s[/color]" % [accent, tip]
	return text


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
	# 分類タブ：具材が先、調味料が後。12個を超えたら「具材1」「具材2」…
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


## 大きい椀の絵の位置に重ねて出すもの：モブの団体の確認＞保存の段階＞「いつもの」の中身（どれか1つ）。
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
