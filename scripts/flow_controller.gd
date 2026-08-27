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

# 一方向の並び。末尾 NEXT_DAY の次は先頭 WAKE へ折り返す。
var _phase_order := [
	GameState.Phase.WAKE,
	GameState.Phase.PREP,
	GameState.Phase.OPEN,
	GameState.Phase.CLOSE,
	GameState.Phase.NEXT_DAY,
]

var runner: EventRunner = null


## 次のフェーズへ進める。NEXT_DAY→WAKE の折り返し時だけ日次処理を挟む。
func advance_phase() -> void:
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
