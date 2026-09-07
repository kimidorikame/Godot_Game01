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

## 椀に足せる具材の上限（DESIGN.md 9.5 STEP 17.6：3枠、4枠案から縮小）。
const MAX_ADDITIONS := 3


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
## 重複可（同じ id を複数回足せる。将来「強さ」を持たせる余地を残すため・STEP 17.6）。
## 上限（MAX_ADDITIONS）に達している、または椀が無い（current_bowl == {}）ときは何もしない
## （UI側でも上限に達したら選択肢を無効化するが、ここでも二重に防ぐ）。
func add_to_bowl(ingredient_id: String) -> void:
	if not current_bowl.has("additions"):
		return
	if current_bowl.additions.size() >= MAX_ADDITIONS:
		return
	current_bowl.additions.append(ingredient_id)


## 3枠に入れた具材だけの tags（DESIGN.md 9.5 STEP 17.6：判定に使うのはこちら）。
## 鍋（soup）は含めない。鍋はその日の全客に共通で、特定の客への判断ではないため
## 「今日の鍋がたまたま合った」という偶然を評価に混ぜない。
func bowl_addition_tags() -> Array:
	var tags: Array = []
	for ingredient_id in current_bowl.get("additions", []):
		tags.append_array(Ingredients.tags_for(str(ingredient_id)))
	return tags


## 現在の椀の最終 tags（DESIGN.md 9.5 STEP 11: Soup.tags + Bowl.additions の Ingredient.tags）。
## GameState.soup を直接参照する（DESIGN.md 4章「soup: GameState.soup を参照」）。
## 椀が無い / 鍋が無いときは、無い方を空として扱う（例外にしない）。
## STEP 17.6: 判定には使わない（表示用。判定は bowl_addition_tags() 側）。
func bowl_final_tags() -> Array:
	var tags: Array = []
	if GameState.soup != null:
		tags.append_array(GameState.soup.get("tags", []))
	tags.append_array(bowl_addition_tags())
	return tags


## 現在の椀を wanted_tags と favorite で判定する（DESIGN.md 9.5 STEP 17.6）。
## 一致数による段階評価に、favorite（好物）によるクリティカルを重ねる:
##   一致0個     → BAD（イマイチ）※favorite があっても上がらない
##   一致1個     → OK（普通）        / favorite あり → GOOD
##   一致2個以上 → GOOD（美味しい）  / favorite あり → GREAT（とても好み）
## 一致0で上がらないのは、合わない一杯に好物を入れられても嬉しくないため。
## favorite は「基本を押さえた上のボーナス」であって救済ではない（DESIGN.md）。
##
## 判定に使うのは bowl_addition_tags()（3枠の中身だけ）。鍋のtagsは数えない。
## 数えるのは「wanted_tags の各要素が椀のtagsに含まれるか」＝要求側をループする形。
## こうすると同じ具材を複数入れても（例：モツ2つ）その tag は1個としてしか数えられない。
## favorite だけは tag ではなく具材id そのもので見る（その現物を入れたかどうか）。
## 具材を何も入れずに提供した場合は一致0 → BAD になる（専用の分岐は不要）。
## 結果は current_bowl に記録する（客が替われば新しい椀に消える一時表示用。
## REACT の反応text自体は書き換えない。どれを見せるかは受け側が都度選ぶ）。
##   result          … BAD / OK / GOOD / GREAT
##   match_count     … 一致数（計器盤の表示用）
##   favorite        … その客の好物id（計器盤の表示用）
##   has_favorite    … 好物が実際に椀へ入っていたか（計器盤の表示用）
##   reaction_variant… 各段階2パターンある反応textのどちらを見せるか。
##                     ここで一度だけ抽選する（表示のたびに再抽選すると結果がちらつくため）
func judge_bowl(wanted_tags: Array, favorite: String = "") -> String:
	var tags := bowl_addition_tags()
	var match_count := 0
	for tag in wanted_tags:
		if tags.has(tag):
			match_count += 1
	var has_favorite: bool = favorite != "" and current_bowl.get("additions", []).has(favorite)
	var result := "BAD"
	if match_count >= 2:
		result = "GREAT" if has_favorite else "GOOD"
	elif match_count == 1:
		result = "GOOD" if has_favorite else "OK"
	current_bowl["result"] = result
	current_bowl["match_count"] = match_count
	current_bowl["favorite"] = favorite
	current_bowl["has_favorite"] = has_favorite
	current_bowl["reaction_variant"] = randi() % 2
	return result
