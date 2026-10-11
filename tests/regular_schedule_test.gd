extends RefCounted
## 常連の固定日程（21枠）とモブの抽選ルールのデータ（フェーズ4-3・DESIGN.md 10.5.1・10.8.1）の
## 検証。対象：data/schedules/week7_regulars.json、mob_rules.json、ScheduleData の読み込みと
## 互換層（compose_day_schedule）。customer_schedule()が実際にこの日程どおりに来るか
## （コミット②）の確認も、このスイートの後半に置く。

const SLOTS := ["宵の口", "夜半", "明け方"]

# 10.5.1の表（日 → [宵の口, 夜半, 明け方]）。JSONの内容をここと突き合わせる。
const TABLE := {
	1: ["delivery_man", "thug", "granny"],
	2: ["officer", "delivery_man", "thug"],
	3: ["hooker", "granny", "officer"],
	4: ["streamer", "hooker", "delivery_man"],
	5: ["thug", "officer", "streamer"],
	6: ["delivery_man", "thug", "hooker"],
	7: ["streamer", "officer", "granny"],
}

# 10.5.1「常連の基本注文」（日によって変えない）と好物。
const BASE_ORDER := {
	"delivery_man": [["HOT", "POWER"], "tofu"],
	"thug": [["MELLOW", "GENTLE"], "meat_ball"],
	"granny": [["SAVORY", "FILLING"], "offal"],
	"officer": [["SOUR", "BITE"], "rice_noodle"],
	"hooker": [["BITTER", "TREAT"], "pickled_lime"],
	"streamer": [["MELLOW", "BITE"], "shrimp"],
}

const MOB_POOL := ["dock_workers", "security_guard", "inn_clerk", "street_cleaners",
	"general_store_clerk", "market_porter", "long_haul_driver"]


func _regulars_of(day: int) -> Array:
	var entries: Array = ScheduleData.regular_schedule_data().get("days", {}).get(str(day), [])
	return entries.map(func(e): return str(e.get("regular", "")))


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()

	# --- 1. week7_regulars.json が 10.5.1 の表と一致する ---
	c.check("week7.jsonのregular_scheduleはweek7_regulars", Rules.regular_schedule() == "week7_regulars")
	var days: Dictionary = ScheduleData.regular_schedule_data().get("days", {})
	c.check("1〜7日の定義がある", days.size() == 7)
	for d in range(1, 8):
		c.check("Day%dの常連は10.5.1の表どおり（宵の口・夜半・明け方の順）" % d,
			_regulars_of(d) == TABLE[d], str(_regulars_of(d)))
		var names := []
		for e in days.get(str(d), []):
			names.append(str(e.get("slot", "")))
		c.check("Day%dの枠名は『宵の口・夜半・明け方』" % d, names == SLOTS, str(names))

	# --- 2. 来店回数・重複・初登場 ---
	var counts := {}
	var dup_days := []
	var first := {}
	for d in range(1, 8):
		var seen := {}
		var regs := _regulars_of(d)
		for i in range(regs.size()):
			var id: String = regs[i]
			counts[id] = int(counts.get(id, 0)) + 1
			if seen.has(id):
				dup_days.append(d)
			seen[id] = true
			if not first.has(id):
				first[id] = [d, i]
	c.check("来店回数：配達員4・チンピラ4・新人警官4・老婆3・夜の女3・配信者3",
		int(counts.get("delivery_man", 0)) == 4 and int(counts.get("thug", 0)) == 4
			and int(counts.get("officer", 0)) == 4 and int(counts.get("granny", 0)) == 3
			and int(counts.get("hooker", 0)) == 3 and int(counts.get("streamer", 0)) == 3, str(counts))
	var total := 0
	for id in counts:
		total += int(counts[id])
	c.check("合計21枠", total == 21)
	c.check("同日の重複なし", dup_days.is_empty(), str(dup_days))
	c.check("初登場は新人警官=Day2・夜の女=Day3・配信者=Day4（いずれも宵の口）",
		first["officer"] == [2, 0] and first["hooker"] == [3, 0] and first["streamer"] == [4, 0],
		str(first))
	c.check("Day7の明け方は老婆", _regulars_of(7)[2] == "granny")

	# --- 3. 21枠それぞれに、基本注文・好物・杯数・会話が存在する（フォールバックでも空にならない） ---
	for d in range(1, 8):
		var regs := _regulars_of(d)
		for i in range(regs.size()):
			var id: String = regs[i]
			var data := ScheduleData.customer_data(id, d)
			var label := "Day%d %s（%s）" % [d, SLOTS[i], id]
			c.check("%s：客データがある" % label, not data.is_empty())
			c.check("%s：基本注文が10.5.1どおり" % label,
				data.get("wanted_tags", []) == BASE_ORDER[id][0], str(data.get("wanted_tags")))
			c.check("%s：好物が10.5.1どおり" % label, str(data.get("favorite", "")) == BASE_ORDER[id][1])
			c.check("%s：杯数は1以上・会話がある" % label,
				int(data.get("servings", 0)) >= 1 and not (data.get("greet", []) as Array).is_empty())

	# --- 4. モブの抽選ルール（既定＋日別の上書き） ---
	var rules := ScheduleData.mob_rules_data()
	c.check("既定のプールは7種", rules.get("default", {}).get("pool", []) == MOB_POOL)
	c.check("既定は3枠ともモブ可", rules.get("default", {}).get("slots", {}) ==
		{ "宵の口": true, "夜半": true, "明け方": true })

	# --- 5. 互換層：旧day_scheduleと同じ形で、常連は固定・モブの出方は旧データと同じ ---
	for d in range(1, 8):
		var comp := ScheduleData.compose_day_schedule(d)
		var old := ScheduleData.day_schedule(d)
		c.check("Day%d：組み立てた枠は3つ（name/main/mob）" % d,
			comp.get("slots", []).size() == 3
				and comp["slots"].all(func(s): return s.has("name") and s.has("main") and s.has("mob")))
		for i in range(3):
			var cs: Dictionary = comp["slots"][i]
			var os: Dictionary = old["slots"][i]
			c.check("Day%d %s：常連は表どおり固定（main_poolではない）" % [d, SLOTS[i]],
				str(cs["main"]) == TABLE[d][i] and not cs.has("main_pool"))
			c.check("Day%d %s：モブの可否は旧データと同じ" % [d, SLOTS[i]],
				Day1Events._slot_mob_eligible(cs) == Day1Events._slot_mob_eligible(os))
			if d >= 2 and Day1Events._slot_mob_eligible(cs):
				c.check("Day%d %s：モブのプールは旧データと同じ" % [d, SLOTS[i]],
					(cs["mob"] as Dictionary)["pool"] == (os["mob"] as Dictionary)["pool"])
	var comp1 := ScheduleData.compose_day_schedule(1)
	c.check("Day1宵の口のモブはdock_workers固定", comp1["slots"][0]["mob"] == { "pool": ["dock_workers"] })
	c.check("Day1夜半のモブは3種のプール（デバッグ上書き用）",
		comp1["slots"][1]["mob"] == { "pool": ["dock_workers", "inn_clerk", "market_porter"] })
	c.check("Day1明け方はモブなし", comp1["slots"][2]["mob"] == false)
	c.check("Day7明け方はモブなし", ScheduleData.compose_day_schedule(7)["slots"][2]["mob"] == false)
	c.check("Day2〜6は3枠とも既定の7種プール",
		[2, 3, 4, 5, 6].all(func(d): return ScheduleData.compose_day_schedule(d)["slots"].all(
			func(s): return s["mob"] == { "pool": MOB_POOL })))
	c.check("定義の無い日（Day8）はDay1と同じ（フォールバック）",
		ScheduleData.compose_day_schedule(8) == ScheduleData.compose_day_schedule(1))

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
