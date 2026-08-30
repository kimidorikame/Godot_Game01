extends RefCounted
class_name OpenController
## OPEN の間だけ生存する客キューの管理役（DESIGN.md 4章「客ループは下位に隔離」）。
##
## Event の中身は持たない。「今どの客か / 次へ / さばき切ったか」だけを答える薄い部品。
## 接客そのものの再生は、客ごとの EventRunner（DebugPanel が flow.runner に載せる）に任せる。
## OPEN が終われば捨てる（RefCounted なので参照が切れれば解放される）。

var queue: Array = []      # 客 id の並び（STEP 6 は ["delivery_man"] の1人）
var index: int = 0         # いま何人目か（0起点）


func _init(customer_queue: Array = []) -> void:
	queue = customer_queue
	index = 0


## いま接客中の客 id。キューを超えていたら null。
func current_customer() -> Variant:
	if index < 0 or index >= queue.size():
		return null
	return queue[index]


## まだ接客すべき客が残っているか。
func has_more() -> bool:
	return index < queue.size()


## 次の客へ。呼び出し側は「今の客の runner が DONE」を確認してから呼ぶこと。
func advance_customer() -> void:
	index += 1


## キューを全員さばき切ったか（OPEN を終えて CLOSE へ進んでよい合図）。
func is_open_done() -> bool:
	return index >= queue.size()
