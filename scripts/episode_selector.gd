extends RefCounted
class_name EpisodeSelector
## 場面の選び方（F6・DESIGN.md 10.8.6。4-4b-2）。DayPlanを作るとき（WAKE。customer_schedule()）に、
## 枠の常連について、前提（requires）を満たす場面を1つ選ぶ。静的・単純な絞り込みだけ
## （andの組み合わせのみ。orや式・スクリプトは持たない＝汎用の会話エンジンは作らない）。
## 乱数は使わない（決定的。同じ記録なら何度呼んでも同じ）。
##
## 選び方：
##   1. 日程（week7_regulars.json）の静的なepisode_idを第一候補にする。requiresを満たせばそれ。
##   2. 満たさなければ、その客の他の場面（id順）から、最初にrequiresを満たすもの。
##   3. どれも満たさなければ第一候補へ戻す（10.8.6の「短い近況の場面」データは今回は作らない。
##      最小の挙動として既定の場面に戻す）。
## 第一候補が満たすなら他の場面は見ない。既存データ（requiresを持たない）では、必ず日程の
## 静的idを返す＝4-4aと同じ場面（動作を変えない）。
##
## requiresのキー（今回読むのはこの2つだけ）：
##   not_seen: true      … この場面をまだ見ていない（customer_memory[id].seen_episodes に無い）
##   facts: { 事実: 値 } … facts（CustomerMemory.fact）が全て一致する。無い事実は false として扱う
##                         （10.8.6の takeout_recipient_known: false が初期状態で成り立つように）。
## min_visits・last_grade は採らない（前回の評価はcallbackが担い、他の条件はfactsで表せる）。


## 客の場面を選ぶ。default_episode_idは日程の静的なepisode_id。
static func select(customer_id: String, default_episode_id: String) -> String:
	if customer_id == "" or default_episode_id == "":
		return default_episode_id
	if satisfies(customer_id, default_episode_id):
		return default_episode_id
	for id in ScheduleData.episode_candidates(customer_id):
		if id != default_episode_id and satisfies(customer_id, id):
			return id
	return default_episode_id


## その客がこの場面のrequiresを満たすか（requiresが無ければ満たす）。
static func satisfies(customer_id: String, episode_id: String) -> bool:
	var requires := ScheduleData.episode_requires(customer_id, episode_id)
	if requires.is_empty():
		return true
	if bool(requires.get("not_seen", false)) and CustomerMemory.has_seen(customer_id, episode_id):
		return false
	var facts = requires.get("facts", {})
	if facts is Dictionary:
		for key in facts:
			if CustomerMemory.fact(customer_id, str(key), false) != facts[key]:
				return false
	return true
