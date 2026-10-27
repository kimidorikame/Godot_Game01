extends RefCounted
## 3-8：3-1〜3-7後の仕様（Day1の9杯・初日セット・SaleRule・鍋容量14・朝の一画面）向けに
## 2026-09-26版（planning/playtest_2026_09_26/playthroughs.gd）を更新した自動試遊。
## 実際のdebug_panel.tscnを生成し、DebugPanelのハンドラ・GameState・EventRunner・
## OpenController・配布データを実際に動かす。ゲーム本体は変更しない。
##
## 仕入れ・仕込み量は、朝のSNSタブが公開している情報（Forecast：総杯数の幅＝上限案、
## 上限案の必要タグ数）だけを読んで決める。翌日以降の抽選やデバッグ付与は読まない。
## 画面を人間の目で読んでクリックしたテストではなく、同じ情報を内部データから取り出す
## 自動操作（読み間違い・操作速度・面白さは測らない）。
## 乱数は朝ごとにシード＋日で固定し、方針間で需要の抽選を対にする。
##
## 引数（--以降）：[0]=旧7方針のシード数(既定30) [1]=新5方針のシード数(既定=[0])
##   [2]=出力ファイル名(既定playthrough_results.json) [3]=方針のカンマ区切り絞り込み（"all"＝絞り込まない）
##   [4]=到達杯数の表（"default"＝既定の12/13/14／"reach_true"＝12/15/18。再測定）
##   [5]=運営費の上書き（整数。省略または負＝データのまま。データは変えず、実行中だけ GameState の値を差し替えて、
##       終わったら元へ戻す）
##   [6]=手がかり（UI準備C⑤。"forecast"＝既定。予報〔Forecast〕を読む＝v2と同じ／"visible"＝予報を読まず、プレイヤーに
##       見えるものだけ〔前日の注文杯数・客足の言葉・DMの匂わせ・自分が受けた注文・在庫と所持金〕で決める＝v3。
##       v3は「言葉と数の対応を覚えた熟練プレイヤー」相当）／"visible_improvise"＝"visible" に加えて、注文のタグの素材が
##       手元に無いとき、足りない軸（味・具）をほかの在庫で補って椀を成立させる（参考の補助測定。v3の既定には含めない）

const OUT := "res://planning/playtest_2026_10_11/"
const POLICIES_OLD := ["forecast_good", "forecast_favorites", "always_small", "always_large",
	"cheap_valid", "bare_broth", "forecast_mistakes"]
## 新規5方針（10.13の比較方針で旧版に無かったもの）。favorite_oracleは好物IDを内部データ
## から読む「上限の目安」であり、画面からは分からない情報を使う（通常の方針とは別枠）。
## decline_one_group は「毎日1組を断る」強い版、decline_once は「3日目に1組だけ断る」弱い版
## （10.13の「1組を断る」をどちらの意味でも読めるよう、両方を測る）。
const POLICIES_NEW := ["favorite_oracle", "no_split", "strength_neglect",
	"decline_one_group", "two_failures", "decline_once"]
## 各仕込み段階で「夜の始まりに鍋へ入れられる量」（水・だしの操作込み。小8→水2回で12／
## 中11→水1回で13／大14→水0回）。一晩の総杯数ではない（営業中の水足し込みの総杯数は
## 12／15／18）。鍋の同時容量14・水は残量12以下のときだけ足せる。DESIGN.md 10.3.8。
## 修繕基金の方針（4-9③。別枠）。既定の方針一覧（POLICIES_OLD + POLICIES_NEW）には入れず、引数[3]で
## 名前を指定したときだけ走る。仕入れ・仕込み・調理・接客の判断は基準方針 forecast_good と同じ（このファイルの
## policy == の分岐のどれにも当たらない＝既定の分岐）で、差は CLOSE の基金の操作だけ。押すのは DebugPanel の
## _on_fund_contribute_pressed 経由（実際の操作経路）。刻み・上限は RepairFund から読み、数値は直書きしない。
##   fund_final_only … 最終日のCLOSEだけ、安全上限の範囲で積めるだけ積む（対照実験）
##   fund_steady     … 毎晩、刻みの中央値（week7では50）を1回積む（安全上限・最終段階までの残りの範囲）
##   fund_max_safe   … 毎晩、安全上限と最終段階までの残りの範囲で積めるだけ積む
const POLICIES_FUND := ["fund_final_only", "fund_steady", "fund_max_safe"]
const FUND_BASE_POLICY := "forecast_good"
## 切り分け用の方針（運営費75。別枠）。既定の方針一覧には入れず、引数[3]で名前を指定したときだけ走る。
##   strength_neglect_dashi … strength_neglect と同じ判断（濃さ・鮮度のミス）で、毎朝のだし2個の買い置きだけ
##                            基準方針と同じにしたもの（だしの買い置きが下振れの原因かを単独で見るため）
const POLICIES_ISOLATION := ["strength_neglect_dashi"]
## 下限版（UI準備C⑤。別枠。引数[3]で名前を指定したときだけ走る。"visible" 専用）：見込みを「前日の注文杯数だけ」にする
## （客足の言葉もDMの匂わせも使わない。Day1は張記の会話の9杯）。ほかの判断は基になる方針と同じ。
const POLICIES_LOWER := ["forecast_good_lower", "favorite_oracle_lower"]
## 備蓄型（情報量の実験の続き。UI準備D。別枠）。予報も見込みも読まず、日持ちする7材料と生ものの3タグを「k単位（購入単位＝1袋）」ぶん手元に置く。引数 info=stock で使う（stockpile_shop）。
const POLICIES_STOCK := ["stockpile"]
const LOWER_BASE := { "forecast_good_lower": "forecast_good", "favorite_oracle_lower": "favorite_oracle" }
const TIER_REACH := { "small": 12, "medium": 13, "large": 14 }
## 再測定（引数[4]=reach_true のときだけ使う）：営業中の水足しを含めて、その段階で一晩に出せる総杯数
## （先に直す④の実測：小12／中15／大18）。choose_tier() が「その段階で足りるか」を測るための表。
const TIER_REACH_TRUE := { "small": 12, "medium": 15, "large": 18 }
const SHOPS := ["produce", "meat_wholesale", "dry_goods", "tofu_noodles", "seafood", "scraps"]

var tree: SceneTree
var panel
var policy := ""   # 判断の分岐に使う名前（下限版は基になる方針の名前）
var policy_label := ""   # 結果に出す名前（下限版は *_lower）
var lower_only := false
var info_mode := "forecast"
var improvise := false   # "visible_improvise" のとき：欠けた軸（味・具）をほかの在庫で補う
## "levels"（情報量の実験。UI準備D）：補う版を土台に、仕入れの必要数のうち「前もって知っている割合」を変える（下の levels_need）。
var levels_on := false
var level_p_reg := 1.0      # 常連（名前あり客）のタグを前もって知っている割合（0〜1）
var level_p_mob := 1.0      # モブのタグを前もって知っている割合
var level_forecast_target := false   # 見込み杯数（仕込みの大きさ）も予報の値にする（確認用）
## 計測H（チップと「具2個」）：ゲーム本体の規則とは別の、ハーネスだけの設定。既定は「無効・定価はデータのまま」で、v2 と全キー一致する。
##   案T：提供ごとに 定価＋チップ（GOOD は tip_good、GREAT は tip_great。BAD・OK は 0。評判の増減は今のまま）。
##   案G：具が1種類しか入っていない椀は、減点−1段階（濃さ1/5・傷みと同じ扱い。重ね掛けはしない＝すでに減点があれば変わらない）。
## 実際の判定・売上・評判の処理（PlaySession・Judge）には触らない。提供が済んだあとに、日の評価の集計（log_quality_counts）と所持金へ反映する。
var tip_good := 0
var tip_great := 0
var two_gu_on := false
var price_override := -1
## 案G＋仕入れ（計測Hの補足）：2つ目の具の仕入れまで方針に入れる。仕入れで、日持ちする具（冬瓜・米麺・乾燥きくらげ・魚の浮き袋）のうち
## 一番安いものを1杯につき1個（備蓄型は個数 k のぶん）買い足す。椀には「注文に合う具」と「その安い具」を入れる（同じ材料は不可）。
## 注文に合う具が最安の具と同じになる杯のために、2番目に安い具も同じ要領で（FILLING の必要数／備蓄型は k 個）買う。2つ目の具が手持ちに無いときだけ減点を受ける。
var two_gu_buy := false
const SECOND_GU := ["winter_melon", "rice_noodle", "dried_wood_ear", "fish_maw"]
var tip_gu_on := false      # 上のどれかが有効（このときだけ、結果に tips・gu_penalized のキーを足す）
var seen_counts: Dictionary = {}   # すでに反映した日の評価の杯数（日が変わると log_quality_counts は 0 に戻る）
var tips_today := 0
var gu_pen_today := 0
var tips_total := 0
var gu_pen_total := 0
var last_cook_toppings := 0     # 直近に作った椀の具の数（椀が空に戻ったあとに反映する場合の控え）
var gu_fallback_total := 0      # 椀が空に戻っていて、控えの具の数で反映した杯数（確認用）
const GRADE_DOWN := { "GREAT": "GOOD", "GOOD": "OK", "OK": "BAD", "BAD": "BAD" }
## 備蓄型（info=stock）：k＝手元に置く単位（購入単位＝1袋）の数、p＝生もの3タグの今夜の必要を前もって知っている確率（-1＝情報なし）
var stock_on := false
var stock_k := 2
var stock_p := -1.0
var stock_pieces := false   # true：k は手元の個数（袋の数ではない。測り直し）。手元が k 個を切ったら1袋買い足す
## 備蓄型の材料：日持ちする7つ（腐らない）と、生ものでしか満たせない3タグ（腐る。POWER は袋の単価が安い肉団子）
const STOCK_DURABLE := [["HOT", "nam_prik_pao"], ["SOUR", "pickled_lime"], ["SAVORY", "herbal_sauce"], ["GENTLE", "winter_melon"],
	["FILLING", "rice_noodle"], ["BITE", "dried_wood_ear"], ["TREAT", "fish_maw"]]
const STOCK_FRESH := [["MELLOW", "coconut_milk"], ["BITTER", "bitter_melon"], ["POWER", "meat_ball"]]
## v3（visible）の「自分が受けた注文」の記録：夜ごとの { tags: { タグ: 杯数 }, cups }。ADJUSTで見た注文（注文カード）から数える。
var seen_nights: Array = []
var night_tags: Dictionary = {}
var night_cups := 0
var reach_name := "default"
var tier_reach: Dictionary = TIER_REACH
## 仕込み段階の選択の記録（再測定。最上位の tier_log に出す。各周のキーには足さない）。
var tier_log: Array = []
## 水を足したいのに足せなかった夜の理由の記録（運営費75の切り分け。最上位の water_stop_log に出す。
## 各周のキーには足さない）。reason：doses＝水の回数切れ／remaining＝残量条件（13杯以上残っている）／
## strength_floor＝濃さの下限（足すと0を下回る）／no_dashi＝濃さが低いのにだしを足せない／other。
var water_stop_log: Array = []
## 足りなかった杯数の理由別の記録（UI準備C③。最上位の unserved_log に出す。各周のキーには足さない）。
## 日ごとに { policy, seed, day, ingredients, pot, declined, not_arrived, unserved }（PlaySession.unserved_breakdown）。
var unserved_log: Array = []
var cur_seed := 0
var clicks := 0
var purchases := 0
var incidents: Array = []
var counts: Dictionary = {}
var day1_cash: Dictionary = {}
var declined_group_today := false
var failed_named := false
var failed_mob := false
var failure_log: Array = []
var fund_log: Array = []
var fund_stage_days: Dictionary = {}


func run(t: SceneTree) -> void:
	tree = t
	# 朝の1枠セーブ（MorningSave）を、実際のセーブと別ファイルへ向ける（試遊中はWAKEのたびに
	# 書かれる。ゲームの進行には影響しない）。
	MorningSave.save_path = "user://playtest_save.dat"
	BalanceLog.path = "user://playtest_balance_log.jsonl"   # 実際の日次ログを汚さない
	ReadState.enabled = false   # 既読ファイルを読まず・書かない（試遊の結果が既読の有無で変わらない）
	var args := OS.get_cmdline_user_args()
	var seeds_old := int(args[0]) if args.size() > 0 else 30
	var seeds_new := int(args[1]) if args.size() > 1 else seeds_old
	var out_name := str(args[2]) if args.size() > 2 else "playthrough_results.json"
	var only: Array = str(args[3]).split(",") if args.size() > 3 else []
	if only.has("all"):
		only = []
	info_mode = str(args[6]) if args.size() > 6 else "forecast"
	if not ["forecast", "visible", "visible_improvise", "levels", "stock"].has(info_mode):
		push_error("unknown info: " + info_mode)
		return
	var info_label := info_mode
	improvise = info_mode == "visible_improvise"
	if improvise:
		info_mode = "visible"
	stock_on = info_mode == "stock"
	if stock_on:
		# 備蓄型：椀の作り方・仕込みの大きさ・濃さは補う版（visible_improvise）と同じ。引数 [7]＝k、[8]＝生ものの情報の確率（%。-1＝情報なし）
		improvise = true
		info_mode = "visible"
		stock_k = int(args[7]) if args.size() > 7 else 2
		stock_p = float(args[8]) / 100.0 if args.size() > 8 and float(args[8]) >= 0.0 else -1.0
		stock_pieces = args.size() > 9 and str(args[9]) == "pieces"   # [9]＝pieces なら k は個数（既定は袋の数）
	levels_on = info_mode == "levels"
	if levels_on:
		# 情報量の実験：補う版（visible_improvise）が土台。引数 [7]＝常連の割合（%）、[8]＝モブの割合（%）、[9]＝"forecast_target" なら見込み杯数も予報
		improvise = true
		info_mode = "visible"
		level_p_reg = float(args[7]) / 100.0 if args.size() > 7 else 1.0
		level_p_mob = float(args[8]) / 100.0 if args.size() > 8 else 1.0
		level_forecast_target = args.size() > 9 and str(args[9]) == "forecast_target"
	# 計測H：[10]＝GOODのチップ、[11]＝GREATのチップ、[12]＝1なら「具2種類」を必須にする（案G）、[13]＝定価の上書き。省略＝無効。
	tip_good = int(args[10]) if args.size() > 10 else 0
	tip_great = int(args[11]) if args.size() > 11 else 0
	two_gu_on = args.size() > 12 and int(args[12]) == 1
	price_override = int(args[13]) if args.size() > 13 and int(args[13]) > 0 else -1
	two_gu_buy = two_gu_on and args.size() > 14 and int(args[14]) == 1
	tip_gu_on = tip_good != 0 or tip_great != 0 or two_gu_on or price_override > 0
	reach_name = str(args[4]) if args.size() > 4 else "default"
	if reach_name == "reach_true":
		tier_reach = TIER_REACH_TRUE
	elif reach_name == "default":
		tier_reach = TIER_REACH
	else:
		push_error("unknown reach: " + reach_name)
		return
	# 運営費の上書き（再測定）。GameState.DAILY_OPERATING_COST は起動時に Rules から読んだ静的変数で、
	# 使うのは WAKE の支払い・朝の文・RepairFund の翌日の確保だけ。データ（week7.json）は変えない。
	var data_cost: int = GameState.DAILY_OPERATING_COST
	var cost_override := int(args[5]) if args.size() > 5 and str(args[5]) != "" else -1
	if cost_override >= 0:
		GameState.DAILY_OPERATING_COST = cost_override
	var data_price: int = GameState.PRICE_PER_SERVING
	if price_override > 0:
		GameState.PRICE_PER_SERVING = price_override
	var policies: Array = []
	for p in POLICIES_OLD + POLICIES_NEW:
		if only.is_empty() or only.has(p):
			policies.append(p)
	for p in POLICIES_FUND + POLICIES_ISOLATION + POLICIES_LOWER + POLICIES_STOCK:
		if only.has(p):
			policies.append(p)
	var results: Array = []
	for p in policies:
		var n := seeds_old if POLICIES_OLD.has(p) else seeds_new
		for run_seed in range(1, n + 1):
			results.append(await play(p, run_seed))
		print("PLAYTEST_PROGRESS ", p, " ", n, " runs")
	var output := { "commit": git_head(), "tracked_changes": git_dirty(),
		"engine": Engine.get_version_info(), "daily_operating_cost": GameState.DAILY_OPERATING_COST,
		"seeds_old": seeds_old, "seeds_new": seeds_new,
		"policies": policies, "runs": results, "info_mode": info_label }
	# 再測定の設定（最上位だけに足す。各周のキーは変えない）。daily_operating_cost は実際に使った値。
	output["reach"] = reach_name
	if stock_on:
		output["info_stock"] = { "k": stock_k, "p_fresh": stock_p, "unit": "pieces" if stock_pieces else "packs" }
	if levels_on:
		output["info_levels"] = { "p_regular": level_p_reg, "p_mob": level_p_mob, "forecast_target": level_forecast_target }
	output["tier_log"] = tier_log
	output["water_stop_log"] = water_stop_log
	output["unserved_log"] = unserved_log
	output["tier_reach"] = tier_reach.duplicate()
	output["daily_operating_cost_data"] = data_cost
	if tip_gu_on:
		output["tip_gu"] = { "tip_good": tip_good, "tip_great": tip_great, "two_gu": two_gu_on, "two_gu_buy": two_gu_buy, "price": GameState.PRICE_PER_SERVING,
			"price_data": data_price }
	GameState.PRICE_PER_SERVING = data_price
	output["daily_operating_cost_overridden"] = cost_override >= 0
	GameState.DAILY_OPERATING_COST = data_cost
	# 基金の方針が選ばれた実行にだけ、最上位に検査と目標の判定を足す（既定の出力の形・各周のキーは変えない）。
	if policies.any(func(x): return POLICIES_FUND.has(x)):
		output["fund_checks"] = fund_checks(results)
		output["goals_by_run"] = goals_by_run(results)
	var f := FileAccess.open(OUT + out_name, FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()
	print("PLAYTEST_COMPLETE ", results.size())


func git_head() -> String:
	var out: Array = []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], out)
	return str(out[0]).strip_edges() if not out.is_empty() else "unknown"


## 実行時点でゲーム本体（scripts/・data/）に未コミットの変更があれば記録する
## （結果がHEADと一致しない状態で実行したことを後から分かるようにするため）。
func git_dirty() -> String:
	var out: Array = []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "status", "--short",
		"--", "scripts", "data"], out)
	return str(out[0]).strip_edges() if not out.is_empty() else ""


## strength_neglect とその切り分け版（判断は同じ。だしの買い置きだけが違う）。
func is_neglect() -> bool:
	return policy == "strength_neglect" or policy == "strength_neglect_dashi"


func play(p: String, run_seed: int) -> Dictionary:
	policy_label = p
	lower_only = LOWER_BASE.has(p)
	policy = str(LOWER_BASE.get(p, p))
	seen_nights = []
	night_tags = {}
	night_cups = 0
	cur_seed = run_seed
	clicks = 0
	purchases = 0
	incidents = []
	counts = {}
	day1_cash = {}
	declined_group_today = false
	failed_named = false
	failed_mob = false
	failure_log = []
	fund_log = []
	fund_stage_days = {}
	seen_counts = {}
	tips_today = 0
	gu_pen_today = 0
	tips_total = 0
	gu_pen_total = 0
	gu_fallback_total = 0
	GameState.reset_for_new_game()
	seed(run_seed * 1000 + 1)
	panel = load("res://scenes/debug_panel.tscn").instantiate()
	tree.root.add_child(panel)
	var rows: Array = []
	var steps := 0
	var done := false
	var stalled := false
	var before_market := false
	var seen_prep := false
	var seen_open := false
	var result_phase := ""
	var result_summary := {}
	while not done and steps < 6000:
		# 表示だけのニュース／共通イベントの TEXT（part が news または common_event）は、プレイヤーの
		# 判断ではないので、操作回数（clicks・actions・steps）に数えずに読み飛ばす。これ以外の差は
		# 見逃さない（TEXT 以外・他の part は対象外）。
		while panel.session.flow.runner != null and panel.session.flow.runner.status == EventRunner.Status.PLAYING \
				and is_display_only(panel.session.flow.runner.current()):
			panel.session.next_event()
		steps += 1
		if steps % 12 == 0:
			await tree.process_frame # release queue_free UI controls
		if tip_gu_on:
			settle_serves()
		if GameState.phase == GameState.Phase.GAME_OVER:
			incidents.append({ "type": "game_over", "day": GameState.day_count, "cash": GameState.money })
			break
		if GameState.day_count == 1:
			if GameState.phase == GameState.Phase.PREP and not seen_prep:
				seen_prep = true
				day1_cash["after_wake"] = cash()
			if GameState.phase == GameState.Phase.OPEN and not seen_open:
				seen_open = true
				day1_cash["after_market"] = cash()
		var r: EventRunner = panel.session.flow.runner
		if GameState.phase == GameState.Phase.NEXT_DAY:
			rows.append(day_row())
			tips_today = 0
			gu_pen_today = 0
			seen_nights.append({ "tags": night_tags.duplicate(), "cups": night_cups })
			night_tags = {}
			night_cups = 0
			var split: Dictionary = panel.session.unserved_breakdown()
			unserved_log.append({ "policy": policy_label, "seed": run_seed, "day": GameState.day_count,
				"ingredients": int(split["unserved_ingredients"]), "pot": int(split["unserved_pot"]),
				"declined": int(split["unserved_declined"]), "not_arrived": int(split["unserved_not_arrived"]),
				"unserved": int(split["unserved_cups"]) })
			if GameState.day_count == 1:
				day1_cash["end"] = GameState.money
			if GameState.day_count == 7:
				# 実際の最終日の流れ（4-2）：advance_phase()がday_endingを発火して最終日の
				# 記録を累計（day_records）へ足し、結果画面（Phase.RESULT）へ入る。新しい周へは
				# 進めない（reset_for_new_gameは呼ばれない）。結果画面の集計（Result.summarize）を
				# 記録し、集計スクリプトがこのスクリプト内の日別集計と突き合わせる。
				panel.session.flow.advance_phase()
				result_phase = str(GameState.Phase.keys()[GameState.phase])
				result_summary = Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
				done = true
				break
			seed(run_seed * 1000 + GameState.day_count + 1)
			declined_group_today = false
			panel.session.flow.advance_phase()
			before_market = false
			continue
		if r.status == EventRunner.Status.DONE:
			# 修繕基金の方針のときだけ、CLOSEの語りを読み終えた時点（基金を積める時点）で積む。
			if GameState.phase == GameState.Phase.CLOSE and POLICIES_FUND.has(policy):
				fund_contribute()
			panel.session.flow.advance_phase()
			continue
		if GameState.phase == GameState.Phase.WAKE:
			panel.session.flow.advance_phase()
			continue
		var ev = r.current()
		var typ := str(ev.get("type", "")) if ev is Dictionary else ""
		if typ == "PREP_TIER":
			if GameState.day_count == 1 and not day1_cash.has("after_kit"):
				day1_cash["after_kit"] = cash()
			var tier := choose_tier()
			var chosen := tier
			if cash() < int(Day1Events.prep_tier_by_id(tier).price):
				tier = "small"
			tier_log.append({ "policy": policy_label, "seed": run_seed, "day": GameState.day_count,
				"target": target_cups(), "chosen": chosen, "tier": tier })
			act("prep")
			panel.session.choose_prep_tier(tier)
			if GameState.day_count == 1:
				day1_cash["tier"] = tier
				day1_cash["after_tier"] = cash()
			continue
		if typ == "MARKET":
			if not before_market:
				shop()
				before_market = true
			act("market_exit")
			panel.session.exit_market()
			continue
		if GameState.phase == GameState.Phase.OPEN:
			if panel.session.pot_open:
				incidents.append({ "type": "pot_mode_stuck", "day": GameState.day_count,
					"soup": GameState.soup.duplicate(), "dashi": GameState.dashi_units })
				stalled = true
				break
			if panel.session.pending_shortage_ev != null:
				if not fix_pot() and panel.session.can_close_now():
					act("close")
					panel.session.close_shop()
				continue
			if typ == "ADJUST":
				handle_adjust()
				if stalled_flag:
					stalled = true
					break
				continue
			# 注文を取る前に濃さを整える（ADJUST中は通常の鍋操作がロックされる）。
			if typ not in ["SERVE", "REACT"] and panel.session.can_touch_pot():
				fix_pot()
		if typ == "CHOICE":
			# 店主の距離感の選択（システム整理C2）：先頭の選択肢を押す。現行の21場面には無い（通らない分岐）
			act("story_choice")
			panel.session.choose_story_option(str(ev.get("choice_id", "")), str((ev["options"] as Array)[0]["id"]))
			continue
		if r.status == EventRunner.Status.WAITING_INPUT:
			act("input")
			panel.session.complete_input()
		else:
			act("next_text_event")
			panel.session.next_event()
	var result := { "policy": policy_label, "seed": run_seed, "completed": done,
		"stalled": stalled or steps >= 6000, "cash": GameState.money, "rep": GameState.reputation,
		"rows": rows, "incidents": incidents.duplicate(true), "actions": counts.duplicate(),
		"clicks": clicks, "purchases": purchases, "steps": steps, "day1_cash": day1_cash.duplicate(),
		"failures": failure_log.duplicate(true),
		"result_phase": result_phase, "result_summary": result_summary,
		"closing_stock_units": GameState.inventory.duplicate(), "dashi": GameState.dashi_units }
	if tip_gu_on:
		result["tips"] = tips_total
		result["gu_penalized"] = gu_pen_total
		result["gu_fallback"] = gu_fallback_total
	if POLICIES_FUND.has(policy):
		result["fund_log"] = fund_log.duplicate(true)
		result["stage_reached"] = RepairFund.repaired_ids().size()
		result["repaired"] = RepairFund.repaired_ids()
		result["target_paid"] = fund_target_paid_all()
		result["stage_days"] = fund_stage_days.duplicate()
	panel.queue_free()
	await tree.process_frame
	return result


var stalled_flag := false


## ADJUST（椀を作る）1回ぶんの操作。具材を選んでから、提供できるかをゲーム側の判定
## （[入力完了]の有効無効＝SaleRule・残量・濃さ）で見る。提供不可（味か具が欠けた椀）の
## ときは、名前あり客は[客を断る]、モブは「注文を断る」を選ぶ（stalledにしない）。
## 空の椀方針（bare_broth）では、これが期待どおりの動作として計数される。
func handle_adjust() -> void:
	stalled_flag = false
	var order: Dictionary = panel.session.react_for_now()
	var wanted := int(order.get("servings", 1))
	var is_mob := bool(order.get("is_mob", false))
	if int(GameState.soup.remaining_servings) < wanted or int(GameState.soup.strength) <= 0:
		fix_pot()
	if GameState.phase != GameState.Phase.OPEN:
		return
	cook(order)
	if is_mob:
		act("confirm")
		panel.session.complete_input()
		if panel.session.pending_group_choice:
			var achievable: int = panel.session.mob_achievable_servings(wanted)
			act("group_choice")
			var wants_decline := policy == "decline_one_group" \
					or (policy == "decline_once" and GameState.day_count == 3)
			if wants_decline and not declined_group_today:
				declined_group_today = true
				act("decline_group")
				panel.session.group_decline(wanted)
			elif achievable < wanted and panel.session.mob_recipe_number == 1 \
					and policy not in ["bare_broth", "cheap_valid", "no_split"]:
				panel.session.group_retry(achievable, wanted)
			elif achievable > 0:
				panel.session.group_serve(achievable, wanted)
			else:
				if policy != "bare_broth":
					incidents.append({ "type": "group_unsellable_declined", "day": GameState.day_count,
						"additions": panel.session.open.current_bowl.get("additions", []).duplicate() })
				act("decline_unsellable")
				panel.session.group_decline(wanted)
		return
	if not panel.session.can_complete_input():
		if panel.session.is_short_in_adjust() or panel.session.is_strength_zero_in_adjust():
			if panel.session.can_close_now():
				incidents.append({ "type": "forced_close", "day": GameState.day_count,
					"soup": GameState.soup.duplicate(), "dashi": GameState.dashi_units })
				act("close")
				panel.session.close_shop()
				return
			stalled_flag = true
			incidents.append({ "type": "adjust_stuck", "day": GameState.day_count,
				"soup": GameState.soup.duplicate() })
			return
		# 味か具が欠けた椀（SaleRule）。断る。
		if policy != "bare_broth":
			incidents.append({ "type": "unsellable_declined", "day": GameState.day_count,
				"customer": str(order.get("customer", "")),
				"reasons": SaleRule.check(panel.session.open.current_bowl, GameState.soup).get("reasons", []),
				"additions": panel.session.open.current_bowl.get("additions", []).duplicate() })
		act("decline_unsellable")
		panel.session.decline_customer()
		return
	act("confirm")
	panel.session.complete_input()


## 仕込み段階：公開予報の上限案（range日）または確定杯数（exact日）を満たす最小の段階。
func choose_tier() -> String:
	if policy == "always_small":
		return "small"
	if policy == "always_large":
		return "large"
	var target := target_cups()
	for tier in ["small", "medium", "large"]:
		if int(tier_reach[tier]) >= target:
			return tier
	return "large"


func target_cups() -> int:
	if levels_on and level_forecast_target:
		return int(Forecast.total()["high"])
	if info_mode == "visible":
		return visible_target()
	return int(Forecast.total()["high"])


## v3（予報を読まない）の見込み杯数。プレイヤーに見えるものだけで決める：
##   Day1（固定需要の日）＝張記の会話で主人公が言う目安（fixed_demand）。
##   それ以外＝（前日の注文杯数＋客足の言葉の帯の中心）÷2を四捨五入し、今朝のDMの匂わせで±1（many＋1・few−1）。
##   下限版（lower_only）＝前日の注文杯数だけ。
## 客足の言葉の帯の中心は「言葉と数の対応を覚えた」熟練プレイヤーの見立て（UiLabels.demand_row_center）。
func visible_target() -> int:
	var fixed := int(Rules.day_overrides(GameState.day_count).get("fixed_demand", 0))
	if fixed > 0:
		return fixed
	var previous: Dictionary = panel.session.previous_day_record()
	var band := UiLabels.demand_row_center(UiLabels.demand_word(GameState.reputation))
	var yesterday := int(previous.get("planned_cups", 0)) if not previous.is_empty() else band
	if lower_only:
		return yesterday
	return roundi((yesterday + band) / 2.0) + dm_hint()


## 今朝届いたDMの匂わせ：many があれば＋1、few があれば−1（なければ0）。
func dm_hint() -> int:
	var hint := 0
	for item in panel.session.phone_dm():
		if int(item["day"]) != GameState.day_count:
			continue
		if str(item["hint"]) == "many":
			hint = 1
		elif str(item["hint"]) == "few" and hint == 0:
			hint = -1
	return hint


## v3の仕入れの必要数：自分が受けた直近2夜の注文のタグの割合×見込み杯数（切り上げ）。注文を見ていなければ空。
func visible_need(target: int) -> Dictionary:
	var tag_cups := {}
	var total := 0
	for night in seen_nights.slice(maxi(seen_nights.size() - 2, 0)):
		for tag in night["tags"]:
			tag_cups[tag] = int(tag_cups.get(tag, 0)) + int(night["tags"][tag])
		total += int(night["cups"])
	var need := {}
	if total <= 0:
		return need
	for tag in tag_cups:
		need[tag] = ceili(float(target) * float(tag_cups[tag]) / float(total))
	return need


## 情報量の実験（UI準備D）：仕入れの必要数を、v2（旧予報の上限案のタグ別必要数）とv3（前の晩までに受けた注文のタグの割合）の混ぜ合わせにする。
## 旧予報の必要数の1単位ごと（タグ×番号。常連の分とモブの分）に、確率 p（常連は level_p_reg、モブは level_p_mob）で「前もって知っている」とする。
## 知っている単位はそのまま数え、知らない分はv3の見積りの同じ割合で置き換える：
##   need[tag] = 知っている単位の数 ＋ ceil(v3の見積り[tag] × 知らない単位の数 ÷ 旧予報の必要数[tag])
## 旧予報の必要数が0のタグ（v3の見積りには出る）は、知らない割合（1−p。常連・モブの単位数で重みづけ）だけ見積りを残す。
## p＝0 → v3の補う版と同じ、p＝1 → 旧予報の必要数そのもの。単位ごとの当たりは専用の決まった値（シード・日・グループ・タグ・番号のハッシュ）で、
## ゲーム本体の乱数（seed()）には触れず、同じ周・同じ日なら p を上げるほど「知っている」が増える一方になる（単調）。
func levels_need(target: int) -> Dictionary:
	var full: Dictionary = (Forecast.cases().back() as Dictionary)["required"]
	var regular: Dictionary = Forecast.required_estimated(0)   # 名前あり客の分（モブの割り振りを足す前）
	var estimate: Dictionary = visible_need(target)
	var total_units := 0
	var regular_units := 0
	for tag in full:
		total_units += int(full[tag])
		regular_units += mini(int(regular.get(tag, 0)), int(full[tag]))
	var mob_units := total_units - regular_units
	var p_all := (level_p_reg * regular_units + level_p_mob * mob_units) / float(maxi(total_units, 1))
	var tags := {}
	for tag in full:
		tags[tag] = true
	for tag in estimate:
		tags[tag] = true
	var need := {}
	for tag in tags:
		var total_t := int(full.get(tag, 0))
		if total_t <= 0:
			var rest := ceili(float(estimate.get(tag, 0)) * (1.0 - p_all))
			if rest > 0:
				need[tag] = rest
			continue
		var regular_t := mini(int(regular.get(tag, 0)), total_t)
		var known := 0
		for k in range(regular_t):
			if info_draw("reg", str(tag), k) < level_p_reg:
				known += 1
		for k in range(total_t - regular_t):
			if info_draw("mob", str(tag), k) < level_p_mob:
				known += 1
		need[tag] = known + ceili(float(estimate.get(tag, 0)) * float(total_t - known) / float(total_t))
	return need


## 備蓄型の仕入れ（info=stock・方針 stockpile）。予報も見込みも読まない。
##   日持ちする7材料（STOCK_DURABLE）：手元が k 単位（購入単位＝1袋の個数×k）を切ったら、袋を買い足す。
##     stock_pieces（引数 [9]＝pieces）のときは k＝手元の個数（袋の数ではない）：k 個を切ったら1袋買い足す（袋はどれも k 個より多い）。
##   生もの3タグ（STOCK_FRESH）：毎朝、手元（前日の残りを含む）が k 単位になるよう買い足す。
##     stock_p が0以上のときは、タグごと・夜ごとに確率 p で「今夜の必要を知っている」とし、その分だけ買う（必要が0なら買わない）。
##     知らない分は備蓄の数（k単位）で補う。当たりは info_draw（専用の決まった値）。
##   予算は「使える」の範囲（cash()）。足りないときは、足りない材料のうち袋の値段が一番安いものから買う。
func stockpile_shop() -> void:
	var targets := {}
	for pair in STOCK_DURABLE:
		targets[str(pair[1])] = stock_k if stock_pieces else stock_k * pack_of(str(pair[1])).count
	var full: Dictionary = {}
	if stock_p >= 0.0:
		full = (Forecast.cases().back() as Dictionary)["required"]
	for pair in STOCK_FRESH:
		var item := str(pair[1])
		var target: int = stock_k if stock_pieces else stock_k * pack_of(item).count
		if stock_p >= 0.0 and info_draw("fresh", str(pair[0]), 0) < stock_p:
			target = int(full.get(str(pair[0]), 0))
		targets[item] = target
	if two_gu_buy:
		# 案G＋仕入れ：最安・2番目に安い日持ちする具も、k 個（備蓄型は個数 k のぶん）手元に置く
		var gu_order := second_gu_order()
		for i in range(2):
			targets[str(gu_order[i])] = maxi(int(targets.get(str(gu_order[i]), 0)), stock_k if stock_pieces else stock_k * pack_of(str(gu_order[i])).count)
	var guard := 0
	while guard < 80:
		guard += 1
		var best := {}
		for item in targets:
			if GameState.fresh_count(str(item)) >= int(targets[item]):
				continue
			var pack: Dictionary = pack_of(str(item))
			if cash() >= int(pack.price) and (best.is_empty() or int(pack.price) < int(best.price)):
				best = pack
		if best.is_empty():
			break
		buy(str(best.shop), str(best.id))
	if panel.session.market_shop != "":
		act("shop_exit")
		panel.session.leave_shop()


## 品目の購入単位（1袋）：{ shop, id, price, count }。袋が複数あれば（モツ・海老の小口など）個数が一番多い袋。
func pack_of(item: String) -> Dictionary:
	var best := {}
	for shop_id in SHOPS:
		for good in PlaySession.shop_goods(shop_id):
			if str(good.get("item", "")) == item and (best.is_empty() or int(good.get("count", 1)) > int(best.count)):
				best = { "shop": shop_id, "id": str(good.get("id", "")), "price": int(good.get("price", 0)), "count": int(good.get("count", 1)) }
	return best


## 0以上1未満の決まった値（情報量の実験の「知っているか」の当たり）。乱数の状態を持たない。
func info_draw(group: String, tag: String, k: int) -> float:
	var h: int = ("%d|%d|%s|%s|%d" % [cur_seed, GameState.day_count, group, tag, k]).hash()
	h = (h ^ (h >> 15)) & 0xFFFFFF
	return float(h) / 16777216.0


## --- 修繕基金の方針（4-9③） ---

## CLOSEの語りを読み終えた時点で、方針に応じて基金を積む。記録は fund_log（日ごとの額・積む前の上限・
## 積んだ後の累計）と fund_stage_days（各段階に初めて届いた日）。
func fund_contribute() -> void:
	var limit_before := RepairFund.max_contribution(RepairFund.first_open_target())
	var safe_before := RepairFund.safe_limit()
	var reserve_before := int(RepairFund.next_day_reserve()["total"])
	var paid_before := RepairFund.paid()
	var pushed := 0
	match policy:
		"fund_final_only":
			if GameState.is_final_day():
				pushed = push_fund_max()
		"fund_steady":
			# 1晩の上限ぶんを一度に積めるときだけ積む（積めない夜は積まない）
			if RepairFund.max_contribution(RepairFund.first_open_target()) >= RepairFund.nightly_remaining():
				pushed = push_fund_max()
		"fund_max_safe":
			pushed = push_fund_max()
	fund_log.append({ "day": GameState.day_count, "amount": pushed, "limit_before": limit_before,
		"safe_limit": safe_before, "reserve": reserve_before, "paid_before": paid_before, "paid_after": RepairFund.paid(),
		"targets": fund_target_paid_all() })
	for id in RepairFund.repaired_ids():
		if not fund_stage_days.has(id):
			fund_stage_days[id] = GameState.day_count


## 対象ごとの累計 { 対象id: 累計 }（対象のidは RepairFund.targets() から読む）。
func fund_target_paid_all() -> Dictionary:
	var out := {}
	for t in RepairFund.targets():
		out[t["id"]] = RepairFund.target_paid(t["id"])
	return out


## 刻み1つぶんを、押せるなら押す（DebugPanel の操作経路）。積んだ額を返す。
func push_fund(step: int) -> int:
	if not RepairFund.can_contribute(RepairFund.first_open_target(), step):
		return 0
	var before := GameState.money
	act("fund")
	panel.session.contribute_fund(step)
	return before - GameState.money


## 積めるだけ積む：大きい刻みから順に、押せる間だけ押す。
func push_fund_max() -> int:
	var total := 0
	var ordered := RepairFund.steps().duplicate()
	ordered.reverse()
	for step in ordered:
		var guard := 0
		while RepairFund.can_contribute(RepairFund.first_open_target(), int(step)) and guard < 100:
			guard += 1
			total += push_fund(int(step))
	return total


## 基金の実行の自動検査（結果の最上位 fund_checks）：
##   control … 同じシードの基準方針と fund_final_only で cash_plus_repair が一致するか、および
##             1〜6日目の日別の行が完全に一致するか（基金の方針が他の点で基準方針と同一である証明）
##   safety  … 基金の全方針・全シードで game_over の事故・stalled が無く、全周が完走したか
func fund_checks(results: Array) -> Dictionary:
	var by_key := {}
	for r in results:
		by_key["%s|%d" % [r["policy"], int(r["seed"])]] = r
	var control_pairs := 0
	var cash_mismatch := []
	var rows_mismatch := []
	for r in results:
		if r["policy"] != "fund_final_only":
			continue
		var base = by_key.get("%s|%d" % [FUND_BASE_POLICY, int(r["seed"])])
		if base == null:
			continue
		control_pairs += 1
		var a: Dictionary = base["result_summary"]
		var b: Dictionary = r["result_summary"]
		if int(a.get("cash_plus_repair", -1)) != int(b.get("cash_plus_repair", -2)):
			cash_mismatch.append({ "seed": r["seed"], "base": a.get("cash_plus_repair"), "fund": b.get("cash_plus_repair") })
		var early_equal := true
		for i in range(mini(6, mini((base["rows"] as Array).size(), (r["rows"] as Array).size()))):
			if JSON.stringify(base["rows"][i]) != JSON.stringify(r["rows"][i]):
				early_equal = false
		if not early_equal:
			rows_mismatch.append(r["seed"])
	var fund_runs := 0
	var game_over := 0
	var stalled := 0
	var incomplete := []
	for r in results:
		if not POLICIES_FUND.has(r["policy"]):
			continue
		fund_runs += 1
		for inc in r["incidents"]:
			if str(inc.get("type", "")) == "game_over":
				game_over += 1
		if bool(r["stalled"]):
			stalled += 1
		if not bool(r["completed"]):
			incomplete.append({ "policy": r["policy"], "seed": r["seed"] })
	return { "control_pairs": control_pairs, "cash_plus_repair_mismatch": cash_mismatch,
		"days_1_to_6_rows_mismatch": rows_mismatch, "fund_runs": fund_runs,
		"game_over_incidents": game_over, "stalled_runs": stalled, "incomplete_runs": incomplete }


## 各周の目標判定（実装の Result.judge_goals そのもの）。基金の方針を含む実行の最上位 goals_by_run。
func goals_by_run(results: Array) -> Array:
	var out := []
	for r in results:
		var summary: Dictionary = r["result_summary"]
		out.append({ "policy": r["policy"], "seed": r["seed"],
			"goals": Result.judge_goals(summary, Rules.goals(), Rules.final_day()) if not summary.is_empty() else [] })
	return out


## ニュース／共通イベント／張記の会話（UI準備C③）の表示専用 TEXT か（type が TEXT で、part が news・common_event・prep_talk）。
func is_display_only(ev) -> bool:
	return ev is Dictionary and str(ev.get("type", "")) == "TEXT" \
			and ["news", "common_event", "prep_talk"].has(str(ev.get("part", "")))


func act(kind: String) -> void:
	clicks += 1
	counts[kind] = int(counts.get(kind, 0)) + 1


func fresh_supply(tag: String) -> int:
	var n := 0
	for id in GameState.inventory:
		if Ingredients.tags_for(str(id)).has(tag):
			n += GameState.fresh_count(str(id))
	return n


## 朝の仕入れ。公開予報の上限案の必要タグ数（SNSタブと同じデータ）に対して、タグ別に
## 不足している分を最安の組み合わせで買う。市場が開いていない日（Day1。初日セットが
## PREPで自動購入される）と空の椀方針では何も買わない。
func shop() -> void:
	if GameState.day_count < Rules.market_open_from_day() or policy == "bare_broth":
		return
	if policy != "strength_neglect":
		while GameState.dashi_units < 2 and cash() >= 16:
			buy("meat_wholesale", "dashi")
	if stock_on:
		stockpile_shop()
		return
	var need: Dictionary = visible_need(target_cups()) if info_mode == "visible" else (Forecast.cases().back() as Dictionary)["required"]
	if levels_on:
		need = levels_need(target_cups())
	if policy == "cheap_valid":
		var cups := target_cups()
		need = { "SOUR": cups, "FILLING": cups }
	for tag in Forecast.TAG_ORDER:
		var n := int(need.get(tag, 0))
		var guard := 0
		while n > 0 and fresh_supply(str(tag)) < n and guard < 12:
			guard += 1
			var short := n - fresh_supply(str(tag))
			var best := {}
			for shop_id in SHOPS:
				for good in PlaySession.shop_goods(shop_id):
					var id := str(good.get("item", ""))
					if id == "" or id == "dashi" or not Ingredients.tags_for(id).has(str(tag)):
						continue
					var units := maxi(int(good.get("count", 1)), 1)
					var option := { "shop": shop_id, "id": str(good.get("id", "")), "price": int(good.price),
						"score": ceili(float(short) / units) * int(good.price),
						"unit": float(good.price) / units }
					if best.is_empty() or option.score < best.score \
							or (option.score == best.score and option.unit < best.unit):
						best = option
			if best.is_empty() or cash() < int(best.price):
				break
			buy(str(best.shop), str(best.id))
	if two_gu_buy:
		buy_second_gu(target_cups(), int(need.get("FILLING", 0)))
	if info_mode == "visible" and policy == "forecast_favorites":
		# 今夜の客の並びは読まない（見えない）。好物を知っている客（来店記録）の分を、1つずつ多く持っておく
		for cid in GameState.customer_memory:
			if GameState.knows_favorite(str(cid)):
				var known_favorite := str((Day1Events._customer_flavor(str(cid)) as Dictionary).get("favorite", ""))
				if known_favorite != "":
					ensure(known_favorite, GameState.fresh_count(known_favorite) + 1)
	elif policy in ["forecast_favorites", "favorite_oracle"]:
		for slot in GameState.today_plan.get("slots", []):
			for cid in slot.customers:
				var flavor: Dictionary = Day1Events._customer_flavor(str(cid))
				if bool(flavor.get("is_mob", false)):
					continue
				var known := GameState.knows_favorite(str(cid))
				if policy == "forecast_favorites" and not known:
					continue
				var favorite := str(flavor.get("favorite", ""))
				if favorite != "":
					ensure(favorite, GameState.fresh_count(favorite) + 1)
	if panel.session.market_shop != "":
		act("shop_exit")
		panel.session.leave_shop()


func ensure(id: String, target: int) -> void:
	while GameState.fresh_count(id) < target:
		var choices: Array = []
		for shop_id in SHOPS:
			for good in PlaySession.shop_goods(shop_id):
				if str(good.get("item", "")) == id:
					var short := target - GameState.fresh_count(id)
					var units := int(good.get("count", 1))
					choices.append({ "shop": shop_id, "good": good,
						"score": ceili(float(short) / units) * int(good.price) })
		choices.sort_custom(func(a, b): return a.score < b.score)
		if choices.is_empty() or cash() < int(choices[0].good.price):
			return
		buy(str(choices[0].shop), str(choices[0].good.id))


## 判断と記録に使う現金：残金から、まだ引いていない運営費（水と炭）を除いた額。運営費を朝に引いていた頃（UI準備Dより前）の所持金と
## 同じ値＝予報ありの基準（v2）の判断・記録（day1_cash など）を保つため。運営費を市場を出るときに引くようにしたあとも、この値で判断する。
func cash() -> int:
	return GameState.money - panel.session.operating_cost_pending()


func buy(shop_id: String, id: String) -> void:
	if panel.session.market_shop != shop_id:
		if panel.session.market_shop != "":
			act("shop_exit")
			panel.session.leave_shop()
		act("shop_enter")
		panel.session.select_stall(shop_id)
	var before := GameState.money
	act("purchase")
	panel.session.buy_item(shop_id, id)
	purchases += before - GameState.money


func cook(order: Dictionary) -> void:
	# 自分が受けた注文（注文カードで見えるタグ×杯数）を覚える（v3の仕入れの必要数の元）
	var order_cups := int(order.get("servings", 1))
	for order_tag in order.get("wanted_tags", []):
		night_tags[str(order_tag)] = int(night_tags.get(str(order_tag), 0)) + order_cups
	night_cups += order_cups
	if policy == "bare_broth":
		return
	var wanted: Array = (order.get("wanted_tags", []) as Array).duplicate()
	var n := int(order.get("servings", 1))
	var is_mob := bool(order.get("is_mob", false))
	if policy == "cheap_valid":
		wanted = cheap_wanted(n)
	if policy == "forecast_mistakes" and GameState.day_count in [3, 5] \
			and panel.session.open.slot_index == 0 and not is_mob:
		wanted = ["SAVORY", "FILLING"] if not wanted.has("SAVORY") else ["HOT", "POWER"]
	# 品質失敗2件（個人1杯＋団体1組）を3日目に1回ずつ意図的に起こす（10.13の3番目）。
	if policy == "two_failures" and GameState.day_count == 3:
		if not is_mob and not failed_named:
			failed_named = true
			wanted = ["SAVORY", "FILLING"] if not wanted.has("SAVORY") else ["HOT", "POWER"]
			failure_log.append({ "day": 3, "kind": "named", "customer": str(order.get("customer", "")) })
		elif is_mob and not failed_mob:
			failed_mob = true
			wanted = ["SAVORY", "FILLING"] if not wanted.has("SAVORY") else ["HOT", "POWER"]
			failure_log.append({ "day": 3, "kind": "mob", "customer": str(order.get("customer", "")) })
	var added: Array = []
	for tag in wanted:
		if added.size() >= 2:
			break
		var id := choose(str(tag), n)
		if id != "" and not added.has(id):
			act("ingredient")
			panel.session.select_ingredient(id)
			added.append(id)
		elif id == "" and is_neglect():
			# 鮮度のミス：新鮮な在庫が無ければ傷んだ在庫も使う（判定が1段階下がる）。
			var damaged_id := choose_damaged(str(tag), n)
			if damaged_id != "" and not added.has(damaged_id):
				act("ingredient_damaged")
				panel.session.select_ingredient(damaged_id, true)
				added.append(damaged_id)
	if improvise:
		improvise_bowl(n)
	var customer := str(order.get("customer", ""))
	if policy == "forecast_favorites" and GameState.knows_favorite(customer):
		add_favorite(order, added, n)
	elif policy == "favorite_oracle" and not is_mob:
		add_favorite(order, added, n)
	if two_gu_on:
		add_cheap_topping(n)
	last_cook_toppings = 0
	for id in panel.session.open.current_bowl.get("additions", []):
		if Ingredients.is_topping(str(id)):
			last_cook_toppings += 1


## 日持ちする具（SECOND_GU）を、単価の安い順（同じなら id 順）に並べたもの。
func second_gu_order() -> Array:
	var ids: Array = SECOND_GU.duplicate()
	ids.sort_custom(func(a, b):
		var ua: float = float(pack_of(str(a)).price) / float(maxi(int(pack_of(str(a)).count), 1))
		var ub: float = float(pack_of(str(b)).price) / float(maxi(int(pack_of(str(b)).count), 1))
		if not is_equal_approx(ua, ub):
			return ua < ub
		return str(a) < str(b))
	return ids


## 案G＋仕入れ：朝の仕入れで、2つ目の具を買う。units＝最安の具の必要個数（1杯につき1個）、alt＝2番目に安い具の必要個数。
func buy_second_gu(units: int, alt: int) -> void:
	var order := second_gu_order()
	if units > 0:
		ensure(str(order[0]), units)
	if alt > 0:
		ensure(str(order[1]), alt)


## 計測H・案G：具が1種類しか入っていない椀に、手持ちの一番安い具（単価の安い順。今ある新鮮な在庫が n 個以上）をもう1つ足す。
## 足せる具が無い・枠（3つ）がいっぱいなら、そのまま（減点を受ける）。単価は市場でいちばん大きい袋の 値段÷個数。
func add_cheap_topping(n: int) -> void:
	var additions: Array = panel.session.open.current_bowl.get("additions", [])
	if additions.size() >= OpenController.MAX_ADDITIONS:
		return
	var toppings := 0
	for id in additions:
		if Ingredients.is_topping(str(id)):
			toppings += 1
	if toppings >= 2:
		return
	var best := ""
	var best_unit := 1.0e9
	if two_gu_buy:
		# 仕入れまで入れる版：2つ目の具は、日持ちする具を安い順に見て、手持ちにあるもの（注文に合う具と同じ材料は不可）。無ければ減点を受ける
		for id in second_gu_order():
			if not additions.has(str(id)) and GameState.fresh_count(str(id)) >= n:
				best = str(id)
				break
		if best != "":
			act("ingredient")
			panel.session.select_ingredient(best)
		return
	for id in GameState.inventory:
		var item := str(id)
		if not Ingredients.is_topping(item) or additions.has(item) or GameState.fresh_count(item) < n:
			continue
		var pack := pack_of(item)
		if pack.is_empty():
			continue
		var unit: float = float(pack.price) / float(maxi(int(pack.count), 1))
		if unit < best_unit or (is_equal_approx(unit, best_unit) and item < best):
			best = item
			best_unit = unit
	if best != "":
		act("ingredient")
		panel.session.select_ingredient(best)


## 計測H：提供のあとに、日の評価の集計（log_quality_counts）へ増えた杯を見て、案G（具が1種類なら−1段階）と案T（チップ）を反映する。
## 前回から増えた分だけ（日が変わって 0 に戻ったら、数え直す）。椀の中身（具の数・減点の有無）は、提供のあとも次の客が来るまで残っている。
func settle_serves() -> void:
	var counts_now: Dictionary = panel.session.log_quality_counts
	for grade in GRADE_DOWN:
		if int(counts_now.get(grade, 0)) < int(seen_counts.get(grade, 0)):
			seen_counts = {}
			break
	var bowl: Dictionary = panel.session.open.current_bowl if panel.session.open != null else {}
	var additions: Array = bowl.get("additions", [])
	var toppings := 0
	for id in additions:
		if Ingredients.is_topping(str(id)):
			toppings += 1
	var already_penalized := bool(bowl.get("penalty_strength", false)) or bool(bowl.get("penalty_spoiled", false))
	# 先に、前回から増えた杯数を全部の評価について読む（減点で1段階下げた杯を、次の評価の「増えた分」と数えない）
	var added_by_grade := {}
	for grade in ["GREAT", "GOOD", "OK", "BAD"]:
		added_by_grade[grade] = int(counts_now.get(grade, 0)) - int(seen_counts.get(grade, 0))
	for grade in ["GREAT", "GOOD", "OK", "BAD"]:
		var added: int = int(added_by_grade[grade])
		if added <= 0:
			continue
		var final_grade: String = grade
		if two_gu_on and additions.is_empty():
			gu_fallback_total += added
			toppings = last_cook_toppings
		if two_gu_on and toppings < 2 and not already_penalized:
			final_grade = GRADE_DOWN[grade]
			if final_grade != grade:
				counts_now[grade] = int(counts_now[grade]) - added
				counts_now[final_grade] = int(counts_now.get(final_grade, 0)) + added
			gu_pen_today += added
			gu_pen_total += added
		var tip := tip_good if final_grade == "GOOD" else (tip_great if final_grade == "GREAT" else 0)
		if tip > 0:
			GameState.apply_money(tip * added)
			tips_today += tip * added
			tips_total += tip * added
	seen_counts = counts_now.duplicate()


## visible_improvise：椀に味か具が欠けているとき、その軸の素材をほかの在庫から1つ足して、売れる椀にする
## （注文のタグの素材が手元に無い日に、プレイヤーなら試すこと）。手元にその軸の素材が無ければ何もしない。
func improvise_bowl(n: int) -> void:
	var additions: Array = panel.session.open.current_bowl.get("additions", [])
	var axes := [["flavor", ["HOT", "MELLOW", "SOUR", "BITTER", "SAVORY"]], ["topping", ["POWER", "GENTLE", "FILLING", "BITE", "TREAT"]]]
	for axis in axes:
		var has := false
		for id in additions:
			has = has or (Ingredients.is_flavor(str(id)) if axis[0] == "flavor" else Ingredients.is_topping(str(id)))
		if has or additions.size() >= OpenController.MAX_ADDITIONS:
			continue
		var pick := ""
		for tag in axis[1]:
			var id := choose(str(tag), n)
			if id == "":
				continue
			if pick == "" or (GameState.fresh_count(id) >= n and GameState.fresh_count(pick) < n):
				pick = id
		if pick != "":
			act("ingredient")
			panel.session.select_ingredient(pick)
			additions = panel.session.open.current_bowl.get("additions", [])


## 「安い完成料理だけ」：売れる最小構成（味1＋具1）を、手元にある安い素材から選ぶ。
## 優先は旧版と同じ SOUR＋FILLING。初日（市場が閉まっていて初日セットしか無い）は
## SOUR が無いので、セットにある味（HOT→MELLOW→SAVORY）と具（FILLING→GENTLE→POWER）へ落とす。
func cheap_wanted(n: int) -> Array:
	var flavor := "SOUR"
	for tag in ["SOUR", "HOT", "MELLOW", "SAVORY"]:
		if fresh_supply(tag) >= n:
			flavor = tag
			break
	var topping := "FILLING"
	for tag in ["FILLING", "GENTLE", "POWER", "BITE", "TREAT"]:
		if fresh_supply(tag) >= n:
			topping = tag
			break
	return [flavor, topping]


func add_favorite(order: Dictionary, added: Array, n: int) -> void:
	var favorite := str(order.get("favorite", ""))
	if favorite != "" and not added.has(favorite) and GameState.fresh_count(favorite) >= n:
		act("ingredient")
		panel.session.select_ingredient(favorite)


func choose(tag: String, n: int) -> String:
	var ids: Array = []
	for id in GameState.inventory:
		if Ingredients.tags_for(str(id)).has(tag) and GameState.fresh_count(id) > 0:
			ids.append(str(id))
	ids.sort_custom(func(a, b):
		var ac: int = GameState.fresh_count(a)
		var bc: int = GameState.fresh_count(b)
		if (ac >= n) != (bc >= n):
			return ac >= n
		# 先に傷む新鮮在庫から使う。同じなら潤沢な在庫、最後はidで安定させる。
		var aa := first_day(a)
		var ba := first_day(b)
		if aa != ba:
			return aa < ba
		if ac != bc:
			return ac > bc
		return a < b)
	return str(ids[0]) if not ids.is_empty() else ""


func choose_damaged(tag: String, n: int) -> String:
	for id in GameState.inventory:
		if Ingredients.tags_for(str(id)).has(tag) and GameState.damaged_count(str(id)) >= 1:
			return str(id)
	return ""


func first_day(id: String) -> int:
	var batches: Array = GameState.perishable_batches.get(id, [])
	for batch in batches:
		if GameState.day_count - int(batch.day) < 2:
			return int(batch.day)
	return 999


## 鍋の調整。濃さ1/5は減点なので、水は「先にだしで濃さを上げてから」入れる
## （3→5→3で減点なしに残量+2。だしが無ければ従来どおり水のみ）。
## strength_neglect方針は、残量不足か濃さ0（提供不可）でない限り調整しない。
func fix_pot() -> bool:
	if not panel.session.can_touch_pot():
		return false
	var n: int = int(panel.session.react_for_now().get("servings", 1))
	var v := int(GameState.soup.remaining_servings)
	var s := int(GameState.soup.strength)
	if v >= n:
		if policy == "bare_broth":
			return false
		if is_neglect() and s >= 1:
			return false
		if s >= 2 and s <= 4:
			return false
	act("pot_open")
	panel.session.open_pot()
	var changed := false
	for attempt in range(6):
		v = int(GameState.soup.remaining_servings)
		s = int(GameState.soup.strength)
		var need_water := (v < n or s >= 5) and GameState.water_reachable()
		if s < 2 and GameState.can_add_dashi() and not panel.session.pot_locked_until_water():
			act("dashi")
			panel.session.add_dashi()
			changed = true
		elif need_water and GameState.can_add_water():
			# 水で濃さが1以下になるなら、先にだしで濃さを上げておく。
			if s - GameState.WATER_STRENGTH_DELTA < 2 and GameState.can_add_dashi() \
					and s + GameState.DASHI_STRENGTH_DELTA <= GameState.STRENGTH_MAX:
				act("dashi")
				panel.session.add_dashi()
				changed = true
			else:
				act("water")
				panel.session.add_water()
				changed = true
		else:
			# 鍋を直したいのに直せないときだけ、理由を記録する（結果は変えない）。
			# 水が要るのに足せない：doses＝回数切れ／remaining＝残量条件／strength_floor＝濃さの下限。
			# 濃さが低い（2未満）のに、だしを足せない：no_dashi。
			var reason := ""
			if (v < n or s >= 5) and not GameState.can_add_water():
				reason = "other"
				if int(GameState.soup.get("water_doses", 0)) <= 0:
					reason = "doses"
				elif v > Rules.pot_capacity() - GameState.WATER_SERVINGS:
					reason = "remaining"
				elif s - GameState.WATER_STRENGTH_DELTA < GameState.STRENGTH_HARD_FLOOR:
					reason = "strength_floor"
			elif s < 2 and not GameState.can_add_dashi():
				reason = "no_dashi"
			if reason != "":
				water_stop_log.append({ "policy": policy_label, "seed": cur_seed, "day": GameState.day_count,
					"reason": reason, "remaining": v, "strength": s, "need": n,
					"dashi_units": GameState.dashi_units })
			break
	var locked: bool = (panel.session.pot_locked_until_water() and GameState.can_add_water()) \
		or (panel.session.pot_locked_until_dashi() and GameState.can_add_dashi())
	if not locked:
		act("pot_back")
		panel.session.pot_open = false
		panel.session.resume_after_shortage()
		panel.session.notify_changed()
	return changed


func day_row() -> Dictionary:
	var served := 0
	var sale := 0
	var declined := 0
	# 常連実績（10.13「現金・品質・常連実績」）：名前あり客（instance idが"mob#"始まりで
	# ない）への提供のGOOD以上・GREATの杯数。単独のresultと集計のresults辞書の両方を見る。
	var reg_cups := 0
	var reg_good_plus := 0
	var reg_great := 0
	for rec in GameState.served:
		if not bool(rec.get("discarded", false)):
			served += int(rec.get("servings", 0))
			sale += int(rec.get("sale", 0))
			if not str(rec.get("customer", "")).begins_with("mob#"):
				reg_cups += int(rec.get("servings", 0))
				var grades: Dictionary = (rec.get("results", {}) as Dictionary).duplicate()
				var single := str(rec.get("result", ""))
				if single != "":
					grades[single] = int(grades.get(single, 0)) + int(rec.get("servings", 0))
				reg_great += int(grades.get("GREAT", 0))
				reg_good_plus += int(grades.get("GREAT", 0)) + int(grades.get("GOOD", 0))
		if bool(rec.get("declined", false)):
			declined += 1
	var quality: float = panel.session.quality_score(panel.session.log_quality_counts, panel.session.log_judged_planned_cups)
	var row := _day_row_base(served, sale, declined, reg_cups, reg_good_plus, reg_great, quality)
	if tip_gu_on:
		row["tips"] = tips_today
		row["gu_penalized"] = gu_pen_today
	return row


func _day_row_base(served: int, sale: int, declined: int, reg_cups: int, reg_good_plus: int, reg_great: int, quality: float) -> Dictionary:
	return { "day": GameState.day_count, "cash": GameState.money, "open_rep": GameState.reputation,
		"next_rep": roundi(GameState.reputation * 0.7 + quality * 0.3), "quality": quality,
		"demand": panel.session.log_planned_cups, "judged_demand": panel.session.log_judged_planned_cups,
		"served": served, "unserved": panel.session.log_planned_cups - served, "declined_records": declined,
		"regular_cups": reg_cups, "regular_good_plus": reg_good_plus, "regular_great": reg_great,
		"sales": sale, "grades": panel.session.log_quality_counts.duplicate(),
		"spoiled_value": panel.session.spoiled_value(panel.session.log_spoiled_items),
		"water": panel.session.log_water_used, "dashi": panel.session.log_dashi_used,
		"soup_left": GameState.soup.get("remaining_servings", 0),
		"stock": GameState.inventory.duplicate(), "actions_cumulative": clicks,
		"spend": Ledger.spend_by_category_today(), "closed_early": panel.session.log_closed_early }
