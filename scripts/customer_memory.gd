extends RefCounted
class_name CustomerMemory
## 来店記録（F5・DESIGN.md 10.8.5。4-4b-1）の書き手。状態はGameState.customer_memoryにあり、
## ここは記録・参照の処理だけを持つ静的クラス（状態は持たない）。**記録するだけ**で、台詞や
## 選び方は変えない。乱数は使わない。名前あり客だけが対象（モブは記録しない）。
##
## 記録の流れ（DebugPanelが呼ぶ）：
##   - 客が来店したとき arrive()：その日の来店を served=0 で1件作る（提供・断り・早仕舞いの
##     どれでも「来た」事実が残る）。同じ日に何度呼んでも増えない（常連は1日1回）。
##   - 提供のたび record_serve()：その来店へ杯ごとに追記する（served・grades・ingredients、
##     grade＝評価した杯の最悪値）。持ち帰りのように評価しない杯（grade=""）も served には
##     数えるが、grade（最悪値）には含めない（結果画面の集計が judged で分けるのと同じ）。
##   - 断り・提供できず退店：何も足さない（arrive()の served=0 がそのまま残る）。


## 来店記録の対象か：名前あり客（モブのインスタンスではなく、客プロフィールがある）。
static func is_recordable(customer_id) -> bool:
	var id := str(customer_id)
	if id == "" or Day1Events.is_mob_customer(id):
		return false
	return not ScheduleData.customer_profile(id).is_empty()


## 客が来店した（その日の来店を served=0 で作り、見た場面を覚える）。
static func arrive(customer_id, slot_name: String, episode_id: String) -> void:
	if is_recordable(customer_id):
		ensure_visit(customer_id, slot_name, episode_id)


## 今日の来店（無ければ作る）。返すのは辞書そのもの（参照）。
static func ensure_visit(customer_id, slot_name: String, episode_id: String) -> Dictionary:
	var entry := GameState.memory_entry(customer_id)
	var visits: Array = entry["visits"]
	var seen: Array = entry["seen_episodes"]
	if episode_id != "" and not seen.has(episode_id):
		seen.append(episode_id)
	if not visits.is_empty() and int((visits[visits.size() - 1] as Dictionary)["day"]) == GameState.day_count:
		return visits[visits.size() - 1]
	var visit := { "day": GameState.day_count, "slot": slot_name, "served": 0, "grade": "",
		"grades": [], "ingredients": [], "episode_id": episode_id }
	visits.append(visit)
	return visit


## 1杯を提供した記録。grade="" は評価しない杯（判定なし）。ingredientsはその杯に入れた
## 具材・調味料のid。
static func record_serve(customer_id, slot_name: String, episode_id: String, servings: int,
		grade: String, ingredients: Array) -> void:
	if not is_recordable(customer_id):
		return
	var visit := ensure_visit(customer_id, slot_name, episode_id)
	visit["served"] = int(visit["served"]) + servings
	(visit["grades"] as Array).append(grade)
	(visit["ingredients"] as Array).append(ingredients.duplicate())
	visit["grade"] = worst_grade(visit["grades"])


## 評価の並び（低い順。OpenController.RESULT_ORDER）で最も悪い評価。空文字（評価なし）は
## 数えない。評価した杯が1つも無ければ空文字。
static func worst_grade(grades: Array) -> String:
	var worst := ""
	var worst_rank := 999
	for g in grades:
		var rank: int = OpenController.RESULT_ORDER.find(str(g))
		if rank >= 0 and rank < worst_rank:
			worst_rank = rank
			worst = str(g)
	return worst


## その客がこの場面を見たか（seen_episodes）。記録が無い客は false（エントリは作らない）。
## 場面の選び方（EpisodeSelector）の not_seen が使う。
static func has_seen(customer_id, episode_id: String) -> bool:
	if not GameState.customer_memory.has(str(customer_id)):
		return false
	return (GameState.customer_memory[str(customer_id)]["seen_episodes"] as Array).has(episode_id)


static func visits_of(customer_id) -> Array:
	if not GameState.customer_memory.has(str(customer_id)):
		return []
	return GameState.customer_memory[str(customer_id)]["visits"]


## その客の最後の来店（無ければ空の辞書）。4-4b-2の「前回の料理を読んだ2行」が読む。
static func last_visit(customer_id) -> Dictionary:
	var visits := visits_of(customer_id)
	return visits[visits.size() - 1] if not visits.is_empty() else {}


## 次回へ残す事実（facts）。今は使わない（4-4b-2以降）。足す手段だけ用意している。
static func set_fact(customer_id, key: String, value) -> void:
	(GameState.memory_entry(customer_id)["facts"] as Dictionary)[key] = value


static func fact(customer_id, key: String, default_value = null) -> Variant:
	if not GameState.customer_memory.has(str(customer_id)):
		return default_value
	return (GameState.memory_entry(customer_id)["facts"] as Dictionary).get(key, default_value)
