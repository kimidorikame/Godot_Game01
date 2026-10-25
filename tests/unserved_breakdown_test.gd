extends RefCounted
## 足りなかった杯数の理由別の記録（UI準備C③）：素材が足りない／鍋が足りない／断った。
## 判断の瞬間に PlaySession が log_unserved へ積み、日の終わりに log_entry へ unserved_ingredients・unserved_pot・
## unserved_declined・unserved_not_arrived（閉店のあと来られなかった客）を足す。4つの合計は unserved_cups と同じ。
## 画面の内訳（unserved_display）は、来られなかった客の分を「鍋」に含める。既存のキーは変えない。

const MOB_ID := "mob_unserved"


## 開店（OPEN）の最初の入力待ち（ADJUST）まで進める。customers は1つの時間帯に並べる。
func _start(t: SceneTree, customers: Array, stock: Dictionary, soup_remaining: int = 999, strength: int = 3, mob_count: int = 0) -> PlaySession:
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var s := PlaySession.new()
	t.root.add_child(s)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in stock:
		GameState.add_inventory(id, int(stock[id]))
	GameState.set_soup("bone_broth", ["meaty"], soup_remaining, strength, 2)
	GameState.phase = GameState.Phase.OPEN
	if mob_count > 0:
		GameState.today_plan["mob_instances"][MOB_ID] = { "type": "dock_workers", "count": mob_count }
	s.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	# OPEN突入の処理（set_runner_for_phase）と同じ：その夜の注文の総杯数を先読みして積む
	s.log_planned_cups = 0
	for customer_id in customers:
		for ev in Day1Events.customer_events(str(customer_id)):
			if ev.get("type", "") == "REACT":
				s.log_planned_cups += int(ev.get("servings", 0))
	s.load_current_customer()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 60:
		guard += 1
		s.next_event()
	return s


func _sum(d: Dictionary) -> int:
	return int(d["unserved_ingredients"]) + int(d["unserved_pot"]) + int(d["unserved_declined"]) + int(d["unserved_not_arrived"])


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var full_stock := { "nam_prik_pao": 9, "offal": 9, "coconut_milk": 9, "tofu": 9 }

	# --- 1. 名前あり客を断る ---
	var s := _start(t, ["officer"], full_stock)
	c.check("最初は理由別の記録は全部0", s.log_unserved == { "ingredients": 0, "pot": 0, "declined": 0 })
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("offal")
	s.decline_customer()   # 提供できる椀なのに断る
	s.next_event()
	c.check("出せる椀なのに断った → 断った", s.log_unserved["declined"] >= 1 and s.log_unserved["pot"] == 0 and s.log_unserved["ingredients"] == 0,
		str(s.log_unserved))
	s.free()

	s = _start(t, ["officer"], full_stock, 0, 3)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("offal")
	s.decline_customer()   # 鍋が空で出せない
	c.check("鍋の残量が足りない椀を断った → 鍋", s.pending_decline_reason == "pot", s.pending_decline_reason)
	s.next_event()
	c.check("理由別の記録の鍋に積まれる", s.log_unserved["pot"] >= 1 and s.log_unserved["declined"] == 0, str(s.log_unserved))
	s.free()

	s = _start(t, ["officer"], full_stock)
	GameState.soup["strength"] = 0   # set_soup は濃さを1以上に丸めるので、直に0にする
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("offal")
	s.decline_customer()
	c.check("濃さ0で出せない椀を断った → 鍋", s.pending_decline_reason == "pot", s.pending_decline_reason)
	s.free()

	s = _start(t, ["officer"], { "nam_prik_pao": 9 })   # 具の素材が手元に無い
	s.select_ingredient("nam_prik_pao")
	s.decline_customer()
	c.check("具の素材が手元に1つも無く、椀が成立しない → 素材", s.pending_decline_reason == "ingredients", s.pending_decline_reason)
	s.free()

	s = _start(t, ["officer"], full_stock)
	s.select_ingredient("nam_prik_pao")   # 具を入れていないだけ（在庫には具がある）
	s.decline_customer()
	c.check("在庫に素材があるのに椀を作らなかった → 断った", s.pending_decline_reason == "declined", s.pending_decline_reason)
	s.free()

	# --- 2. モブの団体 ---
	s = _start(t, [MOB_ID], { "meat_ball": 3, "nam_prik_pao": 10 }, 999, 3, 4)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	var group := s.mob_group_choice()
	s.group_serve(int(group["achievable"]), int(group["ordered"]))
	s.next_event()
	c.check("具材の在庫が3個で3人分だけ出した（注文4）→ 素材が1", int(group["achievable"]) == 3 and s.log_unserved["ingredients"] == 1
		and s.log_unserved["pot"] == 0, str(s.log_unserved))
	s.free()

	s = _start(t, [MOB_ID], { "meat_ball": 10, "nam_prik_pao": 10 }, 2, 3, 4)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	group = s.mob_group_choice()
	s.group_serve(int(group["achievable"]), int(group["ordered"]))
	s.next_event()
	c.check("鍋の残量2で2人分だけ出した（注文4、具材は十分）→ 鍋が2", int(group["achievable"]) == 2 and s.log_unserved["pot"] == 2
		and s.log_unserved["ingredients"] == 0, str(s.log_unserved))
	s.free()

	s = _start(t, [MOB_ID], { "meat_ball": 2, "nam_prik_pao": 10 }, 2, 3, 4)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	group = s.mob_group_choice()
	s.group_serve(int(group["achievable"]), int(group["ordered"]))
	s.next_event()
	c.check("鍋の残量と具材の在庫が同じ2（注文4）→ 同じなら鍋", s.log_unserved["pot"] == 2 and s.log_unserved["ingredients"] == 0, str(s.log_unserved))
	s.free()

	s = _start(t, [MOB_ID], { "meat_ball": 10, "nam_prik_pao": 10 }, 999, 3, 4)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	s.group_decline(4)   # 全員分出せるのに断る
	s.next_event()
	c.check("出せるのにモブの注文を断った → 断った4", s.log_unserved["declined"] == 4 and s.log_unserved["pot"] == 0, str(s.log_unserved))
	s.free()

	s = _start(t, [MOB_ID], { "meat_ball": 10, "nam_prik_pao": 10 }, 999, 3, 4)
	GameState.soup["strength"] = 0
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	s.group_decline(4)   # 濃さ0で1人も出せない
	s.next_event()
	c.check("濃さ0で1人も出せず断った → 鍋4", s.log_unserved["pot"] == 4 and s.log_unserved["declined"] == 0, str(s.log_unserved))
	s.free()

	s = _start(t, [MOB_ID], { "meat_ball": 3, "nam_prik_pao": 10, "tofu": 10 }, 999, 3, 4)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("meat_ball")
	s.complete_input()
	group = s.mob_group_choice()
	s.group_retry(int(group["achievable"]), int(group["ordered"]))   # 3人分を出して、残り1人は別の具材で
	s.next_event()
	c.check("挑戦を選んだ時点では、まだ出せなかった扱いにしない（残りは2レシピ目で決まる）", s.log_unserved == { "ingredients": 0, "pot": 0, "declined": 0 },
		str(s.log_unserved))
	s.free()

	# --- 3. 閉店：今の客の分は鍋、来られなかった客の分は来られなかった ---
	s = _start(t, ["officer", "thug"], full_stock, 0, 3)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("offal")
	c.check("鍋が空で水も足せない状態ではなく、閉店できる（保留でなく、足りない椀の途中）", s.can_close_now() or GameState.water_reachable())
	if not s.can_close_now():
		GameState.soup["water_doses"] = 0
	var cups := s._cups_left_for_current_customer()
	s.close_shop()
	c.check("閉店：今の客の注文の杯数が鍋に積まれる", GameState.phase == GameState.Phase.CLOSE and s.log_unserved["pot"] == cups and cups >= 1,
		"%s cups=%d" % [str(s.log_unserved), cups])
	var tonight := s.tonight_result()
	c.check("tonight_result に内訳の4つのキーがある", tonight.has("unserved_ingredients") and tonight.has("unserved_pot")
		and tonight.has("unserved_declined") and tonight.has("unserved_not_arrived"))
	c.check("4つの合計は出せなかった杯数と同じ", _sum(tonight) == int(tonight["unserved_cups"]), str(tonight))
	c.check("閉店のあと来られなかった客（チンピラ）は unserved_not_arrived", int(tonight["unserved_not_arrived"]) >= 1, str(tonight))
	var shown := PlaySession.unserved_display(tonight)
	c.check("画面の内訳：来られなかった客の分は「鍋」に含める（素材・鍋・断った）",
		int(shown["pot"]) == int(tonight["unserved_pot"]) + int(tonight["unserved_not_arrived"]) and int(shown["ingredients"]) == 0
			and int(shown["declined"]) == 0 and int(shown["pot"]) + int(shown["ingredients"]) + int(shown["declined"]) == int(tonight["unserved_cups"]))
	c.check("画面の1行：合計と、0でない内訳だけ（鍋に来られなかった分を含む）",
		UiParts.unserved_text(int(tonight["unserved_cups"]), shown) == "足りなかった %d杯（鍋 %d）" % [int(tonight["unserved_cups"]), int(shown["pot"])],
		UiParts.unserved_text(int(tonight["unserved_cups"]), shown))
	s.free()

	# 日の終わり：log_entry に4つのキーが入り、既存のキーは変わらない。前日成績の問いでも返る
	s = _start(t, ["officer", "thug"], full_stock, 0, 3)
	s.select_ingredient("nam_prik_pao")
	s.select_ingredient("offal")
	GameState.soup["water_doses"] = 0
	s.close_shop()
	s.on_day_ending()
	var entry: Dictionary = GameState.day_records[GameState.day_records.size() - 1]
	c.check("日次ログ：4つの内訳のキーが足される", entry.has("unserved_ingredients") and entry.has("unserved_pot")
		and entry.has("unserved_declined") and entry.has("unserved_not_arrived"))
	c.check("日次ログ：4つの合計は unserved_cups と同じ", _sum(entry) == int(entry["unserved_cups"]), str(entry))
	c.check("日次ログ：既存のキー（planned_cups・served_cups・unserved_cups・sale_total など）は残る",
		entry.has("planned_cups") and entry.has("served_cups") and entry.has("unserved_cups") and entry.has("sale_total")
			and entry.has("quality_counts") and entry.has("regular_visits"))
	GameState.day_count += 1
	c.check("previous_day_record() でも内訳が返る", s.previous_day_record().has("unserved_pot"))
	s.free()

	# --- 4. 内訳のキーが無い古い記録 ---
	var old := { "unserved_cups": 3 }
	c.check("古い記録（内訳のキーが無い）：画面の内訳は空", PlaySession.unserved_display(old).is_empty())
	c.check("古い記録：画面の1行は合計だけ", UiParts.unserved_text(3, PlaySession.unserved_display(old)) == "足りなかった 3杯")
	c.check("足りなかった杯数が0なら、合計だけ", UiParts.unserved_text(0, { "ingredients": 0, "pot": 0, "declined": 0 }) == "足りなかった 0杯")
	c.check("0でない内訳だけを出す：素材1・断った2", UiParts.unserved_text(3, { "ingredients": 1, "pot": 0, "declined": 2 }) == "足りなかった 3杯（素材 1・断った 2）")
	return c.finish()
