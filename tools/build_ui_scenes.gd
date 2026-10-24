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

var _overwrite := false


func _initialize() -> void:
	# autoload（GameState など）の解決を待つ。待たないと PlaySession を含むスクリプトが読み込めない
	await process_frame
	_overwrite = OS.get_cmdline_user_args().has("--overwrite")
	var built: Array = []
	var skipped: Array = []
	_build(THEME_PATH, _make_theme, built, skipped)
	_build(LEFT_SIDE_PATH, _make_left_side, built, skipped)
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

	_button_style(t, "Button", UiPalette.BUTTON, UiPalette.TEXT, 18)
	_button_style(t, "ButtonPrimary", UiPalette.ACCENT, UiPalette.ON_ACCENT, 18)
	_button_style(t, "ButtonSecondary", UiPalette.BUTTON, UiPalette.TEXT, 15)
	_button_style(t, "ButtonChoice", UiPalette.BUTTON, UiPalette.TEXT, 20)
	_button_style(t, "ButtonIcon", UiPalette.BUTTON, UiPalette.TEXT, 11)
	_button_style(t, "ButtonSmall", UiPalette.BUTTON, UiPalette.TEXT, 14)

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
	if node is Control:
		var c: Control = node
		c.layout_mode = 0
		c.position = rect.position
		c.size = rect.size
	return node


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
	_node(root, skip, "SkipButton", Rect2(560, 486, 118, 40), root, true)
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

	var session := Node.new()
	session.set_script(load("res://scripts/play_session.gd"))
	session.name = "Session"
	root.add_child(session)
	session.owner = root
	session.unique_name_in_owner = true
	return _pack(root)
