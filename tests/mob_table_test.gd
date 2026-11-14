extends RefCounted
## 中身W：モブの日別の職種表（data/schedules/mob_rules.json）の確かめ。
##   1. 2〜7日目に来るモブの組は、入った時間帯の職種（表どおり）。組が多い晩（4組目が宵の口に入る晩など）は、その時間帯の職種が2組目として来る。
##      明け方にモブが来ない晩（7日目）は、3組目が夜半へ回る（今の決まり）。評判（客足）を変えて、組の数が違う晩を作って確かめる。
##   2. 朝の来店予告（DM）で「来る」と言うモブの職種は、その日の表にある職種だけ（来ない職種の予告は出ない）。

const TABLE := {
	2: { "宵の口": "market_porter", "夜半": "laundry_night", "明け方": "long_haul_driver" },
	3: { "宵の口": "inn_clerk", "夜半": "general_store_clerk", "明け方": "street_cleaners" },
	4: { "宵の口": "long_haul_driver", "夜半": "general_store_clerk", "明け方": "laundry_night" },
	5: { "宵の口": "market_porter", "夜半": "security_guard", "明け方": "dock_workers" },
	6: { "宵の口": "long_haul_driver", "夜半": "security_guard", "明け方": "street_cleaners" },
	7: { "宵の口": "inn_clerk", "夜半": "market_porter" },
}


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()
	var wrong := []
	var max_groups := {}
	var two_in_slot := []
	var preview_wrong := []
	for d in TABLE:
		for rep in [10, 30, 50, 65, 80, 100]:
			GameState.reset_for_new_game()
			GameState.day_count = d
			GameState.reputation = rep
			DayPlanner.build()
			var groups := 0
			for slot in GameState.today_plan["slots"]:
				var in_slot := 0
				for id in slot["customers"]:
					if not str(id).begins_with("mob#"):
						continue
					groups += 1
					in_slot += 1
					var type_id := str(GameState.today_plan["mob_instances"][id]["type"])
					var want := str(TABLE[d].get(str(slot["name"]), ""))
					if type_id != want:
						wrong.append("Day%d %s 評判%d：%s（表は %s）" % [d, slot["name"], rep, type_id, want])
				if in_slot >= 2:
					two_in_slot.append("Day%d %s 評判%d：%d組" % [d, slot["name"], rep, in_slot])
			max_groups[d] = maxi(int(max_groups.get(d, 0)), groups)
			for item in Dm.preview_items(d, []):
				if str(item.get("from_kind", "")) == "mob" and not (TABLE[d].values() as Array).has(str(item["subject"])):
					preview_wrong.append("Day%d %s" % [d, item["subject"]])
	c.check("2〜7日目のモブの組は、入った時間帯の職種（表どおり。評判を変えても）", wrong.is_empty(), str(wrong))
	c.check("組が多い晩は、同じ時間帯に同じ職種が2組目として来る（%s）" % str(two_in_slot), not two_in_slot.is_empty())
	c.check("朝の来店予告（DM）のモブは、その日の表にある職種だけ", preview_wrong.is_empty(), str(preview_wrong))
	print("  日ごとの最大の組数：%s" % str(max_groups))
	GameState.reset_for_new_game()
	return c.finish()
