# 初回生成用。再実行すると手の調整が消える
#
# 本番UI（UI準備B）のTheme・シーンの最初の形を作る。以後の調整はGodotのエディタで行う。
# 既にあるファイルは上書きしない（読み飛ばして一覧に出す）。作り直したいときだけ、引数 --overwrite を付ける：
#   godot --headless --path . --script res://tools/build_ui_scenes.gd            # 無いものだけ作る
#   godot --headless --path . --script res://tools/build_ui_scenes.gd -- --overwrite   # 全部作り直す（手の調整が消える）
# 寸法は planning/KAITEN_UI_LAYOUT_2026_10_24.md・SCREENS_UI_LAYOUT_2026_10_24.md の表どおり。
extends SceneTree

const THEME_PATH := "res://resources/ui_theme.tres"
const LEFT_SIDE_PATH := "res://scenes/ui/left_side.tscn"
const GAME_ROOT_PATH := "res://scenes/game_root.tscn"
const HEADER_PATH := "res://scenes/ui/pane_header.tscn"
const BUDGET_PATH := "res://scenes/ui/budget_row.tscn"
const GOODS_ROW_PATH := "res://scenes/ui/goods_row.tscn"
const TIER_CARD_PATH := "res://scenes/ui/tier_card.tscn"
const PANE_MORNING_PATH := "res://scenes/ui/pane_morning.tscn"
const PANE_MARKET_PATH := "res://scenes/ui/pane_market.tscn"
const PANE_BUY_MEAT_PATH := "res://scenes/ui/pane_buy_meat.tscn"
const PANE_BUY_SHOP_PATH := "res://scenes/ui/pane_buy_shop.tscn"
const FONT_PATH := "res://assets/fonts/NotoSansJP[wght].ttf"   # Noto Sans JP（OFL。assets/fonts/OFL.txt）
const WGHT := 2003265652   # OpenType の軸 "wght"（太さ）のタグ

var _overwrite := false


func _initialize() -> void:
	# autoload（GameState など）の解決を待つ。待たないと PlaySession を含むスクリプトが読み込めない
	await process_frame
	_overwrite = OS.get_cmdline_user_args().has("--overwrite")
	var built: Array = []
	var skipped: Array = []
	_build(THEME_PATH, _make_theme, built, skipped)
	_build(LEFT_SIDE_PATH, _make_left_side, built, skipped)
	# 右の枠（UI準備B②）。部品を先に作る（画面がそれを組み込む）
	_build(HEADER_PATH, _make_header, built, skipped)
	_build(BUDGET_PATH, _make_budget_row, built, skipped)
	_build(GOODS_ROW_PATH, _make_goods_row, built, skipped)
	_build(TIER_CARD_PATH, _make_tier_card, built, skipped)
	_build(PANE_MORNING_PATH, _make_pane_morning, built, skipped)
	_build(PANE_MARKET_PATH, _make_pane_market, built, skipped)
	_build(PANE_BUY_MEAT_PATH, _make_pane_buy_meat, built, skipped)
	_build(PANE_BUY_SHOP_PATH, _make_pane_buy_shop, built, skipped)
	_build(GAME_ROOT_PATH, _make_game_root, built, skipped)
	print("作った: %s" % ", ".join(built))
	print("読み飛ばした（既にある）: %s" % ", ".join(skipped))
	quit()


func _build(path: String, maker: Callable, built: Array, skipped: Array) -> void:
	if FileAccess.file_exists(path) and not _overwrite:
		skipped.append(path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var resource: Resource = maker.call()
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("保存に失敗: %s (%d)" % [path, err])
	else:
		built.append(path)


# --- Theme ---

func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	# 既定のフォント：Noto Sans JP（可変フォント）の太さ400。太字の型は太さ700を使う
	var regular := FontVariation.new()
	regular.base_font = load(FONT_PATH)
	regular.variation_opentype = { WGHT: 400 }
	var bold := FontVariation.new()
	bold.base_font = regular.base_font
	bold.variation_opentype = { WGHT: 700 }
	t.default_font = regular
	t.default_font_size = 18
	for key in UiPalette.colors():
		t.set_color(key, "UiPalette", UiPalette.colors()[key])

	t.set_color("font_color", "Label", UiPalette.TEXT)
	t.set_constant("line_spacing", "Label", 0)
	_label_variation(t, "LabelDim", UiPalette.DIM)
	_label_variation(t, "LabelAccent", UiPalette.ACCENT)
	_label_variation(t, "LabelWarn", UiPalette.WARN)
	_label_variation(t, "LabelGood", UiPalette.GOOD)
	_label_variation(t, "LabelSmall", UiPalette.DIM, 13)
	_label_variation(t, "LabelDay", UiPalette.TEXT, 34)
	_label_variation(t, "LabelScreen", UiPalette.DIM, 16)
	_label_variation(t, "LabelMoney", UiPalette.TEXT, 28)
	_label_variation(t, "LabelName", UiPalette.TEXT, 20)
	_label_variation(t, "LabelDialogue", UiPalette.TEXT, 24)
	t.set_constant("line_spacing", "LabelDialogue", 3)
	# 右の枠（UI準備B②）
	_label_variation(t, "LabelHeading", UiPalette.ACCENT, 18)
	_label_variation(t, "LabelSub", UiPalette.DIM, 13)
	_label_variation(t, "LabelCaption", UiPalette.DIM, 12)
	_label_variation(t, "LabelCaptionAccent", UiPalette.ACCENT, 12)
	_label_variation(t, "LabelBody", UiPalette.TEXT, 15)
	_label_variation(t, "LabelShop", UiPalette.TEXT, 16)
	_label_variation(t, "LabelValue", UiPalette.TEXT, 20)
	_label_variation(t, "LabelValueAccent", UiPalette.ACCENT, 20)
	_label_variation(t, "LabelBig", UiPalette.TEXT, 26)
	_label_variation(t, "LabelServings", UiPalette.TEXT, 22)
	_label_variation(t, "LabelPrice", UiPalette.TEXT, 18)
	_label_variation(t, "LabelWarnBody", UiPalette.WARN, 15)
	_label_variation(t, "LabelWarnSmall", UiPalette.WARN, 13)
	_label_variation(t, "LabelGoodBody", UiPalette.GOOD, 15)
	_label_variation(t, "LabelAccentBody", UiPalette.ACCENT, 15)
	_label_variation(t, "LabelRot", UiPalette.WARN, 11)
	_label_variation(t, "LabelTag", UiPalette.DIM, 12)
	var tag_box := _flat(Color(0, 0, 0, 0), UiPalette.LINE, 1, 3)
	tag_box.content_margin_left = 4
	tag_box.content_margin_right = 4
	tag_box.content_margin_top = 0
	tag_box.content_margin_bottom = 0
	t.set_stylebox("normal", "LabelTag", tag_box)
	for bold_type in ["LabelDay", "LabelName", "ButtonPrimary", "LabelHeading"]:
		t.set_font("font", bold_type, bold)

	_button_style(t, "Button", UiPalette.BUTTON, UiPalette.TEXT, 18)
	_button_style(t, "ButtonPrimary", UiPalette.ACCENT, UiPalette.ON_ACCENT, 18)
	_button_style(t, "ButtonSecondary", UiPalette.BUTTON, UiPalette.TEXT, 15)
	_button_style(t, "ButtonChoice", UiPalette.BUTTON, UiPalette.TEXT, 20)
	_button_style(t, "ButtonIcon", UiPalette.BUTTON, UiPalette.TEXT, 11)
	_button_style(t, "ButtonSmall", UiPalette.BUTTON, UiPalette.TEXT, 14)
	_button_style(t, "ButtonRow", UiPalette.BG2, UiPalette.TEXT, 16)    # 店の行（中の文字はラベル）
	_button_style(t, "ButtonCard", UiPalette.BG2, UiPalette.TEXT, 16)   # 鍋の素の段階（中の文字はラベル）

	t.set_stylebox("panel", "Panel", _flat(UiPalette.FRAME, UiPalette.LINE, 1))
	_panel_variation(t, "PanelDark", _flat(Color(UiPalette.BG2, 0.92), UiPalette.LINE, 1))
	_panel_variation(t, "PanelPortrait", _flat(UiPalette.PORTRAIT, UiPalette.LINE, 1))
	_panel_variation(t, "PanelHud", _flat(Color(UiPalette.BG, 0.6), Color(0, 0, 0, 0), 0))
	var plate := _flat(UiPalette.BG2, UiPalette.LINE, 1)
	plate.corner_radius_bottom_left = 0
	plate.corner_radius_bottom_right = 0
	plate.corner_radius_top_left = 10
	plate.corner_radius_top_right = 10
	_panel_variation(t, "PanelNamePlate", plate)
	_panel_variation(t, "PanelBox", _flat(UiPalette.BG2, UiPalette.LINE, 1))
	_panel_variation(t, "PanelBand", _flat(UiPalette.BG2, Color(0, 0, 0, 0), 0, 0))
	_panel_variation(t, "PanelBought", _flat(Color(0, 0, 0, 0), UiPalette.ACCENT, 2))
	return t


func _label_variation(t: Theme, variation: String, color: Color, size: int = 0) -> void:
	t.set_type_variation(variation, "Label")
	t.set_color("font_color", variation, color)
	if size > 0:
		t.set_font_size("font_size", variation, size)


func _panel_variation(t: Theme, variation: String, style: StyleBox) -> void:
	t.set_type_variation(variation, "Panel")
	t.set_stylebox("panel", variation, style)


func _button_style(t: Theme, type_name: String, bg: Color, fg: Color, size: int) -> void:
	if type_name != "Button":
		t.set_type_variation(type_name, "Button")
	var is_primary := bg == UiPalette.ACCENT
	var normal := _flat(bg, UiPalette.LINE if not is_primary else UiPalette.ACCENT, 1)
	var hover := _flat(bg.lightened(0.12), UiPalette.ACCENT if not is_primary else UiPalette.TEXT, 1)
	var pressed := _flat(bg.darkened(0.15), UiPalette.ACCENT, 1)
	var disabled := _flat(UiPalette.BG2, UiPalette.LINE, 1)
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, hover)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("disabled", type_name, disabled)
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	t.set_color("font_color", type_name, fg)
	t.set_color("font_hover_color", type_name, fg)
	t.set_color("font_pressed_color", type_name, fg)
	t.set_color("font_focus_color", type_name, fg)
	t.set_color("font_disabled_color", type_name, Color(UiPalette.DIM, 0.55))
	t.set_font_size("font_size", type_name, size)


# --- シーンを組む道具 ---

func _node(parent: Node, node: Node, node_name: String, rect: Rect2, owner_node: Node, unique: bool = false) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = owner_node
	if unique:
		node.unique_name_in_owner = true
	if node is BaseButton:
		(node as BaseButton).focus_mode = Control.FOCUS_NONE   # マウスで遊ぶ。Space・Enter は会話を進めるのに使う
	if node is Control:
		var c: Control = node
		if parent is Container:
			# 入れ物の子は位置を入れ物が決める。大きさは最小の大きさとして持つ
			c.layout_mode = 2
			if rect.size != Vector2.ZERO:
				c.custom_minimum_size = rect.size
		else:
			# 位置と大きさは offset で直に持つ（size に入れると、ヘッドレスの仮の文字の高さで大きく丸められて保存される）
			c.layout_mode = 0
			c.offset_left = rect.position.x
			c.offset_top = rect.position.y
			c.offset_right = rect.end.x
			c.offset_bottom = rect.end.y
	return node


func _instance(parent: Node, path: String, node_name: String, rect: Rect2, owner_node: Node, unique: bool = false) -> Control:
	var inst: Control = (load(path) as PackedScene).instantiate()
	inst.name = node_name
	parent.add_child(inst)
	inst.owner = owner_node
	if unique:
		inst.unique_name_in_owner = true
	if parent is Container:
		inst.layout_mode = 2
	else:
		inst.layout_mode = 0
		inst.position = rect.position
	return inst


func _panel(parent: Node, node_name: String, variation: String, rect: Rect2, owner_node: Node, unique: bool = false) -> Panel:
	var p := Panel.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(parent, p, node_name, rect, owner_node, unique)
	return p


func _button(parent: Node, node_name: String, text: String, variation: String, rect: Rect2, owner_node: Node,
		unique: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	_node(parent, b, node_name, rect, owner_node, unique)
	return b


## 右の枠の画面の外枠（420×672の Panel）と見出しの帯。
func _pane_root(node_name: String, script_path: String) -> Panel:
	var root := Panel.new()
	root.name = node_name
	root.set_script(load(script_path))
	root.layout_mode = 3
	root.position = Vector2.ZERO
	root.size = Vector2(420, 672)
	_instance(root, HEADER_PATH, "Header", Rect2(2, 2, 416, 49), root, true)
	return root


func _label(parent: Node, node_name: String, text: String, rect: Rect2, owner_node: Node, variation: String = "",
		unique: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != "":
		l.theme_type_variation = variation
	_node(parent, l, node_name, rect, owner_node, unique)
	return l


func _pack(root: Node) -> PackedScene:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack に失敗 (%d)" % err)
	return packed


# --- 左側（共通）---

func _make_left_side() -> PackedScene:
	var root := Control.new()
	root.name = "LeftSide"
	root.set_script(load("res://scripts/ui/left_side.gd"))
	root.layout_mode = 3
	root.position = Vector2.ZERO
	root.size = Vector2(820, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 上部：日・時間帯（または画面名）
	var hud := Panel.new()
	hud.theme_type_variation = "PanelHud"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, hud, "HudDate", Rect2(24, 14, 249, 52), root, true)
	# 34px の文字は Label の最小の高さが約48になるので、寸法表の 95×34 の箱と中心をそろえる
	_label(hud, "DayLabel", "Day 1", Rect2(12, 2, 95, 48), root, "LabelDay", true)
	_label(hud, "ScreenName", "朝", Rect2(121, 12, 116, 28), root, "LabelScreen", true)
	var gauge := Control.new()
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(hud, gauge, "TimeGauge", Rect2(121, 12, 116, 28), root, true)
	for i in range(3):
		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_node(gauge, slot, "Slot%d" % (i + 1), Rect2(i * 40, 0, 36, 28), root)
		var bar := ColorRect.new()
		bar.color = UiPalette.LINE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_node(slot, bar, "Bar", Rect2(0, 0, 36, 6), root)
		_label(slot, "Name", "宵", Rect2(0, 8, 36, 20), root, "LabelSmall", false, HORIZONTAL_ALIGNMENT_CENTER)

	# 所持金・評判（右端 x=796、枠なしの文字）
	var money_box := HBoxContainer.new()
	money_box.alignment = BoxContainer.ALIGNMENT_END
	money_box.add_theme_constant_override("separation", 12)
	money_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, money_box, "MoneyRep", Rect2(546, 20, 250, 41), root, true)   # 28px の所持金が収まる高さ。中心は寸法表の y=26・高さ29の箱と同じ
	var money := Label.new()
	money.text = "¥0"
	money.theme_type_variation = "LabelMoney"
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(money_box, money, "MoneyLabel", Rect2(), root, true)
	var rep := Label.new()
	rep.text = "評判 0"
	rep.theme_type_variation = "LabelScreen"
	rep.size_flags_vertical = Control.SIZE_SHRINK_END
	rep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(money_box, rep, "ReputationLabel", Rect2(), root, true)

	# 立ち絵枠（絵は仮）
	var portrait := Panel.new()
	portrait.theme_type_variation = "PanelPortrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, portrait, "Portrait", Rect2(210, 64, 400, 490), root, true)
	_label(portrait, "Placeholder", "立ち絵（仮）", Rect2(0, 0, 400, 490), root, "LabelDim", false, HORIZONTAL_ALIGNMENT_CENTER)

	# 選択肢（縦に並べる、間隔12）
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	_node(root, choices, "Choices", Rect2(210, 352, 400, 52), root, true)

	# 会話枠
	var box := Panel.new()
	box.theme_type_variation = "PanelDark"
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_node(root, box, "DialogueBox", Rect2(24, 536, 772, 160), root, true)
	var text := _label(box, "DialogueText", "", Rect2(26, 22, 720, 116), root, "LabelDialogue", true)
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label(box, "PageMark", "▼", Rect2(660, 128, 90, 24), root, "LabelDim", true, HORIZONTAL_ALIGNMENT_RIGHT)

	# 名前の札（会話枠の上に重なる）
	var plate := Panel.new()
	plate.theme_type_variation = "PanelNamePlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, plate, "NamePlate", Rect2(44, 498, 200, 40), root, true)
	_label(plate, "NameLabel", "", Rect2(0, 0, 200, 40), root, "LabelName", true, HORIZONTAL_ALIGNMENT_CENTER)

	# スマホ・ログのアイコン、既読スキップ
	var phone := Button.new()
	phone.text = "スマホ"
	phone.theme_type_variation = "ButtonIcon"
	_node(root, phone, "PhoneIcon", Rect2(686, 480, 52, 52), root, true)
	var log_icon := Button.new()
	log_icon.text = "ログ"
	log_icon.theme_type_variation = "ButtonIcon"
	_node(root, log_icon, "LogIcon", Rect2(744, 480, 52, 52), root, true)
	var skip := Button.new()
	skip.text = "既読スキップ"
	skip.theme_type_variation = "ButtonSmall"
	# 既読スキップは会話枠の右下、「▼」の左（plan Q4）
	_node(root, skip, "SkipButton", Rect2(604, 664, 100, 28), root, true)
	return _pack(root)


# --- 右の枠の部品（UI準備B②）---

## 見出しの帯（枠内 (2,2) 416×46）：左に画面名（18px 太字・強調色）、右に補足（13px）、下に3pxの強調色の線。
func _make_header() -> PackedScene:
	var root := Control.new()
	root.name = "PaneHeader"
	root.layout_mode = 3
	root.size = Vector2(416, 49)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel(root, "Band", "PanelBand", Rect2(0, 0, 416, 46), root)
	_label(root, "Title", "画面名", Rect2(12, 0, 250, 46), root, "LabelHeading")
	_label(root, "Sub", "", Rect2(262, 0, 142, 46), root, "LabelSub", false, HORIZONTAL_ALIGNMENT_RIGHT)
	var line := ColorRect.new()
	line.color = UiPalette.ACCENT
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, line, "Line", Rect2(0, 46, 416, 3), root)
	return _pack(root)


## 予算の3つ（388×55、1つ125×55）：残金／確保／使える（使えるは強調色）。
func _make_budget_row() -> PackedScene:
	var root := Control.new()
	root.name = "BudgetRow"
	root.layout_mode = 3
	root.size = Vector2(388, 55)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cells := [["Money", "残金", "LabelValue"], ["Reserved", "確保", "LabelValue"], ["Usable", "使える", "LabelValueAccent"]]
	for i in range(cells.size()):
		var cell := _panel(root, cells[i][0], "PanelBox", Rect2(i * 131.5, 0, 125, 55), root)
		_label(cell, "Caption", cells[i][1], Rect2(10, 3, 105, 18), root, "LabelCaption")
		_label(cell, "Value", "¥0", Rect2(10, 21, 105, 30), root, cells[i][2], false, HORIZONTAL_ALIGNMENT_RIGHT)
	return _pack(root)


## 購入画面の商品の行（388×61）。寸法表 SCREENS_UI_LAYOUT §6。
func _make_goods_row() -> PackedScene:
	var root := Panel.new()
	root.name = "GoodsRow"
	root.set_script(load("res://scripts/ui/goods_row.gd"))
	root.theme_type_variation = "PanelBox"
	root.layout_mode = 3
	root.size = Vector2(388, 61)
	root.custom_minimum_size = Vector2(388, 61)
	# 1行目：品名・タグ・「腐る」（価格に重ならないよう幅を切る）
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.clip_contents = true
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, tags, "Tags", Rect2(12, 4, 204, 28), root)
	var name_label := _label(tags, "Name", "品名", Rect2(), root, "LabelShop")
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rot := _label(tags, "Rot", "腐る", Rect2(), root, "LabelRot")
	rot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(root, "Detail", "3個 / 単価8 / 在庫4(新鮮3・傷1)", Rect2(12, 32, 220, 24), root, "LabelSub")
	_label(root, "Price", "¥0", Rect2(220, 10, 88, 40), root, "LabelPrice", false, HORIZONTAL_ALIGNMENT_RIGHT)
	_button(root, "BuyButton", "買う", "ButtonSmall", Rect2(316, 10, 64, 40), root)
	return _pack(root)


## 鍋の素の1段階（124×119）。寸法表 SCREENS_UI_LAYOUT §5。
func _make_tier_card() -> PackedScene:
	var root := Button.new()
	root.name = "TierCard"
	root.set_script(load("res://scripts/ui/tier_card.gd"))
	root.theme_type_variation = "ButtonCard"
	root.focus_mode = Control.FOCUS_NONE
	root.layout_mode = 3
	root.size = Vector2(124, 119)
	root.custom_minimum_size = Vector2(124, 119)
	_label(root, "Label", "中", Rect2(0, 6, 124, 26), root, "LabelShop", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(root, "Servings", "11杯", Rect2(0, 32, 124, 34), root, "LabelServings", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(root, "Price", "¥0", Rect2(0, 66, 124, 26), root, "LabelAccent", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(root, "Note", "濃さ3から", Rect2(0, 92, 124, 20), root, "LabelCaption", false, HORIZONTAL_ALIGNMENT_CENTER)
	var frame := _panel(root, "BoughtFrame", "PanelBought", Rect2(0, 0, 124, 119), root)
	frame.visible = false
	return _pack(root)


## 右の枠：朝（昨夜の成績）。寸法表 SCREENS_UI_LAYOUT §2。
func _make_pane_morning() -> PackedScene:
	var root := _pane_root("PaneMorning", "res://scripts/ui/pane_morning.gd")
	var record := Control.new()
	record.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, record, "RecordBoxes", Rect2(0, 0, 420, 600), root, true)
	var sales := _panel(record, "SalesBox", "PanelBox", Rect2(16, 62, 388, 71), root)
	_label(sales, "Caption", "売上", Rect2(12, 4, 120, 18), root, "LabelCaption")
	_label(sales, "SalesValue", "¥0", Rect2(12, 22, 180, 42), root, "LabelBig", true)
	_label(sales, "ServedLabel", "提供 0杯 / 注文0杯", Rect2(190, 22, 186, 42), root, "LabelBody", true, HORIZONTAL_ALIGNMENT_RIGHT)
	var grades_box := _panel(record, "GradesBox", "PanelBox", Rect2(16, 143, 388, 96), root)
	_label(grades_box, "Caption", "出来", Rect2(12, 4, 120, 18), root, "LabelCaption")
	var grades := Control.new()
	grades.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(grades_box, grades, "Grades", Rect2(12, 30, 366, 54), root, true)
	var names := ["GREAT", "GOOD", "OK", "BAD"]
	for i in range(names.size()):
		var cell := _panel(grades, names[i], "PanelBand", Rect2(i * 93, 0, 87, 54), root)
		_label(cell, "Name", names[i], Rect2(0, 2, 87, 18), root, "LabelCaptionAccent" if i == 0 else "LabelCaption", false,
			HORIZONTAL_ALIGNMENT_CENTER)
		_label(cell, "Count", "0", Rect2(0, 20, 87, 32), root, "LabelValueAccent" if i == 0 else "LabelValue", false,
			HORIZONTAL_ALIGNMENT_CENTER)
	var short_box := _panel(record, "ShortBox", "PanelBox", Rect2(16, 249, 388, 95), root)
	_label(short_box, "Caption", "足りなかった・廃棄", Rect2(12, 4, 200, 18), root, "LabelCaption")
	_label(short_box, "ShortLabel", "足りなかった 0杯", Rect2(12, 26, 364, 28), root, "LabelWarnBody", true)
	var spoil := _label(short_box, "SpoilLabel", "廃棄 なし", Rect2(12, 56, 364, 32), root, "LabelBody", true)
	spoil.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var money_box := _panel(record, "MoneyBox", "PanelBox", Rect2(16, 354, 388, 123), root)
	_label(money_box, "Caption", "今朝のお金", Rect2(12, 4, 200, 18), root, "LabelCaption")
	_label(money_box, "ReputationLabel", "評判 0 → 0", Rect2(12, 26, 364, 28), root, "LabelBody", true)
	_label(money_box, "CostLabel", "今朝の運営費 −¥0", Rect2(12, 56, 364, 28), root, "LabelWarnBody", true)
	_label(money_box, "UsableLabel", "使える現金 ¥0", Rect2(12, 86, 364, 28), root, "LabelAccentBody", true)
	var none := _label(root, "NoRecord", "初日。昨夜の成績はまだ無い。", Rect2(16, 62, 388, 40), root, "LabelDim", true)
	none.visible = false
	_button(root, "PrimaryButton", "スマホを見る", "ButtonPrimary", Rect2(16, 610, 388, 46), root, true)
	return _pack(root)


## 右の枠：市場（店選び）。寸法表 SCREENS_UI_LAYOUT §4。
func _make_pane_market() -> PackedScene:
	var root := _pane_root("PaneMarket", "res://scripts/ui/pane_market.gd")
	_instance(root, BUDGET_PATH, "Budget", Rect2(16, 62, 388, 55), root, true)
	var stalls := VBoxContainer.new()
	stalls.add_theme_constant_override("separation", 6)
	_node(root, stalls, "Stalls", Rect2(16, 127, 388, 408), root, true)
	for i in range(6):
		var row := _button(stalls, "Stall%d" % (i + 1), "", "ButtonRow", Rect2(0, 0, 388, 63), root)
		_label(row, "Name", "店名", Rect2(12, 6, 220, 26), root, "LabelShop")
		var wares := _label(row, "Wares", "扱う品", Rect2(12, 34, 364, 22), root, "LabelSub")
		wares.clip_text = true
		wares.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label(row, "State", "", Rect2(186, 6, 190, 26), root, "LabelSub", false, HORIZONTAL_ALIGNMENT_RIGHT)
		var frame := _panel(row, "BoughtFrame", "PanelBought", Rect2(0, 0, 388, 63), root)
		frame.visible = false
	_button(root, "ExitButton", "市場を出る", "ButtonPrimary", Rect2(16, 586, 388, 46), root, true)
	_label(root, "ExitNote", "徴収日は、出るときに水道代を払う", Rect2(16, 636, 388, 22), root, "LabelCaption", false,
		HORIZONTAL_ALIGNMENT_CENTER)
	return _pack(root)


## 右の枠：購入（食肉仲卸＝張記）。寸法表 SCREENS_UI_LAYOUT §5。
func _make_pane_buy_meat() -> PackedScene:
	var root := _pane_root("PaneBuyMeat", "res://scripts/ui/pane_buy_meat.gd")
	_instance(root, BUDGET_PATH, "Budget", Rect2(16, 62, 388, 55), root, true)
	_label(root, "TiersCaption", "鍋の素", Rect2(16, 127, 388, 22), root, "LabelCaption")
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 8)
	_node(root, tiers, "Tiers", Rect2(16, 155, 388, 119), root, true)
	for i in range(3):
		_instance(tiers, TIER_CARD_PATH, "Tier%d" % (i + 1), Rect2(), root)
	# 商品の行（追加購入。Day2から）。5品は「店選びへ」の上に入りきらないので、縦に送れる枠に入れる
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_node(root, scroll, "GoodsScroll", Rect2(16, 313, 388, 269), root, true)
	var goods := VBoxContainer.new()
	goods.set_script(load("res://scripts/ui/goods_list.gd"))
	goods.add_theme_constant_override("separation", 6)
	goods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node(scroll, goods, "Goods", Rect2(), root, true)
	_label(root, "WarnNote", "鍋の素を買うまで、ほかの店へは行けない", Rect2(16, 590, 388, 22), root, "LabelWarnSmall", true,
		HORIZONTAL_ALIGNMENT_CENTER)
	_button(root, "BackButton", "店選びへ", "ButtonSecondary", Rect2(16, 616, 388, 40), root, true)
	return _pack(root)


## 右の枠：購入（ほかの店）。寸法表 SCREENS_UI_LAYOUT §6。
func _make_pane_buy_shop() -> PackedScene:
	var root := _pane_root("PaneBuyShop", "res://scripts/ui/pane_buy_shop.gd")
	_instance(root, BUDGET_PATH, "Budget", Rect2(16, 62, 388, 55), root, true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_node(root, scroll, "Scroll", Rect2(16, 127, 388, 479), root, true)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node(scroll, content, "Content", Rect2(), root)
	var goods := VBoxContainer.new()
	goods.set_script(load("res://scripts/ui/goods_list.gd"))
	goods.add_theme_constant_override("separation", 6)
	_node(content, goods, "Goods", Rect2(), root, true)
	var bought := _panel(content, "BoughtBox", "PanelBox", Rect2(0, 0, 388, 67), root, true)
	_label(bought, "Caption", "この店で買った", Rect2(12, 4, 200, 18), root, "LabelCaption")
	var bought_list := _label(bought, "BoughtList", "", Rect2(12, 24, 364, 38), root, "LabelWarnSmall", true)
	bought_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bought_list.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_button(root, "BackButton", "店選びへ戻る", "ButtonSecondary", Rect2(16, 616, 388, 40), root, true)
	return _pack(root)
# --- ルート ---

func _make_game_root() -> PackedScene:
	var root := Control.new()
	root.name = "GameRoot"
	root.set_script(load("res://scripts/ui/game_root.gd"))
	root.layout_mode = 3
	root.position = Vector2.ZERO
	root.size = Vector2(1280, 720)
	root.theme = load(THEME_PATH)

	var bg := ColorRect.new()
	bg.color = UiPalette.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, bg, "Background", Rect2(0, 0, 1280, 720), root)

	var left: Control = (load(LEFT_SIDE_PATH) as PackedScene).instantiate()
	root.add_child(left)
	left.owner = root
	left.unique_name_in_owner = true

	var right := Control.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, right, "RightPane", Rect2(836, 24, 420, 672), root, true)
	# 右の枠の画面は同じ位置に重ね、ルートがいまの1つだけを出す
	for pane in [["PaneMorning", PANE_MORNING_PATH], ["PaneMarket", PANE_MARKET_PATH], ["PaneBuyMeat", PANE_BUY_MEAT_PATH],
			["PaneBuyShop", PANE_BUY_SHOP_PATH]]:
		var inst := _instance(right, pane[1], pane[0], Rect2(0, 0, 420, 672), root, true)
		inst.visible = false


	var session := Node.new()
	session.set_script(load("res://scripts/play_session.gd"))
	session.name = "Session"
	root.add_child(session)
	session.owner = root
	session.unique_name_in_owner = true
	return _pack(root)
