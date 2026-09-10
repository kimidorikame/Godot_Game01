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
@onready var _options_row: HBoxContainer = $Margin/VBox/OptionsRow as HBoxContainer
@onready var _btn_next_phase: Button = $Margin/VBox/PhaseRow/BtnNextPhase as Button
@onready var _btn_day_plus: Button = $Margin/VBox/PhaseRow/BtnDayPlus as Button

# OPEN の間だけ生きる客キュー管理役（STEP 6）。OPEN 以外では null。
# flow.runner は「今の客の接客 runner」に載せ替える。この _open は「今何人目か」を持つだけ。
var _open: OpenController = null

# 判定結果 → 評判の増減（DESIGN.md 7.6）。名前あり客よりモブの方が動きが小さい。
# 「どれだけ動かすか」を決めるのは受け側＝ここ。適用は GameState.apply_reputation()。
# sale と同じ考え方（量は受け側が決め、GameState は入口として適用するだけ）。
# 数値は仮。触ってから調整する（DESIGN.md 7.6「評判のインフレについて」）。
const REPUTATION_NAMED := { "GREAT": 3, "GOOD": 2, "OK": 0, "BAD": -2 }
const REPUTATION_MOB := { "GREAT": 1, "GOOD": 1, "OK": 0, "BAD": -1 }


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
## STEP 17.6: ADJUST 中も含め、常にこのボタンで進める（＝「提供」を兼ねる）。
## 具材ボタンはもう進めない（_on_ingredient_selected 側）ので、ADJUST で止まったまま
## 何度でも具材を選び、進みたくなったらこのボタンを押す、という形になる。
func _on_complete_input_pressed() -> void:
	_complete_input_and_advance()


## ADJUST の具材ボタンが押されたときのハンドラ（STEP 17.6）。
## 「椀へ具材を足す」のは EventRunner ではなく受け側＝ここの責務
## （DESIGN.md 9.5 STEP 13「EventRunner は味付け効果を処理しない」）。
## STEP 13/14 と違い、進めない（advanceしない）。3枠まで何度でも選べるようにするため、
## ADJUST から進むのは [入力完了]（提供）を押したときだけにする。
func _on_ingredient_selected(ingredient_id: String) -> void:
	if _open != null:
		_open.add_to_bowl(ingredient_id)
	_refresh()


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
		_open.advance_customer()
		_load_current_customer()


## Event（データ）を1つ受けて、その効果を GameState に反映する「受け側」の本体。
## type を見て振り分けるだけ。処理はデータ側に持たせない（DESIGN.md 確定事項）。
##   PAY         … { amount } を apply_money(-amount) に渡す（支払い）
##   ADD_ITEM    … { item, amount } を add_inventory(item, amount) に渡す
##   REMOVE_ITEM … { item, amount } を remove_inventory(item, amount) に渡す（仕込みでの消費）
##   SET_SOUP    … { base_id, tags, servings } を set_soup() に渡す（共有鍋の作成・STEP 12/7.6）
##   REACT       … judge_bowl() で BAD/OK/GOOD/GREAT を判定（STEP 17.6）。
##                 判定結果 → apply_reputation / 鍋 → consume_soup(servings) /
##                 売上 → apply_money(+sale)（sale は 50×servings）＋ record_served（7.6）
##   TEXT / WAIT_INPUT / GREET / ADJUST / SERVE … 表示だけ。状態は動かさない
##     （ADJUST は STEP 13 で入力待ちに変わったが、椀への反映は _on_ingredient_selected が
##     行う。ここ（_apply_event）は今も何もしない）
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
			# 7.6: servings（残量の初期値＝仕込んだ杯数）も Event から受け取る。
			GameState.set_soup(str(ev.get("base_id", "")), ev.get("tags", []),
				int(ev.get("servings", 0)))
		"REACT":
			# 判定（BAD/OK/GOOD/GREAT）は OpenController.judge_bowl が行い、current_bowl の
			# result / match_count に記録するだけ。Event（reactions）はここでも書き換えない
			# （DESIGN.md 確定事項「Event はデータ、処理は受け側」）。
			# どの反応textを見せるかは表示側 _current_reaction_text() が都度選ぶ。
			# 7.6: 売上は 50×servings（Event が計算済みの sale を持つ）。評判は判定結果と
			# 名前あり/モブで増減表を引き、GameState の入口を通して適用する。
			# 鍋からは servings 分を取り分ける（consume_soup）。今は 0 未満も許す
			# ＝尽きたときの選択（断る／薄めて出す）は後の段階。
			var sale := int(ev.get("sale", 0))
			var servings := int(ev.get("servings", 1))
			var result := ""
			if _open != null:
				result = _open.judge_bowl(ev.get("wanted_tags", []), str(ev.get("favorite", "")))
			var table: Dictionary = REPUTATION_MOB if ev.get("is_mob", false) else REPUTATION_NAMED
			GameState.apply_reputation(int(table.get(result, 0)))
			GameState.consume_soup(servings)
			GameState.apply_money(sale)
			GameState.record_served({ "customer": ev.get("customer", ""), "sale": sale,
				"servings": servings })


func _on_runner_updated() -> void:
	_refresh()


func _on_day_plus_pressed() -> void:
	GameState.advance_day()
	_refresh()


func _refresh() -> void:
	_game_state_label.text = _format_game_state()
	# OPEN 中は runner 表示のあとに客キューの状態も出す（OPEN 以外は空文字）。
	_runner_label.text = _format_runner() + _format_open()
	_update_options_row()


## 選択肢ボタンの描画（STEP 13、STEP 17.6で挙動変更）。毎回 _refresh() から呼び、
## 状態から描き直す（他の表示と同じ「押した直後だけ更新」ではなく毎回作り直す方針）。
## - 現在の Event が "options" を持つ WAITING_INPUT のときだけボタンを並べる。
## - それ以外（options なしの WAIT_INPUT・PLAYING・DONE）は空にする。
## - STEP 17.6: [入力完了] はもう無効化しない。ADJUST 中でも押せば提供として進める
##   （3枠未満でも提供できる、という仕様のため）。具材が上限（MAX_ADDITIONS）に
##   達していたら、具材ボタン側だけを無効化する（進む手段は[入力完了]のみ残す）。
func _update_options_row() -> void:
	for child in _options_row.get_children():
		child.queue_free()

	var r: EventRunner = flow.runner
	if r == null or r.status != EventRunner.Status.WAITING_INPUT:
		return
	var cur = r.current()
	if not (cur is Dictionary) or not cur.has("options"):
		return
	var at_cap := false
	if _open != null:
		at_cap = _open.current_bowl.get("additions", []).size() >= OpenController.MAX_ADDITIONS
	for option in cur["options"]:
		var btn := Button.new()
		btn.text = str(option.get("label", option.get("id", "?")))
		btn.disabled = at_cap
		btn.pressed.connect(_on_ingredient_selected.bind(str(option.get("id", ""))))
		_options_row.add_child(btn)


func _format_game_state() -> String:
	var phase_name: String = GameState.Phase.keys()[GameState.phase]
	# soup は { base_id, tags[], remaining_servings }（STEP 12 / 7.6）。生 Dictionary は
	# 読みにくいので整形する。
	var soup_text := "(none)"
	if GameState.soup != null:
		# 7.6: 残量（あと何杯出せるか）を併記する。分母（仕込み量）は出さない
		# ＝水やベースを足せば初期値を超えるので、比率ではなく絶対値で見る。
		soup_text = "%s 残量%d杯 tags=%s" % [
			GameState.soup.get("base_id", "?"),
			int(GameState.soup.get("remaining_servings", 0)),
			str(GameState.soup.get("tags", [])),
		]
	# 表示する各項目の意味（GameState = 日をまたいで残る事実）:
	#   day_count  … 今が何日目か。NEXT_DAYで+1
	#   money      … 所持金。支払いで減り売上で増える
	#   reputation … 店の評判値。REACT の判定結果で増減する（7.6）
	#   inventory  … 持っている具材・調味料の個数
	#   rumors     … スマホで得た噂の件数。今は未使用
	#   phase      … 一日のどの段階か（WAKE→PREP→OPEN→CLOSE→NEXT_DAY）
	#   soup       … 仕込んだ鍋と残量。仕込み前はnone。翌日リセット
	#   served     … 接客数（served配列のsize）と杯数（servingsの合計）。翌日リセット
	#                 7.6 で1回の接客が複数杯になったので、両方を出さないと誤読する
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
		"served(接客数/杯数): %d / %d" % [GameState.served.size(), _served_servings()],
	]))


## 今夜出した杯数の合計（ServedRecord の servings を足す）。
## served.size() は「接客イベント数」であって杯数ではない（モブ4人＝1接客4杯）。
func _served_servings() -> int:
	var total := 0
	for record in GameState.served:
		if record is Dictionary:
			total += int(record.get("servings", 1))
	return total


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
##   customer  … いま接客中の客 id と「何人目/全体」、この接客で出す杯数（7.6）。
##                全員終わっていれば (なし)
##   open_done … 全員さばき切ったか。true で [次のPhase] → CLOSE へ進める
func _format_open() -> String:
	if _open == null:
		return ""
	var cust = _open.current_customer()
	var cust_text := "(なし)"
	if cust != null:
		cust_text = "%s (%d/%d) %d杯" % [cust, _open.index + 1, _open.queue.size(), _current_servings()]
	return "\n" + "\n".join(PackedStringArray([
		"── OpenController（客キュー）──",
		"queue(客数): %d" % _open.queue.size(),
		"customer(接客中): %s" % cust_text,
		"open_done(さばき切った): %s" % str(_open.is_open_done()),
	])) + _format_bowl()


## いま接客中の客が何杯注文しているか（7.6）。REACT がまだ current でなくても見たいので、
## runner の Event 列から REACT を探して servings を読む（Event はデータなので読むだけ）。
func _current_servings() -> int:
	if flow.runner == null:
		return 0
	for ev in flow.runner.events:
		if ev is Dictionary and ev.get("type", "") == "REACT":
			return int(ev.get("servings", 1))
	return 0


## 接客中の椀（STEP 13）。DESIGN.md 9.5 STEP 11「椀の最終tags = Soup.tags +
## Bowl.additions 内の Ingredient.tags」を OpenController.bowl_final_tags() で計算して見せる。
## additions の件数表示 (n/上限) は STEP 17.6（今何個入っているか・残り枠が見えるように）。
## STEP 17.6（第二・第三段階）の表示:
##   bowl_tags  … 判定に使う3枠だけのtags（鍋を含まない）
##   final_tags … 鍋込みの椀の最終tags（表示用。判定には使っていない）
##   favorite   … その客の好物idと、実際に入っていたか（判定後だけ出す。ADJUST中に
##                出すと「会話から推測する」検証にならないため）
##   judge      … BAD/OK/GOOD/GREAT と一致数（REACT 適用前は「(未定)」）
##   reaction   … 反応text。判定結果は【】でここ（表示側）が付ける。
##                データ（reactions の文言）には入れない＝本番UIでは付けなければよい
## 椀が無い（客がいない）ときは空文字（表示に何も足さない）。
func _format_bowl() -> String:
	if _open == null or not _open.current_bowl.has("customer_id"):
		return ""
	var additions: Array = _open.current_bowl.get("additions", [])
	var result: String = str(_open.current_bowl.get("result", ""))
	var judge_text := "(未定)"
	if result != "":
		judge_text = "%s (一致%d%s)" % [
			result,
			int(_open.current_bowl.get("match_count", 0)),
			" + favorite" if _open.current_bowl.get("has_favorite", false) else "",
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
