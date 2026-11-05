extends RefCounted
class_name UiInventoryList
## 持ち物の一覧（スマホの「持ち物」タブの中身。UI準備I3）。中身は PlaySession.inventory_view()（読むだけ）。
## 上から：最終日の注意（最終日だけ）・性質チェック（10の札。新鮮が1つ以上＝点灯・傷んだ分だけ＝半点灯・無い＝暗く）・味（調味料）の材料・具の材料。
## 材料は在庫が1つ以上のものだけ（名前・札（言葉）・個数・新鮮／傷の内訳）。
## 市場にいるあいだ（view に かごの分がある＝inventory_view(かご)）は、行の個数の左に「＋N（かご）」（強調色）を足し、
## かごの分でだけ点く札は「＋」を付けて半分の明るさにする（傷んだ分だけの半点灯とは「＋」で見分ける。UI準備P）。

const WIDTH := 380.0


## content（縦に並べる入れ物）に、持ち物の一覧を足す。
static func fill(content: VBoxContainer, view: Dictionary) -> void:
	if bool(view["final_day"]):
		content.add_child(_label("残った分は持ち越せない", &"LabelWarnSmall"))
	content.add_child(_label("性質チェック", &"LabelSub"))
	var has_cart := false
	for row in (view["flavors"] as Array) + (view["toppings"] as Array):
		has_cart = has_cart or int(row.get("cart", 0)) > 0
	for kind in ["flavor", "topping"]:
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		flow.custom_minimum_size.x = WIDTH
		var head := _label("味" if kind == "flavor" else "具", &"LabelCaption", false)
		head.custom_minimum_size.x = 20.0
		flow.add_child(head)
		for entry in view["traits"]:
			if TagWords.kind(str(entry["tag"])) != kind:
				continue
			var chip := UiTagChips.make(str(entry["tag"]))
			var alpha: float = { "lit": 1.0, "cart": 0.6, "half": 0.6 }.get(str(entry["state"]), 0.25)
			chip.modulate = Color(1, 1, 1, alpha)
			if entry["state"] == "cart":
				chip.text = "＋" + chip.text   # かごの分でだけ点く札（買えば点く）
			chip.set_meta("state", entry["state"])
			chip.set_meta("tag", str(entry["tag"]))
			flow.add_child(chip)
		content.add_child(flow)
	var legend := _label("明るい＝新鮮なものがある　半分＝傷んだ分だけ　暗い＝無い", &"LabelCaption")
	legend.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	content.add_child(legend)
	if has_cart:
		content.add_child(_label("＋付き＝かごの分で点く（まだ買っていない）", &"LabelCaption"))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6.0
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)
	_add_section(content, "味（調味料）", view["flavors"])
	_add_section(content, "具", view["toppings"])


static func _add_section(content: VBoxContainer, title: String, items: Array) -> void:
	content.add_child(_label(title, &"LabelSub"))
	if items.is_empty():
		content.add_child(_label("なし", &"LabelDim"))
	for item in items:
		content.add_child(_row(item))


static func _label(text: String, variation: StringName, full_width: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size.x = WIDTH if full_width else 0.0
	return label


## 材料1つの行（1行）：名前・札・（傷があれば新鮮／傷）・個数。
static func _row(item: Dictionary) -> Control:
	var damaged := int(item["damaged"])
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	line.custom_minimum_size.x = WIDTH
	var name_label := _label(str(item["name"]), &"LabelBody", false)
	name_label.custom_minimum_size.x = 84.0
	line.add_child(name_label)
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 2)
	UiTagChips.fill(chips, item["tags"], true)
	line.add_child(chips)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spacer)
	if damaged > 0:
		line.add_child(_label("新鮮%d・傷%d" % [int(item["fresh"]), damaged], &"LabelWarnSmall", false))
	if int(item.get("cart", 0)) > 0:
		line.add_child(_label("＋%d（かご）" % int(item["cart"]), &"LabelSubAccent", false))
	var count := _label("×%d" % (int(item["fresh"]) + damaged), &"LabelShop", false)
	count.custom_minimum_size.x = 34.0
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(count)
	return line
