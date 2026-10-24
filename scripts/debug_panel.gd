extends PanelContainer
## 開発用 State Viewer（DESIGN.md 8章 / 9章 STEP 1・STEP 2）。
##
## GameState と EventRunner.status を画面に映し、デバッグボタンで手叩きする。
## 本番のゲーム画面ではない。絵もシナリオも無し。
## 遊びの進行（FlowController・Eventの受け側・状態）は、UI準備Aで共有部品 PlaySession へ移している最中
## （本番UIと同じ処理を使うため）。PlaySession はこのシーンの子ノードとして持つ（autoload にはしない）。
## このパネルは「表示と結線」だけの役に寄せていく。

# UI準備A：遊びの進行を持つ共有部品。_init() で作る（_ready より前から使えるように）。
var session: PlaySession = null

# UI準備Aの橋。テストを移したら削除（本番UIは session.flow を直接使う）。
var flow: FlowController:
	get:
		return session.flow

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
@onready var _btn_retry: Button = $Margin/VBox/PhaseRow/BtnRetry as Button
@onready var _btn_continue: Button = $Margin/VBox/PhaseRow/BtnContinue as Button
# 結果画面（4-2）の選択肢。RESULTのときだけ表示する（仮ボタン。本番UIはフェーズ6）。
@onready var _result_row: HBoxContainer = $Margin/VBox/ResultRow as HBoxContainer
@onready var _btn_run_again: Button = $Margin/VBox/ResultRow/BtnRunAgain as Button
@onready var _btn_last_morning: Button = $Margin/VBox/ResultRow/BtnLastMorning as Button
@onready var _btn_new_run: Button = $Margin/VBox/ResultRow/BtnNewRun as Button
@onready var _btn_end: Button = $Margin/VBox/ResultRow/BtnEnd as Button

# OPEN の間だけ生きる客キュー管理役（STEP 6）。OPEN 以外では null。
# flow.runner は「今の客の接客 runner」に載せ替える。この _open は「今何人目か」を持つだけ。
# UI準備Aの橋。テストを移したら削除（実体は session.open）。
var _open: OpenController:
	get:
		return session.open
	set(value):
		session.open = value

# 自動閉店（DESIGN.md 7.6）で CLOSE に飛ばすときだけ使う、先頭に差し込む理由テキスト。
# _set_runner_for_phase(CLOSE) が読んで消費する（読んだら空文字に戻す＝一度きり）。
# UI準備Aの橋。テストを移したら削除（実体は session.closed_early_reason）。
var _closed_early_reason: String:
	get:
		return session.closed_early_reason
	set(value):
		session.closed_early_reason = value

# ゲームオーバーの理由テキスト。_set_runner_for_phase(GAME_OVER) が読んで消費する
# （_closed_early_reason と同じく一度きり）。
# UI準備Aの橋。テストを移したら削除（実体は session.game_over_reason）。
var _game_over_reason: String:
	get:
		return session.game_over_reason
	set(value):
		session.game_over_reason = value

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
# UI準備Aの橋。テストを移したら削除（実体は session.pending_shortage_ev）。
var _pending_shortage_ev: Variant:
	get:
		return session.pending_shortage_ev
	set(value):
		session.pending_shortage_ev = value

# 鍋モードに入った時点で鍋が空（残量0以下）だった場合、水を入れるまでの間だけ true。
# _on_pot_pressed() で毎回リセットする。
var _pot_water_added := false

# 鍋モードに入った時点で濃さ0（提供不可）だった場合、濃縮だしを入れるまでの間だけ true。
# _pot_water_added と同じ形（濃さメカニクス三点セット）。_on_pot_pressed() で毎回リセットする。
var _pot_dashi_added := false

# 市場（DESIGN.md 7.7）で水場に寄ったか。PREPに入るたびリセットする。
# UI準備Aの橋。テストを移したら削除（実体は session.market_visited_water）。
var _market_visited_water: bool:
	get:
		return session.market_visited_water
	set(value):
		session.market_visited_water = value

# 今どの店の中にいるか（例: "produce"）。空文字なら市場のトップ（7店舗選択）にいる。
# 鍋モード（_pot_mode）と同じ「EventRunnerには触れないUIだけの入れ子」。
# PREPに入るたびリセットする。
# UI準備Aの橋。テストを移したら削除（実体は session.market_shop）。
var _market_shop: String:
	get:
		return session.market_shop
	set(value):
		session.market_shop = value

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
# UI準備Aの橋。テストを移したら削除（実体は session.bowl_discard_count）。
var _bowl_discard_count: int:
	get:
		return session.bowl_discard_count
	set(value):
		session.bowl_discard_count = value

# 1人の客を複数の杯に分けて接客するとき（REACT に aggregate:true を持たせた客）の、
# 退店までの集計。空辞書なら集計中の客はいない。形は
#   { customer, sale, servings, results, pending_favorite }
# 提供記録は杯ごとではなく客1人分として退店時に1回だけ反映するため、ここに積む
# （_flush_visit_tally）。鍋の消費と売上は杯ごとにその場で反映する（集計するのは
# 提供記録だけ。評判はもう杯ごと・客ごとに積まず、日次ログ全体から閉店時に
# GameState.settle_reputation()で1回だけ計算し直す＝④評判の更新）。客のrunnerが
# DONEになったとき、またはフェーズが替わるとき（途中閉店・ゲームオーバー）に
# 空にする＝二重に反映されない。
# UI準備Aの橋。テストを移したら削除（実体は session.visit_tally）。
var _visit_tally: Dictionary:
	get:
		return session.visit_tally
	set(value):
		session.visit_tally = value

# デバッグ用：今夜のモブ人数の強制指定（-1＝自動）。Day2-7ダミーデータ・モブ抽選独立化で、
# Day1Events.customer_schedule()へそのまま渡す値になった（枠ごとに種類も人数も独立抽選する
# ため、-1以外なら全モブ枠の人数だけを一律で上書きする。種類はそれでも枠ごとにばらつく）。
# OPENに入る瞬間に読まれるので、変えるなら OPEN に入る前（WAKE・PREP中）に押すこと。
# GameState には持たせない（本番の挙動・データには関係しない、この計器盤だけの検証用の上書き）。
var _debug_mob_count := -1

# 前日の営業成績（翌朝のWAKE先頭で一度だけ見せる一言サマリー）。_game_over_reasonと
# 同じ「一度だけ消費するテキスト」の形。_on_day_ending()（day_ending。NEXT_DAY→WAKEの
# 折り返し直前に発火）で組み立て、次にWAKEのrunnerを組むときに読んで空文字へ戻す。
var _last_day_summary_text := ""

# F7 同じ朝への復元（再挑戦・セーブ読み込み）の直後のWAKEで、保存してあるDayPlanを
# そのまま使うための一度きりの印（_set_runner_for_phase(WAKE)が読んで消費する。
# _game_over_reasonと同じ「一度だけ」パターン。「今日のplanがあれば作らない」判定に
# しないのは、同じ日にWAKEを繰り返し通る既存の経路・テストで引き直しが止まらないため）。
var _plan_restored := false

# F7 1枠セーブ（フェーズ4-1コミット②・DESIGN.md 10.6）。朝の保存ファイル（MorningSave）へ
# 書いてよいか。起動時に有効なセーブがあれば、[続きから]を押すか最初の朝を抜けるまで
# false（起動した瞬間のDay1の朝で上書きして、続きから選べなくなるのを防ぐ）。
var _save_armed := true
# 起動時に読めたセーブの封筒（[続きから]で戻す先）。無い・読めない・使用済みなら空。
var _pending_continue: Dictionary = {}

# 今日はクズ野菜ベースか（所持金がベース代に満たないので端材屋へ回った日）。PREPに入る瞬間に
# 1回だけ決めて、prep_events と計器盤の両方で使い回す（_debug_mob_count と同じ形）。
# UI準備Aの橋。テストを移したら削除（実体は session.scraps_base）。
var _scraps_base: bool:
	get:
		return session.scraps_base
	set(value):
		session.scraps_base = value

# --- 日次ログ（BALANCE_REDESIGN_PLAN.md §8「①消費と鮮度の明確化・日次ログ」）用の
# 使い捨てカウンタ。経済数値・計算式には一切関与しない、記録専用の値。WAKEに入った瞬間
# （_set_runner_for_phase）にその日ぶんへ初期化し、FlowController.day_ending シグナル
# （NEXT_DAY→WAKE折り返しで日次リセットの前）で読み出してログへ組み立てる。
# GameStateではなくここに置く理由は_mob_count等と同じ：日をまたいで使い捨てる
# 受け側の作業変数であり、GameStateの「事実のみ・永続」という役割ではないため。
# UI準備Aの橋。テストを移したら削除（実体は session.log_opening_money）。
var _log_opening_money: int:
	get:
		return session.log_opening_money
	set(value):
		session.log_opening_money = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_opening_reputation）。
var _log_opening_reputation: int:
	get:
		return session.log_opening_reputation
	set(value):
		session.log_opening_reputation = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_planned_cups）。
var _log_planned_cups: int:
	get:
		return session.log_planned_cups
	set(value):
		session.log_planned_cups = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_judged_planned_cups）。
var _log_judged_planned_cups: int:
	get:
		return session.log_judged_planned_cups
	set(value):
		session.log_judged_planned_cups = value
									 # ④評判の更新：当夜品質Qの分母に使う（_quality_score参照）
# UI準備Aの橋。テストを移したら削除（実体は session.log_water_used）。
var _log_water_used: int:
	get:
		return session.log_water_used
	set(value):
		session.log_water_used = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_dashi_used）。
var _log_dashi_used: int:
	get:
		return session.log_dashi_used
	set(value):
		session.log_dashi_used = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_closed_early）。
var _log_closed_early: bool:
	get:
		return session.log_closed_early
	set(value):
		session.log_closed_early = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_quality_counts）。
var _log_quality_counts: Dictionary:
	get:
		return session.log_quality_counts
	set(value):
		session.log_quality_counts = value
# UI準備Aの橋。テストを移したら削除（実体は session.log_spoiled_items）。
var _log_spoiled_items: Dictionary:
	get:
		return session.log_spoiled_items
	set(value):
		session.log_spoiled_items = value

# --- ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6。モブ客の団体オーダーだけが対象） ---
# モブ客のADJUST中に選んだ具材を、在庫を引かずに一時記録するリスト（{"id":String,
# "damaged":bool}の配列）。人数が確定した瞬間（_serve_mob_partial）まで在庫消費を遅らせる
# ため、「選ぶ」と「消費する」を分離する置き場所。名前あり客・配達員は使わない
# （今までどおり選んだ瞬間に消費）。
# UI準備Aの橋。テストを移したら削除（実体は session.mob_picks）。
var _mob_picks: Array:
	get:
		return session.mob_picks
	set(value):
		session.mob_picks = value

# [入力完了]を押して「N人分を提供／注文を断る」の確認ボタンを表示中か。
# trueの間、_update_options_row()はADJUSTの具材ボタンの代わりにこの2択を出す
# （_pot_mode/_phone_modeと同じ「専用ボタン行に差し替える」パターン）。
# UI準備Aの橋。テストを移したら削除（実体は session.pending_group_choice）。
var _pending_group_choice: bool:
	get:
		return session.pending_group_choice
	set(value):
		session.pending_group_choice = value

# 確認ボタンで確定した結果（{"servings": 実際に提供する人数, "ordered": 注文人数,
# "retry_remaining": 挑戦を選んだ場合の残り人数（挑戦しないときは省略/0）}）。
# 空でなければ、_apply_event()のREACTケースがこちらを使って_serve_mob_partial()／
# _serve_mob_recipe_and_retry()へ委譲する（名前あり客・配達員のREACTは常にこれが空
# なので既存の経路のまま無影響）。
# UI準備Aの橋。テストを移したら削除（実体は session.pending_group_result）。
var _pending_group_result: Dictionary:
	get:
		return session.pending_group_result
	set(value):
		session.pending_group_result = value

# F3 断る操作（DESIGN.md 10.3.6）：名前あり客・配達員のADJUST中に[客を断る]を押したか。
# trueのままADJUST→SERVE→REACTへ進み、_apply_event()のREACTケースが判定・消費・売上を
# 一切発生させずに未提供として記録する（_pending_group_resultと同じ「確認結果を持ち越す」
# パターンだが、モブとは独立したフラグにして混線を避ける）。
# UI準備Aの橋。テストを移したら削除（実体は session.pending_decline）。
var _pending_decline: bool:
	get:
		return session.pending_decline
	set(value):
		session.pending_decline = value
# 断った客のREACTを表示している間だけtrue（反応文をreactions.UNSERVEDから引くため）。新しい客・
# 再挑戦・新しい周でリセット（システム整理C1）。
# UI準備Aの橋。テストを移したら削除（実体は session.declined_now）。
var _declined_now: bool:
	get:
		return session.declined_now
	set(value):
		session.declined_now = value
# 提供できないまま閉店して退店する客の未提供版（反応・must_infoの本文）。CLOSEの先頭に一度だけ
# 積む（_closed_early_reasonと同じ「一度だけ」パターン。システム整理C1）。
# UI準備Aの橋。テストを移したら削除（実体は session.pending_close_lines）。
var _pending_close_lines: Array:
	get:
		return session.pending_close_lines
	set(value):
		session.pending_close_lines = value
# 共通イベント（Day6の衝突・火災など。News）：その日に再生した（差し込んだ）イベントのid、と、時間帯の
# 最初の客に前置したイベントのid（時間帯の位置ごと。_load_current_customerが同じ客で何度呼ばれても
# 二重に前置せず、同じ列を組み直せるようにする）。保存しない実行時の値で、WAKE・再挑戦・新しい周で
# リセットする（システム整理D）。
# UI準備Aの橋。テストを移したら削除（実体は session.played_events）。
var _played_events: Array:
	get:
		return session.played_events
	set(value):
		session.played_events = value
# UI準備Aの橋。テストを移したら削除（実体は session.slot_event_ids）。
var _slot_event_ids: Dictionary:
	get:
		return session.slot_event_ids
	set(value):
		session.slot_event_ids = value
# レシピ保存（4-7①。仮UI）：保存の段階（""＝ボタン待ち／"slot"＝枠を選ぶ／"name"＝名前を選ぶ）と選んだ枠。
# レシピ用のボタン行は _ready でコードから足す（.tscn は変えない）。
# UI準備Aの橋。テストを移したら削除（実体は session.recipe_save_stage）。
var _recipe_save_stage: String:
	get:
		return session.recipe_save_stage
	set(value):
		session.recipe_save_stage = value
# 修繕基金（4-9。RepairFund）：段階が上がった瞬間の一行（CLOSEの間だけ出す。runnerのイベントではない）。
var _fund_notice := ""
# 積む先の対象のid（選択は実行時のみ・保存しない）。空・修繕済み・未解放なら既定（最初の未修繕の対象）を使う。
var _fund_target := ""
# 会話ログ（4-7②。TalkLog）：すでに記録した位置（日・フェーズ・時間帯・客のindex・イベントのindex・本文）。
# _load_current_customer が同じ客で何度呼ばれても・再描画しても二重に記録しないための印。保存しない。
var _logged_positions := {}
# 既読スキップ（4-7③。ReadState）：直近に新しく見えた行が、それまで未読だったか（スキップの停止条件）。
# [既読スキップ]の仮ボタンは _ready でコードから足す（.tscn は変えない）。
var _last_shown_unread := false
var _btn_skip_read: Button
const SKIP_READ_LIMIT := 200   # 暴走防止：1回のスキップで進めるイベント数の上限
var _recipe_save_slot := -1
var _recipe_row: HBoxContainer

# 聞き直し（4-4b-2。DESIGN.md 10.5.2）の再表示テキスト。画面側だけの一時表示で、GameState・
# 帳簿・来店記録を一切変えない（何度押しても同じ。保存しない）。客が替わる・保存から戻すと消える。
# UI準備Aの橋。テストを移したら削除（実体は session.reask_customer_id／reask_lines。表示用の文はここで組む）。
var _reask_text: String:
	get:
		if session.reask_customer_id == "":
			return ""
		var parts := PackedStringArray([_format_order_card(session.reask_customer_id)])
		for line in session.reask_lines:
			parts.append(str(line))
		return "\n".join(parts)
	set(value):
		if value == "":
			session.clear_reask()

# 団体客の分割提供（最大2レシピ）：グループの元々の総注文人数（レシピ2でも変わらない。
# _flush_visit_tally()でordered_servings/unserved_servingsを出すために覚えておく）。
# 新しい客をロードするたびにのみ-1へ戻す（_reset_mob_group_state()には入れない。
# こちらは[廃棄する]でも呼ばれるため、レシピ2の作り直し時に元注文数を消してしまう）。
# UI準備Aの橋。テストを移したら削除（実体は session.mob_original_ordered）。
var _mob_original_ordered: int:
	get:
		return session.mob_original_ordered
	set(value):
		session.mob_original_ordered = value

# 今どちらのレシピを提供中か（1または2）。2に達したら「挑戦する」ボタンは出さない
# （最大2レシピの打ち止め）。_mob_original_ordered と同じ理由で客のロード時にのみ1へ戻す。
# UI準備Aの橋。テストを移したら削除（実体は session.mob_recipe_number）。
var _mob_recipe_number: int:
	get:
		return session.mob_recipe_number
	set(value):
		session.mob_recipe_number = value


func _init() -> void:
	session = PlaySession.new()
	session.name = "PlaySession"
	add_child(session)


func _ready() -> void:
	# 1枠セーブ：最初の朝のWAKE処理より前に、起動時のセーブを読んでおく。
	_pending_continue = MorningSave.read_file()
	_save_armed = _pending_continue.is_empty()
	_seed_initial_inventory()
	_set_runner_for_phase(GameState.phase)

	# 以下は「どのボタン/シグナルが何を呼ぶか」の結線。処理内容は各ハンドラ側にある。
	# 最終日の翌朝の巻き戻し後に、初期在庫を積み直す（reset → 積み直し → phase_changed の順）。
	session.changed.connect(_refresh)                  # 遊びの状態が変わった → 描き直す（UI準備A）
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
	# [同じ朝からやり直す] = ゲームオーバーのときだけ押せる（F7。仮ボタン。本番UIはフェーズ6）。
	_btn_retry.pressed.connect(_on_retry_pressed)
	# [続きから] = 起動時に読めたセーブの朝へ戻る（仮ボタン。本番UIはフェーズ6）。
	_btn_continue.pressed.connect(_on_continue_pressed)
	# 結果画面の選択肢（4-2）。[終わる]は押せない仮ボタン（フェーズ6）なので結線しない。
	_btn_run_again.pressed.connect(_on_run_again_pressed)
	_btn_last_morning.pressed.connect(_on_last_morning_pressed)
	_btn_new_run.pressed.connect(_on_new_run_pressed)
	# [スマホ] = 3つ目の入れ子モードに入るだけ（EventRunner・GameStateには触れない。
	#   _on_pot_pressed() と同じ形）。常時押せる（例外は開いている間、自身が無効化される）。
	_btn_phone.pressed.connect(_on_phone_pressed)

	# [既読スキップ]（4-7③。仮ボタン）：[次のEvent]の隣。
	_btn_skip_read = Button.new()
	_btn_skip_read.text = "既読スキップ"
	_btn_skip_read.pressed.connect(_on_skip_read_pressed)
	_btn_next_event.get_parent().add_child(_btn_skip_read)
	_btn_next_event.get_parent().move_child(_btn_skip_read, _btn_next_event.get_index() + 1)

	# レシピ用のボタン行（4-7①）：SeasoningRow の下。ADJUST 中の「いつもの」・保存レシピと、提供後の保存ボタン。
	_recipe_row = HBoxContainer.new()
	_recipe_row.add_theme_constant_override("separation", 8)
	var vbox := _seasoning_row.get_parent()
	vbox.add_child(_recipe_row)
	vbox.move_child(_recipe_row, _seasoning_row.get_index() + 1)

	_refresh()


## パネルが木から外れる（終了）とき、既読を書き出す（変更が無ければ書かない）。
func _exit_tree() -> void:
	ReadState.flush()


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


## 結果画面の選択肢の表示・有効無効（RESULTとGAME_OVERのときだけ見せる）。
## RESULT：[もう一度]は、Day1の朝の記録が無い周（[続きから]で途中から始めた周）では押せず、
## 理由をボタンに出す。
## GAME_OVER（先に直す②）：出口を3つ持つ。[最後の朝]（記録があるとき）・[Day1の朝から]・[新しい周]。
## [Day1の朝から]はDay1の記録が無くても押せて、その場合は[新しい周]と同じ動作になる
## （ボタンの文面で分かるようにする。_on_run_again_pressed）。
func _refresh_result_row() -> void:
	var in_result := GameState.phase == GameState.Phase.RESULT
	var in_over := GameState.phase == GameState.Phase.GAME_OVER
	_result_row.visible = in_result or in_over
	var has_day1 := GameState.morning_snapshots.has(1)
	_btn_run_again.disabled = not (in_result or in_over) or (in_result and not has_day1) or _phone_mode
	if has_day1:
		_btn_run_again.text = "もう一度（Day1の朝から）\nDay1の客・需要のみ同じ。2日目以降は評判次第で変わる"
		_btn_run_again.tooltip_text = ""
	elif in_over:
		_btn_run_again.text = "Day1の朝から（＝新しい周と同じ）\nDay1の朝の記録が無い（続きから始めた周のため）。新しい周が始まる"
		_btn_run_again.tooltip_text = "続きから始めた周は、Day1の朝の記録を持っていません。押すと[新しい周]と同じ動作になります。"
	else:
		_btn_run_again.text = "もう一度（使えません）\nDay1の朝の記録が無い（続きから始めた周のため）"
		_btn_run_again.tooltip_text = "続きから始めた周は、Day1の朝の記録を持っていません。"
	_btn_last_morning.disabled = not (in_result or in_over) or GameState.morning_snapshots.is_empty() or _phone_mode
	_btn_last_morning.text = "最後の朝からやり直す" if in_result else "直近の朝からやり直す"
	_btn_new_run.disabled = not (in_result or in_over) or _phone_mode
	_btn_end.disabled = true   # 押せない仮ボタン（フェーズ6）


func _on_phase_changed(phase: int) -> void:
	_set_runner_for_phase(phase)
	_arm_save_after_first_morning(phase)
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
	_fund_notice = ""
	_fund_target = ""
	# 7.7: 市場の水場訪問フラグ・店の中にいるかも PREP に入るたびリセットする。
	_market_visited_water = false
	_market_shop = ""
	# スマホも鍋・市場と同じくフェーズをまたいで持ち越さない（防御的リセット）。
	_phone_mode = false
	_phone_tab = "recipe"
	if phase == GameState.Phase.WAKE:
		TalkLog.clear()   # 会話ログは今日の分だけ（朝へ戻したら空から）
		_logged_positions = {}
		_played_events = []   # 共通イベントはその日ごと（朝へ戻したら最初から再生し直す）
		_slot_event_ids = {}
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
		# F7 朝の保存（DESIGN.md 10.8.7）：今日のDayPlanを先に確定させてから、運営費を引く
		# 前の状態を「朝の辞書」にする（運営費の支払いは乱数を引かないので、build()を
		# 先に呼んでも抽選結果・乱数の消費順は従来と変わらない）。再挑戦・セーブ読み込みで
		# 戻った朝（_plan_restored）は保存してあるDayPlanをそのまま使い、build()を呼ばない
		# ＝抽選を引き直す手段にしない。
		if _plan_restored:
			_plan_restored = false
		else:
			DayPlanner.build(_debug_mob_count)
		var morning := MorningSave.capture(_last_day_summary_text)
		# 日々の運営費（場所代・水道代の再編＋日々の運営費）：WAKEに入った瞬間に必ず1回
		# 直接支払う。wake_events()側にPAY Eventとして置かないのは、WAKEが
		# _phase_can_skip=true（[次のPhase]でrunnerを消化せず進める）なので、Event列に
		# 頼ると支払いを毎回スキップできてしまうため（_visit_water_stall()と同じ
		# 「Eventを介さず直接コードで払う」方式に揃える）。
		# 支払えずゲームオーバーになったら、force_phase(GAME_OVER)が既に
		# _set_runner_for_phase(GAME_OVER)を呼んでrunnerを組んでいるので、ここで
		# wake_events()のrunnerに上書きしないよう即returnする。
		if not _pay_or_game_over(GameState.DAILY_OPERATING_COST, "daily_cost"):
			return
		# 運営費が払えた朝だけ記録する（払えずゲームオーバーになった朝へ戻っても、同じ
		# 不足で必ず詰むため。戻れる最後の朝＝GameState.latest_morning()は前日の朝になる）。
		GameState.record_morning(morning)
		# 1枠セーブ：記録と同じ朝の辞書を書く（運営費が払えた朝だけ。読み込んだ朝が
		# 運営費で詰むことは無い）。
		if _save_armed:
			MorningSave.write_file(morning)
		# F4 帳簿：今日まだ払っていない請求を「確保」として記帳する（旧GameState.
		# set_pending_bills_for_today()。3-5（DESIGN.md 10.3.5）で徴収日は場所代に加え水道代ぶんも
		# 確保対象に含めた＝実際の支払いタイミングは変えていない。水道代は水場訪問時、場所代は
		# 場所代の支払い時に払い、その瞬間にreleaseする。Ledger.pending_bills_today()がこの記帳から
		# 確保額を計算し直す）。日々の運営費は上でもう払い済みなので確保しない（先に直す③：
		# 払った金額をもう一度確保すると、使える現金が運営費ぶん二重に引かれていた）。
		var reserve_amount := 0
		if GameState.is_collection_day():
			reserve_amount = GameState.RENT_PRICE + GameState.WATER_PRICE
		if reserve_amount > 0:
			Ledger.record("reserve", -reserve_amount)
		# 予告（②）：今夜の客の並びは上のDayPlanner.build()で1回だけ確定させ、OPENでは
		# （デバッグの一律上書き中を除き）これを使い回す。以前はOPENに入る瞬間まで客層も
		# 人数も分からなかった＝プレイヤーが仕込み量を勘で決めるしかなかった詰みポイントの
		# 一つだったため、スマホの「SNS」タブ（_format_tonight_memo）で見せられる
		# ようにする。F2 DayPlan（DESIGN.md 10.8.2）：GameState.today_planへ確定させる
		# のはDayPlanner.build()の役目（F7でbuild()の呼び出しは運営費の前へ移した）。
		# 前日の成績（③）：day_ending（NEXT_DAY→WAKEの折り返し）で既に組み立て済みの
		# 一言サマリーがあれば、今日の起床イベントの先頭に差し込む（読んだら消費する。
		# _closed_early_reason/_game_over_reasonと同じ「一度だけ」パターン）。
		var wake_ev := Day1Events.wake_events()
		_mark_events_played(wake_ev)
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
		# 予告（②）：通常はWAKEで確定させたGameState.today_plan["slots"]をそのまま使う
		# （客層・人数を開店直前に変えない＝SNSタブで見せた内容と実際の客入りを一致させる）。
		# デバッグの一律上書き中（_debug_mob_count>=0）は、ボタンの「次にOPENに入る
		# ときから効く」という既存の挙動を保つため、ここで引き直す（QAの便宜。
		# SNSタブの表示が直前の内容と食い違う可能性があるのは元からデバッグ専用機能
		# なので許容する）。today_plan["slots"]が空（テスト等でWAKEを経由せずOPENへ直接
		# 遷移した場合の防御）のときも同様に引き直す＝WAKEを通らなくても従来どおり
		# 動く（この保険はデバッグ上書きが無い自動抽選でも効くので、テストからの
		# 直接呼び出しでcustomer_schedule()が空振りする心配は無い）。
		if _debug_mob_count >= 0 or GameState.today_plan.get("slots", []).is_empty():
			DayPlanner.build(_debug_mob_count)
		_open = OpenController.new(GameState.today_plan.get("slots", []))
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
		# 営業中に届かなかった共通イベント（早仕舞いなど）を、閉店の語りの前に取り戻す
		# （必須情報を客・営業の長さに依存させない）。時系列（データの並び順）で、再生済みは出さない。
		var overdue := []
		for item in News.pending_events(GameState.day_count, _played_events):
			overdue.append_array(News.event_lines(item))
		_mark_events_played(overdue)
		events = overdue + events
		# 提供できないまま退店した客の未提供版（理由テキストの次・共通イベントの前）。
		events = _pending_close_lines + events
		_pending_close_lines = []
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
	elif phase == GameState.Phase.RESULT:
		ReadState.flush()   # 結果画面でも既読を書き出す
		# 結果画面（4-2・DESIGN.md 10.6）：成績・目標・仮の物語欄の3ブロック。集計は
		# GameState.day_records（周回の累計）と帳簿から導く（Result）。選択肢はResultRow。
		var summary := Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
		var goal_results := Result.judge_goals(summary, Rules.goals(), Rules.final_day())
		flow.set_runner([
			{ "type": "TEXT", "text": Result.format_report(summary) },
			{ "type": "TEXT", "text": Result.format_goals(goal_results) },
			{ "type": "TEXT", "text": Result.format_story(summary, GameState.known_favorite_ids()) },
		])
	else:
		flow.set_runner([])   # NEXT_DAY など未実装フェーズ（空 runner ＝即 DONE）


# UI準備Aの橋。テストを移したら削除（本番UIは session.load_current_customer() を直接使う）。
func _load_current_customer() -> void:
	session.load_current_customer()


# UI準備Aの橋。テストを移したら削除（本番UIは session.next_event() を直接使う）。
func _on_next_event_pressed() -> void:
	session.next_event()


# UI準備Aの橋。テストを移したら削除（本番UIは session.complete_input() を直接使う）。
func _on_complete_input_pressed() -> void:
	session.complete_input()


# UI準備Aの橋。テストを移したら削除（本番UIは session.select_ingredient() を直接使う）。
func _on_ingredient_selected(ingredient_id: String, damaged: bool = false) -> void:
	session.select_ingredient(ingredient_id, damaged)


# UI準備Aの橋。テストを移したら削除（本番UIは session.discard_bowl() を直接使う）。
func _on_discard_pressed() -> void:
	session.discard_bowl()


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
	_queue_unserved_exit()
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


# UI準備Aの橋。テストを移したら削除（本番UIは session.select_stall() を直接使う）。
func _on_market_stall_selected(id: String) -> void:
	session.select_stall(id)


# UI準備Aの橋。テストを移したら削除（本番UIは session.shop_goods() を直接使う）。
func _shop_goods(shop: String) -> Array:
	return PlaySession.shop_goods(shop)


# UI準備Aの橋。テストを移したら削除（本番UIは session.buy_item() を直接使う）。
func _on_shop_item_selected(shop: String, id: String) -> void:
	session.buy_item(shop, id)


# UI準備Aの橋。テストを移したら削除（本番UIは session.choose_prep_tier() を直接使う）。
func _on_prep_tier_selected(tier_id: String) -> void:
	session.choose_prep_tier(tier_id)


# UI準備Aの橋。テストを移したら削除（本番UIは session.leave_shop() を直接使う）。
func _on_shop_exit_pressed() -> void:
	session.leave_shop()


# UI準備Aの橋。テストを移したら削除（本番UIは session.visit_water_stall() を直接使う）。
func _visit_water_stall() -> bool:
	return session.visit_water_stall()


# UI準備Aの橋。テストを移したら削除（本番UIは session.exit_market() を直接使う）。
func _on_market_exit_pressed() -> void:
	session.exit_market()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_in_market() を直接使う）。
func _is_in_market() -> bool:
	return session.is_in_market()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_in_story_choice() を直接使う）。
func _is_in_story_choice() -> bool:
	return session.is_in_story_choice()


# UI準備Aの橋。テストを移したら削除（本番UIは session.choose_story_option() を直接使う）。
func _on_story_choice_pressed(choice_id: String, option_id: String) -> void:
	session.choose_story_option(choice_id, option_id)


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_in_prep_tier() を直接使う）。
func _is_in_prep_tier() -> bool:
	return session.is_in_prep_tier()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_choosing_ingredients() を直接使う）。
func _is_choosing_ingredients() -> bool:
	return session.is_choosing_ingredients()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_awaiting_react() を直接使う）。
func _is_awaiting_react() -> bool:
	return session.is_awaiting_react()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.complete_input_and_advance() を直接使う）。
func _complete_input_and_advance() -> void:
	session.complete_input_and_advance()


# UI準備Aの橋。テストを移したら削除（本番UIは session.advance_open_queue_if_customer_done() を直接使う）。
func _advance_open_queue_if_customer_done() -> void:
	session.advance_open_queue_if_customer_done()


# UI準備Aの橋。テストを移したら削除（本番UIは session._apply_event() を直接使う）。
func _apply_event(ev) -> void:
	session._apply_event(ev)


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_current_mob_order() を直接使う）。
func _is_current_mob_order() -> bool:
	return session.is_current_mob_order()


# UI準備Aの橋。テストを移したら削除（本番UIは session.mob_achievable_servings() を直接使う）。
func _mob_achievable_servings(ordered: int) -> int:
	return session.mob_achievable_servings(ordered)


# UI準備Aの橋。テストを移したら削除（本番UIは session.reset_mob_group_state() を直接使う）。
func _reset_mob_group_state() -> void:
	session.reset_mob_group_state()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session._serve_mob_partial() を直接使う）。
func _serve_mob_partial(ev: Dictionary, actual: int, ordered: int) -> void:
	session._serve_mob_partial(ev, actual, ordered)


# UI準備Aの橋。テストを移したら削除（本番UIは session._serve_mob_recipe_and_retry() を直接使う）。
func _serve_mob_recipe_and_retry(ev: Dictionary, actual: int, remaining: int) -> void:
	session._serve_mob_recipe_and_retry(ev, actual, remaining)


# UI準備Aの橋。テストを移したら削除（本番UIは session._serve_customer() を直接使う）。
func _serve_customer(ev: Dictionary) -> void:
	session._serve_customer(ev)


## [客を断る]のハンドラ（F3・DESIGN.md 10.3.6）。名前あり客・配達員のADJUST中、いつでも
## 押せる（達成可能かどうかを問わない。モブの「注文を断る」は既に無条件で選べるので対象外＝
## _is_current_mob_order()のときはこのボタン自体を出さない）。判定・鍋消費・売上を一切
## 発生させず、_pending_group_serveと同じ「ADJUST側で確定させてREACT到達時に反映する」
## パターンでSERVE→REACTへ進める。
func _on_customer_decline_pressed() -> void:
	_pending_decline = true
	_complete_input_and_advance()


# UI準備Aの橋。テストを移したら削除（本番UIは session.flush_visit_tally() を直接使う）。
func _flush_visit_tally() -> void:
	session.flush_visit_tally()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_short_now() を直接使う）。
func _is_short_now() -> bool:
	return session.is_short_now()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_short_in_adjust() を直接使う）。
func _is_short_in_adjust() -> bool:
	return session.is_short_in_adjust()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_servings_short_context() を直接使う）。
func _is_servings_short_context() -> bool:
	return session.is_servings_short_context()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_strength_zero() を直接使う）。
func _is_strength_zero() -> bool:
	return session.is_strength_zero()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_strength_zero_in_adjust() を直接使う）。
func _is_strength_zero_in_adjust() -> bool:
	return session.is_strength_zero_in_adjust()


# UI準備Aの橋。テストを移したら削除（本番UIは session.is_bowl_unsellable_in_adjust() を直接使う）。
func _is_bowl_unsellable_in_adjust() -> bool:
	return session.is_bowl_unsellable_in_adjust()


# UI準備Aの橋。テストを移したら削除（本番UIは session.can_close_now() を直接使う）。
func _can_close_now() -> bool:
	return session.can_close_now()


# UI準備Aの橋。呼び出し元（WAKE・PAY・場所代の特別請求）を移したら削除（実体は session.pay_or_game_over()）。
func _pay_or_game_over(amount: int, category: String = "") -> bool:
	return session.pay_or_game_over(amount, category)


# UI準備Aの橋。呼び出し元を移したら削除（実体は session.game_over()）。
func _game_over(reason: String) -> void:
	session.game_over(reason)


## F7 同じ朝からの再挑戦（DESIGN.md 10.6・10.8.7）。戻れる最後の朝（GameState.latest_morning()）
## へ状態を戻し、WAKEからやり直す。戻した朝の客・需要（DayPlan）は保存したものと同じで、
## build()は呼ばない（抽選を引き直す手段にしない）。運営費が払えずゲームオーバーになった
## ときは、その朝は記録されていないので前日の朝へ戻る。戻る先が無い／封筒が壊れていれば
## 何もせず false を返す（呼び出し側が新規ゲーム等を決める）。
## 4-2（結果画面）の再挑戦も、この関数を呼ぶ。dayを指定すると、その日の朝へ戻る
## （「もう一度＝Day1の朝から」はday=1。戻した日より後の朝の記録は、from_dictが捨てる
## ＝戻した直後に詰んでも、再挑戦が後ろの日の朝へ飛ばない）。
func retry_from_morning(day: int = -1) -> bool:
	var morning := GameState.latest_morning() if day < 0 else GameState.morning_of(day)
	if morning.is_empty() or not MorningSave.is_valid(morning):
		return false
	_restore_morning(morning)
	BalanceLog.note_retry()   # 同じ周の次の挑戦（日次ログの行を区別する）
	return true


## 封筒の朝へ戻す共通処理（再挑戦・セーブ読み込み）。GameState側はfrom_dict、画面側は
## 保存しない状態（接客の途中経過・一度きりの文）を捨て、前日成績の一言だけ戻す。
func _restore_morning(morning: Dictionary) -> void:
	_reset_transient_panel_state()
	MorningSave.apply(morning)
	_last_day_summary_text = str((morning["panel"] as Dictionary)["day_summary_text"])
	_plan_restored = true
	flow.force_phase(GameState.Phase.WAKE)


## 画面側の保存しない状態を捨てる（再挑戦・セーブ読み込み・新しい周の共通処理）。
## 戻す／初期化する前に、途中の客・集計を捨てる（_set_runner_for_phase冒頭の
## _flush_visit_tally()が古い接客を今の状態へ書き込まないようにするため）。
func _reset_transient_panel_state() -> void:
	_visit_tally = {}
	_reset_mob_group_state()
	_pending_decline = false
	_declined_now = false
	_pending_close_lines = []
	_played_events = []
	_slot_event_ids = {}
	_recipe_save_stage = ""
	_fund_notice = ""
	_fund_target = ""
	_logged_positions = {}
	TalkLog.clear()
	_mob_original_ordered = -1
	_mob_recipe_number = 1
	_bowl_discard_count = 0
	_closed_early_reason = ""
	_game_over_reason = ""
	_reask_text = ""


func _on_retry_pressed() -> void:
	retry_from_morning()


## 結果画面：もう一度（Day1の朝から）。Day1の朝の記録（morning_snapshots[1]）へ戻す。
## 累計（day_records）もDay1の朝の値（空）に戻る。Day1の客・需要は同じで、2日目以降は
## 評判次第で抽選が変わる。[続きから]で始めた周はDay1の記録が無いので、RESULTでは押せない。
## GAME_OVERでは押せて、Day1の記録が無いときは[新しい周]と同じ動作にする（出口を塞がない）。
func _on_run_again_pressed() -> void:
	if GameState.phase == GameState.Phase.GAME_OVER and not GameState.morning_snapshots.has(1):
		_on_new_run_pressed()
		return
	retry_from_morning(1)


## 結果画面：最後の朝（最終日の朝）からやり直す。累計は最終日の朝の値に戻る。
func _on_last_morning_pressed() -> void:
	retry_from_morning()


## 結果画面：新しい周。reset_for_new_game()＋game_restartedの後、Day1のWAKEから始める
## （従来の最終日の翌朝の挙動と同じ状態。朝の記録・累計もクリアされ、保存も新しい周の
## Day1の朝で上書きされる）。
func _on_new_run_pressed() -> void:
	_reset_transient_panel_state()
	GameState.reset_for_new_game()
	_last_day_summary_text = ""
	_plan_restored = false
	flow.game_restarted.emit()
	flow.force_phase(GameState.Phase.WAKE)


## 起動時に読めたセーブの朝へ戻る。いまの（起動直後の）ゲームの朝の記録は捨て、
## 読み込んだ朝をGameState.morning_snapshotsへ入れる（読み込んだ朝で詰んだときの
## 戻り先になる。retry_from_morning()がこの記録を使う）。
func _on_continue_pressed() -> void:
	if _pending_continue.is_empty():
		return
	var morning := _pending_continue
	_pending_continue = {}
	_save_armed = true
	GameState.morning_snapshots.clear()
	GameState.record_morning(morning)
	_restore_morning(morning)
	BalanceLog.begin_run()   # 続きから読み込んだ周は別の周（日次ログのrun_idを新しくする）


## 起動時にセーブがあったとき、最初の朝（WAKE）を抜けた時点で書き込みを有効にする
## （[続きから]を押さずに新規ゲームを進めた＝上書きしてよい）。この時点で、いまの
## 朝の記録を1枠セーブへ書く（この後の朝は、WAKEが通常どおり書く）。ゲームオーバーで
## 最初の朝を抜けた場合は何も書かない（記録が無い）。
func _arm_save_after_first_morning(phase: int) -> void:
	if _save_armed or phase == GameState.Phase.WAKE or phase == GameState.Phase.GAME_OVER:
		return
	_save_armed = true
	_pending_continue = {}
	var morning := GameState.latest_morning()
	if not morning.is_empty():
		MorningSave.write_file(morning)


# UI準備Aの橋。テストを移したら削除（本番UIは session._auto_close_kitchen() を直接使う）。
func _auto_close_kitchen() -> void:
	session._auto_close_kitchen()


# UI準備Aの橋。テストを移したら削除（本番UIは session.mark_events_played() を直接使う）。
func _mark_events_played(events: Array) -> void:
	session.mark_events_played(events)


# UI準備Aの橋。テストを移したら削除（本番UIは session.queue_unserved_exit() を直接使う）。
func _queue_unserved_exit() -> void:
	session.queue_unserved_exit()


# UI準備Aの橋。テストを移したら削除（本番UIは session.reason_after_collecting_rent() を直接使う）。
func _reason_after_collecting_rent(base_reason: String) -> String:
	return session.reason_after_collecting_rent(base_reason)


func _on_runner_updated() -> void:
	_refresh()


## 日次ログの本体（FlowController.day_ending。NEXT_DAY→WAKEの折り返しで、日次リセットの
## 前に発火する）。GameStateがまだその日の値のうちに集計を確定し、コンソールとファイルへ
## 出す。④評判の更新（BALANCE_REDESIGN_PLAN.md§5）：ここで初めて、当夜品質Qから
## GameState.settle_reputation()を1回だけ呼んで評判を確定させる（OPEN中は動かさない）。
func _on_day_ending() -> void:
	ReadState.flush()   # 既読は日の終わりに書き出す（1行ごとには書かない）
	var served_cups := 0
	var sale_total := 0
	for record in GameState.served:
		if record is Dictionary and not bool(record.get("discarded", false)):
			served_cups += int(record.get("servings", 0))
			sale_total += int(record.get("sale", 0))
	var unserved_cups: int = maxi(_log_planned_cups - served_cups, 0)
	var spoiled_value := _spoiled_value(_log_spoiled_items)
	var quality := _quality_score(_log_quality_counts, _log_judged_planned_cups)
	# 4-2：常連（名前あり客）への提供の杯数・GREAT・GOOD以上と、その日に来た常連のid。
	# 結果画面の「常連GREAT」「客との間に残ったこと」の元になる（Result.regular_stats）。
	var regulars := Result.regular_stats(GameState.served)
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
		# F4 前日成績v2（DESIGN.md 10.8.4）：Ledgerから初めて出せるようになった追加情報。
		# 既存キーは1つも変更していない（balance_log.jsonlの互換性を保つため、追加のみ）。
		"spend_by_category": Ledger.spend_by_category_today(),
		# 4-2 結果画面用（追加のみ）：常連の杯数・GREAT・GOOD以上・来店した常連のid。
		"regular_cups": int(regulars["cups"]), "regular_great": int(regulars["great"]),
		"regular_good_plus": int(regulars["good_plus"]),
		"regular_visits": regulars["visits"],
	}
	print("BALANCE_LOG: day=%d money=%d→%d rep=%d→%d(Q=%.1f) cups=%d/%d(計画%d) 売上=%d 廃棄額=%d 水%d/だし%d 早期閉店=%s 評価=%s" % [
		log_entry["day"], log_entry["opening_money"], log_entry["closing_money"],
		log_entry["opening_reputation"], log_entry["closing_reputation"], quality,
		served_cups, unserved_cups, _log_planned_cups, sale_total, spoiled_value,
		_log_water_used, _log_dashi_used, str(_log_closed_early), str(_log_quality_counts)])
	BalanceLog.append(log_entry)
	# 4-2：1日の記録を周回の累計へ足す（結果画面の集計元。朝の辞書に入るので、再挑戦・
	# 続きからで戻した朝より後の日は持たない）。
	GameState.record_day(log_entry)
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
	# F4 前日成績v2：Ledgerのカテゴリ別支出をそのまま並べる（新しい集計はしない。
	# spend_by_categoryはLedger.spend_by_category_today()の結果をそのまま持つ）。
	var spend_line := _format_spend_by_category(log_entry.get("spend_by_category", {}))
	if spend_line != "":
		lines.append(spend_line)
	# 修繕基金（4-9）：基金を積んだ日だけ、屋台の段階を1行足す（積まなかった日の文面は従来と同一）。
	if RepairFund.enabled() and int((log_entry.get("spend_by_category", {}) as Dictionary).get("fund", 0)) > 0:
		lines.append("屋台: %s" % RepairFund.progress_text())
	if bool(log_entry.get("closed_early", false)):
		lines.append("（鍋が尽きて早めに閉店した）")
	return "\n".join(lines)


## F4 前日成績v2：Ledger.spend_by_category_today()の結果を「運営費80／場所代90」の
## ような1行にする。固定の並び順で、支出が無かったカテゴリ（0または未記帳）は出さない。
## 全カテゴリ0（何も支出が無い日）なら空文字を返す（_format_day_summary側で行を足さない）。
func _format_spend_by_category(spend: Dictionary) -> String:
	const CATEGORY_LABELS := {
		"daily_cost": "運営費", "rent": "場所代", "water": "水道代",
		"kit": "初日セット", "prep": "仕込み", "market": "市場", "dashi": "だし",
		"fund": "修繕基金",
	}
	var parts := PackedStringArray()
	for category in ["daily_cost", "rent", "water", "kit", "prep", "market", "dashi", "fund"]:
		var amount: int = int(spend.get(category, 0))
		if amount > 0:
			parts.append("%s%d" % [CATEGORY_LABELS[category], amount])
	if parts.is_empty():
		return ""
	return "支出内訳: %s" % "／".join(parts)


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
		_runner_label.text = _format_runner() + _format_open() + _format_market() + _format_fund()
	_update_options_row()
	_record_visible_event()


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
	if _recipe_row != null:
		for child in _recipe_row.get_children():
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
			or _is_in_market() or _is_in_prep_tier() or _is_in_story_choice() \
			or _phone_mode or _pending_group_choice
	# 不足のADJUSTでは提供（[入力完了]）できない。補充するか、閉店するか廃棄以外を選ぶ。
	# ②拒否と部分提供：モブ客は鍋不足だけでは塞がない（達成可能人数の計算に鍋残量も
	# 含めており、[入力完了]を押せば確認ボタンへ進めるため。名前あり客・配達員は無変更）。
	# 濃さメカニクス三点セット：濃さ0も同じ扱い（モブは_mob_achievable_servings()が
	# 強制的に0を返すので「断る」しか出せなくなる。名前あり客・配達員は塞ぐ）。
	# 仕込み3段階化：PREP_TIER中は段階ボタン以外で抜けさせない（_is_in_marketと同じ理由）。
	# F3 SaleRule（DESIGN.md 10.3.1）：具・味のどちらかが欠けた椀も同じ扱いで塞ぐ
	# （モブは_mob_achievable_servings()側で達成可能0に落とすので、ここでは無視する）。
	_btn_complete_input.disabled = _pot_mode or _pending_shortage_ev != null \
			or _is_in_market() or _is_in_prep_tier() or _is_in_story_choice() or _phone_mode or _pending_group_choice \
			or (_is_short_in_adjust() and not _is_current_mob_order()) \
			or (_is_strength_zero_in_adjust() and not _is_current_mob_order()) \
			or (_is_bowl_unsellable_in_adjust() and not _is_current_mob_order())
	if _btn_skip_read != null:
		_btn_skip_read.disabled = not _can_skip_step()
	_btn_close.disabled = not _can_close_now() or _phone_mode
	_btn_next_phase.disabled = _phone_mode
	_btn_retry.disabled = GameState.phase != GameState.Phase.GAME_OVER \
			or GameState.morning_snapshots.is_empty() or _phone_mode
	_btn_continue.disabled = _pending_continue.is_empty() or _phone_mode
	_refresh_result_row()
	# スマホ自体は、開いている間だけ無効化する（隠さない。押せないボタンとして残す）。
	_btn_phone.disabled = _phone_mode

	# スマホは3つ目の入れ子モード（鍋・市場と同じくEventRunnerには触れない）。他のどの
	# モードよりも最優先で判定し、真なら通常のADJUST/鍋/市場ボタンの代わりにタブ＋
	# [閉じる]を出して return する（_pot_mode/_market_shopの値はそのまま裏で保持される）。
	if _phone_mode:
		var tabs := [["recipe", "レシピ"], ["news", "ニュース"], ["sns", "SNS"], ["log", "ログ"]]
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

	_add_recipe_save_buttons()
	_add_fund_buttons()

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

	if cur.get("type", "") == "CHOICE":
		for option in cur.get("options", []):
			_add_pot_button(str(option.get("label", "")), false,
				_on_story_choice_pressed.bind(str(cur.get("choice_id", "")), str(option.get("id", ""))))
		return

	if cur.get("type", "") == "MARKET":
		if _market_shop != "":
			for good in _shop_goods(_market_shop):
				var gid: String = str(good.get("id", ""))
				var price: int = int(good.get("price", 0))
				# F4：個数・単価を表示する（DESIGN.md 10.4「豆腐 3個24／単価8／在庫2」）。
				# dashiのようにcountを持たない商品は従来どおり価格のみ表示する。
				var label: String = str(good.get("label", gid))
				var btn_label: String
				if good.has("count"):
					var count: int = int(good.get("count", 1))
					var unit_price: int = int(price / count) if count > 0 else price
					btn_label = "%s（-%d・%d個入り・単価%d）" % [label, price, count, unit_price]
				else:
					btn_label = "%s（-%d）" % [label, price]
				# 調味料の行と具材の行に分ける（ADJUSTと同じ2行。行の決め方は_shop_good_row）。
				_add_pot_button(btn_label,
					GameState.money < price, _on_shop_item_selected.bind(_market_shop, gid),
					_shop_good_row(good))
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
	# [客を断る]（F3・DESIGN.md 10.3.6）：名前あり客・配達員だけに出す。達成可能かどうかを
	# 問わずいつでも押せる（常に有効）。モブはこのADJUST具材ループにも来る（[入力完了]を
	# 押すまでは通常のADJUSTと同じ画面のため）が、モブには既に無条件の「注文を断る」が
	# [入力完了]の後に出るので、二重に出さないようここで除外する。
	if not _is_current_mob_order():
		_add_pot_button("客を断る", false, _on_customer_decline_pressed)
	# [聞き直す]（仮ボタン。4-4b-2・DESIGN.md 10.5.2）：名前あり客のADJUST中だけ。モブと、
	# 配達員の3杯専用列には出さない（4-4aで動かさないと決めた列に触れない）。
	if _adjust_customer_id() != "":
		_add_pot_button("聞き直す", false, _on_reask_pressed)
	_add_recipe_adjust_buttons()


## --- 修繕基金（4-9②。RepairFund。仮UI。本番UIはフェーズ6） ---

## 積み立て行を出す時点：機能オン・CLOSE の語りを読み終えた後（runner が DONE）・スマホを開いていない間。
## [次のPhase]のゲートは変えない（押さなければ「積まない」）。CLOSE の close_events（TEXT列）には足さない。
func _fund_row_visible() -> bool:
	return RepairFund.enabled() and GameState.phase == GameState.Phase.CLOSE and flow.runner != null \
			and flow.is_runner_done() and not _phone_mode


## 刻みごとの「修繕基金に積む +N」ボタン。安全上限・最終段階までの残りを超える額は無効。
## 最終段階（完了）に届いていれば出さない。
func _add_fund_buttons() -> void:
	if not _fund_row_visible() or RepairFund.complete():
		return
	# 積む先の選択（切り替えボタン。選んだ対象に「▶」）。修繕済み・未解放の対象は選べない。
	var selected := _fund_selected()
	for t in RepairFund.targets():
		var s := RepairFund.target_state(t["id"])
		var text := "積む先：%s%s %d/%d" % ["▶" if t["id"] == selected else "", s["label"], s["paid"], s["price"]]
		if s["repaired"]:
			text += " 修繕済み"
		elif s["locked"]:
			text += "（未解放）"
		_add_pot_button(text, s["repaired"] or s["locked"], _on_fund_target_selected.bind(t["id"]))
	for step in RepairFund.steps():
		_add_pot_button("修繕基金に積む +%d" % step, not RepairFund.can_contribute(selected, step),
			_on_fund_contribute_pressed.bind(step))


## いま積む先の対象のid：選んだ対象（未修繕で解放済み）、無効なら最初の未修繕の対象。
func _fund_selected() -> String:
	if _fund_target != "" and not RepairFund.target(_fund_target).is_empty() and not RepairFund.is_repaired(_fund_target) \
			and RepairFund.unlocked(_fund_target):
		return _fund_target
	return RepairFund.first_open_target()


## 積む先を切り替える（実行時のみ。保存しない）。修繕済み・未解放・存在しない対象は選べない。
func _on_fund_target_selected(target_id: String) -> void:
	if _fund_row_visible() and not RepairFund.target(target_id).is_empty() and not RepairFund.is_repaired(target_id) \
			and RepairFund.unlocked(target_id):
		_fund_target = target_id
	_refresh()


## 積む。段階が上がったら、label を使った一行を覚えて CLOSE の間だけ表示する。
## ゲームオーバーにはならない（RepairFund.contribute は払えるときだけ払う）。
func _on_fund_contribute_pressed(amount: int) -> void:
	if not _fund_row_visible():
		return
	var before := RepairFund.repaired_ids()
	if RepairFund.contribute(_fund_selected(), amount):
		var message := RepairFund.repaired_message(before, RepairFund.repaired_ids())
		if message != "":
			_fund_notice = message
	_refresh()


## CLOSE の積み立て行の状態表示（runner のラベルの末尾）。累計・段階・次の段階まで・今日積める上限・
## 段階が上がった一行。表示の条件に合わなければ空文字。
func _format_fund() -> String:
	if not _fund_row_visible():
		return ""
	var lines := PackedStringArray(["", "── 修繕基金（任意・返金なし）──"])
	lines.append(RepairFund.progress_text())
	if RepairFund.complete():
		lines.append("完了")
	else:
		lines.append("今夜積んだ額: %d／%d" % [RepairFund.paid_tonight(), RepairFund.nightly_max()])
		var selected := _fund_selected()
		lines.append("積む先: %s" % str(RepairFund.target(selected).get("label", "なし")))
		lines.append("今日積める上限: %d" % RepairFund.max_contribution(selected))
		# 安全上限の根拠（仮文面）：翌日に全客へ椀を出せるだけの仕込みと材料費を残す。
		var reserve := RepairFund.next_day_reserve()
		if int(reserve["total"]) > 0:
			lines.append("（明日の仕入れ分を残す：運営費%d＋請求%d＋仕込み%d＋材料費%d＝%d。見込み%d杯）" % [
				reserve["operating"], reserve["bills"], reserve["prep"], reserve["materials"], reserve["total"],
				reserve["expected_cups"]])
	if _fund_notice != "":
		lines.append(_fund_notice)
	return "\n".join(lines)


## --- 会話ログ（4-7②。TalkLog。状態を読むだけで、ゲームの数値・乱数には触れない） ---

## いま見えているイベントを、まだ記録していなければ会話ログへ1行足す。_refresh の末尾から呼ぶ＝
## どの操作（ハンドラ直呼びを含む）でも、新しく current になった行（index 0 を含む）が漏れない。
## 同じ位置・同じ本文は1回だけ（_logged_positions）。REACT は判定後に決まる反応文が空でなくなってから、
## _current_reaction_text() が読む（reaction_variant は判定時に固定済みの値で、ここでは抽選しない）。
func _record_visible_event() -> void:
	if flow.runner == null:
		return
	var ev = flow.runner.current()
	if not (ev is Dictionary):
		return
	var kind := "narration"
	var speaker := ""
	var text := str(ev.get("text", ""))
	match str(ev.get("type", "")):
		"GREET":
			kind = "talk"
			speaker = _log_speaker(str(ev.get("customer", "")))
		"SERVE":
			kind = "serve"
		"REACT":
			kind = "reaction"
			speaker = _log_speaker(str(ev.get("customer", "")))
			text = _current_reaction_text()
		"TEXT":
			if str(ev.get("part", "")) == "news":
				kind = "news"
	if text == "":
		_last_shown_unread = false   # 本文の無いイベント（効果のみ・入力待ち・反応なしのREACT）は未読の行ではない
		return
	var slot_index := -1
	var customer_index := -1
	if _open != null:
		slot_index = _open.slot_index
		customer_index = _open.index
	var key := "%d|%d|%d|%d|%d|%s" % [GameState.day_count, GameState.phase, slot_index, customer_index,
		flow.runner.index, text]
	if _logged_positions.has(key):
		return
	_logged_positions[key] = true
	TalkLog.add(GameState.day_count, kind, speaker, text)
	# 既読（ReadState）：見えた行を既読にする。それまで未読だったかをスキップの停止条件として覚える。
	var read_key := ReadState.line_key(kind, speaker, str(ev.get("part", "")), text)
	_last_shown_unread = not ReadState.is_read(read_key)
	ReadState.mark(read_key)


## --- 既読スキップ（4-7③。ReadState。仮UI） ---

## スキップの1歩を進められるか：[次のEvent]が押せて、再生中（入力待ちでない）で、その客・そのフェーズの
## 最後のイベントではない（客やフェーズの切り替わりをまたぐ前で止まる）。
func _can_skip_step() -> bool:
	if flow.runner == null or _btn_next_event.disabled or flow.runner.status != EventRunner.Status.PLAYING:
		return false
	if GameState.phase == GameState.Phase.GAME_OVER or GameState.phase == GameState.Phase.RESULT:
		return false
	return flow.runner.index < flow.runner.events.size() - 1


## [既読スキップ]：[次のEvent]を、止まる条件に達するまで繰り返す。**効果の適用は [次のEvent] と同一の
## 経路**（_on_next_event_pressed）を1イベントにつき1回だけ通す＝会計・来店記録・事実・評判は1回だけ
## 適用される（別の経路は作らない）。止まる条件：入力待ち（ADJUST・CHOICE・MARKET・PREP_TIER・WAIT_INPUT
## など。選択は決して飛ばさない）／直前に見えた行が未読（その行で止まる）／客・フェーズの切り替わり／
## 鍋不足の保留など[次のEvent]が押せない状態／SKIP_READ_LIMIT 回。進めたイベント数を返す。
func _on_skip_read_pressed() -> int:
	var steps := 0
	var start_runner = flow.runner
	var start_phase: int = GameState.phase
	while steps < SKIP_READ_LIMIT and _can_skip_step():
		_on_next_event_pressed()
		steps += 1
		if _last_shown_unread or flow.runner != start_runner or GameState.phase != start_phase:
			break
	return steps


## ログの話し手（表示名。モブは種類の名前）。
func _log_speaker(customer_id: String) -> String:
	if customer_id == "":
		return ""
	if Day1Events.is_mob_customer(customer_id):
		var inst: Dictionary = GameState.today_plan.get("mob_instances", {}).get(customer_id, {})
		return Day1Events.mob_display_name(str(inst.get("type", "")))
	return ScheduleData.customer_display_name(customer_id)


## --- レシピ保存と「いつもの」（4-7①。DESIGN.md 10.4。仮UI。本番UIはフェーズ6） ---

## ADJUST 中の名前あり客（モブの団体注文は対象外）の客id。それ以外は空文字。
func _recipe_adjust_customer() -> String:
	if _open == null or flow.runner == null or GameState.phase != GameState.Phase.OPEN \
			or flow.runner.status != EventRunner.Status.WAITING_INPUT or _phone_mode or _pot_mode \
			or _pending_group_choice or _pending_shortage_ev != null:
		return ""
	var cur = flow.runner.current()
	if not (cur is Dictionary) or str(cur.get("type", "")) != "ADJUST":
		return ""
	var customer_id := str(cur.get("customer", ""))
	if not CustomerMemory.is_recordable(customer_id) or _is_current_mob_order():
		return ""
	return customer_id


## ADJUST 中のボタン：「いつもの」（その客の直近の料理）と保存レシピ。椀が空のときだけ出す。
## 前回の評価は出さない（今回の注文に合うかの予測も出さない。注文カードが唯一の手がかり）。
## 在庫が足りない具材（新鮮な在庫のみ）はラベルに出して無効にする。
func _add_recipe_adjust_buttons() -> void:
	var customer_id := _recipe_adjust_customer()
	if customer_id == "" or not (_open.current_bowl.get("additions", []) as Array).is_empty():
		return
	var servings := _current_servings()
	var usual := RecipeBook.usual_for(customer_id)
	if not usual.is_empty():
		_add_recipe_button("いつもの（%s）" % RecipeBook.ingredient_text(usual), usual, servings)
	for recipe in GameState.saved_recipes:
		_add_recipe_button("%s（%s）" % [str(recipe["name"]), RecipeBook.ingredient_text(recipe["ingredients"])],
			recipe["ingredients"], servings)


func _add_recipe_button(label: String, ingredients: Array, servings: int) -> void:
	var missing := RecipeBook.shortage(ingredients, servings)
	var text := label
	if not missing.is_empty():
		var names_text := PackedStringArray()
		for id in missing:
			names_text.append(Ingredients.name_for(str(id)))
		text += " 足りない：%s" % "・".join(names_text)
	_add_pot_button(text, not RecipeBook.can_apply(ingredients, servings),
		_on_recipe_apply_pressed.bind(ingredients.duplicate()), _recipe_row)


## レシピ／「いつもの」のボタン。**具材ボタンを順に押したのと同じ処理**（_on_ingredient_selected）で
## 1つずつ椀に足す＝在庫・鮮度の確認と消費は省略しない。全部出せると確かめてから適用する
## （途中で止まって一部だけ入る状態を作らない）。傷んだ側は自動では使わない。椀が空のときだけ。
func _on_recipe_apply_pressed(ingredients: Array) -> void:
	var customer_id := _recipe_adjust_customer()
	if customer_id == "" or not (_open.current_bowl.get("additions", []) as Array).is_empty():
		return
	if not RecipeBook.can_apply(ingredients, _current_servings()):
		return
	for id in ingredients:
		_on_ingredient_selected(str(id), false)


## 今、今作った椀をレシピに保存できるか：OPEN で、名前あり客の判定済みの椀（提供後。複数杯の各杯を含む）
## が残っていて、追加が1つ以上ある間。**その客の最後の行まで**押せる（次の杯の椀・次の客で消える）。
func _can_save_recipe_now() -> bool:
	if _open == null or flow.runner == null or GameState.phase != GameState.Phase.OPEN or _phone_mode:
		return false
	var customer = _open.current_customer()
	if customer == null or not CustomerMemory.is_recordable(str(customer)):
		return false
	var bowl: Dictionary = _open.current_bowl
	return str(bowl.get("result", "")) != "" and not (bowl.get("additions", []) as Array).is_empty()


## 提供後の保存ボタン（段階：[レシピを保存] → 枠 → 名前）。名前は10.4.1の候補（椀のタグを含むものを先頭）。
func _add_recipe_save_buttons() -> void:
	if not _can_save_recipe_now():
		_recipe_save_stage = ""
		return
	var additions: Array = _open.current_bowl["additions"]
	match _recipe_save_stage:
		"slot":
			for i in range(RecipeBook.slot_count()):
				var label := "枠%d：空き" % (i + 1)
				if i < GameState.saved_recipes.size():
					label = "枠%d：%s（上書き）" % [i + 1, str(GameState.saved_recipes[i]["name"])]
				_add_pot_button(label, i > GameState.saved_recipes.size(),
					_on_recipe_slot_selected.bind(i), _recipe_row)
			_add_pot_button("やめる", false, _on_recipe_save_cancel_pressed, _recipe_row)
		"name":
			for item in RecipeBook.names_ordered(_open.bowl_addition_tags()):
				_add_pot_button(str(item["name"]), false, _on_recipe_name_selected.bind(str(item["name"])), _recipe_row)
			_add_pot_button("やめる", false, _on_recipe_save_cancel_pressed, _recipe_row)
		_:
			_add_pot_button("レシピを保存（%s）" % RecipeBook.ingredient_text(additions), false,
				_on_recipe_save_pressed, _recipe_row)


func _on_recipe_save_pressed() -> void:
	if _can_save_recipe_now():
		_recipe_save_stage = "slot"
	_refresh()


func _on_recipe_slot_selected(slot: int) -> void:
	if _can_save_recipe_now() and slot >= 0 and slot < RecipeBook.slot_count() and slot <= GameState.saved_recipes.size():
		_recipe_save_slot = slot
		_recipe_save_stage = "name"
	_refresh()


func _on_recipe_name_selected(recipe_name: String) -> void:
	if _can_save_recipe_now() and _recipe_save_stage == "name":
		RecipeBook.save(_recipe_save_slot, recipe_name, _open.current_bowl["additions"])
	_recipe_save_stage = ""
	_refresh()


func _on_recipe_save_cancel_pressed() -> void:
	_recipe_save_stage = ""
	_refresh()


## スマホのレシピタブ：保存レシピ（枠ごとの名前・タグ・具材）と、客ごとの「いつもの」。
func _format_recipe_tab() -> String:
	var lines := PackedStringArray(["◆保存レシピ（%d/%d枠）◆" % [GameState.saved_recipes.size(), RecipeBook.slot_count()]])
	for i in range(RecipeBook.slot_count()):
		if i < GameState.saved_recipes.size():
			var recipe: Dictionary = GameState.saved_recipes[i]
			lines.append("枠%d：%s　%s　具材：%s" % [i + 1, str(recipe["name"]),
				"/".join(PackedStringArray(RecipeBook.tags_of(recipe["ingredients"]))),
				RecipeBook.ingredient_text(recipe["ingredients"])])
		else:
			lines.append("枠%d：（空き）" % (i + 1))
	lines.append("◆いつもの（客ごとの直近の料理）◆")
	var any := false
	for customer_id in GameState.customer_memory:
		var usual := RecipeBook.usual_for(str(customer_id))
		if not usual.is_empty():
			any = true
			lines.append("%s：%s" % [ScheduleData.customer_display_name(str(customer_id)), RecipeBook.ingredient_text(usual)])
	if not any:
		lines.append("まだありません")
	return "\n".join(lines)


## 動的なボタンを1つ並べる（鍋モード・市場の両方で使う汎用ヘルパー）。rowを省略
## （null）すると、従来どおり_options_row（下の行）へ入れる。
func _add_pot_button(label: String, is_disabled: bool, handler: Callable,
		row: HBoxContainer = null) -> void:
	var btn := Button.new()
	btn.text = label
	btn.disabled = is_disabled
	btn.pressed.connect(handler)
	if row == null:
		row = _options_row
	row.add_child(btn)


## 市場の店の商品を置く行を決める（ADJUSTの調味料の行／具材の行と同じ2行）。
## 判定は既存のIngredients.is_topping()/is_flavor()だけ（新しい分類基準は作らない）：
##   - 具材（具の軸のタグを持つ）          → _options_row（具材の行）。ADJUSTと同じく具材を優先
##   - 調味料（味の軸のタグを持つ）        → _seasoning_row（調味料の行）
##   - itemを持たない商品のうちdashi（濃縮だし）→ _seasoning_row。在庫には入らない資源だが、
##     鍋の濃さ（味の強さ）を上げる素材なので調味料の行に置く（肉卸の具材の行は具材だけにする）
##   - それ以外（どちらにも当たらない）    → _options_row
func _shop_good_row(good: Dictionary) -> HBoxContainer:
	var item := str(good.get("item", ""))
	if item == "":
		return _seasoning_row if str(good.get("id", "")) == "dashi" else _options_row
	if Ingredients.is_topping(item):
		return _options_row
	if Ingredients.is_flavor(item):
		return _seasoning_row
	return _options_row


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
	#   budget     … F4予算表示（DESIGN.md 10.4）「残金／確保／使える」。確保は
	#                Ledger.pending_bills_today()（旧pending_bills_today。実際の天引きは
	#                WAKE・チンピラのPAY等で既に済んでいる「まだ物語上のけじめが付いて
	#                いない金額」）。使える＝残金−確保。常時表示（0でも行は消さない）
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
	var state_lines := PackedStringArray([
		"── GameState（日をまたいで残る事実）──",
		"day_count(日数): %d" % GameState.day_count,
		"money(所持金): %d" % GameState.money,
		"budget(残金/確保/使える): %d / %d / %d" % [
			GameState.money, Ledger.pending_bills_today(), Ledger.usable_cash()],
		"reputation(評判): %d" % GameState.reputation,
		"inventory(在庫数): %d 個" % _inventory_total(),
		"inventory_detail(内訳): %s" % _format_inventory_detail(),
		"rumors(情報数): %d 件" % GameState.rumors.size(),
		"phase(現在フェーズ): %s (%d)" % [phase_name, GameState.phase],
		"soup(今日の鍋): %s" % soup_text,
		"pot(鍋の資源): 水%d回 / 濃縮だし%d回分" % [water_doses, GameState.dashi_units],
		"served(接客数/杯数): %d / %d" % [_served_count(), _served_servings()],
		"discarded(廃棄数): %d 件" % _discarded_count(),
		"favorite_known(好物を知っている客): %s" % (
			"・".join(PackedStringArray(GameState.known_favorite_ids())) if not GameState.known_favorite_ids().is_empty() else "(なし)"),
	])
	# 修繕基金（4-9）：累計が1以上のときだけ（積まない間は従来と同じ文面）。budget の次の行。
	if RepairFund.enabled() and RepairFund.paid() > 0:
		state_lines.insert(4, "fund(修繕基金): 累計%d／修繕済み: %s" % [RepairFund.paid(),
			RepairFund.repaired_labels() if RepairFund.repaired_labels() != "" else "なし"])
	return "\n".join(state_lines)


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
			body = News.tab_text(GameState.day_count, _played_events)
		"sns":
			body = _format_tonight_memo()
		"log":
			body = TalkLog.tab_text()
		_:
			body = _format_recipe_tab()
	return "── スマホ ──\n%s" % body


## 予告（②）＋朝の一画面（3-7・DESIGN.md 10.4）：SNSタブの本文。GameState.today_plan
## （WAKEでDayPlanner.build()が1回だけ確定した今夜の並び）を、時間帯ごとの客層メモと、
## 総杯数・必要な味/具の数・在庫との過不足・使える現金の集計へ整形する。集計そのものは
## Forecastクラス（DebugPanelの外）が行い、ここは文字列に組み立てるだけ。
## 精度（10.4）：Day1（exact）は完全公開（配達員の3杯内訳・モブの人数も）。
## Day2以降（range）は常連の基本注文・既知の好物＋モブの客層（種類の一覧・重複除去。
## 人数・組数は出さない）＋総杯数の幅（需要の中心±幅）。「今日の頼み」は出さない。
## 自動購入はしない（表示のみ）。起床前などtoday_plan["slots"]が空なら旧来の文言を返す。
func _format_tonight_memo() -> String:
	var slots: Array = GameState.today_plan.get("slots", [])
	if slots.is_empty():
		return "SNS：まだ新着はありません"
	var exact: bool = Forecast.mode() == "exact"
	var total := Forecast.total()
	var lines := PackedStringArray(["◆本日の客足予報%s◆" % ("（確定）" if exact else "")])
	if exact:
		lines.append("総杯数: %d杯" % int(total["low"]))
	else:
		lines.append("総杯数: %d〜%d杯" % [int(total["low"]), int(total["high"])])
	for slot in slots:
		var parts := PackedStringArray()
		var mob_types_shown := []   # この枠で既に出したモブの種類（重複除去用）
		for customer_id in slot.get("customers", []):
			var cid := str(customer_id)
			var flavor := Day1Events._customer_flavor(cid)
			if bool(flavor.get("is_mob", false)):
				var inst: Dictionary = GameState.today_plan.get("mob_instances", {}).get(cid, {})
				var type_id := str(inst.get("type", ""))
				var mob_tags: Array = flavor.get("wanted_tags", [])
				var mob_tag_text := "/".join(PackedStringArray(mob_tags)) if not mob_tags.is_empty() else "？"
				var mob_name := Day1Events.mob_display_name(type_id)
				if exact:
					parts.append("%s%d人（%s）" % [mob_name, int(inst.get("count", 0)), mob_tag_text])
				elif not mob_types_shown.has(type_id):
					mob_types_shown.append(type_id)
					parts.append("客層:%s（%s）" % [mob_name, mob_tag_text])
			else:
				var name: String = ScheduleData.customer_display_name(cid)
				var fav_text := ""
				var fav_id := str(flavor.get("favorite", ""))
				if fav_id != "" and GameState.knows_favorite(cid):
					fav_text = "／好物:%s" % Ingredients.name_for(fav_id)
				parts.append("%s（%s%s）" % [name, _format_orders_for_memo(Forecast.orders_of(cid)), fav_text])
		if parts.is_empty():
			continue
		lines.append("・%s：%s" % [str(slot.get("name", "")), "、".join(parts)])
	for plan_case in Forecast.cases():
		var req: Dictionary = plan_case["required"]
		var short := Forecast.shortages(req)
		var short_parts := PackedStringArray()
		for tag in Forecast.TAG_ORDER:
			if short.has(tag):
				short_parts.append("%sあと%d個" % [tag, int(short[tag])])
		lines.append("必要（%s）: %s" % [str(plan_case["label"]), Forecast.format_tags(req)])
		lines.append("　在庫との過不足: %s" % ("不足なし" if short_parts.is_empty() else "・".join(short_parts)))
	lines.append("使える現金: %d円（残金%d／確保%d）" % [
		Ledger.usable_cash(), GameState.money, Ledger.pending_bills_today()])
	return "\n".join(lines)


## 名前あり客の注文を「HOT/POWER」「HOT/POWER×2・MELLOW/GENTLE×1」のように整形する
## （配達員のDay1は3杯が並ぶ）。同じタグ組・同じ並びの注文は杯数をまとめる。
func _format_orders_for_memo(orders: Array) -> String:
	var order_keys := []
	var counts := {}
	for order in orders:
		var tags: Array = order.get("tags", [])
		var key := "/".join(PackedStringArray(tags)) if not tags.is_empty() else "？"
		if not counts.has(key):
			counts[key] = 0
			order_keys.append(key)
		counts[key] = int(counts[key]) + int(order.get("servings", 1))
	if order_keys.size() == 1 and int(counts[order_keys[0]]) == 1:
		return order_keys[0]
	var parts := PackedStringArray()
	for key in order_keys:
		parts.append("%s×%d" % [key, int(counts[key])])
	return "・".join(parts)


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
	return "\n" + "\n".join(lines) + _format_order_card_block() + _format_bowl()


# UI準備Aの橋。テストを移したら削除（本番UIは session.adjust_customer_id() を直接使う）。
func _adjust_customer_id() -> String:
	return session.adjust_customer_id()


## 注文カード（仮表示。本番UIはフェーズ6）：「いつもの：HOT/POWER ／ 今日：MELLOW/GENTLE（持ち帰り）」。
## 今日の頼みが無い客は「いつもの：…」のみ。タグの表記は既存（予告メモ・greet）と同じ「/」区切り。
func _format_order_card(customer_id: String) -> String:
	var card := Day1Events.order_card(customer_id)
	if card.is_empty():
		return ""
	var text := "いつもの：%s" % "/".join(PackedStringArray(card["base"]))
	if not (card["today"] as Array).is_empty():
		text += " ／ 今日：%s" % "/".join(PackedStringArray(card["today"]))
		if str(card["label"]) != "":
			text += "（%s）" % str(card["label"])
	return text


## _format_open()に足す、注文カードと聞き直しの表示（ADJUST中の名前あり客だけ。他は空文字）。
func _format_order_card_block() -> String:
	var customer_id := _adjust_customer_id()
	if customer_id == "":
		return ""
	var block := "\n── 注文カード ──\n%s" % _format_order_card(customer_id)
	if _reask_text != "":
		block += "\n── 聞き直し ──\n%s" % _reask_text
	return block


## [聞き直す]：注文カードと、客の頼みの台詞（場面のorder.reask。無ければ客のgreet）を再表示
## するだけ。料金・評判・評価・来店記録・factsを一切変えない（session の reask_* を書くだけ）。
## 何度押しても同じ。この操作を正解の印にしない（判定・記録は読まない）。
# UI準備Aの橋。テストを移したら削除（本番UIは session.reask() を直接使う）。
func _on_reask_pressed() -> void:
	session.reask()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.current_servings() を直接使う）。
func _current_servings() -> int:
	return session.current_servings()


# UI準備Aの橋。テストを移したら削除（本番UIは session.react_for_now() を直接使う）。
func _react_for_now() -> Dictionary:
	return session.react_for_now()


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
	# F3 減点の事前表示（DESIGN.md 10.3.1・10.3.2）：まだ判定していない椀（result==""）
	# のときだけ、SaleRuleで提供不可なら理由を、提供はできるがJudgeで減点見込みなら
	# その理由を1行足す。判定後（result!=""）は既存のjudge_text側の表示に任せる。
	if result == "":
		var sale_hint := _format_sale_hint()
		if sale_hint != "":
			lines.append(sale_hint)
	# 廃棄回数（0回なら出さない）。椀自体は廃棄のたびに作り直されて消えるので、
	# 「この客で何回作り直したか」は current_bowl とは別に _bowl_discard_count で持つ。
	if _bowl_discard_count > 0:
		lines.append("discard_count(この客での廃棄回数): %d回" % _bowl_discard_count)
	var reaction := _current_reaction_text()
	if reaction != "":
		lines.append("reaction(反応): 【%s】%s" % [result, reaction])
	return "\n" + "\n".join(PackedStringArray(lines))


## F3 減点の事前表示（DESIGN.md 10.3.1・10.3.2・判断が必要な点4）。まだ判定していない
## 椀について、SaleRuleで提供不可なら理由を（優先）、提供はできてもJudgeで濃さ・傷みの
## 減点が見込まれるならその理由を返す。どちらも該当しなければ空文字（_format_bowl()側で
## 行を足さない）。
func _format_sale_hint() -> String:
	if _open == null or not _open.current_bowl.has("customer_id"):
		return ""
	var reasons: Array = SaleRule.check(_open.current_bowl, GameState.soup).get("reasons", [])
	var composition_reasons := PackedStringArray()
	if reasons.has(SaleRule.NO_FLAVOR):
		composition_reasons.append("味付けが入っていません")
	if reasons.has(SaleRule.NO_TOPPING):
		composition_reasons.append("具が入っていません")
	if not composition_reasons.is_empty():
		return "（このままでは提供できません：%s）" % "・".join(composition_reasons)
	var used_spoiled: bool = bool(_open.current_bowl.get("used_spoiled", false))
	var strength := int(GameState.soup.get("strength", 3)) if GameState.soup != null else 3
	var bad_strength: bool = strength == GameState.STRENGTH_MIN or strength == GameState.STRENGTH_MAX
	if bad_strength or used_spoiled:
		var penalty_reasons := PackedStringArray()
		if bad_strength:
			penalty_reasons.append("濃さが%d" % strength)
		if used_spoiled:
			penalty_reasons.append("傷んだ具材を使っています")
		return "（このままだと1段階下がります：%s）" % "・".join(penalty_reasons)
	return ""


# UI準備Aの橋。テストを移したら削除（本番UIは session.current_reaction_text() を直接使う）。
func _current_reaction_text() -> String:
	return session.current_reaction_text()
