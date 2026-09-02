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

# OPEN の間だけ生きる客キュー管理役（STEP 6）。OPEN 以外では null。
# flow.runner は「今の客の接客 runner」に載せ替える。この _open は「今何人目か」を持つだけ。
var _open: OpenController = null


func _ready() -> void:
	_set_runner_for_phase(GameState.phase)

	# 以下は「どのボタン/シグナルが何を呼ぶか」の結線。処理内容は各ハンドラ側にある。
	flow.phase_changed.connect(_on_phase_changed)      # フェーズが変わった → 表示を更新
	flow.runner_updated.connect(_on_runner_updated)    # runner の再生位置が動いた → 表示を更新
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
	_btn_next_phase.pressed.connect(flow.advance_phase)  # [次のPhase] = 上位フェーズを一方向に1つ進める
	_btn_day_plus.pressed.connect(_on_day_plus_pressed)  # [Day+] = 日数だけ +1（デバッグ用）

	_refresh()


func _on_phase_changed(phase: int) -> void:
	_set_runner_for_phase(phase)
	_refresh()


## フェーズごとの Event 列を runner に差し込む。
## STEP 3: WAKE / STEP 4: PREP / STEP 6: OPEN（客キュー）/ STEP 9: CLOSE。
## NEXT_DAY は空のまま（日次処理は FlowController.advance_phase の折り返し側）。
## 新フェーズを実装するときは、ここに elif を1本足して対応する events を返す。
func _set_runner_for_phase(phase: int) -> void:
	_open = null   # OPEN 以外では客キューを持たない
	if phase == GameState.Phase.WAKE:
		flow.set_runner(Day1Events.wake_events())
	elif phase == GameState.Phase.PREP:
		flow.set_runner(Day1Events.prep_events())
	elif phase == GameState.Phase.OPEN:
		# 客ループは OpenController に隔離（DESIGN.md 4章）。中身の再生は客ごとの runner。
		_open = OpenController.new(Day1Events.customer_queue())
		_load_current_customer()
	elif phase == GameState.Phase.CLOSE:
		flow.set_runner(Day1Events.close_events())
	else:
		flow.set_runner([])   # NEXT_DAY など未実装フェーズ（空 runner ＝即 DONE）


## いま接客中の客の Event 列を flow.runner に載せる。
## 客がいなければ空 runner（＝即 DONE）にして、OPEN を CLOSE へ進められる状態にする。
func _load_current_customer() -> void:
	if _open != null and _open.has_more():
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
func _on_complete_input_pressed() -> void:
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
		_open.advance_customer()
		_load_current_customer()


## Event（データ）を1つ受けて、その効果を GameState に反映する「受け側」の本体。
## type を見て振り分けるだけ。処理はデータ側に持たせない（DESIGN.md 確定事項）。
##   PAY         … { amount } を apply_money(-amount) に渡す（支払い）
##   ADD_ITEM    … { item, amount } を add_inventory(item, amount) に渡す
##   REMOVE_ITEM … { item, amount } を remove_inventory(item, amount) に渡す（仕込みでの消費）
##   SET_SOUP    … { base_id, tags } を set_soup() に渡す（共有鍋の作成・STEP 12）
##   REACT       … { sale } を仮の売上として apply_money(+sale) ＋ record_served（STEP 6）
##   TEXT / WAIT_INPUT / GREET / ADJUST / SERVE … 表示だけ。状態は動かさない
##     （ADJUST は STEP 6 では素通し。実入力＝味付けは次 STEP）
## 注意: index 0 の Event は「乗る前進」が無いので適用されない。Day1 の WAKE / PREP /
## 客の接客はどれも先頭が TEXT / GREET（効果なし）なので実害なし。
func _apply_event(ev) -> void:
	if not (ev is Dictionary):
		return
	match ev.get("type", ""):
		"PAY":
			GameState.apply_money(-int(ev.get("amount", 0)))
		"ADD_ITEM":
			GameState.add_inventory(ev.get("item", ""), int(ev.get("amount", 1)))
		"REMOVE_ITEM":
			GameState.remove_inventory(ev.get("item", ""), int(ev.get("amount", 1)))
		"SET_SOUP":
			# 鍋を作るのは GameState.set_soup 経由（受け側は soup を直接触らない）。
			GameState.set_soup(str(ev.get("base_id", "")), ev.get("tags", []))
		"REACT":
			# 満足度判定（DESIGN.md 7章）は未実装。sale は固定プレースホルダ。
			var sale := int(ev.get("sale", 0))
			GameState.apply_money(sale)
			GameState.record_served({ "customer": ev.get("customer", ""), "sale": sale })


func _on_runner_updated() -> void:
	_refresh()


func _on_day_plus_pressed() -> void:
	GameState.advance_day()
	_refresh()


func _refresh() -> void:
	_game_state_label.text = _format_game_state()
	# OPEN 中は runner 表示のあとに客キューの状態も出す（OPEN 以外は空文字）。
	_runner_label.text = _format_runner() + _format_open()


func _format_game_state() -> String:
	var phase_name: String = GameState.Phase.keys()[GameState.phase]
	# soup は { base_id, tags[] }（STEP 12）。生 Dictionary は読みにくいので整形する。
	var soup_text := "(none)"
	if GameState.soup != null:
		soup_text = "%s tags=%s" % [GameState.soup.get("base_id", "?"), str(GameState.soup.get("tags", []))]
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
		# STEP 4: このフェーズは DONE 必須か。ブロック中なら [次のPhase] は no-op。
		"next_phase(次へ進めるか): %s" % ("OK" if not flow.is_advance_blocked() else "ブロック中(runner未DONE)"),
	]))


## OPEN 中の客キュー状態（STEP 6）。OPEN 以外は空文字を返し、表示に何も足さない。
##   queue     … キューの客数
##   customer  … いま接客中の客 id と「何人目/全体」。全員終わっていれば (なし)
##   open_done … 全員さばき切ったか。true で [次のPhase] → CLOSE へ進める
func _format_open() -> String:
	if _open == null:
		return ""
	var cust = _open.current_customer()
	var cust_text := "(なし)" if cust == null else "%s (%d/%d)" % [cust, _open.index + 1, _open.queue.size()]
	return "\n" + "\n".join(PackedStringArray([
		"── OpenController（客キュー）──",
		"queue(客数): %d" % _open.queue.size(),
		"customer(接客中): %s" % cust_text,
		"open_done(さばき切った): %s" % str(_open.is_open_done()),
	]))
