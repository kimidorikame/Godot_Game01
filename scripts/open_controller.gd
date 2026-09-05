extends RefCounted
class_name OpenController
## OPEN の間だけ生存する客キューの管理役（DESIGN.md 4章「客ループは下位に隔離」）。
##
## Event の中身は持たない。「今どの客か / 次へ / さばき切ったか」だけを答える薄い部品。
## 接客そのものの再生は、客ごとの EventRunner（DebugPanel が flow.runner に載せる）に任せる。
## OPEN が終われば捨てる（RefCounted なので参照が切れれば解放される）。

var queue: Array = []      # 客 id の並び（STEP 6 は ["delivery_man"] の1人）
var index: int = 0         # いま何人目か（0起点）

# 現在の客に出す椀。形は { customer_id, additions[] }（DESIGN.md 9.5 STEP 11）。
# tags は持たない＝二重の正本を作らず、必要時に bowl_final_tags() で計算する。
# 客が替わるたび（_init / advance_customer）ここで新規に作り直す。
# 客がいない（キューが空 / さばき切った）ときは {}。
var current_bowl: Dictionary = {}


func _init(customer_queue: Array = []) -> void:
	queue = customer_queue
	index = 0
	current_bowl = _new_bowl(current_customer())


## いま接客中の客 id。キューを超えていたら null。
func current_customer() -> Variant:
	if index < 0 or index >= queue.size():
		return null
	return queue[index]


## まだ接客すべき客が残っているか。
func has_more() -> bool:
	return index < queue.size()


## 次の客へ。呼び出し側は「今の客の runner が DONE」を確認してから呼ぶこと。
## 椀もここで新規に作り直す（前の客の additions を持ち越さない）。
func advance_customer() -> void:
	index += 1
	current_bowl = _new_bowl(current_customer())


## キューを全員さばき切ったか（OPEN を終えて CLOSE へ進んでよい合図）。
func is_open_done() -> bool:
	return index >= queue.size()


## 客 id から空の椀を作る。客がいなければ {}（current_bowl の「なし」状態）。
func _new_bowl(customer_id: Variant) -> Dictionary:
	if customer_id == null:
		return {}
	return { "customer_id": customer_id, "additions": [] }


## 現在の椀に具材 id を1つ足す。ADJUST の選択肢を受けた側（DebugPanel）から呼ぶ。
## "none" は「何も足さない」の合図（STEP 14 の二択で使う。STEP 13 では未使用）。
## 椀が無い（current_bowl == {}）ときも何もしない。
func add_to_bowl(ingredient_id: String) -> void:
	if ingredient_id == "none":
		return
	if not current_bowl.has("additions"):
		return
	current_bowl.additions.append(ingredient_id)


## 現在の椀の最終 tags（DESIGN.md 9.5 STEP 11: Soup.tags + Bowl.additions の Ingredient.tags）。
## GameState.soup を直接参照する（DESIGN.md 4章「soup: GameState.soup を参照」）。
## 椀が無い / 鍋が無いときは、無い方を空として扱う（例外にしない）。
func bowl_final_tags() -> Array:
	var tags: Array = []
	if GameState.soup != null:
		tags.append_array(GameState.soup.get("tags", []))
	for ingredient_id in current_bowl.get("additions", []):
		tags.append_array(Ingredients.tags_for(str(ingredient_id)))
	return tags


## 現在の椀を wanted_tags で判定する（DESIGN.md 9.5 STEP 15）。
## GOOD: wanted_tags の全部が最終tagsに含まれる / 欠ければ MISS。二値のみ、重み付けはしない。
## 結果は current_bowl["result"] にも記録する（客が替われば新しい椀に消える一時表示用。
## REACT の text 自体は書き換えない。どちらを見せるかは受け側が都度選ぶ）。
func judge_bowl(wanted_tags: Array) -> String:
	var final_tags := bowl_final_tags()
	var result := "GOOD"
	for tag in wanted_tags:
		if not final_tags.has(tag):
			result = "MISS"
			break
	current_bowl["result"] = result
	return result
