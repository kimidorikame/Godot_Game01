extends RefCounted
## 需要経路の切替（システム整理A・E 3.4）の検証。モブを総需要システムで決めるかは、日番号
## （以前の day_count > 1）ではなく、その日に固定モブ編成（day_overrides."<日>".mobs）が宣言されて
## いるかで決まる。現行データ（week7.json）ではDay1だけが固定編成なので、動作は従来と同一
## （自動試遊の一致で確認）。ここでは経路の切替そのものを見る。


func _mob_instances() -> Dictionary:
	Day1Events.customer_schedule(-1)
	return (GameState.today_plan["mob_instances"] as Dictionary).duplicate(true)


func _cups(instances: Dictionary) -> int:
	var total := 0
	for id in instances:
		total += int(instances[id]["count"])
	return total


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	Rules.set_campaign("week7")
	Rules.bills()

	# --- 1. 現行データ：Day1は固定編成（宵の口の港湾労働者2・夜半の安宿受付2）で、乱数を引かない ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var day1 := _mob_instances()
	var types := []
	for id in day1:
		types.append("%s:%d" % [str(day1[id]["type"]), int(day1[id]["count"])])
	types.sort()
	c.check("Day1は固定モブ編成（dock_workers:2・inn_clerk:2）", types == ["dock_workers:2", "inn_clerk:2"], str(types))
	seed(12345)
	var before := randi()
	seed(12345)
	_mob_instances()
	c.check("Day1の編成は乱数を引かない（グローバルの乱数列が進まない）", randi() == before)

	# --- 2. 現行データ：Day2〜7は総需要システム（固定編成なし）。総杯数が総需要に合う ---
	for d in range(2, 8):
		GameState.reset_for_new_game()
		GameState.day_count = d
		var inst := _mob_instances()
		c.check("Day%d：固定編成の宣言が無い" % d, Rules.day_overrides(d).get("mobs", []).is_empty())
		c.check("Day%d：モブの杯数は0以上で、総需要を超えない" % d,
			_cups(inst) >= 0 and _cups(inst) <= 17, str(inst))

	# --- 3. 日番号ではなく宣言で決まる：Day1の固定編成を外すと、Day1も総需要システムになる ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	Rules._cache["day_overrides"]["1"].erase("mobs")
	var no_fixed := _mob_instances()
	# Day1の総需要は固定の9杯（day_overrides."1".fixed_demand）。常連3人＝5杯なので、モブへ配るのは最大4杯
	c.check("Day1の固定編成を外すと、総需要（固定9杯）から常連の杯数を引いた残りをモブへ配る（固定の2組×2杯ではない）",
		_cups(no_fixed) > 0 and _cups(no_fixed) <= 4, str(no_fixed))

	# --- 4. 固定編成が宣言された日は、デバッグ上書きが無い限り固定編成が優先される ---
	Rules.set_campaign("week7")
	Rules.bills()
	Rules._cache["day_overrides"]["3"] = { "mobs": [{ "slot": "宵の口", "type": "dock_workers", "count": 1 }] }
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var day3 := _mob_instances()
	c.check("Day3に固定編成を宣言すると、その編成（dock_workers:1の1組）になる",
		day3.size() == 1 and str(day3.values()[0]["type"]) == "dock_workers" and int(day3.values()[0]["count"]) == 1,
		str(day3))

	# --- 5. 後始末 ---
	Rules.set_campaign("week7")
	GameState.reset_for_new_game()
	return c.finish()
