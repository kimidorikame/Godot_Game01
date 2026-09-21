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
## 「PREP という巨大なコード」は作らず、TEXT / PAY / ADD_ITEM / MARKET / REMOVE_ITEM の
## 並びだけで表現する。ここはデータのみ。PAY の amount / ADD_ITEM・REMOVE_ITEM の
## item・amount が「効果」を表し、実際の処理（apply_money / add_inventory /
## remove_inventory）は受け側 = DebugPanel._apply_event が行う。
## text は表示用でしかなく、状態は動かさない。
## 支払いのトーン: 市場 -80 淡々（毎日）/ 水場 -50 生活の愚痴（徴収日のみ）/
##   場所代 -150 理不尽（OPEN・thug 側、同じく徴収日のみ）。金額処理は3つとも apply_money(-x)。
## DESIGN.md 7.7: 市場を MARKET Event（"options" を持つ。ADJUSTと同じくEventRunnerは
##   型を問わずWAITING_INPUTで止まる）として挟む。食肉仲卸は今まで通り自動
##   （TEXT→PAY→ADD_ITEMがMARKETの前に並ぶだけ）。水場は市場滞在中に押せる
##   選択肢の1つになり、TEXTとしては並べない（受け側が直接処理する。詳細は
##   DebugPanel._visit_water_stall / _on_market_exit_pressed）。
## 具材の腐敗: spoiled は今朝PREPに入った瞬間に破棄された品目 id の配列（受け側が
##   GameState.discard_spoiled_inventory() で先に消して渡す）。あれば先頭に一言テキストを
##   1つ足す（データのみ。破棄自体はここでは行わない）。
## クズ野菜ベース: scraps_base は「ベース代（GameState.BASE_PRICE）を払えない」ので
##   食肉仲卸ではなく端材屋へ回る日か。受け側がPREPに入る瞬間に所持金を見て1回だけ決め、
##   ここへは引数で渡す（計器盤にも同じ値を出すため。ここで money を読むと、PREPの途中で
##   所持金が変わったときに表示とずれる）。違うのは冒頭の3つ（TEXT・会話・ADD_ITEM。
##   PAYなし）と、SET_SOUP の濃さ（1スタート）だけ。杯数・仕込みの流れは同じ。
static func prep_events(spoiled: Array = [], scraps_base: bool = false, reserve_lost: bool = false) -> Array:
	var events := []
	# 予備ベースの購入分が腐りきって捨てられた朝は、一言足す（破棄は受け側が先に行う）。
	if reserve_lost:
		events.append({ "type": "TEXT", "text": "予備ベースの購入分は傷みきったので捨てた。" })
	if not spoiled.is_empty():
		var names := PackedStringArray()
		for id in spoiled:
			names.append(Ingredients.name_for(str(id)))
		events.append({ "type": "TEXT",
			"text": "在庫を確かめる。傷みきった%sは捨てた。" % "・".join(names) })
	if scraps_base:
		# 値切る／譲ってもらう。食肉仲卸の「いつもの。80だ」の淡々としたトーンと対比させる。
		events.append_array([
			{ "type": "TEXT", "text": "荷捌き裏通りへ回る。半端市「拾味」。今日は財布が軽い" },
			{ "type": "TEXT", "text": "「すまん、持ち合わせが足りねえ」「……野菜くずなら持ってきな。金はいい」" },
			{ "type": "ADD_ITEM", "item": "soup_base", "amount": 1, "text": "萎れた野菜くずをひと抱え、譲ってもらった" },
		])
	else:
		events.append_array([
			{ "type": "TEXT", "text": "食肉売場へ来た" },
			{ "type": "PAY", "amount": GameState.BASE_PRICE,
				"text": "「いつもの。%dだ」" % GameState.BASE_PRICE },
			{ "type": "ADD_ITEM", "item": "soup_base", "amount": 1, "text": "鶏骨と手羽端を受け取った" },
		])
	# Day2（新人警官の初登場）：ベース入手の後・市場の前に、昼の市場の会話を挟む。要求タグ
	# （酸っぱい汁・噛める具）を仕入れの前に知らせるため。市場の enabled（day2_unlocked）とは
	# 無関係に、会話は必ず出る。日付は _market_options と同じく関数の中で直接読む。
	if GameState.day_count == 2:
		events.append_array(_talk("officer", _OFFICER_MARKET))
	events.append({ "type": "MARKET", "text": "（市場をぶらつく）",
		"options": _market_options(scraps_base) })
	# 仕込み: 在庫を減らす責務は REMOVE_ITEM のまま（鍋作成を混ぜない）。
	events.append({ "type": "REMOVE_ITEM", "item": "soup_base", "amount": 1,
		"text": "さて、仕込むか。鍋に放り込む" })
	# 共有鍋ができる（STEP 12）。ベースは今は鶏がらだしの1種類だけ（DESIGN.md 7.7：
	# 「骨と大根」から「鶏骨＋手羽端」に変更。IDはbone_broth/soup_baseのまま据え置き）。
	# 7.6: 残量（杯数）を Event が運ぶ。PAY の amount / REACT の sale と同じで、
	#   具体値は Event が持ち、適用は受け側（GameState.set_soup）が行う。
	# 7.6: 濃さ（仕込み時は3＝ちょうどいい）と、今夜使える水の回数も一緒に渡す。
	#   水の回数自体は市場（水場）に行ったかとは無関係に毎朝2回分（GameState定数）。
	#   水場で払うのは水道代（徴収日のみ）で、回数を増やす効果ではない。
	# クズ野菜ベース: 濃さ1スタート（既存の濃さ1のペナルティがそのまま効く）。base_id・tags は
	#   veg_scrap_broth / ["vegetal"] にして、計器盤の soup 行で1日中「クズ野菜の日」と読めるようにする
	#   （soupのtagsは判定に使っていない＝表示用。効果は濃さだけ）。
	if scraps_base:
		events.append({ "type": "SET_SOUP", "base_id": "veg_scrap_broth", "tags": ["vegetal"],
			"servings": GameState.SERVINGS_PER_BASE,
			"strength": 1,
			"water_doses": GameState.WATER_DOSES_PER_NIGHT,
			"text": "野菜くずを煮出した。薄い……。今日の鍋ができた（%d杯分）。" % GameState.SERVINGS_PER_BASE })
	else:
		events.append({ "type": "SET_SOUP", "base_id": "bone_broth", "tags": ["meaty"],
			"servings": GameState.SERVINGS_PER_BASE,
			"strength": 3,
			"water_doses": GameState.WATER_DOSES_PER_NIGHT,
			"text": "鶏の出汁が立ってきた。今日の鍋ができた（%d杯分）。" % GameState.SERVINGS_PER_BASE })
	return events


## 市場の選択肢（DESIGN.md 7.7）。"enabled" で今日押せるかをデータ側に持たせる
## （「今日どの店が開いているか」は日ごとに変わる事実なので、is_mob等と同じくデータ側）。
## 食肉仲卸・青果〜端材半端物の6店は2日目から解禁（DESIGN.md 7.7「他の区画は2日目から解禁」）。
##   どの店も実際に買える（各店の商品は produce_goods など <店のid>_goods 参照）。
##   食肉仲卸のベース購入はPREPの先頭で自動で済むが、ここでは追加購入の店として入れる。
##   >= 2 なので3日目以降も開いたまま（店ごとに解禁日を変える仕組みは対象外）。
## 水場は初日から常に押せる。
## "text" は訪問時のセリフ（DESIGN.md 7.7「支払いのトーン」表：水場＝生活の愚痴混じり）。
##   水場は市場外のEventとしては並べないので、この text をDebugPanel側が読んで表示する
##   （_visit_water_stall 参照）。
## 注意: この enabled は prep_events() が呼ばれた瞬間（＝PREPに入った瞬間）に固定される。
##   Event データは読むだけで書き換えない原則のため、MARKET画面を表示したまま
##   day_count が変わっても、その場では反映されない（次にPREPへ入り直すまで）。
## クズ野菜ベースの日（scraps_base）は、Day1だけ「訪問済み」の表示が食肉仲卸ではなく
##   端材半端物の側に付く（自動で済んだ店がグレーで押せない説明のため）。2日目以降は影響なし。
static func _market_options(scraps_base: bool = false) -> Array:
	var day2_unlocked: bool = GameState.day_count >= 2
	# 「（訪問済み）」は、Day1に自動で済んだ店が押せない理由の説明にだけ付ける。
	# 2日目以降は6店とも買い物のできる店なので、クズ野菜の日でも付けず、押せる
	# （貧しい日こそ端材屋の安い商品が要る。店には何度でも入れる）。
	var meat_label := "食肉仲卸"
	var scraps_label := "端材半端物"
	if not day2_unlocked:
		if scraps_base:
			scraps_label += "（訪問済み）"
		else:
			meat_label += "（訪問済み）"
	return [
		{ "id": "meat_wholesale", "label": meat_label, "enabled": day2_unlocked },
		{ "id": "produce",        "label": "青果",       "enabled": day2_unlocked },
		{ "id": "dry_goods",      "label": "乾物調味料", "enabled": day2_unlocked },
		{ "id": "tofu_noodles",   "label": "豆腐麺",     "enabled": day2_unlocked },
		{ "id": "seafood",        "label": "海鮮",       "enabled": day2_unlocked },
		{ "id": "scraps",         "label": scraps_label, "enabled": day2_unlocked },
		{ "id": "water",          "label": "水場",       "enabled": true,
			"text": "「今月分、払っとけよ」「はいはい、分かってる」" },
	]


## 永順青果の商品（DESIGN.md 7.7）。1回選ぶと1袋＝GameState.INGREDIENT_SERVINGS_PER_PURCHASE
## 杯分を買える（何度でも買える。所持金が足りなければ受け側がボタンを無効化する）。
## 価格はPRICING_SPEC.md 6章「安い例」の冬瓜=20を基準。苦瓜はPRICING_SPEC.md 7章では
## 調味料10杯分25だが、ここでは冬瓜と揃えて5杯分梱包に変更したための仮の半額（13）。
## §7の「10杯分」表記との食い違いはPRICING_SPEC.md側の追記が別途必要（今は保留）。
static func produce_goods() -> Array:
	return [
		{ "id": "winter_melon", "label": "冬瓜", "price": 20 },
		{ "id": "bitter_melon", "label": "苦瓜", "price": 13 },
	]


## 残りの店の商品（DESIGN.md 7.7）。<店のid>_goods の名前で produce_goods に揃える
## （DebugPanel._shop_goods の match のキーと一対一）。1回選ぶと INGREDIENT_SERVINGS_PER_PURCHASE
## 杯分を買える。価格は仮（PRICING_SPEC.md §6・§7の例とは食い違う決定値。ドキュメント側の追記は別途）。
## 「既存id」は初期在庫と同じ id で、市場での補充経路が増えるだけ（買い足すと品目全体の
## 補充日が更新される簡易仕様）。
static func meat_wholesale_goods() -> Array:
	return [
		{ "id": "offal",       "label": "モツ",   "price": 35 },
		{ "id": "cartilage",   "label": "軟骨",   "price": 40 },
		{ "id": "tendon_meat", "label": "すじ肉", "price": 40 },
		# 予備ベース（1周1回・購入分だけ期限あり）。在庫（inventory）には入れず、
		# 受け側が GameState.buy_reserve_base() で処理する。Day2から（市場の解禁と同じ）。
		{ "id": "reserve_base", "label": "予備ベース(1袋)", "price": GameState.BASE_PRICE },
	]


static func dry_goods_goods() -> Array:
	return [
		{ "id": "nam_prik_pao",   "label": "ナムプリックパオ",   "price": 25 },
		{ "id": "coconut_milk",   "label": "ココナッツミルク",   "price": 25 },
		{ "id": "herbal_sauce",   "label": "薬膳ナンプラーだれ", "price": 25 },
		{ "id": "pickled_lime",   "label": "塩漬けライム",       "price": 20 },
		{ "id": "dried_wood_ear", "label": "乾燥きくらげ",       "price": 30 },
	]


static func tofu_noodles_goods() -> Array:
	return [
		{ "id": "tofu",       "label": "豆腐", "price": 20 },
		{ "id": "rice_noodle", "label": "米麺", "price": 15 },
	]


static func seafood_goods() -> Array:
	return [
		{ "id": "shrimp",  "label": "海老",         "price": 60 },
		{ "id": "clam",    "label": "貝",           "price": 55 },
		{ "id": "fish_maw", "label": "魚の浮き袋", "price": 75 },
	]


static func scraps_goods() -> Array:
	return [
		{ "id": "broken_wrapper", "label": "割れた餃子皮", "price": 10 },
		{ "id": "meat_ball",      "label": "くず肉団子",   "price": 15 },
	]


## CLOSE の締めくくり（DESIGN.md 9章 STEP 9）。TEXT のみ・効果を持つ Event は入れない。
## 所持金・提供数は計器盤に出ているので、ここは「読ませて区切る」だけ。
## 凝った売上内訳・精算演出は入れない（今ある状態を見せる最小）。
## 最終日（GameState.FINAL_DAY）だけ、末尾に「（終了）」を1つ足す。条件は GameState.is_final_day()
## を中で読む（水道代の条件化・_market_options の day_count 判定と同じ既存パターン）。
static func close_events() -> Array:
	var events := [
		{ "type": "TEXT", "text": "看板の灯を落とす。" },
		{ "type": "TEXT", "text": "屋台を閉める。" },
		{ "type": "TEXT", "text": "本日の営業終了。売上と提供数は計器盤のとおり。" },
	]
	if GameState.is_final_day():
		events.append({ "type": "TEXT", "text": "（終了）" })
	return events


## OPEN の客の並び（DESIGN.md 9章 / 7.6）。STEP 6: 配達員1人 → STEP 7: 3人。
## STEP 17.5: normal_customer を granny（老婆）に差し替え。
## 7.6: モブ客 dock_workers（港湾労働者の一団）を追加。
##   チンピラと老婆を連続させ、老婆がチンピラの退店を見てから来る流れを保つ
##   （PRICING_SPEC.md 2章の接客順）。
## 7.6: フラットな配列をやめ、**時間帯で区切る**（宵の口 / 夜半 / 明け方）。
##   時間帯名と客リストを1つの辞書に同居させる（名前を別配列で並行管理しない）。
##   将来ここに「その時間帯のモブ人数」「時間帯の切り替わりテキスト」を足せる。
##   客の増減も時間帯の増減も、この関数の中だけで済む。
## 7.6: mob_count（その日のモブ人数。呼び出し側がOPEN開始時に1回だけ引いた値）が0なら
##   宵の口に dock_workers 自体を出さない（配達員は必ず出る＝スロットが空になることはない）。
static func customer_schedule(mob_count: int) -> Array:
	# Day2：宵の口に新人警官（＋モブ）だけ。夜半・明け方は客のいない時間帯（空配列）で、
	# OpenController._skip_finished_slots が読み飛ばす。場所代は Day1 だけなのでチンピラを
	# 外しても影響しない。Day1・Day3以降は下の従来の並びのまま。
	if GameState.day_count == 2:
		var evening_day2 := ["officer"]
		if mob_count > 0:
			evening_day2.append("dock_workers")
		return [
			{ "name": "宵の口", "customers": evening_day2 },
			{ "name": "夜半",   "customers": [] },
			{ "name": "明け方", "customers": [] },
		]
	var evening := ["delivery_man"]
	if mob_count > 0:
		evening.append("dock_workers")
	return [
		{ "name": "宵の口", "customers": evening },
		{ "name": "夜半",   "customers": ["thug"] },
		{ "name": "明け方", "customers": ["granny"] },
	]


## id がモブ客か（DESIGN.md 7.6）。自動閉店の判定などで、受け側が
## 「これより後に名前あり客が残っているか」を問い合わせるために公開する。
static func is_mob_customer(customer_id: String) -> bool:
	return bool(_customer_flavor(customer_id).get("is_mob", false))


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
## STEP 15/16: REACT に判定用のデータと反応textを持たせる（DESIGN.md 9.5 STEP 15・16）。
##   判定は受け側 = OpenController.judge_bowl が行う。反応textは書き換えず、
##   どれを見せるかは受け側が都度選ぶ（DebugPanel._current_reaction_text）。
## STEP 17.5: GREET は複数行の掛け合いを1行1Eventに分けて積む（テンポを出すため。
##   EventRunner/受け側は無改修で動く＝WAKEの起床TEXT3連続と同じパターン）。
## STEP 17.6: ADJUSTは3枠まで選べる形に変更（DESIGN.md 9.5 STEP17.6）。
##   「そのまま出す(none)」は削除。何も足さず提供したいときは、選ばずに
##   [入力完了]（提供）を押せばよい（DebugPanel側の変更のみで実現。ここには効果なし）。
##   options自体は全客共通なので _adjust_options() に括り出した。
##   判定は一致数による3段階になり、REACT は wanted_tags（配列）と
##   reactions（結果をキーにした反応textの辞書）を持つ。段階が増えても
##   reactions にキーを足すだけで済む形にしてある（favoriteの「とても好み」など）。
## 7.6: 1回の接客で複数杯出せるようにした（servings）。売上は 50×servings で、
##   値段はデータに書かずルール（GameState.PRICE_PER_SERVING）から出す。
##   is_mob はモブ客かどうか＝評判の増加量を受け側が切り替えるための印。
##   一団でも調理は1回・判定も1回（DESIGN.md 7.6「モブ客の仕様」）。
## 7.6: mob_count は dock_workers の人数（servings・台詞）にだけ使う。乱数は引かない
##   （引くのはOPEN開始時の1回だけ。ここで引くと customer_schedule と食い違う）。
static func customer_events(customer_id: String, mob_count: int = 0) -> Array:
	# 配達員だけは、同じ客へ3杯を1杯ずつ会話の合間に出す専用のEvent列（客ごとの分岐は
	# データ層のここだけ。受け側 DebugPanel には客IDを書かない）。
	if customer_id == "delivery_man":
		return _delivery_man_events()
	var flavor := _customer_flavor(customer_id, mob_count)
	var events := []
	for line in flavor["greet"]:
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	events.append({ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）",
		"options": _adjust_options() })
	events.append({ "type": "SERVE", "customer": customer_id, "text": "「はいよ、お待ち。」" })
	events.append({ "type": "REACT", "customer": customer_id,
		"reactions": flavor["reactions"], "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "servings": flavor["servings"],
		"is_mob": flavor["is_mob"],
		"sale": GameState.PRICE_PER_SERVING * int(flavor["servings"]) })
	events.append_array(_customer_extra_events(customer_id))
	return events


## 会話行（発話・ト書き）を、1行1Eventの GREET にして積む（既存の接客と同じ形）。
static func _talk(customer_id: String, lines: Array) -> Array:
	var events := []
	for line in lines:
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	return events


## 反応文：数行を改行でつないだ1つの文字列にする（reactions の形は従来どおり
## 「結果ごとの文字列配列」のまま。各結果1パターン）。
static func _lines_text(lines: Array) -> String:
	return "\n".join(PackedStringArray(lines))


## 配達員（阿強）の接客：同じ客に3杯を、会話の合間に1杯ずつ出す（本番用会話稿
## 「１日目_運び屋_1.md」）。1杯目・2杯目は阿強本人の分として個別に評価し、3杯目は
## 第八码頭の労働者への持ち帰り（評価なし）。客キューの上では退店まで1人の客のまま
## （客のEvent列を1本にするので、退店会話が終わるまで次の客へ進まない）。
##   - 各杯は ADJUST → SERVE → REACT。2杯目・3杯目の ADJUST は new_bowl:true で椀を新しくする
##   - 1杯目・2杯目の REACT：aggregate:true（鍋の消費と売上はその場で、評判と提供記録は
##     退店時に客1人分として1回だけ反映）。3杯目の REACT：judge:false を足す
##     （判定・反応・評判なし。鍋の消費と売上は通常どおり）
##   - 各杯 servings は1、売上は PRICE_PER_SERVING（合計150）
##   - 要求タグ・好物は旧 delivery_man のデータ（_customer_flavor）をそのまま使う
static func _delivery_man_events() -> Array:
	var id := "delivery_man"
	var flavor := _customer_flavor(id)
	var options := _adjust_options()
	var sale: int = GameState.PRICE_PER_SERVING * 1
	var events := []
	events.append_array(_talk(id, _DELIVERY_ARRIVAL))
	# 一杯目
	events.append({ "type": "ADJUST", "customer": id, "text": "（味を調える）", "options": options })
	events.append({ "type": "SERVE", "customer": id, "text": "（湯気の立つ椀を置く）" })
	events.append({ "type": "REACT", "customer": id, "servings": 1, "sale": sale,
		"reactions": _delivery_reactions_first(), "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "is_mob": false, "aggregate": true })
	events.append_array(_talk(id, _DELIVERY_AFTER_FIRST))
	# 二杯目
	events.append({ "type": "ADJUST", "customer": id, "text": "（味を調える）",
		"options": options, "new_bowl": true })
	events.append({ "type": "SERVE", "customer": id, "text": "（湯気の立つ椀を置く）" })
	events.append({ "type": "REACT", "customer": id, "servings": 1, "sale": sale,
		"reactions": _delivery_reactions_second(), "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "is_mob": false, "aggregate": true })
	events.append_array(_talk(id, _DELIVERY_AFTER_SECOND))
	# 三杯目（持ち帰り・評価なし）
	events.append({ "type": "ADJUST", "customer": id,
		"text": "（持ち帰り用。辛さ控えめ、豆腐多め）", "options": options, "new_bowl": true })
	events.append({ "type": "SERVE", "customer": id, "text": "（店主は蓋つきの容器を袋へ入れる）" })
	events.append({ "type": "REACT", "customer": id, "servings": 1, "sale": sale,
		"reactions": {}, "is_mob": false, "judge": false, "aggregate": true })
	events.append_array(_talk(id, _DELIVERY_EXIT))
	return events


static func _delivery_reactions_first() -> Dictionary:
	return {
		"GREAT": [_lines_text([
			"店主「ほら。辛口、力の出るやつ。豆腐も入れといた」",
			"（配達員は椀を覗き込み、一瞬箸を止める）",
			"配達員「……豆腐まで入ってる。覚えてたのか」",
			"配達員「辛いのに喉ごしが優しい。今日一番の当たりだ」",
			"店主「たまには当てないとな」",
		])],
		"GOOD": [_lines_text([
			"店主「ほら。辛口、力の出るやつ」",
			"（配達員は豆腐を崩し、湯気ごとスープをすすり込む）",
			"配達員「……っ、辛。いい。舌が痛いと、まだ起きてるって分かる」",
			"店主「確認方法が原始的だな」",
			"配達員「最新式の上着は、さっき電池が切れた」",
		])],
		"OK": [_lines_text([
			"店主「ほら。辛口だ」",
			"（配達員は一口すすり、少し考えてからもう一口飲む）",
			"配達員「悪くない。もう少し腹に来ると、走れそうなんだけどな」",
			"店主「走る前に噛め」",
			"配達員「噛む時間も料金に入ってる？」",
		])],
		"BAD": [_lines_text([
			"店主「できたぞ」",
			"（配達員は一口すすり、眠そうな目をさらに細める）",
			"配達員「これは……眠気と仲良くできそうな味だな」",
			"店主「穏やかな夜になる」",
			"配達員「俺が道路で寝なければな。次はちゃんと辛くしてくれ」",
		])],
	}


static func _delivery_reactions_second() -> Dictionary:
	return {
		"GREAT": [_lines_text([
			"店主「二杯目。豆腐、また入れといた」",
			"配達員「気づいてたのか」",
			"店主「一杯目、黙って空にしてただろ」",
			"配達員「一杯目よりうまい。こっちが正解だったんだな」",
			"店主「二回当てれば実力だ」",
		])],
		"GOOD": [_lines_text([
			"店主「二杯目。今度はこぼすなよ」",
			"配達員「一杯目よりうまく感じる」",
			"店主「座ったからだ」",
			"配達員「椅子も具に数えるのか？」",
		])],
		"OK": [_lines_text([
			"店主「二杯目だ」",
			"配達員「今度は走れる味になった」",
			"店主「さっきは？」",
			"配達員「歩ける味」",
		])],
		"BAD": [_lines_text([
			"店主「二杯目だ」",
			"配達員「……店主。俺、何か怒らせた？」",
			"店主「心当たりが多い顔だな」",
			"配達員「三杯目は俺のじゃないから、そっちは頼むぞ」",
		])],
	}


## 来店〜一杯目の注文（会話稿「登場・一杯目の注文」）。
const _DELIVERY_ARRIVAL := [
	"（雨除けのビニール幕が外から持ち上がる。甲高いモーター音が途切れ、配達員が濡れた改造キックボードを屋台の脇へ滑り込ませる）",
	"配達員「まだやってる？」",
	"店主「鍋が見えるなら、やってるよ」",
	"配達員「よかった。辛くて、腹に力が入るやつ。一杯」",
	"店主「座って息を整えてから言え」",
	"配達員「座ったら寝る。立ったままでいい」",
	"（大きな保冷バッグを椅子へ下ろす。左脚が小さく跳ね、配達員は膝裏の古い接続端子を拳で軽く叩く）",
	"店主「脚、どうかしたか」",
	"配達員「古い部品が挨拶しただけ。先に飯」",
	"店主「どのくらい辛くする？」",
	"配達員「眠気が逃げ出すくらい。肉っぽい具も欲しい」",
	"店主「豆腐は？」",
	"配達員「あるなら入れて。辛い汁を吸った豆腐は裏切らない」",
	"店主「明日の腹は裏切るかもしれないぞ」",
	"配達員「明日の俺は、明日の俺が面倒を見る」",
	"店主「今日のお前は、ずいぶん無責任だな」",
	"配達員「今日の俺はもう限界なんだよ」",
]

## 一杯目の共通会話（料理の結果に関係なく表示。会話稿「一杯目・共通会話」）。
const _DELIVERY_AFTER_FIRST := [
	"（胸元の表示は消えているが、保冷バッグの管理番号だけが明るく点滅している）",
	"店主「Kの四一七二」",
	"配達員「読むな読むな。人を荷物みたいに呼ぶやつがいるんだ」",
	"店主「会社もそう呼ぶのか？」",
	"配達員「会社はもっと丁寧だよ。“稼働中の四一七二番”って呼ぶ」",
	"店主「丁寧だな」",
	"配達員「だろ？　人権が二文字ぶん増えてる」",
	"（端末から短い通知音が鳴る）",
	"端末音声「休憩を検出しました。次回評価への影響はありません」",
	"配達員「ほらな。休んでも怒らない、優しい会社だ」",
	"店主「影響はありません、とわざわざ言う会社は信用できない」",
	"配達員「新人の頃は信じてたよ」",
	"店主「今は？」",
	"配達員「影響がないのは“次回評価”だけだと気づいた」",
	"店主「その次には？」",
	"配達員「きっちり響く」",
	"店主「優しいな」",
	"配達員「だろ？」",
	"店主「今日は何件運んだ」",
	"配達員「二十……」",
	"（指を折り始め、途中でやめる）",
	"配達員「たくさん」",
	"店主「数えられないくらいか」",
	"配達員「数えると脚が重くなる」",
	"店主「さっきの部品のせいじゃないのか」",
	"配達員「左の膝裏から足首まで、中古の反射補助器が入ってる。避けろと思ってから、足が動くまでを少し縮める」",
	"店主「最新型？」",
	"配達員「製造年を聞いたら、売った親父が値段を上げるって言った」",
	"店主「年代物か」",
	"配達員「ブラックマーケットじゃ“実績がある”と言う」",
	"店主「役に立つのか？」",
	"配達員「今日、二十七階まで階段で上がった」",
	"店主「エレベーターは？」",
	"配達員「住民専用。運び屋が使うと床が汚れるらしい」",
	"店主「何分かかった」",
	"配達員「予定より三分遅れた。アプリによると、標準的な成人男性なら一分四十秒だそうだ」",
	"店主「標準的な成人男性は飛べるんだな」",
	"配達員「最新型はな」",
	"（配達員は椀を空にして、ようやく椅子へ座る）",
	"配達員「もう一杯いける？」",
	"店主「金は？」",
	"配達員「ある。今夜は危険手当がついてる」",
	"店主「景気のいい話だ」",
	"配達員「景気が悪い場所ほど、手当は高い」",
	"店主「同じのでいいか？」",
	"配達員「同じ。今度は座って食う」",
]

## 二杯目の共通会話（第八码頭の情報はここ。料理の結果に関係なく必ず表示。
## 会話稿「二杯目・共通会話」。持ち帰りの注文まで）。
const _DELIVERY_AFTER_SECOND := [
	"店主「危険手当は、どこへ行った分だ」",
	"配達員「第八码頭。夜勤が止まってる」",
	"店主「ストか」",
	"配達員「ニュースは“交渉中”って言ってたろ」",
	"店主「現場では違う？」",
	"配達員「門の前に百人。中に警備機が三十台。あれを交渉って呼ぶなら、ずいぶん声のでかい話し合いだ」",
	"店主「お前、そこを走ってきたのか」",
	"配達員「横の搬入口からな」",
	"店主「何を運んだ」",
	"配達員「密封箱。依頼票には“生活必需品”」",
	"店主「便利な言葉だな」",
	"配達員「箱には小さく、“第三クレーン制御部品”って書いてあった」",
	"店主「止まっている荷役を動かす部品か」",
	"配達員「たぶん」",
	"店主「ストを止める側の荷物だな」",
	"配達員「分かってる」",
	"店主「誰かに止められたか」",
	"配達員「門にいたおっさんが、キックボードの前へ出た」",
	"店主「轢いたのか？」",
	"配達員「俺を何だと思ってる？」",
	"店主「信号で、だいたい止まる男」",
	"配達員「止まったよ。急ブレーキで補助器がエラーを吐いて、左足だけ板から離れなかった」",
	"店主「それで？」",
	"配達員「俺は転んだ。板は柵に刺さって、前輪の軸が曲がった」",
	"店主「荷物は？」",
	"配達員「背中。中身より俺の肋骨の方が柔らかかった」",
	"店主「その男は？」",
	"配達員「前輪を蹴って戻した。脚の震えが止まるまで、板も押さえてた」",
	"店主「自分で止めたキックボードを？」",
	"配達員「“お前を壊しても港は止まらん”って怒りながら」",
	"店主「それでも運んだのか」",
	"配達員「……運んだ」",
	"（端末の雨音だけが続く。配達員は椀の中の豆腐を箸で割る）",
	"配達員「俺が断っても、別の番号に依頼が飛ぶ」",
	"店主「便利な言葉だな」",
	"配達員「分かってるって」",
	"店主「なら、説教はいらないな」",
	"配達員「スープ屋って、客の身の上話を聞いて諭すんじゃないの？」",
	"店主「追加料金を払うなら」",
	"配達員「いくら？」",
	"店主「お前の罪悪感次第」",
	"配達員「じゃあ高そうだ」",
	"店主「自覚はあるんだな」",
	"（配達員は残ったスープを飲み切る）",
	"配達員「持ち帰りを一つ頼む」",
	"店主「まだ食うのか」",
	"配達員「俺のじゃない。門のおっさんの分」",
	"店主「好みは聞いたのか？」",
	"配達員「聞いてない。咳してたから、辛さは今のより控えめ。豆腐を多めにしてくれ」",
	"店主「外したら？」",
	"配達員「俺が飲む」",
	"店主「無駄がないな」",
	"配達員「運び屋だからな。行き先のない荷物は作らない」",
]

## 持ち帰りの提供後〜退店（会話稿「三杯目・提供と退店」。SERVE の後）。
const _DELIVERY_EXIT := [
	"店主「持ち帰り。傾けるなよ」",
	"配達員「保冷バッグに温かいものを入れていいのかな」",
	"店主「仕事の荷物とは分けろ」",
	"配達員「分かってる。こっちは人間用の荷物だ」",
	"店主「お前が言うと妙だな」",
	"配達員「会社の分類だと、俺も備品だからな」",
	"店主「そういえば、名前を聞いてなかった」",
	"配達員「番号を読んだだろ」",
	"店主「番号じゃなくて」",
	"配達員「阿強って呼ばれてる」",
	"店主「本名か？」",
	"阿強「仕事中は、それが本名」",
	"店主「仕事じゃない時は？」",
	"阿強「仕事じゃない時ができたら教える」",
	"（端末から依頼通知が鳴る）",
	"端末音声「高優先度依頼。第八码頭経由。追加報酬が設定されています」",
	"店主「行くのか？」",
	"阿強「行くよ。届け物がある」",
	"店主「会社の方は？」",
	"阿強「そっちは、その後考える」",
	"店主「評価に響くぞ」",
	"阿強「影響がないのは“次回評価”だけらしいからな」",
	"店主「丁寧な会社だ」",
	"阿強「人権が二文字ぶん増えてる」",
	"店主「三杯で百五十」",
	"（阿強は端末をかざして支払いを済ませる）",
	"阿強「いつか、自分のロードバイクを買う」",
	"店主「急だな」",
	"阿強「会社の番号がついてない、俺の車体だ。道も値段も自分で決める」",
	"店主「それまでは、その板か」",
	"阿強「こいつも払い終われば俺のだよ」",
	"店主「いつ終わる」",
	"阿強「聞くな」",
	"（阿強は保冷バッグを背負い、スープの袋だけを胸の前へ固定する）",
	"阿強「門のおっさんがいなかったら、これ俺が飲むから」",
	"店主「届け先を間違えるなよ」",
	"阿強「行き先のない荷物は作らないって言ったろ」",
	"店主「自分の行き先は？」",
	"阿強「それはまだ配送中」",
	"（左脚の具合を確かめるように一度だけ地面を蹴る。改造キックボードの甲高いモーター音が、雨の通りへ消えていく）",
	"店主「……代金はちゃんと届いたな」",
	"（端末には、受取済みの表示と小さな手数料控除が並んでいる）",
	"店主「こっちも丁寧な会社だ」",
]


## 新人警官（Day2で初登場・表示名「警官」）。本番用会話稿「Day2_新人警官_1.md」。
## 昼の市場（PREP。ベース入手の後・市場の前）と、夜の来店（宵の口）の2部構成。
##   - 要求タグは昼の市場の会話で先に出す（仕入れの前に知る必要がある）。好物（米麺）は夜の来店会話で出す。
##   - 夜は通常の1杯客（GREET → ADJUST → SERVE → REACT → 共通会話 → 会計・退店）。
##     評価（GREAT/GOOD/OK/BAD）で分岐するのは REACT の反応だけで、その後の共通会話と
##     会計・退店は、どの結果でも同じ内容を出す。
##   - 「西側は……」は任意の違和感で、Day2時点でスパイと断定できる材料にしない。
##   - 他のメイン客の、その日の具体的な行動は台詞で確定させない（再来店客との順番に依存させない）。
##   - 昼の市場の会話の冒頭のト書きは、場面を始めるために足したもの（原案に無い）。
##
## 昼・市場（PREP）。
const _OFFICER_MARKET := [
	"（市場の人混みの中、制服の若い警官が地図を手に立ち止まっている）",
	"警官「すみません。先輩とはぐれてしまって。市場裏の搬入口は、どちらですか」",
	"店主「どっちの搬入口だ？」",
	"警官「……二つあるんですか」",
	"店主「表札のある方と、みんなが搬入口と呼ぶ方がある」",
	"警官「先輩が言ったのは、どっちでしょう」",
	"店主「その先輩、ここに来て長いか？」",
	"警官「長いです」",
	"店主「じゃあ表札のない方だ。俺も何年も、そっちへ続く通りの角で夜に屋台をやってる」",
	"警官「……夜……あの、そちらに寄っても？」",
	"店主「何が食いたい？」",
	"警官「酸っぱい汁。あと、ちゃんと噛めるものが入っているとうれしいです」",
	"店主「そうか、用意しとくよ」",
]

## 夜・来店（宵の口）。REACT の前の GREET。
const _OFFICER_ARRIVAL := [
	"（市場の搬入が終わり、通りの角に屋台の灯りがつく。人波の向こうから、昼間の警官が現れる。制服の肩には、巡回でついた細かな埃が残っている）",
	"警官「こんばんは。ここで合っていました」",
	"店主「表札のない方には着けたのか」",
	"警官「はい。先輩とも合流できました。ありがとうございました」",
	"店主「それはよかった。またはぐれたかと思った」",
	"警官「今は休憩です。はぐれたわけではありません」",
	"店主「そういうことにしておこう」",
	"警官「本当です。休憩に入る前に、先輩にこの店へ来ると伝えました」",
	"店主「行き先の報告まで必要なのか」",
	"警官「昼に私を捜したので、次からは言っておけと」",
	"店主「なら、先輩には見つかりやすい店だな」",
	"警官「道の名前は、どう伝えればよかったんでしょう」",
	"店主「市場横の角。鍋の匂いがする方」",
	"警官「後半は地図に書けませんね」",
	"店主「地図に載ってない道でも来られただろ」",
	"（警官は椅子に腰を下ろしかけ、制服の裾を直してから座る）",
	"店主「座っていいぞ。そこは検問所じゃない」",
	"警官「……はい。昼の注文、覚えていますか」",
	"店主「酸っぱい汁。あと、ちゃんと噛めるもの」",
	"警官「覚えていたんですね」",
	"店主「朝から仕入れを考えさせられたからな」",
	"警官「すみません。無理な注文でしたか」",
	"店主「材料を見てから言え。麺は好きか？」",
	"警官「好きです。あれば、少し入れてください」",
	"店主「注文の多い新人だ」",
	"警官「昼間は道まで聞いています。すみません」",
	"店主「勘定に道案内代は入れない。腹の具合だけ教えてくれ」",
	"警官「昼から立ちっぱなしで。さっぱりした汁がいいんですけど、噛まずに飲み終わるのも寂しくて」",
	"店主「分かった。靴じゃなく、腹が仕事したがってるんだな」",
	"警官「靴ももう少し頑張ってほしいです」",
]

## 提供後・共通会話（料理の結果に関係なく必ず表示）。
const _OFFICER_AFTER := [
	"（警官は椀を両手で包む。屋台の外では荷車が一台、車の列を避けて細い通りへ曲がっていく）",
	"店主「今日は朝から、あんなのばかりだ」",
	"警官「荷車ですか」",
	"店主「大通りを通れないから、みんな横の路地へ来る。俺の仕入れも遅れた」",
	"警官「第八码頭の周辺で検問が始まりました。市場へ来る車も迂回しています」",
	"店主「ここの検問は、お前の先輩の持ち場か？」",
	"警官「市場の出入口は交代で見ています。港の方は別の班です」",
	"店主「場所を聞きに来た時は、まだ地図も怪しかったぞ」",
	"警官「先輩の言う『搬入口』と、標識の『搬入口』が違うとは思わなくて」",
	"店主「一年もここを歩けば覚える」",
	"警官「一年かかりますか」",
	"店主「俺はもっとかかった。自分の屋台を置く角だけ先に覚えた」",
	"警官「先輩は、地図を見ずに道の向こうの店まで言い当てます」",
	"店主「見ずに済むまで間違えたんだろ」",
	"警官「そう言ってもらえると助かります」",
	"（外で短いクラクションが鳴る。警官は一瞬そちらを見るが、立ち上がらずに椀へ視線を戻す）",
	"店主「休憩中なんだろ」",
	"警官「はい。今のは私の持ち場ではありません」",
	"店主「真面目だな」",
	"警官「見てから、そう言えるようにしています」",
	"店主「それならいい」",
	"警官「……昼、店主さんが道を教えてくれた時、先輩の顔を知っているのかと思いました」",
	"店主「知らないよ。ここを長く歩いてる人間なら、表札より通りの呼び名で話すからな」",
	"警官「私は表札だけ見ていました」",
	"店主「これから両方見りゃいい」",
	"警官「そうします。今日も、検問の地図では真っすぐな道が、実際は荷車で詰まっていました」",
	"店主「紙の上なら荷車は腹も減らさない」",
	"警官「運転手の方には、あとどれくらい待つか何度も聞かれました」",
	"店主「答えられたか？」",
	"警官「分からない、とだけ。先輩は、分からないことを分かったふりするなと」",
	"店主「いい先輩だな」",
	"警官「はい。待たされる方には、いい答えじゃありませんが」",
	"（警官は残りの汁を飲む。外の車列はまだ動いていない）",
	"店主「明日も、こんな調子か」",
	"警官「西側は……」",
	"（警官は店主の顔を見て、短く息をつく）",
	"警官「すみません。明日の検問について、私からは何とも言えません」",
	"店主「西側、とは言ったな」",
	"警官「東があれだけ混めば、西へ回る車も増えると思って。推測です」",
	"店主「そうか。仕入れは早めに済ませた方がよさそうだ」",
	"警官「……決まっていないことを、決まったように話すべきではありませんでした」",
	"店主「昼に道を教えたんだ。お前の言い間違いまで仕入れないよ」",
	"警官「助かります」",
	"店主「でも、道は覚えろ。また先輩とはぐれたら、うちの客が増える」",
	"警官「それは困りますか」",
	"店主「払ってくれるなら困らない」",
]

## 会計・退店（共通会話の後。料理の結果に関係なく同じ内容）。
const _OFFICER_PAYMENT := [
	"（警官は椀を返し、代金を端末で払う）",
	"警官「一杯、五十で合っていますか」",
	"店主「合ってる。道案内は無料だ」",
	"警官「次は、自分で来られると思います」",
	"店主「次があるのか」",
	"警官「……迷わずに来られたら」",
	"店主「条件が厳しいな」",
	"警官「夜なら、鍋の匂いもあります」",
	"店主「地図に書けない目印を覚えたな」",
	"（警官は帽子をかぶり直す。屋台を離れる前に、市場の方角を一度確かめる）",
	"警官「ごちそうさまでした。おやすみなさい」",
	"店主「まだ仕事だろ」",
	"警官「はい。言ってみたかっただけです」",
	"店主「次は仕事が終わってから言いな」",
	"（警官は小さく笑って頭を下げ、車列とは別の通りへ歩いていく）",
]

## 警官の反応文：結果ごとに短い会話を改行でつないだ1つの文字列にし、各結果の配列は要素数1
## （配達員と同じ形。judge_bowl が選ぶ reaction_variant は pool[variant % pool.size()] で
## 要素1の配列でも安全に0番目を指す）。
static func _officer_reactions() -> Dictionary:
	return {
		"GREAT": [_lines_text([
			"（警官は麺をひと口すすり、続いて具を噛む。背筋を伸ばしたまま、目だけ少し丸くなる）",
			"警官「……あ。麺まで入れてくれたんですね」",
			"店主「少し、って言われたから少しだけな」",
			"警官「酸っぱくて、噛むものもあって。昼に言った通りです」",
			"店主「今なら道案内代も払えるか？」",
			"警官「追加料金のある店でしたか」",
			"店主「冗談だよ」",
		])],
		"GOOD": [_lines_text([
			"（警官はひと口飲み、もうひと口、今度は具を噛む）",
			"警官「おいしいです。昼に思っていたより、ずっと落ち着きます」",
			"店主「目が覚める味の方がよかったか」",
			"警官「休憩中なので、今はこっちがいいです」",
		])],
		"OK": [_lines_text([
			"（警官は椀を少し持ち上げて、湯気を吸う）",
			"警官「ありがとうございます。温かいものを座って食べられるだけで、かなり違います」",
			"店主「注文には、少し外れたか」",
			"警官「少し。でも、ちゃんと一杯です」",
		])],
		"BAD": [_lines_text([
			"（警官は一口飲み、言葉を選んでから椀を置く）",
			"警官「……すみません。昼、私の伝え方が曖昧でしたね」",
			"店主「料理したのは俺だ。謝らなくていい」",
			"警官「じゃあ、正直に。今日はお願いしたものとは違いました」",
			"店主「それは覚えとく」",
		])],
	}


## Day1開始時の初期在庫（DESIGN.md 7.7）。塩漬けライム・苦瓜は含めない
## （苦瓜は市場で買って初めて手に入る、という導線を保つため。定義自体はIngredientsに残したまま）。
## 調味料3種と具材4種で数量に差をつける：
##   調味料（少量で効く・味付け的な使い方）は多め＝各10個
##   具材（実際の食材として消費される）は少なめ＝各4個。初日から在庫を気にする場面を作る
## soup_base（食肉仲卸のベース）はここに含めない＝ADJUSTの対象外の別枠。
static func initial_inventory() -> Dictionary:
	return {
		"nam_prik_pao": 10, "coconut_milk": 10, "herbal_sauce": 10,
		"offal": 4, "meat_ball": 4, "tofu": 4, "broken_wrapper": 4,
	}


## ADJUSTボタンの表示文言。id→ラベルのみで、
## 在庫の有無・個数は _adjust_options() 側（GameState.inventory）が決める。
## OptionsRow（横並び）に収まるよう、「を入れる」は付けず名前だけにしている。
## pickled_lime・bitter_meronのように今は初期在庫に無い（＝市場等で買わないと出てこない）
## idの分も、買った瞬間ラベル無しにならないよう先に用意しておく。
const _ADJUST_LABELS := {
	"nam_prik_pao": "ナムプリックパオ", "coconut_milk": "ココナッツミルク",
	"pickled_lime": "塩漬けライム", "herbal_sauce": "薬膳ナンプラーだれ",
	"bitter_melon": "苦瓜", "offal": "下処理したモツ",
	"meat_ball": "くず肉団子", "tofu": "豆腐",
	"broken_wrapper": "割れた餃子皮", "winter_melon": "冬瓜",
	"cartilage": "軟骨", "tendon_meat": "すじ肉", "dried_wood_ear": "乾燥きくらげ",
	"rice_noodle": "米麺", "shrimp": "海老", "clam": "貝", "fish_maw": "魚の浮き袋",
}


## ADJUSTの選択肢（DESIGN.md 9.5 STEP17.6 → 7.7で在庫連動に変更）。
## 全客共通なのでここに1箇所だけ置く。GameState.inventory にある id だけを出す
## （＝在庫が選択肢を決める）。remove_inventory は0以下でキーごと削除する仕様なので、
## 辞書に残っている＝在庫1個以上、のチェックは不要。
static func _adjust_options() -> Array:
	var options := []
	for id in GameState.inventory:
		if id == "soup_base":   # 鍋のベースはADJUSTの対象外
			continue
		# 腐敗: 3日目の傷んだ具材は注記を付ける（使えるが判定で-1段階）。
		# 日数は夜の間に変わらないので、接客開始時に組み立てる既存の扱いのままでよい。
		var label: String = _ADJUST_LABELS.get(id, str(id))
		if GameState.is_damaged(id):
			label += "(傷)"
		options.append({ "id": id, "label": label })
	return options


## 客ごとに変わる差分だけ（売上は DESIGN.md 6章の Day1 台本準拠：45 / 40 / 55）。
## STEP 17.5: greetは複数行の配列。
## STEP 17.6: wanted_tags は「味の軸＋具の軸」の2つ（DESIGN.md 9.5 STEP17.6）。
##   会話の中に両方の手がかりを置く（例：配達員＝辛くしてくれ／疲れて眠い → HOT + POWER）。
##   reactions は判定結果をキーにした辞書。各段階2パターンで、どちらを出すかはランダム。
##   favorite は好物の具材id（1つ）。椀に入っていれば評価が1段上がる（クリティカル）。
##   本来はレア食材（たまにしか売っていない／高い）にする想定だが、今は検証用に
##   Day1の在庫から選んだ仮設定。いずれも wanted_tags と軸が重ならない具材にしてあり、
##   一致数と favorite の効果を分けて確認できる（GREATには3枠すべてが要る）。
##   TODO: BAD / GREAT の文言は仮。GOOD/OK は STEP17.5 の既存文言をそのまま割り当てている。
## 未知 id は無音・売上0・wanted_tags 空（＝一致0なので常に BAD）でフォールバック。
## mob_count は dock_workers の人数だけに効く（is_mob_customer のように is_mob しか
## 読まない呼び出しは省略してよい）。
static func _customer_flavor(customer_id: String, mob_count: int = 0) -> Dictionary:
	match customer_id:
		"delivery_man":
			# 配達員は customer_events が専用の Event 列（_delivery_man_events）を返す。
			# ここに残すのは、is_mob_customer が読む is_mob と、_delivery_man_events が読む
			# 要求タグ・好物だけ（greet・reactions・servings は使わない＝持たない）。
			return { "is_mob": false,
				"wanted_tags": ["HOT", "POWER"], "favorite": "tofu" }
		"dock_workers":
			# モブ客（DESIGN.md 7.6）。一団まとめて1杯作り、判定も1回。
			# 会話は一言の要望だけ。favorite は持たない＝GREAT は出ない
			# （個人の好物は「その人を知っているから分かる」もので、一見の集団には無い）。
			return { "greet": [
					"（港湾労働者が%d人、まとめて腰を下ろす）" % mob_count,
					"労働者「%dつ頼む。荷揚げで腕が上がらねえ」" % mob_count,
					"労働者「辛いのを、力の出るやつで。景気づけだ」",
				],
				"reactions": {
					"GOOD": [
						"一団「効くなァ！ よし、もうひと踏ん張りいけるぞ」",
						"一団、汗をかきながら黙って椀を空にした。",
					],
					"OK": [
						"一団「まあ、こんなもんか」",
						"労働者「腹には入った。次はもう少し効かせてくれ」",
					],
					"BAD": [
						"労働者「……おい、これで一杯50は取りすぎだろ」",
						"一団、顔を見合わせて半分残した。",
					],
				},
				"servings": mob_count, "is_mob": true,
				"wanted_tags": ["HOT", "POWER"], "favorite": "" }
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
				"reactions": {
					"GREAT": [
						"チンピラ「……肉団子。おまえ、俺の好きなもん覚えてやがるな」",
						"チンピラ「……悪くねえ。今日は兄貴の話はやめておくか」",
					],
					"GOOD": [
						"チンピラ「……そう、これだ」",
						"チンピラ「はー……うめ、腹に刺さらねえ」",
					],
					"OK": [
						"チンピラ「………だから、刺激のあるのはやめろって言っただろ」",
						"チンピラ「あー………まぁいいや」",
					],
					"BAD": [
						"チンピラ「……おい。胃に穴が空いたらどうしてくれる」",
						"チンピラ、途中で箸を置いた。",
					],
				},
				"servings": 1, "is_mob": false,
				"wanted_tags": ["MELLOW", "GENTLE"], "favorite": "meat_ball" }
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
				"reactions": {
					"GREAT": [
						"老婆「……あんた、モツを入れたね。あの診療所の汁も、これが入ってたんだよ」",
						"老婆「ああ、思い出した。この味だ。長生きしてみるもんだねえ」",
					],
					"GOOD": [
						"老婆「そう、これだよ。塩気の奥から、草の根の匂いが戻ってくる」",
						"老婆「苦いだけの薬より、こっちの方がよほど身体に効くねえ」",
					],
					"OK": [
						"老婆「これはこれで悪くない。でも、今夜欲しかったのとは違うね」",
						"老婆「舌じゃなく、古い骨まで温めてくれる味が欲しかったんだけどね」",
					],
					"BAD": [
						"老婆「……年寄りの腹には、ちょいと寂しいねえ」",
						"老婆、半分ほど残して椀を置いた。",
					],
				},
				"servings": 1, "is_mob": false,
				"wanted_tags": ["SAVORY", "FILLING"], "favorite": "offal" }
		"officer":
			# 新人警官（Day2で初登場。表示名「警官」）。通常の1杯客。要求タグ SOUR + BITE、好物は米麺。
			# 米麺（FILLING）だけでは要求タグに一致しない＝一致0なら好物が入っていてもBAD
			# （好物は一致数が1以上のときのボーナス）。会話稿・反応文は上の _OFFICER_* を参照。
			return { "greet": _OFFICER_ARRIVAL,
				"reactions": _officer_reactions(),
				"servings": 1, "is_mob": false,
				"wanted_tags": ["SOUR", "BITE"], "favorite": "rice_noodle" }
		_:
			return { "greet": ["客「……。」"],
				"reactions": {
					"GREAT": ["客、無言。", "客、無言。"],
					"GOOD": ["客、無言。", "客、無言。"],
					"OK": ["客、無言。", "客、無言。"],
					"BAD": ["客、無言。", "客、無言。"],
				},
				"servings": 0, "is_mob": false, "wanted_tags": [], "favorite": "" }


## REACT の後ろに差し込む客ごとの追加 Event（DESIGN.md 4章「pay を1つ挿すだけ」）。
## STEP 8: チンピラの場所代。Day2 の分岐テスト: 「徴収日のみ」に条件化する。
##   - 徴収日の判定は GameState.is_collection_day()（データ関数が事実を読んで出し分け。
##     処理の埋め込みではなく「どの Event を出すか」の判断なので分離方針に反しない）
##   - 金額処理は既存の DebugPanel._apply_event "PAY" 枝（apply_money(-amount)）のまま
##   - 専用 State は作らない（確定事項どおり単なる Event）
##   - thug 以外、または徴収日でない日は空配列
## STEP 17.5: 判定結果に関わらず入る掛け合い（2行）。1行目のチンピラの台詞にPAYの効果を
##   乗せ、2行目の主人公の返しは効果無しのTEXTにする（GREETと同じ「1行1Event」の形）。
## "kind": "rent" は、この PAY が場所代であることを示す印（DebugPanel._apply_event が
##   GameState.mark_rent_paid() を呼ぶかどうかの判定に使う。CURRENT_SPEC.md §11
##   「未解決：閉店で場所代を避けられる」の直し方の一部）。
static func _customer_extra_events(customer_id: String) -> Array:
	# 新人警官：評価の結果に関係なく、REACT の後に同じ共通会話と会計・退店を出す（PAYは無い＝
	# 会計は台詞だけ。売上は REACT の sale で反映済み）。
	if customer_id == "officer":
		return _talk("officer", _OFFICER_AFTER + _OFFICER_PAYMENT)
	if customer_id == "thug" and GameState.is_collection_day():
		return [
			{ "type": "PAY", "customer": "thug", "amount": GameState.RENT_PRICE, "kind": "rent",
				"text": "チンピラ「あ、そうだ。今月分」" },
			{ "type": "TEXT", "text": "主人公「食い終わってから言うなよ」" },
		]
	return []
