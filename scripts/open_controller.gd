extends RefCounted
class_name OpenController
## OPEN の間だけ生存する客キューの管理役（DESIGN.md 4章「客ループは下位に隔離」）。
##
## Event の中身は持たない。「今どの客か / 次へ / さばき切ったか」だけを答える薄い部品。
## 接客そのものの再生は、客ごとの EventRunner（DebugPanel が flow.runner に載せる）に任せる。
## OPEN が終われば捨てる（RefCounted なので参照が切れれば解放される）。

# 時間帯ごとに区切った客の並び（DESIGN.md 7.6）。形は
#   [ { "name": "宵の口", "customers": ["delivery_man", ...] }, ... ]
# 位置は「何番目の時間帯か（slot_index）」と「その中の何人目か（index）」の2つで持つ。
var schedule: Array = []   # 時間帯の並び
var slot_index: int = 0    # いま何番目の時間帯か（0起点）
var index: int = 0         # その時間帯の中で何人目か（0起点）

# 現在の客に出す椀。形は { customer_id, additions[] }（DESIGN.md 9.5 STEP 11）。
# tags は持たない＝二重の正本を作らず、必要時に bowl_final_tags() で計算する。
# 客が替わるたび（_init / advance_customer）ここで新規に作り直す。
# 客がいない（キューが空 / さばき切った）ときは {}。
var current_bowl: Dictionary = {}

## 椀に足せる具材の上限（DESIGN.md 9.5 STEP 17.6：3枠、4枠案から縮小）。
const MAX_ADDITIONS := 3

## 評価の並び（低い順）。濃さペナルティは「この並びで1つ下げる」形で実装する（7.6）。
const RESULT_ORDER := ["BAD", "OK", "GOOD", "GREAT"]


func _init(customer_schedule: Array = []) -> void:
	schedule = customer_schedule
	slot_index = 0
	index = 0
	_skip_finished_slots()   # 先頭が空の時間帯でも詰まらないように
	current_bowl = _new_bowl(current_customer())


## いま接客中の客 id。時間帯もキューも尽きていたら null。
func current_customer() -> Variant:
	var customers := current_slot_customers()
	if index < 0 or index >= customers.size():
		return null
	return customers[index]


## いまの時間帯の客リスト。時間帯を使い切っていれば空配列。
func current_slot_customers() -> Array:
	if slot_index < 0 or slot_index >= schedule.size():
		return []
	var slot = schedule[slot_index]
	if not (slot is Dictionary):
		return []
	return slot.get("customers", [])


## いまの時間帯の名前（「宵の口」など）。使い切っていれば空文字。
func current_slot_name() -> String:
	if slot_index < 0 or slot_index >= schedule.size():
		return ""
	var slot = schedule[slot_index]
	if not (slot is Dictionary):
		return ""
	return str(slot.get("name", ""))


## OPEN 全体でまだ接客すべき客が残っているか（時間帯をまたいで見る）。
func has_more() -> bool:
	return current_customer() != null


## 次の客へ。呼び出し側は「今の客の runner が DONE」を確認してから呼ぶこと。
## その時間帯を終えていたら、次の時間帯の先頭へ送る（受け側は時間帯を意識しなくてよい）。
## 椀もここで新規に作り直す（前の客の additions を持ち越さない）。
##
## 戻り値: **新しい時間帯に入ったか**（7.6）。時間帯が進むと鍋が煮詰まるので、
## その合図として受け側へ返す。OpenController 自身は GameState を書き換えない
## （ここは客の並びを管理する部品で、鍋を動かすのは受け側の仕事）。
## 最後の客を終えて OPEN 自体が終わるときは false ＝ 夜が明けた後に濃くならない。
func advance_customer() -> bool:
	var before_slot := slot_index
	index += 1
	_skip_finished_slots()
	current_bowl = _new_bowl(current_customer())
	return slot_index != before_slot and slot_index < schedule.size()


## 全時間帯をさばき切ったか（OPEN を終えて CLOSE へ進んでよい合図）。
func is_open_done() -> bool:
	return current_customer() == null


## いまの時間帯を使い切っていたら次の時間帯の先頭へ進める。
## 客のいない時間帯は読み飛ばす（将来モブ0人の時間帯があり得るため）。
## 全部使い切ったら slot_index が schedule の外に出て、current_customer() が null になる。
func _skip_finished_slots() -> void:
	while slot_index < schedule.size() and index >= current_slot_customers().size():
		slot_index += 1
		index = 0


## 客 id から空の椀を作る。客がいなければ {}（current_bowl の「なし」状態）。
func _new_bowl(customer_id: Variant) -> Dictionary:
	if customer_id == null:
		return {}
	return { "customer_id": customer_id, "additions": [] }


## 現在の椀に具材 id を1つ足す。ADJUST の選択肢を受けた側（DebugPanel）から呼ぶ。
## 重複可（同じ id を複数回足せる。将来「強さ」を持たせる余地を残すため・STEP 17.6）。
## 上限（MAX_ADDITIONS）に達している、または椀が無い（current_bowl == {}）ときは何もしない
## （UI側でも上限に達したら選択肢を無効化するが、ここでも二重に防ぐ）。
## spoiled: 選んだ時点でその具材が傷んでいたか（腐敗・3日目）。判定時まで待たないのは、
## 選んで在庫が0になるとキーが消え、状態を引けなくなるため。1つでも傷んだ具材を入れたら
## used_spoiled を立てる（作り直し reset_bowl で新しい椀になれば自然に消える）。
## 戻り値：実際に additions へ足せたら true、何もしなかったら false（呼び出し側はこれを
## 見て、足せたときだけ在庫を減らす。フェーズ1 ステップ3「追加が成功したときだけ在庫を
## 減らす」の直し方）。
func add_to_bowl(ingredient_id: String, spoiled: bool = false) -> bool:
	if not current_bowl.has("additions"):
		return false
	if current_bowl.additions.size() >= MAX_ADDITIONS:
		return false
	current_bowl.additions.append(ingredient_id)
	if spoiled:
		current_bowl["used_spoiled"] = true
	return true


## 椀を作り直す（[廃棄する]の後、同じ客へ再挑戦するため）。additionsを空にした
## 新しい椀に差し替えるだけ＝_new_bowl()をそのまま使う。judge_bowlの結果（result等）も
## 新しい椀には無いので、自動的に「判定前」の状態へ戻る。鍋の消費・記録は受け側
## （DebugPanel._on_discard_pressed）が椀を作り直す前に済ませる。
func reset_bowl() -> void:
	current_bowl = _new_bowl(current_customer())


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


## 現在の椀を wanted_tags と favorite で判定する（DESIGN.md 9.5 STEP 17.6 / 7.6 →
## F3 Judge v2で10.3.2へ更新）。判定の中身自体はJudge.grade()へ委譲し、ここは
## current_bowlへの記録だけを行う薄い関数（3-1のPlanで合意した既存フィールド維持方針）。
##
## 「具なしの椀は常にBAD」という強制ルールは廃止した（DESIGN.md 10.3.1：この役目は
## SaleRule「具なしの椀は売れない」に置き換わった。judge_bowl()自体はSaleRuleを経由
## しないので、具なしの椀を直接渡せば具なしのままJudge.grade()へ通る＝呼び出し側が
## 事前にSaleRule.check()でブロックする責務を持つ）。no_toppingフィールドは表示専用
## として引き続きここで計算する。
##
## 結果は current_bowl に記録する（客が替われば新しい椀に消える一時表示用。
## REACT の反応text自体は書き換えない。どれを見せるかは受け側が都度選ぶ）。
##   result           … 最終評価。BAD / OK / GOOD / GREAT
##   base_result      … 減点前の評価（計器盤の表示用）
##   strength_at_judge… 判定した瞬間の濃さ（計器盤の表示用。判定後に鍋をいじっても
##                      ここは動かない。reaction_variant と同じく一度だけ固定する）
##   match_count      … 一致数（計器盤の表示用）
##   favorite         … その客の好物id（計器盤の表示用）
##   has_favorite     … 好物が実際に椀へ入っていたか（計器盤の表示用）
##   no_topping       … 具（Ingredients.is_topping）を1つも入れていないか（表示専用。
##                      判定そのものには使わない）
##   reaction_variant … 各段階2パターンある反応textのどちらを見せるか。
##                      ここで一度だけ抽選する（表示のたびに再抽選すると結果がちらつくため）
func judge_bowl(wanted_tags: Array, favorite: String = "") -> String:
	var no_topping := true
	for ingredient_id in current_bowl.get("additions", []):
		if Ingredients.is_topping(str(ingredient_id)):
			no_topping = false
			break
	var graded := Judge.grade(current_bowl, GameState.soup, { "wanted_tags": wanted_tags, "favorite": favorite })
	var strength := 3
	if GameState.soup != null:
		strength = int(GameState.soup.get("strength", 3))

	current_bowl["penalty_strength"] = graded["penalties"].has("strength")
	current_bowl["penalty_spoiled"] = graded["penalties"].has("spoiled")
	current_bowl["result"] = graded["grade"]
	current_bowl["base_result"] = graded["base_grade"]
	current_bowl["strength_at_judge"] = strength
	current_bowl["match_count"] = graded["match_count"]
	current_bowl["favorite"] = favorite
	current_bowl["has_favorite"] = graded["favorite_hit"]
	current_bowl["no_topping"] = no_topping
	current_bowl["reaction_variant"] = randi() % 2
	return graded["grade"]
