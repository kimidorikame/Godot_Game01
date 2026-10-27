extends RefCounted
class_name UiTagChips
## タグの言葉の小さな札（UI準備F）。客側（いつもの・今日）と材料側（市場の商品・具材ボタン・椀の枠）で同じ見た目：
## 味の軸と具の軸で札の色が2系統（LabelTagFlavor／LabelTagTopping。狭い所は同じ色・形の LabelTagFlavorSmall／LabelTagToppingSmall）。
## 言葉は TagWords（data/tag_words.json）。表示だけで、内部名（HOT 等）は画面に出さない。


## 札を1枚作る。compact＝狭い所（具材ボタン・椀の枠）用の小さい版（色・形は同じ）。
static func make(tag: String, compact: bool = false) -> Label:
	var label := Label.new()
	label.text = TagWords.word(tag)
	var flavor := TagWords.kind(tag) != "topping"
	if compact:
		label.theme_type_variation = &"LabelTagFlavorSmall" if flavor else &"LabelTagToppingSmall"
	else:
		label.theme_type_variation = &"LabelTagFlavor" if flavor else &"LabelTagTopping"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 入れ物の中身を、tags の札だけにする。
static func fill(container: Control, tags: Array, compact: bool = false) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	for tag in tags:
		container.add_child(make(str(tag), compact))
