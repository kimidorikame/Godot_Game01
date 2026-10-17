extends RefCounted
## 店主の距離感の選択（choices）と締めの差分（システム整理C2-①。DESIGN.md 10.5.4・10.8.6）の検証。
## 本文の後に選択ごとの CHOICE（入力待ち・仮ボタン）が出て、選んだ結果を来店記録の choices と選択肢の
## set の事実（facts）へ残す。最後の選択が済んだら、選んだ結果を読んで締め（default ＋ 選択ごとの
## 差分）を組んで差し込む。選択は料金・評判・評価・鍋・在庫を変えない。断った客・未提供には出ない。
## 場面データはキャッシュへ注入する（Day2のチンピラ＝thug_02）。

const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]
const GOOD_PICKS := ["coconut_milk", "tofu"]


func _choice(id: String, key: String) -> Dictionary:
	return { "id": id, "options": [
		{ "id": "yes", "label": "預かる", "set": { key: true } },
		{ "id": "no", "label": "本人に", "set": { key: false } } ] }


func _scene(extra: Dictionary) -> Dictionary:
	var ep := { "id": "thug_02", "customer": "thug", "greet": ["注文"], "servings": 1,
		"reactions": { "GOOD": ["R:GOOD"], "UNSERVED": ["R:UNSERVED"] },
		"body": ["B1"],
		"choices": [ _choice("message", "holding_message") ],
		"closing": { "default": ["C1"], "message:yes": ["Y"], "message:no": ["N"] } }
	ep.merge(extra, true)
	return ep


func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": ["thug", "granny"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()
	return panel


func _serve(panel, picks: Array) -> void:
	for id in picks:
		panel._on_ingredient_selected(id)
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()


## 本文を読み進めて、最初の CHOICE（入力待ち）まで行く。
func _to_choice(panel) -> void:
	var guard := 0
	while not panel._is_in_story_choice() and guard < 20:
		guard += 1
		panel._on_next_event_pressed()


## runnerの現在位置より後ろの [part, text]。
func _after(panel) -> Array:
	var out := []
	var events: Array = panel.flow.runner.events
	for i in range(panel.flow.runner.index + 1, events.size()):
		if events[i].has("part"):
			out.append([str(events[i]["part"]), str(events[i].get("text", events[i].get("choice_id", "")))])
	return out


func _snapshot(panel) -> Dictionary:
	return {
		"money": GameState.money, "rep": GameState.reputation, "day": GameState.day_count,
		"soup": GameState.soup.duplicate(true), "inventory": GameState.inventory.duplicate(true),
		"batches": GameState.perishable_batches.duplicate(true), "dashi": GameState.dashi_units,
		"served": GameState.served.duplicate(true), "ledger": GameState.ledger.size(),
		"slot_index": panel._open.slot_index, "customer_index": panel._open.index,
		"result": str(panel._open.current_bowl.get("result", "")),
	}


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"

	# --- 1. 本文の後にCHOICE（入力待ち）。ボタンは選択肢の数。[次のEvent]・[入力完了]では飛ばせない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({})
	var panel = _setup(t)
	_serve(panel, GOOD_PICKS)
	c.check("提供後の列は 本文 → CHOICE（締めはまだ無い：選択の結果で組む）",
		_after(panel) == [["body", "B1"], ["choice", "message"]], str(_after(panel)))
	_to_choice(panel)
	c.check("本文を読んだ後、CHOICEで入力待ちになる",
		panel._is_in_story_choice() and panel.flow.runner.status == EventRunner.Status.WAITING_INPUT)
	panel._refresh()
	var labels := []
	for child in panel._options_row.get_children():
		if not child.is_queued_for_deletion():   # 描き直しで捨てた古いボタン（次のフレームまで残る）を除く
			labels.append(child.text)
	c.check("仮ボタンは選択肢の数（預かる／本人に）", labels == ["預かる", "本人に"], str(labels))
	c.check("[次のEvent]・[入力完了]は無効", panel._btn_next_event.disabled and panel._btn_complete_input.disabled)
	var index_at_choice: int = panel.flow.runner.index
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()
	c.check("[入力完了]・[次のEvent]では選択を飛ばせない", panel.flow.runner.index == index_at_choice
		and CustomerMemory.choices_today("thug").is_empty())
	panel._on_story_choice_pressed("message", "zzz")
	panel._on_story_choice_pressed("other", "yes")
	c.check("合わない選択・選択肢のidは何もしない", panel.flow.runner.index == index_at_choice
		and CustomerMemory.choices_today("thug").is_empty())

	# --- 2. 選ぶ：来店記録のchoicesと事実(facts)に残り、締めは default ＋ 差分。料金・評判・評価は不変 ---
	var before := _snapshot(panel)
	panel._on_story_choice_pressed("message", "yes")
	c.check("選んだ結果が来店記録 visits[今日].choices に残る",
		CustomerMemory.choices_today("thug") == { "message": "yes" }
			and CustomerMemory.today_visit("thug")["choices"] == { "message": "yes" })
	c.check("選択肢のsetが facts に書かれる", CustomerMemory.fact("thug", "holding_message") == true)
	c.check("選んだ直後は締めの先頭（default）に進み、差分がその後ろに続く（足し算）",
		str(panel.flow.runner.current().get("text", "")) == "C1" and _after(panel) == [["closing", "Y"]],
		str(_after(panel)))
	var closing_lines := []
	var guard := 0
	while panel.flow.runner.current() != null and guard < 10:
		var cur = panel.flow.runner.current()
		if str(cur.get("part", "")) == "closing":
			closing_lines.append(str(cur["text"]))
		if panel.flow.runner.index + 1 >= panel.flow.runner.events.size():
			break
		guard += 1
		panel._on_next_event_pressed()
	c.check("読み進めると 締め: C1 → Y の順", closing_lines == ["C1", "Y"], str(closing_lines))
	c.check("選択の前後で料金・評判・評価・鍋・在庫・腐敗・時間帯・客の位置は不変", _snapshot(panel) == before)
	c.check("選択でも判定の評価は変わらない（提供の瞬間に決まったまま）", str(panel._open.current_bowl.get("result", "")) == "GOOD")
	panel.free()

	# --- 3. もう一方を選ぶと、別の差分と別の事実の値。該当する差分が無ければ default のみ ---
	var p2 = _setup(t)
	_serve(p2, GOOD_PICKS)
	_to_choice(p2)
	p2._on_story_choice_pressed("message", "no")
	c.check("もう一方：事実は false・差分は N", CustomerMemory.fact("thug", "holding_message") == false
		and _after(p2).has(["closing", "N"]) and not _after(p2).has(["closing", "Y"]))
	p2.free()
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "closing": { "default": ["C1"] } })
	var p3 = _setup(t)
	_serve(p3, GOOD_PICKS)
	_to_choice(p3)
	p3._on_story_choice_pressed("message", "yes")
	c.check("差分のキーが無ければ default だけ",
		str(p3.flow.runner.current().get("text", "")) == "C1" and _after(p3).is_empty(), str(_after(p3)))
	p3.free()

	# --- 4. 選択が2つ：最後の選択の後に、両方の差分を場面の選択の順に足した締めを差し込む ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({
		"choices": [ _choice("message", "holding_message"), _choice("camera", "camera_ok") ],
		"closing": { "default": ["C1"], "message:yes": ["MY"], "camera:no": ["CN"], "camera:yes": ["CY"] } })
	var p4 = _setup(t)
	_serve(p4, GOOD_PICKS)
	_to_choice(p4)
	p4._on_story_choice_pressed("message", "yes")
	c.check("1つ目の後は次のCHOICEで止まる（締めはまだ無い）",
		p4._is_in_story_choice() and str(p4.flow.runner.current()["choice_id"]) == "camera"
			and _after(p4).is_empty(), str(_after(p4)))
	p4._on_story_choice_pressed("camera", "no")
	c.check("2つ目の後に締め：default → message:yes → camera:no（場面の選択の順）",
		str(p4.flow.runner.current().get("text", "")) == "C1"
			and _after(p4) == [["closing", "MY"], ["closing", "CN"]], str(_after(p4)))
	c.check("両方の選択と事実が残る",
		CustomerMemory.choices_today("thug") == { "message": "yes", "camera": "no" }
			and CustomerMemory.fact("thug", "holding_message") == true and CustomerMemory.fact("thug", "camera_ok") == false)
	p4.free()

	# --- 5. 断った客・提供しなかった客には選択を出さない ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "must_info": ["m"], "body_unserved": ["U1"] })
	var p5 = _setup(t)
	p5._on_customer_decline_pressed()
	p5._on_next_event_pressed()
	c.check("断った客：選択は出ない（未提供版の本文だけ）", _after(p5) == [["body", "U1"]], str(_after(p5)))
	c.check("断った客：choices・factsは作らない", CustomerMemory.choices_today("thug").is_empty()
		and (GameState.customer_memory["thug"]["facts"] as Dictionary).is_empty())
	p5.free()
	var unserved := Day1Events.unserved_exit_events("thug", "thug_02")
	c.check("閉店で退店する客にも選択は出ない", unserved.filter(func(e): return e["type"] == "CHOICE").is_empty())

	# --- 6. 組み立ては状態を読むだけ：何度呼んでも同じ ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({})
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var memory_before := GameState.customer_memory.duplicate(true)
	var first := Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": "GOOD" })
	for i in range(3):
		Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": "GOOD" })
		Day1Events.closing_events("thug", "thug_02")
	c.check("after_serve_events／closing_events は何度呼んでも同じ列を返し、来店記録を書かない",
		Day1Events.after_serve_events("thug", "thug_02", { "served": true, "grade": "GOOD" }) == first
			and GameState.customer_memory == memory_before)
	c.check("選択のある場面のafter_serve_eventsに締めは含まない（選択の結果を読むため）",
		first.filter(func(e): return e.get("part", "") == "closing").is_empty())
	c.check("CHOICEは options を持つので EventRunner が入力待ちにする（条件分岐はRunnerに無い）",
		EventRunner.new([first[1]]).status == EventRunner.Status.WAITING_INPUT)

	# --- 7. 現行の21場面（選択なし）は何も出ない ---
	ScheduleData.clear_cache()
	var pr = _setup(t)
	var count_before: int = pr.flow.runner.events.size()
	_serve(pr, GOOD_PICKS)
	c.check("実データ：CHOICEは出ず、イベント列も変わらない",
		pr.flow.runner.events.size() == count_before and not pr._is_in_story_choice())
	pr.free()

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
