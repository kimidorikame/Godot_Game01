extends RefCounted
## 本番UI（UI準備B④）：閉店（今夜の結果と修繕基金）と全面（仕込み・結果・ゲームオーバー）の検証。
## 対象：シーンの寸法（寸法表 SCREENS_UI_LAYOUT §7・§8、4px以内。ボタンは始点と幅）、全面の間は左側と右の枠を隠すこと、
## 基金は閉店の語りを読み終えてから積めること、「次の日へ」＝advance_phase 2回、仕込みの点と「開店する」、
## 結果の3ページと出口、ゲームオーバーの種類と額（PlaySession.game_over_info）と「やり直す」。
## どれもボタンの pressed（全面の仕込みはクリック）だけで操作する。

const TOL := 4.0


func _near(a: Rect2, b: Rect2, tol: float = TOL) -> bool:
	return absf(a.position.x - b.position.x) <= tol and absf(a.position.y - b.position.y) <= tol \
		and absf(a.size.x - b.size.x) <= tol and absf(a.size.y - b.size.y) <= tol


func _at(node: Control, pos: Vector2, width: float) -> bool:
	return node.get_global_position().distance_to(pos) <= TOL and absf(node.size.x - width) <= TOL


func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _press(button: BaseButton) -> bool:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


## 本物のマウスの左クリック（当たり判定を通る。台本 tests/ui_autoplay.gd の click と同じ）。
func _click(control: Control) -> void:
	load("res://tests/ui_autoplay.gd").click(control)


func _root(t: SceneTree, day: int = 2) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = day
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	return root


## 閉店の語りを読み、所持金を20にしてから「次の日へ」を押す（翌朝の運営費が払えずゲームオーバーになる）。
func _to_next_morning_broke(root: UiGameRoot) -> void:
	var s := root.session
	s.flow.force_phase(GameState.Phase.CLOSE)
	var guard := 0
	while not s.flow.is_runner_done() and guard < 20:
		guard += 1
		root.left.advance()
	GameState.money = 20
	_press(root.pane_close.get_node("%NextButton"))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. シーンが読み込める ---
	for path in ["res://scenes/ui/pane_close.tscn", "res://scenes/ui/full_prep.tscn", "res://scenes/ui/full_result.tscn",
			"res://scenes/ui/full_gameover.tscn"]:
		var packed: PackedScene = load(path)
		var inst = packed.instantiate() if packed != null else null
		c.check("%s を読み込める" % path.get_file(), inst != null)
		if inst != null:
			inst.free()

	# --- 2. 仕込み（全面）：市場を出たあと ---
	var root := _root(t)
	var s: PlaySession = root.session
	s.flow.force_phase(GameState.Phase.PREP)
	var guard := 0
	while not s.is_in_market() and guard < 60:
		guard += 1
		if s.is_in_prep_tier():
			s.choose_prep_tier("medium")
		else:
			root.left.advance()
	c.check("市場の画面では全面を出さない", s.is_in_market() and not root.full_prep.visible and root.left.visible)
	_press(root.pane_market.get_node("%ExitButton"))
	var prep: UiFullPrep = root.full_prep
	c.check("市場を出ると全面の仕込み：左側と右の枠を隠す", prep.visible and not root.left.visible and not root.right_pane.visible)
	c.check("「仕込み中」と「鍋の素 中・11杯・濃さ3」", prep.get_node("Title").text == "仕込み中"
		and prep.get_node("%Detail").text == "鍋の素 中・%d杯・濃さ3" % int(s.today_base()["servings"]), prep.get_node("%Detail").text)
	c.check("点は1つ目（市場を出た）が点き、「開店する」はまだ出ない", prep.lit_dots() == 1 and not prep.get_node("%OpenButton").visible)
	# 自動：クリックしなくても、約0.7秒ごとに点が1つずつ点く（テストでは時間を手で送る）
	prep.auto_advance = false
	prep.tick(UiFullPrep.STEP_SECONDS * 0.5)
	c.check("0.7秒たつ前は点は増えない", prep.lit_dots() == 1)
	prep.tick(UiFullPrep.STEP_SECONDS * 0.5)
	c.check("0.7秒たつと点が2つになる（クリックなし）", prep.lit_dots() == 2 and not prep.get_node("%OpenButton").visible)
	_click(prep)
	c.check("全面をクリック → すぐ全部の点が点く（3つ・列を読み終える）", prep.lit_dots() == 3 and s.flow.is_runner_done())
	guard = 0
	while not s.flow.is_runner_done() and guard < 10:
		guard += 1
		_click(prep)
	prep.tick(UiFullPrep.STEP_SECONDS * 2.0)
	c.check("全部ついたら時間がたっても進まず、「開店する」(540,440)・幅200が出る", prep.lit_dots() == 3 and prep.get_node("%OpenButton").visible
		and _at(prep.get_node("%OpenButton"), Vector2(540, 440), 200))
	_press(prep.get_node("%OpenButton"))
	c.check("「開店する」→ flow.advance_phase で開店（OPEN）。全面は消え、左側が戻る",
		GameState.phase == GameState.Phase.OPEN and not prep.visible and root.left.visible and root.pane_kaiten.visible)
	root.queue_free()

	# --- 3. 閉店（今夜の結果と修繕基金）---
	root = _root(t)
	s = root.session
	s.flow.force_phase(GameState.Phase.CLOSE)
	_sort(root)
	var close: UiPaneClose = root.pane_close
	c.check("閉店の右の枠：見出し「今夜の結果」", close.visible and close.get_node("%Header/Title").text == "今夜の結果")
	var boxes := { "SalesBox": Rect2(852, 86, 388, 99), "GradesBox": Rect2(852, 195, 388, 96), "%FundBox": Rect2(852, 300, 388, 233) }
	for box_name in boxes:
		c.check("閉店：%s の位置と大きさ（寸法表どおり）" % box_name, _near(close.get_node(box_name).get_global_rect(), boxes[box_name]),
			str(close.get_node(box_name).get_global_rect()))
	var next: Button = close.get_node("%NextButton")
	c.check("「次の日へ」(852,634)・幅388、閉店の語りの途中は押せない", _at(next, Vector2(852, 634), 388) and next.disabled)
	c.check("語りの途中は基金を積めない（一文だけ）", close.get_node("%FundWait").visible and not close.get_node("%Targets").visible)
	var result := s.tonight_result()
	c.check("売上・提供／注文", close.get_node("%SalesValue").text == "¥%d" % int(result["sales"])
		and close.get_node("%ServedLabel").text == "提供 %d杯 / 注文%d杯" % [int(result["served_cups"]), int(result["ordered_cups"])])
	guard = 0
	while not s.flow.is_runner_done() and guard < 20:
		guard += 1
		root.left.advance()
	var view := s.fund_view()
	c.check("語りを読み終えると基金の対象・積むボタン", bool(view["available"]) and close.get_node("%Targets").visible
		and close.get_node("%Steps").visible and not next.disabled)
	var targets: VBoxContainer = close.get_node("%Targets")
	var first_target: Dictionary = view["targets"][0]
	c.check("対象の行：選んでいる対象に▶と強調色・進捗「0/200」の形", targets.get_child(0).get_node("Mark").text == "▶"
		and targets.get_child(0).get_node("Name").text == str(first_target["label"])
		and targets.get_child(0).get_node("State").text == "%d/%d" % [int(first_target["paid"]), int(first_target["price"])])
	var steps: HBoxContainer = close.get_node("%Steps")
	c.check("積むボタン「+10 積む」「+30 積む」", steps.get_child(0).text == "+10 積む" and steps.get_child(1).text == "+30 積む")
	var money := GameState.money
	_press(steps.get_child(0))
	c.check("「+10 積む」→ contribute_fund(10)：所持金が10減り、今夜の額が出る", GameState.money == money - 10
		and int(s.fund_view()["paid_tonight"]) == 10)
	var day := GameState.day_count
	_press(next)
	c.check("「次の日へ」→ advance_phase 2回（CLOSE→NEXT_DAY→WAKE）：翌朝・右の枠は朝",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == day + 1 and root.pane_morning.visible)
	root.queue_free()

	# --- 4. 結果（全面）：最終日の閉店のあと ---
	root = _root(t, GameState.FINAL_DAY)
	s = root.session
	s.flow.force_phase(GameState.Phase.CLOSE)
	guard = 0
	while not s.flow.is_runner_done() and guard < 20:
		guard += 1
		root.left.advance()
	next = root.pane_close.get_node("%NextButton")
	c.check("最終日の閉店：ボタンは「結果を見る」", next.text == "結果を見る" and not next.disabled)
	_press(next)
	_sort(root)
	var res: UiFullResult = root.full_result
	c.check("結果（RESULT）の全面：左側と右の枠を隠す", GameState.phase == GameState.Phase.RESULT and res.visible
		and not root.left.visible and not root.right_pane.visible)
	c.check("結果の枠 (260,80) 760×560", _near(res.get_node("%Frame").get_global_rect(), Rect2(260, 80, 760, 560)))
	var tabs: Control = res.get_node("%Tabs")
	c.check("ページのタブ：(262,82) から1つ幅252（1 成績／2 目標／3 物語）", _at(tabs.get_child(0), Vector2(262, 82), 252)
		and _at(tabs.get_child(1), Vector2(514, 82), 252) and tabs.get_child(2).text == "3 物語")
	c.check("「タイトルへ」(640,578)・「次へ」(826,578)、1つ幅170", _at(res.get_node("%TitleButton"), Vector2(640, 578), 170)
		and _at(res.get_node("%NextButton"), Vector2(826, 578), 170))
	c.check("1ページ目は成績（現行の結果画面の文と同じ）", res.get_node("%Body").text == str(s.flow.runner.events[0]["text"])
		and res.get_node("%Body").text.begins_with("◆結果：店の成績"))
	c.check("「タイトルへ」はタイトル画面（フェーズ6）まで押せない", (res.get_node("%TitleButton") as Button).disabled)
	_press(res.get_node("%NextButton"))
	c.check("「次へ」で2ページ目（目標）", res.page == 1 and res.get_node("%Body").text == str(s.flow.runner.events[1]["text"]))
	c.check("2ページ目では出口を出さない", not res.get_node("%Exits").visible)
	_press(tabs.get_child(2))
	c.check("タブで3ページ目（物語）・出口（もう一度／最後の朝から／新しい周）・「次へ」は押せない",
		res.page == 2 and res.get_node("%Body").text == str(s.flow.runner.events[2]["text"]) and res.get_node("%Exits").visible
			and (res.get_node("%NextButton") as Button).disabled)
	_press(res.get_node("%NewRunButton"))
	c.check("「新しい周」→ new_run：Day1の朝から", GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
		and not res.visible and root.left.visible)
	root.queue_free()

	# --- 5. ゲームオーバー（全面）と、種類と額 ---
	# 実際の流れ：Day2の閉店から翌朝（Day3）へ進み、朝の運営費が払えない。払えなかった朝は記録されない。
	root = _root(t, 2)
	s = root.session
	c.check("ゲームオーバー前は game_over_info は空（available=false）", not bool(s.game_over_info()["available"]))
	_to_next_morning_broke(root)
	var info := s.game_over_info()
	c.check("game_over_info：運営費・必要額・そのときの所持金・日・フェーズ（朝）",
		bool(info["available"]) and str(info["kind"]) == "daily_cost" and int(info["amount"]) == GameState.DAILY_OPERATING_COST
			and int(info["money"]) == 20 and int(info["day"]) == 3 and int(info["phase"]) == GameState.Phase.WAKE, str(info))
	_sort(root)
	var over: UiFullGameOver = root.full_gameover
	c.check("ゲームオーバーの全面：左側と右の枠を隠す", GameState.phase == GameState.Phase.GAME_OVER and over.visible
		and not root.left.visible)
	c.check("枠 (320,234) 640×251", _near(over.get_node("%Frame").get_global_rect(), Rect2(320, 234, 640, 251)))
	c.check("何日目のどこで何が払えなかったかと所持金", over.get_node("%Detail").text
		== "Day 3 の朝に、運営費 ¥%d が払えなかった。
所持金 ¥20" % GameState.DAILY_OPERATING_COST, over.get_node("%Detail").text)
	c.check("払えなかったDay3の朝は記録されず、戻れる最後の朝はDay2", not GameState.morning_snapshots.has(3)
		and GameState.morning_snapshots.has(2))
	var retry: Button = over.get_node("%RetryButton")
	c.check("「Day 2 の朝からやり直す」（retry で戻る先の日）(409,419)・「終わる」(648,419)、1つ幅223、「終わる」は押せない",
		retry.text == "Day 2 の朝からやり直す" and not retry.disabled and _at(retry, Vector2(409, 419), 223)
			and _at(over.get_node("%QuitButton"), Vector2(648, 419), 223) and (over.get_node("%QuitButton") as Button).disabled,
		retry.text)
	_press(retry)
	c.check("「やり直す」→ retry：表示どおりDay2の朝へ戻り、ゲームオーバーの中身は消える", GameState.phase == GameState.Phase.WAKE
		and GameState.day_count == 2 and not over.visible and not bool(s.game_over_info()["available"]))
	root.queue_free()

	# 戻る先がDay1の朝だけ：Day1の閉店から翌朝（Day2）へ進み、運営費が払えない
	root = _root(t, 1)
	s = root.session
	_to_next_morning_broke(root)
	over = root.full_gameover
	retry = over.get_node("%RetryButton")
	c.check("Day1の朝の記録だけ：「Day 1 の朝からやり直す」", GameState.phase == GameState.Phase.GAME_OVER
		and GameState.morning_snapshots.keys() == [1] and retry.text == "Day 1 の朝からやり直す" and not retry.disabled, retry.text)
	_press(retry)
	c.check("→ retry でDay1の朝へ戻る", GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1)
	root.queue_free()

	# 朝の記録が1つも無い：やり直しは Day1 の朝から（記録が無いので新しい周と同じ動作）
	root = _root(t, 2)
	s = root.session
	GameState.morning_snapshots.clear()
	GameState.money = 20
	s.flow.force_phase(GameState.Phase.WAKE)
	over = root.full_gameover
	retry = over.get_node("%RetryButton")
	var exits := s.exits()
	c.check("朝の記録が無い：同じ朝からは戻れず（can_retry=false）、「Day 1 の朝からやり直す」は押せる（run_again＝新しい周と同じ）",
		GameState.phase == GameState.Phase.GAME_OVER and not bool(exits["can_retry"]) and bool(exits["run_again_is_new_run"])
			and retry.text == "Day 1 の朝からやり直す" and not retry.disabled, retry.text)
	_press(retry)
	c.check("→ run_again（新しい周）でDay1の朝から", GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
		and GameState.money == GameState.INITIAL_MONEY - GameState.DAILY_OPERATING_COST)
	root.queue_free()
	return c.finish()
