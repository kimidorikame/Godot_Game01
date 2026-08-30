extends PanelContainer
## 開発用 State Viewer（DESIGN.md 8章 / 9章 STEP 1・STEP 2）。
##
## GameState と EventRunner.status を画面に映し、デバッグボタンで手叩きする。
## 本番のゲーム画面ではない。絵もシナリオも無し。
## FlowController はこのシーンの子ノードとして持つ（autoload にはしない）。

@onready var flow: FlowController = $FlowController as FlowController
@onready var _game_state_label: Label = $Margin/VBox/GameStateLabel as Label
@onready var _runner_label: Label = $Margin/VBox/RunnerLabel as Label
@onready var _btn_next_event: Button = $Margin/VBox/EventRow/BtnNextEvent as Button
@onready var _btn_complete_input: Button = $Margin/VBox/EventRow/BtnCompleteInput as Button
@onready var _btn_next_phase: Button = $Margin/VBox/PhaseRow/BtnNextPhase as Button
@onready var _btn_day_plus: Button = $Margin/VBox/PhaseRow/BtnDayPlus as Button


func _ready() -> void:
	# STEP 1: runner の中身は空。フェーズ用の Event 列は STEP 3 以降で差す。
	flow.set_runner([])

	# 以下は「どのボタン/シグナルが何を呼ぶか」の結線。処理内容は各ハンドラ側にある。
	flow.phase_changed.connect(_on_phase_changed)      # フェーズが変わった → 表示を更新
	flow.runner_updated.connect(_on_runner_updated)    # runner の再生位置が動いた → 表示を更新
	# [次のEvent] = runner_advance:
	#   PLAYING のときだけ index を1つ進める。WAITING_INPUT / DONE では何もしない。
	#   つまり WAIT_INPUT の Event に当たったらこのボタンでは進めなくなる（＝確実に止まる）。
	_btn_next_event.pressed.connect(flow.runner_advance)
	# [入力完了] = runner_complete_input:
	#   WAITING_INPUT を PLAYING に戻してから1つ進める。「入力待ちの解除」専用。
	#   [次のEvent] との違い: あちらは止まっている列を動かせないが、こちらは
	#   止まっている状態を解除したうえで先へ進める。PLAYING 中に押しても無効。
	_btn_complete_input.pressed.connect(flow.runner_complete_input)
	_btn_next_phase.pressed.connect(flow.advance_phase)  # [次のPhase] = 上位フェーズを一方向に1つ進める
	_btn_day_plus.pressed.connect(_on_day_plus_pressed)  # [Day+] = 日数だけ +1（デバッグ用）

	_refresh()


func _on_phase_changed(_phase: int) -> void:
	# TODO(STEP 3/4): PREP 以降を実装する際、ここからフェーズに応じた Event 列の
	#   差し替え（_set_runner_for_phase 相当）を呼ぶ予定。今は表示更新のみ。
	_refresh()


func _on_runner_updated() -> void:
	_refresh()


func _on_day_plus_pressed() -> void:
	GameState.advance_day()
	_refresh()


func _refresh() -> void:
	_game_state_label.text = _format_game_state()
	_runner_label.text = _format_runner()


func _format_game_state() -> String:
	var phase_name: String = GameState.Phase.keys()[GameState.phase]
	var soup_text := "(none)" if GameState.soup == null else str(GameState.soup)
	# 表示する各項目の意味（GameState = 日をまたいで残る事実）:
	#   day_count  … 今が何日目か。NEXT_DAYで+1
	#   money      … 所持金。支払いで減り売上で増える
	#   reputation … 店の評判値。今は予約のみ未使用
	#   inventory  … 持っている具材・調味料の個数
	#   rumors     … スマホで得た噂の件数。今は未使用
	#   phase      … 一日のどの段階か（WAKE→PREP→OPEN→CLOSE→NEXT_DAY）
	#   soup       … 仕込んだ鍋。仕込み前はnone。翌日リセット
	#   served     … 今夜出した杯数。served配列のsize。翌日リセット
	# ラベルは「項目(意味): 値」の形。値の算出ロジックは変更していない。
	return "\n".join(PackedStringArray([
		"── GameState（日をまたいで残る事実）──",
		"day_count(日数): %d" % GameState.day_count,
		"money(所持金): %d" % GameState.money,
		"reputation(評判): %d" % GameState.reputation,
		"inventory(在庫数): %d 個" % GameState.inventory.size(),
		"rumors(情報数): %d 件" % GameState.rumors.size(),
		"phase(現在フェーズ): %s (%d)" % [phase_name, GameState.phase],
		"soup(今日の鍋): %s" % soup_text,
		"served(提供数): %d" % GameState.served.size(),
	]))


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
	]))
