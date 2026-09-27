extends RefCounted
class_name DayPlanner
## その日の計画（F2・DESIGN.md 10.8.2）。WAKEで1回だけ作り、OPENでは使い回す。
##
## 抽選アルゴリズム自体はDay1Events.customer_schedule()に残したまま（tests/schedule_test.gd・
## tests/reputation_demand_test.gdがこの関数を直接呼んで抽選ロジックそのものを検証しており、
## 移設すると無関係なテストまで書き換える必要が出るため）。ここはGameState.today_planへ
## 器として積むだけの薄い入口。customer_schedule()自身がGameState.today_plan["mob_instances"]
## を書き換える（3-2段階①）ので、build()はslots・dayを足すだけでよい。
##
## 専用乱数（DESIGN.md 10.8.2「seedから作るRandomNumberGenerator」）は導入しない。
## 同じ抽選を再現する必要があるのはF7（同じ朝への再挑戦・フェーズ4）からで、それまでは
## 検証する手段が無いまま複雑さだけ増える。today_planに"seed"フィールドを持たせるのも
## F7着手時にする（3-2の時点では宣言すらしない）。


## その日の計画を確定させる。debug_mob_count（-1=自動）はDay1Events.customer_schedule()へ
## そのまま渡す（DebugPanelのモブ人数上書きデバッグ機能を「計画を作り直す」操作として残す）。
static func build(debug_mob_count: int = -1) -> void:
	var slots := Day1Events.customer_schedule(debug_mob_count)
	GameState.today_plan["day"] = GameState.day_count
	GameState.today_plan["slots"] = slots
