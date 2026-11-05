extends RefCounted
## UI準備P-5：鍋の濃さの目盛り（「出せない｜薄い｜適正｜濃い」の6区画と今の位置の▲）と、だし・水を押す前の「押した後の値」。
## 表示だけ（濃さの効き方・水とだしの量・判定は変えない）。どれもボタンの pressed（とマウスの出入りのシグナル）だけで操作する。

const TOL := 4.0


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


## 本番UIのルートを起動し、新人警官の1杯目の入力待ち（ADJUST）まで進めて、鍋タブを開く（tests/ui_kaiten_test.gd と同じ形）。
func _open_pot(t: SceneTree, remaining: int, strength: int, dashi: int) -> UiGameRoot:
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.add_inventory("nam_prik_pao", 9)
	GameState.add_inventory("offal", 9)
	GameState.set_soup("bone_broth", ["meaty"], remaining, strength, 2)
	GameState.dashi_units = dashi
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	root.close_overlay()
	s.notify_changed()
	var guard := 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root.left.advance()
	_press(root.pane_kaiten.get_node("%PotTab"))
	_sort(root)
	return root


func _set_pot(s: PlaySession, strength: int, remaining: int = -1) -> void:
	GameState.soup["strength"] = strength
	if remaining >= 0:
		GameState.soup["remaining_servings"] = remaining
	s.notify_changed()


func _center_x(node: Control) -> float:
	return node.get_global_rect().get_center().x


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root := _open_pot(t, 8, 3, 1)
	var s: PlaySession = root.session
	var pot: UiKaitenPot = root.pane_kaiten.pot
	var gauge: Control = pot.get_node("%Gauge")
	var marker: Label = pot.get_node("%Marker")
	var preview: Label = pot.get_node("%Preview")
	var note: Label = pot.get_node("%StrengthNote")
	var dashi: Button = pot.get_node("%DashiButton")
	var water: Button = pot.get_node("%WaterButton")
	var warn: Color = pot.get_theme_color(&"warn", &"UiPalette")
	var accent: Color = pot.get_theme_color(&"accent", &"UiPalette")
	c.check("鍋タブを開いた（椀を作っている最中でも鍋を触れる）", pot.visible and s.can_touch_pot())

	# --- 1. 目盛りの区画と「適正」の枠 ---
	var cells_ok := true
	for i in range(6):
		var cell: ColorRect = gauge.get_node("Cell%d" % i)
		cells_ok = cells_ok and absf(cell.get_global_rect().position.x - (852.0 + i * 65.0)) <= TOL and absf(cell.size.x - 63.0) <= TOL \
			and absf(cell.get_global_rect().position.y - 178.0) <= TOL
	c.check("目盛り：6区画（濃さ0〜5）・(852,178) から 63幅・間隔65（今の Scale の位置。幅388）", cells_ok
		and not pot.has_node("%Scale"), str(gauge.get_node("Cell1").get_global_rect()))
	var frame: Control = pot.get_node("%FitFrame")
	c.check("「適正」の枠は濃さ2〜4の区画を囲む", frame.get_global_rect().position.x <= gauge.get_node("Cell2").get_global_rect().position.x
		and frame.get_global_rect().end.x >= gauge.get_node("Cell4").get_global_rect().end.x
		and frame.get_global_rect().position.x > gauge.get_node("Cell1").get_global_rect().end.x
		and frame.get_global_rect().end.x < gauge.get_node("Cell5").get_global_rect().position.x)
	c.check("区画の言葉：出せない・薄い・適正・濃い", gauge.get_node("WordZero").text == "出せない" and gauge.get_node("WordThin").text == "薄い"
		and gauge.get_node("WordFit").text == "適正" and gauge.get_node("WordThick").text == "濃い")
	c.check("区画の色：出せない＝濃い注意色・薄い／濃い＝薄い注意色・適正＝薄い良い色",
		(gauge.get_node("Cell0") as ColorRect).color.is_equal_approx(Color(warn, 0.35))
			and (gauge.get_node("Cell1") as ColorRect).color.is_equal_approx(Color(warn, 0.16))
			and (gauge.get_node("Cell5") as ColorRect).color.is_equal_approx(Color(warn, 0.16))
			and (gauge.get_node("Cell3") as ColorRect).color.is_equal_approx(Color(pot.get_theme_color(&"good", &"UiPalette"), 0.16)))

	# --- 2. 濃さ0〜5で、▲が対応する区画の真ん中にある・色 ---
	var marks_ok := true
	var detail := ""
	for v in range(6):
		_set_pot(s, v)
		var cell: Control = gauge.get_node("Cell%d" % v)
		var want: Color = warn if v in [0, 1, 5] else accent
		var ok: bool = absf(_center_x(marker) - _center_x(cell)) <= 1.5 and int(marker.get_meta("value")) == v \
			and marker.get_theme_color(&"font_color").is_equal_approx(want) and marker.text == "▲"
		if not ok:
			marks_ok = false
			detail = "濃さ%d: ▲の中心 %d・区画の中心 %d" % [v, _center_x(marker), _center_x(cell)]
	c.check("濃さ0〜5：▲は濃さの区画の真ん中の下（塗りつぶしではない）。0・1・5は注意色、2〜4は強調色", marks_ok, detail)
	_set_pot(s, 0)
	c.check("濃さ0：注意文「濃さ0では提供できません」（UI準備P-5で足した）", note.visible and note.text == "濃さ0では提供できません", note.text)
	_set_pot(s, 1)
	c.check("濃さ1：注意文は今のまま「濃さ1は評価が1段階下がります」", note.visible and note.text == "濃さ1は評価が1段階下がります", note.text)
	_set_pot(s, 3)
	c.check("濃さ3：注意文は出さない", not note.visible)

	# --- 3. だし：押した後の値 ---
	_set_pot(s, 3, 8)
	c.check("だし（押せる）：「濃さ3→5」", not dashi.disabled and dashi.get_node("Effect").text == "濃さ3→5", dashi.get_node("Effect").text)
	_set_pot(s, 4)
	c.check("だし（5を超えるので押せない）：固定の文「濃さ +2」でグレー", dashi.disabled and dashi.get_node("Effect").text == "濃さ +2")
	GameState.dashi_units = 0
	_set_pot(s, 1)
	c.check("だし（だしが無いので押せない）：固定の文「濃さ +2」", dashi.disabled and dashi.get_node("Effect").text == "濃さ +2")
	GameState.dashi_units = 1
	_set_pot(s, 1)
	c.check("だし（濃さ1）：「濃さ1→3」", not dashi.disabled and dashi.get_node("Effect").text == "濃さ1→3")

	# --- 4. 水：押した後の値 ---
	_set_pot(s, 3, 8)
	c.check("水（押せる）：「濃さ3→1」「残り8→10杯」", not water.disabled and water.get_node("Effect").text == "濃さ3→1"
		and water.get_node("Effect2").text == "残り8→10杯" and water.get_node("Effect").visible and water.get_node("Effect2").visible,
		"%s / %s" % [water.get_node("Effect").text, water.get_node("Effect2").text])
	_set_pot(s, 3, 13)
	c.check("水（残りが多くて押せない）：説明を出さずにグレー（今の仕様）", water.disabled and not water.get_node("Effect").visible
		and not water.get_node("Effect2").visible)
	_set_pot(s, 1, 8)
	c.check("水（濃さ1。0を下回るので押せない）：説明を出さない", water.disabled and not water.get_node("Effect").visible)

	# --- 4b. ボタンの文の色：押した後が適正の外（0・1・5）なら注意色（UI準備P2。タッチ操作でも分かるように）---
	var dashi_fx: Label = dashi.get_node("Effect")
	var water_fx: Label = water.get_node("Effect")
	_set_pot(s, 3, 8)
	c.check("濃さ3：だし「濃さ3→5」は注意色（5＝濃い）・水「濃さ3→1」も注意色（1＝薄い）",
		dashi_fx.text == "濃さ3→5" and dashi_fx.get_theme_color(&"font_color").is_equal_approx(warn)
			and water_fx.text == "濃さ3→1" and water_fx.get_theme_color(&"font_color").is_equal_approx(warn))
	c.check("水の「残り8→10杯」は色を変えない（濃さの文だけ）", not (water.get_node("Effect2") as Label).has_theme_color_override(&"font_color"))
	_set_pot(s, 1, 8)
	c.check("濃さ1：だし「濃さ1→3」は適正の内なので型の色のまま（注意色にしない）",
		dashi_fx.text == "濃さ1→3" and not dashi_fx.has_theme_color_override(&"font_color")
			and not dashi_fx.get_theme_color(&"font_color").is_equal_approx(warn))
	_set_pot(s, 4, 8)
	c.check("濃さ4：水「濃さ4→2」は適正の内なので型の色のまま",
		water_fx.text == "濃さ4→2" and not water_fx.has_theme_color_override(&"font_color"))
	_set_pot(s, 2, 8)
	c.check("濃さ2：水「濃さ2→0」（出せない）は注意色", water_fx.text == "濃さ2→0" and water_fx.get_theme_color(&"font_color").is_equal_approx(warn))
	_set_pot(s, 4, 8)
	c.check("押せないだし（濃さ4）は固定の「濃さ +2」で、注意色にしない", dashi.disabled and dashi_fx.text == "濃さ +2"
		and not dashi_fx.has_theme_color_override(&"font_color"))

	# --- 5. マウスを乗せた間だけ、押した後の位置の△ ---
	_set_pot(s, 3, 8)
	dashi.mouse_entered.emit()
	c.check("だしに乗せる：△が濃さ5の区画（減点の側なので注意色）", preview.visible and int(preview.get_meta("value")) == 5
		and absf(_center_x(preview) - _center_x(gauge.get_node("Cell5"))) <= 1.5 and preview.get_theme_color(&"font_color").is_equal_approx(warn))
	c.check("△が出ていても、▲は今の位置（濃さ3）のまま", int(marker.get_meta("value")) == 3)
	dashi.mouse_exited.emit()
	c.check("だしから外す：△は消える", not preview.visible)
	water.mouse_entered.emit()
	c.check("水に乗せる：△が濃さ1の区画（注意色）", preview.visible and int(preview.get_meta("value")) == 1
		and preview.get_theme_color(&"font_color").is_equal_approx(warn))
	water.mouse_exited.emit()
	_set_pot(s, 1, 8)
	dashi.mouse_entered.emit()
	c.check("濃さ1でだしに乗せる：△は濃さ3（適正なので強調色）", preview.visible and int(preview.get_meta("value")) == 3
		and preview.get_theme_color(&"font_color").is_equal_approx(accent))
	dashi.mouse_exited.emit()
	_set_pot(s, 3, 13)
	water.mouse_entered.emit()
	c.check("押せないボタン（水）に乗せても△は出さない", not preview.visible)
	water.mouse_exited.emit()

	# --- 6. 予告の値と、実際に押した結果が一致する ---
	_set_pot(s, 3, 8)
	var view := s.pot_view()
	_press(water)
	c.check("水：予告（after_water）＝押した結果（濃さ・残り）", int(GameState.soup["strength"]) == int(view["after_water"]["strength"])
		and int(GameState.soup["remaining_servings"]) == int(view["after_water"]["remaining"]), "%s / %s" % [str(view["after_water"]), str(GameState.soup)])
	c.check("水を押したあと、▲は濃さ1の区画へ動く", int(marker.get_meta("value")) == 1)
	view = s.pot_view()
	_press(dashi)
	c.check("だし：予告（after_dashi）＝押した結果（濃さ）。残りは変わらない", int(GameState.soup["strength"]) == int(view["after_dashi"]["strength"])
		and int(GameState.soup["remaining_servings"]) == int(view["remaining"]))
	c.check("だしを押したあと、▲は濃さ3の区画へ動く", int(marker.get_meta("value")) == 3)
	root.queue_free()
	return c.finish()
