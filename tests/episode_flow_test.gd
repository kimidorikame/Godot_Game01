extends RefCounted
## 場面idで客の会話を引く経路（フェーズ4-4a・DESIGN.md 10.8.2・10.9）の検証。
## 対象：DayPlanの枠（regular_id・episode_id）、Day1Events.episode_id_of()の引き方
## （DayPlanの日が今日のときだけ使う／日が違えば日程から引く）、配達員の3杯専用列の判定
## （日番号ではなく場面id）、日程の無い日、保存の版3。

const EPISODES := {
	1: ["delivery_man_01", "thug_01", "granny_01"],
	2: ["officer_01", "delivery_man_02", "thug_02"],
	3: ["hooker_01", "granny_02", "officer_02"],
	4: ["streamer_01", "hooker_02", "delivery_man_03"],
	5: ["thug_03", "officer_03", "streamer_02"],
	6: ["delivery_man_04", "thug_04", "hooker_03"],
	7: ["streamer_03", "officer_04", "granny_03"],
}
const REGULARS := {
	1: ["delivery_man", "thug", "granny"],
	2: ["officer", "delivery_man", "thug"],
	3: ["hooker", "granny", "officer"],
	4: ["streamer", "hooker", "delivery_man"],
	5: ["thug", "officer", "streamer"],
	6: ["delivery_man", "thug", "hooker"],
	7: ["streamer", "officer", "granny"],
}


func _reacts(events: Array) -> int:
	var n := 0
	for ev in events:
		if str(ev.get("type", "")) == "REACT":
			n += 1
	return n


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()

	# --- 1. DayPlanの枠が regular_id・episode_id を持つ（customersの先頭が常連） ---
	for d in range(1, 8):
		GameState.reset_for_new_game()
		GameState.day_count = d
		DayPlanner.build()
		var slots: Array = GameState.today_plan["slots"]
		c.check("Day%d：DayPlanは3枠" % d, slots.size() == 3)
		for i in range(slots.size()):
			var slot: Dictionary = slots[i]
			c.check("Day%d 枠%d：regular_id・episode_idが日程どおり" % [d, i],
				str(slot.get("regular_id", "")) == REGULARS[d][i]
					and str(slot.get("episode_id", "")) == EPISODES[d][i], str(slot))
			c.check("Day%d 枠%d：customersの先頭がregular_id（name・customersは従来の形）" % [d, i],
				(slot["customers"] as Array)[0] == slot["regular_id"] and slot.has("name"))
		c.check("Day%d：today_planの日はその日" % d, int(GameState.today_plan["day"]) == d)

	# --- 2. episode_id_of：DayPlanが今日のものなら枠から。日が違えば日程から ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	DayPlanner.build()
	c.check("Day1：配達員の場面はdelivery_man_01（DayPlanの枠から）",
		Day1Events.episode_id_of("delivery_man") == "delivery_man_01")
	c.check("Day1：配達員の杯数は3（3杯の専用列）", Day1Events._customer_total_servings("delivery_man") == 3)
	# 前日（Day1）の枠を残したまま日を進める（DayPlanner.build()の途中・テストが続けて呼ぶ場合）
	GameState.day_count = 2
	c.check("（前提）前日の枠が残っている（today_planの日=1・今日=2）",
		int(GameState.today_plan["day"]) == 1 and GameState.day_count == 2)
	c.check("日を進めたら前日の枠は使わない：Day2の配達員はdelivery_man_02",
		Day1Events.episode_id_of("delivery_man") == "delivery_man_02",
		Day1Events.episode_id_of("delivery_man"))
	c.check("Day1の3杯列がDay2の杯数計算に混ざらない（配達員1杯）",
		Day1Events._customer_total_servings("delivery_man") == 1)
	c.check("Day2：新人警官はofficer_01（日程から）", Day1Events.episode_id_of("officer") == "officer_01")
	c.check("Day2：前日の枠にいたチンピラは、今日の日程の場面thug_02",
		Day1Events.episode_id_of("thug") == "thug_02")
	# 前日の枠を残したままcustomer_schedule()（build中の計算）をしても、モブ杯数がずれない
	GameState.reputation = 65   # 中心14
	for i in range(20):
		var sched: Array = Day1Events.customer_schedule(-1)
		var mob_cups := 0
		for id in GameState.today_plan["mob_instances"]:
			mob_cups += int(GameState.today_plan["mob_instances"][id]["count"])
		c.check("前日の枠が残っていても、Day2の常連は3杯・総杯数は中心14±1（%d）" % (mob_cups + 3),
			mob_cups + 3 >= 13 and mob_cups + 3 <= 15 and sched[0]["customers"][0] == "officer")
		if mob_cups + 3 < 13 or mob_cups + 3 > 15:
			break
	# DayPlanが今日のものなら、枠のepisode_idを優先する
	DayPlanner.build()
	var plan_slots: Array = GameState.today_plan["slots"]
	plan_slots[1]["episode_id"] = "delivery_man_04"
	c.check("DayPlanが今日のものなら枠のepisode_idを使う",
		Day1Events.episode_id_of("delivery_man") == "delivery_man_04")
	c.check("客でない・場面の無いidは空文字",
		Day1Events.episode_id_of("") == "" and Day1Events.episode_id_of("mob#0") == ""
			and Day1Events.episode_id_of("no_such_customer") == "")

	# --- 3. 配達員の3杯専用列は場面idで決まる（日番号ではない） ---
	for d in [1, 2, 3, 4, 5, 6, 7]:
		GameState.reset_for_new_game()
		GameState.day_count = d
		var reacts := _reacts(Day1Events.customer_events("delivery_man"))
		var want := 3 if d == 1 else 1
		c.check("Day%d：配達員のREACTは%d（Day1だけ3杯列。日程に無いDay3・5・7は最後の場面の1杯）" % [d, want],
			reacts == want, str(reacts))
	# DayPlanが「最初の場面」を持つ日なら、日番号が1でなくても3杯列（日番号の直書きではない）
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.today_plan = { "day": 3, "demand_center": 11, "mob_instances": {},
		"slots": [{ "name": "宵の口", "customers": ["delivery_man"],
			"regular_id": "delivery_man", "episode_id": "delivery_man_01" }] }
	c.check("場面idがdelivery_man_01なら日番号に関わらず3杯列",
		_reacts(Day1Events.customer_events("delivery_man")) == 3)
	GameState.today_plan = { "day": 1, "demand_center": 9, "mob_instances": {},
		"slots": [{ "name": "宵の口", "customers": ["delivery_man"],
			"regular_id": "delivery_man", "episode_id": "delivery_man_02" }] }
	GameState.day_count = 1
	c.check("Day1でも場面idがdelivery_man_02なら通常の1杯",
		_reacts(Day1Events.customer_events("delivery_man")) == 1)

	# --- 4. 日程の無い日（Day8）：枠なし・客なし・落ちない ---
	GameState.reset_for_new_game()
	GameState.day_count = 8
	var s8: Array = Day1Events.customer_schedule(-1)
	c.check("Day8：customer_schedule()は空（客なし）", s8.is_empty())
	DayPlanner.build()
	c.check("Day8：DayPlanの枠も空・落ちない",
		(GameState.today_plan["slots"] as Array).is_empty() and int(GameState.today_plan["day"]) == 8)
	c.check("Day8：OpenControllerは空の枠でも作れる", OpenController.new([]) != null)

	# --- 5. 保存：版3・枠の検査 ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	DayPlanner.build()
	var env := MorningSave.capture("")
	c.check("MorningSaveの版は3", int(env["version"]) == 3 and MorningSave.VERSION == 3)
	c.check("DayPlanの枠が新しい形の封筒は有効", MorningSave.is_valid(env))
	var old_version := env.duplicate(true)
	old_version["version"] = 2
	c.check("版2の保存は読めない扱い（新規ゲーム）", not MorningSave.is_valid(old_version))
	var no_ids := env.duplicate(true)
	for slot in no_ids["state"]["today_plan"]["slots"]:
		slot.erase("regular_id")
		slot.erase("episode_id")
	c.check("枠にregular_id・episode_idが無い封筒（4-3以前）は無効", not MorningSave.is_valid(no_ids))
	var bad_type := env.duplicate(true)
	bad_type["state"]["today_plan"]["slots"][0]["episode_id"] = 5
	c.check("episode_idが文字列でなければ無効", not MorningSave.is_valid(bad_type))
	# 復元しても枠の形・場面idが同じ（再挑戦で同じDayPlanに戻る）
	var before: Array = (GameState.today_plan["slots"] as Array).duplicate(true)
	GameState.reset_for_new_game()
	MorningSave.apply(env)
	c.check("復元後のDayPlanの枠（regular_id・episode_id込み）が同一",
		GameState.today_plan["slots"] == before)
	c.check("復元後も場面idを引ける（日が今日のDayPlanから）",
		Day1Events.episode_id_of("delivery_man") == "delivery_man_02")

	GameState.reset_for_new_game()
	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
