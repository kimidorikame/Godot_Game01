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
## STEP 17.5: normal_customer を granny（老婆）に差し替え。
static func customer_queue() -> Array:
	return ["delivery_man", "thug", "granny"]


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
## STEP 15/16: REACT に wanted_tag / text_miss を持たせる（DESIGN.md 9.5 STEP 15・16）。
##   判定（GOOD/MISS）は受け側 = OpenController.judge_bowl が行う。text は書き換えず、
##   どちらを見せるかは受け側が都度選ぶ（DebugPanel._current_reaction_text）。
## STEP 17.5: GREET は複数行の掛け合いを1行1Eventに分けて積む（テンポを出すため。
##   EventRunner/受け側は無改修で動く＝WAKEの起床TEXT3連続と同じパターン）。
##   ADJUSTは5つの調味料＋そのまま(none)の6択。wanted_tagは単数。
##   text/text_missはそれぞれ2パターンの配列（ランダムでどちらかを表示・STEP17.5）。
static func customer_events(customer_id: String) -> Array:
	var flavor := _customer_flavor(customer_id)
	var events := []
	for line in flavor["greet"]:
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	events.append({ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）",
		"options": [
			{ "id": "nam_prik_pao", "label": "ナムプリックパオを入れる" },
			{ "id": "coconut_milk", "label": "ココナッツミルクを入れる" },
			{ "id": "pickled_lime", "label": "ライム漬けを入れる" },
			{ "id": "bitter_melon", "label": "ゴーヤを入れる" },
			{ "id": "herbal_sauce", "label": "薬膳ナンプラーだれを入れる" },
			{ "id": "none",         "label": "そのまま出す" },
		] })
	events.append({ "type": "SERVE", "customer": customer_id, "text": "「はいよ、お待ち。」" })
	events.append({ "type": "REACT", "customer": customer_id, "text": flavor["react"],
		"text_miss": flavor["react_miss"], "wanted_tag": flavor["wanted_tag"],
		"sale": flavor["sale"] })
	events.append_array(_customer_extra_events(customer_id))
	return events


## 客ごとに変わる差分だけ（売上は DESIGN.md 6章の Day1 台本準拠：45 / 40 / 55）。
## STEP 17.5: greetは複数行の配列、react/react_missは2パターンの配列、wanted_tagは単数。
## greet/react/react_miss は3人とも反映済み（STEP 17.5）。
## 未知 id は無音・売上0・wanted_tag空文字（＝一致しようがないので常にMISS）でフォールバック。
static func _customer_flavor(customer_id: String) -> Dictionary:
	match customer_id:
		"delivery_man":
			return { "greet": [
					"（若い配達員が来る、額から汗が垂れていてぐったりしている）",
					"主人公「なんだ？随分疲れてるみたいだな」",
					"配達員「はあ……港と金融エリアにスラム、今日はこれで二十往復目だぜぇ」",
					"主人公「今日はもう上がりか？」",
					"配達員「あと一便。眠くて信号が二つに見えてきた」",
					"主人公「いつものにするか？」",
					"配達員「うん。今日は遠慮なしで辛くしてくれ」",
					"配達員「赤くて、喉が焼けるくらいのやつ。汗かいたら目も覚めるだろ」",
				],
				"react": [
					"配達員「っうっま、よし！来た来た！ 腹の中で火がついた。これなら数か所行けそうだ」",
					"配達員「これなら帰り道までは寝ずに済みそうだ」",
				],
				"react_miss": [
					"配達員「うまいけど、今日はもの足りないな」",
					"配達員「もっと一発、殴ってくるようなのが欲しかった」",
				],
				"sale": 45, "wanted_tag": "HOT" }
		"thug":
			return { "greet": [
					"（チンピラは腰を下ろすと、腹の辺りを押さえて小さく息を吐く）",
					"チンピラ「一杯。今日は軽いやつにしろ」",
					"主人公「いつもの肉だらけの奴じゃなく？」",
					"チンピラ「昨日、兄貴にしこたま飲まされてまだ胃が焼けてんだよ、辛いのも酸っぱいのも、今日は勘弁しろ」",
					"主人公「じゃあ、薄めて出すか？」",
					"チンピラ「水っぽくしろとは言ってねえ」",
					"チンピラ「ほら………あーあれ、口当たりがまろくなるやつがあるだろ。あれを入れろ」",
				],
				"react": [
					"チンピラ「……そう、これだ」",
					"チンピラ「はー……うめ、腹に刺さらねえ」",
				],
				"react_miss": [
					"チンピラ「………だから、刺激のあるのはやめろって言っただろ」",
					"チンピラ「あー………まぁいいや」",
				],
				"sale": 40, "wanted_tag": "MELLOW" }
		"granny":
			return { "greet": [
					"（老婆は屋台の椅子にゆっくり腰を下ろし、両手を擦り合わせる）",
					"老婆「今夜は骨がよく鳴るねえ。明日は雨だよ」",
					"主人公「また骨占いか」",
					"老婆「そこらの天気予報より当たるさ」",
					"主人公「何がいい？」",
					"老婆「昔、港の診療所で飲ませてもらった汁があってね」",
					"主人公「病院の飯か？」",
					"老婆「薬棚みたいな匂いがして、その奥に港の塩気がある………」",
					"老婆「ああ、水で薄めた貧乏臭いのはごめんだよ、腹の底へちゃんと残る。ああいうのがいいね」",
				],
				"react": [
					"老婆「そう、これだよ。塩気の奥から、草の根の匂いが戻ってくる」",
					"老婆「苦いだけの薬より、こっちの方がよほど身体に効くねえ」",
				],
				"react_miss": [
					"老婆「これはこれで悪くない。でも、今夜欲しかったのとは違うね」",
					"老婆「舌じゃなく、古い骨まで温めてくれる味が欲しかったんだけどね」",
				],
				"sale": 55, "wanted_tag": "SAVORY" }
		_:
			return { "greet": ["客「……。」"], "react": ["客、無言。", "客、無言。"],
				"react_miss": ["客、無言。", "客、無言。"], "sale": 0, "wanted_tag": "" }


## REACT の後ろに差し込む客ごとの追加 Event（DESIGN.md 4章「pay を1つ挿すだけ」）。
## STEP 8: チンピラの場所代。Day2 の分岐テスト: 「徴収日のみ」に条件化する。
##   - 徴収日の判定は GameState.is_collection_day()（データ関数が事実を読んで出し分け。
##     処理の埋め込みではなく「どの Event を出すか」の判断なので分離方針に反しない）
##   - 金額処理は既存の DebugPanel._apply_event "PAY" 枝（apply_money(-amount)）のまま
##   - 専用 State は作らない（確定事項どおり単なる Event）
##   - thug 以外、または徴収日でない日は空配列
## STEP 17.5: GOOD/MISSに関わらず入る掛け合い（2行）。1行目のチンピラの台詞にPAYの効果を
##   乗せ、2行目の主人公の返しは効果無しのTEXTにする（GREETと同じ「1行1Event」の形）。
static func _customer_extra_events(customer_id: String) -> Array:
	if customer_id == "thug" and GameState.is_collection_day():
		return [
			{ "type": "PAY", "customer": "thug", "amount": 150,
				"text": "チンピラ「あ、そうだ。今月分」" },
			{ "type": "TEXT", "text": "主人公「食い終わってから言うなよ」" },
		]
	return []
