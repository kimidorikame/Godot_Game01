extends RefCounted
## 本番UI（UI準備B①）：Theme・ルート・左側（共通）の検証。
## 対象：UiPalette／resources/ui_theme.tres の色と型の変種、scenes/game_root.tscn と scenes/ui/left_side.tscn の
## 寸法（寸法表 KAITEN_UI_LAYOUT §1・4px以内）、PlaySession につないだときの表示（Day・時間帯／画面名・名前の札・
## 会話枠のページ送り・選択肢）、会話の分割 paginate（30字×3行）。
## 文字の幅が要る検査（枠に収まるか）はヘッドレスでは確かに測れない（4.4.1 は TextServer がダミー）ので、スクリーンショットの
## 実行（tools/ui_screens_B.gd）側で見る。ここは位置・大きさ・文の中身を見る。

const TOL := 4.0


func _near(a: Rect2, b: Rect2, tol: float = TOL) -> bool:
	return absf(a.position.x - b.position.x) <= tol and absf(a.position.y - b.position.y) <= tol \
		and absf(a.size.x - b.size.x) <= tol and absf(a.size.y - b.size.y) <= tol


## 文字の入る Label は、フォントの最小の高さで箱が変わるので、中心がそろっているかを見る。
func _center_near(a: Rect2, b: Rect2, tol: float = TOL) -> bool:
	return absf(a.get_center().x - b.get_center().x) <= tol and absf(a.get_center().y - b.get_center().y) <= tol


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 配色とTheme ---
	var want := { "bg": "#12161d", "bg2": "#1a202b", "frame": "#1c222d", "button": "#262e3b", "line": "#3d485a", "text": "#e8ebf0",
		"dim": "#9aa5b5", "accent": "#e8a33d", "on_accent": "#1a1204", "warn": "#ff8a7a", "good": "#6fd49a", "portrait": "#2c3544" }
	var palette := UiPalette.colors()
	var same := palette.size() == want.size()
	for key in want:
		same = same and palette.has(key) and (palette[key] as Color).is_equal_approx(Color(want[key]))
	c.check("UiPalette：決めた12色（地・地2・枠・ボタン・線・文字・薄い文字・強調・強調の上の文字・注意・良い・立ち絵の影）", same)
	var theme: Theme = load("res://resources/ui_theme.tres")
	c.check("resources/ui_theme.tres を読める", theme != null)
	var theme_same := true
	for key in want:
		theme_same = theme_same and theme.has_color(key, "UiPalette") and theme.get_color(key, "UiPalette").is_equal_approx(Color(want[key]))
	c.check("Theme の色（型 UiPalette）が配色と同じ", theme_same)
	var variations_ok := true
	for v in ["LabelDim", "LabelAccent", "LabelWarn", "LabelGood", "LabelSmall", "LabelDay", "LabelScreen", "LabelMoney", "LabelName",
			"LabelDialogue", "ButtonPrimary", "ButtonSecondary", "ButtonChoice", "ButtonIcon", "ButtonSmall",
			"PanelDark", "PanelPortrait", "PanelHud", "PanelNamePlate"]:
		variations_ok = variations_ok and theme.get_type_variation_base(v) != &""
	c.check("Theme の型の変種（文字・ボタン・枠）が揃っている", variations_ok)
	c.check("LabelWarn の文字色は注意色、ButtonPrimary の文字色は強調の上の文字",
		theme.get_color("font_color", "LabelWarn").is_equal_approx(UiPalette.WARN)
			and theme.get_color("font_color", "ButtonPrimary").is_equal_approx(UiPalette.ON_ACCENT))
	var base_font: Font = theme.default_font.base_font if theme.default_font is FontVariation else null
	c.check("Theme の既定のフォントは同梱の Noto Sans JP（太さ400）、Day・名前・主ボタンは太さ700",
		base_font != null and base_font.resource_path == "res://assets/fonts/NotoSansJP[wght].ttf"
			and (theme.default_font as FontVariation).variation_opentype.values() == [400]
			and theme.get_font("font", "LabelDay") is FontVariation
			and (theme.get_font("font", "LabelDay") as FontVariation).variation_opentype.values() == [700]
			and theme.get_font("font", "LabelName") == theme.get_font("font", "LabelDay")
			and theme.get_font("font", "ButtonPrimary") == theme.get_font("font", "LabelDay"))
	c.check("フォントのライセンス文書（OFL.txt）を同梱している", FileAccess.file_exists("res://assets/fonts/OFL.txt"))
	c.check("Day の文字は34px・所持金は28px・会話は24px",
		theme.get_font_size("font_size", "LabelDay") == 34 and theme.get_font_size("font_size", "LabelMoney") == 28
			and theme.get_font_size("font_size", "LabelDialogue") == 24)

	# --- 2. 会話の分割（30字×3行）---
	var one := UiLeftSide.paginate("あ".repeat(30))
	c.check("paginate：30字ちょうどは1ページ1行", one.size() == 1 and one[0] == "あ".repeat(30), str(one))
	var two := UiLeftSide.paginate("あ".repeat(48))
	c.check("paginate：標準の台詞48字は2行（1ページ）", two.size() == 1 and (two[0] as String).count("\n") == 1, str(two))
	var pages := UiLeftSide.paginate("あ".repeat(100))
	c.check("paginate：100字は4行→2ページ（3行＋1行）", pages.size() == 2 and (pages[0] as String).count("\n") == 2
		and (pages[1] as String).count("\n") == 0, str(pages))
	var half := UiLeftSide.paginate("a".repeat(60))
	c.check("paginate：半角は0.5字（60字で1行）", half.size() == 1 and half[0] == "a".repeat(60), str(half))
	var broken := UiLeftSide.paginate("一行目\n二行目\n三行目\n四行目")
	c.check("paginate：書いてある改行は守る（4行→2ページ）", broken.size() == 2 and broken[0] == "一行目\n二行目\n三行目" and broken[1] == "四行目", str(broken))
	c.check("paginate：空の文でも1ページ（空）", UiLeftSide.paginate("") == [""])

	# --- 3. ルート・左側の寸法 ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	c.check("game_root.tscn は 1280×720 で、Theme を持つ", root.size == Vector2(1280, 720) and root.theme == theme)
	t.root.add_child(root)
	c.check("子に Background・LeftSide・RightPane・Session がある",
		root.get_node_or_null("Background") != null and root.left != null and root.get_node_or_null("%RightPane") != null
			and root.session is PlaySession)
	c.check("右の枠は (836,24) 420×672", _near(root.get_node("%RightPane").get_global_rect(), Rect2(836, 24, 420, 672)))
	var left: UiLeftSide = root.left
	var checks := {
		"HudDate": Rect2(24, 14, 249, 52), "Portrait": Rect2(210, 64, 400, 490), "PhoneIcon": Rect2(686, 480, 52, 52),
		"LogIcon": Rect2(744, 480, 52, 52), "NamePlate": Rect2(44, 498, 200, 40), "DialogueBox": Rect2(24, 536, 772, 160) }
	for node_name in checks:
		c.check("%s の位置と大きさ（寸法表どおり・4px以内）" % node_name, _near(left.get_node("%" + node_name).get_global_rect(), checks[node_name]),
			str(left.get_node("%" + node_name).get_global_rect()))
	# Day の文字（34px）は、本物のフォントでは高さ48の箱の中心が寸法表の箱（36,23 95×34）の中心 (83.5,40) になる位置。
	# ヘッドレスの文字の高さは版で違う（4.4.1 はダミーで大きく出る）ので、箱の始点と幅を見る（中心はスクリーンショットで見る）。
	c.check("Day の文字：始点 (36,16)・幅95・時間帯ゲージ：(145,26) 116×28",
		left.get_node("%DayLabel").get_global_position().is_equal_approx(Vector2(36, 16)) and left.get_node("%DayLabel").size.x == 95.0
			and _near(left.get_node("%TimeGauge").get_global_rect(), Rect2(145, 26, 116, 28)),
		str(left.get_node("%DayLabel").get_global_rect(), left.get_node("%TimeGauge").get_global_rect()))
	# 既読スキップ（寸法表に無い。plan Q4：会話枠の右下、「▼」の左）。高さは文字で決まるので始点と幅を見る
	c.check("既読スキップは会話枠の右下 (604,664)・幅100（「▼」の左）",
		left.get_node("%SkipButton").get_global_position().is_equal_approx(Vector2(604, 664)) and left.get_node("%SkipButton").size.x == 100.0
			and left.get_node("%SkipButton").get_global_rect().end.x <= left.get_node("%PageMark").get_global_rect().end.x - 60.0)
	c.check("会話の文字：(50,558) 720×116", _near(left.get_node("%DialogueText").get_global_rect(), Rect2(50, 558, 720, 116)),
		str(left.get_node("%DialogueText").get_global_rect()))
	# 並べ替えは次のフレームに起きるので、ここでは手で走らせる
	(left.get_node("%MoneyRep") as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	var money_rect: Rect2 = left.get_node("%MoneyLabel").get_global_rect()
	var rep_rect: Rect2 = left.get_node("%ReputationLabel").get_global_rect()
	c.check("所持金・評判の右端が x=796 にそろう（評判が右端、所持金はその左）",
		absf(rep_rect.end.x - 796.0) <= TOL and money_rect.end.x <= rep_rect.position.x, str(money_rect, rep_rect))
	# 帯の中での所持金の上端は、文字の高さ（ヘッドレスの測り方は版で違う）で数px動くので、範囲で見る
	c.check("所持金・評判の帯は y=20 から（28px の文字の高さを見込んで、中心は寸法表の帯 y=26〜55 と同じ）",
		money_rect.position.y >= 19.5 and money_rect.position.y <= 24.0
			and absf(left.get_node("%MoneyRep").get_global_position().y - 20.0) <= 0.5, str(money_rect))

	# --- 4. PlaySession につないだ表示 ---
	var s: PlaySession = root.session
	c.check("起動時は Day1 の朝：Day 1・画面名「朝」・時間帯ゲージは隠す",
		left.get_node("%DayLabel").text == "Day 1" and left.get_node("%ScreenName").text == "朝"
			and left.get_node("%ScreenName").visible and not left.get_node("%TimeGauge").visible)
	c.check("所持金と評判を出す", left.get_node("%MoneyLabel").text == "¥%d" % GameState.money
		and left.get_node("%ReputationLabel").text == "評判 %d・客足 %s" % [GameState.reputation, UiLabels.demand_word(GameState.reputation)])
	c.check("会話の相手がいない朝は、立ち絵と名前の札を出さない", not left.get_node("%Portrait").visible and not left.get_node("%NamePlate").visible)
	var shown: String = left.get_node("%DialogueText").text
	c.check("会話枠に、いまの行の頭（ページ分割した先頭）が入る",
		shown != "" and str(s.current_line()["text"]).begins_with(shown.split("\n")[0]), shown)
	c.check("会話ログへ1行だけ記録された（描き直しの最後の record_visible_event）", s.talk_log_entries().size() >= 1)

	# 次へ：ページが残るなら先にページ、無ければ PlaySession の次のEvent
	var before: int = s.flow.runner.index
	var text_before: String = s.current_line()["text"]
	var page_count := UiLeftSide.paginate(text_before).size()
	var guard := 0
	while left.get_node("%PageMark").text == "▼続く" and guard < 10:
		left.advance()
		guard += 1
	c.check("ページが続くあいだは、advance() は Event を進めず会話枠のページだけ送る",
		s.flow.runner.index == before and guard == page_count - 1, "guard=%d pages=%d" % [guard, page_count])
	if s.can_next_event():
		left.advance()
		c.check("最後のページで advance() すると PlaySession の次のEventへ進む（会話枠に出さないEventは続けて進む）",
			s.flow.runner.index >= before + 1 or GameState.phase != GameState.Phase.WAKE)

	# 昨夜の成績の行（part:"day_summary"）は、会話枠に1行だけ出す
	s.flow.runner = EventRunner.new([{ "type": "TEXT", "text": "昨夜の売上は100円。\n提供は9杯。", "part": "day_summary" }])
	left.reset_ui_state()
	left.refresh()
	c.check("part:\"day_summary\" の行は、会話枠には「昨夜の成績を確かめた。」だけ（中身は右の枠）",
		left.get_node("%DialogueText").text == UiLeftSide.SUMMARY_LINE, left.get_node("%DialogueText").text)
	c.check("会話ログの正本（current_line）は元の文のまま", str(s.current_line()["text"]).begins_with("昨夜の売上は100円"))

	# 選択肢（CHOICE）：400×52、(210,352) から縦に、間隔12
	s.flow.runner = EventRunner.new([{ "type": "CHOICE", "customer": "officer", "choice_id": "dist",
		"options": [{ "id": "a", "label": "近くで話す" }, { "id": "b", "label": "離れて話す" }] }])
	left.reset_ui_state()
	left.refresh()
	var box: VBoxContainer = left.get_node("%Choices")
	box.notification(Container.NOTIFICATION_SORT_CHILDREN)
	c.check("選択肢のボタンが2つ出る", box.get_child_count() == 2 and (box.get_child(0) as Button).text == "近くで話す")
	if box.get_child_count() == 2:
		# ボタンの高さは文字の高さで決まる（ヘッドレスは文字の測りがダミー）ので、幅・始点・間隔・52以上を見る
		var first: Rect2 = (box.get_child(0) as Control).get_global_rect()
		var second: Rect2 = (box.get_child(1) as Control).get_global_rect()
		c.check("1つ目は (210,352)・幅400・高さ52以上", first.position.is_equal_approx(Vector2(210, 352)) and first.size.x == 400.0
			and first.size.y >= 52.0, str(first))
		c.check("2つ目は 1つ目の下 12px あけて、幅400", absf(second.position.y - (first.end.y + 12.0)) <= 0.5 and second.size.x == 400.0, str(second))
		c.check("ボタンは押すと choose_story_option へつながる", (box.get_child(0) as Button).pressed.get_connections().size() == 1)
	c.check("話し手がいる行（選択肢の客）でも名前の札は話し手の行でだけ出す：CHOICE は地の文なので出さない",
		not left.get_node("%NamePlate").visible)
	s.flow.runner = EventRunner.new([{ "type": "TEXT", "text": "地の文。" }])
	left.refresh()
	c.check("選択肢でなくなれば、ボタンは消える", left.get_node("%Choices").get_child_count() == 0)

	# 話し手がいる行：名前の札と立ち絵の枠
	s.flow.runner = EventRunner.new([{ "type": "GREET", "customer": "officer", "text": "こんばんは。" }])
	left.reset_ui_state()
	left.refresh()
	c.check("客の台詞（GREET）は、立ち絵の枠と名前の札（表示名）を出す",
		left.get_node("%Portrait").visible and left.get_node("%NamePlate").visible
			and left.get_node("%NameLabel").text == s.log_speaker("officer") and left.get_node("%NameLabel").text != "")

	# 列を読み終えた画面：会話枠を空にせず、最後に出した行を残す（話し手の枠は出さない）。区切りで捨てる
	s.flow.runner = EventRunner.new([{ "type": "GREET", "customer": "officer", "text": "最後の一言。" }])
	left.reset_ui_state()
	left.refresh()
	s.flow.runner.index = s.flow.runner.events.size()
	s.flow.runner.status = EventRunner.Status.DONE
	left.refresh()
	c.check("列が終わっても、会話枠には最後の行が残る（空にならない）", left.get_node("%DialogueText").text == "最後の一言。")
	c.check("残した行では、立ち絵と名前の札は出さない", not left.get_node("%NamePlate").visible)
	left.reset_ui_state()
	left.refresh()
	c.check("区切り（reset_ui_state）で、残した行は捨てる", left.get_node("%DialogueText").text == "")

	# 客足の言葉（評判の横）：区切りは需要表から読む
	var table: Array = Rules.demand_table()
	c.check("客足の言葉の数は需要表の行数と同じ（5つ）", UiLabels.demand_words_match_table() and table.size() == 5)
	var edges := { 0: "少ない", 19: "少ない", 20: "ふつう", 44: "ふつう", 45: "多め", 59: "多め", 60: "多い", 70: "多い", 71: "とても多い", 100: "とても多い" }
	var edges_ok := true
	for rep in edges:
		edges_ok = edges_ok and UiLabels.demand_word(int(rep)) == edges[rep]
	c.check("評判の区切り（0・19・20・44・45・59・60・70・71）で言葉が替わる", edges_ok)
	var center_matches := true
	GameState.day_count = 2   # Day1 は需要が固定（9）なので、Day2 で見る
	for rep in [0, 19, 20, 44, 45, 59, 60, 70, 71, 100]:
		GameState.reputation = rep
		var word_rank: int = ["少ない", "ふつう", "多め", "多い", "とても多い"].find(UiLabels.demand_word(rep))
		center_matches = center_matches and word_rank == [7, 9, 11, 14, 17].find(GameState.demand_center_today())
	c.check("言葉の区切りは、需要の中心（7・9・11・14・17）の区切りと同じ（Day1以外）", center_matches)
	GameState.reputation = 33
	s.notify_changed()
	c.check("画面の評判の横に客足の言葉が出る", left.get_node("%ReputationLabel").text == "評判 33・客足 ふつう", left.get_node("%ReputationLabel").text)

	root.queue_free()
	return c.finish()
