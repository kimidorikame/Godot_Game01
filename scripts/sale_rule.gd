extends RefCounted
class_name SaleRule
## 販売成立条件（F3・DESIGN.md 10.3.1・10.8.3）。椀・鍋から計算するだけの静的クラスで、
## 状態は持たない（DESIGN.md 10.8表「状態の置き場所：—」）。
##
## 判定（Judge）と成立条件（SaleRule）を分ける（DESIGN.md 10.2原則4）。判定は
## 「出来の良し悪し」を決めるだけで、成立条件は「そもそも提供できるか」を決める。
## judge_bowl()/Judge.grade()自体はSaleRuleを経由しない（ingredient_pricing_test.gdが
## judge_bowl()を直接呼ぶ既存テストの回帰を避けるため）。呼び出し側（DebugPanelの
## [入力完了]・モブの達成可能人数計算）が、判定より前にこのcheck()を呼んでブロックする。

const NO_FLAVOR := "NO_FLAVOR"
const NO_TOPPING := "NO_TOPPING"
const STRENGTH_ZERO := "STRENGTH_ZERO"
const SHORT_SERVINGS := "SHORT_SERVINGS"


## bowl: OpenController.current_bowl（additionsを見る）。soup: GameState.soup（null可）。
## order: {"servings": int}。servingsキーが無ければSHORT_SERVINGSは判定しない
## （呼び出し側が既に別の仕組みで見ている場合に二重判定を避けるため。省略可能にしてある）。
static func check(bowl: Dictionary, soup: Variant, order: Dictionary = {}) -> Dictionary:
	var reasons := []
	var additions: Array = bowl.get("additions", [])
	var has_flavor := false
	var has_topping := false
	for id in additions:
		if not has_flavor and Ingredients.is_flavor(str(id)):
			has_flavor = true
		if not has_topping and Ingredients.is_topping(str(id)):
			has_topping = true
	if not has_flavor:
		reasons.append(NO_FLAVOR)
	if not has_topping:
		reasons.append(NO_TOPPING)
	var strength := int(soup.get("strength", 3)) if soup != null else 3
	if strength <= 0:
		reasons.append(STRENGTH_ZERO)
	if order.has("servings"):
		var remaining := int(soup.get("remaining_servings", 0)) if soup != null else 0
		if remaining < int(order["servings"]):
			reasons.append(SHORT_SERVINGS)
	return { "ok": reasons.is_empty(), "reasons": reasons }
