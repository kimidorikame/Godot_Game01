extends RefCounted
## UI準備AF：
##   1. 椀を出さなかった晩（断った・モブの注文を0人で確定した・鍋が尽きて閉めた）に、椀を出すときの行（ADJUST の「（味を調える）」・
##      SERVE の「「はいよ、お待ち。」」・杯ごとの adjust／serve の文）を会話枠にも会話ログにも残さない。断ったときの反応・断った晩の本文は出す。
##      画面の「断る」ボタンからは、椀を出さない SERVE を飛ばして反応へ進む（空の会話枠でクリックを待たない）。
##   2. 接客のあとの投稿（requires.visited）と DM（after_visit）は、その日に来なかった客の分を、あとの日も出さない（来店記録で決める）。

const ADJUST_TEXT := "（味を調える）"
const SERVE_TEXT := "「はいよ、お待ち。」"


func _open(t: SceneTree, customers: Array, day: int, mob: Dictionary = {}) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = day
	TalkLog.clear()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("tofu", 3, 8)
	GameState.add_inventory("nam_prik_pao", 5)
	GameState.add_inventory("herbal_sauce", 5)
	GameState.add_inventory("broken_wrapper", 5)
	GameState.add_inventory("coconut_milk", 5, 8)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	for id in mob:
		GameState.today_plan["mob_instances"][id] = mob[id]
	s.open = OpenController.new([{ "name": "明け方", "customers": customers }])
	s.load_current_customer()
	root.close_overlay()
	TalkLog.clear()
	s.logged_positions = {}
	s.record_visible_event()
	return root


func _to_adjust(root: UiGameRoot) -> void:
	var guard := 0
	while not root.session.is_choosing_ingredients() and guard < 80:
		guard += 1
		root.left.advance()
		root.session.record_visible_event()


func _log_texts() -> Array:
	return TalkLog.entries.map(func(e): return str(e["speaker"]) + str(e["text"]))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ReadState.reset("user://test_read_ui_prep_af.json")
	ScheduleData.clear_cache()

	# --- 1a. 提供した晩（比べるため）：ADJUST と SERVE の行はログに残る ---
	var root := _open(t, ["thug"], 6)
	var s: PlaySession = root.session
	_to_adjust(root)
	c.check("（前提）ADJUST の入力待ちで、ログに「（味を調える）」がある", s.is_choosing_ingredients() and _log_texts().has(ADJUST_TEXT), str(_log_texts()))
	s.select_ingredient("coconut_milk")
	s.select_ingredient("tofu")
	s.complete_input()
	s.record_visible_event()
	c.check("提供した晩：「（味を調える）」「はいよ、お待ち。」はログに残る（今までどおり）",
		_log_texts().has(ADJUST_TEXT) and _log_texts().has(SERVE_TEXT) and s.current_line()["text"] == SERVE_TEXT, str(_log_texts()))
	root.free()

	# --- 1b. 名前あり客を断る（画面の「断る」ボタン）：椀を出すときの行は出ず、すぐ断ったときの反応へ ---
	root = _open(t, ["thug"], 6)
	s = root.session
	_to_adjust(root)
	var top = root.pane_kaiten.topping
	(top.get_node("%DeclineButton") as Button).pressed.emit()
	s.record_visible_event()
	c.check("常連を断った晩（画面の「断る」）：SERVE を飛ばして反応（REACT）へ。ログに「（味を調える）」「はいよ、お待ち。」は無い",
		str(s.current_line()["type"]) == "REACT" and not _log_texts().has(ADJUST_TEXT) and not _log_texts().has(SERVE_TEXT), str(_log_texts()))
	root.free()

	# --- 1c. セッションから断ったとき（テスト・試遊の道具）：今までどおり SERVE で止まるが、その行は会話枠にもログにも出ない ---
	root = _open(t, ["thug"], 6)
	s = root.session
	_to_adjust(root)
	s.decline_customer()
	s.record_visible_event()
	c.check("セッションの decline_customer：SERVE で止まる（今までどおり）が、文は空・ログにも載らない",
		str(s.current_line()["type"]) == "SERVE" and str(s.current_line()["text"]) == "" and s.is_unserved_serve(s.flow.runner.current())
			and not _log_texts().has(SERVE_TEXT) and not _log_texts().has(ADJUST_TEXT), str(_log_texts()))
	s.next_event()
	c.check("そのあと1つ進めると反応（REACT）", str(s.current_line()["type"]) == "REACT")
	root.free()

	# --- 1d. モブの注文を0人で確定（「注文を断る」）：椀を出すときの行は出ない ---
	root = _open(t, ["mob#0"], 6, { "mob#0": { "type": "street_cleaners", "count": 2 } })
	s = root.session
	_to_adjust(root)
	s.group_decline(2)
	s.skip_unserved_serve()   # 画面の「注文を断る」（kaiten_topping._on_group_decline）と同じ
	s.record_visible_event()
	c.check("モブの注文を断った晩：反応へ進み、ログに「（味を調える）」「はいよ、お待ち。」は無い",
		str(s.current_line()["type"]) == "REACT" and not _log_texts().has(ADJUST_TEXT) and not _log_texts().has(SERVE_TEXT), str(_log_texts()))
	root.free()

	# --- 1e. 7日目のターニャ婆を断る：断った晩の4行は出て、「お待ち」は出ない ---
	root = _open(t, ["granny"], 7)
	s = root.session
	_to_adjust(root)
	(root.pane_kaiten.topping.get_node("%DeclineButton") as Button).pressed.emit()
	var guard := 0
	while s.flow.runner != null and not s.flow.is_runner_done() and guard < 60:
		guard += 1
		s.record_visible_event()
		s.next_event()
	s.record_visible_event()
	var logged := _log_texts()
	var refuse_at := logged.find("店主「すまん。今夜は、婆さんの分を出せない」")
	c.check("7日目のターニャ婆を断った晩：ログに断った晩の4行と瓶の場面が出て、「（味を調える）」「はいよ、お待ち。」は無い",
		refuse_at >= 0 and logged.has("ターニャ婆「うん。口も欠けてない。よく乾いてる」") and not logged.has(ADJUST_TEXT) and not logged.has(SERVE_TEXT),
		str(logged.slice(maxi(refuse_at - 3, 0), refuse_at + 2)))
	root.free()

	# --- 1f. 鍋が尽きて閉めた（ADJUST の入力待ちのまま閉店）：その ADJUST の行はログから外れる ---
	root = _open(t, ["thug"], 6)
	s = root.session
	_to_adjust(root)
	var before_close := _log_texts().has(ADJUST_TEXT)
	s._drop_unserved_adjust_log()   # close_shop・_auto_close_kitchen が閉店の前に呼ぶもの
	c.check("鍋が尽きて閉めた晩：入力待ちだった「（味を調える）」はログから外れる（ほかの行は残る）",
		before_close and not _log_texts().has(ADJUST_TEXT) and not _log_texts().is_empty(), str(_log_texts()))
	root.free()

	# --- 2. 来なかった客の接客のあとの投稿・DM は、あとの日も出ない ---
	GameState.reset_for_new_game()
	var lin4: Dictionary = Sns.posts().filter(func(x): return str(x["id"]) == "d4_lin_alt_2125")[0]
	var nika3: Dictionary = Sns.posts().filter(func(x): return str(x["id"]) == "d3_exposure_test_2300")[0]
	GameState.customer_memory["officer"] = { "favorite_known": false, "visits": [{ "day": 2, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	var not_came := [5, 6, 7].all(func(d): return not Sns.is_visible(lin4, d, Sns.LIMIT_DAY_END))
	GameState.customer_memory["officer"]["visits"].append({ "day": 4, "served": 0, "grade": "" })   # 4日目に来た（断った晩も来たことになる）
	var came := [5, 6, 7].all(func(d): return Sns.is_visible(lin4, d, Sns.LIMIT_DAY_END))
	c.check("4日目にリンが来なかった道：5〜7日目も 4日目 21:25 の投稿は見えない。来た道（断った晩も）なら見える", not_came and came)
	c.check("3日目のニカ 23:00 も同じ（ニカの来店記録が無ければ、4日目以降も見えない）",
		not Sns.is_visible(nika3, 4, Sns.LIMIT_DAY_END) and not Sns.is_visible(nika3, 7, Sns.LIMIT_MORNING))
	var day_only := Sns.posts().filter(func(x): return int(x["day"]) == 4 and not x.has("requires"))
	var fire6 := Sns.posts().filter(func(x): return int(x["day"]) == 6 and (x.get("requires", {}) as Dictionary).has("after_event"))
	c.check("時刻だけで見える投稿・after_event の投稿は、来店記録に関係なく、あとの日は見える（今までどおり）",
		day_only.all(func(x): return Sns.is_visible(x, 5, Sns.LIMIT_MORNING)) and fire6.all(func(x): return Sns.is_visible(x, 7, Sns.LIMIT_MORNING)))
	var dock: Dictionary = Dm.item_by_id(7, "d7_dock_0010")
	GameState.day_count = 8   # 7日目のあとの日（DM の届き方だけを見る）
	var dm_no := Dm.night_gate_ok(dock, 7, [], [])
	GameState.customer_memory["streamer"] = { "favorite_known": false, "visits": [{ "day": 7, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	var dm_yes := Dm.night_gate_ok(dock, 7, [], [])
	var fire_dm: Dictionary = Dm.item_by_id(6, "d6_zhang_0218")
	c.check("DM の after_visit も同じ：その日にニカが来なかった道は、あとの日も 00:10 の DM は届かない・来た道なら届く。after_event の DM は今までどおり",
		not dm_no and dm_yes and Dm.night_gate_ok(fire_dm, 6, [], []))
	GameState.reset_for_new_game()

	ReadState.reset(ReadState.path)
	TestCheck.free_added(t, root_before)
	return c.finish()
