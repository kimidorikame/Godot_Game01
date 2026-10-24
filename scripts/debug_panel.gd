extends PanelContainer
## 開発用 State Viewer（DESIGN.md 8章 / 9章 STEP 1・STEP 2）。
##
## GameState と EventRunner.status を画面に映し、デバッグボタンで手叩きする。
## 本番のゲーム画面ではない。絵もシナリオも無し。
## 遊びの進行（FlowController・Eventの受け側・状態）は、UI準備Aで共有部品 PlaySession へ移している最中
## （本番UIと同じ処理を使うため）。PlaySession はこのシーンの子ノードとして持つ（autoload にはしない）。
## このパネルは「表示と結線」だけの役に寄せていく。

# UI準備Aの橋。テストを移したら削除（実体は PlaySession.SKIP_READ_LIMIT）。
const SKIP_READ_LIMIT := PlaySession.SKIP_READ_LIMIT

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
# （評点の表 REPUTATION_SCORE は PlaySession へ移した）

# [鍋を見る] の操作モード中か（DESIGN.md 7.6）。
# EventRunner には一切触れない＝ index も status も動かさない。表示と操作対象を
# 切り替えるだけなので、会話は止まったまま鍋をいじって戻れる。
# UI準備Aの橋。テストを移したら削除（実体は session.pot_open）。
var _pot_mode: bool:
	get:
		return session.pot_open
	set(value):
		session.pot_open = value

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
# UI準備Aの橋。テストを移したら削除（実体は session.pot_water_added）。
var _pot_water_added: bool:
	get:
		return session.pot_water_added
	set(value):
		session.pot_water_added = value

# 鍋モードに入った時点で濃さ0（提供不可）だった場合、濃縮だしを入れるまでの間だけ true。
# _pot_water_added と同じ形（濃さメカニクス三点セット）。_on_pot_pressed() で毎回リセットする。
# UI準備Aの橋。テストを移したら削除（実体は session.pot_dashi_added）。
var _pot_dashi_added: bool:
	get:
		return session.pot_dashi_added
	set(value):
		session.pot_dashi_added = value

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
# UI準備Aの橋。テストを移したら削除（実体は session.debug_mob_count）。
var _debug_mob_count: int:
	get:
		return session.debug_mob_count
	set(value):
		session.debug_mob_count = value

# 前日の営業成績（翌朝のWAKE先頭で一度だけ見せる一言サマリー）。_game_over_reasonと
# 同じ「一度だけ消費するテキスト」の形。_on_day_ending()（day_ending。NEXT_DAY→WAKEの
# 折り返し直前に発火）で組み立て、次にWAKEのrunnerを組むときに読んで空文字へ戻す。
# UI準備Aの橋。テストを移したら削除（実体は session.last_day_summary_text）。
var _last_day_summary_text: String:
	get:
		return session.last_day_summary_text
	set(value):
		session.last_day_summary_text = value

# F7 同じ朝への復元（再挑戦・セーブ読み込み）の直後のWAKEで、保存してあるDayPlanを
# そのまま使うための一度きりの印（_set_runner_for_phase(WAKE)が読んで消費する。
# _game_over_reasonと同じ「一度だけ」パターン。「今日のplanがあれば作らない」判定に
# しないのは、同じ日にWAKEを繰り返し通る既存の経路・テストで引き直しが止まらないため）。
# UI準備Aの橋。テストを移したら削除（実体は session.plan_restored）。
var _plan_restored: bool:
	get:
		return session.plan_restored
	set(value):
		session.plan_restored = value

# F7 1枠セーブ（フェーズ4-1コミット②・DESIGN.md 10.6）。朝の保存ファイル（MorningSave）へ
# 書いてよいか。起動時に有効なセーブがあれば、[続きから]を押すか最初の朝を抜けるまで
# false（起動した瞬間のDay1の朝で上書きして、続きから選べなくなるのを防ぐ）。
# UI準備Aの橋。テストを移したら削除（実体は session.save_armed）。
var _save_armed: bool:
	get:
		return session.save_armed
	set(value):
		session.save_armed = value
# 起動時に読めたセーブの封筒（[続きから]で戻す先）。無い・読めない・使用済みなら空。
# UI準備Aの橋。テストを移したら削除（実体は session.pending_continue）。
var _pending_continue: Dictionary:
	get:
		return session.pending_continue
	set(value):
		session.pending_continue = value

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
# UI準備Aの橋。テストを移したら削除（実体は session.fund_notice）。
var _fund_notice: String:
	get:
		return session.fund_notice
	set(value):
		session.fund_notice = value
# 積む先の対象のid（選択は実行時のみ・保存しない）。空・修繕済み・未解放なら既定（最初の未修繕の対象）を使う。
# UI準備Aの橋。テストを移したら削除（実体は session.fund_target）。
var _fund_target: String:
	get:
		return session.fund_target
	set(value):
		session.fund_target = value
# 会話ログ（4-7②。TalkLog）：すでに記録した位置（日・フェーズ・時間帯・客のindex・イベントのindex・本文）。
# _load_current_customer が同じ客で何度呼ばれても・再描画しても二重に記録しないための印。保存しない。
# UI準備Aの橋。テストを移したら削除（実体は session.logged_positions）。
var _logged_positions: Dictionary:
	get:
		return session.logged_positions
	set(value):
		session.logged_positions = value
# 既読スキップ（4-7③。ReadState）：直近に新しく見えた行が、それまで未読だったか（スキップの停止条件）。
# [既読スキップ]の仮ボタンは _ready でコードから足す（.tscn は変えない）。
# UI準備Aの橋。テストを移したら削除（実体は session.last_shown_unread）。
var _last_shown_unread: bool:
	get:
		return session.last_shown_unread
	set(value):
		session.last_shown_unread = value
var _btn_skip_read: Button
# UI準備Aの橋。テストを移したら削除（実体は session.recipe_save_slot）。
var _recipe_save_slot: int:
	get:
		return session.recipe_save_slot
	set(value):
		session.recipe_save_slot = value
var _recipe_row: HBoxContainer

# 聞き直し（4-4b-2。DESIGN.md 10.5.2）の再表示テキスト。画面側だけの一時表示で、GameState・
# 帳簿・来店記録を一切変えない（何度押しても同じ。保存しない）。客が替わる・保存から戻すと消える。
# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（実体は session.reask_customer_id／reask_lines。表示用の文はここで組む）。
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
	# 表示だけの状態（スマホの開閉・タブ）は、フェーズごとの列を組む直前に捨てる（PlaySession の合図を受ける）。
	session.phase_entering.connect(_on_phase_entering)
	# 起動時の準備（セーブの読み込み・初期在庫・最初のフェーズの列）は PlaySession が行う。
	session.start()

	# 以下は「どのボタン/シグナルが何を呼ぶか」の結線。処理内容は各ハンドラ側にある。
	# （フェーズの遷移・runner の更新・新しい周の合図は PlaySession が受け、changed で知らせる）
	session.changed.connect(_refresh)                  # 遊びの状態が変わった → 描き直す（UI準備A）
	# 日次ログ：NEXT_DAY→WAKEの折り返しで、日次リセットの前に一日分の集計を確定して出す
	# （シグナルは同期発火なので、ここが完了してからFlowController側の日次リセットへ進む）。
	# （日の終わり day_ending は PlaySession が自分で受ける。ここでは結線しない）
	# [次のEvent] = _on_next_event_pressed:
	#   flow.runner_advance() で PLAYING のときだけ index を1つ進める。
	#   WAITING_INPUT / DONE では何もしない（＝WAIT_INPUT で確実に止まる）。
	#   STEP 4: 進んだ先の Event が PAY / ADD_ITEM なら、その効果をここで GameState に反映する。
	_btn_next_event.pressed.connect(session.next_event)
	# [入力完了] = _on_complete_input_pressed:
	#   flow.runner_complete_input() で WAITING_INPUT を PLAYING に戻してから1つ進める。
	#   「入力待ちの解除」専用。[次のEvent] との違い: あちらは止まっている列を動かせないが、
	#   こちらは解除したうえで先へ進める。PLAYING 中に押しても無効。
	#   STEP 4: 進んだ先の Event の効果反映は [次のEvent] と同じ扱い。
	_btn_complete_input.pressed.connect(session.complete_input)
	# [鍋を見る] = 鍋の操作モードに入る（7.6）。EventRunner は進めない。
	#   ADJUST 中（3枠を選んでいる間）は押せない＝調理の途中で鍋をいじらせない。
	_btn_pot.pressed.connect(session.open_pot)
	# [閉店] = 鍋が尽きて選択待ちのときだけ押せる（7.6）。保留中のREACTは適用しない。
	_btn_close.pressed.connect(session.close_shop)
	_btn_next_phase.pressed.connect(session.flow.advance_phase)  # [次のPhase] = 上位フェーズを一方向に1つ進める
	_btn_day_plus.pressed.connect(_on_day_plus_pressed)  # [Day+] = 日数だけ +1（デバッグ用）
	# [所持金 ±50] = 所持金だけ動かす（デバッグ用。クズ野菜ベースやゲームオーバーの確認に使う）。
	_btn_money_minus.pressed.connect(_on_money_debug_pressed.bind(-50))
	_btn_money_plus.pressed.connect(_on_money_debug_pressed.bind(50))
	# [モブ人数] = 今夜のモブ人数を 自動→1→2→3→4→自動… と切り替える（デバッグ用）。
	_btn_mob_debug.pressed.connect(_on_mob_debug_pressed)
	# [同じ朝からやり直す] = ゲームオーバーのときだけ押せる（F7。仮ボタン。本番UIはフェーズ6）。
	_btn_retry.pressed.connect(session.retry)
	# [続きから] = 起動時に読めたセーブの朝へ戻る（仮ボタン。本番UIはフェーズ6）。
	_btn_continue.pressed.connect(session.continue_game)
	# 結果画面の選択肢（4-2）。[終わる]は押せない仮ボタン（フェーズ6）なので結線しない。
	_btn_run_again.pressed.connect(session.run_again)
	_btn_last_morning.pressed.connect(session.last_morning)
	_btn_new_run.pressed.connect(session.new_run)
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


## フェーズごとの列を組む直前：表示だけの状態を捨てる（スマホは鍋・市場と同じくフェーズをまたいで持ち越さない）。
func _on_phase_entering(_phase: int) -> void:
	_phone_mode = false
	_phone_tab = "recipe"


# UI準備Aの橋。テストを移したら削除（本番UIは session.seed_initial_inventory() を直接使う）。
func _seed_initial_inventory() -> void:
	session.seed_initial_inventory()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.set_runner_for_phase() を直接使う）。
func _set_runner_for_phase(phase: int) -> void:
	session.set_runner_for_phase(phase)


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.open_pot() を直接使う）。
func _on_pot_pressed() -> void:
	session.open_pot()


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）。[戻る]＝鍋モードを抜けて、鍋不足で保留中の客がいれば「営業を続ける」。
# 本番UIは鍋タブの切り替え（session.close_pot()）と、「営業を続ける」ボタン（session.resume_after_shortage()）を
# それぞれ直接使う（[戻る]に当たる操作は無い）。
func _on_pot_back_pressed() -> void:
	_pot_mode = false
	session.resume_after_shortage()
	_refresh()


# UI準備Aの橋。テストを移したら削除（本番UIは session.close_shop() を直接使う）。
func _on_close_pressed() -> void:
	session.close_shop()


# UI準備Aの橋。テストを移したら削除（本番UIは session.add_water() を直接使う）。
func _on_add_water_pressed() -> void:
	session.add_water()


# UI準備Aの橋。テストを移したら削除（本番UIは session.add_dashi() を直接使う）。
func _on_add_dashi_pressed() -> void:
	session.add_dashi()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.pot_locked_until_water() を直接使う）。
func _pot_locked_until_water() -> bool:
	return session.pot_locked_until_water()


# UI準備Aの橋。テストを移したら削除（本番UIは session.pot_locked_until_dashi() を直接使う）。
func _pot_locked_until_dashi() -> bool:
	return session.pot_locked_until_dashi()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.group_serve() を直接使う）。
func _on_group_serve_pressed(n: int, ordered: int) -> void:
	session.group_serve(n, ordered)


# UI準備Aの橋。テストを移したら削除（本番UIは session.group_decline() を直接使う）。
func _on_group_decline_pressed(ordered: int) -> void:
	session.group_decline(ordered)


# UI準備Aの橋。テストを移したら削除（本番UIは session.group_retry() を直接使う）。
func _on_group_retry_pressed(achievable: int, ordered: int) -> void:
	session.group_retry(achievable, ordered)


# UI準備Aの橋。テストを移したら削除（本番UIは session._serve_mob_partial() を直接使う）。
func _serve_mob_partial(ev: Dictionary, actual: int, ordered: int) -> void:
	session._serve_mob_partial(ev, actual, ordered)


# UI準備Aの橋。テストを移したら削除（本番UIは session._serve_mob_recipe_and_retry() を直接使う）。
func _serve_mob_recipe_and_retry(ev: Dictionary, actual: int, remaining: int) -> void:
	session._serve_mob_recipe_and_retry(ev, actual, remaining)


# UI準備Aの橋。テストを移したら削除（本番UIは session._serve_customer() を直接使う）。
func _serve_customer(ev: Dictionary) -> void:
	session._serve_customer(ev)


# UI準備Aの橋。テストを移したら削除（本番UIは session.decline_customer() を直接使う）。
func _on_customer_decline_pressed() -> void:
	session.decline_customer()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.retry_from_morning() を直接使う）。
func retry_from_morning(day: int = -1) -> bool:
	return session.retry_from_morning(day)


# UI準備Aの橋。テストを移したら削除（本番UIは session.reset_transient_state() を直接使う）。
func _reset_transient_panel_state() -> void:
	session.reset_transient_state()


# UI準備Aの橋。テストを移したら削除（本番UIは session.retry() を直接使う）。
func _on_retry_pressed() -> void:
	session.retry()


# UI準備Aの橋。テストを移したら削除（本番UIは session.run_again() を直接使う）。
func _on_run_again_pressed() -> void:
	session.run_again()


# UI準備Aの橋。テストを移したら削除（本番UIは session.last_morning() を直接使う）。
func _on_last_morning_pressed() -> void:
	session.last_morning()


# UI準備Aの橋。テストを移したら削除（本番UIは session.new_run() を直接使う）。
func _on_new_run_pressed() -> void:
	session.new_run()


# UI準備Aの橋。テストを移したら削除（本番UIは session.continue_game() を直接使う）。
func _on_continue_pressed() -> void:
	session.continue_game()


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


# UI準備Aの橋。テストを移したら削除（本番UIは session.on_day_ending() を直接使う）。
func _on_day_ending() -> void:
	session.on_day_ending()


# UI準備Aの橋。テストを移したら削除（本番UIは session.format_day_summary() を直接使う）。
func _format_day_summary(log_entry: Dictionary) -> String:
	return session.format_day_summary(log_entry)


# UI準備Aの橋。テストを移したら削除（本番UIは session._format_spend_by_category() を直接使う）。
func _format_spend_by_category(spend: Dictionary) -> String:
	return session._format_spend_by_category(spend)


# UI準備Aの橋。テストを移したら削除（本番UIは session.spoiled_value() を直接使う）。
func _spoiled_value(spoiled_items: Dictionary) -> int:
	return session.spoiled_value(spoiled_items)


# UI準備Aの橋。テストを移したら削除（本番UIは session.quality_score() を直接使う）。
func _quality_score(counts: Dictionary, judged_planned: int) -> float:
	return session.quality_score(counts, judged_planned)


func _on_day_plus_pressed() -> void:
	GameState.advance_day()
	_refresh()


## デバッグ用：モブ人数の強制指定を 自動→1→2→3→4→自動 と回す。次に OPEN に入るときから効く。
func _on_mob_debug_pressed() -> void:
	session.debug_mob_count = session.debug_mob_count + 1 if session.debug_mob_count < 4 else -1
	if session.debug_mob_count == 0:
		session.debug_mob_count = 1
	_btn_mob_debug.text = "モブ人数: %s" % ("自動" if session.debug_mob_count < 0 else str(session.debug_mob_count))
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
	session.record_visible_event()


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
	# 押せるかの問いは PlaySession が持つ（スマホを開いている間の無効化は表示の状態なので、ここで足す）。
	_btn_pot.disabled = not session.can_touch_pot() or _phone_mode
	_btn_next_event.disabled = not session.can_next_event() or _phone_mode
	# 不足のADJUSTでは提供（[入力完了]）できない。補充するか、閉店するか廃棄以外を選ぶ（モブは塞がない。
	# 条件の詳細は session.can_complete_input）。
	_btn_complete_input.disabled = not session.can_complete_input() or _phone_mode
	if _btn_skip_read != null:
		_btn_skip_read.disabled = not _can_skip_step()
	_btn_close.disabled = not session.can_close_now() or _phone_mode
	_btn_next_phase.disabled = _phone_mode
	_btn_retry.disabled = GameState.phase != GameState.Phase.GAME_OVER \
			or GameState.morning_snapshots.is_empty() or _phone_mode
	_btn_continue.disabled = session.pending_continue.is_empty() or _phone_mode
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

	if session.pot_open:
		var locked_water := session.pot_locked_until_water()
		var locked_dashi := session.pot_locked_until_dashi()
		_add_pot_button("水を足す（残量+%d 濃さ-%d）" % [GameState.WATER_SERVINGS, GameState.WATER_STRENGTH_DELTA],
			not GameState.can_add_water(), session.add_water)
		# だしだけ入れても煮出す水が無く意味をなさない（旧ベースと同じ理由）ので、
		# 水待ちロック中はだしボタンも塞ぐ。
		_add_pot_button("だしを足す（濃さ+%d）" % GameState.DASHI_STRENGTH_DELTA,
			not GameState.can_add_dashi() or locked_water, session.add_dashi)
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
	if session.pending_group_choice:
		var group: Dictionary = session.mob_group_choice()
		var ordered: int = int(group["ordered"])
		var achievable: int = int(group["achievable"])
		if group["can_serve"]:
			var serve_label := "%d人分を提供（注文%d人）" if group["recipe_number"] == 1 \
				else "%d人分を提供（残り%d人）"
			_add_pot_button(serve_label % [achievable, ordered], false,
				session.group_serve.bind(achievable, ordered))
		_add_pot_button("注文を断る", false, session.group_decline.bind(ordered))
		if group["can_retry"]:
			_add_pot_button("残り%d人に別の具材で挑戦する" % int(group["remaining"]), false,
				session.group_retry.bind(achievable, ordered))
		return

	_add_recipe_save_buttons()
	_add_fund_buttons()

	var r: EventRunner = session.flow.runner
	if r == null or r.status != EventRunner.Status.WAITING_INPUT:
		return
	var cur = r.current()
	if not (cur is Dictionary) or not cur.has("options"):
		return

	if cur.get("type", "") == "PREP_TIER":
		for tier in cur.get("options", []):
			var price: int = int(tier.get("price", 0))
			_add_pot_button("%s（-%d・%d杯）" % [str(tier.get("label", "")), price, int(tier.get("servings", 0))],
				GameState.money < price, session.choose_prep_tier.bind(str(tier.get("id", ""))))
		return

	if cur.get("type", "") == "CHOICE":
		for option in cur.get("options", []):
			_add_pot_button(str(option.get("label", "")), false,
				session.choose_story_option.bind(str(cur.get("choice_id", "")), str(option.get("id", ""))))
		return

	if cur.get("type", "") == "MARKET":
		if session.market_shop != "":
			for good in PlaySession.shop_goods(session.market_shop):
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
					GameState.money < price, session.buy_item.bind(session.market_shop, gid),
					_shop_good_row(good))
			_add_pot_button("市場に戻る", false, session.leave_shop)
			return
		for option in cur.get("options", []):
			var id: String = str(option.get("id", ""))
			var disabled: bool = not bool(option.get("enabled", true))
			_add_pot_button(str(option.get("label", id)), disabled,
				session.select_stall.bind(id))
		_add_pot_button("市場を出る", false, session.exit_market)
		return

	var at_cap := false
	if session.open != null:
		at_cap = session.open.current_bowl.get("additions", []).size() >= OpenController.MAX_ADDITIONS
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
		btn.pressed.connect(session.select_ingredient.bind(opt_id, opt_damaged))
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
	_add_pot_button("廃棄する", not session.can_discard(), session.discard_bowl)
	# [客を断る]（F3・DESIGN.md 10.3.6）：名前あり客・配達員だけに出す。達成可能かどうかを
	# 問わずいつでも押せる（常に有効）。モブはこのADJUST具材ループにも来る（[入力完了]を
	# 押すまでは通常のADJUSTと同じ画面のため）が、モブには既に無条件の「注文を断る」が
	# [入力完了]の後に出るので、二重に出さないようここで除外する。
	if session.can_decline():
		_add_pot_button("客を断る", false, session.decline_customer)
	# [聞き直す]（仮ボタン。4-4b-2・DESIGN.md 10.5.2）：名前あり客のADJUST中だけ。モブと、
	# 配達員の3杯専用列には出さない（4-4aで動かさないと決めた列に触れない）。
	if session.can_reask():
		_add_pot_button("聞き直す", false, session.reask)
	_add_recipe_adjust_buttons()


## --- 修繕基金（4-9②。RepairFund。仮UI。本番UIはフェーズ6） ---

## 積み立て行を出す時点：機能オン・CLOSE の語りを読み終えた後（runner が DONE）・スマホを開いていない間。
## [次のPhase]のゲートは変えない（押さなければ「積まない」）。CLOSE の close_events（TEXT列）には足さない。
func _fund_row_visible() -> bool:
	return session.fund_row_available() and not _phone_mode


## 刻みごとの「修繕基金に積む +N」ボタン。安全上限・最終段階までの残りを超える額は無効。
## 最終段階（完了）に届いていれば出さない。
func _add_fund_buttons() -> void:
	if not _fund_row_visible() or RepairFund.complete():
		return
	# 積む先の選択（切り替えボタン。選んだ対象に「▶」）。修繕済み・未解放の対象は選べない。
	var selected := session.fund_selected()
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


# UI準備Aの橋。テストを移したら削除（本番UIは session.fund_selected() を直接使う）。
func _fund_selected() -> String:
	return session.fund_selected()


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.select_fund_target() を直接使う）。
# スマホを開いている間は表示の状態なので、ここで足す（積み立て行は出ていない＝選べない）。
func _on_fund_target_selected(target_id: String) -> void:
	if _phone_mode:
		_refresh()
		return
	session.select_fund_target(target_id)


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.contribute_fund() を直接使う）。
func _on_fund_contribute_pressed(amount: int) -> void:
	if _phone_mode:
		return
	session.contribute_fund(amount)


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
		var selected := session.fund_selected()
		lines.append("積む先: %s" % str(RepairFund.target(selected).get("label", "なし")))
		lines.append("今日積める上限: %d" % RepairFund.max_contribution(selected))
		# 安全上限の根拠（仮文面）：翌日に全客へ椀を出せるだけの仕込みと材料費を残す。
		var reserve := RepairFund.next_day_reserve()
		if int(reserve["total"]) > 0:
			lines.append("（明日の仕入れ分を残す：運営費%d＋請求%d＋仕込み%d＋材料費%d＝%d。見込み%d杯）" % [
				reserve["operating"], reserve["bills"], reserve["prep"], reserve["materials"], reserve["total"],
				reserve["expected_cups"]])
	if session.fund_notice != "":
		lines.append(session.fund_notice)
	return "\n".join(lines)


## --- 会話ログ（4-7②。TalkLog。状態を読むだけで、ゲームの数値・乱数には触れない） ---

# UI準備Aの橋。テストを移したら削除（本番UIは session.record_visible_event() を直接使う）。
func _record_visible_event() -> void:
	session.record_visible_event()


## --- 既読スキップ（4-7③。ReadState。仮UI） ---

# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.can_skip_step() を直接使う）。
# スマホを開いている間は[次のEvent]が押せない（表示の状態）ので、ここで足す。
func _can_skip_step() -> bool:
	return not _phone_mode and session.can_skip_step()


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.skip_read() を直接使う）。
func _on_skip_read_pressed() -> int:
	if _phone_mode:
		return 0
	return session.skip_read()


## --- レシピ保存と「いつもの」（4-7①。DESIGN.md 10.4。仮UI。本番UIはフェーズ6） ---

# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.recipe_adjust_customer() を直接使う）。
# スマホを開いている間は出さない（表示の状態）ので、ここで足す。
func _recipe_adjust_customer() -> String:
	if _phone_mode:
		return ""
	return session.recipe_adjust_customer()


## ADJUST 中のボタン：「いつもの」（その客の直近の料理）と保存レシピ。椀が空のときだけ出す。
## 前回の評価は出さない（今回の注文に合うかの予測も出さない。注文カードが唯一の手がかり）。
## 在庫が足りない具材（新鮮な在庫のみ）はラベルに出して無効にする。
func _add_recipe_adjust_buttons() -> void:
	var customer_id := _recipe_adjust_customer()
	if customer_id == "" or not (session.open.current_bowl.get("additions", []) as Array).is_empty():
		return
	var servings := session.current_servings()
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


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.apply_recipe() を直接使う）。
func _on_recipe_apply_pressed(ingredients: Array) -> void:
	if _phone_mode:
		return
	session.apply_recipe(ingredients)


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.can_save_recipe() を直接使う）。
func _can_save_recipe_now() -> bool:
	return not _phone_mode and session.can_save_recipe()


## 提供後の保存ボタン（段階：[レシピを保存] → 枠 → 名前）。名前は10.4.1の候補（椀のタグを含むものを先頭）。
func _add_recipe_save_buttons() -> void:
	if not _can_save_recipe_now():
		session.recipe_save_stage = ""
		return
	var additions: Array = session.open.current_bowl["additions"]
	match session.recipe_save_stage:
		"slot":
			for i in range(RecipeBook.slot_count()):
				var label := "枠%d：空き" % (i + 1)
				if i < GameState.saved_recipes.size():
					label = "枠%d：%s（上書き）" % [i + 1, str(GameState.saved_recipes[i]["name"])]
				_add_pot_button(label, i > GameState.saved_recipes.size(),
					_on_recipe_slot_selected.bind(i), _recipe_row)
			_add_pot_button("やめる", false, session.cancel_recipe_save, _recipe_row)
		"name":
			for item in RecipeBook.names_ordered(session.open.bowl_addition_tags()):
				_add_pot_button(str(item["name"]), false, _on_recipe_name_selected.bind(str(item["name"])), _recipe_row)
			_add_pot_button("やめる", false, session.cancel_recipe_save, _recipe_row)
		_:
			_add_pot_button("レシピを保存（%s）" % RecipeBook.ingredient_text(additions), false,
				_on_recipe_save_pressed, _recipe_row)


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.start_recipe_save() を直接使う）。
func _on_recipe_save_pressed() -> void:
	if _phone_mode:
		_refresh()
		return
	session.start_recipe_save()


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.select_recipe_slot() を直接使う）。
func _on_recipe_slot_selected(slot: int) -> void:
	if _phone_mode:
		_refresh()
		return
	session.select_recipe_slot(slot)


# DebugPanelの実体（転送だけの橋ではない。橋の整理でも残す）（本番UIは session.select_recipe_name() を直接使う）。
func _on_recipe_name_selected(recipe_name: String) -> void:
	if _phone_mode:
		session.recipe_save_stage = ""
		_refresh()
		return
	session.select_recipe_name(recipe_name)


# UI準備Aの橋。テストを移したら削除（本番UIは session.cancel_recipe_save() を直接使う）。
func _on_recipe_save_cancel_pressed() -> void:
	session.cancel_recipe_save()


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
			body = News.tab_text(GameState.day_count, session.played_events)
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
	var r: EventRunner = session.flow.runner
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
		"runner_done(完了フラグ): %s" % str(session.flow.is_runner_done()),
		# STEP 4: このフェーズは DONE 必須か。ブロック中なら [次のPhase] は no-op。
		"next_phase(次へ進めるか): %s" % ("OK" if not session.flow.is_advance_blocked() else "ブロック中(runner未DONE)"),
	]))


## OPEN 中の客キュー状態（STEP 6）。OPEN 以外は空文字を返し、表示に何も足さない。
##   時間帯   … いまの時間帯名と「何番目/全体」（7.6）。使い切っていれば (終了)
##   queue    … **その時間帯の**客数（7.6 で1日の総数から意味が変わった）
##   customer … いま接客中の客 id と「その時間帯の中で何人目/その時間帯の人数」、
##              この接客で出す杯数。全員終わっていれば (なし)
##   open_done … 全時間帯をさばき切ったか。true で [次のPhase] → CLOSE へ進める
##   pending   … 鍋が尽きて[鍋を見る]/[閉店]の選択待ちか（7.6）
func _format_open() -> String:
	if session.open == null:
		return ""
	var slot_customers: Array = session.open.current_slot_customers()
	var slot_text := "(終了)"
	if session.open.current_slot_name() != "":
		slot_text = "%s (%d/%d)" % [
			session.open.current_slot_name(), session.open.slot_index + 1, session.open.schedule.size()]
	var cust = session.open.current_customer()
	var cust_text := "(なし)"
	if cust != null:
		cust_text = "%s (%d/%d) %d杯" % [
			cust, session.open.index + 1, slot_customers.size(), session.current_servings()]
	var lines := PackedStringArray([
		"── OpenController（客キュー）──",
		"時間帯: %s" % slot_text,
		"queue(この時間帯の客数): %d" % slot_customers.size(),
		"customer(接客中): %s" % cust_text,
		"open_done(さばき切った): %s" % str(session.open.is_open_done()),
		"pending(鍋の選択待ち): %s" % ("はい" if session.pending_shortage_ev != null else "いいえ"),
	])
	# 1杯ずつ接客する客の集計中だけ出す（退店時に提供記録として1回反映される。
	# 評判はもう客ごとに積まないので、この表示からは外れた）。
	if not session.visit_tally.is_empty():
		lines.append("visit(この客の集計): 判定内訳%s 売上%d %d杯" % [
			str(session.visit_tally.get("results", {})),
			int(session.visit_tally["sale"]), int(session.visit_tally["servings"])])
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
	var customer_id := session.adjust_customer_id()
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
		"base(今日のベース): %s" % ("端材屋のクズ野菜（濃さ1スタート）" if session.scraps_base else "食肉仲卸"),
		"water(水場訪問済み): %s" % ("はい" if session.market_visited_water else "いいえ"),
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
	if session.open == null or not session.open.current_bowl.has("customer_id"):
		return ""
	var additions: Array = session.open.current_bowl.get("additions", [])
	var result: String = str(session.open.current_bowl.get("result", ""))
	var judge_text := "(未定)"
	# 評価しない杯（REACT に judge:false。例：持ち帰り用の杯）は、判定前から
	# 「(評価なし)」と出す（「まだ判定していないだけ」に見えないように）。
	if result == "" and not bool(session.react_for_now().get("judge", true)):
		judge_text = "(評価なし)"
	if result != "":
		var base_result: String = str(session.open.current_bowl.get("base_result", result))
		var penalty_suffix := ""
		if base_result != result:
			# 下げる理由を併記する（両方成立しても下げるのは1段階だけ）。
			var reasons := PackedStringArray()
			if session.open.current_bowl.get("penalty_strength", false):
				reasons.append("濃さ%d" % int(session.open.current_bowl.get("strength_at_judge", 0)))
			if session.open.current_bowl.get("penalty_spoiled", false):
				reasons.append("傷んだ具材")
			penalty_suffix = " → %sで1段下げ" % "・".join(reasons)
		# 具なし（フェーズ1 ステップ3）で強制BADになった場合、一致数だけ見ると
		# なぜBADなのか分からないので理由を併記する。
		var no_topping_suffix := "・具なし" if session.open.current_bowl.get("no_topping", false) else ""
		judge_text = "%s (一致%d%s%s%s)" % [
			result,
			int(session.open.current_bowl.get("match_count", 0)),
			" + favorite" if session.open.current_bowl.get("has_favorite", false) else "",
			no_topping_suffix,
			penalty_suffix,
		]
	var lines := [
		"── Bowl（接客中の椀）──",
		"additions(具材): %s (%d/%d)" % [str(additions), additions.size(), OpenController.MAX_ADDITIONS],
		"bowl_tags(3枠のtags): %s" % str(session.open.bowl_addition_tags()),
		"final_tags(最終tags): %s" % str(session.open.bowl_final_tags()),
	]
	# favorite は判定後（REACT適用後）だけ出す。判定前は好物を伏せておく（判定に実際に
	# 使った値＝初回は空になる。current_bowlはjudge_bowlに渡した後の値を持つ）。
	var favorite: String = str(session.open.current_bowl.get("favorite", ""))
	if result != "" and favorite != "":
		var in_bowl: bool = session.open.current_bowl.get("has_favorite", false)
		lines.append("favorite(好物): %s → %s" % [favorite, "入っている" if in_bowl else "入っていない"])
	# ③初回好物の開示：検証用に、判定の有無に関わらず「本来の好物」と既知状態を出す
	# （Event側の生の値。current_bowlの上のfavoriteとは別。書き換えない読み取り専用）。
	var raw_favorite: String = str(session.react_for_now().get("favorite", ""))
	if raw_favorite != "":
		var customer_id: String = str(session.open.current_bowl.get("customer_id", ""))
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
	if session.bowl_discard_count > 0:
		lines.append("discard_count(この客での廃棄回数): %d回" % session.bowl_discard_count)
	var reaction := session.current_reaction_text()
	if reaction != "":
		lines.append("reaction(反応): 【%s】%s" % [result, reaction])
	return "\n" + "\n".join(PackedStringArray(lines))


## F3 減点の事前表示（DESIGN.md 10.3.1・10.3.2・判断が必要な点4）。まだ判定していない
## 椀について、SaleRuleで提供不可なら理由を（優先）、提供はできてもJudgeで濃さ・傷みの
## 減点が見込まれるならその理由を返す。どちらも該当しなければ空文字（_format_bowl()側で
## 行を足さない）。理由は PlaySession.sale_hint() のコード（UI準備A④で抜き出した）から文にする。
func _format_sale_hint() -> String:
	if session.open == null or not session.open.current_bowl.has("customer_id"):
		return ""
	var hint: Dictionary = session.sale_hint()
	var blockers: Array = hint["blockers"]
	var composition_reasons := PackedStringArray()
	if blockers.has(SaleRule.NO_FLAVOR):
		composition_reasons.append("味付けが入っていません")
	if blockers.has(SaleRule.NO_TOPPING):
		composition_reasons.append("具が入っていません")
	if not composition_reasons.is_empty():
		return "（このままでは提供できません：%s）" % "・".join(composition_reasons)
	var penalty_reasons := PackedStringArray()
	for penalty in hint["penalties"]:
		if str(penalty["code"]) == "STRENGTH_EXTREME":
			penalty_reasons.append("濃さが%d" % int(penalty["value"]))
		elif str(penalty["code"]) == "SPOILED":
			penalty_reasons.append("傷んだ具材を使っています")
	if not penalty_reasons.is_empty():
		return "（このままだと1段階下がります：%s）" % "・".join(penalty_reasons)
	return ""


# UI準備Aの橋。テストを移したら削除（本番UIは session.current_reaction_text() を直接使う）。
func _current_reaction_text() -> String:
	return session.current_reaction_text()
