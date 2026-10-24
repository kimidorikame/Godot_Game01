extends Node
class_name PlaySession
## 遊びの進行を持つ共有部品（UI準備A。DESIGN.md「設計上の確定事項」最後の項目の分離）。
##
## DebugPanel（検証用）と本番UIが、**同じゲーム処理を1か所から使う**ための部品。画面（ノード・ボタン・
## ラベル）には一切触れない。UIは「操作を呼ぶ」「問いを読む」「changed を受けて描き直す」だけにする。
## FlowController と同じく、画面のシーンの子ノードとして持つ（autoload にはしない）。FlowController は
## この部品が自分で作って持つ（画面のシーンは PlaySession を1つ持てば足りる）。
##
## 移行中（UI準備A）：処理は DebugPanel から塊ごとに移している。移した操作は、末尾で changed を出す
## （今の DebugPanel の _refresh() と同じ考え方。UIは changed を受けて全体を描き直す）。
## 通知の粒度は1本（changed）。種類ごとのシグナルは作らない。

## 状態が変わったことをUIへ知らせる。各操作の末尾で1回出す（途中の経過では出さない）。
signal changed()

## フェーズの一方向遷移と、フェーズ内の Event 再生（runner）を持つ。
var flow: FlowController = null


func _init() -> void:
	flow = FlowController.new()
	flow.name = "FlowController"
	add_child(flow)


## 状態が変わったことを知らせる（UIは全体を描き直す）。
func notify_changed() -> void:
	changed.emit()
