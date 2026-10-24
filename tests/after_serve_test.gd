extends RefCounted
## 提供後の列（システム整理C1-②。DESIGN.md 10.5.3・10.8.6）の検証。
## REACT の処理が済んだ後に Day1Events.after_serve_events() が組んだ列（本文 → 締め）を、
## DebugPanel が現在位置の直後へ差し込む。反応は REACT の表示（reactions[出来]／UNSERVED）。
## 確認すること：出来4段階それぞれの順序・場面データにキーが無ければ従来と同一・断った客の
## UNSERVED と未提供版の本文（must_info）・差し込んだ列を読む間に鍋/腐敗/客の待ちが進まない・
## customer_events と after_serve_events を何度呼んでも状態が変わらない。
## 場面データはキャッシュへ注入する（Day2のチンピラ＝thug_02。基本注文 MELLOW/GENTLE・好物 meat_ball）。

const GRADE_PICKS := {
	"GREAT": ["coconut_milk", "tofu", "meat_ball"],
	"GOOD": ["coconut_milk", "tofu"],
	"OK": ["coconut_milk", "offal"],
	"BAD": ["nam_prik_pao", "offal"],
}
const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]


func _scene(extra: Dictionary) -> Dictionary:
	var ep := { "id": "thug_02", "customer": "thug", "greet": ["注文"], "servings": 1,
		"reactions": {
			"GREAT": ["R:GREAT"], "GOOD": ["R:GOOD"], "OK": ["R:OK"], "BAD": ["R:BAD"], "UNSERVED": ["R:UNSERVED"] } }
	ep.merge(extra, true)
	return ep


## Day2のWAKEを通し、客（チンピラ→老婆）の接客のADJUST待ちまで進める。
func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": ["thug", "granny"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()
	return panel


## 椀を作って提供し、REACTを適用させる（REACTがcurrentになった状態で返す）。
func _serve(panel, picks: Array) -> void:
	for id in picks:
		panel._on_ingredient_selected(id)
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()


## runnerの現在位置より後ろのイベントのうち、提供後の列（partを持つもの）の [part, text]。
func _after_lines(panel) -> Array:
	var out := []
	var events: Array = panel.session.flow.runner.events
	for i in range(panel.session.flow.runner.index + 1, events.size()):
		if events[i].has("part"):
			out.append([str(events[i]["part"]), str(events[i]["text"])])
	return out


## 状態の写し（読んでいる間に変わってはいけないもの）。客の位置も含める。
func _snapshot(panel) -> Dictionary:
	return {
		"money": GameState.money, "rep": GameState.reputation, "day": GameState.day_count,
		"soup": GameState.soup.duplicate(true), "inventory": GameState.inventory.duplicate(true),
		"batches": GameState.perishable_batches.duplicate(true), "dashi": GameState.dashi_units,
		"served": GameState.served.duplicate(true), "ledger": GameState.ledger.size(),
		"slot_index": panel.session.open.slot_index, "customer_index": panel.session.open.index,
		"memory": GameState.customer_memory.duplicate(true), "plan": GameState.today_plan.duplicate(true),
	}


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()

	# --- 1. 出来4段階：反応（REACTの表示）→ 本文 → 締め の順 ---
	for grade in GRADE_PICKS:
		ScheduleData.clear_cache()
		ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1", "B2"], "closing": { "default": ["C1"] } })
		var panel = _setup(t)
		var before_events: int = panel.session.flow.runner.events.size()
		_serve(panel, GRADE_PICKS[grade])
		c.check("%s：判定は期待どおり" % grade, str(panel.session.open.current_bowl.get("result", "")) == grade,
			str(panel.session.open.current_bowl.get("result", "")))
		c.check("%s：反応はREACTの表示（reactions[出来]）" % grade, panel._current_reaction_text() == "R:" + grade,
			panel._current_reaction_text())
		c.check("%s：REACTの後に 本文×2 → 締め×1 が差し込まれる（イベントは3つ増える）" % grade,
			_after_lines(panel) == [["body", "B1"], ["body", "B2"], ["closing", "C1"]]
				and panel.session.flow.runner.events.size() == before_events + 3, str(_after_lines(panel)))
		var next_event = panel.session.flow.runner.events[panel.session.flow.runner.index + 1]
		c.check("%s：差し込んだ行は効果の無いGREET（客・本文）" % grade,
			str(next_event["type"]) == "GREET" and str(next_event["customer"]) == "thug")
		panel.free()

	# --- 2. 場面データにキーが無い（現行の21場面）なら、従来と同一（何も差さない） ---
	ScheduleData.clear_cache()
	var plain = _setup(t)
	var plain_before: int = plain.session.flow.runner.events.size()
	_serve(plain, GRADE_PICKS["GOOD"])
	c.check("実データ：REACTの前後でイベント数が変わらない（何も差さない）",
		plain.session.flow.runner.events.size() == plain_before and _after_lines(plain).is_empty())
	c.check("実データ：反応は従来どおり（reactions[出来]）", plain._current_reaction_text() != "")
	plain.free()

	# --- 3. 断った客：反応は UNSERVED。must_info の無い場面は本文を出さない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1"], "closing": { "default": ["C1"] } })
	var declined = _setup(t)
	var money_before_decline: int = GameState.money
	var stock_before_decline: Dictionary = GameState.inventory.duplicate(true)
	declined._on_customer_decline_pressed()
	declined._on_next_event_pressed()
	c.check("断る：REACTの反応は reactions.UNSERVED", declined._current_reaction_text() == "R:UNSERVED",
		declined._current_reaction_text())
	c.check("断る：must_info が無ければ、本文も締めも出さない", _after_lines(declined).is_empty())
	c.check("断る：売上・在庫は動かず、来店記録は served=0",
		GameState.money == money_before_decline and GameState.inventory == stock_before_decline
			and int(CustomerMemory.last_visit("thug")["served"]) == 0)
	declined.free()

	# --- 4. 断った客でも must_info の場面は、未提供版の本文（body_unserved）を再生する。締めは出さない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1"], "body_unserved": ["U1", "U2"],
		"closing": { "default": ["C1"] }, "must_info": ["info_a"] })
	var must = _setup(t)
	must._on_customer_decline_pressed()
	must._on_next_event_pressed()
	c.check("must_info：断っても未提供版の本文が差し込まれる（通常の本文・締めは出ない）",
		_after_lines(must) == [["body", "U1"], ["body", "U2"]], str(_after_lines(must)))
	c.check("must_info：反応はUNSERVED", must._current_reaction_text() == "R:UNSERVED")
	must.free()
	# 提供したときは、must_infoがあっても通常の本文・締め
	var must_served = _setup(t)
	_serve(must_served, GRADE_PICKS["GOOD"])
	c.check("must_infoの場面でも、提供したときは通常の本文 → 締め",
		_after_lines(must_served) == [["body", "B1"], ["closing", "C1"]], str(_after_lines(must_served)))
	must_served.free()

	# --- 5. 差し込んだ列を読む間に、鍋・腐敗・客の待ちが進まない。料金・評判・評価は変わらない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1", "B2", "B3"], "closing": { "default": ["C1", "C2"] } })
	var reading = _setup(t)
	_serve(reading, GRADE_PICKS["GOOD"])
	var snap_start := _snapshot(reading)
	var graded: String = str(reading.session.open.current_bowl.get("result", ""))
	var read_count := 0
	while reading.session.flow.runner.index + 1 < reading.session.flow.runner.events.size() 			and reading.session.flow.runner.events[reading.session.flow.runner.index + 1].has("part") and read_count < 10:
		reading._on_next_event_pressed()
		read_count += 1
		c.check("本文/締めの%d行目まで読んでも、状態（鍋・在庫・腐敗・所持金・評判・客の位置・来店記録）は不変" % read_count,
			_snapshot(reading) == snap_start)
	c.check("本文3行＋締め2行の5行を読んだ（客はまだ退店していない）",
		read_count == 5 and str(reading.session.open.current_customer()) == "thug", str(read_count))
	c.check("評価は提供の瞬間に決まったまま（読んでも変わらない）",
		str(reading.session.open.current_bowl.get("result", "")) == graded)
	reading.free()

	# --- 6. customer_events・after_serve_events は、何度呼んでも状態が変わらない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "body": ["B1"], "closing": { "default": ["C1"] },
		"pre_order": ["P1"], "must_info": ["m"], "body_unserved": ["U1"] })
	var pure = _setup(t)
	var snap_before := _snapshot(pure)
	var forecast_before := Forecast.orders_of("thug")
	var first_events := Day1Events.customer_events("thug")
	var first_after := Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": "GOOD" })
	var first_unserved := Day1Events.after_serve_events("thug", "thug_02", { "served": false, "grade": "" })
	for i in range(5):
		Day1Events.customer_events("thug")
		Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": "GOOD" })
		Day1Events.after_serve_events("thug", "thug_02", { "served": false, "grade": "" })
	c.check("何度呼んでも状態（GameState・DayPlan・来店記録・鍋・在庫）が変わらない", _snapshot(pure) == snap_before)
	c.check("何度呼んでも同じ列を返す",
		Day1Events.customer_events("thug") == first_events
			and Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": "GOOD" }) == first_after
			and Day1Events.after_serve_events("thug", "thug_02", { "served": false, "grade": "" }) == first_unserved)
	c.check("朝の予報（Forecast）・杯数の先読みは変わらない",
		Forecast.orders_of("thug") == forecast_before and Day1Events._customer_total_servings("thug", "thug_02") == 1)
	c.check("customer_eventsは来店まで（提供後の本文・締めを含まない）",
		first_events.filter(func(e): return e.has("part")).is_empty())
	c.check("served=false は must_info があるので未提供版、served=true は本文→締め",
		first_unserved == [{ "type": "GREET", "customer": "thug", "text": "U1", "part": "body" }]
			and first_after == [{ "type": "GREET", "customer": "thug", "text": "B1", "part": "body" },
				{ "type": "GREET", "customer": "thug", "text": "C1", "part": "closing" }])
	pure.free()

	# --- 7. 出来で本文・締めは分けない（わざと失敗すると親密になる経路を作らない） ---
	var by_grade := []
	for grade in ["GREAT", "GOOD", "OK", "BAD"]:
		by_grade.append(Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": grade }))
	c.check("served=true の列は出来（GREAT/GOOD/OK/BAD）で変わらない",
		by_grade[0] == by_grade[1] and by_grade[1] == by_grade[2] and by_grade[2] == by_grade[3])

	# --- 8. 対象外：モブ・配達員の3杯列・客でないid・場面なしは空 ---
	c.check("モブ・3杯列・空id・場面なしは空",
		Day1Events.after_serve_events("mob#0", "x", { "served": true }).is_empty()
			and Day1Events.after_serve_events("delivery_man", "delivery_man_01", { "served": true }).is_empty()
			and Day1Events.after_serve_events("", "thug_02", { "served": true }).is_empty()
			and Day1Events.after_serve_events("thug", "", { "served": true }).is_empty())

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
