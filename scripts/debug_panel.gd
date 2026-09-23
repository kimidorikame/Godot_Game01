extends PanelContainer
## 開発用 State Viewer（DESIGN.md 8章 / 9章 STEP 1・STEP 2）。
##
## GameState と EventRunner.status を画面に映し、デバッグボタンで手叩きする。
## 本番のゲーム画面ではない。絵もシナリオも無し。
## FlowController はこのシーンの子ノードとして持つ（autoload にはしない）。

@onready var flow: FlowController = $FlowController as FlowController
@onready var _game_state_label: Label = $Margin/VBox/TextScroll/TextBox/GameStateLabel as Label
@onready var _runner_label: Label = $Margin/VBox/TextScroll/TextBox/RunnerLabel as Label
@onready var _btn_next_event: Button = $Margin/VBox/EventRow/BtnNextEvent as Button
@onready var _btn_complete_input: Button = $Margin/VBox/EventRow/BtnCompleteInput as Button
@onready var _btn_pot: Button = $Margin/VBox/EventRow/BtnPot as Button
@onready var _btn_close: Button = $Margin/VBox/EventRow/BtnClose as Button
@onready var _btn_phone: Button = $Margin/VBox/EventRow/BtnPhone as Button
@onready var _options_row: HBoxContainer = $Margin/VBox/OptionsRow as HBoxContainer
@onready var _btn_next_phase: Button = $Margin/VBox/PhaseRow/BtnNextPhase as Button
@onready var _btn_day_plus: Button = $Margin/VBox/PhaseRow/BtnDayPlus as Button
@onready var _btn_money_minus: Button = $Margin/VBox/PhaseRow/BtnMoneyMinus as Button
@onready var _btn_money_plus: Button = $Margin/VBox/PhaseRow/BtnMoneyPlus as Button
@onready var _btn_mob_debug: Button = $Margin/VBox/PhaseRow/BtnMobDebug as Button

# OPEN の間だけ生きる客キュー管理役（STEP 6）。OPEN 以外では null。
# flow.runner は「今の客の接客 runner」に載せ替える。この _open は「今何人目か」を持つだけ。
var _open: OpenController = null

# 自動閉店（DESIGN.md 7.6）で CLOSE に飛ばすときだけ使う、先頭に差し込む理由テキスト。
# _set_runner_for_phase(CLOSE) が読んで消費する（読んだら空文字に戻す＝一度きり）。
var _closed_early_reason := ""

# ゲームオーバーの理由テキスト。_set_runner_for_phase(GAME_OVER) が読んで消費する
# （_closed_early_reason と同じく一度きり）。
var _game_over_reason := ""

# 判定結果 → 評判の増減（DESIGN.md 7.6）。名前あり客よりモブの方が動きが小さい。
# 「どれだけ動かすか」を決めるのは受け側＝ここ。適用は GameState.apply_reputation()。
# sale と同じ考え方（量は受け側が決め、GameState は入口として適用するだけ）。
# 数値は仮。触ってから調整する（DESIGN.md 7.6「評判のインフレについて」）。
const REPUTATION_NAMED := { "GREAT": 3, "GOOD": 2, "OK": 0, "BAD": -2 }
const REPUTATION_MOB := { "GREAT": 1, "GOOD": 1, "OK": 0, "BAD": -1 }

# [鍋を見る] の操作モード中か（DESIGN.md 7.6）。
# EventRunner には一切触れない＝ index も status も動かさない。表示と操作対象を
# 切り替えるだけなので、会話は止まったまま鍋をいじって戻れる。
var _pot_mode := false

# 鍋が尽きて「作り直すか閉店するか」の選択待ちのとき、保留中のREACT Eventを持つ。
# null なら選択待ちではない（DESIGN.md 7.6：条件1・2のどちらか一方だけ成立したとき）。
# 判定・売上・鍋の消費はまだ行っていない状態＝[戻る]で初めて _serve_customer() が動く。
var _pending_shortage_ev = null

# 鍋モードに入った時点で鍋が空（残量0以下）だった場合、水を入れるまでの間だけ true。
# _on_pot_pressed() で毎回リセットする。
var _pot_water_added := false

# 市場（DESIGN.md 7.7）で水場に寄ったか。PREPに入るたびリセットする。
var _market_visited_water := false

# 直前に訪れた市場の店のセリフ（DESIGN.md 7.7「支払いのトーン」）。PREPに入るたび
# リセットする。水場のように専用Eventを持たない店の text を表示するための一時状態。
var _market_last_text := ""

# 今どの店の中にいるか（例: "produce"）。空文字なら市場のトップ（7店舗選択）にいる。
# 鍋モード（_pot_mode）と同じ「EventRunnerには触れないUIだけの入れ子」。
# PREPに入るたびリセットする。
var _market_shop := ""

# スマホ（3つ目の入れ子モード）。鍋モード・市場モードと同じくEventRunnerには一切触れない。
# フェーズ・鍋モード・市場モードのどれからでも開ける（排他にしない）。_update_options_row()の
# 最優先で判定するので、_pot_mode/_market_shopの値はそのまま裏で保持され、閉じれば
# 自動的に元の画面へ戻る（退避・復元の処理は不要）。
var _phone_mode := false

# スマホの現在のタブ（"recipe" / "news" / "sns"）。フェーズをまたいでも維持しない
# （_set_runner_for_phase()で既定値に戻す。鍋モードの水入れ状態などと同じ扱い）。
var _phone_tab := "recipe"

# 今の客の椀を何回廃棄したか（[廃棄する]で作り直すたびに+1）。客が替わる
# （_load_current_customer）たびにリセットする一時状態。現在の椀自体はリセットで
# 消えてしまうので、廃棄したという事実を別に持っておかないと計器盤から見えなくなる。
var _bowl_discard_count := 0

# 1人の客を複数の杯に分けて接客するとき（REACT に aggregate:true を持たせた客）の、
# 退店までの集計。空辞書なら集計中の客はいない。形は
#   { customer, rep_sum, rep_count, sale, servings }
# 評判と提供記録は杯ごとではなく客1人分として退店時に1回だけ反映するため、ここに積む
# （_flush_visit_tally）。鍋の消費と売上は杯ごとにその場で反映する（集計するのは
# 評判と提供記録だけ）。客のrunnerがDONEになったとき、またはフェーズが替わるとき
# （途中閉店・ゲームオーバー）に空にする＝二重に反映されない。
var _visit_tally := {}

# デバッグ用：今夜のモブ人数の強制指定（-1＝自動）。Day2-7ダミーデータ・モブ抽選独立化で、
# Day1Events.customer_schedule()へそのまま渡す値になった（枠ごとに種類も人数も独立抽選する
# ため、-1以外なら全モブ枠の人数だけを一律で上書きする。種類はそれでも枠ごとにばらつく）。
# OPENに入る瞬間に読まれるので、変えるなら OPEN に入る前（WAKE・PREP中）に押すこと。
# GameState には持たせない（本番の挙動・データには関係しない、この計器盤だけの検証用の上書き）。
var _debug_mob_count := -1

# 今日はクズ野菜ベースか（所持金がベース代に満たないので端材屋へ回った日）。PREPに入る瞬間に
# 1回だけ決めて、prep_events と計器盤の両方で使い回す（_debug_mob_count と同じ形）。
var _scraps_base := false

# --- 日次ログ（BALANCE_REDESIGN_PLAN.md §8「①消費と鮮度の明確化・日次ログ」）用の
# 使い捨てカウンタ。経済数値・計算式には一切関与しない、記録専用の値。WAKEに入った瞬間
# （_set_runner_for_phase）にその日ぶんへ初期化し、FlowController.day_ending シグナル
# （NEXT_DAY→WAKE折り返しで日次リセットの前）で読み出してログへ組み立てる。
# GameStateではなくここに置く理由は_mob_count等と同じ：日をまたいで使い捨てる
# 受け側の作業変数であり、GameStateの「事実のみ・永続」という役割ではないため。
var _log_opening_money := 0
var _log_opening_reputation := 0
var _log_planned_cups := 0          # OPEN突入時、その日の全客のREACT servingsを合算
var _log_water_used := 0            # [水を足す]を押した回数
var _log_base_used := 0             # [ベースを足す]を押した回数
var _log_closed_early := false      # 鍋不足等でCLOSEへ強制遷移したか
var _log_quality_counts := {}       # {"GREAT":n, "GOOD":n, "OK":n, "BAD":n, "":n(判定なし)}
var _log_spoiled_items := {}        # PREP突入時のdiscard_spoiled_inventory()の結果をそのまま保持


func _ready() -> void:
	_seed_initial_inventory()
	_set_runner_for_phase(GameState.phase)

	# 以下は「どのボタン/シグナルが何を呼ぶか」の結線。処理内容は各ハンドラ側にある。
	# 最終日の翌朝の巻き戻し後に、初期在庫を積み直す（reset → 積み直し → phase_changed の順）。
	flow.game_restarted.connect(_seed_initial_inventory)
	flow.phase_changed.connect(_on_phase_changed)      # フェーズが変わった → 表示を更新
	flow.runner_updated.connect(_on_runner_updated)    # runner の再生位置が動いた → 表示を更新
	# 日次ログ：NEXT_DAY→WAKEの折り返しで、日次リセットの前に一日分の集計を確定して出す
	# （シグナルは同期発火なので、ここが完了してからFlowController側の日次リセットへ進む）。
	flow.day_ending.connect(_on_day_ending)
	# [次のEvent] = _on_next_event_pressed:
	#   flow.runner_advance() で PLAYING のときだけ index を1つ進める。
	#   WAITING_INPUT / DONE では何もしない（＝WAIT_INPUT で確実に止まる）。
	#   STEP 4: 進んだ先の Event が PAY / ADD_ITEM なら、その効果をここで GameState に反映する。
	_btn_next_event.pressed.connect(_on_next_event_pressed)
	# [入力完了] = _on_complete_input_pressed:
	#   flow.runner_complete_input() で WAITING_INPUT を PLAYING に戻してから1つ進める。
	#   「入力待ちの解除」専用。[次のEvent] との違い: あちらは止まっている列を動かせないが、
	#   こちらは解除したうえで先へ進める。PLAYING 中に押しても無効。
	#   STEP 4: 進んだ先の Event の効果反映は [次のEvent] と同じ扱い。
	_btn_complete_input.pressed.connect(_on_complete_input_pressed)
	# [鍋を見る] = 鍋の操作モードに入る（7.6）。EventRunner は進めない。
	#   ADJUST 中（3枠を選んでいる間）は押せない＝調理の途中で鍋をいじらせない。
	_btn_pot.pressed.connect(_on_pot_pressed)
	# [閉店] = 鍋が尽きて選択待ちのときだけ押せる（7.6）。保留中のREACTは適用しない。
	_btn_close.pressed.connect(_on_close_pressed)
	_btn_next_phase.pressed.connect(flow.advance_phase)  # [次のPhase] = 上位フェーズを一方向に1つ進める
	_btn_day_plus.pressed.connect(_on_day_plus_pressed)  # [Day+] = 日数だけ +1（デバッグ用）
	# [所持金 ±50] = 所持金だけ動かす（デバッグ用。クズ野菜ベースやゲームオーバーの確認に使う）。
	_btn_money_minus.pressed.connect(_on_money_debug_pressed.bind(-50))
	_btn_money_plus.pressed.connect(_on_money_debug_pressed.bind(50))
	# [モブ人数] = 今夜のモブ人数を 自動→1→2→3→4→自動… と切り替える（デバッグ用）。
	_btn_mob_debug.pressed.connect(_on_mob_debug_pressed)
	# [スマホ] = 3つ目の入れ子モードに入るだけ（EventRunner・GameStateには触れない。
	#   _on_pot_pressed() と同じ形）。常時押せる（例外は開いている間、自身が無効化される）。
	_btn_phone.pressed.connect(_on_phone_pressed)

	_refresh()


## Day1開始時の初期在庫を積む（DESIGN.md 7.7）。ゲーム開始時（_ready）と、最終日の翌朝の
## 新規ゲームへの巻き戻し後（game_restarted）の両方から呼ぶ。
## is_empty()でガード＝シーン再読み込み等で二度走っても二重に積まない。
## 巻き戻しでは day_count が1に戻った後に呼ばれるので、購入日別のバッチも1日目で記録される。
func _seed_initial_inventory() -> void:
	if not GameState.inventory.is_empty():
		return
	var starting: Dictionary = Day1Events.initial_inventory()
	for id in starting:
		GameState.add_inventory(id, int(starting[id]))


func _on_phase_changed(phase: int) -> void:
	_set_runner_for_phase(phase)
	_refresh()


## フェーズごとの Event 列を runner に差し込む。
## STEP 3: WAKE / STEP 4: PREP / STEP 6: OPEN（客キュー）/ STEP 9: CLOSE。
## NEXT_DAY は空のまま（日次処理は FlowController.advance_phase の折り返し側）。
## 新フェーズを実装するときは、ここに elif を1本足して対応する events を返す。
func _set_runner_for_phase(phase: int) -> void:
	# 途中閉店・ゲームオーバー（force_phase）でも、そこまでに提供した杯の評判と提供記録を
	# 失わないよう、客キューを捨てる前に集計を反映する（空なら何もしない）。
	_flush_visit_tally()
	_open = null   # OPEN 以外では客キューを持たない
	# 7.6: 鍋の選択待ち・鍋モードも OPEN 以外には持ち越さない（防御的リセット）。
	_pending_shortage_ev = null
	_pot_mode = false
	_pot_water_added = false
	# 7.7: 市場の水場訪問フラグ・直前のセリフ・店の中にいるかも PREP に入るたびリセットする。
	_market_visited_water = false
	_market_last_text = ""
	_market_shop = ""
	# スマホも鍋・市場と同じくフェーズをまたいで持ち越さない（防御的リセット）。
	_phone_mode = false
	_phone_tab = "recipe"
	if phase == GameState.Phase.WAKE:
		# 日次ログ：その日の開始時点として、所持金・評判を記録し、当日ぶんのカウンタを
		# 初期化する（前日の day_ending 発火はもう終わっている＝直前のログには影響しない）。
		_log_opening_money = GameState.money
		_log_opening_reputation = GameState.reputation
		_log_planned_cups = 0
		_log_water_used = 0
		_log_base_used = 0
		_log_closed_early = false
		_log_quality_counts = { "GREAT": 0, "GOOD": 0, "OK": 0, "BAD": 0, "": 0 }
		_log_spoiled_items = {}
		flow.set_runner(Day1Events.wake_events())
	elif phase == GameState.Phase.PREP:
		# 具材の腐敗: PREPに入る瞬間に1回だけ、腐りきった在庫（4日目以降）を消して、
		# 捨てた品目を先頭の一言テキストで知らせる（市場で買い足しても救われない簡易版）。
		# クズ野菜ベース: 所持金がベース代に満たなければ食肉仲卸ではなく端材屋へ回る（自動）。
		_scraps_base = GameState.money < GameState.BASE_PRICE
		# 予備ベースの購入分も同じ瞬間に1回だけ判定し、捨てたら一言足す。
		var spoiled := GameState.discard_spoiled_inventory()
		_log_spoiled_items = spoiled   # 日次ログ用に保持（廃棄額の概算に使う）
		var reserve_lost := GameState.discard_spoiled_reserve_base()
		flow.set_runner(Day1Events.prep_events(spoiled, _scraps_base, reserve_lost))
	elif phase == GameState.Phase.OPEN:
		# 客ループは OpenController に隔離（DESIGN.md 4章）。中身の再生は客ごとの runner。
		# モブの種類・人数は枠ごとにcustomer_schedule()が内部で独立抽選するので、ここでは
		# デバッグ用の一律上書き値（_debug_mob_count。-1=自動）をそのまま渡すだけでよい。
		_open = OpenController.new(Day1Events.customer_schedule(_debug_mob_count))
		# 日次ログ：その日の計画杯数（提供できたか否かに関わらず）を、実際の接客より前に
		# 先読みして合算する。customer_events()はGameState.day_countとJSONキャッシュを
		# 読むだけの副作用なし関数なので、ここで呼んでも以後の本編の進行に影響しない。
		_log_planned_cups = 0
		for slot in _open.schedule:
			for customer_id in slot.get("customers", []):
				for ev in Day1Events.customer_events(str(customer_id)):
					if ev.get("type", "") == "REACT":
						_log_planned_cups += int(ev.get("servings", 0))
		_load_current_customer()
	elif phase == GameState.Phase.CLOSE:
		# 7.6: 自動閉店（鍋が尽きた）で来たときだけ、理由テキストを先頭に差し込む。
		# 読んだら消費する（次に通常経路でCLOSEへ来たときに残っていないように）。
		var events := Day1Events.close_events()
		if _closed_early_reason != "":
			events = [{ "type": "TEXT", "text": _closed_early_reason }] + events
			_closed_early_reason = ""
		flow.set_runner(events)
	elif phase == GameState.Phase.GAME_OVER:
		# 最小実装：理由と「（ゲームオーバー）」を出すだけ。以後フェーズは進まない
		# （FlowController.advance_phase が止める）。演出・タイトルへの導線・復帰は対象外。
		flow.set_runner([
			{ "type": "TEXT", "text": _game_over_reason },
			{ "type": "TEXT", "text": "（ゲームオーバー）" },
		])
		_game_over_reason = ""
	else:
		flow.set_runner([])   # NEXT_DAY など未実装フェーズ（空 runner ＝即 DONE）


## いま接客中の客の Event 列を flow.runner に載せる。
## 客がいなければ空 runner（＝即 DONE）にして、OPEN を CLOSE へ進められる状態にする。
func _load_current_customer() -> void:
	_bowl_discard_count = 0   # 新しい客ごとにリセット（廃棄回数は客をまたがない）
	if _open != null and _open.has_more():
		# モブの人数はDay1Events._mob_instances側で客ごとに覚えているので、ここでは
		# 第2引数（mob_count）を渡さない（渡しても_customer_flavor側で無視される）。
		flow.set_runner(Day1Events.customer_events(str(_open.current_customer())))
	else:
		flow.set_runner([])


## [次のEvent] のハンドラ。runner を1つ進め、新しく current になった Event の効果を受ける。
## 「Event はデータ / 処理は受け側」（DESIGN.md 確定事項）の "受け側" がここ。
## EventRunner はカーソルを動かすだけで、PAY / ADD_ITEM の反映は一切しない。
func _on_next_event_pressed() -> void:
	if flow.runner == null:
		return
	var before: int = flow.runner.index
	flow.runner_advance()
	# index が動いたときだけ適用（WAITING_INPUT で空振りした場合などは二重適用しない）。
	if flow.runner.index != before:
		_apply_event(flow.runner.current())
	_advance_open_queue_if_customer_done()
	_refresh()


## [入力完了] のハンドラ。入力待ちを解除して1つ進め、[次のEvent] と同じく新 current を適用。
## STEP 17.6: ADJUST 中も含め、常にこのボタンで進める（＝「提供」を兼ねる）。
## 具材ボタンはもう進めない（_on_ingredient_selected 側）ので、ADJUST で止まったまま
## 何度でも具材を選び、進みたくなったらこのボタンを押す、という形になる。
func _on_complete_input_pressed() -> void:
	_complete_input_and_advance()


## ADJUST の具材ボタンが押されたときのハンドラ（STEP 17.6 → 7.7で在庫連動）。
## 「椀へ具材を足す」のは EventRunner ではなく受け側＝ここの責務
## （DESIGN.md 9.5 STEP 13「EventRunner は味付け効果を処理しない」）。
## STEP 13/14 と違い、進めない（advanceしない）。3枠まで何度でも選べるようにするため、
## ADJUST から進むのは [入力完了]（提供）を押したときだけにする。
## 7.7: 選ぶたびに在庫を servings 分減らす（DESIGN.md 7.6「モブ客の仕様」：
## 「鍋 −人数分 / 具材 −人数分」。1つの椀で servings 人分をまとめて作る以上、
## 具材も鍋（consume_soup）と同じく人数分＝1人前の名前あり客なら1個のまま）。
## 在庫切れ（ボタン側で無効化済みだが二重に防ぐ）なら何もしない。
## フェーズ1 ステップ3：在庫を減らすのは add_to_bowl() が実際に椀へ足せたとき（戻り値
## true）だけにする。上限（3枠）に達している・椀が無いときに add_to_bowl() が
## 何もせず false を返すケースで、椀には入らないのに在庫だけ減る不具合があったため。
## 鮮度: 傷み判定は「どちらのボタンを押したか」だけで決める（damaged＝傷んだボタン）。
## 押した側の在庫が足りなくても、合計が servings 以上なら、もう一方から補って人数分まとめて
## 引く（押した側に1個以上あることはボタン側で保証。二重にここでも見る）。
func _on_ingredient_selected(ingredient_id: String, damaged: bool = false) -> void:
	var servings := _current_servings()
	var own: int = GameState.damaged_count(ingredient_id) if damaged else GameState.fresh_count(ingredient_id)
	if own < 1 or GameState.fresh_count(ingredient_id) + GameState.damaged_count(ingredient_id) < servings:
		return
	var added := _open != null and _open.add_to_bowl(ingredient_id, damaged)
	if added:
		if damaged:
			GameState.remove_inventory_damaged(ingredient_id, servings)
		else:
			GameState.remove_inventory_fresh(ingredient_id, servings)
	_refresh()


## [廃棄する] のハンドラ。取り分けた一杯を無駄にしてから、**同じ客への椀を作り直す**
## （客を進めない＝EventRunnerはADJUSTに留まったまま。SERVE/REACTには一切触れない
## ので、EventRunnerの「optionsを持つEventは入力待ちで止まる」ルールは無傷）。
## 判定・売上・評判は発生しない：judge_bowlを呼んでいない＝判定自体が無いため。
## servingsは _current_servings()（REACTをまだ経由せず先読みする既存の仕組み）を使う。
func _on_discard_pressed() -> void:
	# 残量が servings に満たないときは廃棄できない（ボタン側でも無効化済みだが二重に防ぐ）。
	if _open == null or _is_short_now():
		return
	var servings := _current_servings()
	GameState.consume_soup(servings)
	GameState.record_served({ "customer": str(_open.current_customer()), "sale": 0,
		"servings": servings, "discarded": true })
	_bowl_discard_count += 1
	_open.reset_bowl()
	_refresh()


## [鍋を見る] のハンドラ（7.6）。モードに入るだけで、EventRunner には触れない。
## 鍋モードに入るたびに「水を入れたか」をリセットする（_pot_locked_until_water 用）。
func _on_pot_pressed() -> void:
	_pot_mode = true
	_pot_water_added = false
	_refresh()


## 鍋モードの [戻る]。会話へ戻る（こちらも EventRunner には触れない）。
## 7.6: 鍋が尽きての選択待ち中だった場合、ここで初めて保留中のREACTを適用する
## （＝「営業を続ける」を選んだことになる）。作り直しが実際に足りているかは
## 再チェックしない（一度決めたら、その結果のまま提供する）。
func _on_pot_back_pressed() -> void:
	_pot_mode = false
	if _pending_shortage_ev != null:
		var ev = _pending_shortage_ev
		_pending_shortage_ev = null
		_serve_customer(ev)
	_refresh()


## [閉店] のハンドラ（7.6）。鍋が尽きて選択待ちのとき、またはADJUST中に鍋が足りず水も
## 無いときだけ押せる（_can_close_now）。保留中のREACTは適用しない（この客には出せなかった
## 扱い）。理由テキストを添えてCLOSEへ飛ばす。評判・売上の扱いは変えない。
## 場所代が未払いなら、CLOSEへ飛ばす前に特別請求する（§11「未解決」の直し方の実装。
## _reason_after_collecting_rent参照）。払えずゲームオーバーになったらCLOSEへは進まない。
func _on_close_pressed() -> void:
	if not _can_close_now():
		return
	var reason := _reason_after_collecting_rent("（今日はここで店じまいにする。）")
	if reason == "":
		return
	_pending_shortage_ev = null
	_pot_mode = false
	_closed_early_reason = reason
	_log_closed_early = true   # 日次ログ：鍋不足で名前あり客を最後まで回せなかった
	flow.force_phase(GameState.Phase.CLOSE)
	_refresh()


## 鍋モードの [水を足す] / [ベースを足す]。効果は GameState の入口にまとめてある
## （残量・濃さ・資源が同時に動くので、受け側から分けて呼べないようにしている）。
func _on_add_water_pressed() -> void:
	GameState.add_water()
	_pot_water_added = true
	_log_water_used += 1   # 日次ログ：水を足した回数
	_refresh()


func _on_add_base_pressed() -> void:
	GameState.add_base()
	_log_base_used += 1   # 日次ログ：ベースを足した回数
	_refresh()


## [スマホ] のハンドラ。モードに入るだけで、EventRunner には触れない（_on_pot_pressed()
## と同じ形）。_pot_mode/_market_shopの値は変更しない＝閉じれば自動的に元の画面へ戻る。
func _on_phone_pressed() -> void:
	_phone_mode = true
	_refresh()


## スマホの [閉じる]。会話・鍋・市場のどの状態にも触れず、ただモードを抜けるだけ。
func _on_phone_close_pressed() -> void:
	_phone_mode = false
	_refresh()


## スマホのタブ切り替え（[レシピ]/[ニュース]/[SNS]）。
func _on_phone_tab_selected(tab: String) -> void:
	_phone_tab = tab
	_refresh()


## 市場の店ボタンが押されたときのハンドラ（DESIGN.md 7.7）。ADJUSTの具材ボタンと同じく
## 進めない（EventRunnerには触れない）。押せない店（Day1の食肉仲卸など）は
## 押せる状態にならない限りここには来ない（data側の"enabled"で塞いである）。
func _on_market_stall_selected(id: String) -> void:
	match id:
		"water":
			_visit_water_stall()
		"produce", "meat_wholesale", "dry_goods", "tofu_noodles", "seafood", "scraps":
			_market_shop = id  # 店内へ（鍋モードと同じ、UIだけの入れ子）
		_:
			pass
	_refresh()


## 店名から、その店の商品リストを引く。店ごとの商品データは day1_events.gd 側
## （"today's shop"の事実として、enabledと同じ置き場所）。未実装の店は空配列。
func _shop_goods(shop: String) -> Array:
	match shop:
		"produce":
			return Day1Events.produce_goods()
		"meat_wholesale":
			return Day1Events.meat_wholesale_goods()
		"dry_goods":
			return Day1Events.dry_goods_goods()
		"tofu_noodles":
			return Day1Events.tofu_noodles_goods()
		"seafood":
			return Day1Events.seafood_goods()
		"scraps":
			return Day1Events.scraps_goods()
		_:
			return []


## 店の商品ボタンが押されたときのハンドラ（DESIGN.md 7.7）。店を出ずその場に留まる
## （何度でも買える）。所持金が足りない商品はボタン側で無効化済みなので、ここでは
## 二重チェックだけ（防御的）。
func _on_shop_item_selected(shop: String, id: String) -> void:
	for good in _shop_goods(shop):
		if str(good.get("id", "")) == id:
			var price: int = int(good.get("price", 0))
			if id == "reserve_base":
				if GameState.money >= price and not GameState.reserve_base_purchased:
					GameState.apply_money(-price)
					GameState.buy_reserve_base()
			elif GameState.money >= price:
				GameState.apply_money(-price)
				GameState.add_inventory(id, GameState.INGREDIENT_SERVINGS_PER_PURCHASE)
			break
	_refresh()


## [市場に戻る]（店から出る）。鍋モードの[戻る]と同じくEventRunnerには触れない。
func _on_shop_exit_pressed() -> void:
	_market_shop = ""
	_refresh()


## 水場を訪れる（水道代の支払い＋水汲みの効果）。市場中の[水場]ボタンからも、
## 未訪問のまま[市場を出る]で抜けようとしたときの自動訪問からも呼ばれる。
## 水道代が払えずゲームオーバーになったら false（呼び出し元は先へ進めないこと）。
func _visit_water_stall() -> bool:
	if GameState.is_collection_day():
		if not _pay_or_game_over(50):
			return false
	_market_visited_water = true
	_market_last_text = _market_option_text("water")
	return true


## 今の MARKET Event の options から、id に対応する "text"（セリフ）を探す。
## 専用Eventを持たない店の会話を表示するために使う（例: 水場。_visit_water_stall 参照）。
## 見つからなければ空文字（"text" を持たない店もあるので、その場合は何も表示しない）。
func _market_option_text(id: String) -> String:
	var r: EventRunner = flow.runner
	if r == null:
		return ""
	var cur = r.current()
	if not (cur is Dictionary):
		return ""
	for option in cur.get("options", []):
		if str(option.get("id", "")) == id:
			return str(option.get("text", ""))
	return ""


## [市場を出る] のハンドラ（DESIGN.md 7.7）。水場に未訪問なら自動で訪れてから、
## [入力完了]と同じ手順（WAITING_INPUT解除→1つ進める→効果適用）で仕込みへ進む。
## 訪問済み・未訪問に関わらず常に押せる（水汲み忘れで詰まらせない）。
func _on_market_exit_pressed() -> void:
	if not _market_visited_water:
		# 水道代が払えずゲームオーバーになったら、仕込みへ進まずここで止まる。
		if not _visit_water_stall():
			return
	_complete_input_and_advance()


## いま MARKET が現在の Event か（options を持つ WAITING_INPUT の一種）。
## [次のEvent]/[入力完了] を無効化する判定に使う（抜ける経路を[市場を出る]だけにする）。
func _is_in_market() -> bool:
	var r: EventRunner = flow.runner
	if r == null:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.get("type", "") == "MARKET"


## いま ADJUST で3枠を選んでいる最中か（options を持つ WAITING_INPUT）。
## 鍋モードに入れるかの判定に使う（調理の途中で鍋をいじらせない）。
func _is_choosing_ingredients() -> bool:
	var r: EventRunner = flow.runner
	if r == null or r.status != EventRunner.Status.WAITING_INPUT:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.has("options")


## いま SERVE（[入力完了]で椀を確定した直後、まだ判定[REACT]が適用される前）か。
## フェーズ1 ステップ4：judge_bowl は REACT が適用される瞬間に鍋の濃さをその場で
## 読みに行くため、椀の中身（additions）は確定済みなのに、SERVEで足踏みしている間だけ
## 鍋を触って濃さを変えられると判定が後から変わってしまう（廃棄する・閉店はこの状態では
## 元々出せない／押せないので、塞ぐ必要があるのは鍋モードだけ）。REACT はEventが
## current になった瞬間に同じ処理内で即座に適用される実装なので、SERVEさえ塞げば
## 判定前に鍋をいじれる隙間は無くなる。
func _is_awaiting_react() -> bool:
	var r: EventRunner = flow.runner
	if r == null:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.get("type", "") == "SERVE"


## 鍋モードに入った時点で鍋が空（残量0以下）だった場合、水を入れる（_pot_water_added）
## までの間だけ true（DESIGN.md 7.6：ベースだけ入れても煮出す水が無く意味をなさない）。
## "どうやって鍋モードに入ったか" ではなく "残量が実際に空かどうか" で判定するので、
## 選択待ち経由でも普段の任意タイミングでの訪問でも同じルールが自然にかかる。
func _pot_locked_until_water() -> bool:
	if _pot_water_added:
		return false
	return GameState.soup != null and int(GameState.soup.get("remaining_servings", 0)) <= 0


## [入力完了] と選択肢ボタンの共通処理：WAITING_INPUT を解除して1つ進め、
## 新 current の効果を適用し、OPEN の客キューを必要なら進めて再描画する。
func _complete_input_and_advance() -> void:
	if flow.runner == null:
		return
	var before: int = flow.runner.index
	flow.runner_complete_input()
	if flow.runner.index != before:
		_apply_event(flow.runner.current())
	_advance_open_queue_if_customer_done()
	_refresh()


## OPEN 中、今の客の接客 runner が DONE になったら次の客をロードする。
## 全員さばき切ったら空 runner（DONE）になり、[次のPhase] で CLOSE へ進めるようになる。
## OPEN 以外・キューが空のときは何もしない。
func _advance_open_queue_if_customer_done() -> void:
	if GameState.phase != GameState.Phase.OPEN or _open == null:
		return
	if flow.is_runner_done() and _open.has_more():
		# 退店：複数の杯に分けて接客した客の評判・提供記録を、ここで1回だけ反映する。
		_flush_visit_tally()
		# 7.6: 時間帯が変わったら鍋が煮詰まる（残量は変わらない＝蒸発なし）。
		# 「変わったか」は OpenController が返し、鍋を動かすのは受け側のここ。
		if _open.advance_customer():
			GameState.deepen_soup()
		_load_current_customer()


## Event（データ）を1つ受けて、その効果を GameState に反映する「受け側」の本体。
## type を見て振り分けるだけ。処理はデータ側に持たせない（DESIGN.md 確定事項）。
##   PAY         … { amount } を apply_money(-amount) に渡す（支払い）
##   ADD_ITEM    … { item, amount } を add_inventory(item, amount) に渡す
##   REMOVE_ITEM … { item, amount } を remove_inventory(item, amount) に渡す（仕込みでの消費）
##   SET_SOUP    … { base_id, tags, servings } を set_soup() に渡す（共有鍋の作成・STEP 12/7.6）
##   REACT       … 残量が足りれば _serve_customer() で判定・評判・鍋消費・売上・記録
##                 （STEP 17.6・7.6）。足りないときは条件次第で自動閉店／選択待ち／
##                 そのまま提供に分かれる（7.6。詳細はこのcase内のコメント参照）
##   ADJUST      … new_bowl:true のときだけ、椀を新しく作り直す（同じ客の2杯目以降。
##                 前の杯の具材・評価・傷み印を持ち越さない）。それ以外は表示だけ
##   TEXT / WAIT_INPUT / GREET / SERVE / MARKET … 表示だけ。状態は動かさない
##     （ADJUST は STEP 13 で入力待ちに変わったが、椀への具材の反映は _on_ingredient_selected
##     が行う。MARKET（7.7）も同様に、水場の効果は _on_market_stall_selected /
##     _on_market_exit_pressed が行う）
## 注意: index 0 の Event は「乗る前進」が無いので適用されない。Day1 の WAKE / PREP /
## 客の接客はどれも先頭が TEXT / GREET（効果なし）なので実害なし。
func _apply_event(ev) -> void:
	if not (ev is Dictionary):
		return
	match ev.get("type", ""):
		"PAY":
			# 払えなければ実行せずゲームオーバー（水道代・場所代）。ベース代も同じ経路だが、
			# 払える所持金のときしかイベント自体が組まれない（クズ野菜ベースへ自動で切り替わる）。
			# kind:"rent"（チンピラの場所代）が実際に払えたときだけ、払い終えた印を付ける
			# （閉店直前の特別請求が二重にならないようにするため。§11「未解決」の直し方）。
			if _pay_or_game_over(int(ev.get("amount", 0))) and ev.get("kind", "") == "rent":
				GameState.mark_rent_paid()
		"ADD_ITEM":
			GameState.add_inventory(ev.get("item", ""), int(ev.get("amount", 1)))
		"REMOVE_ITEM":
			GameState.remove_inventory(ev.get("item", ""), int(ev.get("amount", 1)))
		"ADJUST":
			# 同じ客の2杯目以降：新しい椀へ切り替える。ADJUST は入力待ちで、具材を選べる前に
			# 「新しく current になった瞬間」に1回だけここへ来るので、必ず選ぶ前に新しくなる。
			if ev.get("new_bowl", false) and _open != null:
				_open.reset_bowl()
		"SET_SOUP":
			# 鍋を作るのは GameState.set_soup 経由（受け側は soup を直接触らない）。
			# 7.6: servings（残量の初期値＝仕込んだ杯数）、strength（濃さ）、
			#   water_doses（今夜使える水の回数）も Event から受け取る。
			GameState.set_soup(str(ev.get("base_id", "")), ev.get("tags", []),
				int(ev.get("servings", 0)),
				int(ev.get("strength", 3)),
				int(ev.get("water_doses", 0)))
		"REACT":
			# 7.6: 提供しようとした時点で残量が servings に足りないとき、
			# 条件1（名前あり客がもう残っていない）と条件2（水が無い）の成立具合で分かれる：
			#   両方成立     → 自動的に閉店（_auto_close_kitchen。選ぶ余地が無い）
			#   それ以外     → 保留してプレイヤーに選ばせる（_pending_shortage_ev。
			#                  [鍋を見る]で作り直すか[閉店]するか）
			# 「残量 ≥ servings のときだけ提供できる」ルールで、ADJUSTの[入力完了]が不足時は
			# 押せないので、通常ここには足りているときしか来ない。不足で来てしまった場合の
			# 保険として、薄めて満額で出す道は無くし、必ず保留に落とす。
			# 効果の適用自体は _serve_customer() に切り出した（[戻る]からも呼ぶ共通処理）。
			var servings := int(ev.get("servings", 1))
			var available := 0
			if GameState.soup != null:
				available = int(GameState.soup.get("remaining_servings", 0))
			if available < servings:
				var named_done := _no_named_customers_remaining()
				var resources_gone := _no_resources_left()
				if named_done and resources_gone:
					_auto_close_kitchen()
					return
				_pending_shortage_ev = ev
				return
			_serve_customer(ev)


## REACT の効果を実際に適用する（判定→評判→鍋の消費→売上→記録）。
## 通常の提供（_apply_event から）と、鍋を作り直した後の [戻る]（_on_pot_back_pressed）
## の両方から呼ばれる共通処理。Event（reactions）は書き換えない
## （DESIGN.md 確定事項「Event はデータ、処理は受け側」）。
## どの反応textを見せるかは表示側 _current_reaction_text() が都度選ぶ。
##
## REACT のフラグ（どちらも既定値なら従来どおり＝判定して、評判・記録もその場で反映）：
##   judge:false     … 判定しない（judge_bowl を呼ばない）。評判は動かない。評価も付かない
##                     杯（例：配達員の持ち帰り）。鍋の消費と売上は通常どおり
##   aggregate:true  … 鍋の消費と売上はその場で反映するが、評判と提供記録は _visit_tally に
##                     積み、退店時に客1人分として1回だけ反映する（_flush_visit_tally）
func _serve_customer(ev: Dictionary) -> void:
	var sale := int(ev.get("sale", 0))
	var servings := int(ev.get("servings", 1))
	var judged: bool = bool(ev.get("judge", true))
	var aggregate: bool = bool(ev.get("aggregate", false))
	var result := ""
	var delta := 0
	if judged:
		if _open != null:
			result = _open.judge_bowl(ev.get("wanted_tags", []), str(ev.get("favorite", "")))
		var table: Dictionary = REPUTATION_MOB if ev.get("is_mob", false) else REPUTATION_NAMED
		delta = int(table.get(result, 0))
	GameState.consume_soup(servings)
	GameState.apply_money(sale)
	if aggregate:
		_add_to_visit_tally(str(ev.get("customer", "")), judged, delta, sale, servings, result)
		return
	if judged:
		GameState.apply_reputation(delta)
	# 日次ログ：判定結果ごとに集計する。judged=falseの杯（配達員の持ち帰り等）は
	# result=""のまま（判定なしと分かる値。指示文どおり）。
	_log_quality_counts[result] = int(_log_quality_counts.get(result, 0)) + servings
	GameState.record_served({ "customer": ev.get("customer", ""), "sale": sale,
		"servings": servings, "result": result })


## 集計（_visit_tally）に1杯分を積む。判定した杯だけ評判の増減を積み（評価なしの杯は
## 積まない）、売上と杯数は全杯を積む。
## 日次ログ：resultsに判定結果ごとの杯数も積んでおく（_flush_visit_tallyで
## _log_quality_countsへ合算し、record_servedにも残す。判定なしの杯はresult=""のまま）。
func _add_to_visit_tally(customer: String, judged: bool, delta: int, sale: int,
		servings: int, result: String = "") -> void:
	if _visit_tally.is_empty():
		_visit_tally = { "customer": customer, "rep_sum": 0, "rep_count": 0,
			"sale": 0, "servings": 0, "results": {} }
	if judged:
		_visit_tally["rep_sum"] = int(_visit_tally["rep_sum"]) + delta
		_visit_tally["rep_count"] = int(_visit_tally["rep_count"]) + 1
	_visit_tally["sale"] = int(_visit_tally["sale"]) + sale
	_visit_tally["servings"] = int(_visit_tally["servings"]) + servings
	var results: Dictionary = _visit_tally["results"]
	results[result] = int(results.get(result, 0)) + servings


## 集計を客1人分として反映し、空にする（空なら何もしない＝何度呼んでも二重には効かない）。
## 評判：判定した杯の増減の平均を、四捨五入した整数で1回だけ適用する。
## roundi は半端を「ゼロから遠い側」へ丸める（Godot 4.4.1 で確認：roundi(2.5)=3、
## roundi(-2.5)=-3）。整数の割り算は切り捨てになるので使わず、浮動小数で割る。
## 例：GOOD(+2)とOK(0)→+1、GOOD(+2)とBAD(-2)→0、GREAT(+3)とGOOD(+2)→+3。
## 判定した杯が1つも無ければ評判は動かさない。提供記録は売上・杯数の合計で1件残す。
func _flush_visit_tally() -> void:
	if _visit_tally.is_empty():
		return
	var rep_count := int(_visit_tally["rep_count"])
	if rep_count > 0:
		GameState.apply_reputation(roundi(float(int(_visit_tally["rep_sum"])) / float(rep_count)))
	# 日次ログ：この客の杯ごとの判定結果を、その日の集計へ合算する。
	var results: Dictionary = _visit_tally.get("results", {})
	for key in results:
		_log_quality_counts[key] = int(_log_quality_counts.get(key, 0)) + int(results[key])
	GameState.record_served({ "customer": _visit_tally["customer"],
		"sale": int(_visit_tally["sale"]), "servings": int(_visit_tally["servings"]),
		"results": results })
	_visit_tally = {}


## もう水が無いか（DESIGN.md 7.6：自動閉店・選択待ちの条件2）。
## 残量を増やせるのは水だけ（ベースは濃さを上げるだけで、量は増やさない）ので、
## 不足を埋められるかの判定は水の有無だけを見る。
func _no_resources_left() -> bool:
	return not GameState.can_add_water()


## 今の客の注文（servings）に、鍋の残量が足りないか。ADJUST中の提供・廃棄の共通ルール：
## 残量 ≥ servings のときだけ提供も廃棄もできる（取り分けられる一杯が無ければ、
## 出すことも無駄にすることもできない）。客がいない・鍋が無いときは false。
func _is_short_now() -> bool:
	if _open == null or GameState.soup == null:
		return false
	return int(GameState.soup.get("remaining_servings", 0)) < _current_servings()


## ADJUST中（椀を作っている最中）で、鍋が足りないか。[入力完了]を止め、
## [鍋を見る]・[閉店]を出す条件に使う。
func _is_short_in_adjust() -> bool:
	return _is_choosing_ingredients() and _is_short_now()


## [閉店]を押せるか。鍋不足の保留中、または「ADJUST中で不足、かつ水が無い」
## （足せなければ閉店）。どちらも、その客には出せなかった扱いで CLOSE へ進む。
func _can_close_now() -> bool:
	return _pending_shortage_ev != null \
			or (_is_short_in_adjust() and _no_resources_left())


## 現在の客（含む）から OPEN 終了まで、名前あり客がもう出てこないか。
## 今の客自身が名前あり客なら、その客はまだ「済んでいない」ので false になる
## （＝名前あり客のREACT中に自動閉店の分岐1が成立することはない）。
func _no_named_customers_remaining() -> bool:
	if _open == null:
		return true
	var customers := _open.current_slot_customers()
	for i in range(_open.index, customers.size()):
		if not Day1Events.is_mob_customer(customers[i]):
			return false
	for s in range(_open.slot_index + 1, _open.schedule.size()):
		var slot = _open.schedule[s]
		if slot is Dictionary:
			for cid in slot.get("customers", []):
				if not Day1Events.is_mob_customer(cid):
					return false
	return true


## 義務的な支払い（水道代・場所代）。払えれば true。払えなければ支払いを実行せず
## （所持金はマイナスにならない）ゲームオーバーにして false を返す。
func _pay_or_game_over(amount: int) -> bool:
	if GameState.try_pay(amount):
		return true
	_game_over("所持金が足りない。支払えない（必要 ¥%d／所持 ¥%d）。" % [amount, GameState.money])
	return false


## ゲームオーバーにする。自動閉店（_auto_close_kitchen）と同じく force_phase で終端フェーズへ
## 飛ばす（_set_runner_for_phase の冒頭リセットで、OPEN・市場の途中状態も片付く）。
func _game_over(reason: String) -> void:
	_game_over_reason = reason
	flow.force_phase(GameState.Phase.GAME_OVER)


## 鍋が尽きて自動的に閉店する（DESIGN.md 7.6）。判定・売上・評判・鍋の消費は
## 一切行わない（この客には出せなかった、という扱い）。反応・セリフは最小の仮テキストのみ。
## FlowController.force_phase() でゲートを通さず CLOSE へ飛ばす
## （_open は _set_runner_for_phase(CLOSE) が既存の「OPEN以外ではnull」処理で片付ける）。
## _on_close_pressed と同じく、場所代が未払いならCLOSEへ飛ばす前に特別請求する。
func _auto_close_kitchen() -> void:
	var reason := _reason_after_collecting_rent("（鍋が尽きた。今日はもう終いだ。）")
	if reason == "":
		return
	_closed_early_reason = reason
	_log_closed_early = true   # 日次ログ：鍋が尽きて自動的に閉店した
	flow.force_phase(GameState.Phase.CLOSE)


## 未払いの場所代（徴収日のみ）があれば、閉店の直前に特別請求する共通処理
## （§11「未解決：閉店で場所代を避けられる」の直し方。手動閉店[_on_close_pressed]・
## 自動閉店[_auto_close_kitchen]の両方から呼ぶ）。
## 徴収日でない、またはもう払っている（GameState.rent_paid_today）ならbase_reasonを
## そのまま返す。未払いなら _pay_or_game_over(RENT_PRICE) で請求し、払えなければ
## 既存の水道代・場所代と同じくゲームオーバーへ飛ばして空文字を返す（呼び出し側は
## 空文字を見てCLOSEへ進まない・base_reasonが空文字になることは無いので安全に判別できる）。
## 払えたら、その旨を一言添えた理由テキストを返す。
func _reason_after_collecting_rent(base_reason: String) -> String:
	if not GameState.is_collection_day() or GameState.rent_paid_today:
		return base_reason
	if not _pay_or_game_over(GameState.RENT_PRICE):
		return ""
	GameState.mark_rent_paid()
	return base_reason + "（今月の場所代は、閉店前にきっちり払わせてもらった。）"


func _on_runner_updated() -> void:
	_refresh()


## 日次ログの本体（FlowController.day_ending。NEXT_DAY→WAKEの折り返しで、日次リセットの
## 前に発火する）。GameStateがまだその日の値のうちに集計を確定し、コンソールとファイルへ
## 出す。経済数値・計算式には一切手を入れない、記録専用の処理（BALANCE_REDESIGN_PLAN.md
## §8「①消費と鮮度の明確化・日次ログ」）。
func _on_day_ending() -> void:
	var served_cups := 0
	var sale_total := 0
	for record in GameState.served:
		if record is Dictionary and not bool(record.get("discarded", false)):
			served_cups += int(record.get("servings", 0))
			sale_total += int(record.get("sale", 0))
	var unserved_cups: int = maxi(_log_planned_cups - served_cups, 0)
	var spoiled_value_approx := _spoiled_value_approx(_log_spoiled_items)
	var log_entry := {
		"day": GameState.day_count,
		"opening_money": _log_opening_money, "closing_money": GameState.money,
		"opening_reputation": _log_opening_reputation, "closing_reputation": GameState.reputation,
		"planned_cups": _log_planned_cups, "served_cups": served_cups,
		"unserved_cups": unserved_cups, "sale_total": sale_total,
		"quality_counts": _log_quality_counts.duplicate(),
		"spoiled_items": _log_spoiled_items.duplicate(),
		"spoiled_value_approx": spoiled_value_approx,
		"water_used": _log_water_used, "base_used": _log_base_used,
		"closed_early": _log_closed_early,
	}
	print("BALANCE_LOG: day=%d money=%d→%d rep=%d→%d cups=%d/%d(計画%d) 売上=%d 廃棄概算=%d 水%d/ベース%d 早期閉店=%s 評価=%s" % [
		log_entry["day"], log_entry["opening_money"], log_entry["closing_money"],
		log_entry["opening_reputation"], log_entry["closing_reputation"],
		served_cups, unserved_cups, _log_planned_cups, sale_total, spoiled_value_approx,
		_log_water_used, _log_base_used, str(_log_closed_early), str(_log_quality_counts)])
	_append_balance_log_file(log_entry)


## discard_spoiled_inventory()の結果（品目id→個数）を、市場価格から割り出した
## 1杯あたり単価（price / GameState.INGREDIENT_SERVINGS_PER_PURCHASE）で概算する。
## ロットごとの実購入単価は記録していないため（BALANCE_REDESIGN_PLAN.mdが前提とする
## 将来のロット単価管理は今回のタスク対象外）、あくまで概算。
func _spoiled_value_approx(spoiled_items: Dictionary) -> int:
	var prices := Day1Events.ingredient_prices()
	var total := 0
	for item in spoiled_items:
		var unit_price: float = float(prices.get(str(item), 0)) / float(GameState.INGREDIENT_SERVINGS_PER_PURCHASE)
		total += int(round(unit_price * int(spoiled_items[item])))
	return total


## 日次ログをuser://配下へJSON Linesで追記する（1行1JSON。人が読むための整形は不要）。
func _append_balance_log_file(log_entry: Dictionary) -> void:
	var path := "user://balance_log.jsonl"
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BALANCE_LOG: failed to open %s (%s)" % [path, FileAccess.get_open_error()])
		return
	f.store_line(JSON.stringify(log_entry))
	f.close()


func _on_day_plus_pressed() -> void:
	GameState.advance_day()
	_refresh()


## デバッグ用：モブ人数の強制指定を 自動→1→2→3→4→自動 と回す。次に OPEN に入るときから効く。
func _on_mob_debug_pressed() -> void:
	_debug_mob_count = _debug_mob_count + 1 if _debug_mob_count < 4 else -1
	if _debug_mob_count == 0:
		_debug_mob_count = 1
	_btn_mob_debug.text = "モブ人数: %s" % ("自動" if _debug_mob_count < 0 else str(_debug_mob_count))
	_refresh()


## デバッグ用：所持金を delta だけ動かす（apply_money を通す＝本番と同じ入口）。
## 下限は設けない（マイナスにもなる＝ゲームオーバー系の確認にも使える）。
## PREPのベース分岐はPREPに入る瞬間に固定されるので、確認するときは PREP に入る前
## （WAKE中など）に押すこと。
func _on_money_debug_pressed(delta: int) -> void:
	GameState.apply_money(delta)
	_refresh()


func _refresh() -> void:
	_game_state_label.text = _format_game_state()
	# OPEN 中は runner 表示のあとに客キューの状態も出す。PREP 中は市場の状態を出す
	# （どちらも対象外のフェーズでは空文字なので、両方繋げても実害はない）。
	# スマホを開いている間は、会話・鍋・市場の文面をスマホの中身に差し替える（裏では
	# そのまま保持されているので、閉じれば元の表示に戻る。実データを消しはしない）。
	if _phone_mode:
		_runner_label.text = _format_phone()
	else:
		_runner_label.text = _format_runner() + _format_open() + _format_market()
	_update_options_row()


## 動的なボタン行の描画。毎回 _refresh() から呼び、状態から描き直す
## （他の表示と同じ「押した直後だけ更新」ではなく毎回作り直す方針）。
## 1つの行を3つの用途で使い分ける（各モードは互いに排他なので衝突しない）:
##   - 鍋モード中（7.6）… [水を足す] [ベースを足す] [戻る]
##   - MARKET中（7.7）  … 7店舗のボタン ＋ [市場を出る]
##   - それ以外          … ADJUST の具材ボタン（"options" を持つ WAITING_INPUT のときだけ）
## STEP 17.6: [入力完了] は ADJUST 中でも押せる（3枠未満でも提供できる仕様）。
##   具材が上限（MAX_ADDITIONS）に達したら具材ボタン側だけを無効化する。
## 7.6: [鍋を見る] は ADJUST 中だけ無効。鍋モード中は [次のEvent]/[入力完了] を無効に
##   して「会話が止まっている」ことを見た目にも合わせる。
## 7.6: 鍋が尽きて選択待ち（_pending_shortage_ev != null）のときは、それに加えて
##   [次のEvent]/[入力完了]も無効（保留を解決するまで進めない）。[鍋を見る]は
##   選択待ち中だけ「水かベースが残っているか」も条件に足す（無ければ作り直しようが
##   ないので、実質[閉店]しか選べない状態にする）。[閉店]は選択待ち中だけ有効。
## 7.7: MARKET中も [次のEvent]/[入力完了] を無効化する。抜ける経路を[市場を出る]
##   （水場未訪問なら自動で訪れる安全策を持つ）だけに絞るため。
## フェーズ1 ステップ4: [鍋を見る] は SERVE 中（[入力完了]で椀を確定した直後、
##   まだ判定[REACT]が適用される前）も無効にする。椀の中身は確定済みなのに、
##   ここで鍋の濃さを変えられると judge_bowl の結果が後から変わってしまうため
##   （_is_awaiting_react 参照）。
func _update_options_row() -> void:
	for child in _options_row.get_children():
		child.queue_free()

	# ボタンの有効/無効は毎回ここで決め直す（状態から描き直す方針に揃える）。
	# 鍋がまだ無い（仕込み前）ときも押せない。
	# ゲームオーバー後は、OPENで止まって鍋が残っていても鍋を触らせない。
	# [鍋を見る]：ADJUST中は原則触れない（作っている椀があるため）が、鍋が足りないときだけ
	# 触れる（水を足して足りれば提供できる）。足せるものが無いときは入れない（入っても出口が
	# 無くなるため）。不足を埋められるのは水だけなので、不足の文脈（保留中・ADJUSTで不足）では
	# 水の有無を、それ以外（濃さの調整）では水かベースがあるかを見る。
	# SERVE中（_is_awaiting_react）は不足の文脈になり得ない（ADJUSTの[入力完了]は不足時
	# 押せないので、無事SERVEまで来た時点で足りている）ため、無条件で塞いでよい。
	var shortage_context := _pending_shortage_ev != null or _is_short_in_adjust()
	var nothing_to_add: bool
	if shortage_context:
		nothing_to_add = _no_resources_left()
	else:
		nothing_to_add = not GameState.can_add_water() and not GameState.can_add_base()
	var pot_disabled := GameState.soup == null or _pot_mode \
			or (_is_choosing_ingredients() and not _is_short_now()) \
			or _is_awaiting_react() \
			or GameState.phase == GameState.Phase.GAME_OVER or nothing_to_add
	_btn_pot.disabled = pot_disabled or _phone_mode
	_btn_next_event.disabled = _pot_mode or _pending_shortage_ev != null or _is_in_market() or _phone_mode
	# 不足のADJUSTでは提供（[入力完了]）できない。補充するか、閉店するか廃棄以外を選ぶ。
	_btn_complete_input.disabled = _pot_mode or _pending_shortage_ev != null \
			or _is_in_market() or _is_short_in_adjust() or _phone_mode
	_btn_close.disabled = not _can_close_now() or _phone_mode
	_btn_next_phase.disabled = _phone_mode
	# スマホ自体は、開いている間だけ無効化する（隠さない。押せないボタンとして残す）。
	_btn_phone.disabled = _phone_mode

	# スマホは3つ目の入れ子モード（鍋・市場と同じくEventRunnerには触れない）。他のどの
	# モードよりも最優先で判定し、真なら通常のADJUST/鍋/市場ボタンの代わりにタブ＋
	# [閉じる]を出して return する（_pot_mode/_market_shopの値はそのまま裏で保持される）。
	if _phone_mode:
		var tabs := [["recipe", "レシピ"], ["news", "ニュース"], ["sns", "SNS"]]
		for tab in tabs:
			_add_pot_button(tab[1], _phone_tab == tab[0], _on_phone_tab_selected.bind(tab[0]))
		_add_pot_button("閉じる", false, _on_phone_close_pressed)
		return

	if _pot_mode:
		var locked := _pot_locked_until_water()
		_add_pot_button("水を足す（残量+%d 濃さ-1）" % GameState.WATER_SERVINGS,
			not GameState.can_add_water(), _on_add_water_pressed)
		_add_pot_button("ベースを足す（濃さ+1）",
			not GameState.can_add_base() or locked, _on_add_base_pressed)
		# 水待ちで[戻る]を塞ぐのは、[水を足す]で解ける（水がある）ときだけ。
		# 水が無ければ塞がない＝鍋モードには必ず出口がある。
		_add_pot_button("戻る", locked and GameState.can_add_water(), _on_pot_back_pressed)
		return

	var r: EventRunner = flow.runner
	if r == null or r.status != EventRunner.Status.WAITING_INPUT:
		return
	var cur = r.current()
	if not (cur is Dictionary) or not cur.has("options"):
		return

	if cur.get("type", "") == "MARKET":
		if _market_shop != "":
			for good in _shop_goods(_market_shop):
				var gid: String = str(good.get("id", ""))
				var price: int = int(good.get("price", 0))
				var bought: bool = gid == "reserve_base" and GameState.reserve_base_purchased
				_add_pot_button("%s（-%d）%s" % [str(good.get("label", gid)), price, "（購入済み）" if bought else ""],
					GameState.money < price or bought, _on_shop_item_selected.bind(_market_shop, gid))
			_add_pot_button("市場に戻る", false, _on_shop_exit_pressed)
			return
		for option in cur.get("options", []):
			var id: String = str(option.get("id", ""))
			var disabled: bool = not bool(option.get("enabled", true))
			if id == "water" and _market_visited_water:
				disabled = true
			_add_pot_button(str(option.get("label", id)), disabled,
				_on_market_stall_selected.bind(id))
		_add_pot_button("市場を出る", false, _on_market_exit_pressed)
		return

	var at_cap := false
	if _open != null:
		at_cap = _open.current_bowl.get("additions", []).size() >= OpenController.MAX_ADDITIONS
	var servings := _current_servings()
	for option in cur["options"]:
		var opt_id: String = str(option.get("id", ""))
		# 7.7: options は接客開始時に1回だけ組み立てた在庫のスナップショット（MARKETの
		# enabledと同じく読むだけで書き換えない）。同じ接客中に選び尽くして0になる分は
		# ここでライブの在庫数を見て無効化し直す（水場ボタンと同じ形）。
		# DESIGN.md 7.6「具材 −人数分」：1回選ぶと servings 個消費するので、
		# servings に満たない残りしか無ければ押せない（黙って端数だけ消費させない）。
		# 鮮度: 押した側のバケツが1個以上あり、かつ両バケツの合計が servings 以上なら押せる
		# （不足はもう一方で補う。押した側が空のボタンで傷みの有無を選び直せないようにする）。
		var opt_damaged: bool = bool(option.get("damaged", false))
		var own: int = GameState.damaged_count(opt_id) if opt_damaged else GameState.fresh_count(opt_id)
		var out_of_stock: bool = own < 1 \
			or GameState.fresh_count(opt_id) + GameState.damaged_count(opt_id) < servings
		var btn := Button.new()
		btn.text = str(option.get("label", opt_id if opt_id != "" else "?"))
		btn.disabled = at_cap or out_of_stock
		btn.pressed.connect(_on_ingredient_selected.bind(opt_id, opt_damaged))
		_options_row.add_child(btn)
	# [廃棄する]：枠が0〜3個どの状態でも／at_cap・在庫切れに関係なく押せるが、鍋の残量が
	# 客の注文（servings）に満たないときは無効（無駄にできる一杯が無い）。鍋モードの[戻る]・
	# MARKETの[市場を出る]と同じ「今のモードに常駐する専用ボタン」の扱い。
	_add_pot_button("廃棄する", _is_short_now(), _on_discard_pressed)


## 動的なボタンを1つ並べる（鍋モード・市場の両方で使う汎用ヘルパー）。
func _add_pot_button(label: String, is_disabled: bool, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.disabled = is_disabled
	btn.pressed.connect(handler)
	_options_row.add_child(btn)


func _format_game_state() -> String:
	var phase_name: String = GameState.Phase.keys()[GameState.phase]
	# soup は { base_id, tags[], remaining_servings }（STEP 12 / 7.6）。生 Dictionary は
	# 読みにくいので整形する。
	var soup_text := "(none)"
	if GameState.soup != null:
		# 7.6: 残量（あと何杯出せるか）を併記する。分母（仕込み量）は出さない
		# ＝水やベースを足せば初期値を超えるので、比率ではなく絶対値で見る。
		# 濃さは 1〜5（3がちょうどいい）。表示名（水っぽい等）はまだ付けない。
		soup_text = "%s 残量%d杯 濃さ%d tags=%s" % [
			GameState.soup.get("base_id", "?"),
			int(GameState.soup.get("remaining_servings", 0)),
			int(GameState.soup.get("strength", 0)),
			str(GameState.soup.get("tags", [])),
		]
	# 表示する各項目の意味（GameState = 日をまたいで残る事実）:
	#   day_count  … 今が何日目か。NEXT_DAYで+1
	#   money      … 所持金。支払いで減り売上で増える
	#   reputation … 店の評判値。REACT の判定結果で増減する（7.6）
	#   inventory  … 持っている具材・調味料の合計個数（辞書 { id: 個数 } の値を合計。7.7）
	#   inventory_detail … 品目ごとの内訳（7.7：市場で複数品目を買うと合計数だけでは
	#                 「何が増えたか」が分からないため、id:個数の一覧を別行で出す）
	#   rumors     … スマホで得た噂の件数。今は未使用
	#   phase      … 一日のどの段階か（WAKE→PREP→OPEN→CLOSE→NEXT_DAY）
	#   soup       … 仕込んだ鍋と残量・濃さ。仕込み前はnone。翌日リセット
	#   pot        … 鍋に足せる資源。水は今夜だけ（soupの中）、予備ベースは翌日へ持ち越す
	#                 （GameState直下）。寿命が違うので soup とは行を分けている
	#   served     … 接客数と杯数（servingsの合計）。翌日リセット。どちらも廃棄
	#                 （discarded:true）を除く＝客に何も出していないので混ぜない
	#   discarded  … 廃棄した件数（廃棄機能の追加時に新設。servedとは別枠で見せる）
	#                 7.6 で1回の接客が複数杯になったので、接客数と杯数は両方出さないと誤読する
	# ラベルは「項目(意味): 値」の形。値の算出ロジックは変更していない。
	var water_doses := 0
	if GameState.soup != null:
		water_doses = int(GameState.soup.get("water_doses", 0))
	return "\n".join(PackedStringArray([
		"── GameState（日をまたいで残る事実）──",
		"day_count(日数): %d" % GameState.day_count,
		"money(所持金): %d" % GameState.money,
		"reputation(評判): %d" % GameState.reputation,
		"inventory(在庫数): %d 個" % _inventory_total(),
		"inventory_detail(内訳): %s" % _format_inventory_detail(),
		"rumors(情報数): %d 件" % GameState.rumors.size(),
		"phase(現在フェーズ): %s (%d)" % [phase_name, GameState.phase],
		"soup(今日の鍋): %s" % soup_text,
		"pot(鍋の資源): 水%d回 / 予備ベース%d単位%s" % [water_doses, GameState.reserve_base_units,
			"（購入分%d単位は傷んでいる）" % GameState.reserve_base_purchase_remaining if GameState.is_reserve_base_damaged() else ""],
		"served(接客数/杯数): %d / %d" % [_served_count(), _served_servings()],
		"discarded(廃棄数): %d 件" % _discarded_count(),
	]))


## 今夜出した接客数（served配列のうち discarded ではないものの件数）。
func _served_count() -> int:
	var count := 0
	for record in GameState.served:
		if record is Dictionary and not bool(record.get("discarded", false)):
			count += 1
	return count


## 今夜出した杯数の合計（ServedRecord の servings を足す）。discarded は除く
## （客に何も出していないので、sale・servingsの集計に混ぜない）。
func _served_servings() -> int:
	var total := 0
	for record in GameState.served:
		if record is Dictionary and not bool(record.get("discarded", false)):
			total += int(record.get("servings", 1))
	return total


## 廃棄した件数（served配列のうち discarded:true のものの件数）。
func _discarded_count() -> int:
	var count := 0
	for record in GameState.served:
		if record is Dictionary and bool(record.get("discarded", false)):
			count += 1
	return count


## 在庫の合計個数（GameState.inventory は { id: 個数 } の辞書なので、
## 値を合計して出す。STEP 4当時のArray.size()と同じ「持っている総数」を保つ・7.7）。
func _inventory_total() -> int:
	var total := 0
	for count in GameState.inventory.values():
		total += int(count)
	return total


## 在庫の品目別内訳（7.7：市場で何を買ったかを目で確認できるようにするため）。
## 例: "winter_melon:5 tofu:4(新鮮3・傷1)"。空なら "(なし)"。
## 腐る品目だけ、傷んだ分があるときに内訳を添える（傷＝使えるが判定-1段階）。
## キーの並びはDictionaryの挿入順（買った順）でよい・ソートはしない。
func _format_inventory_detail() -> String:
	if GameState.inventory.is_empty():
		return "(なし)"
	var parts := PackedStringArray()
	for id in GameState.inventory:
		var entry := "%s:%d" % [str(id), int(GameState.inventory[id])]
		if Ingredients.is_perishable(str(id)):
			var bad := GameState.damaged_count(id)
			if bad > 0:
				entry += "(新鮮%d・傷%d)" % [GameState.fresh_count(id), bad]
		parts.append(entry)
	return " ".join(parts)


## スマホの本文（シェルのみ。中身は今回すべてプレースホルダー。DESIGN.md該当箇所は
## 別タスクでレシピ／ニュース／SNSの実データを積むときに更新する）。
func _format_phone() -> String:
	var body: String
	match _phone_tab:
		"news":
			body = "ニュース：まだ届いていません"
		"sns":
			body = "SNS：まだ新着はありません"
		_:
			body = "レシピ：まだ記録がありません"
	return "── スマホ ──\n%s" % body


func _format_runner() -> String:
	var r: EventRunner = flow.runner
	if r == null:
		return "── EventRunner（イベント列の再生位置）──\n(none)"
	var status_name: String = EventRunner.Status.keys()[r.status]
	var cur = r.current()
	var cur_text := "(none)" if cur == null else str(cur)
	# 表示する各項目の意味（EventRunner = イベント列の再生位置）:
	#   events      … 現フェーズに積まれたイベント数
	#   index       … そのうち今何番目を処理中か（0起点）
	#   status      … PLAYING=自動 / WAITING_INPUT=入力待ち停止 / DONE=消化済み
	#   current     … OPEN中に接客している客。それ以外はnone
	#   runner_done … statusがDONEか。trueで次フェーズへ進める合図
	# ラベルは「項目(意味): 値」の形。値の算出ロジックは変更していない。
	return "\n".join(PackedStringArray([
		"── EventRunner（イベント列の再生位置）──",
		"events(イベント総数): %d" % r.events.size(),
		"index(現在位置): %d" % r.index,
		"status(進行状態): %s (%d)" % [status_name, r.status],
		"current(接客中の客): %s" % cur_text,
		"runner_done(完了フラグ): %s" % str(flow.is_runner_done()),
		# STEP 4: このフェーズは DONE 必須か。ブロック中なら [次のPhase] は no-op。
		"next_phase(次へ進めるか): %s" % ("OK" if not flow.is_advance_blocked() else "ブロック中(runner未DONE)"),
	]))


## OPEN 中の客キュー状態（STEP 6）。OPEN 以外は空文字を返し、表示に何も足さない。
##   時間帯   … いまの時間帯名と「何番目/全体」（7.6）。使い切っていれば (終了)
##   queue    … **その時間帯の**客数（7.6 で1日の総数から意味が変わった）
##   customer … いま接客中の客 id と「その時間帯の中で何人目/その時間帯の人数」、
##              この接客で出す杯数。全員終わっていれば (なし)
##   open_done … 全時間帯をさばき切ったか。true で [次のPhase] → CLOSE へ進める
##   pending   … 鍋が尽きて[鍋を見る]/[閉店]の選択待ちか（7.6）
func _format_open() -> String:
	if _open == null:
		return ""
	var slot_customers: Array = _open.current_slot_customers()
	var slot_text := "(終了)"
	if _open.current_slot_name() != "":
		slot_text = "%s (%d/%d)" % [
			_open.current_slot_name(), _open.slot_index + 1, _open.schedule.size()]
	var cust = _open.current_customer()
	var cust_text := "(なし)"
	if cust != null:
		cust_text = "%s (%d/%d) %d杯" % [
			cust, _open.index + 1, slot_customers.size(), _current_servings()]
	var lines := PackedStringArray([
		"── OpenController（客キュー）──",
		"時間帯: %s" % slot_text,
		"queue(この時間帯の客数): %d" % slot_customers.size(),
		"customer(接客中): %s" % cust_text,
		"open_done(さばき切った): %s" % str(_open.is_open_done()),
		"pending(鍋の選択待ち): %s" % ("はい" if _pending_shortage_ev != null else "いいえ"),
	])
	# 1杯ずつ接客する客の集計中だけ出す（退店時に評判・提供記録として1回反映される）。
	if not _visit_tally.is_empty():
		lines.append("visit(この客の集計): 評価%d件 評判増減の合計%d 売上%d %d杯" % [
			int(_visit_tally["rep_count"]), int(_visit_tally["rep_sum"]),
			int(_visit_tally["sale"]), int(_visit_tally["servings"])])
	return "\n" + "\n".join(lines) + _format_bowl()


## PREP中の市場の状態（DESIGN.md 7.7）。PREP以外は空文字（表示に何も足さない）。
func _format_market() -> String:
	if GameState.phase != GameState.Phase.PREP:
		return ""
	var lines := PackedStringArray([
		"── 市場（7.7）──",
		"base(今日のベース): %s" % ("端材屋のクズ野菜（濃さ1スタート）" if _scraps_base else "食肉仲卸"),
		"water(水場訪問済み): %s" % ("はい" if _market_visited_water else "いいえ"),
	])
	# 専用Eventを持たない店（水場等）のセリフはここでしか表示されないので、
	# 空文字でなければ出す（訪問前は _market_last_text が空のまま＝何も足さない）。
	if _market_last_text != "":
		lines.append("last(直前の会話): %s" % _market_last_text)
	return "\n" + "\n".join(lines)


## いま接客中の客が何杯注文しているか（7.6）。REACT がまだ current でなくても見たいので、
## runner の Event 列から REACT を探して servings を読む（Event はデータなので読むだけ）。
## 探すのは「今の位置から先の最初のREACT」で、先に無ければ「直前のREACT」（_react_for_now）。
## 1杯ずつ接客する客（REACTが複数ある客）でも、今の杯の値を返せる。REACTが1つだけの客は、
## どの位置でも従来と同じ値になる。
func _current_servings() -> int:
	var react := _react_for_now()
	if react.is_empty():
		return 0
	return int(react.get("servings", 1))


## いま見ている杯に対応するREACT Event（先の最初、無ければ直前の最後）。無ければ空辞書。
## 客のEvent列に REACT が複数ある（1杯ずつ接客する）場合に、今の杯の REACT を引くための
## 読み取り専用の探索。Event はデータなので書き換えない。
func _react_for_now() -> Dictionary:
	if flow.runner == null:
		return {}
	var events: Array = flow.runner.events
	var start: int = clampi(flow.runner.index, 0, events.size())
	for i in range(start, events.size()):
		var ev = events[i]
		if ev is Dictionary and ev.get("type", "") == "REACT":
			return ev
	for i in range(start - 1, -1, -1):
		var ev = events[i]
		if ev is Dictionary and ev.get("type", "") == "REACT":
			return ev
	return {}


## 接客中の椀（STEP 13）。DESIGN.md 9.5 STEP 11「椀の最終tags = Soup.tags +
## Bowl.additions 内の Ingredient.tags」を OpenController.bowl_final_tags() で計算して見せる。
## additions の件数表示 (n/上限) は STEP 17.6（今何個入っているか・残り枠が見えるように）。
## STEP 17.6（第二・第三段階）の表示:
##   bowl_tags  … 判定に使う3枠だけのtags（鍋を含まない）
##   final_tags … 鍋込みの椀の最終tags（表示用。判定には使っていない）
##   favorite   … その客の好物idと、実際に入っていたか（判定後だけ出す。ADJUST中に
##                出すと「会話から推測する」検証にならないため）
##   judge      … BAD/OK/GOOD/GREAT と一致数（REACT 適用前は「(未定)」）。
##                濃さ1/5で1段下げたときは、その旨を付け足す（7.6）
##   reaction   … 反応text。判定結果は【】でここ（表示側）が付ける。
##                データ（reactions の文言）には入れない＝本番UIでは付けなければよい
## 椀が無い（客がいない）ときは空文字（表示に何も足さない）。
func _format_bowl() -> String:
	if _open == null or not _open.current_bowl.has("customer_id"):
		return ""
	var additions: Array = _open.current_bowl.get("additions", [])
	var result: String = str(_open.current_bowl.get("result", ""))
	var judge_text := "(未定)"
	# 評価しない杯（REACT に judge:false。例：持ち帰り用の杯）は、判定前から
	# 「(評価なし)」と出す（「まだ判定していないだけ」に見えないように）。
	if result == "" and not bool(_react_for_now().get("judge", true)):
		judge_text = "(評価なし)"
	if result != "":
		var base_result: String = str(_open.current_bowl.get("base_result", result))
		var penalty_suffix := ""
		if base_result != result:
			# 下げる理由を併記する（両方成立しても下げるのは1段階だけ）。
			var reasons := PackedStringArray()
			if _open.current_bowl.get("penalty_strength", false):
				reasons.append("濃さ%d" % int(_open.current_bowl.get("strength_at_judge", 0)))
			if _open.current_bowl.get("penalty_spoiled", false):
				reasons.append("傷んだ具材")
			penalty_suffix = " → %sで1段下げ" % "・".join(reasons)
		# 具なし（フェーズ1 ステップ3）で強制BADになった場合、一致数だけ見ると
		# なぜBADなのか分からないので理由を併記する。
		var no_topping_suffix := "・具なし" if _open.current_bowl.get("no_topping", false) else ""
		judge_text = "%s (一致%d%s%s%s)" % [
			result,
			int(_open.current_bowl.get("match_count", 0)),
			" + favorite" if _open.current_bowl.get("has_favorite", false) else "",
			no_topping_suffix,
			penalty_suffix,
		]
	var lines := [
		"── Bowl（接客中の椀）──",
		"additions(具材): %s (%d/%d)" % [str(additions), additions.size(), OpenController.MAX_ADDITIONS],
		"bowl_tags(3枠のtags): %s" % str(_open.bowl_addition_tags()),
		"final_tags(最終tags): %s" % str(_open.bowl_final_tags()),
	]
	# favorite は判定後（REACT適用後）だけ出す。判定前は好物を伏せておく。
	var favorite: String = str(_open.current_bowl.get("favorite", ""))
	if result != "" and favorite != "":
		var in_bowl: bool = _open.current_bowl.get("has_favorite", false)
		lines.append("favorite(好物): %s → %s" % [favorite, "入っている" if in_bowl else "入っていない"])
	lines.append("judge(判定): %s" % judge_text)
	# 廃棄回数（0回なら出さない）。椀自体は廃棄のたびに作り直されて消えるので、
	# 「この客で何回作り直したか」は current_bowl とは別に _bowl_discard_count で持つ。
	if _bowl_discard_count > 0:
		lines.append("discard_count(この客での廃棄回数): %d回" % _bowl_discard_count)
	var reaction := _current_reaction_text()
	if reaction != "":
		lines.append("reaction(反応): 【%s】%s" % [result, reaction])
	return "\n" + "\n".join(PackedStringArray(lines))


## 現在の Event が REACT のときだけ、判定結果に応じた反応textを選んで返す（STEP 16〜17.6）。
## Event（reactions）は書き換えない。判定結果（BAD/OK/GOOD/GREAT）をキーにして引くだけ。
## 各段階2パターンあり、どれを見せるかは judge_bowl() が一度だけ抽選して
## current_bowl["reaction_variant"] に記録済みのものを使う
## （ここで再抽選すると、再描画のたびに表示が変わってしまうため）。
## 判定前は result が空文字でキーに当たらないので、自動的に空文字になる。
## REACT 以外（GREET/ADJUST/SERVE など）や runner が無いときも空文字（表示に何も足さない）。
func _current_reaction_text() -> String:
	var r: EventRunner = flow.runner
	if r == null or _open == null:
		return ""
	var cur = r.current()
	if not (cur is Dictionary) or cur.get("type", "") != "REACT":
		return ""
	var result: String = str(_open.current_bowl.get("result", ""))
	var reactions: Dictionary = cur.get("reactions", {})
	var pool: Array = reactions.get(result, [])
	if pool.is_empty():
		return ""
	var variant: int = _open.current_bowl.get("reaction_variant", 0)
	return str(pool[variant % pool.size()])
