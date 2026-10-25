extends RefCounted
## 日別ニュースと必須情報の担保（システム整理D-①。DESIGN.md 10.5.5。SEVEN_DAY_OUTLINE.md §11）の検証。
## data/news/week7.json の形、必須情報9項目のカタログ、すべての項目が「ニュースまたは共通イベント」
## （客・モブ・評判に依存しない経路）で、概要表の日に届くこと、場面データの must_info が未知の
## 識別子を使えないこと、仮データの印（provisional）。

# SEVEN_DAY_OUTLINE.md §11 の表（必須情報の id → 届く日）。データがこの表から外れたら落とす。
const EXPECTED_DAYS := {
	"strike_started": 1, "checkpoints": 2, "nightlife_spillover": 3, "video_spread": 4,
	"night_removal": 5, "rights_shift": 5, "clash_fire": 6, "official_arson_claim": 7,
	"truth_unresolved": 7,
}
# 共通イベントで届ける項目（朝のニュースではない）。
const EVENT_ONLY := ["clash_fire"]


func _fresh() -> Dictionary:
	return News.data().duplicate(true)


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	News.clear_cache()
	ScheduleData.clear_cache()

	# --- 1. 実データ：形に問題が無い・カタログは9項目で概要表のとおり ---
	var problems := News.problems()
	c.check("data/news/week7.json の形と担保に問題が無い", problems.is_empty(), str(problems))
	var catalog := News.catalog()
	c.check("必須情報は9項目", catalog.size() == 9, str(catalog.size()))
	var catalog_days := {}
	for entry in catalog:
		catalog_days[entry["id"]] = entry["day"]
		c.check("%s：label がある" % entry["id"], str(entry["label"]) != "")
	c.check("カタログの id と届く日が概要表（§11）と一致", catalog_days == EXPECTED_DAYS, str(catalog_days))

	# --- 2. 担保：全項目が、ニュースか共通イベントで、表の日に現れる（客の場面を根拠にしない） ---
	var delivered := News.delivered_days()
	for id in EXPECTED_DAYS:
		c.check("%s：ニュースまたは共通イベントのDay%dに現れる（その日だけ）" % [id, EXPECTED_DAYS[id]],
			delivered.has(id) and delivered[id] == [EXPECTED_DAYS[id]], str(delivered.get(id)))
	var event_ids := []
	for day in range(1, 8):
		for ev in News.day_entry(day)["events"]:
			for id in ev["must_info"]:
				event_ids.append(id)
	c.check("共通イベントで届ける項目は clash_fire だけ（他は朝のニュース）", Array(event_ids).filter(
		func(id): return not EVENT_ONLY.has(id)).is_empty() and event_ids.has("clash_fire"))
	var day7_unresolved := false
	for item in News.day_entry(7)["news"]:
		day7_unresolved = day7_unresolved or (item["must_info"] as Array).has("truth_unresolved")
	c.check("#9 真相は確定しない：Day7のニュースに truth_unresolved の印がある", day7_unresolved)
	var truth_item: Dictionary = {}
	for item in News.day_entry(7)["news"]:
		if (item["must_info"] as Array).has("truth_unresolved"):
			truth_item = item
	c.check("#9：複数の説を並べる（本文が3行以上）", (truth_item.get("body", []) as Array).size() >= 3)

	# --- 3. 仮データの印：全項目に provisional が付いている（脚本で差し替える） ---
	var all_provisional := true
	var any_items := 0
	for day in range(1, 8):
		var entry := News.day_entry(day)
		for kind in ["news", "events"]:
			for item in entry[kind]:
				any_items += 1
				all_provisional = all_provisional and bool(item.get("provisional", false))
	c.check("全項目に provisional が付いている（%d件）" % any_items, all_provisional and any_items > 0)
	c.check("毎日ニュースが1件以上ある（Day1〜7）", range(1, 8).all(func(d): return not News.day_entry(d)["news"].is_empty()))
	c.check("日程の無い日・未来の日は空（Day8）", News.day_entry(8)["news"].is_empty() and News.day_entry(8)["events"].is_empty())

	# --- 4. 担保が崩れるデータは落ちる ---
	var removed := _fresh()
	for item in removed["days"]["5"]["news"]:
		if (item["must_info"] as Array).has("night_removal"):
			(item["must_info"] as Array).erase("night_removal")
	c.check("ニュースから項目を外す（客の場面にだけ残る状態）と落ちる：%s" % "night_removal",
		not News.problems(removed).is_empty() and str(News.problems(removed)).contains("night_removal"))
	var moved := _fresh()
	moved["days"]["6"]["events"][0]["must_info"] = []
	moved["days"]["6"]["events"][1]["must_info"] = []
	c.check("共通イベントから clash_fire を外すと落ちる", str(News.problems(moved)).contains("clash_fire"))
	var wrong_day := _fresh()
	wrong_day["days"]["3"]["news"][0]["must_info"] = ["strike_started"]
	c.check("表と違う日に現れると落ちる（strike_started をDay3へ）", str(News.problems(wrong_day)).contains("strike_started"))
	var unknown := _fresh()
	unknown["days"]["2"]["news"][0]["must_info"] = ["no_such_info"]
	c.check("未知の識別子を弾く", str(News.problems(unknown)).contains("no_such_info"))
	var bad_at := _fresh()
	bad_at["days"]["6"]["events"][0]["at"] = "昼"
	c.check("at が wake／close／時間帯名でないと落ちる", not News.problems(bad_at).is_empty())
	var dup_id := _fresh()
	dup_id["days"]["2"]["news"][0]["id"] = "d1_strike"
	c.check("ニュース／共通イベントの id の重複を弾く", not News.problems(dup_id).is_empty())
	var no_lines := _fresh()
	no_lines["days"]["6"]["events"][0]["lines"] = []
	c.check("共通イベントの lines が空だと落ちる", not News.problems(no_lines).is_empty())
	var no_headline := _fresh()
	no_headline["days"]["1"]["news"][0]["headline"] = ""
	c.check("headline が空だと落ちる", not News.problems(no_headline).is_empty())
	var bad_day_key := _fresh()
	bad_day_key["days"]["9"] = { "news": [], "events": [] }
	c.check("日のキーが最終日を超えると落ちる", not News.problems(bad_day_key).is_empty())
	var no_catalog := _fresh()
	no_catalog.erase("must_info")
	c.check("カタログが無いと落ちる", not News.problems(no_catalog).is_empty())
	c.check("読めない（空の）データは問題として返す", News.problems({ "x": 1 }) != [])

	# --- 5. 場面データの must_info：カタログにある id だけ（実データ21場面は持たない） ---
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()
	var scenes := 0
	var scene_problems := []
	for cid in ["delivery_man", "thug", "granny", "officer", "hooker", "streamer"]:
		for eid in ScheduleData.customer_episode_ids(cid):
			scenes += 1
			scene_problems.append_array(News.scene_problems(ScheduleData.episode_data(cid, eid)))
			c.check("%s：場面は must_info を持たない（客の場面は補強。担保の根拠にしない）" % eid,
				ScheduleData.episode_must_info(cid, eid).is_empty())
	c.check("実データ21場面：未知の must_info は無い", scenes == 21 and scene_problems.is_empty(), str(scene_problems))
	c.check("場面の must_info がカタログにある id なら通る", News.scene_problems({ "must_info": ["night_removal"] }).is_empty())
	c.check("場面の must_info が未知の id なら弾く", not News.scene_problems({ "must_info": ["no_such_info"] }).is_empty())
	c.check("場面に must_info が無ければ問題なし", News.scene_problems({}).is_empty())

	News.clear_cache()
	return c.finish()
