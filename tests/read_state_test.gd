extends RefCounted
## 既読の記録と既読スキップ（フェーズ4・手順4-7③。DESIGN.md 10.4）の検証。
## 既読は「その周の状態」ではなく「見たことがあるか」＝朝の保存に入れず、再挑戦・新しい周でも消えない
## （ReadState。user://read_state.json）。スキップは [次のEvent] と同一の経路を繰り返すだけで、会計・
## 来店記録・事実・評判は1回だけ適用される（二重適用なし）。未読の行・入力待ち・選択・客やフェーズの
## 切り替わり・上限で止まる。テストは開始時にメモリ上の集合とパスを初期化し、実際の
## user://read_state.json を読まず・書かない。

const TEST_PATH := "user://read_state_test.json"
const OTHER_PATH := "user://read_state_test_other.json"
const REAL_PATH := "user://read_state.json"
const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]
const GOOD_PICKS := ["coconut_milk", "tofu"]


func _fresh(enabled: bool = true) -> void:
	for p in [TEST_PATH, OTHER_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	ReadState.reset(TEST_PATH, enabled)


func _thug_scene(extra: Dictionary = {}) -> Dictionary:
	var ep := { "id": "thug_01", "customer": "thug", "greet": ["g1", "g2", "g3", "g4"], "servings": 1,
		"reactions": { "GREAT": ["R:GREAT"], "GOOD": ["R:GOOD"], "OK": ["R:OK"], "BAD": ["R:BAD"] },
		"body": ["本文1"], "closing": { "default": ["締め1"] }, "sets_facts": { "k": true } }
	ep.merge(extra, true)
	return ep


## Day1（徴収日。チンピラの場所代 PAY がある）の夜半、チンピラ1人の接客を ADJUST 待ちまで進める。
func _setup(t: SceneTree, seed_value: int = 1, day: int = 1):
	seed(seed_value)
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "夜半", "customers": ["thug"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	return panel


func _to_adjust(panel) -> void:
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()


## 椀を作って提供し、REACT の手前（SERVE）まで進める。判定の抽選を同じにするため直前に seed を固定する。
func _serve(panel) -> void:
	for id in GOOD_PICKS:
		panel._on_ingredient_selected(id)
	seed(555)
	panel._on_complete_input_pressed()


func _state(panel) -> String:
	return JSON.stringify([GameState.to_dict(), GameState.served, GameState.ledger,
		GameState.rent_paid_today, panel._open.current_bowl, panel.flow.runner.index])


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()
	var real_existed := FileAccess.file_exists(REAL_PATH)
	var real_time := FileAccess.get_modified_time(REAL_PATH) if real_existed else 0
	_fresh()

	# --- 1. ReadState：キー・追加・書き出し・読み込み・パス差し替え ---
	var k1 := ReadState.line_key("talk", "チンピラ", "", "本文")
	c.check("キーは 種別・話し手・part・本文のsha1 で決まる（同じなら同じ）",
		k1 == ReadState.line_key("talk", "チンピラ", "", "本文") and k1.ends_with("|" + "本文".sha1_text()))
	c.check("本文・話し手・part・種別のどれかが違えば別のキー",
		k1 != ReadState.line_key("talk", "チンピラ", "", "本文２") and k1 != ReadState.line_key("talk", "老婆", "", "本文")
			and k1 != ReadState.line_key("talk", "チンピラ", "news", "本文") and k1 != ReadState.line_key("narration", "チンピラ", "", "本文"))
	c.check("最初は未読。足すと既読（新しく足したときだけ true）",
		not ReadState.is_read(k1) and ReadState.mark(k1) and ReadState.is_read(k1) and not ReadState.mark(k1) and ReadState.count() == 1)
	c.check("本文が差し替わった行は未読に戻る", not ReadState.is_read(ReadState.line_key("talk", "チンピラ", "", "本文（直した）")))
	c.check("書き出す前はファイルが無い（1行ごとには書かない）", not FileAccess.file_exists(TEST_PATH))
	c.check("flush で書き出す。version と lines を持つJSON",
		ReadState.flush() and FileAccess.file_exists(TEST_PATH)
			and JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH)) == { "version": 1.0, "lines": [k1] })
	c.check("変更が無ければ書かない（flush は false）", not ReadState.flush())
	ReadState.mark(ReadState.line_key("news", "", "news", "ニュース"))
	c.check("変更があればまた書く", ReadState.flush() and (JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))["lines"] as Array).size() == 2)
	# 読み込み：メモリを捨てて（未読み込み状態に戻して）ファイルから読む
	ReadState._lines = {}
	ReadState._loaded = false
	c.check("ファイルから読み込める（初回の利用で読む）", ReadState.is_read(k1) and ReadState.count() == 2)
	# パス差し替え
	ReadState.reset(OTHER_PATH)
	c.check("パスを差し替えた直後は空の集合から始める（別ファイルは読まない）", ReadState.count() == 0 and not ReadState.is_read(k1))
	ReadState.mark(k1)
	ReadState.flush()
	c.check("差し替えたパスへ書く（元のファイルは変えない）",
		FileAccess.file_exists(OTHER_PATH) and (JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))["lines"] as Array).size() == 2)
	# 壊れたファイル・別の版
	var f := FileAccess.open(OTHER_PATH, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	ReadState._lines = {}
	ReadState._loaded = false
	c.check("壊れたファイルは空の集合から始める（クラッシュしない）", ReadState.count() == 0)
	f = FileAccess.open(OTHER_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": 99, "lines": [k1] }))
	f.close()
	ReadState._lines = {}
	ReadState._loaded = false
	c.check("版が違うファイルは読まない", ReadState.count() == 0 and not ReadState.is_read(k1))
	# 無効化（試遊用）
	_fresh(false)
	c.check("enabled=false：足せず・既読にならず・書かない（試遊は既読ファイルを読まず書かない）",
		not ReadState.mark(k1) and not ReadState.is_read(k1) and not ReadState.flush() and not FileAccess.file_exists(TEST_PATH)
			and ReadState.count() == 0)
	_fresh()

	# --- 2. 朝の保存には入れない・再挑戦／新しい周でも消えない ---
	c.check("既読は朝の保存（GameState／MorningSave）の項目ではない（seen_episodes とも別物）",
		not GameState.SAVED_FIELDS.has("read_lines") and not GameState.to_dict().has("read_state") and MorningSave.VERSION == 6)
	var p2 = _setup(t, 1, 2)
	_to_adjust(p2)
	var count_before_retry := ReadState.count()
	c.check("（前提）見えた行が既読になっている", count_before_retry >= 2)
	c.check("朝へ戻しても既読は消えない", p2.retry_from_morning(2) and ReadState.count() >= count_before_retry)
	p2._on_new_run_pressed()
	c.check("新しい周でも既読は消えない", ReadState.count() >= count_before_retry)
	p2.free()
	_fresh()

	# --- 3. スキップと手動の同一性：REACT・SERVE・PAY・SCENE_END を含む列で、GameState・帳簿・来店記録まで ---
	ScheduleData._episode_cache["thug/thug_01"] = _thug_scene()
	# 1周目：手で最後まで読む（既読にする）。最後のイベントまでの押下回数 K と状態を記録する
	var p3a = _setup(t, 31)
	_to_adjust(p3a)
	_serve(p3a)
	var kinds := []
	var manual_steps := 0
	while p3a.flow.runner.index < p3a.flow.runner.events.size() - 1:
		p3a._on_next_event_pressed()
		manual_steps += 1
	for ev in p3a.flow.runner.events:
		kinds.append(str(ev["type"]))
	var manual_state := _state(p3a)
	c.check("（前提）列に SERVE・REACT・SCENE_END・場所代の PAY を含む",
		kinds.has("SERVE") and kinds.has("REACT") and kinds.has("SCENE_END") and kinds.has("PAY"), str(kinds))
	c.check("（前提）手で最後まで読むと、事実が立ち・場所代が払われる（1回）",
		CustomerMemory.fact("thug", "k") == true and GameState.rent_paid_today)
	var money_manual: int = GameState.money
	var facts_manual: Dictionary = (GameState.customer_memory["thug"]["facts"] as Dictionary).duplicate()
	p3a.free()
	# 2周目：同じ手順の手動（比較用の基準）。既読は1周目のものが残っている
	var p3b = _setup(t, 31)
	_to_adjust(p3b)
	_serve(p3b)
	var manual_steps_b := 0
	while p3b.flow.runner.index < p3b.flow.runner.events.size() - 1:
		p3b._on_next_event_pressed()
		manual_steps_b += 1
	var manual_state_b := _state(p3b)
	p3b.free()
	# 3周目：スキップ
	var p3c = _setup(t, 31)
	_to_adjust(p3c)
	_serve(p3c)
	var skipped: int = p3c._on_skip_read_pressed()
	c.check("スキップが進めたイベント数は、[次のEvent]を最後まで押した回数と同じ", skipped == manual_steps and skipped == manual_steps_b and skipped >= 5,
		"%d / %d / %d" % [skipped, manual_steps, manual_steps_b])
	c.check("スキップ後の GameState・提供記録・帳簿・場所代の支払い・椀・位置が、手動と完全に同一（二重適用なし）",
		_state(p3c) == manual_state and _state(p3c) == manual_state_b)
	c.check("所持金・事実も1回だけ（スキップでも会計1回・事実1回）",
		GameState.money == money_manual and (GameState.customer_memory["thug"]["facts"] as Dictionary) == facts_manual)
	c.check("来店記録の提供は1杯のまま（served=1）", int(CustomerMemory.last_visit("thug")["served"]) == 1
		and (CustomerMemory.last_visit("thug")["grades"] as Array).size() == 1)
	c.check("最後のイベントで止まる（客の切り替わりをまたがない）", p3c.flow.runner.index == p3c.flow.runner.events.size() - 1)
	c.check("最後のイベントでは [既読スキップ] は無効・押しても進まない",
		p3c._btn_skip_read.disabled and p3c._on_skip_read_pressed() == 0)
	p3c.free()

	# --- 4. 止まる条件 ---
	# 未読の行：g3 だけ未読にして、g2 を通り過ぎ g3 で止まる
	_fresh()
	var p4 = _setup(t, 41)
	for text in ["g2", "g4"]:
		ReadState.mark(ReadState.line_key("talk", "チンピラ", "", text))
	p4._load_current_customer()   # 先頭（g1）から組み直す
	var steps_unread: int = p4._on_skip_read_pressed()
	c.check("未読の行（g3）の手前の既読（g2）は飛ばし、未読の行で止まる（その行は見えている）",
		steps_unread == 2 and str(p4.flow.runner.current()["text"]) == "g3", "%d / %s" % [steps_unread, str(p4.flow.runner.current())])
	c.check("止まった未読の行は既読になる（次回は飛ばせる）", ReadState.is_read(ReadState.line_key("talk", "チンピラ", "", "g3")))
	# 入力待ち：全部既読にして ADJUST（入力待ち）で止まる
	p4._on_skip_read_pressed()   # g4 は既読、ADJUST の文は未読 → ADJUST で止まる
	c.check("入力待ち（ADJUST）で止まる", str(p4.flow.runner.current()["type"]) == "ADJUST" and p4.flow.runner.status == EventRunner.Status.WAITING_INPUT)
	c.check("入力待ちでは [既読スキップ] は無効・押しても進まない", p4._btn_skip_read.disabled and p4._on_skip_read_pressed() == 0)
	p4.free()

	# 反応が未読：反応の文だけ未読にして REACT で止まる
	_fresh()
	var p4b = _setup(t, 31)
	_to_adjust(p4b)
	_serve(p4b)
	while p4b.flow.runner.index < p4b.flow.runner.events.size() - 1:
		p4b._on_next_event_pressed()   # 手で全部読む（既読にする）
	p4b.free()
	var reaction_key := ReadState.line_key("reaction", "チンピラ", "", "R:GOOD")
	c.check("（前提）反応文も既読になった", ReadState.is_read(reaction_key))
	ReadState._lines.erase(reaction_key)
	var p4c = _setup(t, 31)
	_to_adjust(p4c)
	_serve(p4c)
	var steps_reaction: int = p4c._on_skip_read_pressed()
	c.check("反応文が未読ならその行（REACT）で止まる（選ばれた反応文の本文で数える）",
		steps_reaction == 1 and str(p4c.flow.runner.current()["type"]) == "REACT" and p4c._current_reaction_text() == "R:GOOD")
	p4c.free()

	# 選択は決して飛ばさない
	_fresh()
	ScheduleData._episode_cache["thug/thug_01"] = _thug_scene({ "sets_facts": {},
		"choices": [ { "id": "message", "options": [ { "id": "yes", "label": "はい", "set": { "a": true } },
			{ "id": "no", "label": "いいえ", "set": { "a": false } } ] } ] })
	var pc = _setup(t, 31)
	_to_adjust(pc)
	_serve(pc)
	while not pc._is_in_story_choice() and pc.flow.runner.index < pc.flow.runner.events.size() - 1:
		pc._on_next_event_pressed()   # 手で CHOICE まで読む（本文までを既読にする）
	pc.free()
	var pc2 = _setup(t, 31)
	_to_adjust(pc2)
	_serve(pc2)
	pc2._on_skip_read_pressed()
	c.check("選択（CHOICE）の入力待ちで止まる。選択は記録されず、スキップは無効",
		pc2._is_in_story_choice() and CustomerMemory.choices_today("thug").is_empty() and pc2._btn_skip_read.disabled
			and pc2._on_skip_read_pressed() == 0 and CustomerMemory.choices_today("thug").is_empty())
	pc2.free()
	ScheduleData._episode_cache["thug/thug_01"] = _thug_scene()

	# ゲームオーバー（フェーズ切り替え）：場所代が払えないと、PAY で止まる（PAYは1回だけ）
	_fresh()
	var pg1 = _setup(t, 31)
	_to_adjust(pg1)
	_serve(pg1)
	while pg1.flow.runner.index < pg1.flow.runner.events.size() - 1:
		pg1._on_next_event_pressed()
	pg1.free()
	var pg2 = _setup(t, 31)
	_to_adjust(pg2)
	_serve(pg2)
	GameState.money = 0
	var steps_over: int = pg2._on_skip_read_pressed()
	c.check("場所代が払えずゲームオーバーになると、フェーズの切り替えで止まる（PAYの適用は1回・所持金は負にならない）",
		GameState.phase == GameState.Phase.GAME_OVER and GameState.money >= 0 and steps_over >= 1 and not GameState.rent_paid_today)
	pg2.free()

	# 上限：既読の行が300あっても、1回に進めるのは SKIP_READ_LIMIT まで
	_fresh()
	var plimit = _setup(t, 7)
	var long_events := []
	for i in range(300):
		long_events.append({ "type": "TEXT", "text": "長い行%d" % i })
		ReadState.mark(ReadState.line_key("narration", "", "", "長い行%d" % i))
	plimit.flow.set_runner(long_events)
	var steps_limit: int = plimit._on_skip_read_pressed()
	c.check("上限（%d回）で止まる" % plimit.SKIP_READ_LIMIT, steps_limit == plimit.SKIP_READ_LIMIT
		and plimit.flow.runner.index == plimit.SKIP_READ_LIMIT)
	plimit.free()

	# 無効（試遊）：既読にならず、毎回その行で止まる
	_fresh(false)
	var poff = _setup(t, 7)
	var steps_off: int = poff._on_skip_read_pressed()
	c.check("ReadState が無効だと、全部未読として1行ずつ止まる・既読の集合は増えない",
		steps_off == 1 and ReadState.count() == 0 and not ReadState.flush())
	poff.free()

	# --- 5. 書き出す時点：日の終わり・結果画面・終了 ---
	_fresh()
	var p5 = _setup(t, 51)
	_to_adjust(p5)
	c.check("見えただけではファイルに書かない", not FileAccess.file_exists(TEST_PATH))
	p5._on_day_ending()
	c.check("日の終わりに書き出す", FileAccess.file_exists(TEST_PATH)
		and (JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))["lines"] as Array).size() == ReadState.count())
	DirAccess.remove_absolute(TEST_PATH)
	ReadState.mark(ReadState.line_key("narration", "", "", "結果画面の前"))
	p5._set_runner_for_phase(GameState.Phase.RESULT)
	c.check("結果画面に入るときに書き出す", FileAccess.file_exists(TEST_PATH))
	DirAccess.remove_absolute(TEST_PATH)
	ReadState.mark(ReadState.line_key("narration", "", "", "終了の前"))
	p5.free()
	c.check("終了（パネルが木から外れるとき）に書き出す", FileAccess.file_exists(TEST_PATH))

	# --- 6. 実際の既読ファイルには触れていない ---
	c.check("実際の user://read_state.json を作らず・書き換えていない",
		FileAccess.file_exists(REAL_PATH) == real_existed and (not real_existed or FileAccess.get_modified_time(REAL_PATH) == real_time))

	_fresh()
	ReadState.reset("user://test_read_state.json")
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
