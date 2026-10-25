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
const INGREDIENT_BUTTON_PATH := "res://scenes/ui/ingredient_button.tscn"
const KAITEN_POT_PATH := "res://scenes/ui/kaiten_pot.tscn"
const KAITEN_TOPPING_PATH := "res://scenes/ui/kaiten_topping.tscn"
const PANE_KAITEN_PATH := "res://scenes/ui/pane_kaiten.tscn"
const PANE_CLOSE_PATH := "res://scenes/ui/pane_close.tscn"
const FULL_PREP_PATH := "res://scenes/ui/full_prep.tscn"
const FULL_RESULT_PATH := "res://scenes/ui/full_result.tscn"
const FULL_GAMEOVER_PATH := "res://scenes/ui/full_gameover.tscn"
const PANE_PHONE_PATH := "res://scenes/ui/pane_phone.tscn"
const PANE_LOG_PATH := "res://scenes/ui/pane_log.tscn"
const TNUM := 1953396077   # OpenType の機能 "tnum"（数字の幅をそろえる）のタグ
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
	# 開店の操作エリア（UI準備B③）
	_build(INGREDIENT_BUTTON_PATH, _make_ingredient_button, built, skipped)
	_build(KAITEN_POT_PATH, _make_kaiten_pot, built, skipped)
	_build(KAITEN_TOPPING_PATH, _make_kaiten_topping, built, skipped)
	_build(PANE_KAITEN_PATH, _make_pane_kaiten, built, skipped)
	# 閉店と全面（UI準備B④）
	_build(PANE_CLOSE_PATH, _make_pane_close, built, skipped)
	_build(FULL_PREP_PATH, _make_full_prep, built, skipped)
	_build(FULL_RESULT_PATH, _make_full_result, built, skipped)
	_build(FULL_GAMEOVER_PATH, _make_full_gameover, built, skipped)
	# スマホ・会話ログ（UI準備B⑤）
	_build(PANE_PHONE_PATH, _make_pane_phone, built, skipped)
	_build(PANE_LOG_PATH, _make_pane_log, built, skipped)
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
	# 開店の操作エリア（UI準備B③）
	_label_variation(t, "LabelPriceWarn", UiPalette.WARN, 18)
	_label_variation(t, "LabelSubAccent", UiPalette.ACCENT, 13)
	_label_variation(t, "LabelSlot", UiPalette.TEXT, 14)
	_label_variation(t, "LabelSlotWarn", UiPalette.WARN, 14)
	_label_variation(t, "LabelOrder", UiPalette.TEXT, 14)
	_label_variation(t, "LabelIngName", UiPalette.TEXT, 12)
	_label_variation(t, "LabelIngCount", UiPalette.DIM, 13)
	_label_variation(t, "LabelPotName", UiPalette.TEXT, 20)
	_label_variation(t, "LabelPotCount", UiPalette.DIM, 14)
	t.set_type_variation("RichPenalty", "RichTextLabel")   # 減点の予告（12px・2行まで）
	t.set_color("default_color", "RichPenalty", UiPalette.DIM)
	t.set_font_size("normal_font_size", "RichPenalty", 12)
	t.set_constant("line_separation", "RichPenalty", -2)
	# 数字の幅をそろえる（OpenType の tnum）。所持金・評判・価格・杯数などの数字の型に使う。
	# 同梱の Noto Sans JP は tnum を持たないが、数字は初めから同じ幅（UI準備B③で計測）。
	var numeric := FontVariation.new()
	numeric.base_font = regular.base_font
	numeric.variation_opentype = { WGHT: 400 }
	numeric.opentype_features = { TNUM: 1 }
	for numeric_type in ["LabelMoney", "LabelValue", "LabelValueAccent", "LabelBig", "LabelServings", "LabelPrice",
			"LabelPriceWarn", "LabelPotCount", "LabelIngCount"]:
		t.set_font("font", numeric_type, numeric)
	# 閉店と全面（UI準備B④）
	_label_variation(t, "LabelPrepTitle", UiPalette.TEXT, 34)
	_label_variation(t, "LabelTitleWarn", UiPalette.WARN, 32)
	_label_variation(t, "LabelResult", UiPalette.TEXT, 18)
	t.set_font("font", "LabelPrepTitle", bold)
	t.set_font("font", "LabelTitleWarn", bold)
	# スマホ・会話ログ（UI準備B⑤）
	_label_variation(t, "LabelPhoneHeadline", UiPalette.TEXT, 16)
	_label_variation(t, "LabelPhoneBody", UiPalette.TEXT, 14)
	_label_variation(t, "LabelLogNarration", UiPalette.DIM, 14)
	t.set_font("font", "LabelPhoneHeadline", bold)
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
	_button_style(t, "ButtonCategory", UiPalette.BG2, UiPalette.DIM, 14)      # 分類タブ
	_button_style(t, "ButtonCategoryOn", UiPalette.BG2, UiPalette.TEXT, 14)   # 分類タブ（開いている）
	t.set_stylebox("normal", "ButtonCategoryOn", _flat(UiPalette.BUTTON, UiPalette.ACCENT, 1))
	_button_style(t, "ButtonIngredient", UiPalette.BUTTON, UiPalette.TEXT, 12)   # 具材ボタン（中の文字はラベル）
	_button_style(t, "ButtonDamaged", UiPalette.BG2, UiPalette.WARN, 11)         # 具材ボタンの右端「傷N」
	for state in ["normal", "hover", "pressed"]:
		t.set_stylebox(state, "ButtonDamaged", _flat(UiPalette.BG2 if state != "hover" else UiPalette.BUTTON, UiPalette.WARN, 1, 3))
	_button_style(t, "ButtonPot", UiPalette.BUTTON, UiPalette.TEXT, 16)   # だし・水（中の文字はラベル）
	# 鍋／トッピングのタブ：枠なし。選ばれている方は下線（シーンの Underline）と明るい文字
	for tab_type in ["ButtonTab", "ButtonTabOn"]:
		_button_style(t, tab_type, Color(0, 0, 0, 0), UiPalette.DIM if tab_type == "ButtonTab" else UiPalette.TEXT, 18)
		t.set_stylebox("normal", tab_type, _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
		t.set_stylebox("hover", tab_type, _flat(UiPalette.BG2, Color(0, 0, 0, 0), 0, 0))
		t.set_stylebox("pressed", tab_type, _flat(UiPalette.BG2, Color(0, 0, 0, 0), 0, 0))

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
	_panel_variation(t, "PanelSlot", _flat(UiPalette.BG2, UiPalette.LINE, 1))
	_panel_variation(t, "PanelSlotDamaged", _flat(UiPalette.BG2, UiPalette.WARN, 2))
	_panel_variation(t, "PanelSlotEmpty", _flat(Color(0, 0, 0, 0), Color(UiPalette.LINE, 0.6), 1))
	_panel_variation(t, "PanelToday", _flat(UiPalette.BG2, UiPalette.ACCENT, 1))
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
# --- 開店の操作エリア（UI準備B③）---

## 具材ボタン（93×42）：本体（短縮名・「×在庫数」）と、右端の「傷N」（28×40）。寸法表 KAITEN_UI_LAYOUT §4。
func _make_ingredient_button() -> PackedScene:
	var root := Control.new()
	root.name = "IngredientButton"
	root.set_script(load("res://scripts/ui/ingredient_button.gd"))
	root.layout_mode = 3
	root.size = Vector2(93, 42)
	root.custom_minimum_size = Vector2(93, 42)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var main := _button(root, "MainButton", "", "ButtonIngredient", Rect2(0, 0, 93, 42), root)
	var name_label := _label(main, "Name", "名前", Rect2(5, 2, 58, 38), root, "LabelIngName")
	name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	name_label.max_lines_visible = 2
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label(main, "Count", "×0", Rect2(5, 22, 58, 18), root, "LabelIngCount", false, HORIZONTAL_ALIGNMENT_RIGHT)
	var damaged := _button(root, "DamagedButton", "傷\n0", "ButtonDamaged", Rect2(64, 1, 28, 40), root)
	damaged.visible = false
	return _pack(root)


## 鍋の状態。寸法表 KAITEN_UI_LAYOUT §3。
func _make_kaiten_pot() -> PackedScene:
	var root := Control.new()
	root.name = "KaitenPot"
	root.set_script(load("res://scripts/ui/kaiten_pot.gd"))
	root.layout_mode = 3
	root.size = Vector2(420, 672)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(root, "RemainCaption", "残り杯数", Rect2(16, 62, 160, 27), root, "LabelShop")
	_label(root, "RemainValue", "0杯", Rect2(176, 62, 180, 27), root, "LabelPrice", true, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(root, "RemainMax", "/0", Rect2(358, 62, 46, 27), root, "LabelSub", true)
	var bar := ColorRect.new()
	bar.color = UiPalette.LINE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, bar, "Bar", Rect2(16, 93, 388, 14), root)
	var fill := ColorRect.new()
	fill.color = UiPalette.ACCENT
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, fill, "BarFill", Rect2(16, 93, 388, 14), root, true)
	_label(root, "StrengthCaption", "濃さ", Rect2(16, 124, 160, 27), root, "LabelShop")
	_label(root, "StrengthValue", "3", Rect2(224, 124, 180, 27), root, "LabelPrice", true, HORIZONTAL_ALIGNMENT_RIGHT)
	var scale := Control.new()
	scale.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, scale, "Scale", Rect2(16, 154, 194, 14), root, true)
	for i in range(5):
		var cell := ColorRect.new()
		cell.color = UiPalette.LINE
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_node(scale, cell, "Cell%d" % (i + 1), Rect2(i * 40, 0, 34, 14), root)
	var note := _label(root, "StrengthNote", "濃さ1は評価が1段階下がります", Rect2(16, 172, 388, 19), root, "LabelWarnSmall", true)
	note.visible = false
	# だし（左）・水（右）。右寄せ。上から名前・残り・効果（寸法表 §3）
	var dashi := _button(root, "DashiButton", "", "ButtonPot", Rect2(224, 203, 86, 96), root, true)
	_label(dashi, "Name", "だし", Rect2(0, 8, 86, 28), root, "LabelPotName", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(dashi, "Count", "残り0", Rect2(0, 38, 86, 20), root, "LabelPotCount", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(dashi, "Effect", "濃さ +2", Rect2(0, 60, 86, 18), root, "LabelSub", false, HORIZONTAL_ALIGNMENT_CENTER)
	var water := _button(root, "WaterButton", "", "ButtonPot", Rect2(318, 203, 86, 96), root, true)
	_label(water, "Name", "水", Rect2(0, 8, 86, 28), root, "LabelPotName", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(water, "Count", "残り0", Rect2(0, 38, 86, 20), root, "LabelPotCount", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(water, "Effect", "濃さ −2", Rect2(0, 58, 86, 18), root, "LabelSub", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(water, "Effect2", "+2杯", Rect2(0, 75, 86, 18), root, "LabelSub", false, HORIZONTAL_ALIGNMENT_CENTER)
	var art := _panel(root, "PotArt", "PanelBox", Rect2(16, 310, 388, 346), root)
	_label(art, "Placeholder", "鍋（仮）", Rect2(0, 0, 388, 346), root, "LabelDim", false, HORIZONTAL_ALIGNMENT_CENTER)
	# 鍋が尽きた保留（または椀の途中で鍋が足りず足せるものも無い）：鍋の絵に重ねる
	var shortage := _panel(root, "ShortageBox", "PanelSlotDamaged", Rect2(16, 420, 388, 176), root, true)
	shortage.visible = false
	var text := _label(shortage, "ShortageText", "", Rect2(14, 10, 360, 58), root, "LabelBody", true)
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_button(shortage, "ResumeButton", "営業を続ける", "ButtonPrimary", Rect2(14, 74, 360, 44), root, true)
	_button(shortage, "CloseButton", "閉店", "ButtonSecondary", Rect2(14, 126, 360, 40), root, true)
	var close_night := _button(root, "CloseNightButton", "閉店する", "ButtonPrimary", Rect2(16, 610, 388, 46), root, true)
	close_night.visible = false
	return _pack(root)


## トッピングの状態。寸法表 KAITEN_UI_LAYOUT §4。
func _make_kaiten_topping() -> PackedScene:
	var root := Control.new()
	root.name = "KaitenTopping"
	root.set_script(load("res://scripts/ui/kaiten_topping.gd"))
	root.layout_mode = 3
	root.size = Vector2(420, 672)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 注文カード（いつもの／今日。「今日」は枠と色で強調）と[聞き直す]
	var usual := _panel(root, "UsualRow", "PanelBox", Rect2(16, 62, 303, 28), root, true)
	_label(usual, "Caption", "いつもの", Rect2(8, 0, 70, 28), root, "LabelCaption")
	_label(usual, "UsualTags", "", Rect2(78, 0, 218, 28), root, "LabelOrder", true)
	var today := _panel(root, "TodayRow", "PanelToday", Rect2(16, 96, 303, 28), root, true)
	_label(today, "Caption", "今日", Rect2(8, 0, 70, 28), root, "LabelCaptionAccent")
	_label(today, "TodayTags", "", Rect2(78, 0, 218, 28), root, "LabelOrder", true)
	_button(root, "ReaskButton", "聞き直す", "ButtonSmall", Rect2(329, 62, 75, 62), root, true)
	# いまの椀（3枠。押せない）
	_label(root, "BowlCaption", "いまの椀(3枠)", Rect2(16, 132, 388, 19), root, "LabelSub")
	var slots := Control.new()
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, slots, "Slots", Rect2(16, 155, 387, 48), root, true)
	for i in range(3):
		var slot := _panel(slots, "Slot%d" % (i + 1), "PanelSlotEmpty", Rect2(i * 131, 0, 125, 48), root)
		_label(slot, "Label", "", Rect2(0, 0, 125, 48), root, "LabelSlot", false, HORIZONTAL_ALIGNMENT_CENTER)
	# 減点の予告（理由をつないで1行。濃さが理由なら続けて鍋タブでの手当てを強調色で。入りきらなければ2行）
	var penalty := RichTextLabel.new()
	penalty.bbcode_enabled = true
	penalty.scroll_active = false
	penalty.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	penalty.theme_type_variation = "RichPenalty"
	penalty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, penalty, "Penalty", Rect2(16, 206, 388, 30), root, true)
	# 分類タブ（具材が先、調味料が後）と具材の一覧（4列×3行）
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_node(root, tabs, "Tabs", Rect2(16, 236, 388, 30), root, true)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_node(root, grid, "Grid", Rect2(16, 272, 390, 138), root, true)
	for i in range(12):
		_instance(grid, INGREDIENT_BUTTON_PATH, "Item%d" % (i + 1), Rect2(), root)
	# 大きい椀の絵（仮）。「いつもの」「保存」の中身・モブの団体の確認は、ここに重ねて出す（plan Q14）
	var art := _panel(root, "BowlArt", "PanelBox", Rect2(16, 418, 388, 119), root)
	_label(art, "Placeholder", "椀（仮）", Rect2(0, 0, 388, 119), root, "LabelDim", false, HORIZONTAL_ALIGNMENT_CENTER)
	var group := _panel(root, "GroupBox", "PanelToday", Rect2(16, 418, 388, 119), root, true)
	group.visible = false
	var group_text := _label(group, "GroupText", "", Rect2(12, 6, 364, 48), root, "LabelBody", true)
	group_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	group_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var group_buttons := HBoxContainer.new()
	group_buttons.add_theme_constant_override("separation", 6)
	_node(group, group_buttons, "Buttons", Rect2(12, 66, 364, 42), root)
	for spec in [["GroupServe", "提供"], ["GroupRetry", "残りに挑戦"], ["GroupDecline", "注文を断る"]]:
		var b := _button(group_buttons, spec[0], spec[1], "ButtonSmall", Rect2(0, 0, 0, 42), root, true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
	var menu := _panel(root, "RecipeMenu", "PanelToday", Rect2(16, 418, 388, 119), root, true)
	menu.visible = false
	_label(menu, "RecipeCaption", "", Rect2(12, 4, 364, 20), root, "LabelCaption", true)
	var menu_buttons := GridContainer.new()
	menu_buttons.columns = 3
	menu_buttons.add_theme_constant_override("h_separation", 5)
	menu_buttons.add_theme_constant_override("v_separation", 5)
	_node(menu, menu_buttons, "RecipeButtons", Rect2(12, 26, 364, 86), root, true)
	# 鍋の小表示・提供・下の4つ
	_label(root, "PotMini", "鍋 残0杯 / 濃さ0", Rect2(16, 546, 388, 20), root, "LabelSub", true)
	_button(root, "ServeButton", "提供", "ButtonPrimary", Rect2(16, 571, 388, 45), root, true)
	var bottoms := [["UsualButton", "いつもの"], ["SaveButton", "保存"], ["DiscardButton", "廃棄"], ["DeclineButton", "断る"]]
	for i in range(bottoms.size()):
		_button(root, bottoms[i][0], bottoms[i][1], "ButtonSmall", Rect2(16 + i * 99, 622, 93, 34), root, true)
	return _pack(root)


## 開店の操作エリア：鍋／トッピングのタブと、その中身。寸法表 KAITEN_UI_LAYOUT §2。
func _make_pane_kaiten() -> PackedScene:
	var root := Panel.new()
	root.name = "PaneKaiten"
	root.set_script(load("res://scripts/ui/pane_kaiten.gd"))
	root.layout_mode = 3
	root.size = Vector2(420, 672)
	_button(root, "PotTab", "鍋", "ButtonTabOn", Rect2(2, 2, 208, 46), root, true)
	_button(root, "ToppingTab", "トッピング", "ButtonTab", Rect2(210, 2, 208, 46), root, true)
	var dot := _label(root, "PotDot", "●", Rect2(122, 2, 24, 46), root, "LabelWarnSmall", true)
	dot.visible = false
	var underline := ColorRect.new()
	underline.color = UiPalette.ACCENT
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, underline, "Underline", Rect2(2, 45, 208, 3), root, true)
	var line := ColorRect.new()
	line.color = UiPalette.LINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, line, "TabLine", Rect2(2, 48, 416, 1), root)
	_instance(root, KAITEN_POT_PATH, "Pot", Rect2(0, 0, 420, 672), root, true)
	var topping := _instance(root, KAITEN_TOPPING_PATH, "Topping", Rect2(0, 0, 420, 672), root, true)
	topping.visible = false
	return _pack(root)


# --- 閉店と全面（UI準備B④）---

## 右の枠：閉店（今夜の結果と修繕基金）。寸法表 SCREENS_UI_LAYOUT §7。
func _make_pane_close() -> PackedScene:
	var root := _pane_root("PaneClose", "res://scripts/ui/pane_close.gd")
	var sales := _panel(root, "SalesBox", "PanelBox", Rect2(16, 62, 388, 99), root)
	_label(sales, "Caption", "売上", Rect2(12, 4, 120, 18), root, "LabelCaption")
	_label(sales, "SalesValue", "¥0", Rect2(12, 22, 180, 42), root, "LabelBig", true)
	_label(sales, "ServedLabel", "提供 0杯 / 注文0杯", Rect2(190, 22, 186, 42), root, "LabelBody", true, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(sales, "ShortLabel", "足りなかった 0杯", Rect2(12, 66, 364, 26), root, "LabelWarnBody", true)
	var grades_box := _panel(root, "GradesBox", "PanelBox", Rect2(16, 171, 388, 96), root)
	_label(grades_box, "Caption", "出来", Rect2(12, 4, 120, 18), root, "LabelCaption")
	var grades := Control.new()
	grades.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(grades_box, grades, "Grades", Rect2(12, 22, 366, 50), root, true)
	var names := ["GREAT", "GOOD", "OK", "BAD"]
	for i in range(names.size()):
		var cell := _panel(grades, names[i], "PanelBand", Rect2(i * 93, 0, 87, 50), root)
		_label(cell, "Name", names[i], Rect2(0, 0, 87, 18), root, "LabelCaptionAccent" if i == 0 else "LabelCaption", false,
			HORIZONTAL_ALIGNMENT_CENTER)
		_label(cell, "Count", "0", Rect2(0, 18, 87, 30), root, "LabelValueAccent" if i == 0 else "LabelValue", false,
			HORIZONTAL_ALIGNMENT_CENTER)
	_label(grades_box, "Note", "評判は明日の朝に決まる", Rect2(12, 74, 364, 18), root, "LabelCaption")
	var fund := _panel(root, "FundBox", "PanelBox", Rect2(16, 276, 388, 233), root, true)
	_label(fund, "Caption", "修繕基金(任意・積まなくてもよい)", Rect2(12, 4, 364, 20), root, "LabelSub")
	var wait := _label(fund, "FundWait", "閉店の語りを読み終えると積める", Rect2(12, 30, 364, 40), root, "LabelDim", true)
	wait.visible = false
	var targets := VBoxContainer.new()
	targets.add_theme_constant_override("separation", 4)
	_node(fund, targets, "Targets", Rect2(12, 28, 364, 128), root, true)
	for i in range(4):
		var row := _button(targets, "Target%d" % (i + 1), "", "ButtonRow", Rect2(0, 0, 364, 29), root)
		_label(row, "Mark", "", Rect2(6, 0, 18, 29), root, "LabelAccentBody")
		_label(row, "Name", "対象", Rect2(24, 0, 200, 29), root, "LabelBody")
		_label(row, "State", "0/0", Rect2(224, 0, 132, 29), root, "LabelSub", false, HORIZONTAL_ALIGNMENT_RIGHT)
	var info := _label(fund, "FundInfo", "", Rect2(12, 158, 364, 30), root, "LabelSub", true)
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	_node(fund, steps, "Steps", Rect2(12, 191, 364, 34), root, true)
	for i in range(2):
		var b := _button(steps, "Step%d" % (i + 1), "+10 積む", "ButtonSmall", Rect2(0, 0, 179, 34), root)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(root, "NextButton", "次の日へ", "ButtonPrimary", Rect2(16, 610, 388, 46), root, true)
	return _pack(root)


## 全面の地（静止画1枚の仮）。左側の会話・上部の数字・アイコンは出さない。
func _full_root(node_name: String, script_path: String, still_text: String) -> Control:
	var root := Control.new()
	root.name = node_name
	root.set_script(load(script_path))
	root.layout_mode = 3
	root.size = Vector2(1280, 720)
	var still := ColorRect.new()
	still.color = UiPalette.BG2
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, still, "Still", Rect2(0, 0, 1280, 720), root)
	_label(root, "StillNote", still_text, Rect2(24, 680, 400, 24), root, "LabelCaption")
	return root


## 全面：仕込み。寸法表 SCREENS_UI_LAYOUT §8（中央・約206×107）。
func _make_full_prep() -> PackedScene:
	var root := _full_root("FullPrep", "res://scripts/ui/full_prep.gd", "静止画（仕込み・仮）")
	_label(root, "Title", "仕込み中", Rect2(440, 300, 400, 48), root, "LabelPrepTitle", false, HORIZONTAL_ALIGNMENT_CENTER)
	_label(root, "Detail", "鍋の素 中・11杯・濃さ3", Rect2(440, 350, 400, 28), root, "LabelResult", true, HORIZONTAL_ALIGNMENT_CENTER)
	var dots := Control.new()
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, dots, "Dots", Rect2(616, 392, 48, 10), root, true)
	for i in range(3):
		var dot := ColorRect.new()
		dot.color = UiPalette.LINE
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_node(dots, dot, "Dot%d" % (i + 1), Rect2(i * 19, 0, 10, 10), root)
	var open := _button(root, "OpenButton", "開店する", "ButtonPrimary", Rect2(540, 440, 200, 46), root, true)
	open.visible = false
	return _pack(root)


## 全面：結果。寸法表 SCREENS_UI_LAYOUT §8（枠 (260,80) 760×560、タブ1つ252×49、ボタン1つ170×46）。
func _make_full_result() -> PackedScene:
	var root := _full_root("FullResult", "res://scripts/ui/full_result.gd", "静止画（結果・仮）")
	var frame := _panel(root, "Frame", "Panel", Rect2(260, 80, 760, 560), root, true)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var tabs := Control.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(frame, tabs, "Tabs", Rect2(2, 2, 756, 49), root, true)
	for i in range(3):
		_button(tabs, "Tab%d" % (i + 1), "%d" % (i + 1), "ButtonTab", Rect2(i * 252, 0, 252, 49), root)
	var underline := ColorRect.new()
	underline.color = UiPalette.ACCENT
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(frame, underline, "Underline", Rect2(2, 48, 252, 3), root, true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_node(frame, scroll, "BodyScroll", Rect2(24, 66, 712, 360), root, true)
	var body := _label(scroll, "Body", "", Rect2(), root, "LabelResult", true)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var exits := HBoxContainer.new()
	exits.add_theme_constant_override("separation", 8)
	_node(frame, exits, "Exits", Rect2(24, 436, 712, 46), root, true)
	for spec in [["RunAgainButton", "もう一度（Day1の朝から）"], ["LastMorningButton", "最後の朝から"], ["NewRunButton", "新しい周"]]:
		var b := _button(exits, spec[0], spec[1], "ButtonSecondary", Rect2(0, 0, 0, 46), root, true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(frame, "TitleButton", "タイトルへ", "ButtonSecondary", Rect2(380, 498, 170, 46), root, true)
	_button(frame, "NextButton", "次へ", "ButtonPrimary", Rect2(566, 498, 170, 46), root, true)
	return _pack(root)


## 全面：ゲームオーバー。寸法表 SCREENS_UI_LAYOUT §8（枠 (320,234) 640×251、ボタン1つ223×46）。
func _make_full_gameover() -> PackedScene:
	var root := _full_root("FullGameOver", "res://scripts/ui/full_gameover.gd", "静止画（ゲームオーバー・仮）")
	var frame := _panel(root, "Frame", "Panel", Rect2(320, 234, 640, 251), root, true)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_label(frame, "Title", "ゲームオーバー", Rect2(24, 18, 592, 48), root, "LabelTitleWarn", false, HORIZONTAL_ALIGNMENT_CENTER)
	var detail := _label(frame, "Detail", "", Rect2(24, 74, 592, 90), root, "LabelResult", true, HORIZONTAL_ALIGNMENT_CENTER)
	detail.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_button(frame, "RetryButton", "Day 1 の朝からやり直す", "ButtonPrimary", Rect2(89, 185, 223, 46), root, true)
	_button(frame, "QuitButton", "終わる", "ButtonSecondary", Rect2(328, 185, 223, 46), root, true)
	return _pack(root)


# --- スマホ・会話ログ（UI準備B⑤）---

## 右の枠：スマホ。寸法表 SCREENS_UI_LAYOUT §3（上の帯 (2,2) 416×28、タブ (2,30) 1つ139×46、閉じる (16,616) 388×40）。
func _make_pane_phone() -> PackedScene:
	var root := Panel.new()
	root.name = "PanePhone"
	root.set_script(load("res://scripts/ui/pane_phone.gd"))
	root.layout_mode = 3
	root.size = Vector2(420, 672)
	_panel(root, "TopBand", "PanelBand", Rect2(2, 2, 416, 28), root)
	_label(root, "TopLeft", "スマホ", Rect2(14, 2, 200, 28), root, "LabelCaption")
	_label(root, "TopRight", "Day 1", Rect2(206, 2, 200, 28), root, "LabelCaption", true, HORIZONTAL_ALIGNMENT_RIGHT)
	var tabs := Control.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, tabs, "Tabs", Rect2(2, 30, 417, 46), root, true)
	var titles := ["SNS", "ニュース", "レシピ"]
	for i in range(3):
		var b := _button(tabs, "Tab%d" % (i + 1), titles[i], "ButtonTab", Rect2(i * 139, 0, 139, 46), root)
		b.add_theme_font_size_override("font_size", 17)
	var underline := ColorRect.new()
	underline.color = UiPalette.ACCENT
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, underline, "Underline", Rect2(0, 73, 139, 3), root, true)
	var line := ColorRect.new()
	line.color = UiPalette.LINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, line, "TabLine", Rect2(2, 76, 416, 1), root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_node(root, scroll, "Scroll", Rect2(16, 90, 388, 516), root, true)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node(scroll, content, "Content", Rect2(), root, true)
	_button(root, "CloseButton", "閉じる", "ButtonSecondary", Rect2(16, 616, 388, 40), root, true)
	return _pack(root)


## 右の枠：会話ログ。寸法表に無いので、右の枠の共通の形（見出しの帯・中身の余白14・一番下の補助ボタン）で出す。
func _make_pane_log() -> PackedScene:
	var root := _pane_root("PaneLog", "res://scripts/ui/pane_log.gd")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_node(root, scroll, "Scroll", Rect2(16, 62, 388, 544), root, true)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node(scroll, content, "Content", Rect2(), root, true)
	_button(root, "CloseButton", "閉じる", "ButtonSecondary", Rect2(16, 616, 388, 40), root, true)
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
			["PaneBuyShop", PANE_BUY_SHOP_PATH], ["PaneKaiten", PANE_KAITEN_PATH],
			["PaneClose", PANE_CLOSE_PATH], ["PanePhone", PANE_PHONE_PATH], ["PaneLog", PANE_LOG_PATH]]:
		var inst := _instance(right, pane[1], pane[0], Rect2(0, 0, 420, 672), root, true)
		inst.visible = false
	# 全面（仕込み・結果・ゲームオーバー）。出ている間は左側と右の枠を隠す
	var full := Control.new()
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node(root, full, "Full", Rect2(0, 0, 1280, 720), root, true)
	for screen in [["FullPrep", FULL_PREP_PATH], ["FullResult", FULL_RESULT_PATH], ["FullGameOver", FULL_GAMEOVER_PATH]]:
		var inst := _instance(full, screen[1], screen[0], Rect2(0, 0, 1280, 720), root, true)
		inst.visible = false

	var session := Node.new()
	session.set_script(load("res://scripts/play_session.gd"))
	session.name = "Session"
	root.add_child(session)
	session.owner = root
	session.unique_name_in_owner = true
	return _pack(root)
