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
##   [2]=出力ファイル名(既定playthrough_results.json) [3]=方針のカンマ区切り絞り込み

const OUT := "res://planning/playtest_2026_10_11/"
const POLICIES_OLD := ["forecast_good", "forecast_favorites", "always_small", "always_large",
	"cheap_valid", "bare_broth", "forecast_mistakes"]
## 新規5方針（10.13の比較方針で旧版に無かったもの）。favorite_oracleは好物IDを内部データ
## から読む「上限の目安」であり、画面からは分からない情報を使う（通常の方針とは別枠）。
## decline_one_group は「毎日1組を断る」強い版、decline_once は「3日目に1組だけ断る」弱い版
## （10.13の「1組を断る」をどちらの意味でも読めるよう、両方を測る）。
const POLICIES_NEW := ["favorite_oracle", "no_split", "strength_neglect",
	"decline_one_group", "two_failures", "decline_once"]
## 各仕込み段階が（水・だしの操作込みで）届く最大杯数（小8→水2回で12／中11→水1回で13／
## 大14→水0回。鍋の同時容量14・水は残量12以下のときだけ足せる。DESIGN.md 10.3.8）。
## 修繕基金の方針（4-9③。別枠）。既定の方針一覧（POLICIES_OLD + POLICIES_NEW）には入れず、引数[3]で
## 名前を指定したときだけ走る。仕入れ・仕込み・調理・接客の判断は基準方針 forecast_good と同じ（このファイルの
## policy == の分岐のどれにも当たらない＝既定の分岐）で、差は CLOSE の基金の操作だけ。押すのは DebugPanel の
## _on_fund_contribute_pressed 経由（実際の操作経路）。刻み・上限は RepairFund から読み、数値は直書きしない。
##   fund_final_only … 最終日のCLOSEだけ、安全上限の範囲で積めるだけ積む（対照実験）
##   fund_steady     … 毎晩、刻みの中央値（week7では50）を1回積む（安全上限・最終段階までの残りの範囲）
##   fund_max_safe   … 毎晩、安全上限と最終段階までの残りの範囲で積めるだけ積む
const POLICIES_FUND := ["fund_final_only", "fund_steady", "fund_max_safe"]
const FUND_BASE_POLICY := "forecast_good"
const TIER_REACH := { "small": 12, "medium": 13, "large": 14 }
const SHOPS := ["produce", "meat_wholesale", "dry_goods", "tofu_noodles", "seafood", "scraps"]

var tree: SceneTree
var panel
var policy := ""
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
	var policies: Array = []
	for p in POLICIES_OLD + POLICIES_NEW:
		if only.is_empty() or only.has(p):
			policies.append(p)
	for p in POLICIES_FUND:
		if only.has(p):
			policies.append(p)
	var results: Array = []
	for p in policies:
		var n := seeds_old if POLICIES_OLD.has(p) else seeds_new
		for run_seed in range(1, n + 1):
			results.append(await play(p, run_seed))
		print("PLAYTEST_PROGRESS ", p, " ", n, " runs")
	var output := { "commit": git_head(), "tracked_changes": git_dirty(),
		"engine": Engine.get_version_info(), "daily_operating_cost": Rules.daily_operating_cost(),
		"seeds_old": seeds_old, "seeds_new": seeds_new,
		"policies": policies, "runs": results }
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


func play(p: String, run_seed: int) -> Dictionary:
	policy = p
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
		while panel.flow.runner != null and panel.flow.runner.status == EventRunner.Status.PLAYING \
				and is_display_only(panel.flow.runner.current()):
			panel._on_next_event_pressed()
		steps += 1
		if steps % 12 == 0:
			await tree.process_frame # release queue_free UI controls
		if GameState.phase == GameState.Phase.GAME_OVER:
			incidents.append({ "type": "game_over", "day": GameState.day_count, "cash": GameState.money })
			break
		if GameState.day_count == 1:
			if GameState.phase == GameState.Phase.PREP and not seen_prep:
				seen_prep = true
				day1_cash["after_wake"] = GameState.money
			if GameState.phase == GameState.Phase.OPEN and not seen_open:
				seen_open = true
				day1_cash["after_market"] = GameState.money
		var r: EventRunner = panel.flow.runner
		if GameState.phase == GameState.Phase.NEXT_DAY:
			rows.append(day_row())
			if GameState.day_count == 1:
				day1_cash["end"] = GameState.money
			if GameState.day_count == 7:
				# 実際の最終日の流れ（4-2）：advance_phase()がday_endingを発火して最終日の
				# 記録を累計（day_records）へ足し、結果画面（Phase.RESULT）へ入る。新しい周へは
				# 進めない（reset_for_new_gameは呼ばれない）。結果画面の集計（Result.summarize）を
				# 記録し、集計スクリプトがこのスクリプト内の日別集計と突き合わせる。
				panel.flow.advance_phase()
				result_phase = str(GameState.Phase.keys()[GameState.phase])
				result_summary = Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
				done = true
				break
			seed(run_seed * 1000 + GameState.day_count + 1)
			declined_group_today = false
			panel.flow.advance_phase()
			before_market = false
			continue
		if r.status == EventRunner.Status.DONE:
			# 修繕基金の方針のときだけ、CLOSEの語りを読み終えた時点（基金を積める時点）で積む。
			if GameState.phase == GameState.Phase.CLOSE and POLICIES_FUND.has(policy):
				fund_contribute()
			panel.flow.advance_phase()
			continue
		if GameState.phase == GameState.Phase.WAKE:
			panel.flow.advance_phase()
			continue
		var ev = r.current()
		var typ := str(ev.get("type", "")) if ev is Dictionary else ""
		if typ == "PREP_TIER":
			if GameState.day_count == 1 and not day1_cash.has("after_kit"):
				day1_cash["after_kit"] = GameState.money
			var tier := choose_tier()
			if GameState.money < int(Day1Events.prep_tier_by_id(tier).price):
				tier = "small"
			act("prep")
			panel._on_prep_tier_selected(tier)
			if GameState.day_count == 1:
				day1_cash["tier"] = tier
				day1_cash["after_tier"] = GameState.money
			continue
		if typ == "MARKET":
			if not before_market:
				shop()
				before_market = true
			act("market_exit")
			panel._on_market_exit_pressed()
			continue
		if GameState.phase == GameState.Phase.OPEN:
			if panel._pot_mode:
				incidents.append({ "type": "pot_mode_stuck", "day": GameState.day_count,
					"soup": GameState.soup.duplicate(), "dashi": GameState.dashi_units })
				stalled = true
				break
			if panel._pending_shortage_ev != null:
				if not fix_pot() and not panel._btn_close.disabled:
					act("close")
					panel._on_close_pressed()
				continue
			if typ == "ADJUST":
				handle_adjust()
				if stalled_flag:
					stalled = true
					break
				continue
			# 注文を取る前に濃さを整える（ADJUST中は通常の鍋操作がロックされる）。
			if typ not in ["SERVE", "REACT"] and not panel._btn_pot.disabled:
				fix_pot()
		if typ == "CHOICE":
			# 店主の距離感の選択（システム整理C2）：先頭の選択肢を押す。現行の21場面には無い（通らない分岐）
			act("story_choice")
			panel._on_story_choice_pressed(str(ev.get("choice_id", "")), str((ev["options"] as Array)[0]["id"]))
			continue
		if r.status == EventRunner.Status.WAITING_INPUT:
			act("input")
			panel._on_complete_input_pressed()
		else:
			act("next_text_event")
			panel._on_next_event_pressed()
	var result := { "policy": policy, "seed": run_seed, "completed": done,
		"stalled": stalled or steps >= 6000, "cash": GameState.money, "rep": GameState.reputation,
		"rows": rows, "incidents": incidents.duplicate(true), "actions": counts.duplicate(),
		"clicks": clicks, "purchases": purchases, "steps": steps, "day1_cash": day1_cash.duplicate(),
		"failures": failure_log.duplicate(true),
		"result_phase": result_phase, "result_summary": result_summary,
		"closing_stock_units": GameState.inventory.duplicate(), "dashi": GameState.dashi_units }
	if POLICIES_FUND.has(policy):
		result["fund_log"] = fund_log.duplicate(true)
		result["stage_reached"] = RepairFund.repaired_ids().size()
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
	var order: Dictionary = panel._react_for_now()
	var wanted := int(order.get("servings", 1))
	var is_mob := bool(order.get("is_mob", false))
	if int(GameState.soup.remaining_servings) < wanted or int(GameState.soup.strength) <= 0:
		fix_pot()
	if GameState.phase != GameState.Phase.OPEN:
		return
	cook(order)
	if is_mob:
		act("confirm")
		panel._on_complete_input_pressed()
		if panel._pending_group_choice:
			var achievable: int = panel._mob_achievable_servings(wanted)
			act("group_choice")
			var wants_decline := policy == "decline_one_group" \
					or (policy == "decline_once" and GameState.day_count == 3)
			if wants_decline and not declined_group_today:
				declined_group_today = true
				act("decline_group")
				panel._on_group_decline_pressed(wanted)
			elif achievable < wanted and panel._mob_recipe_number == 1 \
					and policy not in ["bare_broth", "cheap_valid", "no_split"]:
				panel._on_group_retry_pressed(achievable, wanted)
			elif achievable > 0:
				panel._on_group_serve_pressed(achievable, wanted)
			else:
				if policy != "bare_broth":
					incidents.append({ "type": "group_unsellable_declined", "day": GameState.day_count,
						"additions": panel._open.current_bowl.get("additions", []).duplicate() })
				act("decline_unsellable")
				panel._on_group_decline_pressed(wanted)
		return
	if panel._btn_complete_input.disabled:
		if panel._is_short_in_adjust() or panel._is_strength_zero_in_adjust():
			if not panel._btn_close.disabled:
				incidents.append({ "type": "forced_close", "day": GameState.day_count,
					"soup": GameState.soup.duplicate(), "dashi": GameState.dashi_units })
				act("close")
				panel._on_close_pressed()
				return
			stalled_flag = true
			incidents.append({ "type": "adjust_stuck", "day": GameState.day_count,
				"soup": GameState.soup.duplicate() })
			return
		# 味か具が欠けた椀（SaleRule）。断る。
		if policy != "bare_broth":
			incidents.append({ "type": "unsellable_declined", "day": GameState.day_count,
				"customer": str(order.get("customer", "")),
				"reasons": SaleRule.check(panel._open.current_bowl, GameState.soup).get("reasons", []),
				"additions": panel._open.current_bowl.get("additions", []).duplicate() })
		act("decline_unsellable")
		panel._on_customer_decline_pressed()
		return
	act("confirm")
	panel._on_complete_input_pressed()


## 仕込み段階：公開予報の上限案（range日）または確定杯数（exact日）を満たす最小の段階。
func choose_tier() -> String:
	if policy == "always_small":
		return "small"
	if policy == "always_large":
		return "large"
	var target := target_cups()
	for tier in ["small", "medium", "large"]:
		if int(TIER_REACH[tier]) >= target:
			return tier
	return "large"


func target_cups() -> int:
	return int(Forecast.total()["high"])


## --- 修繕基金の方針（4-9③） ---

## CLOSEの語りを読み終えた時点で、方針に応じて基金を積む。記録は fund_log（日ごとの額・積む前の上限・
## 積んだ後の累計）と fund_stage_days（各段階に初めて届いた日）。
func fund_contribute() -> void:
	var limit_before := RepairFund.max_contribution(RepairFund.first_open_target())
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
		"paid_before": paid_before, "paid_after": RepairFund.paid() })
	for id in RepairFund.repaired_ids():
		if not fund_stage_days.has(id):
			fund_stage_days[id] = GameState.day_count


## 刻み1つぶんを、押せるなら押す（DebugPanel の操作経路）。積んだ額を返す。
func push_fund(step: int) -> int:
	if not RepairFund.can_contribute(RepairFund.first_open_target(), step):
		return 0
	var before := GameState.money
	act("fund")
	panel._on_fund_contribute_pressed(step)
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


## ニュース／共通イベントの表示専用 TEXT か（type が TEXT で、part が news または common_event）。
func is_display_only(ev) -> bool:
	return ev is Dictionary and str(ev.get("type", "")) == "TEXT" \
			and ["news", "common_event"].has(str(ev.get("part", "")))


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
		while GameState.dashi_units < 2 and GameState.money >= 16:
			buy("meat_wholesale", "dashi")
	var need: Dictionary = (Forecast.cases().back() as Dictionary)["required"]
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
				for good in panel._shop_goods(shop_id):
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
			if best.is_empty() or GameState.money < int(best.price):
				break
			buy(str(best.shop), str(best.id))
	if policy in ["forecast_favorites", "favorite_oracle"]:
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
	if panel._market_shop != "":
		act("shop_exit")
		panel._on_shop_exit_pressed()


func ensure(id: String, target: int) -> void:
	while GameState.fresh_count(id) < target:
		var choices: Array = []
		for shop_id in SHOPS:
			for good in panel._shop_goods(shop_id):
				if str(good.get("item", "")) == id:
					var short := target - GameState.fresh_count(id)
					var units := int(good.get("count", 1))
					choices.append({ "shop": shop_id, "good": good,
						"score": ceili(float(short) / units) * int(good.price) })
		choices.sort_custom(func(a, b): return a.score < b.score)
		if choices.is_empty() or GameState.money < int(choices[0].good.price):
			return
		buy(str(choices[0].shop), str(choices[0].good.id))


func buy(shop_id: String, id: String) -> void:
	if panel._market_shop != shop_id:
		if panel._market_shop != "":
			act("shop_exit")
			panel._on_shop_exit_pressed()
		act("shop_enter")
		panel._on_market_stall_selected(shop_id)
	var before := GameState.money
	act("purchase")
	panel._on_shop_item_selected(shop_id, id)
	purchases += before - GameState.money


func cook(order: Dictionary) -> void:
	if policy == "bare_broth":
		return
	var wanted: Array = (order.get("wanted_tags", []) as Array).duplicate()
	var n := int(order.get("servings", 1))
	var is_mob := bool(order.get("is_mob", false))
	if policy == "cheap_valid":
		wanted = cheap_wanted(n)
	if policy == "forecast_mistakes" and GameState.day_count in [3, 5] \
			and panel._open.slot_index == 0 and not is_mob:
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
			panel._on_ingredient_selected(id)
			added.append(id)
		elif id == "" and policy == "strength_neglect":
			# 鮮度のミス：新鮮な在庫が無ければ傷んだ在庫も使う（判定が1段階下がる）。
			var damaged_id := choose_damaged(str(tag), n)
			if damaged_id != "" and not added.has(damaged_id):
				act("ingredient_damaged")
				panel._on_ingredient_selected(damaged_id, true)
				added.append(damaged_id)
	var customer := str(order.get("customer", ""))
	if policy == "forecast_favorites" and GameState.knows_favorite(customer):
		add_favorite(order, added, n)
	elif policy == "favorite_oracle" and not is_mob:
		add_favorite(order, added, n)


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
		panel._on_ingredient_selected(favorite)


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
	if panel._btn_pot.disabled:
		return false
	var n: int = int(panel._react_for_now().get("servings", 1))
	var v := int(GameState.soup.remaining_servings)
	var s := int(GameState.soup.strength)
	if v >= n:
		if policy == "bare_broth":
			return false
		if policy == "strength_neglect" and s >= 1:
			return false
		if s >= 2 and s <= 4:
			return false
	act("pot_open")
	panel._on_pot_pressed()
	var changed := false
	for attempt in range(6):
		v = int(GameState.soup.remaining_servings)
		s = int(GameState.soup.strength)
		var need_water := (v < n or s >= 5) and GameState.water_reachable()
		if s < 2 and GameState.can_add_dashi() and not panel._pot_locked_until_water():
			act("dashi")
			panel._on_add_dashi_pressed()
			changed = true
		elif need_water and GameState.can_add_water():
			# 水で濃さが1以下になるなら、先にだしで濃さを上げておく。
			if s - GameState.WATER_STRENGTH_DELTA < 2 and GameState.can_add_dashi() \
					and s + GameState.DASHI_STRENGTH_DELTA <= GameState.STRENGTH_MAX:
				act("dashi")
				panel._on_add_dashi_pressed()
				changed = true
			else:
				act("water")
				panel._on_add_water_pressed()
				changed = true
		else:
			break
	var locked: bool = (panel._pot_locked_until_water() and GameState.can_add_water()) \
		or (panel._pot_locked_until_dashi() and GameState.can_add_dashi())
	if not locked:
		act("pot_back")
		panel._on_pot_back_pressed()
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
	var quality: float = panel._quality_score(panel._log_quality_counts, panel._log_judged_planned_cups)
	return { "day": GameState.day_count, "cash": GameState.money, "open_rep": GameState.reputation,
		"next_rep": roundi(GameState.reputation * 0.7 + quality * 0.3), "quality": quality,
		"demand": panel._log_planned_cups, "judged_demand": panel._log_judged_planned_cups,
		"served": served, "unserved": panel._log_planned_cups - served, "declined_records": declined,
		"regular_cups": reg_cups, "regular_good_plus": reg_good_plus, "regular_great": reg_great,
		"sales": sale, "grades": panel._log_quality_counts.duplicate(),
		"spoiled_value": panel._spoiled_value(panel._log_spoiled_items),
		"water": panel._log_water_used, "dashi": panel._log_dashi_used,
		"soup_left": GameState.soup.get("remaining_servings", 0),
		"stock": GameState.inventory.duplicate(), "actions_cumulative": clicks,
		"spend": Ledger.spend_by_category_today(), "closed_early": panel._log_closed_early }
