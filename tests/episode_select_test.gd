extends RefCounted
## 場面の選び方・今日の頼み・DayPlanの枠（F6・DESIGN.md 10.8.6。フェーズ4-4b-2コミット①）の検証。
## 対象：ScheduleDataの場面の読み口（requires・order.today_request・callback・候補）、
## EpisodeSelector（requires・not_seen・facts・第一候補・フォールバック・決定性）、
## DayPlanの枠のtoday_request、選んだ場面の杯数での総需要の引き算、封筒の版5。
## 新しい仕組みの確認は、tests/fixtures/episodes/ の場面データ（フィクスチャ）で行い、
## 実データ（requires・order・callbackを持たない21場面）では4-4aと同じ場面を返すことを確かめる。

const FIXTURE_DIR := "res://tests/fixtures/episodes/"

# 実データの21枠（日 → [宵の口, 夜半, 明け方]）の静的episode_id。4-4aの割り当て。
const STATIC_IDS := {
	1: ["delivery_man_01", "thug_01", "granny_01"],
	2: ["officer_01", "delivery_man_02", "thug_02"],
	3: ["hooker_01", "granny_02", "officer_02"],
	4: ["streamer_01", "hooker_02", "delivery_man_03"],
	5: ["thug_03", "officer_03", "streamer_02"],
	6: ["delivery_man_04", "thug_04", "hooker_03"],
	7: ["streamer_03", "officer_04", "granny_03"],
}


func _use_fixtures() -> void:
	ScheduleData.episodes_dir = FIXTURE_DIR
	ScheduleData.clear_cache()


func _use_real() -> void:
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	_use_real()
	GameState.reset_for_new_game()

	# --- 1. 実データ：requires・order・callbackを持たない＝選び方は4-4aと同じ場面を返す ---
	for d in range(1, 8):
		for i in range(3):
			var slot: Dictionary = ScheduleData.regular_slots(d)[i]
			var regular := str(slot["regular"])
			var eid := str(slot["episode_id"])
			c.check("Day%d 枠%d（%s）：選び方は静的idと同じ（4-4a）" % [d, i, regular],
				EpisodeSelector.select(regular, eid) == STATIC_IDS[d][i] and eid == STATIC_IDS[d][i])
	# 既読にしても、requiresが無ければ変わらない
	GameState.customer_memory.clear()
	for d in range(1, 8):
		for slot in ScheduleData.regular_slots(d):
			CustomerMemory.ensure_visit(str(slot["regular"]), "宵の口", str(slot["episode_id"]))
	var all_same := true
	for d in range(1, 8):
		for slot in ScheduleData.regular_slots(d):
			if EpisodeSelector.select(str(slot["regular"]), str(slot["episode_id"])) != str(slot["episode_id"]):
				all_same = false
	c.check("全場面を見ていても、requiresが無ければ選び方は変わらない", all_same)
	var bad_keys := []
	for d in range(1, 8):
		for slot in ScheduleData.regular_slots(d):
			var ep := ScheduleData.episode_data(str(slot["regular"]), str(slot["episode_id"]))
			for key in ["requires", "order", "callback"]:
				if ep.has(key):
					bad_keys.append("%s:%s" % [slot["episode_id"], key])
	c.check("実データの21場面は requires・order・callback を持たない", bad_keys.is_empty(), str(bad_keys))
	GameState.reset_for_new_game()

	# --- 2. 実データのDayPlan：全日の枠が today_request を持つ（空）。episode_idは4-4aと同じ ---
	for d in range(1, 8):
		GameState.reset_for_new_game()
		GameState.day_count = d
		DayPlanner.build()
		var slots: Array = GameState.today_plan["slots"]
		var shape_ok := slots.size() == 3
		for i in range(slots.size()):
			if not (slots[i].has("today_request") and slots[i]["today_request"] == {}) \
					or str(slots[i]["episode_id"]) != STATIC_IDS[d][i]:
				shape_ok = false
		c.check("Day%d：DayPlanの枠はtoday_request（空）を持ち、episode_idは4-4aと同じ" % d, shape_ok, str(slots))

	# --- 3. フィクスチャ：場面データの読み口（requires・order・callback・候補・余分なキー） ---
	_use_fixtures()
	c.check("候補はid順（thug_01〜thug_04）", ScheduleData.episode_candidates("thug") ==
		["thug_01", "thug_02", "thug_03", "thug_04"], str(ScheduleData.episode_candidates("thug")))
	c.check("置き場の無い客の候補は空（エラーにならない）", ScheduleData.episode_candidates("hooker").is_empty())
	c.check("requiresを読める（facts）",
		ScheduleData.episode_requires("thug", "thug_02") == { "facts": { "unlock": true } })
	c.check("requiresが無い場面は空辞書", ScheduleData.episode_requires("thug", "thug_01").is_empty())
	c.check("today_requestを読める（tags・label）",
		ScheduleData.episode_today_request("thug", "thug_01") ==
			{ "tags": ["MELLOW", "GENTLE"], "label": "持ち帰り" })
	c.check("today_requestが無い場面は空辞書", ScheduleData.episode_today_request("thug", "thug_02").is_empty())
	var callback := ScheduleData.episode_callback("officer", "officer_01")
	c.check("callbackを読める（出し分けのキーごとの行）",
		callback.has("first") and callback.has("last_unserved") and callback.has("last_grade_good_or_better")
			and callback.has("last_grade_bad") and (callback["first"] as Array).size() == 2)
	var extra := ScheduleData.episode_data("officer", "officer_01")
	c.check("sets_facts・choices・body・closing・must_info が入っていても壊れない（読まない）",
		extra.has("sets_facts") and extra.has("choices") and extra.has("body") and extra.has("closing")
			and extra.has("must_info") and not ScheduleData.episode_today_request("officer", "officer_01").is_empty())
	c.check("無い場面・空idは空辞書", ScheduleData.episode_requires("thug", "thug_99").is_empty()
		and ScheduleData.episode_today_request("", "x").is_empty()
		and ScheduleData.episode_callback("thug", "").is_empty())
	var order_fixture: Dictionary = ScheduleData.episode_data("thug", "thug_01").get("order", {})
	c.check("order.reask（聞き直しの台詞）は辞書の中に残る（読み口は③）",
		order_fixture.get("reask", []) == ["持ち帰りを頼む（再掲）"])

	# --- 4. 選び方（フィクスチャ）：第一候補が満たせばそれ・満たさなければ他の場面・満たす物が無ければ第一候補 ---
	GameState.reset_for_new_game()
	c.check("第一候補がrequiresを満たす（なし）ならそれ", EpisodeSelector.select("thug", "thug_01") == "thug_01")
	c.check("factsが満たされなければ、id順で最初に満たす他の場面（thug_01）",
		EpisodeSelector.select("thug", "thug_02") == "thug_01")
	CustomerMemory.set_fact("thug", "unlock", true)
	c.check("factsを立てると第一候補（thug_02）が選ばれる", EpisodeSelector.select("thug", "thug_02") == "thug_02")
	CustomerMemory.set_fact("thug", "unlock", false)
	c.check("事実が別の値なら満たさない（unlock=falseのとき）",
		EpisodeSelector.select("thug", "thug_02") == "thug_01")
	GameState.customer_memory.clear()
	c.check("not_seen：未読なら第一候補（thug_03）", EpisodeSelector.select("thug", "thug_03") == "thug_03")
	CustomerMemory.arrive("thug", "宵の口", "thug_03")   # thug_03を見た（seen_episodes）
	c.check("not_seen：既読の場面は選ばない（thug_01へ）", EpisodeSelector.select("thug", "thug_03") == "thug_01")
	c.check("満たす場面が無ければ第一候補へ戻す（granny：どれも満たさない）",
		EpisodeSelector.select("granny", "granny_01") == "granny_01"
			and EpisodeSelector.select("granny", "granny_02") == "granny_02")
	c.check("置き場の無い客・空idは第一候補をそのまま返す",
		EpisodeSelector.select("hooker", "hooker_01") == "hooker_01"
			and EpisodeSelector.select("", "x") == "x" and EpisodeSelector.select("thug", "") == "")
	var stable := true
	for i in range(30):
		if EpisodeSelector.select("thug", "thug_02") != "thug_01":
			stable = false
	c.check("乱数を使わない（同じ記録で30回とも同じ）", stable)
	GameState.customer_memory.clear()
	c.check("候補の順（id順）：thug_02が満たせないとき、thug_03も満たせる状況でもthug_01が先",
		EpisodeSelector.select("thug", "thug_02") == "thug_01")

	# --- 5. DayPlan：選んだ場面・今日の頼みが枠に入る。モブ杯数は選んだ場面の杯数で引く ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65   # 需要の中心14
	DayPlanner.build()
	var slots2: Array = GameState.today_plan["slots"]
	# Day2：宵の口=新人警官・夜半=配達員・明け方=チンピラ（静的idはthug_02。unlockが無いのでthug_01へ）
	c.check("前提を満たさない第一候補は、別の場面へ（thug_02→thug_01）",
		str(slots2[2]["regular_id"]) == "thug" and str(slots2[2]["episode_id"]) == "thug_01", str(slots2[2]))
	c.check("選んだ場面の今日の頼みが枠に入る",
		slots2[2]["today_request"] == { "tags": ["MELLOW", "GENTLE"], "label": "持ち帰り" })
	c.check("今日の頼みを持つ場面（フィクスチャのofficer_01）の枠にも入り、持たない客（配達員）は空辞書",
		slots2[0]["today_request"] == { "tags": ["SOUR", "BITE"], "label": "いつもの確認" }
			and slots2[1]["today_request"] == {})
	c.check("episode_id_ofはDayPlanが選んだ場面を返す（thug_01）",
		Day1Events.episode_id_of("thug") == "thug_01")
	var mob_cups := 0
	for id in GameState.today_plan["mob_instances"]:
		mob_cups += int(GameState.today_plan["mob_instances"][id]["count"])
	var center := GameState.demand_center_today()
	# 常連の杯数＝新人警官1＋配達員1＋選んだ場面（thug_01）の2杯＝4。
	c.check("モブ杯数は選んだ場面の杯数（thug_01=2杯）で引く（総杯数が中心±1・実測%d）" % (mob_cups + 4),
		mob_cups + 4 >= center - 1 and mob_cups + 4 <= center + 1)
	c.check("選んだ場面のservings（2）がcustomer_eventsに出る",
		_servings_of(Day1Events.customer_events("thug", 0, "thug_01")) == 2
			and _servings_of(Day1Events.customer_events("thug", 0, "thug_02")) == 1)
	# factsを立てて作り直すと第一候補（thug_02）
	GameState.reset_for_new_game()
	GameState.day_count = 2
	CustomerMemory.set_fact("thug", "unlock", true)
	DayPlanner.build()
	c.check("事実が立っていれば、枠のepisode_idは第一候補（thug_02）・今日の頼みは空",
		str(GameState.today_plan["slots"][2]["episode_id"]) == "thug_02"
			and GameState.today_plan["slots"][2]["today_request"] == {})
	# 同日に同じ客は2回来ない（選び方は枠ごと。日程で保証）
	var regulars := []
	for slot in GameState.today_plan["slots"]:
		regulars.append(slot["regular_id"])
	c.check("同日に同じ客が2回来ない", regulars.size() == 3 and regulars[0] != regulars[1]
		and regulars[1] != regulars[2] and regulars[0] != regulars[2])
	# 同じ記録で作り直しても同じ（決定的）
	var first_slots: Array = (GameState.today_plan["slots"] as Array).duplicate(true)
	DayPlanner.build()
	c.check("同じ記録でDayPlanを作り直しても枠が同じ（決定的）", GameState.today_plan["slots"] == first_slots)

	# --- 6. 保存：版5・枠のtoday_request・往復・再挑戦で同じ今日の頼み ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	DayPlanner.build()
	var env := MorningSave.capture("")
	c.check("MorningSaveの版は5", int(env["version"]) == 5 and MorningSave.VERSION == 5)
	c.check("today_requestを持つ枠の封筒は有効", MorningSave.is_valid(env))
	var v4 := env.duplicate(true)
	v4["version"] = 4
	c.check("版4の保存は読めない扱い（新規ゲーム）", not MorningSave.is_valid(v4))
	var no_req := env.duplicate(true)
	for slot in no_req["state"]["today_plan"]["slots"]:
		slot.erase("today_request")
	c.check("枠にtoday_requestが無い封筒（版4以前）は無効", not MorningSave.is_valid(no_req))
	var bad_req := env.duplicate(true)
	bad_req["state"]["today_plan"]["slots"][0]["today_request"] = "x"
	c.check("today_requestが辞書でなければ無効", not MorningSave.is_valid(bad_req))
	var before: Array = (GameState.today_plan["slots"] as Array).duplicate(true)
	GameState.reset_for_new_game()
	MorningSave.apply(env)
	c.check("復元後のDayPlanの枠（today_request込み）が同一（再挑戦で同じ今日の頼み）",
		GameState.today_plan["slots"] == before and before[2]["today_request"].has("tags"))
	c.check("復元後もepisode_id_ofは選んだ場面（thug_01）を返す", Day1Events.episode_id_of("thug") == "thug_01")

	_use_real()
	GameState.reset_for_new_game()
	return c.finish()


func _servings_of(events: Array) -> int:
	var total := 0
	for ev in events:
		if str(ev.get("type", "")) == "REACT":
			total += int(ev.get("servings", 0))
	return total
