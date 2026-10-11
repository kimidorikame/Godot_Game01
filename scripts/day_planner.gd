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
## 専用乱数（DESIGN.md 10.8.2「seedから作るRandomNumberGenerator」）は、F7（4-1）でも
## 導入しなかった。同じ朝への再挑戦は、乱数を再現するのではなく、WAKEで確定した
## today_plan（slots・mob_instances・demand_center）を朝の辞書（MorningSave）に入れて
## そのまま戻す方式（DESIGN.md 10.8.7「DayPlanも同じなので抽選は変わらない」）。戻した朝は
## build()を呼ばない（debug_panel.gdの_plan_restored）ので、抽選を引き直す手段にならない。
## 乱数の仕組みを足さないのでcustomer_schedule()・total_demand_today()は無改修。
## 反応文の2択（OpenController.reaction_variant）は演出の乱数で、再挑戦では変わりうる。


## その日の計画を確定させる。debug_mob_count（-1=自動）はDay1Events.customer_schedule()へ
## そのまま渡す（DebugPanelのモブ人数上書きデバッグ機能を「計画を作り直す」操作として残す）。
static func build(debug_mob_count: int = -1) -> void:
	var slots := Day1Events.customer_schedule(debug_mob_count)
	GameState.today_plan["day"] = GameState.day_count
	GameState.today_plan["slots"] = slots
	# 3-7：予報の幅（DESIGN.md 10.4）の基準になる総需要の中心を、計画と一緒に確定
	# させる（乱数を引かない。実際の総需要の抽選はcustomer_schedule()内で済んでいる）。
	GameState.today_plan["demand_center"] = GameState.demand_center_today()
