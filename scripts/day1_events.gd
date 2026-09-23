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
## 具材の腐敗: spoiled は今朝PREPに入った瞬間に破棄された品目 id → 個数の Dictionary
##   （受け側が GameState.discard_spoiled_inventory() で先に消して渡す。日次ログ導入で
##   個数も持つようになったが、ここでは `for id in spoiled` でキーを回すだけなので
##   Array時代と同じ書き方のまま動く）。あれば先頭に一言テキストを1つ足す
##   （データのみ。破棄自体はここでは行わない）。
## クズ野菜ベース: scraps_base は「ベース代（GameState.BASE_PRICE）を払えない」ので
##   食肉仲卸ではなく端材屋へ回る日か。受け側がPREPに入る瞬間に所持金を見て1回だけ決め、
##   ここへは引数で渡す（計器盤にも同じ値を出すため。ここで money を読むと、PREPの途中で
##   所持金が変わったときに表示とずれる）。違うのは冒頭の3つ（TEXT・会話・ADD_ITEM。
##   PAYなし）と、SET_SOUP の濃さ（1スタート）だけ。杯数・仕込みの流れは同じ。
static func prep_events(spoiled: Dictionary = {}, scraps_base: bool = false, reserve_lost: bool = false) -> Array:
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


## 品目id → 市場価格（1回の購入＝GameState.INGREDIENT_SERVINGS_PER_PURCHASE杯分の値段）。
## 日次ログ（廃棄額の概算）用。数値をここへ書き写さず、既存の *_goods() を1回ずつ集めて
## 作るだけにする（市場価格を変えてもこちらは自動で追従する）。reserve_base（予備ベース）は
## 仕込み用の別資源で腐敗バッチにも登場しないため、含めても実害はないが対象外として省く。
static func ingredient_prices() -> Dictionary:
	var prices := {}
	var all_goods := produce_goods() + meat_wholesale_goods() + dry_goods_goods() \
		+ tofu_noodles_goods() + seafood_goods() + scraps_goods()
	for good in all_goods:
		var id := str(good.get("id", ""))
		if id != "" and id != "reserve_base":
			prices[id] = int(good.get("price", 0))
	return prices


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


## OPEN の客の並び（DESIGN.md 9章 / 7.6 / §9-C「データの外部化」）。STEP 6: 配達員1人
## → STEP 7: 3人 → §9-C: 日ごとの構成をScheduleData.day_schedule()のJSONから組み立てる
## 汎用ロジックに変更（day1_events.gd側にはもう客IDのif/matchを持たない）。
## 7.6: フラットな配列をやめ、**時間帯で区切る**（宵の口 / 夜半 / 明け方）。
##   時間帯名と客リストを1つの辞書に同居させる（名前を別配列で並行管理しない）。
## §9-C: day_schedule.jsonに無い日（Day3〜7）はScheduleData側で"1"（Day1）へ
##   フォールバックする。ここでは「今日の枠構成」をそのまま信じて組み立てるだけでよい。
## 時間帯に客がいない（＝main/main_poolを持たない）ことは今回は無い想定だが、
##   将来そういう枠を足しても "id": "" のまま customers=[] になるだけで安全。
##
## モブの独立抽選（Day2-7ダミーデータ・モブ抽選独立化）：以前は日全体で共有の1個の
## mob_countを全モブ枠に使い回していたが、**枠（宵の口・夜半・明け方）ごとに、種類も
## 人数も別々に抽選する**。引数の意味が「今日の実人数」から「デバッグ用の一律上書き値
## （-1=自動。debug_panel.gdの_debug_mob_countをそのまま渡す）」に変わった点に注意
## （引数名もそれに合わせて改名）。
## 枠ごとに決めたモブの（型・人数）は、customersに積む文字列自体を"mob#N"という
## その日だけのインスタンスidにし、_mob_instancesへ退避しておく（客の番が来て
## customer_events()→_customer_flavor()が呼ばれるときに引けるようにするため。
## OpenController・debug_panel.gdはcustomersを不透明な文字列としてしか見ないので、
## この2つは無改修で動く）。_mob_instancesはここで毎回clear()するので、次の日の
## customer_schedule()呼び出しで自動的に前日の分が消える（明示的なリセットフックは
## 不要と判断した）。
static func customer_schedule(debug_mob_count: int = -1) -> Array:
	_mob_instances.clear()
	var slots: Array = ScheduleData.day_schedule(GameState.day_count).get("slots", [])
	var chosen_mains := []   # 同日内の重複禁止（main_poolの抽選用。§9-C確定仕様）
	var mob_seq := 0
	var result := []
	for slot in slots:
		var main_id := _pick_main(slot, chosen_mains)
		var customers := []
		if main_id != "":
			customers.append(main_id)
			chosen_mains.append(main_id)
		var mob := _pick_mob(slot, debug_mob_count)
		if not mob.is_empty():
			var instance_id := "mob#%d" % mob_seq
			mob_seq += 1
			_mob_instances[instance_id] = mob
			customers.append(instance_id)
		result.append({ "name": str(slot.get("name", "")), "customers": customers })
	return result


## 1枠ぶんのメイン客idを決める（day_schedule.jsonの読み込みからは独立させた純粋関数。
## §9-Cで確定：固定("main")と抽選プール("main_pool")の2値のみ。特別な「初登場」
## 「最後に固定」用のフィールドは作らない）。
## main_poolの抽選は、その日すでに選ばれた客（chosen）を除外して選ぶ（同日内で同じ
## メイン客が2回出ない）。除外すると候補が0になる場合（プールが尽きた）は、除外を
## 無視してプール全体から選び直す（クラッシュしない。§9-C確定仕様）。
## 乱数はRandomNumberGeneratorを作らず、既存の流儀どおりグローバルなrandi()を使う。
static func _pick_main(slot: Dictionary, chosen: Array) -> String:
	if slot.has("main"):
		return str(slot["main"])
	var pool: Array = slot.get("main_pool", [])
	if pool.is_empty():
		return ""
	var candidates: Array = pool.filter(func(id): return not chosen.has(id))
	if candidates.is_empty():
		candidates = pool
	return str(candidates[randi() % candidates.size()])


## 1枠ぶんのモブの型・人数を決める（Day2-7ダミーデータ・モブ抽選独立化で新設）。
## "mob"の値は3値：false/無指定（モブなし）、true（既存どおりdock_workers固定）、
## {"pool":[...]}（型をプールから抽選。**同日内の重複除外はしない**＝main_poolとは
## 対称的な仕様。3-1節確定）。型が決まったら、人数は debug_count>=0 ならそれを、
## そうでなければ GameState.mob_count_today() を毎回独立に呼んで決める（Day1は
## day_count==1の分岐で常に固定4を返す関数なので、宵の口・夜半とも今までどおり4人。
## Day2以降は枠ごとに別々の乱数が引かれる）。人数が0ならその枠にモブは出さない
## （{}を返す。既存の「mob_count>0のときだけ出す」ルールを踏襲）。
static func _pick_mob(slot: Dictionary, debug_count: int) -> Dictionary:
	var spec = slot.get("mob", false)
	var type_id := ""
	# Dictionary と bool を == で比べると実行時エラーになるため、先に is Dictionary で
	# 分岐する（それ以外はbool(spec)でtrue/falseを見る）。
	if spec is Dictionary:
		var pool: Array = spec.get("pool", [])
		if pool.is_empty():
			return {}
		type_id = str(pool[randi() % pool.size()])
	elif bool(spec):
		type_id = "dock_workers"
	else:
		return {}
	var count := debug_count if debug_count >= 0 else GameState.mob_count_today()
	if count <= 0:
		return {}
	return { "type": type_id, "count": count }


## id がモブ客か（DESIGN.md 7.6）。自動閉店の判定などで、受け側が
## 「これより後に名前あり客が残っているか」を問い合わせるために公開する。
static func is_mob_customer(customer_id: String) -> bool:
	return bool(_customer_flavor(customer_id).get("is_mob", false))


## その日だけのモブのインスタンスid（"mob#0"等）→{type, count}。customer_schedule()が
## 枠を組み立てる際に書き込み、customer_schedule()の次回呼び出し（＝翌日のOPEN開始）で
## clear()される。_customer_flavor()がここを見てモブの型・人数を引く。
static var _mob_instances: Dictionary = {}


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
	# 配達員は初日だけ、同じ客へ3杯を1杯ずつ会話の合間に出す専用のEvent列（客ごとの分岐は
	# データ層のここだけ。受け側 DebugPanel には客IDを書かない）。2日目以降に配達員が
	# 再来店した場合は、他の客と同じ通常の1杯の流れ（下の汎用ロジック）を使う
	# （customers/delivery_man.json の"days"."1"エントリが汎用フローの内容を持ち、
	# customer_dataのフォールバックにより2日目以降どの日でもここへフォールバックする）。
	if customer_id == "delivery_man" and GameState.day_count == 1:
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
		"GREAT": ["配達員【GREAT】(1杯目)"],
		"GOOD": ["配達員【GOOD】(1杯目)"],
		"OK": ["配達員【OK】(1杯目)"],
		"BAD": ["配達員【BAD】(1杯目)"],
	}


static func _delivery_reactions_second() -> Dictionary:
	return {
		"GREAT": ["配達員【GREAT】(2杯目)"],
		"GOOD": ["配達員【GOOD】(2杯目)"],
		"OK": ["配達員【OK】(2杯目)"],
		"BAD": ["配達員【BAD】(2杯目)"],
	}


## 来店〜一杯目の注文（会話稿「登場・一杯目の注文」）。
const _DELIVERY_ARRIVAL := [
	"配達員「注文（HOT/POWER）」1杯目",
]

## 一杯目の共通会話（料理の結果に関係なく表示。会話稿「一杯目・共通会話」）。
const _DELIVERY_AFTER_FIRST := [
	"配達員「1杯目の共通会話（第八码頭の話は省略）」",
]

## 二杯目の共通会話（第八码頭の情報はここ。料理の結果に関係なく必ず表示。
## 会話稿「二杯目・共通会話」。持ち帰りの注文まで）。
const _DELIVERY_AFTER_SECOND := [
	"配達員「2杯目の共通会話（持ち帰りを注文）」",
]

## 持ち帰りの提供後〜退店（会話稿「三杯目・提供と退店」。SERVE の後）。
const _DELIVERY_EXIT := [
	"配達員「退店（会計・名前は阿強）」",
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
	"警官（市場・要求タグ: SOUR/BITE）",
]

## 夜・来店（宵の口）。REACT の前の GREET。§9-C「データの外部化」で
## res://data/customers/officer.json（days."2".greet）へ移した（重複を避けるため
## 定数としては持たない。中身を見るならJSON側を参照）。

## 提供後・共通会話（料理の結果に関係なく必ず表示）。
const _OFFICER_AFTER := [
	"警官（提供後・共通会話）",
]

## 会計・退店（共通会話の後。料理の結果に関係なく同じ内容）。
const _OFFICER_PAYMENT := [
	"警官（会計・退店）",
]

## 警官の反応文（結果ごとに短い会話を改行でつないだ1つの文字列。各結果の配列は要素数1）。
## §9-C「データの外部化」で res://data/customers/officer.json（days."2".reactions）へ
## 移した（重複を避けるため関数としては持たない。中身を見るならJSON側を参照）。


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
## 鮮度: 腐る品目は「傷んでいない分」と「傷んだ分」を別ボタンにする（傷んだ側は
## "damaged": true とラベル末尾の「(傷)」。キーが無ければ傷んでいない側）。腐らない品目は
## damaged_count が常に0なので今までどおり1つ。どちらのボタンを押したかが判定を決める
## （傷んだボタン＝-1段階）。その側の在庫が0のボタンは出さない。
static func _adjust_options() -> Array:
	var options := []
	for id in GameState.inventory:
		if id == "soup_base":   # 鍋のベースはADJUSTの対象外
			continue
		# 日数は夜の間に変わらないので、接客開始時に組み立てる既存の扱いのままでよい。
		var label: String = _ADJUST_LABELS.get(id, str(id))
		if GameState.fresh_count(id) > 0:
			options.append({ "id": id, "label": label })
		if GameState.damaged_count(id) > 0:
			options.append({ "id": id, "label": label + "(傷)", "damaged": true })
	return options


## 客ごとに変わる差分だけ（売上は DESIGN.md 6章の Day1 台本準拠：45 / 40 / 55）。
## STEP 17.5: greetは複数行の配列。
## STEP 17.6: wanted_tags は「味の軸＋具の軸」の2つ（DESIGN.md 9.5 STEP17.6）。
##   会話の中に両方の手がかりを置く（例：配達員＝辛くしてくれ／疲れて眠い → HOT + POWER）。
##   reactions は判定結果をキーにした辞書。各段階2パターンで、どちらを出すかはランダム。
##   favorite は好物の具材id（1つ）。椀に入っていれば評価が1段上がる（クリティカル）。
## §9-C「データの外部化」：客の会話・要求タグ・favorite・reactions・servingsは
##   ScheduleData.customer_data()（res://data/customers/<id>.json）へ外部化した。
##   ここでは「どのデータ源を読むか」の出し分けだけを行う（データそのものは持たない）。
##   delivery_man は初日だけ customer_events が専用の Event 列（_delivery_man_events）を
##   返すため、その間は is_mob・wanted_tags・favorite だけ使う。2日目以降に配達員が
##   再来店したときは（客の番数請求は1杯に減る）、他の客と同じ下の汎用の返り値を使う
##   （customers/delivery_man.json の "days"."1" エントリへフォールバックする内容）。
## モブ（DESIGN.md 7.6）は、まず_mob_instances（customer_schedule()が枠ごとに独立抽選
##   した結果）を見る。あれば、そのインスタンスの型でScheduleData.mob_data()を読む
##   （favorite は持たない＝GREAT は出ない。個人の好物は「その人を知っているから分かる」
##   もので、一見の集団には無い。servingsはそのインスタンスの人数）。引数のmob_countは
##   モブに対しては使わない（枠ごとに独立して決めた人数を使うため。互換のため引数
##   自体は残す）。
## 未知 id（JSONファイルが無い等）は無音・売上0・wanted_tags 空（＝一致0なので常に BAD）
##   でフォールバックする（既存どおり。ScheduleDataは空辞書を返すのでそこで判別する）。
static func _customer_flavor(customer_id: String, mob_count: int = 0) -> Dictionary:
	if _mob_instances.has(customer_id):
		var inst: Dictionary = _mob_instances[customer_id]
		var mob := ScheduleData.mob_data(str(inst.get("type", "")))
		if mob.is_empty():
			return _unknown_customer_flavor()
		var count := int(inst.get("count", 0))
		var greet := []
		for line in mob.get("greet", []):
			greet.append(_format_mob_greet(str(line), count))
		return { "greet": greet, "reactions": mob.get("reactions", {}),
			"servings": count, "is_mob": true,
			"wanted_tags": mob.get("wanted_tags", []), "favorite": "" }
	var data := ScheduleData.customer_data(customer_id, GameState.day_count)
	if data.is_empty():
		return _unknown_customer_flavor()
	if customer_id == "delivery_man" and GameState.day_count == 1:
		# 初日は_delivery_man_events()が専用のEvent列を組む（greet/reactions/servingsは
		# 使わない＝ここでは返さない）。2日目以降は下の汎用の返り値（他の客と同じ形）を使う。
		return { "is_mob": data.get("is_mob", false),
			"wanted_tags": data.get("wanted_tags", []), "favorite": data.get("favorite", "") }
	return { "greet": data.get("greet", []), "reactions": data.get("reactions", {}),
		"servings": int(data.get("servings", 1)), "is_mob": data.get("is_mob", false),
		"wanted_tags": data.get("wanted_tags", []), "favorite": data.get("favorite", "") }


## モブのgreet 1行を仕上げる（旧_format_dock_greetを改名。dock_workers専用ではなく
## 全モブ種で使う）。"%d"を含む行だけ人数を埋め込み、含まない行（素の台詞）はそのまま
## 返す（GDScriptの % 演算子はプレースホルダの無い文字列に値を渡すと実行時エラーに
## なるため、含む行だけに絞る）。
static func _format_mob_greet(line: String, count: int) -> String:
	if line.contains("%d"):
		return line % count
	return line


## 未知id・データ無しのフォールバック（既存どおり）。
static func _unknown_customer_flavor() -> Dictionary:
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
				"text": "チンピラ（場所代）" },
		]
	return []
