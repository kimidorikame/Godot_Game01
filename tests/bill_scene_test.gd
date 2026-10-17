extends RefCounted
## 請求（week7.json の bills[]）の scene と市場の解禁日（システム整理A・E 3.2・3.3）の検証。
## 以前は「thug かつ is_collection_day()」でチンピラの場所代のPAYを作り、市場の解禁は
## day_count >= 2 の直書きだった。今は bills[] の scene（取り立てる客のid）・days（今日を含む）から
## PAYを作り、市場は Rules.market_open_from_day() で判定する。現行データでは動作は同一
## （場所代はDay1のチンピラだけ・値は90のまま・Day2から市場が押せる）。
## Rules の読み込み結果（static のキャッシュ）をテストの中で書き換え、最後に読み直して戻す。


func _pays(customer_id: String, day: int) -> Array:
	GameState.reset_for_new_game()
	GameState.day_count = day
	return Day1Events.customer_events(customer_id).filter(func(e): return str(e.get("type", "")) == "PAY")


func _market_enabled(day: int) -> bool:
	GameState.reset_for_new_game()
	GameState.day_count = day
	var options: Array = Day1Events._market_options(false)
	var all_same := true
	for o in options:
		all_same = all_same and bool(o["enabled"]) == bool(options[0]["enabled"])
	return bool(options[0]["enabled"]) and all_same


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	Rules.set_campaign("week7")
	Rules.bills()   # 読み込ませる

	# --- 1. 現行データ：場所代はDay1のチンピラだけ・値は90のまま ---
	c.check("場所代の金額は請求（bills[].amount）から引き、90のまま",
		Rules.bill_amount("rent") == 90 and GameState.RENT_PRICE == 90 and GameState.WATER_PRICE == 50)
	c.check("請求の取り立て先（scene）は場所代＝thug・水道代＝water_stall",
		str(Rules.bill("rent")["scene"]) == "thug" and str(Rules.bill("water")["scene"]) == "water_stall")
	var d1 := _pays("thug", 1)
	c.check("Day1のチンピラ：場所代のPAYが1つ（kind=rent・90・従来の文）",
		d1.size() == 1 and int(d1[0]["amount"]) == 90 and str(d1[0]["kind"]) == "rent"
			and str(d1[0]["customer"]) == "thug" and str(d1[0]["text"]) == "チンピラ（場所代）", str(d1))
	for d in range(2, 8):
		c.check("Day%dのチンピラ：PAYは出ない" % d, _pays("thug", d).is_empty())
	for cid in ["delivery_man", "granny", "officer", "hooker", "streamer"]:
		c.check("%s：Day1でもPAYは出ない（scene が別の客）" % cid, _pays(cid, 1).is_empty())

	# --- 2. daysを差し替える：徴収日にだけ出る（JSONの数値はfloat） ---
	for b in Rules._cache["bills"]:
		if str(b["id"]) == "rent":
			b["days"] = [2.0, 3.0]
	c.check("rentのdaysを[2,3]にするとDay1は出ない", _pays("thug", 1).is_empty())
	c.check("Day2・Day3に出る", _pays("thug", 2).size() == 1 and _pays("thug", 3).size() == 1)
	c.check("Day4には出ない", _pays("thug", 4).is_empty())
	c.check("bills_for_sceneは日とsceneで絞る",
		Rules.bills_for_scene("thug", 3).size() == 1 and Rules.bills_for_scene("thug", 1).is_empty()
			and Rules.bills_for_scene("granny", 3).is_empty())

	# --- 3. sceneが別の客の請求：その客にだけ出る（金額・ラベルは請求のもの） ---
	Rules._cache["bills"].append({ "id": "tab", "amount": 33.0, "days": [2.0], "reserve": "WAKE",
		"scene": "granny", "label": "つけ" })
	var granny_pays := _pays("granny", 2)
	c.check("scene=grannyの請求はDay2の老婆にだけ出る（kind=請求のid・金額・老婆の表示名）",
		granny_pays.size() == 1 and int(granny_pays[0]["amount"]) == 33 and str(granny_pays[0]["kind"]) == "tab"
			and str(granny_pays[0]["text"]) == "老婆（つけ）", str(granny_pays))
	c.check("別の客（チンピラ）の請求には混ざらない（Day2のチンピラのPAYは場所代1つ）",
		_pays("thug", 2).size() == 1 and str(_pays("thug", 2)[0]["kind"]) == "rent")
	c.check("sceneが別の客の請求は、Day3の老婆には出ない", _pays("granny", 3).is_empty())
	Rules._cache["bills"].append({ "id": "lonely", "amount": 10, "days": [1] })
	c.check("sceneの無い請求はどの客にも出ない（クラッシュしない）", _pays("delivery_man", 1).is_empty())
	c.check("請求が無いidは空辞書・金額はfallback",
		Rules.bill("no_such_bill").is_empty() and Rules.bill_amount("no_such_bill", 7) == 7)

	# --- 4. 市場の解禁日（Rules.market_open_from_day()） ---
	Rules.set_campaign("week7")
	Rules.bills()
	c.check("市場の解禁日は2のまま", Rules.market_open_from_day() == 2)
	c.check("Day1は店が押せない・Day2以降は押せる",
		not _market_enabled(1) and _market_enabled(2) and _market_enabled(3) and _market_enabled(7))
	Rules._cache["market_open_from_day"] = 4
	c.check("解禁日を4にするとDay3までは押せず、Day4から押せる",
		not _market_enabled(1) and not _market_enabled(3) and _market_enabled(4))
	Rules._cache["market_open_from_day"] = 1
	c.check("解禁日を1にするとDay1から押せる", _market_enabled(1))

	# --- 5. 後始末：読み直して現行データへ戻す ---
	Rules.set_campaign("week7")
	c.check("後始末：現行のbillsに戻っている（rentは[1]）",
		Rules.bills().size() == 2 and Rules.bills_for_scene("thug", 1).size() == 1)
	GameState.reset_for_new_game()
	return c.finish()
