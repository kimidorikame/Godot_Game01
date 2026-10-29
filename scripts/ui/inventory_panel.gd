extends Control
class_name UiInventoryPanel
## 持ち物パネル（朝・市場・準備の左側。UI準備I2）。在庫が1つ以上の材料（味と具に分ける。名前・札・個数・新鮮／傷）と、10の性質の点灯。
## 中身は PlaySession.inventory_view()（読むだけ）。かごに入れた分は含めない。ログを開いたら隠す・営業中は出さない（具材ボタンに在庫が出ている）。
## 配置：立ち絵が出ない場面（朝・市場など）は左の領域を広く使い、材料の一覧（味｜具の2列）と性質チェックを横に並べる。
## 立ち絵が出る場面（準備の会話など）は、立ち絵（210〜610）を避けて、左の列（材料）と右の列（性質チェック）に分ける。
## 一覧は縦に送れる（あふれるときだけ、ホイールを受ける＝あふれないときは会話を進めるクリックを塞がない）。

const NARROW_LIST_WIDTH := 180.0
const WIDE_LIST_WIDTH := 572.0
const TRAITS_WIDTH := 192.0
const AREA_HEIGHT := 420.0

var _wide := true

@onready var _list_panel: Panel = %ListPanel
@onready var _list_title: Label = %ListTitle
@onready var _list_note: Label = %ListNote
@onready var _scroll: ScrollContainer = %ListScroll
@onready var _content: HBoxContainer = %ListContent
@onready var _traits_panel: Panel = %TraitsPanel
@onready var _traits: VBoxContainer = %TraitsContent


## wide＝立ち絵が出ていない（左の領域全体を使う）。
func refresh(session: PlaySession, wide: bool) -> void:
	_wide = wide
	var view := session.inventory_view()
	_layout(bool(view["final_day"]))
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var flavors: Array = view["flavors"]
	var toppings: Array = view["toppings"]
	var rows := 0
	if wide:
		_content.add_child(_column("味（調味料）", flavors))
		_content.add_child(_column("具", toppings))
		rows = maxi(flavors.size(), toppings.size())
	else:
		var column := _column("味（調味料）", flavors)
		_fill_column(column, "具", toppings)
		_content.add_child(column)
		rows = flavors.size() + toppings.size() + 2
	if flavors.is_empty() and toppings.is_empty():
		var empty := Label.new()
		empty.text = "（在庫なし）"
		empty.theme_type_variation = &"LabelDim"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(empty)
	# あふれるときだけホイールを受ける（クリックは会話を進める下の部品へ通す）
	var need := float(rows) * (26.0 if wide else 40.0) + (0.0 if wide else 20.0)
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if need > _scroll.size.y else Control.MOUSE_FILTER_IGNORE
	_fill_traits(view["traits"])


func _layout(final_day: bool) -> void:
	var list_width := WIDE_LIST_WIDTH if _wide else NARROW_LIST_WIDTH
	_list_panel.position = Vector2(0, 0)
	_list_panel.size = Vector2(list_width, AREA_HEIGHT)
	_traits_panel.position = Vector2(580, 0) if _wide else Vector2(592, 0)
	_traits_panel.size = Vector2(TRAITS_WIDTH if _wide else 180.0, 400.0)   # スマホ・ログのボタン（y480〜）に重ならない高さ
	_list_note.visible = final_day
	_list_note.size.x = list_width - 20.0
	var top := 44.0 if final_day else 26.0
	_scroll.position = Vector2(4, top)
	_scroll.size = Vector2(list_width - 8.0, AREA_HEIGHT - top - 4.0)
	_content.custom_minimum_size.x = list_width - 20.0


## 材料の列（見出し＋行）。
func _column(title: String, items: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size.x = 266.0 if _wide else 164.0
	_fill_column(column, title, items)
	return column


## 列に、見出しと材料の行を足す。
func _fill_column(column: VBoxContainer, title: String, items: Array) -> void:
	var head := Label.new()
	head.text = title
	head.theme_type_variation = &"LabelSub"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	if items.is_empty():
		var none := Label.new()
		none.text = "なし"
		none.theme_type_variation = &"LabelDim"
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(none)
	for item in items:
		column.add_child(_row(item))


## 材料1つの行：広いときは1行（名前・札・個数・傷）、狭いときは2行（名前と個数／札と傷）。
func _row(item: Dictionary) -> Control:
	var damaged := int(item["damaged"])
	var count_text := "×%d" % (int(item["fresh"]) + damaged)
	var detail := "新鮮%d・傷%d" % [int(item["fresh"]), damaged] if damaged > 0 else ""
	var name_label := Label.new()
	name_label.text = str(item["name"])
	name_label.theme_type_variation = &"LabelBody"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count_label := Label.new()
	count_label.text = count_text
	count_label.theme_type_variation = &"LabelShop"
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 2)
	UiTagChips.fill(chips, item["tags"], true)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.theme_type_variation = &"LabelWarnSmall"
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _wide:
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 6)
		name_label.custom_minimum_size.x = 78.0
		count_label.custom_minimum_size.x = 30.0
		line.add_child(name_label)
		line.add_child(chips)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(spacer)
		line.add_child(detail_label)
		line.add_child(count_label)
		return line
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(count_label)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 4)
	bottom.add_child(chips)
	bottom.add_child(detail_label)
	box.add_child(top)
	box.add_child(bottom)
	return box


## 性質チェック：10の札（味→具）。明るい＝新鮮が1つ以上／半点灯＝傷んだ分だけ／暗い＝無い。
func _fill_traits(traits: Array) -> void:
	for child in _traits.get_children():
		_traits.remove_child(child)
		child.queue_free()
	for kind in ["flavor", "topping"]:
		var head := Label.new()
		head.text = "味" if kind == "flavor" else "具"
		head.theme_type_variation = &"LabelSub"
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_traits.add_child(head)
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.custom_minimum_size.x = 170.0
		for entry in traits:
			if TagWords.kind(str(entry["tag"])) != kind:
				continue
			var chip := UiTagChips.make(str(entry["tag"]))
			chip.modulate = Color(1, 1, 1, 1.0) if entry["state"] == "lit" else (Color(1, 1, 1, 0.6) if entry["state"] == "half" else Color(1, 1, 1, 0.25))
			chip.set_meta("state", entry["state"])
			flow.add_child(chip)
		_traits.add_child(flow)
