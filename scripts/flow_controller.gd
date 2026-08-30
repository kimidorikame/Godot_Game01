extends Node
class_name FlowController
## 上位フェーズの一方向遷移だけを司るノード。
##
## 設計上の役割分担（DESIGN.md 準拠）:
##   - フェーズは WAKE→PREP→OPEN→CLOSE→NEXT_DAY→(WAKEへ) の一方向。前に戻さない。
##   - 「今どのフェーズか」は GameState.phase に書く。進行度は持たない。
##   - フェーズ内の Event 再生は EventRunner に委譲。ここは1本だけ保持する。
##   - STEP 1 では runner の中身は空でよい（DebugPanel から手叩き検証するための骨組み）。

signal phase_changed(phase: int)
signal runner_updated()

# フェーズの並び順。advance_phase() は現在位置の +1 しか行わず、前のフェーズには戻さない。
# 末尾 NEXT_DAY の次は先頭 WAKE へ折り返す（そこで日次リセット＋日数+1）。
# 設計意図: この一方向性が「一日一鍋・仕込み直し不可」を構造で保証する。
#   PREP（仕込み）を後から通り直す経路がそもそも無いので、OPEN 以降に鍋を作り直す・
#   仕込みをやり直すといった操作は、コード上あり得ない形になる。
var _phase_order := [
	GameState.Phase.WAKE,
	GameState.Phase.PREP,
	GameState.Phase.OPEN,
	GameState.Phase.CLOSE,
	GameState.Phase.NEXT_DAY,
]

# フェーズごとに「runner が DONE でなくても [次のPhase] で先へ進めてよいか」。
#   true  … ゲートなし。中身を消化しきる前でも進める
#   false … DONE 必須。runner.status == DONE になるまで advance_phase() は弾く
# WAKE:     スマホ（WAIT_INPUT）を飛ばして先へ行けるよう true。
# NEXT_DAY: 日次処理だけの自動フェーズなので true。
# PREP / OPEN / CLOSE: 仕込み・接客・精算を途中で飛ばさせない＝false。
# 注意: OPEN / CLOSE は現状 Event 列が空（_set_runner_for_phase に elif が無い）で、
#   空 runner は即 DONE になるため、中身が入る STEP までゲートは実質素通りする。
var _phase_can_skip := {
	GameState.Phase.WAKE: true,
	GameState.Phase.PREP: false,
	GameState.Phase.OPEN: false,
	GameState.Phase.CLOSE: false,
	GameState.Phase.NEXT_DAY: true,
}

var runner: EventRunner = null


## 現在フェーズが「DONE 必須」なのに runner がまだ DONE でない＝[次のPhase] を
## 弾くべき状態か。未登録フェーズは既定で「ゲートなし」(get の既定 true) にして、
## 想定外のフェーズで進行不能に陥らせない。
func is_advance_blocked() -> bool:
	return not _phase_can_skip.get(GameState.phase, true) and not is_runner_done()


## 次のフェーズへ進める。NEXT_DAY→WAKE の折り返し時だけ日次処理を挟む。
## DONE 必須フェーズで runner が未 DONE のときは、何もせず return（phase も
## runner も日次処理も一切動かさない）。
func advance_phase() -> void:
	if is_advance_blocked():
		return
	var i := _phase_order.find(GameState.phase)
	if i == -1:
		i = 0
	var wrapping := (GameState.phase == GameState.Phase.NEXT_DAY)
	var next_phase = _phase_order[(i + 1) % _phase_order.size()]
	if wrapping:
		GameState.reset_for_new_day()
		GameState.advance_day()
	GameState.phase = next_phase
	phase_changed.emit(next_phase)


## 現フェーズの Event 列を差し込む。STEP 1 では空配列で可。
func set_runner(events: Array = []) -> void:
	runner = EventRunner.new(events)
	runner_updated.emit()


## runner を次の Event へ。
func runner_advance() -> void:
	if runner == null:
		return
	runner.advance()
	runner_updated.emit()


## runner の入力待ちを解除して次へ。
func runner_complete_input() -> void:
	if runner == null:
		return
	runner.complete_input()
	runner_updated.emit()


## runner が最後まで消化済みか（フェーズを次へ進めてよい合図）。
func is_runner_done() -> bool:
	return runner != null and runner.status == EventRunner.Status.DONE
