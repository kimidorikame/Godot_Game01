extends RefCounted
class_name Day1Events
## Day1 の Event 列（データのみ）。DESIGN.md 9章 STEP 3。
##
## 「シナリオデータと処理を分離する」方針（DESIGN.md 確定事項）に従い、
## Event の中身はここに置く。処理（表示・入力待ち解除など）は
## EventRunner / DebugPanel 側で行い、ここには書かない。
##
## STEP 3: WAKE のみ。STEP 4: PREP を最小構成で追加。STEP 6: OPEN の客1人分を追加。

static func wake_events() -> Array:
	return [
		{ "type": "TEXT", "text": "……目が覚めた。まだ薄暗い店の奥。" },
		{ "type": EventRunner.TYPE_WAIT_INPUT, "text": "スマホを見る。" },
		{ "type": "TEXT", "text": "さて、準備へ向かうか。" },
	]


## PREP の最小構成（DESIGN.md 9章 STEP 4）。
## 「PREP という巨大なコード」は作らず、TEXT / PAY / ADD_ITEM / REMOVE_ITEM の並びだけで表現する。
## ここはデータのみ。PAY の amount / ADD_ITEM・REMOVE_ITEM の item・amount が「効果」を表し、
## 実際の処理（apply_money / add_inventory / remove_inventory）は
## 受け側 = DebugPanel._apply_event が行う。text は表示用でしかなく、状態は動かさない。
## 末尾の REMOVE_ITEM が「仕込み＝具材を鍋へ消費」。soup を埋める処理はまだ持たない
## （在庫を1減らすだけ）。移動・水汲み・水場の使用料・仕込み演出は STEP 4 の範囲外。
static func prep_events() -> Array:
	return [
		{ "type": "TEXT", "text": "食肉売場へ来た" },
		{ "type": "PAY", "amount": 80, "text": "「いつもの。80だ」" },
		{ "type": "ADD_ITEM", "item": "soup_base", "amount": 1, "text": "骨と大根を受け取った" },
		{ "type": "REMOVE_ITEM", "item": "soup_base", "amount": 1, "text": "さて、仕込むか。鍋に放り込む" },
	]


## OPEN の客キュー（DESIGN.md 9章 STEP 6：まず配達員1人だけ）。
## 客が増えるのは STEP 7。ここに id を並べれば OpenController がその順で回す。
static func customer_queue() -> Array:
	return ["delivery_man"]


## 1人の客の接客 Event 列。GREET→ADJUST→SERVE→REACT の4つ（DESIGN.md 4章）。
## データのみ。処理は受け側 = DebugPanel._apply_event（GREET/ADJUST/SERVE は表示だけ、
## REACT で仮の売上を計上）。
## STEP 6 の割り切り:
##   - ADJUST はダミー素通し（WAIT_INPUT にしない。実入力＝味付けUIは次 STEP で足す）
##   - REACT の sale は満足度判定（DESIGN.md 7章）が入るまでの固定プレースホルダ
##   - 鍋の残量・濃さ・時間劣化・水（7.5章）は入れない
static func customer_events(customer_id: String) -> Array:
	return [
		{ "type": "GREET",  "customer": customer_id, "text": "配達員「いつもの。」" },
		{ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）※STEP6は素通し" },
		{ "type": "SERVE",  "customer": customer_id, "text": "「はいよ、お待ち。」" },
		{ "type": "REACT",  "customer": customer_id, "text": "配達員「繁盛してるな。」", "sale": 45 },
	]
