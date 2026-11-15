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
		grade: String, ingredients: Array, request_honored = null) -> void:
	if not is_recordable(customer_id):
		return
	var visit := ensure_visit(customer_id, slot_name, episode_id)
	visit["served"] = int(visit["served"]) + servings
	(visit["grades"] as Array).append(grade)
	(visit["ingredients"] as Array).append(ingredients.duplicate())
	visit["grade"] = worst_grade(visit["grades"])
	# 今日の頼みに応えたか（システム整理C2。今日の頼みがある場面の提供だけが bool を渡す。無い場面は
	# キー自体を入れない）。複数の杯があれば、すべて応えたときだけ true。
	if request_honored is bool:
		visit["request_honored"] = bool(request_honored) and bool(visit.get("request_honored", true))


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


## 今日より前の最後の来店（無ければ空の辞書）。「前回の料理を読んだ2行」（4-4b-2。callback）が
## 読むのは、last_visit()ではなくこちら：来店した時点でarrive()が今日の来店（served=0）を
## 作るので、last_visit()だと今日の分を拾ってしまう。dayが今日より小さい来店だけを見るので、
## customer_eventsを呼ぶのがarrive()の前でも後でも、再挑戦で戻して来店をやり直しても、
## 前回の来店は同じになる。
static func previous_visit(customer_id) -> Dictionary:
	var visits := visits_of(customer_id)
	for i in range(visits.size() - 1, -1, -1):
		if int((visits[i] as Dictionary)["day"]) < GameState.day_count:
			return visits[i]
	return {}


## その客の最後の来店（無ければ空の辞書。今日の来店を含む）。
static func last_visit(customer_id) -> Dictionary:
	var visits := visits_of(customer_id)
	return visits[visits.size() - 1] if not visits.is_empty() else {}


## 今日の来店（無ければ空の辞書。作らない）。返すのは辞書そのもの（参照）。
static func today_visit(customer_id) -> Dictionary:
	var visit := last_visit(customer_id)
	if not visit.is_empty() and int(visit["day"]) == GameState.day_count:
		return visit
	return {}


## 今日の来店で選んだ選択（{ 選択id: 選択肢id }）。選んでいなければ空の辞書。
static func choices_today(customer_id) -> Dictionary:
	var choices = today_visit(customer_id).get("choices", {})
	return (choices as Dictionary).duplicate() if choices is Dictionary else {}


## 店主の距離感の選択を記録する（システム整理C2）。今日の来店の choices へ 選択id→選択肢id を残し、
## 選択肢の set（事実の辞書）を facts へ即時に書く。料金・評判・評価・関係の数値は持たない。
## 同じ選択を2度押しても上書き（最後の1つ）で、事実も同じ値になる。
static func record_choice(customer_id, slot_name: String, episode_id: String, choice_id: String,
		option_id: String, set_facts: Dictionary) -> void:
	if not is_recordable(customer_id):
		return
	var visit := ensure_visit(customer_id, slot_name, episode_id)
	if not (visit.get("choices") is Dictionary):
		visit["choices"] = {}
	(visit["choices"] as Dictionary)[choice_id] = option_id
	for key in set_facts:
		set_fact(customer_id, str(key), set_facts[key])


## 次回へ残す事実（facts）。今は使わない（4-4b-2以降）。足す手段だけ用意している。
## 客の今の表示名（UI準備Y）：その客が名乗っていれば（facts.revealed_name）その名前、無ければプロフィールの name
## （ScheduleData.customer_display_name）。客ノート・連絡先のカード・DMの相手の名前・結果画面・会話ログの話し手などはこれを使う。
const REVEALED_NAME_FACT := "revealed_name"


## 中身Z：名乗る前の名前。客のプロフィールに name_before_reveal（配信者＝「初めての客」）があれば、名乗るまではそれ
## （プロフィールの name は名乗る前には出さない）。無い客（新人警官など）は今までどおりプロフィールの name。
const NAME_BEFORE_REVEAL_KEY := "name_before_reveal"


static func display_name(customer_id) -> String:
	var revealed := str(fact(customer_id, REVEALED_NAME_FACT, ""))
	if revealed != "":
		return revealed
	var before := str(ScheduleData.customer_profile(str(customer_id)).get(NAME_BEFORE_REVEAL_KEY, ""))
	return before if before != "" else ScheduleData.customer_display_name(str(customer_id))


## --- 条件付きの行・DM（中身Z。ScheduleData.CONDITION_KEY） ---

## 条件（{ fact | not_fact: <キー>, customer?: <客id> }）を今の事実で満たすか。customer を省略したら default_customer の事実を見る。
## 事実が真＝ true・0 でない数・空でない文字列。無い事実は偽。形の違う条件は偽（検査は ScheduleData.condition_problems）。状態を読むだけ。
static func condition_met(cond, default_customer: String) -> bool:
	if not (cond is Dictionary):
		return false
	var customer := str((cond as Dictionary).get("customer", default_customer))
	if (cond as Dictionary).has("fact"):
		return _truthy(fact(customer, str(cond["fact"]), null))
	if (cond as Dictionary).has("not_fact"):
		return not _truthy(fact(customer, str(cond["not_fact"]), null))
	return false


static func _truthy(value) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return value != ""
	return true


## 行の配列の条件付きのまとまりを、今の事実で開く（満たすまとまりの lines をその位置に入れ、満たさないものは捨てる。入れ子も開く）。
## ほかの要素（行・名乗りの印）はそのまま。状態を読むだけ。
static func resolve_lines(lines, customer_id: String) -> Array:
	var out := []
	if not (lines is Array):
		return out
	for line in lines:
		if ScheduleData.is_condition_group(line):
			if condition_met(line[ScheduleData.CONDITION_KEY], customer_id):
				out.append_array(resolve_lines(line["lines"], customer_id))
		else:
			out.append(line)
	return out


## その客が名乗った（場面の行の reveal_name）：今の表示名を変える。来店記録の facts に残す（朝のセーブに入る）。
static func reveal_name(customer_id, name: String) -> void:
	if str(customer_id) != "" and name != "":
		set_fact(customer_id, REVEALED_NAME_FACT, name)


static func set_fact(customer_id, key: String, value) -> void:
	(GameState.memory_entry(customer_id)["facts"] as Dictionary)[key] = value


static func fact(customer_id, key: String, default_value = null) -> Variant:
	if not GameState.customer_memory.has(str(customer_id)):
		return default_value
	return (GameState.memory_entry(customer_id)["facts"] as Dictionary).get(key, default_value)
