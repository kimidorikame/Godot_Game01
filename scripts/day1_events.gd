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


## PREP の最小構成（DESIGN.md 9章 STEP 4 → STEP 9 で水道代 → Day2 分岐で条件化）。
## 「PREP という巨大なコード」は作らず、TEXT / PAY / ADD_ITEM / REMOVE_ITEM の並びだけで表現する。
## ここはデータのみ。PAY の amount / ADD_ITEM・REMOVE_ITEM の item・amount が「効果」を表し、
## 実際の処理（apply_money / add_inventory / remove_inventory）は
## 受け側 = DebugPanel._apply_event が行う。text は表示用でしかなく、状態は動かさない。
## 支払いのトーン: 市場 -80 淡々（毎日）/ 水場 -50 生活の愚痴（徴収日のみ）/
##   場所代 -150 理不尽（OPEN・thug 側、同じく徴収日のみ）。金額処理は3つとも apply_money(-x)。
## 「水を汲む」TEXT は毎日入れる仮（状態変化なし。実際の水の入手＝7.5 の水の持ち方が
## 決まるまで保留）。方法A: is_collection_day() を読んで配列を組み立てる。
static func prep_events() -> Array:
	# 毎日の骨格。水汲み TEXT は仮（状態は動かさない）。
	var events := [
		{ "type": "TEXT", "text": "食肉売場へ来た" },
		{ "type": "PAY", "amount": 80, "text": "「いつもの。80だ」" },
		{ "type": "ADD_ITEM", "item": "soup_base", "amount": 1, "text": "骨と大根を受け取った" },
		{ "type": "TEXT", "text": "水場でポリタンクに水を汲む。" },
	]
	# 水道代は徴収日だけ。非徴収日は PAY が抜け、水汲み TEXT は残る。
	if GameState.is_collection_day():
		events.append({ "type": "PAY", "amount": 50,
			"text": "水場のポンプ番に呼び止められる。「今月分、払っとけよ」「はいはい、分かってる」" })
	# 仕込み: 在庫を減らす責務は REMOVE_ITEM のまま（鍋作成を混ぜない）。
	events.append({ "type": "REMOVE_ITEM", "item": "soup_base", "amount": 1,
		"text": "さて、仕込むか。鍋に放り込む" })
	# 共有鍋ができる（STEP 12）。ベースは今は骨だしの1種類だけ。
	# 野菜くず ["vegetal"] は金が無い日の分岐として後日。水量・濃さは持たせない。
	events.append({ "type": "SET_SOUP", "base_id": "bone_broth", "tags": ["meaty"],
		"text": "骨の出汁が立ってきた。今日の鍋ができた。" })
	return events


## CLOSE の締めくくり（DESIGN.md 9章 STEP 9）。TEXT のみ・効果を持つ Event は入れない。
## 所持金・提供数は計器盤に出ているので、ここは「読ませて区切る」だけ。
## 凝った売上内訳・精算演出は入れない（今ある状態を見せる最小）。
static func close_events() -> Array:
	return [
		{ "type": "TEXT", "text": "看板の灯を落とす。" },
		{ "type": "TEXT", "text": "屋台を閉める。" },
		{ "type": "TEXT", "text": "本日の営業終了。売上と提供数は計器盤のとおり。" },
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
##   - REACT の sale は満足度判定（DESIGN.md 7章）が入るまでの固定プレースホルダ
##   - 個性・調理・評価・鍋・水（7章 / 7.5章）は入れない
## STEP 13: ADJUST は素通しをやめ、"options" を持たせて入力待ちにする（DESIGN.md 9.5 STEP 13）。
##   選択肢を選ぶ処理（椀へ足す）は EventRunner ではなく受け側（DebugPanel）が行う。
## STEP 14: 二択にする（DESIGN.md 9.5 STEP 14）。Day1/Day2 を問わず同じ二択
##   （Day1 も「足す/足さない」を選べるチュートリアルとして）。"none" は
##   add_to_bowl 側で「何も足さない」として既に扱える（STEP 13 で用意済み）。
static func customer_events(customer_id: String) -> Array:
	var flavor := _customer_flavor(customer_id)
	var events := [
		{ "type": "GREET",  "customer": customer_id, "text": flavor["greet"] },
		{ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）",
			"options": [
				{ "id": "nam_prik_pao", "label": "ナムプリックパオを入れる" },
				{ "id": "none", "label": "なにも足さない" },
			] },
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
## STEP 8: チンピラの場所代。Day2 の分岐テスト: 「徴収日のみ」に条件化する。
##   - 徴収日の判定は GameState.is_collection_day()（データ関数が事実を読んで出し分け。
##     処理の埋め込みではなく「どの Event を出すか」の判断なので分離方針に反しない）
##   - 金額処理は既存の DebugPanel._apply_event "PAY" 枝（apply_money(-amount)）のまま
##   - 専用 State は作らない（確定事項どおり単なる Event）
##   - thug 以外、または徴収日でない日は空配列（4イベントのまま）
static func _customer_extra_events(customer_id: String) -> Array:
	if customer_id == "thug" and GameState.is_collection_day():
		return [
			{ "type": "PAY", "customer": "thug", "amount": 150,
				"text": "箸を置いてから、思い出したように。「あ、そうだ。今月分。」" },
		]
	return []
