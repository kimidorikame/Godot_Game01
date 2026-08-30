extends RefCounted
class_name Day1Events
## Day1 の Event 列（データのみ）。DESIGN.md 9章 STEP 3。
##
## 「シナリオデータと処理を分離する」方針（DESIGN.md 確定事項）に従い、
## Event の中身はここに置く。処理（表示・入力待ち解除など）は
## EventRunner / DebugPanel 側で行い、ここには書かない。
##
## STEP 3: WAKE のみ。STEP 4: PREP を最小構成で追加。
## STEP 6: OPEN の客1人分。STEP 7: OPEN の客を3人に（キューを増やすだけで回る確認）。
## STEP 8: チンピラの REACT 後ろに場所代 PAY を1つ差す（専用 State なし・単なる Event）。

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


## OPEN の客キュー（DESIGN.md 9章）。STEP 6: 配達員1人 → STEP 7: 3人。
## ここに id を並べれば OpenController がその順で1人ずつ回す。増減はこの1行だけ。
static func customer_queue() -> Array:
	return ["delivery_man", "thug", "normal_customer"]


## 1人の客の接客 Event 列。GREET→ADJUST→SERVE→REACT の4ステップは全客共通（DESIGN.md 4章）。
## データのみ。処理は受け側 = DebugPanel._apply_event（GREET/ADJUST/SERVE は表示だけ、
## REACT で仮の売上を計上）。
## STEP 7/8 の割り切り:
##   - 4ステップ骨格は全客共通。客ごとの差は text と sale、および REACT 後ろの追加 Event だけ
##   - ADJUST はダミー素通し（WAIT_INPUT にしない。実入力＝味付けUIは次 STEP で足す）
##   - REACT の sale は満足度判定（DESIGN.md 7章）が入るまでの固定プレースホルダ
##   - 個性・調理・評価・鍋・水（7章 / 7.5章）は入れない
static func customer_events(customer_id: String) -> Array:
	var flavor := _customer_flavor(customer_id)
	var events := [
		{ "type": "GREET",  "customer": customer_id, "text": flavor["greet"] },
		{ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）※素通し" },
		{ "type": "SERVE",  "customer": customer_id, "text": "「はいよ、お待ち。」" },
		{ "type": "REACT",  "customer": customer_id, "text": flavor["react"], "sale": flavor["sale"] },
	]
	events.append_array(_customer_extra_events(customer_id))
	return events


## 客ごとに変わる差分だけ（売上は DESIGN.md 6章の Day1 台本準拠：45 / 40 / 55）。
## 未知 id は無音・売上0でフォールバック。
static func _customer_flavor(customer_id: String) -> Dictionary:
	match customer_id:
		"delivery_man":
			return { "greet": "配達員「いつもの。」", "react": "配達員「繁盛してるな。」", "sale": 45 }
		"thug":
			return { "greet": "チンピラ「……同じの。」", "react": "チンピラ、黙って食い終えた。", "sale": 40 }
		"normal_customer":
			return { "greet": "客「適当に一杯。」", "react": "客「ごちそうさん。」", "sale": 55 }
		_:
			return { "greet": "客「……。」", "react": "客、無言。", "sale": 0 }


## REACT の後ろに差し込む客ごとの追加 Event（DESIGN.md 4章「pay を1つ挿すだけ」）。
## STEP 8: チンピラの場所代のみ。食い終わってから切り出す理不尽を PAY の text で出す。
##   - 金額処理は既存の DebugPanel._apply_event "PAY" 枝（apply_money(-amount)）をそのまま使う
##   - 専用 State は作らない（確定事項どおり単なる Event）
##   - 月1回などの条件分岐は入れない＝ Day1 は場所代の日として固定（条件化は Day2 の分岐テスト）
## 追加が無い客は空配列を返す（delivery_man / normal_customer は4イベントのまま）。
static func _customer_extra_events(customer_id: String) -> Array:
	match customer_id:
		"thug":
			return [
				{ "type": "PAY", "customer": "thug", "amount": 150,
					"text": "箸を置いてから、思い出したように。「あ、そうだ。今月分。」" },
			]
		_:
			return []
