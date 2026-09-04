extends RefCounted
class_name EventRunner
## フェーズ内の Event 列を index で1つずつ進める使い捨て部品。
##
## なぜ status を GameState ではなく EventRunner が持つか:
##   runner は「客ごと・フェーズごと」に new して使い捨てる前提。進行度（status）も
##   各 runner が自前で持てば、別の客・別フェーズの進行度と混ざりようがない。
##   GameState に置くと1個の値をみんなで共有することになり、取り違えの元になる。
##
## 設計上の役割分担（DESIGN.md 準拠）:
##   - 進行度（index / status）はここが持つ。GameState には置かない。
##   - Event の種別ごとの処理（apply_money 等）はここではやらない。受ける側の責務。
##   - STEP 1 で解釈するのは「入力待ちか否か」だけ（type == WAIT_INPUT）。
##     残りの Event 型（TEXT / PAY / ADD_ITEM）は STEP 3〜4 で受け側に足す。

# フェーズ内 Event 列の再生状態。3値の意味:
#   PLAYING       … 自動で先へ進めてよい。[次のEvent] で index が進む
#   WAITING_INPUT … 入力待ち Event で停止中。complete_input() を通すまで動かない
#   DONE          … 列を最後まで消化しきった状態。「フェーズ内を消化しきった＝
#                   次のフェーズへ進んでよい」という合図として上位（FlowController）が見る
enum Status { PLAYING, WAITING_INPUT, DONE }

# 入力待ちを表す Event の type 値。STEP 1.5 で先行して決めた唯一の型。
const TYPE_WAIT_INPUT := "WAIT_INPUT"

var events: Array = []
var index: int = 0
var status: Status = Status.PLAYING


func _init(event_list: Array = []) -> void:
	events = event_list
	reset()


## 先頭に戻す。events はそのまま。
func reset() -> void:
	index = 0
	status = _status_for_index(0)


## 現在の Event。範囲外なら null。
func current() -> Variant:
	if index < 0 or index >= events.size():
		return null
	return events[index]


## 次の Event へ進める。index が範囲内かつ status == PLAYING のときだけ +1 する。
## - status が DONE / WAITING_INPUT のときは早期 return し、index も status も動かさない。
## - 進めた後、新しい index を見て status を計算し直す（末尾超え=DONE、次が入力待ち種別なら
##   WAITING_INPUT、それ以外 PLAYING）。
## complete_input() と2つに分けてある理由: 通常の「次へ」では WAIT_INPUT を飛び越えさせず、
## そこで確実に止めるため。解除は complete_input() 経由でしか行えない。
func advance() -> void:
	if status == Status.DONE or status == Status.WAITING_INPUT:
		return
	index += 1
	status = _status_for_index(index)


## 入力待ちを解除して次へ。WAITING_INPUT のときだけ有効（それ以外は早期 return）。
## まず status を WAITING_INPUT → PLAYING に戻し、そのうえで advance() を1回呼んで前進する。
## advance() と別関数なのは、「入力が済んだ」という合図を受けたここでだけ WAIT_INPUT を
## 越えさせるため。ただの「次へ」では越えられない、という区別を保つ。
func complete_input() -> void:
	if status != Status.WAITING_INPUT:
		return
	status = Status.PLAYING
	advance()


func _status_for_index(i: int) -> Status:
	if i >= events.size():
		return Status.DONE
	if _is_wait_input(events[i]):
		return Status.WAITING_INPUT
	return Status.PLAYING


## 入力待ちの判定。type == WAIT_INPUT のほか、"options" を持つ Event
## （ADJUST の選択肢など。STEP 13）も入力待ちとして扱う。
## options が1個か2個か（STEP 13 の一択 / STEP 14 の二択）は関知しない。
func _is_wait_input(ev) -> bool:
	return ev is Dictionary and (ev.get("type", "") == TYPE_WAIT_INPUT or ev.has("options"))
