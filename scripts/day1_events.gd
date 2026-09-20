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
static func prep_events(spoiled: Array = [], scraps_base: bool = false) -> Array:
	var events := []
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
				"reactions": {
					"GREAT": [
						"配達員「……なんだこれ、豆腐まで入ってる。おまえ、覚えててくれたのか」",
						"配達員「辛いのに喉ごしが優しい。これは……今日一番の当たりだな」",
					],
					"GOOD": [
						"配達員「っうっま、よし！来た来た！ 腹の中で火がついた。これなら数か所行けそうだ」",
						"配達員「これなら帰り道までは寝ずに済みそうだ」",
					],
					"OK": [
						"配達員「うまいけど、今日はもの足りないな」",
						"配達員「もっと一発、殴ってくるようなのが欲しかった」",
					],
					"BAD": [
						"配達員「……悪いな、これじゃ目が覚めねえや」",
						"配達員「腹には入ったけど、まだ瞼が重いままだ」",
					],
				},
				"servings": 3, "is_mob": false,
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
static func _customer_extra_events(customer_id: String) -> Array:
	if customer_id == "thug" and GameState.is_collection_day():
		return [
			{ "type": "PAY", "customer": "thug", "amount": 150,
				"text": "チンピラ「あ、そうだ。今月分」" },
			{ "type": "TEXT", "text": "主人公「食い終わってから言うなよ」" },
		]
	return []
