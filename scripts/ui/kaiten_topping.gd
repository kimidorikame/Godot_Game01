extends Control
class_name UiKaitenTopping
## 開店の操作エリア：トッピング。寸法表 KAITEN_UI_LAYOUT §4・§5。
## UI準備S（配置の整理）：上から 好物の行（order_card_view の favorite。知らない客・モブ・客がいないときは「—」）、
## いまの椀の3枠（bowl_view。傷んだ具材は注意色の枠で「豆腐(傷)」）と鍋の小さな絵（UiPotGauge。量＝残りの杯数・色＝濃さ。数字は出さない）、
## 案内文と減点の予告（sale_hint）、分類タブ（調味料が先・具材が後。1タブ6個まで。最初に開くのは具材）、具材ボタン（本体＝新鮮、右上＝傷んだ側。
## select_ingredient）、大きい椀の絵、提供（complete_input）、一杯を捨てる｜断る。
## 「前回」「今日」の欄・[聞き直す]・[いつもの]・[レシピ保存]は画面から外した（UI準備S。注文はセリフとログで確かめる。
## session の reask・recipe_adjust_buttons・start_recipe_save などの仕組みは消さずに残す）。
## モブの団体の確認は、大きい椀の絵の位置に重ねて出し、出ている間は椀の絵を隠す（plan Q14）。
## 短縮名を使うのはこの画面だけ（UiLabels.short_name）。

const PER_TAB := 6   # 1ページの具材ボタン（UI準備P：文字を大きくして3列×2段。以前は4列×2段の8個）。超えたら「具材1」「具材2」…
## 味・具が欠ける以外の、提供できない理由（味・具の欠けは案内文で出す。UI準備P）。
const BLOCKER_TEXT := { "STRENGTH_ZERO": "濃さ0", "SHORT_SERVINGS": "鍋が足りない" }

var session: PlaySession = null

## 好物を知らない・出す客がいないときの好物の行の文字（UI準備S。行は消さずに残す）。
const NO_FAVORITE := "—"

## 表示だけの状態：開いている分類タブ（{kind, page}）、タブを決めた客。
var _tab := { "kind": "topping", "page": 0 }
var _tab_customer := ""

@onready var _favorite_row: Control = %FavoriteRow
@onready var _favorite: Label = %FavoriteLabel
@onready var _slots: Control = %Slots
@onready var _bowl_art: Control = $BowlArt
@onready var _pot_gauge: UiPotGauge = %PotGauge
@onready var _penalty: RichTextLabel = %Penalty
@onready var _tabs: HBoxContainer = %Tabs
@onready var _grid: GridContainer = %Grid
@onready var _group_box: Control = %GroupBox
@onready var _group_text: Label = %GroupText
@onready var _group_serve: Button = %GroupServe
@onready var _group_retry: Button = %GroupRetry
@onready var _group_decline: Button = %GroupDecline
@onready var _serve: Button = %ServeButton
@onready var _discard: Button = %DiscardButton
@onready var _decline: Button = %DeclineButton

var _items: Array = []   # いまのタブに並べている品目 [{ id, fresh, damaged, main, dmg }]


func _ready() -> void:
	_serve.pressed.connect(_on_serve_pressed)
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
		# 客が替わったら、分類タブは具材（最初に開くのは具材。並びは調味料が先）に戻す
		_tab_customer = customer
		_tab = { "kind": "topping", "page": 0 }
	var adjusting := is_adjusting()
	var group := session.mob_group_choice()
	_refresh_favorite()
	_refresh_bowl(bowl)
	_refresh_penalty(bowl)
	_refresh_items(adjusting and group.is_empty())
	_pot_gauge.set_pot(session.pot_view())
	_serve.disabled = not (adjusting and group.is_empty() and session.can_complete_input())
	_discard.disabled = not (adjusting and group.is_empty() and session.can_discard())
	_decline.disabled = not (adjusting and group.is_empty() and session.can_decline())
	_refresh_overlay(group)


## 好物の行（UI準備S）：行は常に出す。好物を知った名前あり客は材料名、それ以外（知らない客・モブ・客がいない）は「—」（薄い色）。
## 見出し「好物」＝LabelCaption、材料名＝LabelOrder（14）。知る時刻は favorite_reveal のまま（order_card_view の favorite）。
func _refresh_favorite() -> void:
	var favorite := str(session.order_card_view().get("favorite", ""))
	_favorite_row.visible = true
	_favorite.text = favorite if favorite != "" else NO_FAVORITE
	_favorite.modulate = Color(1, 1, 1, 1.0) if favorite != "" else Color(1, 1, 1, 0.4)


## 適正の外か（0以下・1・5）。鍋タブ（UiKaitenPot._outside_fit）と同じ線引き。鍋の小さな絵（UiPotGauge）の縁の注意色に使う。
static func strength_outside_fit(value: int, pot: Dictionary) -> bool:
	return value <= int(pot.get("strength_floor", GameState.STRENGTH_HARD_FLOOR)) \
		or value == int(pot.get("strength_min", GameState.STRENGTH_MIN)) or value == int(pot.get("strength_max", GameState.STRENGTH_MAX))


## いまの椀の3枠（UI準備S：幅100・高さ68。札は折り返す〔HFlowContainer〕）。札が1段なら名前と札を枠の上下の真ん中に、
## 札が2つ（腱肉）なら幅に入らないので2段にして、名前を上に寄せる。
const SLOT_ONE_ROW := { "label": 12.0, "chips": 36.0 }
const SLOT_TWO_ROWS := { "label": 1.0, "chips": 25.0 }
const SLOT_LABEL_H := 22.0
const SLOT_CHIP_ROW_H := 20.0


func _refresh_bowl(bowl: Dictionary) -> void:
	var additions: Array = bowl.get("additions", [])
	var damaged: Array = bowl.get("additions_damaged", [])
	for i in range(_slots.get_child_count()):
		var slot: Panel = _slots.get_child(i)
		var label: Label = slot.get_node("Label")
		var tags: Array = []
		if i < additions.size():
			var is_damaged := i < damaged.size() and bool(damaged[i])
			label.text = UiLabels.short_name(str(additions[i])) + ("(傷)" if is_damaged else "")
			tags = Ingredients.tags_for(str(additions[i]))
			UiTagChips.fill(slot.get_node("Chips"), tags, true)   # その材料のタグの言葉の札（UI準備F）
			slot.theme_type_variation = &"PanelSlotDamaged" if is_damaged else &"PanelSlot"
			label.theme_type_variation = &"LabelSlotWarn" if is_damaged else &"LabelSlot"
		else:
			label.text = ""
			UiTagChips.fill(slot.get_node("Chips"), [], true)
			slot.theme_type_variation = &"PanelSlotEmpty"
		_place_slot(slot, 2 if tags.size() >= 2 else 1)


## 枠の中の名前と札の縦の位置（rows＝札の段数）。
func _place_slot(slot: Control, rows: int) -> void:
	var spot: Dictionary = SLOT_TWO_ROWS if rows >= 2 else SLOT_ONE_ROW
	var label: Control = slot.get_node("Label")
	var chips: Control = slot.get_node("Chips")
	label.offset_top = float(spot["label"])
	label.offset_bottom = float(spot["label"]) + SLOT_LABEL_H
	chips.offset_top = float(spot["chips"])
	chips.offset_bottom = float(spot["chips"]) + SLOT_CHIP_ROW_H * rows + 2.0 * (rows - 1)


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
	# 分類タブ：調味料が先、具材が後（UI準備S。調味料は1タブに収まる）。1ページ（PER_TAB）を超えたら「具材1」「具材2」…
	var tabs: Array = []
	for kind in ["seasoning", "topping"]:
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


## 大きい椀の絵の位置に重ねて出すもの：モブの団体の確認（出ている間は椀の絵を隠す）。
func _refresh_overlay(group: Dictionary) -> void:
	_group_box.visible = not group.is_empty()
	if not group.is_empty():
		var achievable := int(group["achievable"])
		_group_text.text = "注文は%d人分。いまの鍋と具材で出せるのは%d人分。" % [int(group["ordered"]), achievable]
		_group_serve.text = "%d人分を提供" % achievable
		_group_serve.disabled = not bool(group["can_serve"])
		_group_retry.visible = bool(group["can_retry"])
		_group_retry.text = "残り%d人に挑戦" % int(group["remaining"])
	_bowl_art.visible = not _group_box.visible


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
