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
# 調味料・具材のボタンを2行に分ける（C）：ADJUSTのときだけ調味料側をここに出す。
# それ以外の文脈（市場・仕込み段階・鍋モード等）では空のまま（_options_rowのみ使う）。
@onready var _seasoning_row: HBoxContainer = $Margin/VBox/SeasoningRow as HBoxContainer
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

# 判定結果 → 評点（BALANCE_REDESIGN_PLAN.md§5「評判・需要・日程」）。名前あり客・モブの
# 区別はなくなり、どの客でも共通の得点表を使う（旧REPUTATION_NAMED/REPUTATION_MOBは
# ④評判の更新+⑤客数の決め方で廃止。評判は閉店時に_quality_score()の結果をまとめて
# GameState.settle_reputation()へ渡す1回だけの処理に変わった＝杯ごとの即時加算はしない）。
const REPUTATION_SCORE := { "GREAT": 100, "GOOD": 75, "OK": 35, "BAD": 0 }

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

# 鍋モードに入った時点で濃さ0（提供不可）だった場合、濃縮だしを入れるまでの間だけ true。
# _pot_water_added と同じ形（濃さメカニクス三点セット）。_on_pot_pressed() で毎回リセットする。
var _pot_dashi_added := false

# 市場（DESIGN.md 7.7）で水場に寄ったか。PREPに入るたびリセットする。
var _market_visited_water := false

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
#   { customer, sale, servings, results, pending_favorite }
# 提供記録は杯ごとではなく客1人分として退店時に1回だけ反映するため、ここに積む
# （_flush_visit_tally）。鍋の消費と売上は杯ごとにその場で反映する（集計するのは
# 提供記録だけ。評判はもう杯ごと・客ごとに積まず、日次ログ全体から閉店時に
# GameState.settle_reputation()で1回だけ計算し直す＝④評判の更新）。客のrunnerが
# DONEになったとき、またはフェーズが替わるとき（途中閉店・ゲームオーバー）に
# 空にする＝二重に反映されない。
var _visit_tally := {}

# デバッグ用：今夜のモブ人数の強制指定（-1＝自動）。Day2-7ダミーデータ・モブ抽選独立化で、
# Day1Events.customer_schedule()へそのまま渡す値になった（枠ごとに種類も人数も独立抽選する
# ため、-1以外なら全モブ枠の人数だけを一律で上書きする。種類はそれでも枠ごとにばらつく）。
# OPENに入る瞬間に読まれるので、変えるなら OPEN に入る前（WAKE・PREP中）に押すこと。
# GameState には持たせない（本番の挙動・データには関係しない、この計器盤だけの検証用の上書き）。
var _debug_mob_count := -1

# 今夜の客の並び（予告メモ・作業ゲー化対策）。以前はOPENに入る瞬間にcustomer_schedule()
# を呼んで初めて決まっていた（＝プレイヤーは開店するまで客層も人数も分からなかった）ため、
# WAKEに入った瞬間にここで1回だけ確定させ、OPENでは（デバッグ上書き中を除き）これを
# そのまま使い回す。スマホの「SNS」タブ（_format_tonight_memo）が見せる内容も
# ここを参照する＝スマホの開閉や表示の都合で再抽選されることはない。
var _tonight_schedule: Array = []

# 前日の営業成績（翌朝のWAKE先頭で一度だけ見せる一言サマリー）。_game_over_reasonと
# 同じ「一度だけ消費するテキスト」の形。_on_day_ending()（day_ending。NEXT_DAY→WAKEの
# 折り返し直前に発火）で組み立て、次にWAKEのrunnerを組むときに読んで空文字へ戻す。
var _last_day_summary_text := ""

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
var _log_judged_planned_cups := 0   # 同上のうちjudge:false（配達員の持ち帰り等）を除いた分。
									 # ④評判の更新：当夜品質Qの分母に使う（_quality_score参照）
var _log_water_used := 0            # [水を足す]を押した回数
var _log_dashi_used := 0            # [だしを足す]を押した回数（旧_log_base_used）
var _log_closed_early := false      # 鍋不足等でCLOSEへ強制遷移したか
var _log_quality_counts := {}       # {"GREAT":n, "GOOD":n, "OK":n, "BAD":n, "":n(判定なし)}
var _log_spoiled_items := {}        # PREP突入時のdiscard_spoiled_inventory()の結果をそのまま保持

# --- ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6。モブ客の団体オーダーだけが対象） ---
# モブ客のADJUST中に選んだ具材を、在庫を引かずに一時記録するリスト（{"id":String,
# "damaged":bool}の配列）。人数が確定した瞬間（_serve_mob_partial）まで在庫消費を遅らせる
# ため、「選ぶ」と「消費する」を分離する置き場所。名前あり客・配達員は使わない
# （今までどおり選んだ瞬間に消費）。
var _mob_picks: Array = []

# [入力完了]を押して「N人分を提供／注文を断る」の確認ボタンを表示中か。
# trueの間、_update_options_row()はADJUSTの具材ボタンの代わりにこの2択を出す
# （_pot_mode/_phone_modeと同じ「専用ボタン行に差し替える」パターン）。
var _pending_group_choice := false

# 確認ボタンで確定した結果（{"servings": 実際に提供する人数, "ordered": 注文人数,
# "retry_remaining": 挑戦を選んだ場合の残り人数（挑戦しないときは省略/0）}）。
# 空でなければ、_apply_event()のREACTケースがこちらを使って_serve_mob_partial()／
# _serve_mob_recipe_and_retry()へ委譲する（名前あり客・配達員のREACTは常にこれが空
# なので既存の経路のまま無影響）。
var _pending_group_result := {}

# 団体客の分割提供（最大2レシピ）：グループの元々の総注文人数（レシピ2でも変わらない。
# _flush_visit_tally()でordered_servings/unserved_servingsを出すために覚えておく）。
# 新しい客をロードするたびにのみ-1へ戻す（_reset_mob_group_state()には入れない。
# こちらは[廃棄する]でも呼ばれるため、レシピ2の作り直し時に元注文数を消してしまう）。
var _mob_original_ordered := -1

# 今どちらのレシピを提供中か（1または2）。2に達したら「挑戦する」ボタンは出さない
# （最大2レシピの打ち止め）。_mob_original_ordered と同じ理由で客のロード時にのみ1へ戻す。
var _mob_recipe_number := 1


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
	_pot_dashi_added = false
	# 7.7: 市場の水場訪問フラグ・店の中にいるかも PREP に入るたびリセットする。
	_market_visited_water = false
	_market_shop = ""
	# スマホも鍋・市場と同じくフェーズをまたいで持ち越さない（防御的リセット）。
	_phone_mode = false
	_phone_tab = "recipe"
	if phase == GameState.Phase.WAKE:
		# 日次ログ：その日の開始時点として、所持金・評判を記録し、当日ぶんのカウンタを
		# 初期化する（前日の day_ending 発火はもう終わっている＝直前のログには影響しない）。
		# opening_moneyは日々の運営費を引く前の値（その日入ってきた素の所持金）にする。
		_log_opening_money = GameState.money
		_log_opening_reputation = GameState.reputation
		_log_planned_cups = 0
		_log_judged_planned_cups = 0
		_log_water_used = 0
		_log_dashi_used = 0
		_log_closed_early = false
		_log_quality_counts = { "GREAT": 0, "GOOD": 0, "OK": 0, "BAD": 0, "": 0 }
		_log_spoiled_items = {}
		# 日々の運営費（場所代・水道代の再編＋日々の運営費）：WAKEに入った瞬間に必ず1回
		# 直接支払う。wake_events()側にPAY Eventとして置かないのは、WAKEが
		# _phase_can_skip=true（[次のPhase]でrunnerを消化せず進める）なので、Event列に
		# 頼ると支払いを毎回スキップできてしまうため（_visit_water_stall()と同じ
		# 「Eventを介さず直接コードで払う」方式に揃える）。
		# 支払えずゲームオーバーになったら、force_phase(GAME_OVER)が既に
		# _set_runner_for_phase(GAME_OVER)を呼んでrunnerを組んでいるので、ここで
		# wake_events()のrunnerに上書きしないよう即returnする。
		if not _pay_or_game_over(GameState.DAILY_OPERATING_COST):
			return
		# 支払い予定（表示専用）：今日まだ物語上のけじめが付いていない金額を確定させる。
		# 徴収日は場所代ぶんも含む（GameState.set_pending_bills_for_today参照）。
		GameState.set_pending_bills_for_today()
		# 予告（②）：今夜の客の並びをここで1回だけ確定させ、OPENでは（デバッグの一律
		# 上書き中を除き）これを使い回す。以前はOPENに入る瞬間まで客層も人数も
		# 分からなかった＝プレイヤーが仕込み量を勘で決めるしかなかった詰みポイントの
		# 一つだったため、スマホの「SNS」タブ（_format_tonight_memo）で見せられる
		# ようにする。
		_tonight_schedule = Day1Events.customer_schedule(_debug_mob_count)
		# 前日の成績（③）：day_ending（NEXT_DAY→WAKEの折り返し）で既に組み立て済みの
		# 一言サマリーがあれば、今日の起床イベントの先頭に差し込む（読んだら消費する。
		# _closed_early_reason/_game_over_reasonと同じ「一度だけ」パターン）。
		var wake_ev := Day1Events.wake_events()
		if _last_day_summary_text != "":
			wake_ev = [{ "type": "TEXT", "text": _last_day_summary_text }] + wake_ev
			_last_day_summary_text = ""
		flow.set_runner(wake_ev)
	elif phase == GameState.Phase.PREP:
		# 具材の腐敗: PREPに入る瞬間に1回だけ、腐りきった在庫（4日目以降）を消して、
		# 捨てた品目を先頭の一言テキストで知らせる（市場で買い足しても救われない簡易版）。
		# クズ野菜ベース: 所持金が一番安い仕込み（PREP_TIERS[0]）にも満たなければ、
		# 3段階から選ばせず食肉仲卸ではなく端材屋へ回る（自動）。
		_scraps_base = GameState.money < int(Day1Events.PREP_TIERS[0].get("price", 0))
		var spoiled := GameState.discard_spoiled_inventory()
		_log_spoiled_items = spoiled   # 日次ログ用に保持（廃棄額の概算に使う）
		flow.set_runner(Day1Events.prep_events(spoiled, _scraps_base))
	elif phase == GameState.Phase.OPEN:
		# 客ループは OpenController に隔離（DESIGN.md 4章）。中身の再生は客ごとの runner。
		# モブの種類・人数は枠ごとにcustomer_schedule()が内部で独立抽選するので、ここでは
		# デバッグ用の一律上書き値（_debug_mob_count。-1=自動）をそのまま渡すだけでよい。
		# 予告（②）：通常はWAKEで確定させた_tonight_scheduleをそのまま使う（客層・人数を
		# 開店直前に変えない＝SNSタブで見せた内容と実際の客入りを一致させる）。
		# デバッグの一律上書き中（_debug_mob_count>=0）は、ボタンの「次にOPENに入る
		# ときから効く」という既存の挙動を保つため、ここで引き直す（QAの便宜。
		# SNSタブの表示が直前の内容と食い違う可能性があるのは元からデバッグ専用機能
		# なので許容する）。_tonight_scheduleが空（テスト等でWAKEを経由せずOPENへ直接
		# 遷移した場合の防御）のときも同様に引き直す＝WAKEを通らなくても従来どおり
		# 動く（この保険はデバッグ上書きが無い自動抽選でも効くので、テストからの
		# 直接呼び出しでcustomer_schedule()が空振りする心配は無い）。
		if _debug_mob_count >= 0 or _tonight_schedule.is_empty():
			_tonight_schedule = Day1Events.customer_schedule(_debug_mob_count)
		_open = OpenController.new(_tonight_schedule)
		# 日次ログ：その日の計画杯数（提供できたか否かに関わらず）を、実際の接客より前に
		# 先読みして合算する。customer_events()はGameState.day_countとJSONキャッシュを
		# 読むだけの副作用なし関数なので、ここで呼んでも以後の本編の進行に影響しない。
		# _log_judged_planned_cupsは同時に、judge:falseの杯（配達員の持ち帰り等）を除いた
		# 分も積む（④評判の更新：当夜品質Qの分母。判定対象ではない杯をQから除外するため）。
		_log_planned_cups = 0
		_log_judged_planned_cups = 0
		for slot in _open.schedule:
			for customer_id in slot.get("customers", []):
				for ev in Day1Events.customer_events(str(customer_id)):
					if ev.get("type", "") == "REACT":
						var ev_servings := int(ev.get("servings", 0))
						_log_planned_cups += ev_servings
						if bool(ev.get("judge", true)):
							_log_judged_planned_cups += ev_servings
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
	_reset_mob_group_state()   # ②拒否と部分提供：客が替わるたび選択中の具材・確認状態を破棄
	_mob_original_ordered = -1   # 団体客の分割提供：新しい客ごとにレシピ状態も破棄
	_mob_recipe_number = 1
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
## ②拒否と部分提供：モブ客のADJUST中に押した最初の一回は、まだ進めず
## 「N人分を提供／注文を断る」の確認ボタンへ差し替えるだけにする（_pot_mode等と同じ
## 「専用ボタン行に差し替える」パターン）。名前あり客・配達員は今までどおり即座に進む。
func _on_complete_input_pressed() -> void:
	if _is_current_mob_order() and not _pending_group_choice:
		_pending_group_choice = true
		_refresh()
		return
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
## ②拒否と部分提供：有効条件を「押した側のバケツに1個以上あるか」だけに簡略化した
## （旧条件の「fresh+damaged合計がservings以上」は、名前あり客・配達員（servings常に1）に
## 対しては数学的に同値なので、この2者の挙動は変わらない。モブ（servings>1）だけが
## 「揃わなくても選べる」ようになる）。
## モブ客（is_mob）は在庫をまだ引かない。_mob_picksへ記録するだけにして、実際の消費は
## 人数が確定した瞬間（_serve_mob_partial）まで遅らせる。名前あり客・配達員は
## 今までどおり選んだ瞬間に消費する。
func _on_ingredient_selected(ingredient_id: String, damaged: bool = false) -> void:
	var own: int = GameState.damaged_count(ingredient_id) if damaged else GameState.fresh_count(ingredient_id)
	if own < 1:
		return
	var added := _open != null and _open.add_to_bowl(ingredient_id, damaged)
	if not added:
		_refresh()
		return
	if _is_current_mob_order():
		_mob_picks.append({ "id": ingredient_id, "damaged": damaged })
	else:
		var servings := _current_servings()
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
	_reset_mob_group_state()   # ②拒否と部分提供：作り直すので選択中の具材・確認状態も破棄
	_refresh()


## [鍋を見る] のハンドラ（7.6）。モードに入るだけで、EventRunner には触れない。
## 鍋モードに入るたびに「水を入れたか」「だしを入れたか」をリセットする
## （_pot_locked_until_water / _pot_locked_until_dashi 用）。
func _on_pot_pressed() -> void:
	_pot_mode = true
	_pot_water_added = false
	_pot_dashi_added = false
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


## 鍋モードの [水を足す] / [だしを足す]。効果は GameState の入口にまとめてある
## （残量・濃さ・資源が同時に動くので、受け側から分けて呼べないようにしている）。
func _on_add_water_pressed() -> void:
	GameState.add_water()
	_pot_water_added = true
	_log_water_used += 1   # 日次ログ：水を足した回数
	_refresh()


func _on_add_dashi_pressed() -> void:
	GameState.add_dashi()
	_pot_dashi_added = true
	_log_dashi_used += 1   # 日次ログ：だしを足した回数
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
			if id == "dashi":
				if GameState.money >= price:
					GameState.apply_money(-price)
					GameState.buy_dashi()
			elif GameState.money >= price:
				var item = good.get("item", id)
				var count: int = int(good.get("count", 1))
				GameState.apply_money(-price)
				GameState.add_inventory(item, count, int(price / count) if count > 0 else price)
			break
	_refresh()


## 仕込み3段階（PREP_TIER）のボタンが押されたときのハンドラ。MARKETの商品選択と同じく
## 「押した瞬間にGameStateへ直接反映する」即時方式（EventRunnerのcomplete_input()は
## 経由しない）。ただしMARKETと違い一発選択で終わるため、選んだ段階を確定させたら
## 残りのPREP Event列（ADD_ITEM→市場→REMOVE_ITEM→SET_SOUP）をその場で組み立て直し、
## flow.set_runner()でrunnerごと差し替える（prep_events()を呼んだ時点ではまだ段階が
## 決まっていなかったため、SET_SOUPの杯数はここで初めて確定する。
## Day1Events.prep_after_tier_events参照）。
## 差し替え後の新しいEvent列の先頭はEventRunnerの仕様で効果が適用されない（index 0）ため、
## prep_after_tier_events()側で必ず効果の無いTEXTを先頭にしてある。
func _on_prep_tier_selected(tier_id: String) -> void:
	var tier := Day1Events.prep_tier_by_id(tier_id)
	var price: int = int(tier.get("price", 0))
	if GameState.money < price:
		return   # ボタン側で無効化済みのはずの二重チェック（防御的）
	GameState.apply_money(-price)
	flow.set_runner(Day1Events.prep_after_tier_events(tier, false))
	_refresh()


## [市場に戻る]（店から出る）。鍋モードの[戻る]と同じくEventRunnerには触れない。
func _on_shop_exit_pressed() -> void:
	_market_shop = ""
	_refresh()


## 水場を訪れる（水道代の支払いのみ。会話・ボタンは廃止し、[市場を出る]の際に
## 自動で1回だけ呼ばれる。場所代・水道代の再編＋日々の運営費：水場は市場のボタン
## 一覧には出さない。_market_visited_waterは「今日もう払ったか」の防御用に残す）。
## 水道代が払えずゲームオーバーになったら false（呼び出し元は先へ進めないこと）。
func _visit_water_stall() -> bool:
	if GameState.is_collection_day():
		if not _pay_or_game_over(GameState.WATER_PRICE):
			return false
	_market_visited_water = true
	return true


## [市場を出る] のハンドラ（DESIGN.md 7.7）。水場に未訪問なら自動で訪れてから、
## [入力完了]と同じ手順（WAITING_INPUT解除→1つ進める→効果適用）で仕込みへ進む。
## 訪問済み・未訪問に関わらず常に押せる（水汲み忘れで詰まらせない）。
## 場所代・水道代の再編＋日々の運営費：市場を出た瞬間に、日々の運営費ぶんの
## 支払い予定（表示専用）を決済する（実際の天引きはWAKEで既に済んでいる。
## GameState.settle_daily_cost_pending参照）。runnerはこの直後の
## _complete_input_and_advance()でMARKETの次（新設のTEXT「共同水道と炭屋に
## 寄り、市場を出た。」）へ進む。
func _on_market_exit_pressed() -> void:
	if not _market_visited_water:
		# 水道代が払えずゲームオーバーになったら、仕込みへ進まずここで止まる。
		if not _visit_water_stall():
			return
	GameState.settle_daily_cost_pending()
	_complete_input_and_advance()


## いま MARKET が現在の Event か（options を持つ WAITING_INPUT の一種）。
## [次のEvent]/[入力完了] を無効化する判定に使う（抜ける経路を[市場を出る]だけにする）。
func _is_in_market() -> bool:
	var r: EventRunner = flow.runner
	if r == null:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.get("type", "") == "MARKET"


## いま PREP_TIER（仕込み3段階の選択）が現在の Event か。_is_in_market() と同じ形。
## [次のEvent]/[入力完了] を無効化する判定に使う（抜ける経路を段階選択ボタンだけにする。
## 選ばずに素通りされると、その先のADD_ITEM/SET_SOUPが無いまま仕込みが成立しなくなる）。
func _is_in_prep_tier() -> bool:
	var r: EventRunner = flow.runner
	if r == null:
		return false
	var cur = r.current()
	return cur is Dictionary and cur.get("type", "") == "PREP_TIER"


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
## までの間だけ true（DESIGN.md 7.6：だしだけ入れても煮出す水が無く意味をなさない）。
## "どうやって鍋モードに入ったか" ではなく "残量が実際に空かどうか" で判定するので、
## 選択待ち経由でも普段の任意タイミングでの訪問でも同じルールが自然にかかる。
func _pot_locked_until_water() -> bool:
	if _pot_water_added:
		return false
	if GameState.soup == null or int(GameState.soup.get("remaining_servings", 0)) > 0:
		return false
	# 鍋操作不能バグの修正：残量0でも、濃さが低すぎて「今すぐは」水を出せない
	# （can_add_water()がfalse）場合はロックしない。ロックしたままだと、
	# だしボタンも「水待ちロック中」を理由に塞がれ、濃さを上げる唯一の手段である
	# だしすら使えなくなり、詰んでしまう（濃さが上がって初めて水が出せるように
	# なる、という順序を考慮できていなかった）。水が今すぐ出せる状態でだけ
	# 「まず水を」の順序を強制する。
	return GameState.can_add_water()


## 濃さメカニクス三点セット：鍋モードに入った時点で濃さ0（提供不可）だった場合、
## 濃縮だしを入れる（_pot_dashi_added）までの間だけ true。_pot_locked_until_water() と
## 同じ形（"どうやって入ったか"ではなく"濃さが実際に0かどうか"で判定）。
func _pot_locked_until_dashi() -> bool:
	if _pot_dashi_added:
		return false
	return GameState.soup != null and int(GameState.soup.get("strength", 3)) <= 0


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
		# 濃さメカニクス三点セット：1晩で鍋が煮詰まるのは明け方（最後の時間帯）に
		# 入った瞬間の1回だけにする（旧：時間帯が変わるたび＝1晩最大2回だった）。
		# 「新しい時間帯に入ったか」はOpenControllerが返すが、「それが最後の時間帯か」は
		# slot_index（進んだ後の値）とschedule.size()から受け側で判定する
		# （OpenController自身は「時間帯が進んだか」だけを答える薄い部品のまま無改修）。
		if _open.advance_customer() and _open.slot_index == _open.schedule.size() - 1:
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
##   TEXT / WAIT_INPUT / GREET / SERVE / MARKET / PREP_TIER … 表示だけ。状態は動かさない
##     （ADJUST は STEP 13 で入力待ちに変わったが、椀への具材の反映は _on_ingredient_selected
##     が行う。MARKET（7.7）も同様に、水場の効果は _on_market_stall_selected /
##     _on_market_exit_pressed が行う。PREP_TIER（仕込み3段階化）も同様に、選んだ効果は
##     _on_prep_tier_selected が直接GameStateへ反映し、あわせて残りのPREP Event列を
##     flow.set_runner()で差し替える）
## 注意: index 0 の Event は「乗る前進」が無いので適用されない。Day1 の WAKE / PREP /
## 客の接客はどれも先頭が TEXT / GREET（効果なし）なので実害なし。PREP_TIER選択後に
## 差し替わる新しいEvent列も、この理由から必ず先頭をTEXTにしてある
## （Day1Events.prep_after_tier_events参照）。
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
				_reset_mob_group_state()   # ②拒否と部分提供：同じ客の次の杯でも選択中の状態を破棄
		"SET_SOUP":
			# 鍋を作るのは GameState.set_soup 経由（受け側は soup を直接触らない）。
			# 7.6: servings（残量の初期値＝仕込んだ杯数）、strength（濃さ）、
			#   water_doses（今夜使える水の回数）も Event から受け取る。
			GameState.set_soup(str(ev.get("base_id", "")), ev.get("tags", []),
				int(ev.get("servings", 0)),
				int(ev.get("strength", 3)),
				int(ev.get("water_doses", 0)))
		"REACT":
			# ②拒否と部分提供：モブ客はADJUST中の確認ボタン（_on_group_serve_pressed /
			# _on_group_decline_pressed / _on_group_retry_pressed）で人数をすでに確定させて
			# いるので、_serve_mob_partial() / _serve_mob_recipe_and_retry() へ委譲する
			# （下の「残量が足りない」判定は経由しない＝鍋不足も具材不足もADJUST側の
			# 達成可能人数の計算にすでに含まれているため）。名前あり客・配達員は
			# _pending_group_result が常に空なので、この分岐には入らず既存のまま。
			if not _pending_group_result.is_empty():
				var result: Dictionary = _pending_group_result
				_pending_group_result = {}
				var retry_remaining: int = int(result.get("retry_remaining", 0))
				# 団体客の分割提供：「挑戦する」を選んだ（retry_remaining>0）ときだけ
				# レシピ2を差し込む。それ以外（通常の提供／断る／レシピ2自身の確定）は
				# 従来どおり最終レシピとして即flushする。
				if retry_remaining > 0:
					_serve_mob_recipe_and_retry(ev, int(result.get("servings", 0)), retry_remaining)
				else:
					_serve_mob_partial(ev, int(result.get("servings", 0)), int(result.get("ordered", 0)))
				return
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
			# 濃さメカニクス三点セット：濃さ0（提供不可）のときも判定せず保留に落とす。
			# ADJUST側の[入力完了]無効化（_is_strength_zero_in_adjust）で通常はここまで
			# 来ないが、残量不足の判定と同じ「保険」として一段レイヤーを重ねる（名前あり客・
			# 配達員向け。モブは_pending_group_result経由で上のreturnに引っかかるので無関係）。
			# 自動閉店には倒さない（濃縮だしがあれば[鍋を見る]で救えるため）。
			if GameState.soup != null and int(GameState.soup.get("strength", 3)) <= 0:
				_pending_shortage_ev = ev
				return
			_serve_customer(ev)


## ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6）：対象はモブ客の団体オーダーだけ。
## いま見ているREACTがモブ客のものか。_react_for_now()は書き換えない読み取り専用の
## 先読みなので、ADJUST中（REACT到達前）でも判定に使える。
func _is_current_mob_order() -> bool:
	return bool(_react_for_now().get("is_mob", false))


## 達成可能人数 = min(注文人数, 鍋の残量, 選んだ各具材のバケツ別在庫数)。
## 「新鮮2個＋傷み2個を新鮮4人分にはしない」（仕様3）＝押したバケツ単体の在庫数だけを見る
## （fresh+damagedの合算はしない）。同じ具材・同じバケツを2枠選んだ場合はその具材について
## 在庫数を選んだ回数で割る（add_to_bowlは重複を許すため。例：軟骨(新鮮)を2枠→
## 新鮮在庫8個なら軟骨に関する上限は8÷2=4人）。
## 濃さメカニクス三点セット：濃さ0（提供不可）の鍋は人数に関係なく達成可能0にする
## （具材や残量が足りていても、薄すぎる鍋では誰にも出せない。既存の「達成可能0なら
## 断るしか出せない」というモブUIにそのまま乗せるだけで、新しい分岐は増やさない）。
func _mob_achievable_servings(ordered: int) -> int:
	var achievable := ordered
	if GameState.soup != null:
		achievable = mini(achievable, int(GameState.soup.get("remaining_servings", 0)))
		if int(GameState.soup.get("strength", 3)) <= 0:
			achievable = 0
	else:
		achievable = 0
	var counts := {}   # "id|damaged" -> 選んだ回数
	for pick in _mob_picks:
		var key: String = "%s|%s" % [pick["id"], pick["damaged"]]
		counts[key] = int(counts.get(key, 0)) + 1
	var seen := {}
	for pick in _mob_picks:
		var key: String = "%s|%s" % [pick["id"], pick["damaged"]]
		if seen.has(key):
			continue
		seen[key] = true
		var avail: int = GameState.damaged_count(pick["id"]) if pick["damaged"] else GameState.fresh_count(pick["id"])
		achievable = mini(achievable, int(avail / int(counts[key])))
	return maxi(achievable, 0)


## モブ客の選択中の状態（在庫はまだ引いていない）を破棄する。客が替わる・同じ客の次の杯・
## 廃棄して作り直す、の3箇所から呼ぶ（_reset_mob_group_state）。
func _reset_mob_group_state() -> void:
	_mob_picks = []
	_pending_group_choice = false
	_pending_group_result = {}


## 「N人分を提供」ボタン。人数を確定してADJUST→SERVEへ進める（実際の消費・判定・売上・
## 評判・記録はREACT到達時の_serve_mob_partial()で行う。Event（データ）はここでは
## 一切書き換えない）。レシピ1のときだけ元注文数を覚える（レシピ2ではordered自体が
## 「残り人数」になるため、_mob_original_orderedを上書きしない）。
func _on_group_serve_pressed(n: int, ordered: int) -> void:
	if _mob_recipe_number == 1:
		_mob_original_ordered = ordered
	_pending_group_result = { "servings": n, "ordered": ordered }
	_pending_group_choice = false
	_complete_input_and_advance()


## 「注文を断る」ボタン。人数0で確定させる（_serve_mob_partial側で「断り」として扱う）。
func _on_group_decline_pressed(ordered: int) -> void:
	if _mob_recipe_number == 1:
		_mob_original_ordered = ordered
	_pending_group_result = { "servings": 0, "ordered": ordered }
	_pending_group_choice = false
	_complete_input_and_advance()


## 「残り◯人に別の具材で挑戦する」ボタン（団体客の分割提供：最大2レシピ）。達成可能分
## （achievable）はこの場で確定・提供し、残り（ordered-achievable）人ぶんを2レシピ目の
## ADJUSTへ回す。_mob_recipe_number==1のときしか出さないボタンなので、ここに来る時点で
## 必ずレシピ1（_serve_mob_recipe_and_retry側でレシピ番号を2へ進める）。
func _on_group_retry_pressed(achievable: int, ordered: int) -> void:
	if _mob_recipe_number == 1:
		_mob_original_ordered = ordered
	_pending_group_result = { "servings": achievable, "ordered": ordered,
		"retry_remaining": ordered - achievable }
	_pending_group_choice = false
	_complete_input_and_advance()


## REACT到達時、_pending_group_result（確認ボタンで確定済み）があるモブ客はこちらで処理する
## （_apply_event()のREACTケースから委譲。名前あり客・配達員は_pending_group_resultが
## 常に空なので、この関数自体を通らない＝既存の_serve_customer()のみ使う）。
## actual（実際に提供する人数）が0なら「断り」＝判定・鍋消費・売上のいずれも発生させない
## （既存の[閉店]と同じ扱い。仕様7）。1以上なら、実際に消費するのはactual人分だけ
## （鍋・選んだ各具材とも）。判定（GREAT/GOOD/OK/BAD）はactualの大小に関係なく「何を
## 入れたか」だけで決まる（人数に比例させない。§2確定仕様）。
## 団体客の分割提供：記録は_visit_tallyへ積むだけにし、_log_quality_countsへの加算は
## _flush_visit_tally()側に一本化する（ここで直接加算すると、2レシピ目のflush時に
## resultsから再度合算されて二重加算になるため）。
func _apply_mob_recipe(ev: Dictionary, actual: int) -> void:
	var customer := str(ev.get("customer", ""))
	if actual <= 0:
		_add_to_visit_tally(customer, false, 0, 0, "", "", _mob_original_ordered)
		return
	var result := ""
	if _open != null:
		result = _open.judge_bowl(ev.get("wanted_tags", []), str(ev.get("favorite", "")))
	for pick in _mob_picks:
		if bool(pick["damaged"]):
			GameState.remove_inventory_damaged(str(pick["id"]), actual)
		else:
			GameState.remove_inventory_fresh(str(pick["id"]), actual)
	GameState.consume_soup(actual)
	var sale: int = actual * GameState.PRICE_PER_SERVING
	GameState.apply_money(sale)
	_add_to_visit_tally(customer, true, sale, actual, result, str(ev.get("favorite", "")),
		_mob_original_ordered)


## この団体客への最後（または唯一）のレシピを確定し、その場で退店集計として確定させる
## （客が変わるまで待つ通常の_flush_visit_tallyタイミングとは違い、モブは既存どおり
## REACT到達の瞬間に確定させる。_visit_tally.is_empty()なら何もしない性質を使っているので、
## レシピ1回だけの団体（従来どおりの2択のみ）でも同じ関数で正しく動く）。
func _serve_mob_partial(ev: Dictionary, actual: int, ordered: int) -> void:
	_apply_mob_recipe(ev, actual)
	_flush_visit_tally()


## 「挑戦する」を選んだ場合の処理：レシピ1（achievable人分）をその場で確定・積算し、
## 同じ客のrunnerへレシピ2用のADJUST→SERVE→REACTを動的に差し込む（末尾追加ではなく
## 現在位置の直後へinsertする。モブ客の接客Event列に閉店会話等の追加Eventが後ろへ
## 続く場合でも順序を壊さないため）。レシピ2のADJUSTはnew_bowl:trueにして
## _apply_event()の既存ADJUSTケースに椀のリセット・_reset_mob_group_state()を任せる。
func _serve_mob_recipe_and_retry(ev: Dictionary, actual: int, remaining: int) -> void:
	_apply_mob_recipe(ev, actual)
	_mob_recipe_number = 2
	_mob_picks = []
	var customer: String = str(ev.get("customer", ""))
	var next_events := [
		{ "type": "ADJUST", "customer": customer, "text": "（味を調える）",
			"options": Day1Events._adjust_options(), "new_bowl": true },
		{ "type": "SERVE", "customer": customer, "text": "「はいよ、お待ち。」" },
		{ "type": "REACT", "customer": customer, "reactions": ev.get("reactions", {}),
			"wanted_tags": ev.get("wanted_tags", []), "favorite": ev.get("favorite", ""),
			"servings": remaining, "is_mob": true,
			"sale": GameState.PRICE_PER_SERVING * remaining },
	]
	var insert_at: int = flow.runner.index + 1
	for i in range(next_events.size()):
		flow.runner.events.insert(insert_at + i, next_events[i])


## REACT の効果を実際に適用する（判定→評判→鍋の消費→売上→記録）。
## 通常の提供（_apply_event から）と、鍋を作り直した後の [戻る]（_on_pot_back_pressed）
## の両方から呼ばれる共通処理。Event（reactions）は書き換えない
## （DESIGN.md 確定事項「Event はデータ、処理は受け側」）。
## どの反応textを見せるかは表示側 _current_reaction_text() が都度選ぶ。
##
## REACT のフラグ（どちらも既定値なら従来どおり＝判定して、記録もその場で反映）：
##   judge:false     … 判定しない（judge_bowl を呼ばない）。評価も付かない杯
##                     （例：配達員の持ち帰り）。鍋の消費と売上は通常どおり
##   aggregate:true  … 鍋の消費と売上はその場で反映するが、提供記録は _visit_tally に
##                     積み、退店時に客1人分として1回だけ反映する（_flush_visit_tally）
## 評判は閉店時に_log_quality_countsから一括で計算し直す（④評判の更新。ここでは
## GameState.apply_reputationのような即時適用は行わない）。
func _serve_customer(ev: Dictionary) -> void:
	var sale := int(ev.get("sale", 0))
	var servings := int(ev.get("servings", 1))
	var judged: bool = bool(ev.get("judge", true))
	var aggregate: bool = bool(ev.get("aggregate", false))
	var customer_id := str(ev.get("customer", ""))
	# ③初回好物の開示：Event側の本来のfavorite（生の値。書き換えない）と、判定に実際に
	# 使う値（まだ知らない客なら空にして隠す）を分けて持つ。current_bowlに残るfavorite/
	# has_favoriteは「判定に使った値」の方になる（初回は好物を入れてもGREATにならない）。
	var raw_favorite := str(ev.get("favorite", ""))
	var favorite_for_judge := raw_favorite if GameState.knows_favorite(customer_id) else ""
	var result := ""
	if judged and _open != null:
		result = _open.judge_bowl(ev.get("wanted_tags", []), favorite_for_judge)
	GameState.consume_soup(servings)
	GameState.apply_money(sale)
	if aggregate:
		# 集計客（配達員）は「退店時」に知った扱いにする必要があるため、ここではまだ
		# mark_favorite_known() を呼ばない（呼ぶと1杯目の直後から2杯目で使えてしまう）。
		# _flush_visit_tally() が退店の瞬間に1回だけ確定させる。
		_add_to_visit_tally(customer_id, judged, sale, servings, result, raw_favorite)
		return
	if judged and raw_favorite != "":
		GameState.mark_favorite_known(customer_id)
	# 日次ログ：判定結果ごとに集計する。judged=falseの杯（配達員の持ち帰り等）は
	# result=""のまま（判定なしと分かる値。指示文どおり）。
	_log_quality_counts[result] = int(_log_quality_counts.get(result, 0)) + servings
	GameState.record_served({ "customer": customer_id, "sale": sale,
		"servings": servings, "result": result })


## 集計（_visit_tally）に1杯分を積む。売上と杯数は全杯を積む。
## 日次ログ：resultsに判定結果ごとの杯数も積んでおく（_flush_visit_tallyで
## _log_quality_countsへ合算し、record_servedにも残す。判定なしの杯はresult=""のまま）。
## ③初回好物の開示：raw_favoriteが空でなければ_visit_tallyへ覚えておき（既に何か
## 覚えていれば上書きしない＝配達員3杯目のfavorite無しに負けない）、退店時の
## _flush_visit_tally()で1回だけ「知った」扱いにする。
## 団体客の分割提供：ordered_servings（元の総注文人数）を渡すと、積み始めた瞬間
## （_visit_tally が空だったとき）だけ記録する。2レシピ目以降は既に入っている値を
## 上書きしない（レシピ2のorderedは「残り人数」であって元の総注文人数ではないため）。
## 配達員の集計（この引数を渡さない呼び出し）はキー自体が付かず、今までどおりの
## 4フィールド（customer/sale/servings/results）のまま変わらない。
func _add_to_visit_tally(customer: String, judged: bool, sale: int,
		servings: int, result: String = "", raw_favorite: String = "",
		ordered_servings: int = -1) -> void:
	if _visit_tally.is_empty():
		_visit_tally = { "customer": customer,
			"sale": 0, "servings": 0, "results": {}, "pending_favorite": "" }
		if ordered_servings >= 0:
			_visit_tally["ordered_servings"] = ordered_servings
	_visit_tally["sale"] = int(_visit_tally["sale"]) + sale
	_visit_tally["servings"] = int(_visit_tally["servings"]) + servings
	var results: Dictionary = _visit_tally["results"]
	results[result] = int(results.get(result, 0)) + servings
	if judged and raw_favorite != "":
		_visit_tally["pending_favorite"] = raw_favorite


## 集計を客1人分として反映し、空にする（空なら何もしない＝何度呼んでも二重には効かない）。
## 評判は閉店時に_log_quality_countsから一括で計算し直す（④評判の更新。旧・杯ごとの
## 増減平均をここで即時適用する処理は廃止した）。提供記録は売上・杯数の合計で1件残す。
## 団体客の分割提供：_visit_tallyにordered_servingsがある（＝モブの団体オーダー由来）
## ときだけ、ordered_servings/unserved_servings/declinedも記録に足す（配達員の集計には
## このキーが付かないので、既存の4フィールド形のまま変わらない）。
func _flush_visit_tally() -> void:
	if _visit_tally.is_empty():
		return
	# 日次ログ：この客の杯ごとの判定結果を、その日の集計へ合算する。
	var results: Dictionary = _visit_tally.get("results", {})
	for key in results:
		_log_quality_counts[key] = int(_log_quality_counts.get(key, 0)) + int(results[key])
	# ③初回好物の開示：退店するこの瞬間に1回だけ「知った」扱いにする（配達員は
	# これで1・2杯目の途中では判明せず、3杯すべて終えた退店時に判明する）。
	var pending_favorite := str(_visit_tally.get("pending_favorite", ""))
	if pending_favorite != "":
		GameState.mark_favorite_known(str(_visit_tally["customer"]))
	var record := { "customer": _visit_tally["customer"],
		"sale": int(_visit_tally["sale"]), "servings": int(_visit_tally["servings"]),
		"results": results }
	if _visit_tally.has("ordered_servings"):
		var ordered: int = int(_visit_tally["ordered_servings"])
		var served: int = int(_visit_tally["servings"])
		record["ordered_servings"] = ordered
		record["unserved_servings"] = maxi(ordered - served, 0)
		record["declined"] = served <= 0
	GameState.record_served(record)
	_visit_tally = {}


## もう水が無いか（DESIGN.md 7.6：自動閉店・選択待ちの条件2）。
## 残量を増やせるのは水だけ（だしは濃さを上げるだけで、量は増やさない）ので、
## 不足を埋められるかの判定は水の有無だけを見る。ただし濃さが低すぎて今すぐは
## 水を出せない（can_add_water()がfalse）だけの場合、だしを先に入れれば水を
## 出せる手順が残っていることがあるため、GameState.water_reachable()で
## その手順まで含めて判定する（鍋操作不能バグの修正。単独判定のcan_add_water()
## だと、まだ回復可能な状況を「もう資源が無い」と誤判定し、詰んでいないのに
## 自動閉店・強制ゲームオーバー相当の分岐へ落としてしまっていた）。
func _no_resources_left() -> bool:
	return not GameState.water_reachable()


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


## 残量不足が「今まさに提供を妨げている」文脈か：ADJUST中に既に不足しているか、
## 保留中のREACT（_pending_shortage_ev）がその不足で保留になっているか。
## ADJUST中の判定（_is_short_in_adjust）はSERVE/REACT到達前しか見えないため、
## 保留に落ちた後（SERVEを過ぎている）も同じ問いに答えられるよう別関数にしてある。
## 水で解決できるかどうかの判定（鍋モードの入場可否）に使う。
func _is_servings_short_context() -> bool:
	if _is_short_in_adjust():
		return true
	if _pending_shortage_ev == null or GameState.soup == null:
		return false
	return int(GameState.soup.get("remaining_servings", 0)) < int(_pending_shortage_ev.get("servings", 1))


## 濃さメカニクス三点セット：鍋の濃さが実際に0（提供不可）か。文脈（ADJUST中か保留中か）を
## 問わない素の状態チェック（濃さは接客中に自然には変わらないので、どちらの文脈でも
## 同じ値になる。だしで解決できるかどうかの判定に使う）。
func _is_strength_zero() -> bool:
	return GameState.soup != null and int(GameState.soup.get("strength", 3)) <= 0


## ADJUST中（椀を作っている最中）で、濃さ0（提供不可）か。残量不足（_is_short_in_adjust）
## とは独立した別の条件（判定そのものが成立しない）。[入力完了]を止め、
## [鍋を見る]・[閉店]を出す条件に使う（残量不足と同じ役割）。
func _is_strength_zero_in_adjust() -> bool:
	return _is_choosing_ingredients() and _is_strength_zero()


## [閉店]を押せるか。鍋不足の保留中、「ADJUST中で残量不足、かつ水が無い」、または
## 「ADJUST中で濃さ0、かつだしが無い」（どちらも足せなければ閉店）。いずれも、その客には
## 出せなかった扱いで CLOSE へ進む。
## ②拒否と部分提供：モブ客の不足は「断る」で次の客へ進めるので、これだけを理由に
## [閉店]は出さない（名前あり客・配達員は無変更。濃さ0もモブは_mob_achievable_servings()の
## 「達成可能0」経由で断れるので同じ扱いにする）。
func _can_close_now() -> bool:
	return _pending_shortage_ev != null \
			or (_is_short_in_adjust() and _no_resources_left() and not _is_current_mob_order()) \
			or (_is_strength_zero_in_adjust() and not GameState.can_add_dashi() and not _is_current_mob_order())


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
## 出す。④評判の更新（BALANCE_REDESIGN_PLAN.md§5）：ここで初めて、当夜品質Qから
## GameState.settle_reputation()を1回だけ呼んで評判を確定させる（OPEN中は動かさない）。
func _on_day_ending() -> void:
	var served_cups := 0
	var sale_total := 0
	for record in GameState.served:
		if record is Dictionary and not bool(record.get("discarded", false)):
			served_cups += int(record.get("servings", 0))
			sale_total += int(record.get("sale", 0))
	var unserved_cups: int = maxi(_log_planned_cups - served_cups, 0)
	var spoiled_value := _spoiled_value(_log_spoiled_items)
	var quality := _quality_score(_log_quality_counts, _log_judged_planned_cups)
	GameState.settle_reputation(quality)
	var log_entry := {
		"day": GameState.day_count,
		"opening_money": _log_opening_money, "closing_money": GameState.money,
		"opening_reputation": _log_opening_reputation, "closing_reputation": GameState.reputation,
		"planned_cups": _log_planned_cups, "served_cups": served_cups,
		"unserved_cups": unserved_cups, "sale_total": sale_total,
		"quality_counts": _log_quality_counts.duplicate(),
		"judged_planned_cups": _log_judged_planned_cups, "quality": quality,
		"spoiled_items": _log_spoiled_items.duplicate(),
		"spoiled_value": spoiled_value,
		"water_used": _log_water_used, "dashi_used": _log_dashi_used,
		"closed_early": _log_closed_early,
	}
	print("BALANCE_LOG: day=%d money=%d→%d rep=%d→%d(Q=%.1f) cups=%d/%d(計画%d) 売上=%d 廃棄額=%d 水%d/だし%d 早期閉店=%s 評価=%s" % [
		log_entry["day"], log_entry["opening_money"], log_entry["closing_money"],
		log_entry["opening_reputation"], log_entry["closing_reputation"], quality,
		served_cups, unserved_cups, _log_planned_cups, sale_total, spoiled_value,
		_log_water_used, _log_dashi_used, str(_log_closed_early), str(_log_quality_counts)])
	_append_balance_log_file(log_entry)
	# 日次の成績表示（③）：今日作ったlog_entryをそのまま人間向けの文にして、次のWAKE（別日）の先頭で一度だけ見せる。ここでのdebug_panel.gd内のローカル変数ではなくlog_entryの値だけを使うのは、日次ログファイルJSONと完全に同じ内容にして、二重の集計ロジックを作らないため。
	_last_day_summary_text = _format_day_summary(log_entry)


## 日次の成績表示（③）：_on_day_ending()が組み立てたlog_entry（opening/closingの所持金・評判、
## 提供杯数、売上、品質内訳、廃棄額、水・だし回数、早期閉店）を、プレイヤー向けの
## 日本語一言サマリーへ整形する。日内ログファイルJSONと同じlog_entryだけを参照し、新しい集計はしない。
func _format_day_summary(log_entry: Dictionary) -> String:
	var money_diff: int = int(log_entry["closing_money"]) - int(log_entry["opening_money"])
	var counts: Dictionary = log_entry["quality_counts"]
	var lines := PackedStringArray([
		"◆前日（Day%d）の成績◆" % int(log_entry["day"]),
		"所持金: %d → %d（%s%d）" % [
			int(log_entry["opening_money"]), int(log_entry["closing_money"]),
			"+" if money_diff >= 0 else "", money_diff],
		"評判: %d → %d" % [
			int(log_entry["opening_reputation"]), int(log_entry["closing_reputation"])],
		"提供: %d/%d杯（未提供%d杯）　売上: %d" % [
			int(log_entry["served_cups"]), int(log_entry["planned_cups"]),
			int(log_entry["unserved_cups"]), int(log_entry["sale_total"])],
		"品質: GREAT%d GOOD%d OK%d BAD%d（Q=%.1f）" % [
			int(counts.get("GREAT", 0)), int(counts.get("GOOD", 0)),
			int(counts.get("OK", 0)), int(counts.get("BAD", 0)), float(log_entry["quality"])],
		"廃棄額: %d　水%d回／だし%d回" % [
			int(log_entry["spoiled_value"]), int(log_entry["water_used"]), int(log_entry["dashi_used"])],
	])
	if bool(log_entry.get("closed_early", false)):
		lines.append("（鍋が尽きて早めに閉店した）")
	return "\n".join(lines)


## discard_spoiled_inventory()が返す各品目の"value"（ロットごとに実際に払った単価×個数の
## 合計。①具材の購入単位でGameStateが計算するようになった）をそのまま足し合わせるだけ。
## 概算はしない（パック購入と小口購入で単価が違っても、GameStateが記録した実額を使う）。
func _spoiled_value(spoiled_items: Dictionary) -> int:
	var total := 0
	for item in spoiled_items:
		total += int(spoiled_items[item].get("value", 0))
	return total


## 当夜品質Q（BALANCE_REDESIGN_PLAN.md§5）＝判定した杯の得点合計 ÷ 朝に確定した
## 判定対象杯数（judge:falseの杯は数えない。judged_plannedはOPEN開始時に先読みした
## _log_judged_planned_cups）。未提供の杯（部分提供の残り・早期閉店で届かなかった杯）は
## 得点0のまま分母にだけ残る（quality_countsに積まれないため。指示文どおり、未提供への
## 別の固定減点は重ねない）。judged_plannedが0（判定対象の杯が1つも無い日。実際には
## 起こらない想定だがガードする）ならQは0とみなす。
func _quality_score(counts: Dictionary, judged_planned: int) -> float:
	if judged_planned <= 0:
		return 0.0
	var total := 0
	for key in REPUTATION_SCORE:
		total += int(REPUTATION_SCORE[key]) * int(counts.get(key, 0))
	return float(total) / float(judged_planned)


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
##   - 鍋モード中（7.6）… [水を足す] [だしを足す] [戻る]
##   - MARKET中（7.7）  … 7店舗のボタン ＋ [市場を出る]
##   - それ以外          … ADJUST の具材ボタン（"options" を持つ WAITING_INPUT のときだけ）
## STEP 17.6: [入力完了] は ADJUST 中でも押せる（3枠未満でも提供できる仕様）。
##   具材が上限（MAX_ADDITIONS）に達したら具材ボタン側だけを無効化する。
## 7.6: [鍋を見る] は ADJUST 中だけ無効。鍋モード中は [次のEvent]/[入力完了] を無効に
##   して「会話が止まっている」ことを見た目にも合わせる。
## 7.6: 鍋が尽きて選択待ち（_pending_shortage_ev != null）のときは、それに加えて
##   [次のEvent]/[入力完了]も無効（保留を解決するまで進めない）。[鍋を見る]は
##   選択待ち中だけ「水かだしが残っているか」も条件に足す（無ければ作り直しようが
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
	# 調味料と具材のボタンを2行に分ける：ADJUST以外の文脈（市場・仕込み段階・鍋モード・
	# グループ確認ボタン等）では_seasoning_rowは使わないので、ここで毎回空にしておけば
	# 何もしなくても空のまま維持される。
	for child in _seasoning_row.get_children():
		child.queue_free()

	# ボタンの有効/無効は毎回ここで決め直す（状態から描き直す方針に揃える）。
	# 鍋がまだ無い（仕込み前）ときも押せない。
	# ゲームオーバー後は、OPENで止まって鍋が残っていても鍋を触らせない。
	# [鍋を見る]：ADJUST中は原則触れない（作っている椀があるため）が、残量不足または
	# 濃さ0（提供不可）のときだけ触れる（水／だしを足して解決できる可能性があるため）。
	# 足せるものが無いときは入れない（入っても出口が無くなるため）。残量不足を埋められるのは
	# 水だけ、濃さ0を埋められるのはだしだけなので、それぞれ独立に「解決可能か」を見て、
	# どちらか一方でも解決可能なら鍋モードへ入れる（濃さメカニクス三点セット）。
	# 濃さ0は文脈を問わない素の状態（_is_strength_zero）で見る＝ADJUST中でも保留中の
	# REACT待ちでも同じ値になる。残量不足は「今それが実際に提供を妨げているか」
	# （_is_servings_short_context。ADJUST中の判定はSERVEを過ぎると見えなくなるため、
	# 保留中は_pending_shortage_evの注文数から再計算する）で見る。
	# それ以外（不足の文脈でない・濃さの調整だけ）では水かだしのどちらかがあるかを見る。
	# SERVE中（_is_awaiting_react）は不足の文脈になり得ない（ADJUSTの[入力完了]は不足時
	# 押せないので、無事SERVEまで来た時点で足りている）ため、無条件で塞いでよい。
	var servings_short := _is_servings_short_context()
	var strength_zero := _is_strength_zero()
	var nothing_to_add: bool
	if servings_short or strength_zero:
		# 鍋操作不能バグの修正：ここもcan_add_water()単独ではなく、だし経由の回復まで
		# 含めたwater_reachable()で判定する（さもないと[鍋を見る]ボタン自体が
		# 無効化され、回復手順に一歩も入れない）。
		var can_fix_servings := servings_short and GameState.water_reachable()
		var can_fix_strength := strength_zero and GameState.can_add_dashi()
		nothing_to_add = not can_fix_servings and not can_fix_strength
	else:
		nothing_to_add = not GameState.can_add_water() and not GameState.can_add_dashi()
	var pot_disabled := GameState.soup == null or _pot_mode \
			or (_is_choosing_ingredients() and not _is_short_now() and not strength_zero) \
			or _is_awaiting_react() \
			or GameState.phase == GameState.Phase.GAME_OVER or nothing_to_add
	_btn_pot.disabled = pot_disabled or _phone_mode
	_btn_next_event.disabled = _pot_mode or _pending_shortage_ev != null \
			or _is_in_market() or _is_in_prep_tier() \
			or _phone_mode or _pending_group_choice
	# 不足のADJUSTでは提供（[入力完了]）できない。補充するか、閉店するか廃棄以外を選ぶ。
	# ②拒否と部分提供：モブ客は鍋不足だけでは塞がない（達成可能人数の計算に鍋残量も
	# 含めており、[入力完了]を押せば確認ボタンへ進めるため。名前あり客・配達員は無変更）。
	# 濃さメカニクス三点セット：濃さ0も同じ扱い（モブは_mob_achievable_servings()が
	# 強制的に0を返すので「断る」しか出せなくなる。名前あり客・配達員は塞ぐ）。
	# 仕込み3段階化：PREP_TIER中は段階ボタン以外で抜けさせない（_is_in_marketと同じ理由）。
	_btn_complete_input.disabled = _pot_mode or _pending_shortage_ev != null \
			or _is_in_market() or _is_in_prep_tier() or _phone_mode or _pending_group_choice \
			or (_is_short_in_adjust() and not _is_current_mob_order()) \
			or (_is_strength_zero_in_adjust() and not _is_current_mob_order())
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
		var locked_water := _pot_locked_until_water()
		var locked_dashi := _pot_locked_until_dashi()
		_add_pot_button("水を足す（残量+%d 濃さ-%d）" % [GameState.WATER_SERVINGS, GameState.WATER_STRENGTH_DELTA],
			not GameState.can_add_water(), _on_add_water_pressed)
		# だしだけ入れても煮出す水が無く意味をなさない（旧ベースと同じ理由）ので、
		# 水待ちロック中はだしボタンも塞ぐ。
		_add_pot_button("だしを足す（濃さ+%d）" % GameState.DASHI_STRENGTH_DELTA,
			not GameState.can_add_dashi() or locked_water, _on_add_dashi_pressed)
		# 水待ち・だし待ちで[戻る]を塞ぐのは、それぞれ[水を足す]/[だしを足す]で
		# 解ける（資源がある）ときだけ。資源が無ければ塞がない＝鍋モードには必ず出口がある。
		_add_pot_button("戻る",
			(locked_water and GameState.can_add_water()) or (locked_dashi and GameState.can_add_dashi()),
			_on_pot_back_pressed)
		return

	# ②拒否と部分提供：モブ客が[入力完了]を押した後は、通常のADJUST具材ボタンの代わりに
	# 「N人分を提供／注文を断る」の2択を出す（達成可能人数は毎回ここで計算し直すので、
	# 鍋モードへ寄り道して水を足してから戻ってきても最新の値になる）。全員分そろっている
	# ときも「注文を断る」は必ず出す（仕様6）。達成可能人数が0なら「断る」だけを出す。
	# 団体客の分割提供（最大2レシピ）：達成可能人数が注文人数に満たない（0を含む）とき、
	# レシピ1（_mob_recipe_number==1）に限り「残り◯人に別の具材で挑戦する」も出す。
	# レシピ2ではこのボタンを出さない＝最大2レシピで打ち止め。
	if _pending_group_choice:
		var order := _react_for_now()
		var ordered: int = int(order.get("servings", 0))
		var achievable := _mob_achievable_servings(ordered)
		if achievable >= 1:
			var serve_label := "%d人分を提供（注文%d人）" if _mob_recipe_number == 1 \
				else "%d人分を提供（残り%d人）"
			_add_pot_button(serve_label % [achievable, ordered], false,
				_on_group_serve_pressed.bind(achievable, ordered))
		_add_pot_button("注文を断る", false, _on_group_decline_pressed.bind(ordered))
		if _mob_recipe_number == 1 and achievable < ordered:
			_add_pot_button("残り%d人に別の具材で挑戦する" % (ordered - achievable), false,
				_on_group_retry_pressed.bind(achievable, ordered))
		return

	var r: EventRunner = flow.runner
	if r == null or r.status != EventRunner.Status.WAITING_INPUT:
		return
	var cur = r.current()
	if not (cur is Dictionary) or not cur.has("options"):
		return

	if cur.get("type", "") == "PREP_TIER":
		for tier in cur.get("options", []):
			var price: int = int(tier.get("price", 0))
			_add_pot_button("%s（-%d・%d杯）" % [str(tier.get("label", "")), price, int(tier.get("servings", 0))],
				GameState.money < price, _on_prep_tier_selected.bind(str(tier.get("id", ""))))
		return

	if cur.get("type", "") == "MARKET":
		if _market_shop != "":
			for good in _shop_goods(_market_shop):
				var gid: String = str(good.get("id", ""))
				var price: int = int(good.get("price", 0))
				_add_pot_button("%s（-%d）" % [str(good.get("label", gid)), price],
					GameState.money < price, _on_shop_item_selected.bind(_market_shop, gid))
			_add_pot_button("市場に戻る", false, _on_shop_exit_pressed)
			return
		for option in cur.get("options", []):
			var id: String = str(option.get("id", ""))
			var disabled: bool = not bool(option.get("enabled", true))
			_add_pot_button(str(option.get("label", id)), disabled,
				_on_market_stall_selected.bind(id))
		_add_pot_button("市場を出る", false, _on_market_exit_pressed)
		return

	var at_cap := false
	if _open != null:
		at_cap = _open.current_bowl.get("additions", []).size() >= OpenController.MAX_ADDITIONS
	for option in cur["options"]:
		var opt_id: String = str(option.get("id", ""))
		# 7.7: options は接客開始時に1回だけ組み立てた在庫のスナップショット（MARKETの
		# enabledと同じく読むだけで書き換えない）。同じ接客中に選び尽くして0になる分は
		# ここでライブの在庫数を見て無効化し直す（水場ボタンと同じ形）。
		# 鮮度: 押した側のバケツに1個以上あれば押せる（②拒否と部分提供：旧条件の
		# 「両バケツの合計がservings以上」は、名前あり客・配達員(servings常に1)には
		# own>=1と数学的に同値なので挙動は変わらない。モブ(servings>1)だけが
		# 「揃わなくても選べる」ようになる＝達成可能人数はADJUST完了時に別途計算する）。
		var opt_damaged: bool = bool(option.get("damaged", false))
		var own: int = GameState.damaged_count(opt_id) if opt_damaged else GameState.fresh_count(opt_id)
		var out_of_stock: bool = own < 1
		var btn := Button.new()
		# B: 所持数を表示（既に無効化判定に使っているownをそのまま表示に使うだけ）。
		btn.text = "%s(%d)" % [str(option.get("label", opt_id if opt_id != "" else "?")), own]
		btn.disabled = at_cap or out_of_stock
		btn.pressed.connect(_on_ingredient_selected.bind(opt_id, opt_damaged))
		# C: 調味料（味の軸のみ）と具材（具の軸を持つ）で行を分ける。「具」の判定基準は
		# 「具なしの椀は常に最低評価」で使っているIngredients.is_topping()をそのまま流用する
		# （新しい分類基準を増やさないため。ADJUST以外の文脈はこのループを通らないので無影響）。
		if Ingredients.is_topping(opt_id):
			_options_row.add_child(btn)
		else:
			_seasoning_row.add_child(btn)
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
	#   money      … 所持金。支払いで減り売上で増える。括弧の「支払い予定」は表示専用の
	#                注記（GameState.pending_bills_today）で、実際の天引きはWAKE・
	#                チンピラのPAY等で既に済んでいる。市場を出る・場所代を払うたびに
	#                減っていき、0になったら注記自体が消える
	#   reputation … 店の評判値。REACT の判定結果で増減する（7.6）
	#   inventory  … 持っている具材・調味料の合計個数（辞書 { id: 個数 } の値を合計。7.7）
	#   inventory_detail … 品目ごとの内訳（7.7：市場で複数品目を買うと合計数だけでは
	#                 「何が増えたか」が分からないため、id:個数の一覧を別行で出す）
	#   rumors     … スマホで得た噂の件数。今は未使用
	#   phase      … 一日のどの段階か（WAKE→PREP→OPEN→CLOSE→NEXT_DAY）
	#   soup       … 仕込んだ鍋と残量・濃さ。仕込み前はnone。翌日リセット
	#   pot        … 鍋に足せる資源。水は今夜だけ（soupの中）、濃縮だしは翌日へ持ち越す
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
		"money(所持金): %d%s" % [GameState.money,
			"（支払い予定%d）" % GameState.pending_bills_today if GameState.pending_bills_today > 0 else ""],
		"reputation(評判): %d" % GameState.reputation,
		"inventory(在庫数): %d 個" % _inventory_total(),
		"inventory_detail(内訳): %s" % _format_inventory_detail(),
		"rumors(情報数): %d 件" % GameState.rumors.size(),
		"phase(現在フェーズ): %s (%d)" % [phase_name, GameState.phase],
		"soup(今日の鍋): %s" % soup_text,
		"pot(鍋の資源): 水%d回 / 濃縮だし%d回分" % [water_doses, GameState.dashi_units],
		"served(接客数/杯数): %d / %d" % [_served_count(), _served_servings()],
		"discarded(廃棄数): %d 件" % _discarded_count(),
		"known_favorites(好物を知っている客): %s" % (
			"・".join(PackedStringArray(GameState.known_favorites.keys())) if not GameState.known_favorites.is_empty() else "(なし)"),
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
			body = _format_tonight_memo()
		_:
			body = "レシピ：まだ記録がありません"
	return "── スマホ ──\n%s" % body


## 予告（②）：SNSタブの本文。_tonight_schedule（WAKEで1回だけ確定した今夜の並び）
## を、時間帯ごとに「誰が・何人・どんな味を求めているか」だけ分かる一言メモへ整形する。
## 好物はknows_favorite()がtrueの客だけ添える（③初回好物の開示と同じ「知っているかどうか」
## のルールに揃える。モブはそもそもfavoriteを持たないので対象外）。
## _tonight_schedule がまだ空（起床前など）なら、旧来のプレースホルダ文言を返す。
func _format_tonight_memo() -> String:
	if _tonight_schedule.is_empty():
		return "SNS：まだ新着はありません"
	var lines := PackedStringArray(["◆本日の客足予報◆"])
	for slot in _tonight_schedule:
		var parts := PackedStringArray()
		for customer_id in slot.get("customers", []):
			var cid := str(customer_id)
			var flavor := Day1Events._customer_flavor(cid)
			var tags: Array = flavor.get("wanted_tags", [])
			var tag_text := "/".join(PackedStringArray(tags)) if not tags.is_empty() else "？"
			if bool(flavor.get("is_mob", false)):
				# モブの表示名（「港湾労働者」等）はJSON側に構造化データを持たないため、
				# greet[0]（例:「港湾労働者 4人（HOT/POWER）」）をそのまま使う。
				var greet_lines: Array = flavor.get("greet", [])
				if not greet_lines.is_empty():
					parts.append(str(greet_lines[0]))
				else:
					parts.append("モブ %d人（%s）" % [int(flavor.get("servings", 0)), tag_text])
			else:
				var name: String = Day1Events.CUSTOMER_NAMES.get(cid, cid)
				var fav_text := ""
				var fav_id := str(flavor.get("favorite", ""))
				if fav_id != "" and GameState.knows_favorite(cid):
					fav_text = "／好物:%s" % Ingredients.name_for(fav_id)
				parts.append("%s（%s%s）" % [name, tag_text, fav_text])
		if parts.is_empty():
			continue
		lines.append("・%s：%s" % [str(slot.get("name", "")), "、".join(parts)])
	return "\n".join(lines)


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
	# 1杯ずつ接客する客の集計中だけ出す（退店時に提供記録として1回反映される。
	# 評判はもう客ごとに積まないので、この表示からは外れた）。
	if not _visit_tally.is_empty():
		lines.append("visit(この客の集計): 判定内訳%s 売上%d %d杯" % [
			str(_visit_tally.get("results", {})),
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
	# favorite は判定後（REACT適用後）だけ出す。判定前は好物を伏せておく（判定に実際に
	# 使った値＝初回は空になる。current_bowlはjudge_bowlに渡した後の値を持つ）。
	var favorite: String = str(_open.current_bowl.get("favorite", ""))
	if result != "" and favorite != "":
		var in_bowl: bool = _open.current_bowl.get("has_favorite", false)
		lines.append("favorite(好物): %s → %s" % [favorite, "入っている" if in_bowl else "入っていない"])
	# ③初回好物の開示：検証用に、判定の有無に関わらず「本来の好物」と既知状態を出す
	# （Event側の生の値。current_bowlの上のfavoriteとは別。書き換えない読み取り専用）。
	var raw_favorite: String = str(_react_for_now().get("favorite", ""))
	if raw_favorite != "":
		var customer_id: String = str(_open.current_bowl.get("customer_id", ""))
		lines.append("favorite_true(本来の好物・デバッグ): %s (known=%s)" % [
			raw_favorite, str(GameState.knows_favorite(customer_id))])
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
