extends RefCounted
## 日別ニュースと必須情報の担保（システム整理D-①。DESIGN.md 10.5.5。SEVEN_DAY_OUTLINE.md §11）の検証。
## data/news/week7.json の形、必須情報9項目のカタログ、すべての項目が「ニュースまたは共通イベント」
## （客・モブ・評判に依存しない経路）で、概要表の日に届くこと、場面データの must_info が未知の
## 識別子を使えないこと、仮データの印（provisional）。

# 必須情報の id → 届く日。中身Z：1〜2日目は SEVEN_DAY_OUTLINE.md §11 のまま、3〜7日目は改訂版の筋で組み直した9項目。データがこの表から外れたら落とす。
const EXPECTED_DAYS := {
	"strike_started": 1, "checkpoints": 2, "new_window_cargo": 3, "old_warehouse_load": 4,
	"contract_shift": 5, "warehouse_fire": 6, "police_wiring_probe": 7, "window_changed_before_fire": 7,
	"truth_unresolved": 7,
}
# 共通イベントで届ける項目（朝のニュースではない）。6日目の火災（夜半の共通イベント d6_fire）。
const EVENT_ONLY := ["warehouse_fire"]


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
	c.check("共通イベントで届ける項目は warehouse_fire だけ（他は朝のニュース。中身Z：6日目の「衝突」の共通イベントは印を外した）", Array(event_ids).filter(
		func(id): return not EVENT_ONLY.has(id)).is_empty() and event_ids.has("warehouse_fire"))
	var day7_unresolved := false
	for item in News.day_entry(7)["news"]:
		day7_unresolved = day7_unresolved or (item["must_info"] as Array).has("truth_unresolved")
	c.check("#9 真相は確定しない：Day7のニュースに truth_unresolved の印がある", day7_unresolved)
	var truth_item: Dictionary = {}
	for item in News.day_entry(7)["news"]:
		if (item["must_info"] as Array).has("truth_unresolved"):
			truth_item = item
	c.check("#9：複数の説を並べる（本文が3行以上）", (truth_item.get("body", []) as Array).size() >= 3)

	# --- 3. 仮データの印：Day7 の全項目に provisional が付いている（脚本で差し替える）。Day1〜6 は本番の文（中身U1・中身X・中身Z・中身AA・中身AB・中身AD）で付かない ---
	var all_provisional := true
	var any_items := 0
	for day in range(7, 8):
		var entry := News.day_entry(day)
		for kind in ["news", "events"]:
			for item in entry[kind]:
				any_items += 1
				all_provisional = all_provisional and bool(item.get("provisional", false))
	c.check("Day7 の全項目に provisional が付いている（%d件）" % any_items, all_provisional and any_items > 0)
	var day4_news: Array = News.day_entry(4)["news"]
	c.check("Day4 は本番の4本（4日目_ニュース.md。中身AA）：provisional なし・1本目は旧倉庫の見出しで must_info（old_warehouse_load。5段落）・ほかは4段落で必須情報なし・仮の d4_video は無い",
		day4_news.size() == 4 and day4_news.all(func(i): return not bool(i.get("provisional", false)))
			and str(day4_news[0]["headline"]) == "【港湾】旧倉庫への夜間搬入増える　第八码頭の作業停止続く"
			and day4_news[0]["must_info"] == ["old_warehouse_load"] and (day4_news[0]["body"] as Array).size() == 5
			and day4_news.slice(1).all(func(i): return (i["must_info"] as Array).is_empty() and (i["body"] as Array).size() == 4)
			and not day4_news.any(func(i): return str(i["id"]) == "d4_video"),
		str(day4_news.map(func(i): return i["headline"])))
	var day3_news: Array = News.day_entry(3)["news"]
	c.check("Day3 は本番の4本（3日目_ニュース.md。中身Z）：provisional なし・1本目は迂回便の見出しで must_info（new_window_cargo）・ほかは必須情報なし・共通イベントなし",
		day3_news.size() == 4 and day3_news.all(func(i): return not bool(i.get("provisional", false)))
			and str(day3_news[0]["headline"]) == "【港湾】第八码頭の作業停止続く　迂回便、複数の窓口で受付"
			and day3_news[0]["must_info"] == ["new_window_cargo"] and (day3_news[0]["body"] as Array).size() == 4
			and day3_news.slice(1).all(func(i): return (i["must_info"] as Array).is_empty())
			and (News.day_entry(3)["events"] as Array).is_empty(),
		str(day3_news.map(func(i): return i["headline"])))
	var day2_news: Array = News.day_entry(2)["news"]
	c.check("Day2 は本番の4本（2日目_ニュース.md。中身X）：provisional なし・1本目は検問の見出しで must_info ②（checkpoints）・ほかは必須情報なし",
		day2_news.size() == 4 and day2_news.all(func(i): return not bool(i.get("provisional", false)))
			and str(day2_news[0]["id"]) == "d2_checkpoints" and str(day2_news[0]["headline"]) == "【港湾】第八码頭の周辺で検問始まる　市場への搬入に遅れ"
			and day2_news[0]["must_info"] == ["checkpoints"] and day2_news.slice(1).all(func(i): return (i["must_info"] as Array).is_empty() and (i["body"] as Array).size() == 4)
			and not day2_news.any(func(i): return str(i["headline"]).contains("物別れ")),
		str(day2_news.map(func(i): return i["headline"])))
	var day1_news: Array = News.day_entry(1)["news"]
	c.check("Day1 は本番の4本（1日目_ニュース.md）：provisional なし・1本目はストの見出しで must_info ①（strike_started）",
		day1_news.size() == 4 and day1_news.all(func(i): return not bool(i.get("provisional", false)))
			and str(day1_news[0]["headline"]) == "【港湾】第八码頭、二倉庫で夜間作業停止" and day1_news[0]["must_info"] == ["strike_started"]
			and day1_news.slice(1).all(func(i): return (i["must_info"] as Array).is_empty() and (i["body"] as Array).size() == 4),
		str(day1_news.map(func(i): return i["headline"])))
	c.check("毎日ニュースが1件以上ある（Day1〜7）", range(1, 8).all(func(d): return not News.day_entry(d)["news"].is_empty()))
	c.check("日程の無い日・未来の日は空（Day8）", News.day_entry(8)["news"].is_empty() and News.day_entry(8)["events"].is_empty())

	# --- 4. 担保が崩れるデータは落ちる ---
	var removed := _fresh()
	for item in removed["days"]["5"]["news"]:
		if (item["must_info"] as Array).has("contract_shift"):
			(item["must_info"] as Array).erase("contract_shift")
	c.check("ニュースから項目を外す（客の場面にだけ残る状態）と落ちる：%s" % "contract_shift",
		not News.problems(removed).is_empty() and str(News.problems(removed)).contains("contract_shift"))
	var moved := _fresh()
	moved["days"]["6"]["events"][0]["must_info"] = []
	moved["days"]["6"]["events"][1]["must_info"] = []
	c.check("共通イベントから warehouse_fire を外すと落ちる", str(News.problems(moved)).contains("warehouse_fire"))
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
	c.check("場面の must_info がカタログにある id なら通る", News.scene_problems({ "must_info": ["contract_shift"] }).is_empty())
	# 中身Z：市場の場面（data/talks）の must_info の印（その会話で伝わる必須情報。担保はニュース）もカタログにある id だけ
	var talk_ids := []
	for talk_id in ["day1_market", "day2_market", "day3_market"]:
		for part in ScheduleData.talk_data(talk_id).get("parts", []):
			for id in (part as Dictionary).get("must_info", []):
				talk_ids.append(str(id))
	c.check("市場の場面の must_info の印はカタログにある（3日目の張姐＝new_window_cargo だけ）",
		talk_ids == ["new_window_cargo"] and News.scene_problems({ "must_info": talk_ids }).is_empty(), str(talk_ids))
	c.check("場面の must_info が未知の id なら弾く", not News.scene_problems({ "must_info": ["no_such_info"] }).is_empty())
	c.check("場面に must_info が無ければ問題なし", News.scene_problems({}).is_empty())

	News.clear_cache()
	return c.finish()
