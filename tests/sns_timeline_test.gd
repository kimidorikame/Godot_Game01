extends RefCounted
## スマホのSNS（UI準備R・試しの実装）：タブは SNS／ニュース／持ち物（客タブは画面に出さない）。SNSタブはタイムライン（最初に開く）と DM（相手ごと）。
## タイムラインのデータ（data/sns/week7.json）の検査・見える時刻（UI準備R2：前の日までは全部。今日の分はゲームの中の時刻まで＝
## 朝 09:59／市場・準備 17:59／宵の口 21:59／夜半 翌00:59／明け方・閉店のあと 翌04:59）・met（その客の初来店の日の閉店のあとから）・並び（新しい日が上・同じ日は新しい時刻が上・夜中はその日の24時以降・返信は元の投稿の下に古い順）・
## 未読の●（SNSタブとスマホのボタン。タイムラインを開くと消える）・DMの一覧／やりとり／戻る／相手ごとの未読・連絡先のカード・朝の保存から戻したとき。
## 中身U1：本番のタイムラインは1日目の分（1日目_タイムライン.md。アカウント7・投稿8）だけになったので、日をまたぐ並び・見える時刻の仕組みは、
## 前の試しのデータ（夜歩きカメラなど21件）を写した tests/fixtures/sns/week7.json で確かめる（Sns.data_dir を差し替え、最後に戻す）。
## 本番のデータは、最初の 0. で検査する。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _names(content: Node, prefix: String) -> Array:
	var out := []
	for child in content.get_children():
		if str(child.name).begins_with(prefix):
			out.append(str(child.name).trim_prefix(prefix))
	return out


func _texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_texts(child, out)
	return out


func _post_ids(sections: Array) -> Array:
	var out := []
	for section in sections:
		for item in section["posts"]:
			out.append(str(item["id"]))
			for reply in item["replies"]:
				out.append("  " + str(reply["id"]))
	return out


## 英語を3文字ずらす（A→D。リンの裏アカの暗号）。
func _shift3(plain: String) -> String:
	var out := ""
	for ch in plain:
		out += String.chr((ch.unicode_at(0) - 65 + 3) % 26 + 65) if ch >= "A" and ch <= "Z" else ch
	return out


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Sns.clear_cache()

	# --- 0. 本番のデータ（中身U3：1日目_タイムライン.md の23件版） ---
	c.check("本番のタイムラインに問題がない", Sns.problems().is_empty(), str(Sns.problems()))
	c.check("本番：アカウント32（1日目21＋2日目7＋3日目4。4・5日目は新しいアカウント無し）・投稿121（Day1 23・Day2 26・Day3 24・Day4 24・Day5 24。中身X・中身Z・中身AA・中身AB）。6日目以降の投稿はまだ無い", Sns.accounts().size() == 32 and Sns.posts().size() == 121
		and Sns.posts().filter(func(x): return int(x["day"]) == 1).size() == 23 and Sns.posts().filter(func(x): return int(x["day"]) == 2).size() == 26
		and Sns.posts().filter(func(x): return int(x["day"]) == 3).size() == 24 and Sns.posts().filter(func(x): return int(x["day"]) == 4).size() == 24
		and Sns.posts().filter(func(x): return int(x["day"]) == 5).size() == 24 and not Sns.posts().any(func(x): return int(x["day"]) >= 6),
		"%d / %d" % [Sns.accounts().size(), Sns.posts().size()])
	var used := {}
	for x in Sns.posts():
		used[str(x["account"])] = true
	c.check("本番：どのアカウントも投稿に使われている", Sns.accounts().keys().all(func(a): return used.has(a)))
	var real_owner := func(id: String) -> String: return str(Sns.accounts()[id]["owner"])
	c.check("本番：持ち主（書き手用）は阿強＝delivery_man・港の二人＝dock_workers・受付＝inn_clerk・裏アカ＝officer・ニカ＝streamer・セティヤ＝hooker・ほかは town",
		real_owner.call("akiang") == "delivery_man" and real_owner.call("dock_a") == "dock_workers" and real_owner.call("dock_b") == "dock_workers"
			and real_owner.call("desk") == "inn_clerk" and real_owner.call("lin_alt") == "officer" and str(Sns.accounts()["lin_alt"]["kind"]) == "alt"
			and real_owner.call("exposure_test") == "streamer" and real_owner.call("setiya") == "hooker"
			and real_owner.call("shiwei") == "town" and real_owner.call("ayu") == "town" and real_owner.call("east_news") == "town")
	c.check("本番：東塔NEWS は id east_news・ID @easttower_news・表（main）", str(Sns.accounts()["east_news"]["handle"]) == "@easttower_news"
		and str(Sns.accounts()["east_news"]["kind"]) == "main" and str(Sns.accounts()["east_news"]["name"]) == "東塔NEWS")
	var real_by_id := {}
	for x in Sns.posts():
		real_by_id[str(x["id"])] = x
	c.check("本番：返信は3件（17:35→17:20 の K4172、21:52→21:40 の荷役、2日目 17:35→17:10 の継ぎ目）・写真は7件（3日目・4日目に2件ずつ）・裏アカの原文と意味は truth に",
		str(real_by_id["d1_passer1_1735"]["reply_to"]) == "d1_akiang_1720" and str(real_by_id["d1_dock_a_2152"]["reply_to"]) == "d1_dock_b_2140"
			and str(real_by_id["d2_passer1_1735"]["reply_to"]) == "d2_rex_1710"
			and Sns.posts().filter(func(x): return x.has("reply_to")).size() == 3
			and Sns.posts().filter(func(x): return x.has("photo")).size() == 7
			and str(real_by_id["d1_lin_alt_2350"]["truth"]).contains("ARRIVED. DUTY STARTS TOMORROW.")
			and not str(real_by_id["d1_lin_alt_2350"]["truth"]).contains("スパイはいない"))
	# --- 0b. 2日目（中身X：2日目_タイムライン.md の26件）の確かめ a〜e ---
	var day2 := Sns.posts().filter(func(x): return int(x["day"]) == 2)
	var new_accounts := ["rex", "one_box", "cold_noodle", "laundry_3", "sou_jobhunt", "south_blocks", "lisa_walks"]
	c.check("2日目 a：新しいアカウント7つがあり、投稿のアカウントはどれもある・投稿の id は重ならない",
		new_accounts.all(func(a): return Sns.accounts().has(a)) and day2.all(func(x): return Sns.accounts().has(str(x["account"])))
			and real_by_id.size() == Sns.posts().size())
	var replies_ok := true
	for x in day2.filter(func(p): return p.has("reply_to")):
		var parent_id := str(x["reply_to"])
		replies_ok = replies_ok and real_by_id.has(parent_id) and Sns.order_value(2, str(x["time"])) \
			> Sns.order_value(int(real_by_id[parent_id]["day"]), str(real_by_id[parent_id]["time"]))
	c.check("2日目 b：返信先があり、返信先の時刻が前（17:35 の通行人 → 17:10 の継ぎ目）", replies_ok)
	c.check("2日目 c：時刻は HH:MM（23:59 まで）", day2.all(func(x): return Sns.minutes(str(x["time"])) >= 0 and str(x["time"]).length() == 5))
	var pairs := {}
	for x in day2:
		pairs["%s %s" % [x["time"], x["account"]]] = true
	c.check("2日目 d：同じ時刻・同じアカウントの投稿は重ならない", pairs.size() == day2.size())
	var count_in := func(lo: int, hi: int) -> int: return day2.filter(func(x): return Sns.day_minutes(str(x["time"])) >= lo and Sns.day_minutes(str(x["time"])) <= hi).size()
	c.check("2日目 e：件数 朝4／市場・準備11／宵の口5／夜半6／明け方0／合計26",
		count_in.call(0, Sns.LIMIT_MORNING) == 4 and count_in.call(Sns.LIMIT_MORNING + 1, Sns.LIMIT_MARKET) == 11
			and count_in.call(Sns.LIMIT_MARKET + 1, Sns.LIMIT_EVENING) == 5 and count_in.call(Sns.LIMIT_EVENING + 1, Sns.LIMIT_MIDNIGHT) == 6
			and count_in.call(Sns.LIMIT_MIDNIGHT + 1, Sns.LIMIT_DAY_END) == 0 and day2.size() == 26)
	var lin2 := day2.filter(func(x): return str(x["account"]) == "lin_alt")
	c.check("2日目：リンの裏アカ「・」は3件（14:10・23:10・23:40）。暗号文はそのまま・truth に原文と意味・報告か記録か",
		lin2.map(func(x): return str(x["time"])) == ["14:10", "23:10", "23:40"]
			and str(lin2[0]["text"]) == "ORFDO VRXUFH: WKUHH PDUNHW HQWUDQFHV. RQOB RQH PDUNHG. UHDU URXWH YHULILHG."
			and str(lin2[0]["truth"]).contains("LOCAL SOURCE: THREE MARKET ENTRANCES.") and str(lin2[0]["truth"]).contains("誰かへの報告")
			and str(lin2[1]["truth"]).contains("CONTACT MADE WITH NIGHT STALL OWNER.") and str(lin2[1]["truth"]).contains("誰かへの報告")
			and str(lin2[2]["truth"]).contains("FIRST DAY. LOST ONCE. FOUND SOUP.") and str(lin2[2]["truth"]).contains("自分用の記録"))
	c.check("2日目：リンの 14:10 は、昼の市場で新人警官の会話が済むまで見えない（市場・準備のあいだ。済んだら・開店のあと・次の日は見える）",
		not Sns.is_visible(lin2[0], 2, Sns.LIMIT_MARKET) and Sns.is_visible(lin2[0], 2, Sns.LIMIT_MARKET, ["officer"])
			and not Sns.is_visible(lin2[0], 2, Sns.LIMIT_MARKET, ["thug"])
			and Sns.is_visible(lin2[0], 2, Sns.LIMIT_EVENING) and Sns.is_visible(lin2[0], 3, Sns.LIMIT_MORNING))
	c.check("2日目：リンの 23:10・23:40 は宵の口（リンの接客の時間帯）には見えず、夜半から見える（時刻の決まりだけ）",
		lin2.slice(1).all(func(x): return not Sns.is_visible(x, 2, Sns.LIMIT_EVENING) and Sns.is_visible(x, 2, Sns.LIMIT_MIDNIGHT) and not x.has("requires")))
	# --- 0c. 3日目（中身Z：3日目_タイムライン.md の24件）の確かめ a〜e ---
	var day3 := Sns.posts().filter(func(x): return int(x["day"]) == 3)
	var new3 := ["min", "hao_gifts", "back_shelf", "second_floor"]
	c.check("3日目 a：新しいアカウント4つ（粉まみれ @flour_daily・贈り物覚え書き @hao_gifts・棚の奥 @back_shelf・二階の住人 @second_floor）があり、投稿のアカウントはどれもある・投稿の id は重ならない",
		new3.all(func(a): return Sns.accounts().has(a)) and day3.all(func(x): return Sns.accounts().has(str(x["account"])))
			and str(Sns.accounts()["min"]["handle"]) == "@flour_daily" and str(Sns.accounts()["hao_gifts"]["handle"]) == "@hao_gifts"
			and str(Sns.accounts()["back_shelf"]["handle"]) == "@back_shelf" and str(Sns.accounts()["second_floor"]["handle"]) == "@second_floor"
			and real_owner.call("back_shelf") == "general_store_clerk" and real_owner.call("min") == "town"
			and real_by_id.size() == Sns.posts().size())
	c.check("3日目 b：返信は無い（元の文の返信先はすべて —）", not day3.any(func(x): return x.has("reply_to")))
	c.check("3日目 c：時刻は HH:MM（23:59 まで）", day3.all(func(x): return Sns.minutes(str(x["time"])) >= 0 and str(x["time"]).length() == 5))
	var pairs3 := {}
	for x in day3:
		pairs3["%s %s" % [x["time"], x["account"]]] = true
	c.check("3日目 d：同じ時刻・同じアカウントの投稿は重ならない", pairs3.size() == day3.size())
	var count3 := func(lo: int, hi: int) -> int: return day3.filter(func(x): return Sns.day_minutes(str(x["time"])) >= lo and Sns.day_minutes(str(x["time"])) <= hi).size()
	c.check("3日目 e：件数 朝5／市場・準備10／宵の口5／夜半4／明け方0／合計24",
		count3.call(0, Sns.LIMIT_MORNING) == 5 and count3.call(Sns.LIMIT_MORNING + 1, Sns.LIMIT_MARKET) == 10
			and count3.call(Sns.LIMIT_MARKET + 1, Sns.LIMIT_EVENING) == 5 and count3.call(Sns.LIMIT_EVENING + 1, Sns.LIMIT_MIDNIGHT) == 4
			and count3.call(Sns.LIMIT_MIDNIGHT + 1, Sns.LIMIT_DAY_END) == 0 and day3.size() == 24)
	var lin3 := day3.filter(func(x): return str(x["account"]) == "lin_alt")
	c.check("3日目：リンの裏アカ「・」は2件（15:00・23:35）。暗号文は原文を3文字ずらしたもの・truth は「誰かへの報告」で、報告先・組織の名前は書かない・条件は無い",
		lin3.map(func(x): return str(x["time"])) == ["15:00", "23:35"]
			and str(lin3[0]["text"]) == _shift3("NEW NAME ON OLD WAREHOUSE CARGO. PASSED WITHOUT STOP. AS INSTRUCTED.")
			and str(lin3[1]["text"]) == _shift3("REAR MARKET ROUTE STILL OPEN. NO CONTACT WITH STALL OWNER TODAY.")
			and lin3.all(func(x): return str(x["truth"]).contains("誰かへの報告") and not str(x["truth"]).contains("組織）") and not str(x["truth"]).contains("新興") and not x.has("requires")))
	var nika23 := day3.filter(func(x): return str(x["account"]) == "exposure_test" and str(x["time"]) == "23:00")
	c.check("3日目：ニカの 23:00 だけ requires.visited（streamer）。ほかの3日目の投稿に条件は無い",
		nika23.size() == 1 and nika23[0]["requires"] == { "visited": "streamer" } and day3.filter(func(x): return x.has("requires")).size() == 1)
	c.check("3日目：ニカの 23:00 は夜半に入っても、ニカの接客が済むまで見えない（済んだら・次の日は見える）",
		not Sns.is_visible(nika23[0], 3, Sns.LIMIT_MIDNIGHT) and not Sns.is_visible(nika23[0], 3, Sns.LIMIT_MIDNIGHT, [], ["delivery_man"])
			and Sns.is_visible(nika23[0], 3, Sns.LIMIT_MIDNIGHT, [], ["delivery_man", "streamer"])
			and not Sns.is_visible(nika23[0], 3, Sns.LIMIT_EVENING, [], ["streamer"])
			and Sns.is_visible(nika23[0], 4, Sns.LIMIT_MORNING))
	c.check("本番：Day3 の見える件数：朝54・市場・準備64・宵の口69・夜半（ニカの前）72・ニカのあと73・Day4 の朝に Day3 までの73件＋Day4 の朝の5件（累計）",
		Sns.visible_ids(3, Sns.LIMIT_MORNING).size() == 54 and Sns.visible_ids(3, Sns.LIMIT_MARKET).size() == 64
			and Sns.visible_ids(3, Sns.LIMIT_EVENING).size() == 69 and Sns.visible_ids(3, Sns.LIMIT_MIDNIGHT).size() == 72
			and Sns.visible_ids(3, Sns.LIMIT_MIDNIGHT, {}, [], ["streamer"]).size() == 73 and Sns.visible_ids(4, Sns.LIMIT_MORNING).size() == 78,
		"%d / %d / %d / %d" % [Sns.visible_ids(3, Sns.LIMIT_MORNING).size(), Sns.visible_ids(3, Sns.LIMIT_MARKET).size(),
			Sns.visible_ids(3, Sns.LIMIT_EVENING).size(), Sns.visible_ids(3, Sns.LIMIT_MIDNIGHT).size()])
	# --- 0d. 4日目（中身AA：4日目_タイムライン.md の24件）の確かめ a〜e ---
	var day4 := Sns.posts().filter(func(x): return int(x["day"]) == 4)
	c.check("4日目 a：新しいアカウントは無く、投稿のアカウントはどれもある（1〜3日目のアカウントだけ）・投稿の id は重ならない",
		Sns.accounts().size() == 32 and day4.all(func(x): return Sns.accounts().has(str(x["account"]))) and real_by_id.size() == Sns.posts().size())
	c.check("4日目 b：返信は無い（元の文の返信先はすべて —）", not day4.any(func(x): return x.has("reply_to")))
	c.check("4日目 c：時刻は HH:MM（23:59 まで）", day4.all(func(x): return Sns.minutes(str(x["time"])) >= 0 and str(x["time"]).length() == 5))
	var pairs4 := {}
	for x in day4:
		pairs4["%s %s" % [x["time"], x["account"]]] = true
	c.check("4日目 d：同じ時刻・同じアカウントの投稿は重ならない", pairs4.size() == day4.size())
	var count4 := func(lo: int, hi: int) -> int: return day4.filter(func(x): return Sns.day_minutes(str(x["time"])) >= lo and Sns.day_minutes(str(x["time"])) <= hi).size()
	c.check("4日目 e：件数 朝5／市場・準備9／宵の口6／夜半4／明け方0／合計24",
		count4.call(0, Sns.LIMIT_MORNING) == 5 and count4.call(Sns.LIMIT_MORNING + 1, Sns.LIMIT_MARKET) == 9
			and count4.call(Sns.LIMIT_MARKET + 1, Sns.LIMIT_EVENING) == 6 and count4.call(Sns.LIMIT_EVENING + 1, Sns.LIMIT_MIDNIGHT) == 4
			and count4.call(Sns.LIMIT_MIDNIGHT + 1, Sns.LIMIT_DAY_END) == 0 and day4.size() == 24)
	var lin4 := day4.filter(func(x): return str(x["account"]) == "lin_alt")
	c.check("4日目：リンの「・」は2件（15:00・21:25）。暗号文は原文を3文字ずらしたもの・truth は「誰かへの報告」で、報告先・組織の名前は書かない。21:25 だけ requires.visited（officer）",
		lin4.map(func(x): return str(x["time"])) == ["15:00", "21:25"]
			and str(lin4[0]["text"]) == _shift3("NEW NAME CLEARED AGAIN. AS INSTRUCTED. OLD WAREHOUSE QUEUE GROWING.")
			and str(lin4[1]["text"]) == _shift3("CONTACT WITH STALL OWNER COMPLETE. REAR ROUTE OPEN ON FOOT. VEHICLE ACCESS UNCONFIRMED. HILLTOP LOT LIT. NO PATROL ASSIGNED.")
			and lin4.all(func(x): return str(x["truth"]).contains("誰かへの報告") and not str(x["truth"]).contains("新興"))
			and not lin4[0].has("requires") and lin4[1]["requires"] == { "visited": "officer" }
			and day4.filter(func(x): return x.has("requires")).size() == 1)
	c.check("4日目：リンの 21:25 は宵の口でも、リンの接客が済むまで見えない（済んだら・次の日は見える）",
		not Sns.is_visible(lin4[1], 4, Sns.LIMIT_EVENING) and Sns.is_visible(lin4[1], 4, Sns.LIMIT_EVENING, [], ["officer"])
			and Sns.is_visible(lin4[1], 5, Sns.LIMIT_MORNING))
	c.check("4日目：写真の欄はニカの 23:00 が動画（photo_kind video）・阿強の 23:35 が写真",
		day4.filter(func(x): return x.has("photo")).map(func(x): return "%s %s" % [x["time"], str(x.get("photo_kind", "photo"))]) == ["23:00 video", "23:35 photo"])
	# --- 0e. 5日目（中身AB：5日目_タイムライン.md の24件）の確かめ a〜e ---
	var day5 := Sns.posts().filter(func(x): return int(x["day"]) == 5)
	c.check("5日目 a：新しいアカウントは無く、投稿のアカウントはどれもある（1〜3日目のアカウントだけ）・投稿の id は重ならない",
		Sns.accounts().size() == 32 and day5.all(func(x): return Sns.accounts().has(str(x["account"]))) and real_by_id.size() == Sns.posts().size())
	c.check("5日目 b：返信は無い（元の文の返信先はすべて —）・写真も無い（写真の欄はすべて —）",
		not day5.any(func(x): return x.has("reply_to")) and not day5.any(func(x): return x.has("photo")))
	c.check("5日目 c：時刻は HH:MM（23:59 まで）", day5.all(func(x): return Sns.minutes(str(x["time"])) >= 0 and str(x["time"]).length() == 5))
	var pairs5 := {}
	for x in day5:
		pairs5["%s %s" % [x["time"], x["account"]]] = true
	c.check("5日目 d：同じ時刻・同じアカウントの投稿は重ならない", pairs5.size() == day5.size())
	var count5 := func(lo: int, hi: int) -> int: return day5.filter(func(x): return Sns.day_minutes(str(x["time"])) >= lo and Sns.day_minutes(str(x["time"])) <= hi).size()
	c.check("5日目 e：件数 朝5／市場・準備9／宵の口6／夜半4／明け方0／合計24",
		count5.call(0, Sns.LIMIT_MORNING) == 5 and count5.call(Sns.LIMIT_MORNING + 1, Sns.LIMIT_MARKET) == 9
			and count5.call(Sns.LIMIT_MARKET + 1, Sns.LIMIT_EVENING) == 6 and count5.call(Sns.LIMIT_EVENING + 1, Sns.LIMIT_MIDNIGHT) == 4
			and count5.call(Sns.LIMIT_MIDNIGHT + 1, Sns.LIMIT_DAY_END) == 0 and day5.size() == 24)
	var lin5 := day5.filter(func(x): return str(x["account"]) == "lin_alt")
	c.check("5日目：リンの「・」は2件（15:00・23:35）。暗号文は原文を3文字ずらしたもの・truth は「誰かへの報告」で、報告先・組織の名前は書かない。5日目の投稿に条件は無い",
		lin5.map(func(x): return str(x["time"])) == ["15:00", "23:35"]
			and str(lin5[0]["text"]) == _shift3("NEW NAME CARGO NOT HELD. AS INSTRUCTED. TOMORROW NIGHT PATROL: OLD WAREHOUSE SIDE DROPPED. NO REASON GIVEN.")
			and str(lin5[1]["text"]) == _shift3("MARKET REAR ROUTE CHECK IN PROGRESS. STALL CONTACT TO CONTINUE.")
			and lin5.all(func(x): return str(x["truth"]).contains("誰かへの報告") and not str(x["truth"]).contains("新興"))
			and not day5.any(func(x): return x.has("requires")))
	c.check("5日目：リンの 23:35 は夜半に見える（明け方のリンの接客より前でよい。時刻の決まりだけ）",
		not Sns.is_visible(lin5[1], 5, Sns.LIMIT_EVENING) and Sns.is_visible(lin5[1], 5, Sns.LIMIT_MIDNIGHT))
	var broken_visit: Dictionary = (Sns.data() as Dictionary).duplicate(true)
	(broken_visit["posts"] as Array)[0]["requires"] = { "visited": "no_such_customer" }
	c.check("requires.visited の客が無いと落ちる", not Sns.problems(broken_visit).is_empty())
	GameState.reset_for_new_game()
	c.check("本番：見える時刻で数える件数：朝（〜09:59）5件・準備まで（〜17:59）16件・宵の口まで20件・夜半まで23件・閉店のあと23件",
		Sns.visible_ids(1, Sns.LIMIT_MORNING).size() == 5 and Sns.visible_ids(1, Sns.LIMIT_MARKET).size() == 16
			and Sns.visible_ids(1, Sns.LIMIT_EVENING).size() == 20 and Sns.visible_ids(1, Sns.LIMIT_MIDNIGHT).size() == 23
			and Sns.visible_ids(1, Sns.LIMIT_DAY_END).size() == 23,
		"%d / %d / %d / %d" % [Sns.visible_ids(1, Sns.LIMIT_MORNING).size(), Sns.visible_ids(1, Sns.LIMIT_MARKET).size(),
			Sns.visible_ids(1, Sns.LIMIT_EVENING).size(), Sns.visible_ids(1, Sns.LIMIT_MIDNIGHT).size()])
	c.check("本番：Day2 の朝に Day1 の全23件＋Day2 の朝の4件が見える", Sns.visible_ids(2, Sns.LIMIT_MORNING).size() == 27, str(Sns.visible_ids(2, Sns.LIMIT_MORNING).size()))
	c.check("本番：Day2 の市場・準備（会話の前）37件・会話のあと38件・宵の口43件・夜半49件・Day3 の朝に全49件（累計）",
		Sns.visible_ids(2, Sns.LIMIT_MARKET).size() == 37 and Sns.visible_ids(2, Sns.LIMIT_MARKET, {}, ["officer"]).size() == 38
			and Sns.visible_ids(2, Sns.LIMIT_EVENING).size() == 43 and Sns.visible_ids(2, Sns.LIMIT_MIDNIGHT).size() == 49
			and Sns.visible_ids(3, Sns.LIMIT_MORNING).size() == 54,
		"%d / %d / %d / %d" % [Sns.visible_ids(2, Sns.LIMIT_MARKET).size(), Sns.visible_ids(2, Sns.LIMIT_MARKET, {}, ["officer"]).size(),
			Sns.visible_ids(2, Sns.LIMIT_EVENING).size(), Sns.visible_ids(2, Sns.LIMIT_MIDNIGHT).size()])

	# ここから下は、仕組みの検査に前の試しのデータ（fixture）を使う
	var data_dir_saved := Sns.data_dir
	Sns.data_dir = "res://tests/fixtures/sns/"
	Sns.clear_cache()

	# --- 1. データの検査 ---
	c.check("タイムラインのデータ（試しの fixture）に問題がない", Sns.problems().is_empty(), str(Sns.problems()))
	c.check("アカウントは5件・投稿は21件（試しの fixture）", Sns.accounts().size() == 5 and Sns.posts().size() == 21, "%d / %d" % [Sns.accounts().size(), Sns.posts().size()])
	var base: Dictionary = Sns.data().duplicate(true)
	var bad: Dictionary = base.duplicate(true)
	(bad["posts"] as Array).append({ "id": "x1", "account": "nobody", "day": 2, "time": "10:00", "text": "あ" })
	(bad["posts"] as Array).append({ "id": "x2", "account": "dock", "day": 3, "time": "18:00", "text": "早すぎる返信", "reply_to": "d3_yoru_rain" })
	(bad["posts"] as Array).append({ "id": "x3", "account": "dock", "day": 3, "time": "20:00", "text": "あ", "reply_to": "no_such_post" })
	(bad["posts"] as Array).append({ "id": "x4", "account": "dock", "day": 3, "time": "20:00", "text": "" })
	(bad["posts"] as Array).append({ "id": "x5", "account": "dock", "day": 3, "time": "20:00", "text": "HOT が好き" })
	(bad["posts"] as Array).append({ "id": "x1", "account": "dock", "day": 3, "time": "20:00", "text": "9時に3人" })
	bad["accounts"]["dup"] = { "name": "重複", "handle": "@dock_hands", "icon": { "color": "#123456", "text": "重" }, "kind": "main", "owner": "town", "profile": "" }
	var p := Sns.problems(bad)
	c.check("検査：無いアカウント・返信先が無い・返信が元より前の時刻・本文が空・英字の札・id の重複・ID（@〜）の重複を弾く",
		p.any(func(x): return str(x).contains("nobody")) and p.any(func(x): return str(x).contains("no_such_post"))
			and p.any(func(x): return str(x).contains("x2") and str(x).contains("前の時刻")) and p.any(func(x): return str(x).contains("x4") and str(x).contains("空"))
			and p.any(func(x): return str(x).contains("HOT")) and p.any(func(x): return str(x).contains("x1") and str(x).contains("重複"))
			and p.any(func(x): return str(x).contains("@dock_hands")), str(p))
	c.check("検査：数字は使ってよい", not p.any(func(x): return str(x).contains("9時に3人")))

	# --- 2. 見える時刻・met・並び ---
	GameState.reset_for_new_game()
	var morning := { "day": 4, "time": "11:20" }
	var dusk := { "day": 4, "time": "17:50" }
	var evening := { "day": 2, "time": "19:30" }
	var night := { "day": 2, "time": "22:30" }
	var late := { "day": 2, "time": "02:15" }
	c.check("朝（09:59 まで）には、その日の 11:20・17:50 は見えない（未来の投稿）。市場・準備（17:59 まで）では見える",
		not Sns.is_visible(morning, 4, Sns.LIMIT_MORNING) and not Sns.is_visible(dusk, 4, Sns.LIMIT_MORNING)
			and Sns.is_visible(morning, 4, Sns.LIMIT_MARKET) and Sns.is_visible(dusk, 4, Sns.LIMIT_MARKET))
	c.check("宵の口（21:59 まで）：19:30 は見え、22:30 は見えない。夜半（翌00:59 まで）で 22:30 も見える",
		Sns.is_visible(evening, 2, Sns.LIMIT_EVENING) and not Sns.is_visible(night, 2, Sns.LIMIT_EVENING) and Sns.is_visible(night, 2, Sns.LIMIT_MIDNIGHT))
	c.check("夜中（02:15）はその日の24時以降：夜半には見えず、明け方・閉店のあと（翌04:59 まで）で見える",
		not Sns.is_visible(late, 2, Sns.LIMIT_MIDNIGHT) and Sns.is_visible(late, 2, Sns.LIMIT_DAY_END))
	c.check("前の日までの投稿は全部見える（翌日の朝なら 22:30・02:15 も）・その日より先は見えない",
		Sns.is_visible(night, 3, Sns.LIMIT_MORNING) and Sns.is_visible(late, 3, Sns.LIMIT_MORNING) and not Sns.is_visible(morning, 3, Sns.LIMIT_DAY_END))
	var met := { "day": 4, "time": "22:30", "requires": { "met": "streamer" } }
	c.check("met：会っていない客の条件の投稿は見えない", not Sns.is_visible(met, 6, Sns.LIMIT_MORNING))
	var day := GameState.day_count
	GameState.day_count = 4
	CustomerMemory.arrive("streamer", "宵の口", "streamer_01")
	GameState.day_count = day
	c.check("met：その客の初来店の日（Day4）の閉店のあとから（Day4 の夜半には見えず、閉店のあと・翌朝に見える）",
		not Sns.is_visible(met, 4, Sns.LIMIT_MIDNIGHT) and Sns.is_visible(met, 4, Sns.LIMIT_DAY_END) and Sns.is_visible(met, 5, Sns.LIMIT_MORNING))
	var ids := _post_ids(Sns.timeline(7, Sns.LIMIT_MARKET))
	c.check("並び（Day7 の市場）：新しい日が上・同じ日は新しい時刻が上・夜中は24時以降・返信は元の投稿のすぐ下に古い順。Day7 の夜の投稿はまだ見えない",
		ids.find("d7_yoru_apology") == 0 and ids.find("  d7_passer1_reply") == 1 and ids.find("  d7_passer2_reply") == 2
			and not ids.has("d7_yoru_tonight") and not ids.has("d7_noise_retract")
			and ids.find("d6_noise_deleted") < ids.find("d6_yoru_fire") and ids.find("d6_yoru_fire") + 1 == ids.find("  d6_passer2_reply")
			and ids.find("d5_yoru_stopped") < ids.find("d5_yoru_company") and ids.find("d5_yoru_company") < ids.find("d5_noise_shrimp")
			and ids.find("d2_yoru_hungry") < ids.find("d2_yoru_checkpoint") and ids.has("d4_yoru_ate"), str(ids))
	var sections := Sns.timeline(7, Sns.LIMIT_MARKET)
	c.check("日の区切り：Day7 から Day1 まで、新しい日が上", sections.map(func(s): return int(s["day"])) == [7, 6, 5, 4, 3, 2, 1], str(sections.map(func(s): return int(s["day"]))))
	c.check("閉店のあと（最終日の結果画面も）なら Day7 の夜の投稿も見える", _post_ids(Sns.timeline(7, Sns.LIMIT_DAY_END)).has("d7_noise_retract"))
	GameState.reset_for_new_game()

	# --- 3. 画面：タブ・タイムライン・●（Day2 の朝まで遊ぶ） ---
	ReadState.reset("user://test_read_sns.json")
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	while not (GameState.day_count == 2 and GameState.phase == GameState.Phase.WAKE) and guard < 3000:
		guard += 1
		play.step()
	var envelope: Dictionary = MorningSave.capture("")
	var phone: UiPanePhone = root.pane_phone
	var tabs: Control = phone.get_node("%Tabs")
	var tab_texts := []
	for child in tabs.get_children():
		if child is Button:
			tab_texts.append((child as Button).text)
	c.check("タブは3つ（SNS／ニュース／持ち物）・客タブは無い", tab_texts == ["SNS", "ニュース", "持ち物"], str(tab_texts))
	var unread_before := s.timeline_unread_count()
	c.check("Day2 の朝：Day1 の夜の投稿が見えていて、未読（スマホのボタンの数に入る）", unread_before == 1 and s.phone_unread_count() >= unread_before + s.dm_unread_count(), "%d" % unread_before)
	root.open_phone("news")
	var sns_badge := (phone.get_node("%SnsBadge") as Label).text
	c.check("SNSタブの●＝タイムラインの新しい投稿＋未読のDM", sns_badge == "●%d" % (unread_before + s.dm_unread_count()), sns_badge)
	_press(tabs.get_child(0))
	var content: VBoxContainer = phone.get_node("%Content")
	c.check("SNSタブを開くと、いつもタイムライン（上に「タイムライン｜DM」）", phone.sns_mode == "timeline" and content.has_node("SnsSwitch")
		and content.has_node("Post_d1_yoru_strike") and content.has_node("Day_1"), str(_names(content, "")))
	var post: Node = content.get_node("Post_d1_yoru_strike")
	var post_texts := _texts(post)
	c.check("投稿：表示名・ID（@〜）・時刻（Day1 23:10）・本文。持ち主は出さない", post_texts.has("夜歩きカメラ") and post_texts.has("@yoru_cam_09") and post_texts.has("Day1 23:10")
		and not post_texts.any(func(x): return str(x).contains("streamer") or str(x).contains("配信者")), str(post_texts))
	c.check("タイムラインを開いたら●が消える（未読 0）・開いた時点で未読だった投稿には左の線", s.timeline_unread_count() == 0
		and (post.get_node("UnreadBar") as ColorRect).color.a > 0.0)
	c.check("その日より先の投稿は出ない（Day2 の朝は Day1 の分だけ）", _names(content, "Post_") == ["d1_yoru_strike"], str(_names(content, "Post_")))

	# --- 4. DM：相手ごとの一覧・やりとり・戻る・相手ごとの未読・連絡先のカード ---
	var threads := s.dm_threads()
	var keys: Array = threads.map(func(th): return str(th["key"]))
	c.check("DMは相手ごと（阿強＝名前あり客／張姐＝客でない差出人。中身X）", keys.has("customer:delivery_man") and keys.has("npc:張姐"), str(keys))
	var orders: Array = threads.map(func(th): return int(th["last"]["day"]) * 10000 + Sns.minutes(str(th["last"]["time"])))
	var sorted_orders := orders.duplicate()
	sorted_orders.sort()
	sorted_orders.reverse()
	c.check("相手の並び：最後のメッセージが新しい相手が上（DMの朝の時刻〔04:45 など〕はその日の朝として並べる）", orders == sorted_orders, str(orders))
	var dm_total := s.dm_unread_count()
	_press(content.get_node("SnsSwitch/SwitchDm"))
	c.check("「DM」に切り替えると相手の一覧（未読のある相手に●・DMの切り替えに未読の数）", phone.sns_mode == "dm" and content.has_node("DmRow_customer_delivery_man")
		and content.has_node("DmRow_customer_delivery_man/UnreadMark") and (content.get_node("SnsSwitch/DmUnread") as Label).text == "●%d" % dm_total, str(_names(content, "DmRow_")))
	c.check("一覧を見ただけでは読んだ扱いにならない", s.dm_unread_count() == dm_total)
	var dm_thread: Dictionary = threads.filter(func(th): return str(th["key"]) == "customer:delivery_man")[0]
	var npc_unread := int(threads.filter(func(th): return str(th["key"]) == "npc:張姐")[0]["unread"])
	_press(content.get_node("DmRow_customer_delivery_man"))
	var thread_texts := _texts(content)
	c.check("相手を押すとやりとり（吹き出し・日時の区切り）。その相手の未読だけ消える", phone.dm_open == "customer:delivery_man" and content.has_node("DmBack")
		and (dm_thread["messages"] as Array).all(func(m): return thread_texts.has(str(m["text"])) and thread_texts.has(Calendar.stamp(int(m["day"]), str(m["time"]))))
		and s.dm_unread_count() == dm_total - int(dm_thread["unread"]), str(thread_texts))
	var card: Node = content.get_node("ContactCard")
	var card_texts := _texts(card)
	c.check("連絡先のカード（名前あり客）：名前・前回の注文の札（辛い・スタミナ）・来た日（Day1）・好物（知った客だけ）", card_texts.has("阿強") and card_texts.has("辛い")
		and card_texts.has("スタミナ") and card_texts.has("来た日　Day1") and (card_texts.has("好物　" + Ingredients.name_for("tofu")) == GameState.knows_favorite("delivery_man")), str(card_texts))
	_press(content.get_node("DmBack"))
	c.check("「戻る」で相手の一覧・配達員の●は消えている", phone.dm_open == "" and content.has_node("DmRow_customer_delivery_man") and not content.has_node("DmRow_customer_delivery_man/UnreadMark"))
	_press(content.get_node("DmRow_npc_張姐"))
	c.check("客でない相手のカードは名前だけ", _texts(content.get_node("ContactCard")) == ["張姐"], str(_texts(content.get_node("ContactCard"))))
	_press(content.get_node("SnsSwitch/SwitchTimeline"))
	c.check("上の切り替えでタイムラインにも戻れる", phone.sns_mode == "timeline" and content.has_node("Post_d1_yoru_strike"))
	root.close_overlay()

	# --- 5. 朝の保存から戻したとき（既読は保存とは別に持つ。見える投稿はその朝の日で決まる） ---
	MorningSave.apply(envelope)
	c.check("朝の保存から戻す：その朝に見える投稿だけ・一度読んだ投稿とDMは読んだまま（●は戻らない）", s.timeline_unread_count() == 0
		and Sns.visible_ids(GameState.day_count, s.timeline_limit()) == ["d1_yoru_strike"] and s.dm_unread_count() == dm_total - int(dm_thread["unread"]) - npc_unread)

	# --- 6. ゲームの中の時刻で見える投稿が変わる（戻した Day2 の朝から、Day2 を通しで遊ぶ） ---
	var seen := {}
	var phone_in_open := false
	guard = 0
	while GameState.day_count == 2 and guard < 3000:
		guard += 1
		var key := ""
		match GameState.phase:
			GameState.Phase.WAKE:
				key = "朝"
			GameState.Phase.PREP:
				key = "市場・準備"
			GameState.Phase.OPEN:
				key = s.open.current_slot_name() if s.open != null else ""
			GameState.Phase.CLOSE:
				key = "閉店のあと"
		if key != "" and not seen.has(key):
			seen[key] = Sns.visible_ids(2, s.timeline_limit())
		if key == "宵の口" and not phone_in_open:
			phone_in_open = true
			root.open_phone("sns")
			phone_in_open = phone.visible and phone.sns_mode == "timeline" and content.has_node("Post_d2_yoru_checkpoint") and not content.has_node("Post_d2_yoru_hungry")
			c.check("営業中（宵の口）もスマホを開ける・タイムラインは 21:59 までの投稿", phone_in_open, str(_names(content, "Post_")))
			root.close_overlay()
			phone_in_open = true
		play.step()
	var has := func(k: String, id: String) -> bool: return (seen.get(k, []) as Array).has(id)
	c.check("朝・市場・準備：Day2 の夜の投稿（19:30・02:15）はまだ見えない", seen.has("朝") and seen.has("市場・準備")
		and not has.call("朝", "d2_yoru_checkpoint") and not has.call("市場・準備", "d2_yoru_checkpoint") and has.call("市場・準備", "d1_yoru_strike"), str(seen))
	c.check("宵の口：19:30 は見え、02:15 は見えない／夜半：まだ 02:15 は見えない／明け方・閉店のあと：02:15 も見える",
		has.call("宵の口", "d2_yoru_checkpoint") and not has.call("宵の口", "d2_yoru_hungry") and has.call("夜半", "d2_yoru_checkpoint")
			and not has.call("夜半", "d2_yoru_hungry") and has.call("明け方", "d2_yoru_hungry") and has.call("閉店のあと", "d2_yoru_hungry"), str(seen))
	root.queue_free()
	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	Sns.data_dir = data_dir_saved
	Sns.clear_cache()
	return c.finish()
