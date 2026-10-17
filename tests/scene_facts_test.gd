extends RefCounted
## 場面が次回へ残す事実（sets_facts）と、今日の頼みに応えたか（request_honored）、来店記録の拡張の
## 保存（システム整理C2-②。DESIGN.md 10.8.5・10.8.7）の検証。
##   - sets_facts：締めを読み終えて SCENE_END に来た時に facts へ書く。未提供・途中の閉店／再挑戦では書かない。
##     翌朝の EpisodeSelector が requires.facts でその事実を読んで場面を選ぶ
##   - request_honored：今日の頼みがある場面を提供したときだけ（実効注文のタグを全部満たした＝true）
##   - 保存：版は5のまま。visits の choices／request_honored は任意キー（あれば型を検査）。旧形式も読める。
##     朝の辞書の往復と再挑戦（朝へ戻す）で、選択と事実が正しく戻る
## 場面データはキャッシュへ注入する（Day2のチンピラ＝thug_02）。

const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]
const GOOD_PICKS := ["coconut_milk", "tofu"]
const TEST_PATH := "user://scene_facts_test.dat"


func _choice(id: String, key: String) -> Dictionary:
	return { "id": id, "options": [
		{ "id": "yes", "label": "はい", "set": { key: true } },
		{ "id": "no", "label": "いいえ", "set": { key: false } } ] }


func _scene(extra: Dictionary) -> Dictionary:
	var ep := { "id": "thug_02", "customer": "thug", "greet": ["注文"], "servings": 1,
		"reactions": { "GOOD": ["R:GOOD"], "UNSERVED": ["R:UNSERVED"] }, "body": ["B1"],
		"closing": { "default": ["C1"] } }
	ep.merge(extra, true)
	return ep


func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（朝の記録ができる）
	_start_open(panel)
	return panel


## OPENに入り、客（チンピラ→老婆）の接客のADJUST待ちまで進める。
func _start_open(panel) -> void:
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


func _serve(panel, picks: Array) -> void:
	for id in picks:
		panel._on_ingredient_selected(id)
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()


## 現在の events のうち、次の type が来るまで1つずつ進める（CHOICE は押さない）。
func _advance_until(panel, type: String) -> void:
	var guard := 0
	while guard < 30 and panel.flow.runner.current() != null \
			and str(panel.flow.runner.current().get("type", "")) != type \
			and panel.flow.runner.status == EventRunner.Status.PLAYING:
		guard += 1
		panel._on_next_event_pressed()


func _facts(customer_id: String) -> Dictionary:
	if not GameState.customer_memory.has(customer_id):
		return {}
	return (GameState.customer_memory[customer_id]["facts"] as Dictionary).duplicate()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"

	# --- 1. sets_facts：SCENE_END に来た時に書く（締めを読み終えた後）。翌朝の場面選びが読む ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "sets_facts": { "went_home_early": true } })
	var panel = _setup(t)
	_serve(panel, GOOD_PICKS)
	var kinds := []
	for ev in panel.flow.runner.events:
		kinds.append(str(ev["type"]))
	c.check("提供後の列は 本文 → 締め → SCENE_END（事実は列の最後に積む）",
		kinds.slice(kinds.size() - 3) == ["GREET", "GREET", "SCENE_END"], str(kinds))
	c.check("本文・締めを読んでいる間は、まだ事実を書かない", _facts("thug").is_empty())
	panel._on_next_event_pressed()   # 本文
	panel._on_next_event_pressed()   # 締め
	c.check("締めを読んでも、まだ書かない（SCENE_ENDに進むまで）", _facts("thug").is_empty())
	panel._on_next_event_pressed()   # SCENE_END
	c.check("SCENE_ENDに来た時に facts へ書く", _facts("thug") == { "went_home_early": true }, str(_facts("thug")))
	c.check("何度適用しても同じ値（冪等）", CustomerMemory.fact("thug", "went_home_early") == true)
	panel.free()

	# 翌朝の場面選び：thug_02 は事実が立っているときだけ選ばれる（無ければ別の場面）
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "requires": { "facts": { "went_home_early": true } } })
	GameState.reset_for_new_game()
	GameState.day_count = 3
	c.check("事実が無い朝：thug_02 は選ばれず、前提の無い別の場面（thug_01）になる",
		EpisodeSelector.select("thug", "thug_02") == "thug_01")
	CustomerMemory.set_fact("thug", "went_home_early", true)
	c.check("事実が立った朝：EpisodeSelector が requires.facts を読んで thug_02 を選ぶ",
		EpisodeSelector.select("thug", "thug_02") == "thug_02")

	# --- 2. 選択の set と sets_facts は別のキー（合わせて2個まで）で、どちらも書かれる ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "choices": [ _choice("message", "holding_message") ],
		"closing": { "default": ["C1"], "message:yes": ["Y"] }, "sets_facts": { "met_today": true } })
	var p2 = _setup(t)
	_serve(p2, GOOD_PICKS)
	_advance_until(p2, "CHOICE")
	p2._on_story_choice_pressed("message", "yes")
	c.check("選択の直後：選択のsetは書かれ、sets_factsはまだ", _facts("thug") == { "holding_message": true }, str(_facts("thug")))
	_advance_until(p2, "SCENE_END")
	p2._on_next_event_pressed()
	c.check("締めの後（SCENE_END）：sets_factsも書かれる（合わせて2個）",
		_facts("thug") == { "holding_message": true, "met_today": true }, str(_facts("thug")))
	p2.free()

	# --- 3. 提供しなかった客は事実を書かない（本文を再生しても） ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "sets_facts": { "met_today": true },
		"must_info": ["m"], "body_unserved": ["U1"] })
	var p3 = _setup(t)
	p3._on_customer_decline_pressed()
	p3._on_next_event_pressed()
	var has_end := false
	for ev in p3.flow.runner.events:
		has_end = has_end or str(ev["type"]) == "SCENE_END"
	c.check("断った客：SCENE_ENDは付かず、未提供版の本文を読み終えても事実は書かれない",
		not has_end and _facts("thug").is_empty())
	p3.free()
	c.check("閉店で退店する客の未提供版にもSCENE_ENDは無い",
		Day1Events.unserved_exit_events("thug", "thug_02").filter(func(e): return e["type"] == "SCENE_END").is_empty())

	# --- 4. request_honored：今日の頼みがある場面だけ、実効注文を全部満たしたら true ---
	var request_scene := { "order": { "today_request": { "tags": ["HOT", "POWER"], "label": "辛め" } },
		"closing": { "default": ["C1"], "request_honored:true": ["HT"], "request_honored:false": ["HF"] } }
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene(request_scene)
	var p4 = _setup(t)
	_serve(p4, ["nam_prik_pao", "offal"])
	c.check("頼み（HOT/POWER）を両方満たした椀：request_honored=true",
		CustomerMemory.today_visit("thug").get("request_honored") == true, str(CustomerMemory.today_visit("thug")))
	var lines4 := []
	for ev in p4.flow.runner.events:
		if str(ev.get("part", "")) == "closing":
			lines4.append(str(ev["text"]))
	c.check("締めに request_honored:true の差分が足される（default → 差分）", lines4 == ["C1", "HT"], str(lines4))
	p4.free()
	var p4b = _setup(t)
	_serve(p4b, GOOD_PICKS)
	c.check("頼みを満たさない椀（基本注文だけ満たす）：request_honored=false",
		CustomerMemory.today_visit("thug").get("request_honored") == false)
	var lines4b := []
	for ev in p4b.flow.runner.events:
		if str(ev.get("part", "")) == "closing":
			lines4b.append(str(ev["text"]))
	c.check("締めは request_honored:false の差分（評価が下がっても締めは default ＋ 差分のみ）",
		lines4b == ["C1", "HF"], str(lines4b))
	p4b.free()
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({})
	var p4c = _setup(t)
	_serve(p4c, GOOD_PICKS)
	c.check("今日の頼みが無い場面：request_honored のキー自体を入れない",
		not CustomerMemory.today_visit("thug").has("request_honored"))
	p4c.free()
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene(request_scene)
	var p4d = _setup(t)
	p4d._on_customer_decline_pressed()
	p4d._on_next_event_pressed()
	c.check("断った客：request_honored は入れない", not CustomerMemory.today_visit("thug").has("request_honored"))
	p4d.free()

	# --- 5. 保存：朝の辞書の往復で choices・request_honored・facts が戻る。版は5のまま ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "choices": [ _choice("message", "holding_message") ],
		"order": request_scene["order"], "sets_facts": { "met_today": true },
		"closing": { "default": ["C1"], "message:yes": ["Y"] } })
	var p5 = _setup(t)
	_serve(p5, ["nam_prik_pao", "offal"])
	_advance_until(p5, "CHOICE")
	p5._on_story_choice_pressed("message", "yes")
	_advance_until(p5, "SCENE_END")
	p5._on_next_event_pressed()
	var memory_after := GameState.customer_memory.duplicate(true)
	var visit_now: Dictionary = CustomerMemory.today_visit("thug")
	c.check("（前提）来店記録に choices・request_honored・facts がある",
		visit_now["choices"] == { "message": "yes" } and visit_now["request_honored"] == true
			and _facts("thug") == { "holding_message": true, "met_today": true })
	var d := GameState.to_dict()
	GameState.reset_for_new_game()
	GameState.from_dict(d)
	c.check("to_dict→from_dict で choices・request_honored・facts が戻る（深いコピー）",
		JSON.stringify(GameState.customer_memory) == JSON.stringify(memory_after))
	(d["customer_memory"]["thug"]["visits"][0]["choices"] as Dictionary)["message"] = "no"
	c.check("戻した後に元の辞書を書き換えても、来店記録は変わらない",
		CustomerMemory.today_visit("thug")["choices"] == { "message": "yes" })

	var saved_path := MorningSave.save_path
	MorningSave.save_path = TEST_PATH
	MorningSave.delete_file()
	var env := MorningSave.capture("")
	c.check("新形式の封筒は検証を通る（choices・request_honoredは任意キーで版を上げない。版は4-7①の6）",
		MorningSave.is_valid(env) and int(env["version"]) == 6 and MorningSave.VERSION == 6)
	c.check("ファイルへ書いて読むと、choices・request_honored・facts が型も含めて戻る",
		MorningSave.write_file(env) and JSON.stringify(MorningSave.read_file()["state"]["customer_memory"])
			== JSON.stringify(memory_after))

	# --- 6. 旧形式（choices・request_honored の無い来店記録）も読める。型が不正なら弾く ---
	var old_env := MorningSave.capture("")
	for id in old_env["state"]["customer_memory"]:
		for v in old_env["state"]["customer_memory"][id]["visits"]:
			(v as Dictionary).erase("choices")
			(v as Dictionary).erase("request_honored")
	c.check("旧形式（任意キーなし）の封筒も検証を通る", MorningSave.is_valid(old_env))
	MorningSave.write_file(old_env)
	var loaded := MorningSave.read_file()
	c.check("旧形式をファイルから読めて、適用できる",
		not loaded.is_empty() and MorningSave.is_valid(loaded))
	GameState.reset_for_new_game()
	MorningSave.apply(loaded)
	c.check("適用後、来店記録はキーなしのまま（選択・応えたかは空として読む）",
		CustomerMemory.choices_today("thug").is_empty()
			and not CustomerMemory.today_visit("thug").has("request_honored"))
	var bad_choices := MorningSave.capture("")
	bad_choices["state"]["customer_memory"]["thug"]["visits"][0]["choices"] = ["yes"]
	c.check("choices が辞書でないものは弾く", not MorningSave.is_valid(bad_choices))
	var bad_choices2 := MorningSave.capture("")
	bad_choices2["state"]["customer_memory"]["thug"]["visits"][0]["choices"] = { "message": 1 }
	c.check("choices の値が文字列でないものは弾く", not MorningSave.is_valid(bad_choices2))
	var bad_honored := MorningSave.capture("")
	bad_honored["state"]["customer_memory"]["thug"]["visits"][0]["request_honored"] = "yes"
	c.check("request_honored が真偽値でないものは弾く", not MorningSave.is_valid(bad_honored))
	MorningSave.delete_file()
	MorningSave.save_path = saved_path
	p5.free()

	# --- 7. 再挑戦（朝へ戻す）：選択・事実・応えたかが戻した朝の状態へ戻る。やり直しても同じ結果 ---
	ScheduleData.clear_cache()
	ScheduleData._episode_cache["thug/thug_02"] = _scene({ "choices": [ _choice("message", "holding_message") ],
		"order": request_scene["order"], "sets_facts": { "met_today": true },
		"closing": { "default": ["C1"], "message:yes": ["Y"], "message:no": ["N"] } })
	var p7 = _setup(t)
	c.check("（前提）Day2の朝の記録がある", GameState.morning_snapshots.has(2))
	_serve(p7, ["nam_prik_pao", "offal"])
	_advance_until(p7, "CHOICE")
	p7._on_story_choice_pressed("message", "yes")
	_advance_until(p7, "SCENE_END")
	p7._on_next_event_pressed()
	c.check("（前提）選択・事実・応えたかが残っている",
		CustomerMemory.choices_today("thug") == { "message": "yes" } and _facts("thug").size() == 2)
	c.check("朝へ戻せる", p7.retry_from_morning(2) and GameState.day_count == 2)
	c.check("再挑戦で、選択・事実・応えたか・来店記録が朝の状態へ戻る（その客の記録は無い）",
		not GameState.customer_memory.has("thug") or (CustomerMemory.visits_of("thug").is_empty()
			and _facts("thug").is_empty()))
	# やり直し：別の選択をすると、その結果が残る（前の選択が残らない）
	_start_open(p7)
	_serve(p7, GOOD_PICKS)
	_advance_until(p7, "CHOICE")
	p7._on_story_choice_pressed("message", "no")
	c.check("やり直し：別の選択がそのまま残る（前の選択は残らない）",
		CustomerMemory.choices_today("thug") == { "message": "no" }
			and CustomerMemory.fact("thug", "holding_message") == false
			and CustomerMemory.today_visit("thug")["request_honored"] == false)
	c.check("やり直し：SCENE_ENDの前なので sets_facts はまだ無い", CustomerMemory.fact("thug", "met_today", null) == null)
	p7.free()

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
