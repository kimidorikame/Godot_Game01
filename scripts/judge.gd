extends RefCounted
class_name Judge
## 品質判定（F3・DESIGN.md 10.3.2・10.8.3）。椀・鍋から計算するだけの静的クラスで、
## 状態は持たない（DESIGN.md 10.8表「状態の置き場所：—」）。
##
## 「具なしの椀は常にBAD」（フェーズ1の強制ルール）はここでは行わない。DESIGN.md 10.3.1に
## 明記のとおり、その役目はSaleRuleの「具なしの椀は売れない（提供不可）」に置き換わった
## （grade()が呼ばれる時点でSaleRule.check()を先に通っている前提。呼び出し側の責務）。


## bowl: OpenController.current_bowl（additionsを見る。tagsの正本はGameStateではなく
## bowl自身なのでOpenControllerを介さず直接計算する）。
static func _addition_tags(bowl: Dictionary) -> Array:
	var tags: Array = []
	for id in bowl.get("additions", []):
		tags.append_array(Ingredients.tags_for(str(id)))
	return tags


## bowl: OpenController.current_bowl。soup: GameState.soup（null可）。
## order: {"wanted_tags": Array, "favorite": String}。
## 戻り値：{grade, base_grade, penalties(Array["strength","spoiled"]), favorite_hit, match_count}
static func grade(bowl: Dictionary, soup: Variant, order: Dictionary) -> Dictionary:
	var tags := _addition_tags(bowl)
	var match_count := 0
	for tag in order.get("wanted_tags", []):
		if tags.has(tag):
			match_count += 1
	var favorite: String = str(order.get("favorite", ""))
	var favorite_hit: bool = favorite != "" and bowl.get("additions", []).has(favorite)

	# 判定ルールv2（DESIGN.md 10.3.2）：好物は一致2個（GOOD相当）のときだけGREATへ
	# 押し上げる。一致1個＋好物はOKのまま（現行の「GOOD」から変更。ここが3-3の
	# 中心的な変更点）。
	var base_grade := "BAD"
	if match_count >= 2:
		base_grade = "GREAT" if favorite_hit else "GOOD"
	elif match_count == 1:
		base_grade = "OK"

	var strength := int(soup.get("strength", 3)) if soup != null else 3
	var penalties := []
	if strength == GameState.STRENGTH_MIN or strength == GameState.STRENGTH_MAX:
		penalties.append("strength")
	if bool(bowl.get("used_spoiled", false)):
		penalties.append("spoiled")
	# 減点の重ね掛け（DESIGN.md 10.3.2・F1 Rules.penalty_stacking）：7日版はfalseなので
	# 該当する条件がいくつあっても1段階しか下げない（既存どおり）。trueなら条件の数だけ
	# 下げる（21日版の上級設定向け。7日版では発火しない）。
	var steps: int = penalties.size() if Rules.penalty_stacking() else mini(penalties.size(), 1)
	const RESULT_ORDER := ["BAD", "OK", "GOOD", "GREAT"]
	var idx: int = maxi(RESULT_ORDER.find(base_grade) - steps, 0)
	var final_grade: String = RESULT_ORDER[idx]

	return { "grade": final_grade, "base_grade": base_grade, "penalties": penalties,
		"favorite_hit": favorite_hit, "match_count": match_count }
