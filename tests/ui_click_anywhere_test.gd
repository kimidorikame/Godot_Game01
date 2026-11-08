extends RefCounted
## UI準備T：ボタンなど、画面のどの部品も受け取らなかった左クリックでも、クリック待ちの会話を進める（game_root._unhandled_input）。
## 本物のマウスイベント（Viewport.push_input。当たり判定を通す）で確かめる。場面：開店（Day2・宵の口・新人警官）の来店の会話。
## 対象：右の操作領域の空いた場所・左右のあいだの隙間で進む／押せるボタン・押せないボタン・タブの上では進まない／
## 椀を作っている最中・選択肢・スマホ・ログを開いているときは進まない／右クリック・ホイールでは進まない／会話枠のクリックは今までどおり1行ずつ。


func _event_at(viewport: Viewport, pos: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		viewport.push_input(ev, true)


func _click(root: UiGameRoot, pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_event_at(root.get_viewport(), pos, button)


## 当たるコントロール（無ければ null）。
func _hit(root: UiGameRoot, pos: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.get_viewport().push_input(motion, true)
	return root.get_viewport().gui_get_hovered_control()


## rect の中で、当たるのが frame（見た目の枠）そのものの点（ボタンや一覧の上ではない空いた場所）。
func _empty_point(root: UiGameRoot, frame: Control) -> Vector2:
	var rect := frame.get_global_rect()
	for iy in range(30):
		for ix in range(20):
			var pos := rect.position + Vector2(rect.size.x * (ix + 0.5) / 20.0, rect.size.y * (iy + 0.5) / 30.0)
			if _hit(root, pos) == frame:
				return pos
	return Vector2(-1, -1)


## 会話の位置（runner の位置と、会話枠の文）。
func _where(root: UiGameRoot) -> String:
	return "%d|%s" % [root.session.flow.runner.index, str(root.left.get_node("%DialogueText").text)]


func _open(t: SceneTree) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["nam_prik_pao", "offal", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	# 来店の会話を長めにする（クリック待ちの行を何度か作る）
	for i in range(5):
		s.flow.runner.events.insert(0, { "type": "GREET", "customer": "officer", "text": "（会話の行%d・仮）" % (5 - i) })
	root.close_overlay()
	s.notify_changed()
	return root


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root := _open(t)
	var s: PlaySession = root.session
	var pane: UiPaneKaiten = root.pane_kaiten
	var left := root.left
	c.check("場面：開店・来店の会話のクリック待ち（▼）。右は鍋のタブ", s.flow.runner.status == EventRunner.Status.PLAYING
		and left.is_waiting_click() and pane.visible and pane.pot.visible, "%s st=%d mark=%s ch=%s next=%s wait=%s pv=%s pot=%s" % [_where(root), s.flow.runner.status,
			str(left.get_node("%PageMark").visible), str(left.get_node("%Choices").visible), str(s.can_next_event()), str(s.is_waiting_input()), str(pane.visible), str(pane.pot.visible)])

	# --- 1. 右の操作領域の空いた場所・左右の隙間で進む ---
	var empty := _empty_point(root, pane)
	c.check("右の操作領域（鍋のタブ）に空いた場所がある（枠そのものに当たる点）", empty.x >= 0.0, str(empty))
	var before := _where(root)
	_click(root, empty)
	var after_right := _where(root)
	c.check("右の操作領域の空いた場所を押すと、会話が1行進む", after_right != before and s.flow.runner.index == int(before.split("|")[0]) + 1,
		before + " → " + after_right)
	var gap := Vector2(828, 300)   # 左の列（〜820）と右の枠（836〜）のあいだ
	var gh := _hit(root, gap)
	c.check("左右のあいだの隙間には、どの部品も当たらない", gh == null, str(gh) + (" " + str(gh.get_path()) + " " + str(gh.get_global_rect()) + " " + str(gh.get_parent()) if gh != null else ""))
	before = _where(root)
	_click(root, gap)
	c.check("左右のあいだの隙間を押しても進む", _where(root) != before, before + " → " + _where(root))

	# --- 2. ボタン・タブの上では進まない（押せないボタンも） ---
	var pot_tab: Button = pane.get_node("%PotTab")
	before = _where(root)
	_click(root, pot_tab.get_global_rect().get_center())
	c.check("タブ（鍋。押せる）の上を押しても進まない", _where(root) == before and pane.pot.visible, _where(root))
	var water: Button = pane.pot.get_node("%WaterButton")
	var dashi: Button = pane.pot.get_node("%DashiButton")
	c.check("鍋の水は押せない（残りが多い）・だしは押せる（だしがある）", water.disabled and water.is_visible_in_tree())
	before = _where(root)
	var soup_before: Dictionary = GameState.soup.duplicate(true)
	_click(root, water.get_global_rect().get_center())
	c.check("押せないボタン（水）の上を押しても進まない・何も変わらない", _where(root) == before and GameState.soup == soup_before, _where(root))
	var topping_tab: Button = pane.get_node("%ToppingTab")
	_click(root, topping_tab.get_global_rect().get_center())
	c.check("タブ（トッピング）を押すとタブが替わるだけで、会話は進まない", _where(root) == before and pane.topping.visible, _where(root))
	var item: Control = pane.topping.get_node("%Grid").get_child(0)
	var main: Button = item.get_node("MainButton")
	c.check("会話のあいだの具材ボタンは押せない", main.disabled and main.is_visible_in_tree())
	_click(root, main.get_global_rect().get_center())
	c.check("押せない具材ボタンの上を押しても進まない", _where(root) == before, _where(root))
	var serve: Button = pane.topping.get_node("%ServeButton")
	_click(root, serve.get_global_rect().get_center())
	c.check("押せない提供ボタンの上を押しても進まない", serve.disabled and _where(root) == before, _where(root))
	var topping_empty := _empty_point(root, pane)
	before = _where(root)
	_click(root, topping_empty)
	c.check("トッピングのタブの空いた場所（椀の絵などの見た目の枠の上）を押すと進む", topping_empty.x >= 0.0 and _where(root) != before,
		str(topping_empty) + " " + before + " → " + _where(root))
	_click(root, pot_tab.get_global_rect().get_center())

	# --- 3. 右クリック・ホイールでは進まない ---
	before = _where(root)
	_click(root, empty, MOUSE_BUTTON_RIGHT)
	_click(root, empty, MOUSE_BUTTON_WHEEL_DOWN)
	_click(root, empty, MOUSE_BUTTON_WHEEL_UP)
	c.check("右クリック・ホイールでは進まない", _where(root) == before, _where(root))

	# --- 4. スマホ・ログを開いているあいだは進まない ---
	root.open_phone("news")
	c.check("スマホを開いた（右の枠と入れ替わる）", root.overlay == "phone" and root.pane_phone.visible)
	_click(root, gap)
	var phone_empty := _empty_point(root, root.pane_phone)
	if phone_empty.x >= 0.0:
		_click(root, phone_empty)
	c.check("スマホを開いているあいだは、隙間やスマホの枠を押しても進まない", _where(root) == before and root.pane_phone.visible, _where(root))
	root.close_overlay()
	left.toggle_log()
	c.check("ログを開いた", left.is_log_open())
	_click(root, gap)
	_click(root, _empty_point(root, pane))
	c.check("ログを開いているあいだは、右や隙間を押しても進まない（ログも開いたまま）", _where(root) == before and left.is_log_open(), _where(root))
	left.close_log()

	# --- 5. 会話枠のクリックは今までどおり（1回で1行。右の処理と二重にならない） ---
	before = _where(root)
	load("res://tests/ui_autoplay.gd").click(left.get_node("%DialogueBox"))
	c.check("会話枠のクリック：1回で1行だけ進む（二重に進まない）", s.flow.runner.index == int(before.split("|")[0]) + 1, before + " → " + _where(root))

	# --- 6. 選択肢が出ているときは進まない ---
	var at := s.flow.runner.index
	s.flow.runner.events.insert(at + 1, { "type": "CHOICE", "customer": "officer", "choice_id": "test_choice",
		"options": [{ "id": "a", "label": "はい" }, { "id": "b", "label": "いいえ" }] })
	_click(root, empty)
	c.check("選択肢（CHOICE）まで進んだ", s.is_in_story_choice(), _where(root))
	before = _where(root)
	_click(root, empty)
	_click(root, gap)
	c.check("選択肢が出ているあいだは、右や隙間を押しても進まない", _where(root) == before and s.is_in_story_choice() and not left.is_waiting_click(), _where(root))
	root.queue_free()

	# --- 7. 椀を作っている最中（入力待ち）は進まない ---
	root = _open(t)
	s = root.session
	pane = root.pane_kaiten
	var guard := 0
	while not s.is_choosing_ingredients() and guard < 20:
		guard += 1
		_click(root, Vector2(828, 300))
	c.check("隙間のクリックだけで、椀を作るところ（ADJUST）まで進められる", s.is_choosing_ingredients() and pane.topping.visible, _where(root))
	before = _where(root)
	_click(root, Vector2(828, 300))
	_click(root, _empty_point(root, pane))
	c.check("椀を作っている最中は、右や隙間を押しても進まない（入力待ちのまま）", _where(root) == before and s.is_choosing_ingredients()
		and not root.left.is_waiting_click(), _where(root))
	root.queue_free()
	GameState.reset_for_new_game()
	return c.finish()
