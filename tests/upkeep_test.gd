extends RefCounted
## 場所代・水道代の再編＋日々の運営費（BALANCE_REDESIGN_PLAN.md §1・§2）の検証。
## 対象は新しい定数（RENT_PRICE=90・WATER_PRICE=50・DAILY_OPERATING_COST=80）と、
## 日々の運営費の支払いタイミング・[次のPhase]でのスキップ不可・既存の場所代の
## 特別請求（_reason_after_collecting_rent）が新しい値でも機能することだけ。
## 判定ロジック・具材の腐敗・濃さメカニクスは変更していないことも合わせて確認する。


func _setup(t: SceneTree, money: int, day: int = 1):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がその場で_set_runner_for_phase(WAKE)を呼ぶ
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 新しい定数の値そのもの ---
	c.check("RENT_PRICEは90", GameState.RENT_PRICE == 90)
	c.check("WATER_PRICEは50", GameState.WATER_PRICE == 50)
	c.check("DAILY_OPERATING_COSTは80", GameState.DAILY_OPERATING_COST == 80)
	c.check("場所代+水道代の合計は140", GameState.RENT_PRICE + GameState.WATER_PRICE == 140)

	# --- 2. WAKEに入ると日々の運営費が引かれる(Day1・Day2とも) ---
	var panel = _setup(t, 300, 1)
	c.check("Day1のWAKEで日々の運営費が引かれる(300-80=220)",
		GameState.money == 220, str(GameState.money))
	var panel_d2 = _setup(t, 300, 2)
	c.check("Day2のWAKEでも日々の運営費が引かれる(300-80=220)",
		GameState.money == 220, str(GameState.money))

	# --- 3. [次のPhase]相当(flow.advance_phase)をrunnerに一切触れず直後に呼んでも、
	#    運営費は既にWAKE突入時点で確定している(スキップできない。§0で見つけた
	#    抜け穴の直接的な回帰テスト) ---
	var panel2 = _setup(t, 300, 1)
	var money_after_wake: int = GameState.money
	c.check("スキップ前の時点で既に220円に減っている", money_after_wake == 220)
	panel2.flow.advance_phase()   # WAKEのrunner(4要素)を1つも消化せずPREPへ進む
	c.check("[次のPhase]で即座にWAKEを抜けても運営費は二重に引かれない・戻らない",
		GameState.money == money_after_wake, str(GameState.money))

	# --- 4. 運営費差し引き後の所持金でPREPのscraps_base判定が行われる
	#    (150円スタート: 差し引き前80以上→通常なら仕込み可、差し引き後70<80で端材屋行き) ---
	var panel3 = _setup(t, 150, 1)
	c.check("WAKE後の所持金は150-80=70", GameState.money == 70, str(GameState.money))
	GameState.phase = GameState.Phase.PREP
	panel3._set_runner_for_phase(GameState.Phase.PREP)
	c.check("運営費差し引き後(70<80)なので端材屋ルートになる", panel3._scraps_base)

	# --- 5. 運営費未満ならWAKEでゲームオーバー。理由テキストは水道代・場所代と同じ形式 ---
	# 通常のDay1 WAKE(成功)を経てから資金が尽きたDay2のWAKEへ再突入する形にする
	# （インスタンス化直後・最初のWAKEで即ゲームオーバーになるケースは、_ready()が
	# flow.phase_changed.connect()より前に_set_runner_for_phase(WAKE)を呼ぶ構造上、
	# force_phase(GAME_OVER)のシグナルをまだ誰も聞いておらずrunnerが組まれない。
	# 実際のプレイではINITIAL_MONEY(300)がDAILY_OPERATING_COST(80)を必ず上回るため
	# 初回WAKEでの資金不足は起こらない＝現状は影響しないが、テストではこの経路を避ける）。
	var panel4 = _setup(t, 300, 1)
	GameState.money = 50
	GameState.day_count = 2
	panel4._set_runner_for_phase(GameState.Phase.WAKE)
	c.check("運営費(80)未満ならゲームオーバーになる", GameState.phase == GameState.Phase.GAME_OVER)
	c.check("支払えなかったので所持金は変化しない", GameState.money == 50)
	var reason: String = str(panel4.flow.runner.current().get("text", ""))
	c.check("ゲームオーバー理由が水道代・場所代と同じ形式(必要額・所持額を含む)",
		reason.contains("所持金が足りない") and reason.contains("¥80") and reason.contains("¥50"),
		reason)

	# --- 6. Day1のチンピラPAYは新しい場所代(90)。Day2はチンピラPAY自体が出ない ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var extra_day1: Array = Day1Events._customer_extra_events("thug")
	c.check("Day1のチンピラPAYは場所代90",
		extra_day1.size() == 1 and int(extra_day1[0].get("amount", -1)) == 90, str(extra_day1))
	GameState.day_count = 2
	var extra_day2: Array = Day1Events._customer_extra_events("thug")
	c.check("Day2はチンピラPAYが出ない(is_collection_dayでない)", extra_day2.is_empty(), str(extra_day2))

	# --- 7. Day1の水道代は新しい値(50)。Day2以降は水道代を払わない ---
	var panel5 = _setup(t, 300, 1)
	var money_before5: int = GameState.money
	panel5._visit_water_stall()
	c.check("Day1の水道代は50", GameState.money == money_before5 - 50, str(GameState.money))

	var panel6 = _setup(t, 300, 2)
	var money_before6: int = GameState.money
	var visited6: bool = panel6._visit_water_stall()
	c.check("Day2は水道代を払わない(is_collection_dayでない)",
		visited6 and GameState.money == money_before6, str(GameState.money))

	# --- 8. 未払いのまま閉店しようとしたときの特別請求が新しいRENT_PRICE(90)で機能する
	#    (既存の_reason_after_collecting_rentの回帰確認) ---
	var panel7 = _setup(t, 300, 1)
	var money_before7: int = GameState.money
	var close_reason: String = panel7._reason_after_collecting_rent("（今日はここで店じまい）")
	c.check("未払いのまま閉店すると場所代90が特別請求される",
		GameState.money == money_before7 - 90, str(GameState.money))
	c.check("特別請求後はrent_paid_todayがtrueになる", GameState.rent_paid_today)
	c.check("理由テキストに場所代を払った旨が追記される",
		close_reason.contains("店じまい") and close_reason.contains("場所代"), close_reason)

	# --- 9. 支払い予定(pending_bills_today、表示専用)：非徴収日はWAKE直後80、
	#    市場を出ると0になる（GameStateは単一のシングルトンなので、徴収日のケースと
	#    混ざらないよう各シナリオでresetから作り直して自己完結させる） ---
	var panel8 = _setup(t, 300, 2)
	c.check("非徴収日のWAKE直後は支払い予定80のみ", GameState.pending_bills_today == 80,
		str(GameState.pending_bills_today))
	var money_before8: int = GameState.money
	panel8._on_market_exit_pressed()
	c.check("非徴収日：市場を出ると支払い予定が0になる", GameState.pending_bills_today == 0,
		str(GameState.pending_bills_today))
	c.check("非徴収日は水道代が発生しないので市場を出てもmoneyは動かない",
		GameState.money == money_before8, str(GameState.money))

	# --- 10. 支払い予定：徴収日はWAKE直後170、市場を出ると場所代ぶんの90だけ残る
	#    （水道代の自動訪問も同時に起きるのでmoneyはここで動く）、場所代を払うと0になる
	#    (通常のREACT経路・特別請求経路のどちらから呼ばれても同じmark_rent_paid()の
	#    1箇所で決済される) ---
	var panel9 = _setup(t, 300, 1)
	c.check("徴収日のWAKE直後は支払い予定80+90=170", GameState.pending_bills_today == 170,
		str(GameState.pending_bills_today))
	panel9._on_market_exit_pressed()
	c.check("徴収日：市場を出ると支払い予定は場所代ぶんの90だけ残る",
		GameState.pending_bills_today == 90, str(GameState.pending_bills_today))
	GameState.mark_rent_paid()
	c.check("場所代を払うと支払い予定が0になる", GameState.pending_bills_today == 0)

	# --- 12. prep_after_tier_events(): MARKETの直後に「共同水道と炭屋に寄り、
	#    市場を出た。」という表示専用のTEXTが入る ---
	var tail: Array = Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[0], false)
	var market_idx := -1
	for i in range(tail.size()):
		if str(tail[i].get("type", "")) == "MARKET":
			market_idx = i
			break
	c.check("MARKETの直後に市場を出た旨のTEXTが入る",
		market_idx >= 0 and market_idx + 1 < tail.size()
			and str(tail[market_idx + 1].get("type", "")) == "TEXT"
			and str(tail[market_idx + 1].get("text", "")).contains("共同水道と炭屋"),
		str(tail))

	# --- 13. STATE VIEWERのmoney行に支払い予定の注記が出る／消える ---
	var panel10 = _setup(t, 300, 1)
	c.check("支払い予定がある間はmoney行に注記が出る",
		panel10._format_game_state().contains("支払い予定170"), panel10._format_game_state())
	panel10._on_market_exit_pressed()
	c.check("市場を出た後は注記が90に更新される",
		panel10._format_game_state().contains("支払い予定90"), panel10._format_game_state())
	GameState.mark_rent_paid()
	c.check("支払い予定が0になると注記自体が消える",
		not panel10._format_game_state().contains("支払い予定"), panel10._format_game_state())

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
